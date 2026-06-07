#import "MacControlSupport.hpp"
#import "SubprocessRunner.hpp"

#import <CommonCrypto/CommonDigest.h>

#include "domain/control/ControlPermission.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fnmatch.h>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "domain/control/ControlRuntimeLimits.hpp"

const NSUInteger kMaxRequestBytes = dietcode::domain::control::kMaxRequestBytes;
const NSUInteger kMaxResponseBytes = dietcode::domain::control::kMaxResponseBytes;
const NSInteger kMaxGrepResults = dietcode::domain::control::kMaxGrepResults;
const NSUInteger kMaxFileTextBytes = dietcode::domain::control::kMaxFileTextBytes;
const NSUInteger kMaxPatchBytesBeforeConfirmation = dietcode::domain::control::kMaxPatchBytesBeforeConfirmation;
const NSUInteger kMaxPatchBytes = dietcode::domain::control::kMaxPatchBytes;
const NSInteger kMaxBatchPatchCount = dietcode::domain::control::kMaxBatchPatchCount;
const NSUInteger kMaxChunkPreviewLength = dietcode::domain::control::kMaxChunkPreviewLength;
const NSInteger kMaxSearchDepth = dietcode::domain::control::kMaxSearchDepth;
const NSInteger kMaxSearchScanFiles = dietcode::domain::control::kMaxSearchScanFiles;
const NSUInteger kMaxSearchFileBytes = dietcode::domain::control::kMaxSearchFileBytes;
const NSInteger kMaxPlanSteps = dietcode::domain::control::kMaxPlanSteps;
const NSInteger kMaxActiveCombos = dietcode::domain::control::kMaxActiveCombos;
NSString* const kDietCodeAppVersion = @"1.6.5";
NSString* const kDietCodeTerminalOutputDidUpdateNotification = @"kDietCodeTerminalOutputDidUpdateNotification";

NSString* NSStringFromStdString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string StdStringFromNSString(NSString* value) {
    if (value == nil) {
        return {};
    }
    return std::string([value UTF8String]);
}

NSArray<NSString*>* LinesFromText(NSString* text) {
    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    [text enumerateLinesUsingBlock:^(NSString* line, BOOL*) {
        [lines addObject:line ?: @""];
    }];
    if (text.length > 0 && [text hasSuffix:@"\n"]) {
        [lines addObject:@""];
    }
    return lines;
}

std::string LowerASCII(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return (char)std::tolower(c);
    });
    return value;
}

NSArray<NSDictionary*>* LiteralMatchSpans(const std::string& line, const std::string& query, BOOL caseSensitive) {
    NSMutableArray* spans = [NSMutableArray array];
    if (query.empty()) return spans;
    std::string haystack = caseSensitive ? line : LowerASCII(line);
    std::string needle = caseSensitive ? query : LowerASCII(query);
    size_t pos = 0;
    while ((pos = haystack.find(needle, pos)) != std::string::npos) {
        [spans addObject:@{
            @"columnStart": @(pos + 1),
            @"columnEnd": @(pos + needle.size()),
            @"text": NSStringFromStdString(line.substr(pos, needle.size()))
        }];
        pos += std::max<size_t>(needle.size(), 1);
    }
    return spans;
}

NSString* TextForLineRange(NSArray<NSString*>* lines, NSInteger startLine, NSInteger endLine) {
    if (startLine < 1 || endLine < startLine || endLine > (NSInteger)lines.count) {
        return nil;
    }
    NSMutableArray<NSString*>* selected = [NSMutableArray array];
    for (NSInteger i = startLine; i <= endLine; i++) {
        [selected addObject:lines[(NSUInteger)i - 1]];
    }
    return [selected componentsJoinedByString:@"\n"];
}

NSDictionary* TextChunkResponse(NSString* text, NSInteger offset, NSInteger maxBytes) {
    NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSInteger totalBytes = (NSInteger)data.length;
    NSInteger safeOffset = MAX(0, MIN(offset, totalBytes));
    NSInteger safeMax = maxBytes > 0 ? MIN(maxBytes, (NSInteger)kMaxResponseBytes / 2) : 64 * 1024;
    NSInteger end = MIN(totalBytes, safeOffset + safeMax);
    NSRange range = NSMakeRange((NSUInteger)safeOffset, (NSUInteger)(end - safeOffset));
    NSData* chunkData = [data subdataWithRange:range];
    NSString* chunk = [[NSString alloc] initWithData:chunkData encoding:NSUTF8StringEncoding];
    while (!chunk && range.length > 0) {
        range.length--;
        chunkData = [data subdataWithRange:range];
        chunk = [[NSString alloc] initWithData:chunkData encoding:NSUTF8StringEncoding];
        end = safeOffset + (NSInteger)range.length;
    }
    if (!chunk) chunk = @"";

    NSString* prefix = @"";
    if (safeOffset > 0) {
        NSData* prefixData = [data subdataWithRange:NSMakeRange(0, (NSUInteger)safeOffset)];
        prefix = [[NSString alloc] initWithData:prefixData encoding:NSUTF8StringEncoding] ?: @"";
    }
    NSInteger lineStart = [[prefix componentsSeparatedByString:@"\n"] count];
    NSInteger lineEnd = lineStart + MAX(0, (NSInteger)[[chunk componentsSeparatedByString:@"\n"] count] - 1);

    return @{
        @"chunk": chunk,
        @"offset": @(safeOffset),
        @"nextOffset": @(end),
        @"totalBytes": @(totalBytes),
        @"hasMore": @(end < totalBytes),
        @"lineStart": @(lineStart),
        @"lineEnd": @(lineEnd),
        @"sha256": StableHashForString(text ?: @""),
        @"chunkSha256": StableHashForString(chunk ?: @"")
    };
}

BOOL FileIsWithinSearchReadCap(const std::filesystem::path& path) {
    std::error_code sizeEc;
    auto size = std::filesystem::file_size(path, sizeEc);
    return sizeEc || size <= kMaxSearchFileBytes;
}

NSString* WordAtOffset(NSString* text, NSInteger offset) {
    if (text.length == 0) return @"";
    NSUInteger idx = (NSUInteger)MAX(0, MIN(offset, (NSInteger)text.length - 1));
    NSCharacterSet* wordSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if (![wordSet characterIsMember:[text characterAtIndex:idx]] && idx > 0) {
        idx--;
    }
    if (![wordSet characterIsMember:[text characterAtIndex:idx]]) {
        return @"";
    }
    NSUInteger start = idx;
    while (start > 0 && [wordSet characterIsMember:[text characterAtIndex:start - 1]]) {
        start--;
    }
    NSUInteger end = idx;
    while (end + 1 < text.length && [wordSet characterIsMember:[text characterAtIndex:end + 1]]) {
        end++;
    }
    return [text substringWithRange:NSMakeRange(start, end - start + 1)];
}

NSString* RunGitOutput(NSString* cwd, NSArray<NSString*>* args) {
    if (cwd.length == 0) return @"";
    std::vector<std::string> cppArgs;
    for (NSString* arg in args) {
        cppArgs.push_back([arg UTF8String]);
    }
    using namespace dietcode::platform::macos;
    SubprocessResult res = SubprocessRunner::run("/usr/bin/git", cppArgs, [cwd UTF8String], 10.0);
    return [NSString stringWithUTF8String:res.stdOut.c_str()] ?: @"";
}

BOOL IsTextBinary(NSString* text) {
    if (text == nil) return NO;
    NSUInteger len = [text length];
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == 0) {
            return YES;
        }
    }
    return NO;
}

NSArray<NSString*>* DefaultVerifyCommands(void) {
    return @[@"make test", @"make app", @"git diff --check"];
}

NSArray<NSString*>* VerifyCommandsAllowlist(void) {
    NSArray* configured = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"AgentVerifyCommands"];
    if (configured.count == 0) {
        return DefaultVerifyCommands();
    }
    NSMutableArray* commands = [NSMutableArray array];
    for (NSString* command in configured) {
        if ([command isKindOfClass:[NSString class]] && command.length > 0) {
            [commands addObject:command];
        }
    }
    return commands.count > 0 ? commands : DefaultVerifyCommands();
}

BOOL VerifyCommandIsAllowed(NSString* command, NSArray<NSString*>* allowedCommands) {
    for (NSString* allowed in allowedCommands) {
        if ([command isEqualToString:allowed] || [command hasPrefix:[allowed stringByAppendingString:@" "]]) {
            return YES;
        }
    }
    return NO;
}

NSDictionary* RuntimeError(NSString* code, NSString* message, NSString* stepId, NSString* chip, NSString* phase, BOOL recoverable) {
    NSMutableDictionary* err = [@{
        @"code": code ?: @"internal_error",
        @"message": message ?: @"",
        @"recoverable": @(recoverable)
    } mutableCopy];
    if (stepId.length > 0) err[@"stepId"] = stepId;
    if (chip.length > 0) err[@"chip"] = chip;
    if (phase.length > 0) err[@"phase"] = phase;
    return err;
}

NSInteger PermissionRank(NSString* permission) {
    return dietcode::domain::control::permissionRankFromString(StdStringFromNSString(permission));
}

NSString* CanonicalChipName(NSString* chip) {
    if (chip.length == 0) return @"";
    NSRange at = [chip rangeOfString:@"@"];
    return at.location == NSNotFound ? chip : [chip substringToIndex:at.location];
}

NSArray<NSString*>* DirtyFilePathsFromTabs(NSArray* tabs) {
    NSMutableArray* paths = [NSMutableArray array];
    for (id tab in tabs) {
        BOOL dirty = [[tab valueForKey:@"dirty"] boolValue];
        NSString* path = [tab valueForKey:@"path"];
        if (dirty && path.length > 0) {
            [paths addObject:path];
        }
    }
    return paths;
}

NSDictionary* DiagnosticsSummaryFromProblems(NSArray<NSDictionary*>* problems) {
    NSInteger errors = 0;
    NSInteger warnings = 0;
    NSInteger infos = 0;
    NSMutableSet* files = [NSMutableSet set];

    for (NSDictionary* problem in problems) {
        NSString* severity = [problem[@"severity"] lowercaseString] ?: @"info";
        if ([severity isEqualToString:@"error"]) errors++;
        else if ([severity isEqualToString:@"warning"] || [severity isEqualToString:@"warn"]) warnings++;
        else infos++;

        NSString* path = problem[@"path"];
        if (path.length > 0) {
            [files addObject:path];
        }
    }

    return @{
        @"errors": @(errors),
        @"warnings": @(warnings),
        @"infos": @(infos),
        @"files": @([files count]),
        @"total": @(problems.count)
    };
}

NSArray<NSDictionary*>* ClusterDiagnostics(NSArray<NSDictionary*>* problems) {
    NSMutableDictionary<NSString*, NSMutableDictionary*>* clusters = [NSMutableDictionary dictionary];

    for (NSDictionary* problem in problems) {
        NSString* path = problem[@"path"] ?: @"";
        NSMutableDictionary* cluster = clusters[path];
        if (!cluster) {
            cluster = [@{
                @"path": path,
                @"errors": @0,
                @"warnings": @0,
                @"infos": @0,
                @"problems": [NSMutableArray array]
            } mutableCopy];
            clusters[path] = cluster;
        }

        NSString* severity = [problem[@"severity"] lowercaseString] ?: @"info";
        if ([severity isEqualToString:@"error"]) {
            cluster[@"errors"] = @([cluster[@"errors"] integerValue] + 1);
        } else if ([severity isEqualToString:@"warning"] || [severity isEqualToString:@"warn"]) {
            cluster[@"warnings"] = @([cluster[@"warnings"] integerValue] + 1);
        } else {
            cluster[@"infos"] = @([cluster[@"infos"] integerValue] + 1);
        }
        [cluster[@"problems"] addObject:problem];
    }

    NSMutableArray* result = [[clusters allValues] mutableCopy];
    [result sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        NSInteger scoreA = [a[@"errors"] integerValue] * 100 + [a[@"warnings"] integerValue] * 10 + [a[@"infos"] integerValue];
        NSInteger scoreB = [b[@"errors"] integerValue] * 100 + [b[@"warnings"] integerValue] * 10 + [b[@"infos"] integerValue];
        if (scoreA == scoreB) {
            return [a[@"path"] compare:b[@"path"]];
        }
        return scoreA > scoreB ? NSOrderedAscending : NSOrderedDescending;
    }];
    return result;
}

NSArray<NSString*>* ContextLines(const std::vector<std::string>& lines, NSInteger start, NSInteger end) {
    NSMutableArray* context = [NSMutableArray array];
    if (lines.empty()) return context;
    start = MAX(start, 0);
    end = MIN(end, (NSInteger)lines.size() - 1);
    for (NSInteger i = start; i <= end; i++) {
        [context addObject:NSStringFromStdString(lines[(size_t)i])];
    }
    return context;
}
