#import "MacControlServer.hpp"
#import "MacWindow.hpp"
#import <CommonCrypto/CommonDigest.h>
#import "SymbolIndexService.hpp"
#import "DiffAnalysisService.hpp"
#import "WorkspaceAnalysisService.hpp"
#import "BufferStateService.hpp"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fnmatch.h>
#include <fstream>
#include <sstream>
#include <chrono>
#include <filesystem>
#include <vector>
#include <string>
#include <set>
#include <map>
#include <iomanip>

namespace {
static const NSUInteger kMaxRequestBytes = 1024 * 1024;
static const NSUInteger kMaxResponseBytes = 4 * 1024 * 1024;
static const NSInteger kMaxGrepResults = 500;
static const NSUInteger kMaxFileTextBytes = 1024 * 1024;
static const NSUInteger kMaxPatchBytesBeforeConfirmation = 10 * 1024;
static const NSUInteger kMaxPatchBytes = 1024 * 1024;
static const NSInteger kMaxBatchPatchCount = 10;
static const NSUInteger kMaxChunkPreviewLength = 180;
static const NSInteger kMaxPlanSteps = 30;
static const NSInteger kMaxActiveCombos = 4;

NSString* NSStringFromStdString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string StdStringFromNSString(NSString* value) {
    if (value == nil) {
        return {};
    }
    return std::string([value UTF8String]);
}

NSString* AbsolutePathForRPCPath(NSString* path, NSString* workspace) {
    if (path.length == 0) return path;
    if ([path isAbsolutePath] || workspace.length == 0) return path;
    return [workspace stringByAppendingPathComponent:path];
}

BOOL PathIsInsideWorkspace(NSString* path, NSString* workspace) {
    if (path.length == 0 || workspace.length == 0) return NO;
    std::error_code ec;
    std::filesystem::path p(StdStringFromNSString(path));
    std::filesystem::path ws = std::filesystem::canonical(std::filesystem::path(StdStringFromNSString(workspace)), ec);
    if (ec) return NO;
    
    std::filesystem::path resolvedPath;
    if (std::filesystem::exists(p)) {
        resolvedPath = std::filesystem::canonical(p, ec);
        if (ec) return NO;
    } else {
        std::filesystem::path parent = p.parent_path();
        if (parent.empty()) {
            parent = ".";
        }
        std::filesystem::path parentCanonical = std::filesystem::weakly_canonical(parent, ec);
        if (ec) return NO;
        resolvedPath = parentCanonical / p.filename();
    }
    
    // Explicitly reject if resolved path is a symlink pointing outside
    if (std::filesystem::is_symlink(resolvedPath, ec)) {
        std::filesystem::path target = std::filesystem::read_symlink(resolvedPath, ec);
        if (!ec) {
            std::filesystem::path targetCanonical = std::filesystem::canonical(target, ec);
            if (!ec) {
                auto rel = std::filesystem::relative(targetCanonical, ws, ec);
                if (ec || rel.string().rfind("..", 0) == 0 || rel.is_absolute()) {
                    return NO;
                }
            }
        }
    }
    
    auto rel = std::filesystem::relative(resolvedPath, ws, ec);
    if (ec) return NO;
    std::string relStr = rel.string();
    return relStr == "." || (relStr.rfind("..", 0) != 0 && !rel.is_absolute());
}

NSArray<NSDictionary*>* HunkSummariesFromPatch(NSString* patch) {
    NSMutableArray* hunks = [NSMutableArray array];
    NSError* regErr = nil;
    NSRegularExpression* hunkRegex = [NSRegularExpression regularExpressionWithPattern:@"^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@" options:0 error:&regErr];
    NSArray<NSString*>* lines = [patch componentsSeparatedByString:@"\n"];
    NSMutableDictionary* current = nil;
    NSInteger added = 0;
    NSInteger removed = 0;

    for (NSString* line in lines) {
        NSTextCheckingResult* match = [hunkRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            if (current) {
                current[@"addedLines"] = @(added);
                current[@"removedLines"] = @(removed);
                [hunks addObject:current];
            }
            NSString* oldStart = [line substringWithRange:[match rangeAtIndex:1]];
            NSString* oldCount = [match rangeAtIndex:2].location == NSNotFound ? @"" : [line substringWithRange:[match rangeAtIndex:2]];
            NSString* newStart = [line substringWithRange:[match rangeAtIndex:3]];
            NSString* newCount = [match rangeAtIndex:4].location == NSNotFound ? @"" : [line substringWithRange:[match rangeAtIndex:4]];
            current = [@{
                @"oldStart": @([oldStart integerValue]),
                @"oldLines": @(oldCount.length > 0 ? [oldCount integerValue] : 1),
                @"newStart": @([newStart integerValue]),
                @"newLines": @(newCount.length > 0 ? [newCount integerValue] : 1),
                @"header": line
            } mutableCopy];
            added = 0;
            removed = 0;
        } else if (current) {
            if ([line hasPrefix:@"+"] && ![line hasPrefix:@"+++"]) added++;
            else if ([line hasPrefix:@"-"] && ![line hasPrefix:@"---"]) removed++;
        }
    }

    if (current) {
        current[@"addedLines"] = @(added);
        current[@"removedLines"] = @(removed);
        [hunks addObject:current];
    }
    return hunks;
}

NSArray<NSNumber*>* ModifiedNewLinesFromPatch(NSString* patch) {
    NSMutableArray<NSNumber*>* linesOut = [NSMutableArray array];
    NSError* regErr = nil;
    NSRegularExpression* hunkRegex = [NSRegularExpression regularExpressionWithPattern:@"^@@ -(\\d+),?(\\d*) \\+(\\d+),?(\\d*) @@" options:0 error:&regErr];
    NSInteger currentNewLine = 0;
    for (NSString* line in [patch componentsSeparatedByString:@"\n"]) {
        NSTextCheckingResult* match = [hunkRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            currentNewLine = [[line substringWithRange:[match rangeAtIndex:3]] integerValue];
            continue;
        }
        if (currentNewLine <= 0) continue;
        if ([line hasPrefix:@"+"] && ![line hasPrefix:@"+++"]) {
            [linesOut addObject:@(currentNewLine)];
            currentNewLine++;
        } else if ([line hasPrefix:@"-"] && ![line hasPrefix:@"---"]) {
            [linesOut addObject:@(currentNewLine)];
        } else if ([line hasPrefix:@" "]) {
            currentNewLine++;
        }
    }
    return linesOut;
}

NSArray<NSString*>* AffectedSymbolsForPatch(NSString* patch, NSArray<NSDictionary*>* symbols) {
    NSArray<NSNumber*>* modifiedLines = ModifiedNewLinesFromPatch(patch);
    NSMutableSet<NSString*>* names = [NSMutableSet set];
    for (NSDictionary* sym in symbols ?: @[]) {
        NSInteger startLine = [sym[@"line"] integerValue];
        NSInteger endLine = [sym[@"endLine"] integerValue];
        for (NSNumber* line in modifiedLines) {
            NSInteger value = [line integerValue];
            if (value >= startLine && value <= endLine && [sym[@"name"] length] > 0) {
                [names addObject:sym[@"name"]];
                break;
            }
        }
    }
    return [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

NSInteger ChangedLineCountFromHunks(NSArray<NSDictionary*>* hunks) {
    NSInteger count = 0;
    for (NSDictionary* hunk in hunks) {
        count += [hunk[@"addedLines"] integerValue] + [hunk[@"removedLines"] integerValue];
    }
    return count;
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

BOOL AnyPatternMatches(NSArray<NSString*>* patterns, const std::string& relPath, const std::string& filename) {
    for (NSString* pattern in patterns ?: @[]) {
        std::string pat = StdStringFromNSString(pattern);
        if (fnmatch(pat.c_str(), relPath.c_str(), FNM_CASEFOLD) == 0 ||
            fnmatch(pat.c_str(), filename.c_str(), FNM_CASEFOLD) == 0) {
            return YES;
        }
        std::filesystem::path p(relPath);
        for (const auto& part : p) {
            if (fnmatch(pat.c_str(), part.string().c_str(), FNM_CASEFOLD) == 0) {
                return YES;
            }
        }
    }
    return NO;
}

BOOL ShouldSkipSearchPath(const std::filesystem::path& path, const std::string& relPath, NSArray<NSString*>* includes, NSArray<NSString*>* excludes) {
    std::string filename = path.filename().string();
    NSArray* defaultExcludes = @[@".git", @"build", @"dist", @"node_modules", @"DerivedData", @".next", @"__pycache__"];
    if (AnyPatternMatches(defaultExcludes, relPath, filename) || AnyPatternMatches(excludes, relPath, filename)) {
        return YES;
    }
    if (includes.count > 0 && !AnyPatternMatches(includes, relPath, filename)) {
        return YES;
    }
    return NO;
}

NSString* RunGitOutput(NSString* cwd, NSArray<NSString*>* args) {
    if (cwd.length == 0) return @"";
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/git"];
    [task setArguments:args];
    [task setCurrentDirectoryPath:cwd];
    NSPipe* outPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:[NSPipe pipe]];
    @try {
        [task launch];
        [task waitUntilExit];
        NSData* data = [[outPipe fileHandleForReading] readDataToEndOfFile];
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    } @catch (NSException*) {
        return @"";
    }
}

NSString* ISODateString(NSDate* date) {
    if (!date) return @"";
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return [formatter stringFromDate:date];
}

NSString* StableHashForData(NSData* data) {
    if (!data) data = [NSData data];
    const uint8_t* bytes = (const uint8_t*)data.bytes;
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", hash];
}

NSString* StableHashForString(NSString* text) {
    NSData* data = [(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return StableHashForData(data);
}

NSString* SHA256ForData(NSData* data) {
    if (!data) data = [NSData data];
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString* s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [s appendFormat:@"%02x", hash[i]];
    }
    return s;
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
    if ([permission isEqualToString:@"read"] || [permission isEqualToString:@"Read"]) return 0;
    if ([permission isEqualToString:@"edit"] || [permission isEqualToString:@"Edit"]) return 1;
    if ([permission isEqualToString:@"execute"] || [permission isEqualToString:@"Execute"]) return 2;
    if ([permission isEqualToString:@"destructive"] || [permission isEqualToString:@"Destructive"]) return 3;
    if ([permission isEqualToString:@"external"] || [permission isEqualToString:@"External"]) return 4;
    return 0;
}

NSString* CanonicalChipName(NSString* chip) {
    if (chip.length == 0) return @"";
    NSRange at = [chip rangeOfString:@"@"];
    return at.location == NSNotFound ? chip : [chip substringToIndex:at.location];
}

NSDictionary* PatchPreviewSummary(NSString* patch) {
    NSArray<NSDictionary*>* hunks = HunkSummariesFromPatch(patch ?: @"");
    NSMutableArray* previews = [NSMutableArray array];
    for (NSDictionary* hunk in hunks) {
        NSInteger start = [hunk[@"newStart"] integerValue];
        NSInteger end = start + MAX([hunk[@"newLines"] integerValue] - 1, 0);
        [previews addObject:@{
            @"startLine": @(start),
            @"endLine": @(end),
            @"preview": hunk[@"header"] ?: @"",
            @"addedLines": hunk[@"addedLines"] ?: @0,
            @"removedLines": hunk[@"removedLines"] ?: @0
        }];
    }
    NSInteger added = 0;
    NSInteger removed = 0;
    for (NSDictionary* hunk in hunks) {
        added += [hunk[@"addedLines"] integerValue];
        removed += [hunk[@"removedLines"] integerValue];
    }
    return @{
        @"addedLines": @(added),
        @"removedLines": @(removed),
        @"changedLines": @(added + removed),
        @"hunks": previews
    };
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
}

@interface DietCodeControlServer ()

- (void)acceptLoop;
- (void)handleClient:(int)clientFd;
- (void)processRequest:(const std::string&)requestStr clientFd:(int)clientFd;
- (NSString*)permissionLevelForMethod:(NSString*)method params:(NSDictionary*)params;
- (void)executeMethod:(NSString*)method params:(NSDictionary*)params outResult:(NSDictionary**)outResult outErrCode:(NSString**)outErrCode outErrMsg:(NSString**)outErrMsg outPaths:(NSString**)outPaths;
- (void)sendError:(NSString*)reqId code:(id)code message:(NSString*)message clientFd:(int)clientFd;
- (void)sendSuccess:(NSString*)reqId result:(NSDictionary*)result clientFd:(int)clientFd;
- (void)logAuditMethod:(NSString*)method caller:(NSString*)caller permission:(NSString*)permission duration:(long long)duration result:(NSString*)result paths:(NSString*)paths;
- (NSArray<NSDictionary*>*)rpcMethodDescriptions;
- (NSDictionary*)descriptionForRPCMethod:(NSString*)method;
- (NSArray<NSDictionary*>*)chipRegistry;
- (NSDictionary*)metadataForChip:(NSString*)chip;
- (NSDictionary*)primitiveForChip:(NSString*)chip params:(NSDictionary*)params;
- (NSString*)chipNameForStep:(NSDictionary*)step;
- (NSDictionary*)paramsForComboStep:(NSDictionary*)step;
- (NSArray<NSString*>*)pathsDeclaredByParams:(NSDictionary*)params chip:(NSString*)chip;
- (BOOL)comboPolicy:(NSDictionary*)policy allowsPermission:(NSString*)permission;
- (BOOL)validateCombo:(NSDictionary*)combo normalizedPlan:(NSDictionary**)planOut errors:(NSArray<NSDictionary*>**)errorsOut;
- (NSDictionary*)serializableCombo:(NSMutableDictionary*)combo;
- (NSUInteger)activeComboCount;
- (NSArray<NSString*>*)mutationPathsForChip:(NSString*)chip params:(NSDictionary*)params;
- (BOOL)acquireMutationLocks:(NSArray<NSString*>*)paths comboId:(NSString*)comboId error:(NSString**)errorOut;
- (void)releaseMutationLocks:(NSArray<NSString*>*)paths comboId:(NSString*)comboId;
- (NSDictionary*)executeComboStep:(NSDictionary*)step combo:(NSMutableDictionary*)combo sequence:(NSInteger)sequence;
- (NSDictionary*)runComboWithPlan:(NSDictionary*)plan comboId:(NSString*)comboId;
- (BOOL)writeManifest:(NSDictionary*)manifest toPath:(NSString*)path error:(NSString**)errorOut;
- (NSDictionary*)loadManifestFromPath:(NSString*)path error:(NSString**)errorOut;
- (NSString*)canonicalJsonStringForObject:(id)obj error:(NSString**)errorOut;
- (BOOL)validateManifestStructure:(NSDictionary*)manifest error:(NSString**)errorOut;
- (NSDictionary*)validatePatchAtPath:(NSString*)path patch:(NSString*)patch currentText:(NSString*)currentTextOverride;
- (NSDictionary*)currentChangesInfo;
- (NSDictionary*)runVerificationCommand:(NSString*)command cwd:(NSString*)cwd;
- (NSDictionary*)verificationStatus;
- (NSDictionary*)contextSnapshotPayload;
- (NSArray<NSString*>*)verificationFailureLines;
- (void)recordLastRPCPatchPaths:(NSArray<NSDictionary*>*)records;
- (BOOL)restorePatchRecords:(NSArray<NSDictionary*>*)records error:(NSString**)errorOut;
- (BOOL)path:(NSString*)path isAllowedByScope:(NSDictionary*)scope;
- (BOOL)dirtyBufferExistsAtPath:(NSString*)path;
- (BOOL)task:(NSMutableDictionary*)task canConsumeStep:(NSDictionary*)step error:(NSString**)errorOut;
- (NSDictionary*)serializableTask:(NSMutableDictionary*)task;
- (NSDictionary*)primitiveForWorkbenchStep:(NSDictionary*)step;
- (NSDictionary*)executeWorkbenchStep:(NSDictionary*)step task:(NSMutableDictionary*)task;
- (NSDictionary*)repairContextForFailure:(NSString*)failure params:(NSDictionary*)params;

@end

@implementation DietCodeControlServer {
    int _serverFd;
    NSThread* _acceptThread;
    NSString* _lastVerifyCommand;
    NSDate* _lastVerifyStartedAt;
    NSDate* _lastVerifyFinishedAt;
    NSNumber* _lastVerifyExitCode;
    NSMutableArray<NSDictionary*>* _lastRPCPatchRecords;
    NSMutableDictionary<NSString*, NSDictionary*>* _contextSnapshots;
    NSInteger _contextSnapshotCounter;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* _tasks;
    NSInteger _taskCounter;
    NSMutableDictionary<NSString*, NSDictionary*>* _editPlans;
    NSInteger _editPlanCounter;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* _combos;
    NSInteger _comboCounter;
    NSMutableDictionary<NSString*, NSString*>* _pathLocks;
    NSString* _sessionToken;
    dispatch_queue_t _executionQueue;
    BOOL _globalMutationLock;
    NSDictionary* _lastVerifyStatus;
    NSString* _lastComboId;
}

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller {
    self = [super init];
    if (self) {
        _windowController = controller;
        _isRunning = NO;
        _serverFd = -1;
        _lastRPCPatchRecords = [NSMutableArray array];
        _contextSnapshots = [NSMutableDictionary dictionary];
        _contextSnapshotCounter = 0;
        _tasks = [NSMutableDictionary dictionary];
        _taskCounter = 0;
        _editPlans = [NSMutableDictionary dictionary];
        _editPlanCounter = 0;
        _combos = [NSMutableDictionary dictionary];
        _comboCounter = 0;
        _pathLocks = [NSMutableDictionary dictionary];
        _sessionToken = nil;
        _executionQueue = dispatch_queue_create("com.dietcode.runtime.execution", DISPATCH_QUEUE_SERIAL);
        _globalMutationLock = NO;
        _lastVerifyStatus = @{
            @"command": @"",
            @"state": @"idle",
            @"exitCode": [NSNull null],
            @"passed": @NO
        };
        _lastComboId = nil;
    }
    return self;
}

- (NSString*)safeWorkspacePath {
    if ([NSThread isMainThread]) {
        return [_windowController workspacePath];
    }
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController workspacePath];
    });
    return res;
}

- (NSString*)safeTextForFileAtPath:(NSString*)path {
    if ([NSThread isMainThread]) {
        return [_windowController textForFileAtPath:path];
    }
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController textForFileAtPath:path];
    });
    return res;
}

- (BOOL)safeReplaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path {
    if ([NSThread isMainThread]) {
        return [_windowController replaceTextInRange:range withText:text forFileAtPath:path];
    }
    __block BOOL res = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController replaceTextInRange:range withText:text forFileAtPath:path];
    });
    return res;
}

- (NSArray<NSString*>*)safeOpenFilePaths {
    if ([NSThread isMainThread]) {
        return [_windowController openFilePaths];
    }
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController openFilePaths];
    });
    return res;
}

- (NSArray<NSDictionary*>*)safeProblemsList {
    if ([NSThread isMainThread]) {
        return [_windowController problemsList];
    }
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController problemsList];
    });
    return res;
}

- (NSString*)safeActiveFilePath {
    if ([NSThread isMainThread]) {
        return [_windowController activeFilePath];
    }
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController activeFilePath];
    });
    return res;
}

- (NSArray*)safeOpenTabs {
    if ([NSThread isMainThread]) {
        return _windowController.openTabs;
    }
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = _windowController.openTabs;
    });
    return res;
}

- (NSDictionary*)safeGitStatusInfo {
    if ([NSThread isMainThread]) {
        return [_windowController gitStatusInfo];
    }
    __block NSDictionary* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController gitStatusInfo];
    });
    return res;
}

- (NSString*)safeGitDiffForFile:(NSString*)path {
    if ([NSThread isMainThread]) {
        return [_windowController gitDiffForFile:path];
    }
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_windowController gitDiffForFile:path];
    });
    return res;
}

- (void)start {
    if (_isRunning) return;
    
    NSString* homeDir = NSHomeDirectory();
    NSString* dcDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    
    // Create ~/.dietcode directory with 0700 permissions
    [[NSFileManager defaultManager] createDirectoryAtPath:dcDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0700)} ofItemAtPath:dcDir error:nil];
    
    // Generate session token
    NSString* token = [NSString stringWithFormat:@"%08x%08x%08x%08x", 
                       arc4random(), arc4random(), arc4random(), arc4random()];
    NSString* tokenPath = [dcDir stringByAppendingPathComponent:@"session.token"];
    [token writeToFile:tokenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:tokenPath error:nil];
    _sessionToken = [token copy];
    
    NSString* sockPathStr = [dcDir stringByAppendingPathComponent:@"control.sock"];
    const char* sockPath = [sockPathStr UTF8String];
    
    unlink(sockPath); // Delete stale socket if any
    
    _serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_serverFd < 0) {
        [self appendLogLine:@"[Error] Failed to create Unix socket."];
        return;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sockPath, sizeof(addr.sun_path) - 1);
    
    if (bind(_serverFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        [self appendLogLine:@"[Error] Failed to bind Unix socket."];
        close(_serverFd);
        _serverFd = -1;
        return;
    }
    
    chmod(sockPath, 0600); // Strict user-only permissions
    
    if (listen(_serverFd, 5) < 0) {
        [self appendLogLine:@"[Error] Failed to listen on socket."];
        close(_serverFd);
        _serverFd = -1;
        unlink(sockPath);
        return;
    }
    
    _isRunning = YES;
    [self appendLogLine:@"[System] External Control Server started. Listening on ~/.dietcode/control.sock"];
    
    _acceptThread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop) object:nil];
    [_acceptThread start];
}

- (void)stop {
    if (!_isRunning) return;
    _isRunning = NO;
    
    int fd = _serverFd;
    _serverFd = -1;
    if (fd >= 0) {
        close(fd);
    }
    
    NSString* sockPathStr = [[NSHomeDirectory() stringByAppendingPathComponent:@".dietcode"] stringByAppendingPathComponent:@"control.sock"];
    unlink([sockPathStr UTF8String]);
    
    [self appendLogLine:@"[System] External Control Server stopped."];
    [_windowController setControlActiveCommand:nil caller:nil];
}

- (void)acceptLoop {
    while (_isRunning && _serverFd >= 0) {
        struct sockaddr_un clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientFd = accept(_serverFd, (struct sockaddr*)&clientAddr, &clientLen);
        if (clientFd < 0) {
            if (!_isRunning) break;
            usleep(100000); // 100ms backoff on error
            continue;
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientFd];
        });
    }
}

- (void)handleClient:(int)clientFd {
    std::string buffer;
    char readBuf[4096];
    
    while (_isRunning) {
        ssize_t bytes = read(clientFd, readBuf, sizeof(readBuf));
        if (bytes <= 0) break;
        
        buffer.append(readBuf, bytes);
        if (buffer.size() > kMaxRequestBytes) {
            [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
            buffer.clear();
            break;
        }
        
        size_t newlinePos;
        while ((newlinePos = buffer.find('\n')) != std::string::npos) {
            std::string line = buffer.substr(0, newlinePos);
            buffer.erase(0, newlinePos + 1);
            
            if (line.empty()) continue;
            if (line.size() > kMaxRequestBytes) {
                [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
                continue;
            }
            dispatch_async(_executionQueue, ^{
                [self processRequest:line clientFd:clientFd];
            });
        }
    }
    close(clientFd);
}

- (void)processRequest:(const std::string&)requestStr clientFd:(int)clientFd {
    auto startTime = std::chrono::high_resolution_clock::now();
    if (requestStr.size() > kMaxRequestBytes) {
        [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
        [self logAuditMethod:@"invalid" caller:@"unknown" permission:@"none" duration:0 result:@"request_too_large" paths:@""];
        return;
    }
    
    NSData* reqData = [NSData dataWithBytes:requestStr.data() length:requestStr.size()];
    NSError* jsonErr = nil;
    NSDictionary* req = [NSJSONSerialization JSONObjectWithData:reqData options:0 error:&jsonErr];
    
    NSString* reqId = req[@"id"] ?: @"unknown";
    NSString* method = req[@"method"];
    NSDictionary* params = req[@"params"] ?: @{};
    
    if (jsonErr || !method) {
        [self sendError:reqId code:@"invalid_request" message:@"Malformed JSON or missing method." clientFd:clientFd];
        [self logAuditMethod:@"invalid" caller:@"unknown" permission:@"none" duration:0 result:@"failed" paths:@""];
        return;
    }
    
    // Validate session token
    NSString* token = req[@"token"];
    if (!_sessionToken || ![token isEqualToString:_sessionToken]) {
        [self sendError:reqId code:@"permission_denied" message:@"Invalid or missing session token." clientFd:clientFd];
        [self logAuditMethod:method caller:@"unknown" permission:@"none" duration:0 result:@"auth_failed" paths:@""];
        return;
    }
    
    NSString* caller = @"unix_socket";
    NSString* permission = [self permissionLevelForMethod:method params:params];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_windowController setControlActiveCommand:method caller:caller];
    });
    
    __block BOOL allowed = YES;
    if ([permission isEqualToString:@"Destructive"]) {
        __block NSString* alertMsg = [NSString stringWithFormat:@"An external agent is requesting to execute a destructive command:\n\nMethod: %@\nParams: %@", method, params];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:@"External Control Confirmation"];
            [alert setInformativeText:alertMsg];
            [alert addButtonWithTitle:@"Allow"];
            [alert addButtonWithTitle:@"Deny"];
            NSModalResponse res = [alert runModal];
            allowed = (res == NSAlertFirstButtonReturn);
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    } else if ([permission isEqualToString:@"Execute"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([method hasPrefix:@"terminal"]) {
                [[self windowController] showBottomPanelTab:@"terminal"];
            } else if ([method hasPrefix:@"language.lint"]) {
                [[self windowController] showBottomPanelTab:@"errors"];
            }
        });
    }
    
    if (!allowed) {
        [self sendError:reqId code:@"permission_denied" message:@"User rejected the command execution." clientFd:clientFd];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_windowController setControlActiveCommand:nil caller:caller];
        });
        
        auto endTime = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
        [self logAuditMethod:method caller:caller permission:permission duration:duration result:@"rejected" paths:@""];
        [self appendLogLine:[NSString stringWithFormat:@"[%@] %@ -> Rejected (user denied)", caller, method]];
        return;
    }
    
    __block NSDictionary* result = nil;
    __block NSString* errCode = nil;
    __block NSString* errMsg = nil;
    __block NSString* affectedPaths = @"";
    
    // Check if the method runs on background serial queue or needs main thread
    BOOL isBackgroundMethod = [method isEqualToString:@"verify.run"] ||
                              [method isEqualToString:@"workspace.grep"] ||
                              [method isEqualToString:@"search.text"] ||
                              [method isEqualToString:@"search.files"] ||
                              [method isEqualToString:@"workspace.listFiles"] ||
                              [method isEqualToString:@"recovery.scan"] ||
                              [method isEqualToString:@"combo.run"];
    
    if (isBackgroundMethod) {
        [self executeMethod:method params:params outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&affectedPaths];
    } else {
        dispatch_semaphore_t execSem = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self executeMethod:method params:params outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&affectedPaths];
            dispatch_semaphore_signal(execSem);
        });
        dispatch_semaphore_wait(execSem, DISPATCH_TIME_FOREVER);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_windowController setControlActiveCommand:nil caller:caller];
    });
    
    auto endTime = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    
    if (errCode) {
        [self sendError:reqId code:errCode message:errMsg clientFd:clientFd];
        [self logAuditMethod:method caller:caller permission:permission duration:duration result:[NSString stringWithFormat:@"error: %@", errCode] paths:affectedPaths];
        [self appendLogLine:[NSString stringWithFormat:@"[%@] %@ -> Error (%@) in %lldms", caller, method, errMsg, duration]];
    } else {
        [self sendSuccess:reqId result:result clientFd:clientFd];
        [self logAuditMethod:method caller:caller permission:permission duration:duration result:@"success" paths:affectedPaths];
        [self appendLogLine:[NSString stringWithFormat:@"[%@] %@ -> Success in %lldms", caller, method, duration]];
    }
}

- (NSArray<NSDictionary*>*)rpcMethodDescriptions {
    static NSArray<NSDictionary*>* methods = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        methods = @[
            @{ @"name": @"rpc.ping", @"permission": @"Read", @"params": @{}, @"returns": @{ @"pong": @"boolean", @"server": @"string" } },
            @{ @"name": @"rpc.methods", @"permission": @"Read", @"params": @{}, @"returns": @{ @"methods": @"array" } },
            @{ @"name": @"rpc.describe", @"permission": @"Read", @"params": @{ @"method": @"string optional" }, @"returns": @{ @"methods": @"array" } },
            @{ @"name": @"chip.list", @"permission": @"Read", @"params": @{}, @"returns": @{ @"chips": @"array" } },
            @{ @"name": @"chip.describe", @"permission": @"Read", @"params": @{ @"chip": @"string" }, @"returns": @{ @"chip": @"object" } },
            @{ @"name": @"combo.validate", @"permission": @"Read", @"params": @{ @"combo": @"object" }, @"returns": @{ @"valid": @"boolean", @"errors": @"array", @"plan": @"object optional" } },
            @{ @"name": @"combo.run", @"permission": @"Edit/Execute", @"params": @{ @"combo": @"object" }, @"returns": @{ @"combo": @"object" } },
            @{ @"name": @"combo.status", @"permission": @"Read", @"params": @{ @"comboId": @"string" }, @"returns": @{ @"combo": @"object" } },
            @{ @"name": @"combo.result", @"permission": @"Read", @"params": @{ @"comboId": @"string" }, @"returns": @{ @"combo": @"object" } },
            @{ @"name": @"combo.cancel", @"permission": @"Read", @"params": @{ @"comboId": @"string" }, @"returns": @{ @"cancelled": @"boolean" } },
            @{ @"name": @"combo.rollback", @"permission": @"Edit", @"params": @{ @"comboId": @"string optional" }, @"returns": @{ @"reverted": @"boolean" } },
            @{ @"name": @"recovery.scan", @"permission": @"Read", @"params": @{}, @"returns": @{ @"backups": @"array" } },
            @{ @"name": @"workspace.getRoot", @"permission": @"Read", @"params": @{}, @"returns": @{ @"path": @"string" } },
            @{ @"name": @"workspace.openFolder", @"permission": @"Destructive", @"params": @{ @"path": @"directory path" }, @"returns": @{ @"opened": @"boolean" } },
            @{ @"name": @"workspace.listFiles", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"workspace.grep", @"permission": @"Read", @"params": @{ @"query": @"string", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"matches": @"array with contextBefore/contextAfter" } },
            @{ @"name": @"workspace.openFile", @"permission": @"Read", @"params": @{ @"path": @"string" }, @"returns": @{ @"opened": @"boolean" } },
            @{ @"name": @"workspace.getRecentFiles", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"search.files", @"permission": @"Read", @"params": @{ @"query": @"string", @"include": @"array optional", @"exclude": @"array optional", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"search.text", @"permission": @"Read", @"params": @{ @"query": @"string", @"before": @"number optional", @"after": @"number optional", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"search.todo", @"permission": @"Read", @"params": @{ @"include": @"array optional", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"search.diagnostics", @"permission": @"Read", @"params": @{ @"severity": @"string optional", @"source": @"string optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"file.read", @"permission": @"Read", @"params": @{ @"path": @"string" }, @"returns": @{ @"text": @"string" } },
            @{ @"name": @"file.readRange", @"permission": @"Read", @"params": @{ @"path": @"string", @"startLine": @"number", @"endLine": @"number" }, @"returns": @{ @"text": @"string" } },
            @{ @"name": @"file.readAround", @"permission": @"Read", @"params": @{ @"path": @"string", @"line": @"number", @"before": @"number optional", @"after": @"number optional" }, @"returns": @{ @"text": @"string" } },
            @{ @"name": @"file.getChunks", @"permission": @"Read", @"params": @{ @"path": @"string", @"chunkSize": @"number optional" }, @"returns": @{ @"chunks": @"array" } },
            @{ @"name": @"file.stat", @"permission": @"Read", @"params": @{ @"path": @"string" }, @"returns": @{ @"path": @"string", @"sizeBytes": @"number", @"lineCount": @"number" } },
            @{ @"name": @"editor.getActiveFile", @"permission": @"Read", @"params": @{}, @"returns": @{ @"path": @"string" } },
            @{ @"name": @"editor.getOpenFiles", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"editor.getText", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"text": @"string" } },
            @{ @"name": @"editor.getSelection", @"permission": @"Read", @"params": @{}, @"returns": @{ @"text": @"string", @"start": @"number", @"end": @"number" } },
            @{ @"name": @"editor.setSelection", @"permission": @"Edit", @"params": @{ @"start": @"number", @"end": @"number" }, @"returns": @{ @"success": @"boolean" } },
            @{ @"name": @"editor.insertText", @"permission": @"Edit", @"params": @{ @"text": @"string" }, @"returns": @{ @"inserted": @"boolean" } },
            @{ @"name": @"editor.replaceSelection", @"permission": @"Edit", @"params": @{ @"text": @"string" }, @"returns": @{ @"replaced": @"boolean" } },
            @{ @"name": @"editor.replaceRange", @"permission": @"Edit", @"params": @{ @"path": @"string optional", @"start": @"number", @"end": @"number", @"text": @"string" }, @"returns": @{ @"replaced": @"boolean" } },
            @{ @"name": @"editor.applyPatch", @"permission": @"Edit/Destructive", @"params": @{ @"path": @"string", @"patch": @"unified diff", @"confirm": @"boolean optional" }, @"returns": @{ @"patched": @"boolean", @"validation": @"object" } },
            @{ @"name": @"editor.saveFile", @"permission": @"Edit", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"saved": @"boolean" } },
            @{ @"name": @"editor.closeFile", @"permission": @"Edit", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"closed": @"boolean" } },
            @{ @"name": @"editor.goto", @"permission": @"Read", @"params": @{ @"path": @"string optional", @"line": @"number", @"column": @"number optional" }, @"returns": @{ @"navigated": @"boolean" } },
            @{ @"name": @"analysis.workspaceSummary", @"permission": @"Read", @"params": @{}, @"returns": @{ @"root": @"string", @"languages": @"object" } },
            @{ @"name": @"analysis.searchRanked", @"permission": @"Read", @"params": @{ @"query": @"string", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"analysis.fileSummary", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"path": @"string", @"symbolCount": @"number" } },
            @{ @"name": @"analysis.relatedFiles", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"symbols.document", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"symbols": @"array" } },
            @{ @"name": @"symbols.outline", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"symbols": @"array" } },
            @{ @"name": @"symbols.activeDocument", @"permission": @"Read", @"params": @{}, @"returns": @{ @"symbols": @"array" } },
            @{ @"name": @"symbols.references", @"permission": @"Read", @"params": @{ @"symbol": @"string" }, @"returns": @{ @"references": @"array" } },
            @{ @"name": @"symbols.atCursor", @"permission": @"Read", @"params": @{}, @"returns": @{ @"symbol": @"object" } },
            @{ @"name": @"diff.validatePatch", @"permission": @"Read", @"params": @{ @"path": @"string", @"patch": @"unified diff", @"currentText": @"string optional" }, @"returns": @{ @"ok": @"boolean", @"patchAppliesCleanly": @"boolean", @"requiresConfirmation": @"boolean" } },
            @{ @"name": @"diff.applyPatchPreview", @"permission": @"Read", @"params": @{ @"path": @"string", @"patch": @"unified diff" }, @"returns": @{ @"validation": @"object" } },
            @{ @"name": @"diff.workspaceInfo", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array", @"totalAdded": @"number", @"totalDeleted": @"number" } },
            @{ @"name": @"diff.stats", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array", @"totalAdded": @"number", @"totalDeleted": @"number" } },
            @{ @"name": @"diff.file", @"permission": @"Read", @"params": @{ @"path": @"string" }, @"returns": @{ @"diff": @"string" } },
            @{ @"name": @"diff.previewPatch", @"permission": @"Read", @"params": @{ @"path": @"string", @"patch": @"unified diff" }, @"returns": @{ @"ok": @"boolean", @"risk": @"string" } },
            @{ @"name": @"patch.validate", @"permission": @"Read", @"params": @{ @"path": @"string", @"patch": @"unified diff" }, @"returns": @{ @"applies": @"boolean", @"changedLines": @"number", @"hunks": @"number" } },
            @{ @"name": @"patch.preview", @"permission": @"Read", @"params": @{ @"path": @"string", @"patch": @"unified diff" }, @"returns": @{ @"addedLines": @"number", @"removedLines": @"number", @"hunks": @"array" } },
            @{ @"name": @"patch.apply", @"permission": @"Edit/Destructive", @"params": @{ @"path": @"string", @"patch": @"unified diff", @"confirm": @"boolean optional" }, @"returns": @{ @"patched": @"boolean" } },
            @{ @"name": @"patch.applyBatch", @"permission": @"Edit/Destructive", @"params": @{ @"patches": @"array", @"dryRun": @"boolean optional", @"confirm": @"boolean optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"patch.revertLast", @"permission": @"Edit", @"params": @{}, @"returns": @{ @"reverted": @"boolean" } },
            @{ @"name": @"diff.current", @"permission": @"Read", @"params": @{}, @"returns": @{ @"changes": @"object" } },
            @{ @"name": @"diff.staged", @"permission": @"Read", @"params": @{}, @"returns": @{ @"diff": @"string" } },
            @{ @"name": @"diff.unstaged", @"permission": @"Read", @"params": @{}, @"returns": @{ @"diff": @"string" } },
            @{ @"name": @"diff.summary", @"permission": @"Read", @"params": @{}, @"returns": @{ @"filesChanged": @"number", @"addedLines": @"number", @"removedLines": @"number" } },
            @{ @"name": @"buffers.snapshot", @"permission": @"Read", @"params": @{}, @"returns": @{ @"buffers": @"array" } },
            @{ @"name": @"buffers.dirty", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"buffers.active", @"permission": @"Read", @"params": @{}, @"returns": @{ @"path": @"string", @"selection": @"object" } },
            @{ @"name": @"buffers.unsavedDiff", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"diff": @"string" } },
            @{ @"name": @"changes.current", @"permission": @"Read", @"params": @{}, @"returns": @{ @"modifiedFiles": @"array", @"unsavedBuffers": @"array", @"stagedFiles": @"array", @"unstagedFiles": @"array" } },
            @{ @"name": @"changes.summary", @"permission": @"Read", @"params": @{}, @"returns": @{ @"summary": @"object" } },
            @{ @"name": @"changes.revertFile", @"permission": @"Destructive", @"params": @{ @"path": @"string" }, @"returns": @{ @"reverted": @"boolean" } },
            @{ @"name": @"verify.run", @"permission": @"Execute", @"params": @{ @"command": @"make test | make app | git diff --check" }, @"returns": @{ @"started": @"boolean" } },
            @{ @"name": @"verify.last", @"permission": @"Read", @"params": @{}, @"returns": @{ @"command": @"string", @"status": @"object" } },
            @{ @"name": @"verify.status", @"permission": @"Read", @"params": @{}, @"returns": @{ @"status": @"object" } },
            @{ @"name": @"verify.failures", @"permission": @"Read", @"params": @{}, @"returns": @{ @"failures": @"array", @"problems": @"array" } },
            @{ @"name": @"context.snapshot", @"permission": @"Read", @"params": @{}, @"returns": @{ @"snapshotId": @"string", @"snapshot": @"object" } },
            @{ @"name": @"context.delta", @"permission": @"Read", @"params": @{ @"snapshotId": @"string" }, @"returns": @{ @"changed": @"object" } },
            @{ @"name": @"task.start", @"permission": @"Read", @"params": @{ @"goal": @"string", @"scope": @"object", @"budget": @"object", @"verify": @"array optional" }, @"returns": @{ @"taskId": @"string", @"task": @"object" } },
            @{ @"name": @"task.status", @"permission": @"Read", @"params": @{ @"taskId": @"string" }, @"returns": @{ @"task": @"object" } },
            @{ @"name": @"task.step", @"permission": @"Edit/Execute", @"params": @{ @"taskId": @"string", @"step": @"object" }, @"returns": @{ @"stepResult": @"object" } },
            @{ @"name": @"task.runLoop", @"permission": @"Edit/Execute", @"params": @{ @"taskId": @"string", @"steps": @"array" }, @"returns": @{ @"results": @"array", @"finalDiff": @"object" } },
            @{ @"name": @"task.cancel", @"permission": @"Read", @"params": @{ @"taskId": @"string" }, @"returns": @{ @"cancelled": @"boolean" } },
            @{ @"name": @"task.result", @"permission": @"Read", @"params": @{ @"taskId": @"string" }, @"returns": @{ @"result": @"object" } },
            @{ @"name": @"edit.plan", @"permission": @"Read", @"params": @{ @"steps": @"array" }, @"returns": @{ @"planId": @"string", @"plan": @"object" } },
            @{ @"name": @"edit.executePlan", @"permission": @"Edit/Execute", @"params": @{ @"planId": @"string optional", @"steps": @"array optional", @"taskId": @"string optional" }, @"returns": @{ @"results": @"array" } },
            @{ @"name": @"repair.fromCompilerErrors", @"permission": @"Read", @"params": @{ @"files": @"array optional", @"diagnostics": @"array optional" }, @"returns": @{ @"failure": @"string", @"files": @"array" } },
            @{ @"name": @"repair.fromTestFailures", @"permission": @"Read", @"params": @{ @"files": @"array optional", @"diagnostics": @"array optional" }, @"returns": @{ @"failure": @"string", @"files": @"array" } },
            @{ @"name": @"repair.fromPatchFailure", @"permission": @"Read", @"params": @{ @"files": @"array optional", @"diagnostics": @"array optional" }, @"returns": @{ @"failure": @"string", @"files": @"array" } },
            @{ @"name": @"diagnostics.list", @"permission": @"Read", @"params": @{}, @"returns": @{ @"diagnostics": @"array with stable id" } },
            @{ @"name": @"diagnostics.summary", @"permission": @"Read", @"params": @{}, @"returns": @{ @"errors": @"number", @"warnings": @"number" } },
            @{ @"name": @"diagnostics.cluster", @"permission": @"Read", @"params": @{}, @"returns": @{ @"clusters": @"array" } },
            @{ @"name": @"diagnostics.forFile", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"diagnostics": @"array" } },
            @{ @"name": @"problems.list", @"permission": @"Read", @"params": @{}, @"returns": @{ @"problems": @"array with stable id" } },
            @{ @"name": @"problems.open", @"permission": @"Edit", @"params": @{ @"id": @"stable diagnostic id" }, @"returns": @{ @"opened": @"boolean" } },
            @{ @"name": @"problems.clearSource", @"permission": @"Edit", @"params": @{ @"source": @"string" }, @"returns": @{ @"cleared": @"boolean" } },
            @{ @"name": @"terminal.run", @"permission": @"Execute", @"params": @{ @"command": @"string", @"cwd": @"string optional", @"show": @"boolean optional" }, @"returns": @{ @"run": @"boolean" } },
            @{ @"name": @"terminal.stop", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"stopped": @"boolean" } },
            @{ @"name": @"terminal.getOutput", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"output": @"string" } },
            @{ @"name": @"terminal.clear", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"cleared": @"boolean" } },
            @{ @"name": @"terminal.status", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"pid": @"number", @"running": @"boolean" } },
            @{ @"name": @"terminal.jobs", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"jobs": @"array" } },
            @{ @"name": @"terminal.history", @"permission": @"Execute", @"params": @{}, @"returns": @{ @"commands": @"array" } },
            @{ @"name": @"git.status", @"permission": @"Read", @"params": @{}, @"returns": @{ @"branch": @"string", @"staged": @"array", @"modified": @"array", @"untracked": @"array" } },
            @{ @"name": @"git.diff", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"diff": @"string" } },
            @{ @"name": @"git.stage", @"permission": @"Edit", @"params": @{ @"path": @"string" }, @"returns": @{ @"staged": @"boolean" } },
            @{ @"name": @"git.unstage", @"permission": @"Edit", @"params": @{ @"path": @"string" }, @"returns": @{ @"unstaged": @"boolean" } },
            @{ @"name": @"git.discard", @"permission": @"Destructive", @"params": @{ @"path": @"string" }, @"returns": @{ @"discarded": @"boolean" } },
            @{ @"name": @"git.commit", @"permission": @"Destructive", @"params": @{ @"message": @"string" }, @"returns": @{ @"committed": @"boolean" } },
            @{ @"name": @"language.diagnostics", @"permission": @"Read", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"diagnostics": @"array" } },
            @{ @"name": @"language.format", @"permission": @"Execute", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"formatted": @"boolean" } },
            @{ @"name": @"language.lint", @"permission": @"Execute", @"params": @{ @"path": @"string optional" }, @"returns": @{ @"linted": @"boolean" } },
            @{ @"name": @"language.gotoDefinition", @"permission": @"Read", @"params": @{}, @"returns": @{ @"action_triggered": @"boolean" } },
            @{ @"name": @"session.info", @"permission": @"Read", @"params": @{}, @"returns": @{ @"workspace": @"string", @"activeFile": @"string" } },
            @{ @"name": @"session.workflowState", @"permission": @"Read", @"params": @{}, @"returns": @{ @"workspace": @"string", @"activeFile": @"string" } },
            @{ @"name": @"session.recentCommands", @"permission": @"Read", @"params": @{}, @"returns": @{ @"commands": @"array" } },
            @{ @"name": @"session.lastSearches", @"permission": @"Read", @"params": @{}, @"returns": @{ @"searches": @"array" } },
            @{ @"name": @"session.clearHistory", @"permission": @"Read", @"params": @{}, @"returns": @{ @"cleared": @"boolean" } }
        ];
    });
    return methods;
}

- (NSDictionary*)descriptionForRPCMethod:(NSString*)method {
    for (NSDictionary* desc in [self rpcMethodDescriptions]) {
        if ([desc[@"name"] isEqualToString:method]) {
            return desc;
        }
    }
    return @{};
}

- (NSArray<NSDictionary*>*)chipRegistry {
    static NSArray<NSDictionary*>* chips = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        chips = @[
            @{ @"name": @"file.readRange", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"path", @"startLine", @"endLine"] },
            @{ @"name": @"file.readAround", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"path", @"line"] },
            @{ @"name": @"file.getChunks", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"path"] },
            @{ @"name": @"search.files", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"query"] },
            @{ @"name": @"search.text", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"query"] },
            @{ @"name": @"search.todo", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"search.diagnostics", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @NO, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"patch.validate", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"path", @"patch"] },
            @{ @"name": @"patch.preview", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"path", @"patch"] },
            @{ @"name": @"patch.apply", @"version": @1, @"category": @"mutation", @"permission": @"edit", @"deterministic": @YES, @"idempotency": @"non_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @YES, @"runsProcess": @NO, @"usesTerminal": @NO, @"mayModifyBuffers": @YES }, @"rollback": @{ @"supported": @YES, @"kind": @"content_preimage", @"conflictPolicy": @"fail_closed" }, @"requiredParams": @[@"path", @"patch"] },
            @{ @"name": @"patch.applyBatch", @"version": @1, @"category": @"mutation", @"permission": @"edit", @"deterministic": @YES, @"idempotency": @"non_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @YES, @"runsProcess": @NO, @"usesTerminal": @NO, @"mayModifyBuffers": @YES }, @"rollback": @{ @"supported": @YES, @"kind": @"content_preimage", @"conflictPolicy": @"fail_closed" }, @"requiredParams": @[@"patches"] },
            @{ @"name": @"diff.summary", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"diff.current", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"verify.run", @"version": @1, @"category": @"execute", @"permission": @"execute", @"deterministic": @NO, @"idempotency": @"non_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @YES, @"runsProcess": @YES, @"usesTerminal": @YES }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[@"command"] },
            @{ @"name": @"verify.failures", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @NO, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"context.snapshot", @"version": @1, @"category": @"read", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"repair.fromCompilerErrors", @"version": @1, @"category": @"repair_context", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"repair.fromTestFailures", @"version": @1, @"category": @"repair_context", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] },
            @{ @"name": @"repair.fromPatchFailure", @"version": @1, @"category": @"repair_context", @"permission": @"read", @"deterministic": @YES, @"idempotency": @"conditionally_idempotent", @"sideEffects": @{ @"readsWorkspace": @YES, @"writesWorkspace": @NO, @"runsProcess": @NO, @"usesTerminal": @NO }, @"rollback": @{ @"supported": @NO }, @"requiredParams": @[] }
        ];
    });
    return chips;
}

- (NSDictionary*)metadataForChip:(NSString*)chip {
    NSString* canonical = CanonicalChipName(chip);
    for (NSDictionary* meta in [self chipRegistry]) {
        if ([meta[@"name"] isEqualToString:canonical]) return meta;
    }
    return nil;
}

- (NSDictionary*)primitiveForChip:(NSString*)chip params:(NSDictionary*)params {
    NSString* canonical = CanonicalChipName(chip);
    if (canonical.length == 0) return @{};
    return @{ @"method": canonical, @"params": params ?: @{} };
}

- (NSString*)chipNameForStep:(NSDictionary*)step {
    NSString* chip = step[@"chip"];
    if (chip.length > 0) return CanonicalChipName(chip);
    NSDictionary* primitive = [self primitiveForWorkbenchStep:step];
    return primitive[@"method"] ?: @"";
}

- (NSDictionary*)paramsForComboStep:(NSDictionary*)step {
    NSDictionary* params = step[@"params"];
    if ([params isKindOfClass:[NSDictionary class]]) return params;
    NSMutableDictionary* copy = [step mutableCopy];
    [copy removeObjectForKey:@"id"];
    [copy removeObjectForKey:@"chip"];
    [copy removeObjectForKey:@"type"];
    [copy removeObjectForKey:@"needs"];
    [copy removeObjectForKey:@"expects"];
    return copy;
}

- (NSArray<NSString*>*)pathsDeclaredByParams:(NSDictionary*)params chip:(NSString*)chip {
    NSMutableArray<NSString*>* paths = [NSMutableArray array];
    NSString* path = params[@"path"];
    if (path.length > 0) [paths addObject:path];
    NSString* cwd = params[@"cwd"];
    if (cwd.length > 0) [paths addObject:cwd];
    for (NSDictionary* item in params[@"patches"] ?: @[]) {
        NSString* patchPath = item[@"path"];
        if (patchPath.length > 0) [paths addObject:patchPath];
    }
    for (NSDictionary* file in params[@"files"] ?: @[]) {
        NSString* filePath = file[@"path"];
        if (filePath.length > 0) [paths addObject:filePath];
    }
    return paths;
}

- (BOOL)comboPolicy:(NSDictionary*)policy allowsPermission:(NSString*)permission {
    NSArray* permissions = policy[@"permissions"];
    if (![permissions isKindOfClass:[NSArray class]] || permissions.count == 0) {
        permissions = @[@"read"];
    }
    NSInteger needed = PermissionRank(permission);
    for (NSString* allowed in permissions) {
        if (PermissionRank(allowed) >= needed) return YES;
    }
    return NO;
}

- (BOOL)validateCombo:(NSDictionary*)combo normalizedPlan:(NSDictionary**)planOut errors:(NSArray<NSDictionary*>**)errorsOut {
    NSMutableArray<NSDictionary*>* errors = [NSMutableArray array];
    
    NSString* planVersion = combo[@"schemaVersion"];
    if (!planVersion || ![planVersion isEqualToString:@"1.6.2"]) {
        [errors addObject:RuntimeError(@"invalid_combo", @"Plan must declare schemaVersion '1.6.2'.", nil, nil, @"validate", YES)];
    }
    
    NSArray* steps = combo[@"steps"];
    NSDictionary* budget = combo[@"budget"] ?: @{};
    NSDictionary* policy = combo[@"policy"] ?: @{};
    NSDictionary* scope = combo[@"scope"] ?: @{};
    NSInteger maxSteps = budget[@"maxSteps"] ? [budget[@"maxSteps"] integerValue] : kMaxPlanSteps;
    maxSteps = MIN(maxSteps, kMaxPlanSteps);

    if (![steps isKindOfClass:[NSArray class]] || steps.count == 0 || steps.count > (NSUInteger)maxSteps) {
        [errors addObject:RuntimeError(@"invalid_combo", @"steps must be a non-empty bounded array.", nil, nil, @"validate", YES)];
    }

    NSMutableSet<NSString*>* stepIds = [NSMutableSet set];
    NSMutableArray* normalizedSteps = [NSMutableArray array];
    NSMutableSet<NSString*>* completedIds = [NSMutableSet set];
    NSUInteger index = 0;
    for (NSDictionary* step in steps ?: @[]) {
        if (![step isKindOfClass:[NSDictionary class]]) {
            [errors addObject:RuntimeError(@"invalid_combo", @"Every step must be an object.", nil, nil, @"validate", YES)];
            index++;
            continue;
        }
        NSString* stepId = step[@"id"] ?: [NSString stringWithFormat:@"step-%lu", (unsigned long)index + 1];
        if ([stepIds containsObject:stepId]) {
            [errors addObject:RuntimeError(@"invalid_combo", @"Duplicate step id.", stepId, nil, @"validate", YES)];
        }
        [stepIds addObject:stepId];

        NSString* chip = [self chipNameForStep:step];
        NSDictionary* meta = [self metadataForChip:chip];
        if (!meta) {
            [errors addObject:RuntimeError(@"unknown_chip", @"Step references an unknown chip.", stepId, chip, @"validate", YES)];
            index++;
            continue;
        }
        NSDictionary* params = [self paramsForComboStep:step];
        for (NSString* required in meta[@"requiredParams"] ?: @[]) {
            id value = params[required];
            if (!value || value == [NSNull null] || ([value respondsToSelector:@selector(length)] && [value length] == 0)) {
                [errors addObject:RuntimeError(@"invalid_params", [NSString stringWithFormat:@"Missing required parameter: %@", required], stepId, chip, @"validate", YES)];
            }
        }
        if (![self comboPolicy:policy allowsPermission:meta[@"permission"]]) {
            [errors addObject:RuntimeError(@"permission_denied", @"Combo policy does not allow this chip permission.", stepId, chip, @"validate", YES)];
        }
        if ([params[@"confirm"] boolValue]) {
            [errors addObject:RuntimeError(@"confirmation_required", @"Confirmation cannot be embedded inside combo steps.", stepId, chip, @"validate", YES)];
        }
        for (NSString* declaredPath in [self pathsDeclaredByParams:params chip:chip]) {
            if (![self path:declaredPath isAllowedByScope:scope]) {
                [errors addObject:RuntimeError(@"outside_scope", @"Step declares a path outside combo scope.", stepId, chip, @"validate", YES)];
            }
        }
        for (NSString* dep in step[@"needs"] ?: @[]) {
            if (![completedIds containsObject:dep]) {
                [errors addObject:RuntimeError(@"dependency_failed", @"Dependencies must reference earlier completed step ids in sequential combos.", stepId, chip, @"validate", YES)];
            }
        }
        if ([chip isEqualToString:@"patch.apply"] || [chip isEqualToString:@"patch.applyBatch"]) {
            NSArray* patchItems = [chip isEqualToString:@"patch.apply"] ? @[@{ @"path": params[@"path"] ?: @"", @"patch": params[@"patch"] ?: @"" }] : (params[@"patches"] ?: @[]);
            for (NSDictionary* item in patchItems) {
                if ([self dirtyBufferExistsAtPath:item[@"path"]] && ![params[@"allowDirtyBuffer"] boolValue]) {
                    [errors addObject:RuntimeError(@"dirty_buffer_conflict", @"Mutation targets a dirty editor buffer; set allowDirtyBuffer explicitly for buffer-domain patching.", stepId, chip, @"validate", YES)];
                }
                NSDictionary* validation = [self validatePatchAtPath:item[@"path"] patch:item[@"patch"] currentText:nil];
                if (![validation[@"ok"] boolValue]) {
                    [errors addObject:RuntimeError(@"patch_failed", validation[@"rejectedReason"] ?: @"Patch validation failed.", stepId, chip, @"validate", YES)];
                }
                if ([validation[@"requiresConfirmation"] boolValue]) {
                    [errors addObject:RuntimeError(@"confirmation_required", @"Patch exceeds combo confirmation threshold.", stepId, chip, @"validate", YES)];
                }
            }
        }
        [normalizedSteps addObject:@{ @"id": stepId, @"chip": chip, @"params": params, @"metadata": meta, @"needs": step[@"needs"] ?: @[] }];
        [completedIds addObject:stepId];
        index++;
    }

    if (errors.count > 0) {
        if (errorsOut) *errorsOut = errors;
        return NO;
    }
    if (planOut) {
        *planOut = @{
            @"schemaVersion": combo[@"schemaVersion"] ?: @"1.6.2",
            @"goal": combo[@"goal"] ?: @"",
            @"scope": scope,
            @"policy": policy,
            @"budget": budget,
            @"steps": normalizedSteps
        };
    }
    if (errorsOut) *errorsOut = @[];
    return YES;
}

- (NSDictionary*)serializableCombo:(NSMutableDictionary*)combo {
    NSMutableDictionary* copy = [combo mutableCopy];
    [copy removeObjectForKey:@"startedAtDate"];
    [copy removeObjectForKey:@"lockedPathsSet"];
    return copy;
}

- (NSUInteger)activeComboCount {
    NSUInteger count = 0;
    for (NSDictionary* combo in [_combos allValues]) {
        NSString* status = combo[@"status"] ?: @"";
        if ([status isEqualToString:@"running"] ||
            [status isEqualToString:@"validated"] ||
            [status isEqualToString:@"waiting_confirmation"]) {
            count++;
        }
    }
    return count;
}

- (NSArray<NSString*>*)mutationPathsForChip:(NSString*)chip params:(NSDictionary*)params {
    if ([chip isEqualToString:@"patch.apply"]) {
        NSString* path = params[@"path"];
        return path.length > 0 ? @[AbsolutePathForRPCPath(path, [_windowController workspacePath]) ?: path] : @[];
    }
    if ([chip isEqualToString:@"patch.applyBatch"]) {
        NSMutableArray* paths = [NSMutableArray array];
        for (NSDictionary* item in params[@"patches"] ?: @[]) {
            NSString* path = item[@"path"];
            if (path.length > 0) [paths addObject:AbsolutePathForRPCPath(path, [_windowController workspacePath]) ?: path];
        }
        return paths;
    }
    return @[];
}

- (BOOL)acquireMutationLocks:(NSArray<NSString*>*)paths comboId:(NSString*)comboId error:(NSString**)errorOut {
    for (NSString* path in paths ?: @[]) {
        NSString* holder = _pathLocks[path];
        if (holder.length > 0 && ![holder isEqualToString:comboId]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Path is locked by another combo: %@", path];
            return NO;
        }
    }
    for (NSString* path in paths ?: @[]) {
        _pathLocks[path] = comboId;
    }
    return YES;
}

- (void)releaseMutationLocks:(NSArray<NSString*>*)paths comboId:(NSString*)comboId {
    for (NSString* path in paths ?: @[]) {
        if ([_pathLocks[path] isEqualToString:comboId]) {
            [_pathLocks removeObjectForKey:path];
        }
    }
}

- (NSDictionary*)executeComboStep:(NSDictionary*)step combo:(NSMutableDictionary*)combo sequence:(NSInteger)sequence {
    NSString* comboId = combo[@"comboId"] ?: @"";
    NSString* stepId = step[@"id"] ?: @"";
    NSString* chip = step[@"chip"] ?: @"";
    NSDictionary* params = step[@"params"] ?: @{};
    NSDictionary* metadata = step[@"metadata"] ?: @{};
    NSDate* started = [NSDate date];
    NSMutableDictionary* trace = [@{
        @"sequence": @(sequence),
        @"stepId": stepId,
        @"chip": [NSString stringWithFormat:@"%@@%@", chip, metadata[@"version"] ?: @1],
        @"state": @"prechecking",
        @"phase": @"prechecking",
        @"startedAt": ISODateString(started),
        @"inputHash": StableHashForString([params description]),
        @"touchedPaths": [self mutationPathsForChip:chip params:params]
    } mutableCopy];

    if ([combo[@"status"] isEqualToString:@"cancelled"]) {
        trace[@"state"] = @"cancelled";
        trace[@"error"] = RuntimeError(@"cancelled", @"Combo was cancelled before step execution.", stepId, chip, @"prechecking", YES);
        return trace;
    }

    NSArray* mutationPaths = [self mutationPathsForChip:chip params:params];
    for (NSString* p in mutationPaths) {
        if (![_pathLocks[p] isEqualToString:comboId]) {
            trace[@"state"] = @"failed";
            trace[@"error"] = RuntimeError(@"lock_conflict", @"Required path lock not held by active combo.", stepId, chip, @"prechecking", YES);
            return trace;
        }
    }

    NSDictionary* primitive = [self primitiveForChip:chip params:params];
    NSString* method = primitive[@"method"];
    __block NSDictionary* result = nil;
    __block NSString* errCode = nil;
    __block NSString* errMsg = nil;
    __block NSString* affectedPaths = @"";

    trace[@"state"] = @"executing";
    trace[@"phase"] = @"executing";
    
    BOOL isBackground = [method isEqualToString:@"verify.run"] ||
                        [method isEqualToString:@"workspace.grep"] ||
                        [method isEqualToString:@"search.text"] ||
                        [method isEqualToString:@"search.files"] ||
                        [method isEqualToString:@"workspace.listFiles"] ||
                        [method isEqualToString:@"recovery.scan"];
                        
    if (isBackground) {
        [self executeMethod:method params:primitive[@"params"] ?: @{} outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&affectedPaths];
    } else {
        dispatch_semaphore_t execSem = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self executeMethod:method params:primitive[@"params"] ?: @{} outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&affectedPaths];
            dispatch_semaphore_signal(execSem);
        });
        dispatch_semaphore_wait(execSem, DISPATCH_TIME_FOREVER);
    }

    NSDate* finished = [NSDate date];
    trace[@"finishedAt"] = ISODateString(finished);
    trace[@"durationMs"] = @((NSInteger)([finished timeIntervalSinceDate:started] * 1000.0));
    if (affectedPaths.length > 0) trace[@"affectedPaths"] = affectedPaths;

    if (errCode) {
        trace[@"state"] = @"failed";
        trace[@"phase"] = @"failed";
        trace[@"error"] = RuntimeError(errCode, errMsg ?: @"Step failed.", stepId, chip, @"executing", YES);
        return trace;
    }

    trace[@"state"] = @"complete";
    trace[@"phase"] = @"postchecking";
    trace[@"outputHash"] = StableHashForString([result description]);
    trace[@"result"] = result ?: @{};
    return trace;
}

- (NSDictionary*)runComboWithPlan:(NSDictionary*)plan comboId:(NSString*)comboId {
    NSMutableDictionary* combo = [@{
        @"comboId": comboId,
        @"schemaVersion": plan[@"schemaVersion"] ?: @"1.6",
        @"goal": plan[@"goal"] ?: @"",
        @"status": @"running",
        @"createdAt": ISODateString([NSDate date]),
        @"startedAt": ISODateString([NSDate date]),
        @"plan": plan,
        @"trace": [NSMutableArray array],
        @"errors": [NSMutableArray array],
        @"budgetUsed": [@{ @"steps": @0, @"patchBatches": @0, @"verifyRuns": @0, @"filesTouched": @0, @"durationMs": @0 } mutableCopy]
    } mutableCopy];
    combo[@"startedAtDate"] = [NSDate date];
    combo[@"lockedPathsSet"] = [NSMutableSet set];
    _combos[comboId] = combo;
    _lastComboId = [comboId copy];

    // 1. Gather all mutation paths and determine if there are mutation chips
    BOOL containsMutation = NO;
    NSMutableArray* allMutationPaths = [NSMutableArray array];
    for (NSDictionary* step in plan[@"steps"] ?: @[]) {
        NSString* chip = step[@"chip"];
        if ([chip isEqualToString:@"patch.apply"] || [chip isEqualToString:@"patch.applyBatch"]) {
            containsMutation = YES;
        }
        NSArray* stepPaths = [self mutationPathsForChip:chip params:step[@"params"] ?: @{}];
        for (NSString* p in stepPaths) {
            if (![allMutationPaths containsObject:p]) {
                [allMutationPaths addObject:p];
            }
        }
    }

    // 2. Enforce global mutation lock
    if (containsMutation) {
        if (_globalMutationLock) {
            combo[@"status"] = @"failed";
            [combo[@"errors"] addObject:RuntimeError(@"lock_conflict", @"A mutation combo transaction is already in progress.", nil, nil, @"prechecking", YES)];
            combo[@"finishedAt"] = ISODateString([NSDate date]);
            return [self serializableCombo:combo];
        }
        _globalMutationLock = YES;
    }

    // 3. Acquire locks for ALL paths
    NSString* lockErr = nil;
    if (![self acquireMutationLocks:allMutationPaths comboId:comboId error:&lockErr]) {
        combo[@"status"] = @"failed";
        [combo[@"errors"] addObject:RuntimeError(@"lock_conflict", lockErr ?: @"Path lock conflict.", nil, nil, @"prechecking", YES)];
        if (containsMutation) _globalMutationLock = NO;
        combo[@"finishedAt"] = ISODateString([NSDate date]);
        return [self serializableCombo:combo];
    }

    // 4. Create Preimage Backup Checkpoint directory and records
    __block NSDictionary* manifest = nil;
    __block NSString* backupDirOut = nil;
    __block NSString* checkpointErr = nil;
    
    BOOL checkpointOk = [self createCheckpointForPaths:allMutationPaths comboId:comboId plan:plan manifestOut:&manifest backupDirOut:&backupDirOut error:&checkpointErr];
    if (!checkpointOk) {
        combo[@"status"] = @"failed";
        [combo[@"errors"] addObject:RuntimeError(@"checkpoint_write_failed", [NSString stringWithFormat:@"Failed to create checkpoint: %@", checkpointErr], nil, nil, @"prechecking", YES)];
        if (containsMutation) _globalMutationLock = NO;
        [self releaseMutationLocks:allMutationPaths comboId:comboId];
        combo[@"finishedAt"] = ISODateString([NSDate date]);
        return [self serializableCombo:combo];
    }

    NSInteger seq = 0;
    NSMutableSet* touched = [NSMutableSet set];
    NSDate* started = combo[@"startedAtDate"];
    NSDictionary* budget = plan[@"budget"] ?: @{};
    NSMutableDictionary* budgetUsed = combo[@"budgetUsed"];
    NSInteger maxVerifyRuns = budget[@"maxVerifyRuns"] ? [budget[@"maxVerifyRuns"] integerValue] : 3;
    NSInteger maxPatchBatches = budget[@"maxPatchBatches"] ? [budget[@"maxPatchBatches"] integerValue] : 3;
    NSInteger maxFilesTouched = budget[@"maxFilesTouched"] ? [budget[@"maxFilesTouched"] integerValue] : 4;
    NSInteger maxDurationMs = budget[@"maxDurationMs"] ? [budget[@"maxDurationMs"] integerValue] : 300000;

    BOOL executionFailed = NO;

    for (NSDictionary* step in plan[@"steps"] ?: @[]) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:started] * 1000.0;
        if (elapsed > maxDurationMs) {
            combo[@"status"] = @"expired";
            [combo[@"errors"] addObject:RuntimeError(@"timeout", @"Combo exceeded maxDurationMs.", step[@"id"], step[@"chip"], @"prechecking", YES)];
            executionFailed = YES;
            break;
        }

        NSString* chip = step[@"chip"] ?: @"";
        NSArray* mutationPaths = [self mutationPathsForChip:chip params:step[@"params"] ?: @{}];
        NSMutableSet* projectedTouched = [touched mutableCopy];
        for (NSString* path in mutationPaths) [projectedTouched addObject:path];
        if (projectedTouched.count > (NSUInteger)maxFilesTouched) {
            combo[@"status"] = @"failed";
            [combo[@"errors"] addObject:RuntimeError(@"budget_exceeded", @"Combo exceeded maxFilesTouched.", step[@"id"], chip, @"prechecking", YES)];
            executionFailed = YES;
            break;
        }
        if (([chip isEqualToString:@"patch.apply"] || [chip isEqualToString:@"patch.applyBatch"]) &&
            [budgetUsed[@"patchBatches"] integerValue] >= maxPatchBatches) {
            combo[@"status"] = @"failed";
            [combo[@"errors"] addObject:RuntimeError(@"budget_exceeded", @"Combo exceeded maxPatchBatches.", step[@"id"], chip, @"prechecking", YES)];
            executionFailed = YES;
            break;
        }
        if ([chip isEqualToString:@"verify.run"] && [budgetUsed[@"verifyRuns"] integerValue] >= maxVerifyRuns) {
            combo[@"status"] = @"failed";
            [combo[@"errors"] addObject:RuntimeError(@"budget_exceeded", @"Combo exceeded maxVerifyRuns.", step[@"id"], chip, @"prechecking", YES)];
            executionFailed = YES;
            break;
        }

        NSDictionary* trace = [self executeComboStep:step combo:combo sequence:++seq];
        [combo[@"trace"] addObject:trace];
        budgetUsed[@"steps"] = @([budgetUsed[@"steps"] integerValue] + 1);
        for (NSString* path in mutationPaths) [touched addObject:path];
        budgetUsed[@"filesTouched"] = @([touched count]);
        if ([chip isEqualToString:@"patch.apply"] || [chip isEqualToString:@"patch.applyBatch"]) {
            budgetUsed[@"patchBatches"] = @([budgetUsed[@"patchBatches"] integerValue] + 1);
        }
        if ([chip isEqualToString:@"verify.run"]) {
            budgetUsed[@"verifyRuns"] = @([budgetUsed[@"verifyRuns"] integerValue] + 1);
        }
        budgetUsed[@"durationMs"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:started] * 1000.0));
        if (![trace[@"state"] isEqualToString:@"complete"]) {
            combo[@"status"] = @"failed";
            if (trace[@"error"]) [combo[@"errors"] addObject:trace[@"error"]];
            executionFailed = YES;
            break;
        } else {
            NSString* ws = [_windowController workspacePath];
            NSMutableDictionary* mutableManifest = [manifest mutableCopy];
            NSMutableArray* updatedFiles = [NSMutableArray array];
            for (NSDictionary* fileEntry in manifest[@"files"] ?: @[]) {
                NSMutableDictionary* mutFile = [fileEntry mutableCopy];
                NSString* relPath = fileEntry[@"workspaceRelativePath"];
                NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
                if ([[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
                    NSString* currentText = [self safeTextForFileAtPath:absPath];
                    if (currentText) {
                        mutFile[@"expectedPostimageHash"] = StableHashForString(currentText);
                    }
                }
                [updatedFiles addObject:mutFile];
            }
            mutableManifest[@"files"] = updatedFiles;
            manifest = mutableManifest;
            
            NSString* manifestPath = [backupDirOut stringByAppendingPathComponent:@"manifest.json"];
            [self writeManifest:manifest toPath:manifestPath error:nil];
        }
    }

    // 5. If failed/expired/cancelled, trigger automatic rollback
    if (executionFailed || [combo[@"status"] isEqualToString:@"cancelled"]) {
        NSString* rollbackErr = nil;
        NSString* rollbackErrorCode = nil;
        BOOL rollbackOk = [self restorePatchFromManifest:manifest backupDir:backupDirOut confirm:YES error:&rollbackErr errorCode:&rollbackErrorCode];
        if (!rollbackOk) {
            [combo[@"errors"] addObject:RuntimeError(rollbackErrorCode ?: @"rollback_failed", [NSString stringWithFormat:@"Automatic rollback failed: %@", rollbackErr], nil, nil, @"rolling_back", NO)];
        } else {
            [combo[@"errors"] addObject:RuntimeError(@"rollback_success", @"Automatic rollback completed successfully.", nil, nil, @"rolling_back", YES)];
        }
    }

    if ([combo[@"status"] isEqualToString:@"running"]) {
        combo[@"status"] = @"complete";
    }

    // 6. Release all locks and global lock
    [self releaseMutationLocks:allMutationPaths comboId:comboId];
    if (containsMutation) {
        _globalMutationLock = NO;
    }

    combo[@"finishedAt"] = ISODateString([NSDate date]);
    combo[@"finalDiff"] = [self currentChangesInfo];
    combo[@"verify"] = [self verificationStatus];
    return [self serializableCombo:combo];
}


- (NSString*)canonicalJsonStringForObject:(id)obj error:(NSString**)errorOut {
    if ([obj isKindOfClass:[NSString class]]) {
        NSMutableString* s = [NSMutableString stringWithString:obj];
        [s replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, s.length)];
        [s replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, s.length)];
        [s replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, s.length)];
        [s replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, s.length)];
        [s replaceOccurrencesOfString:@"\t" withString:@"\\t" options:0 range:NSMakeRange(0, s.length)];
        return [NSString stringWithFormat:@"\"%@\"", s];
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        if (obj == (id)kCFBooleanTrue) {
            return @"true";
        } else if (obj == (id)kCFBooleanFalse) {
            return @"false";
        }
        const char* type = [obj objCType];
        if (type && (type[0] == 'c' || type[0] == 'B')) {
            return [obj boolValue] ? @"true" : @"false";
        }
        return [obj stringValue];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray* parts = [NSMutableArray array];
        for (id child in obj) {
            NSString* childJson = [self canonicalJsonStringForObject:child error:errorOut];
            if (!childJson) return nil;
            [parts addObject:childJson];
        }
        return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray* sortedKeys = [[obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray* parts = [NSMutableArray array];
        for (NSString* key in sortedKeys) {
            id val = obj[key];
            NSString* valJson = [self canonicalJsonStringForObject:val error:errorOut];
            if (!valJson) return nil;
            [parts addObject:[NSString stringWithFormat:@"\"%@\":%@", key, valJson]];
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
    } else if (obj == [NSNull null] || obj == nil) {
        return @"null";
    } else {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Unsupported type for canonical JSON: %@", NSStringFromClass([obj class])];
        return nil;
    }
}

- (BOOL)validateManifestStructure:(NSDictionary*)manifest error:(NSString**)errorOut {
    if (![manifest isKindOfClass:[NSDictionary class]]) {
        if (errorOut) *errorOut = @"Manifest is not a JSON object.";
        return NO;
    }
    
    NSSet* allowedTopLevel = [NSSet setWithArray:@[
        @"schemaVersion",
        @"comboId",
        @"createdAt",
        @"workspaceRootHash",
        @"chipVersions",
        @"files"
    ]];
    
    for (NSString* key in manifest.allKeys) {
        if (![allowedTopLevel containsObject:key]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Manifest contains unknown top-level field: %@", key];
            return NO;
        }
    }
    
    NSString* schemaVersion = manifest[@"schemaVersion"];
    if (schemaVersion && ![schemaVersion isKindOfClass:[NSString class]]) {
        if (errorOut) *errorOut = @"schemaVersion must be a string.";
        return NO;
    }
    
    if (schemaVersion && ![schemaVersion isEqualToString:@"1.6.1"] && ![schemaVersion isEqualToString:@"1.6.2"]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Unsupported schema version: %@", schemaVersion];
        return NO;
    }
    
    NSString* comboId = manifest[@"comboId"];
    if (comboId) {
        if (![comboId isKindOfClass:[NSString class]]) {
            if (errorOut) *errorOut = @"comboId must be a string.";
            return NO;
        }
        if (comboId.length > 128) {
            if (errorOut) *errorOut = @"comboId exceeds maximum allowed length of 128 characters.";
            return NO;
        }
    }
    
    NSString* createdAt = manifest[@"createdAt"];
    if (createdAt && ![createdAt isKindOfClass:[NSString class]]) {
        if (errorOut) *errorOut = @"createdAt must be a string.";
        return NO;
    }
    
    NSString* wsHash = manifest[@"workspaceRootHash"];
    if (wsHash && ![wsHash isKindOfClass:[NSString class]]) {
        if (errorOut) *errorOut = @"workspaceRootHash must be a string.";
        return NO;
    }
    
    NSArray* chipVersions = manifest[@"chipVersions"];
    if (chipVersions) {
        if (![chipVersions isKindOfClass:[NSArray class]]) {
            if (errorOut) *errorOut = @"chipVersions must be an array.";
            return NO;
        }
        if (chipVersions.count > 32) {
            if (errorOut) *errorOut = @"chipVersions exceeds maximum count of 32 items.";
            return NO;
        }
        for (id item in chipVersions) {
            if (![item isKindOfClass:[NSString class]]) {
                if (errorOut) *errorOut = @"All items in chipVersions must be strings.";
                return NO;
            }
        }
    }
    
    NSArray* files = manifest[@"files"];
    if (files) {
        if (![files isKindOfClass:[NSArray class]]) {
            if (errorOut) *errorOut = @"files must be an array.";
            return NO;
        }
        if (files.count > 256) {
            if (errorOut) *errorOut = @"files array exceeds maximum size of 256 entries.";
            return NO;
        }
    }
    
    NSSet* allowedFileKeys = [NSSet setWithArray:@[
        @"workspaceRelativePath",
        @"canonicalPathHash",
        @"domain",
        @"wasMissing",
        @"wasBinary",
        @"sizeBytes",
        @"newlineMode",
        @"preimageHash",
        @"expectedPostimageHash",
        @"backupBlobHash"
    ]];
    
    for (id fileEntry in files ?: @[]) {
        if (![fileEntry isKindOfClass:[NSDictionary class]]) {
            if (errorOut) *errorOut = @"Every entry in files must be a JSON object.";
            return NO;
        }
        
        NSDictionary* entry = (NSDictionary*)fileEntry;
        for (NSString* key in entry.allKeys) {
            if (![allowedFileKeys containsObject:key]) {
                if (errorOut) *errorOut = [NSString stringWithFormat:@"File entry contains unknown field: %@", key];
                return NO;
            }
        }
        
        NSString* relPath = entry[@"workspaceRelativePath"];
        if (relPath) {
            if (![relPath isKindOfClass:[NSString class]]) {
                if (errorOut) *errorOut = @"workspaceRelativePath must be a string.";
                return NO;
            }
            if (relPath.length > 4096) {
                if (errorOut) *errorOut = @"workspaceRelativePath exceeds maximum allowed length of 4096 characters.";
                return NO;
            }
        }
        
        NSString* cPathHash = entry[@"canonicalPathHash"];
        if (cPathHash && ![cPathHash isKindOfClass:[NSString class]]) {
            if (errorOut) *errorOut = @"canonicalPathHash must be a string.";
            return NO;
        }
        
        NSString* domain = entry[@"domain"];
        if (domain) {
            if (![domain isKindOfClass:[NSString class]]) {
                if (errorOut) *errorOut = @"domain must be a string.";
                return NO;
            }
            if (![domain isEqualToString:@"disk"] && ![domain isEqualToString:@"buffer"]) {
                if (errorOut) *errorOut = [NSString stringWithFormat:@"domain has invalid enum value: %@", domain];
                return NO;
            }
        }
        
        NSString* preimageHash = entry[@"preimageHash"];
        if (preimageHash && ![preimageHash isKindOfClass:[NSString class]]) {
            if (errorOut) *errorOut = @"preimageHash must be a string.";
            return NO;
        }
        
        NSString* expPostHash = entry[@"expectedPostimageHash"];
        if (expPostHash && ![expPostHash isKindOfClass:[NSString class]]) {
            if (errorOut) *errorOut = @"expectedPostimageHash must be a string.";
            return NO;
        }
        
        NSString* backupBlobHash = entry[@"backupBlobHash"];
        if (backupBlobHash && ![backupBlobHash isKindOfClass:[NSString class]]) {
            if (errorOut) *errorOut = @"backupBlobHash must be a string.";
            return NO;
        }
        
        NSNumber* sizeBytes = entry[@"sizeBytes"];
        if (sizeBytes && ![sizeBytes isKindOfClass:[NSNumber class]]) {
            if (errorOut) *errorOut = @"sizeBytes must be a number.";
            return NO;
        }
        
        NSString* newlineMode = entry[@"newlineMode"];
        if (newlineMode) {
            if (![newlineMode isKindOfClass:[NSString class]]) {
                if (errorOut) *errorOut = @"newlineMode must be a string.";
                return NO;
            }
            if (![newlineMode isEqualToString:@"lf"] && ![newlineMode isEqualToString:@"crlf"]) {
                if (errorOut) *errorOut = [NSString stringWithFormat:@"newlineMode has invalid enum value: %@", newlineMode];
                return NO;
            }
        }
        
        NSNumber* wasMissing = entry[@"wasMissing"];
        if (wasMissing && ![wasMissing isKindOfClass:[NSNumber class]]) {
            if (errorOut) *errorOut = @"wasMissing must be a boolean.";
            return NO;
        }
        
        NSNumber* wasBinary = entry[@"wasBinary"];
        if (wasBinary && ![wasBinary isKindOfClass:[NSNumber class]]) {
            if (errorOut) *errorOut = @"wasBinary must be a boolean.";
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)writeManifest:(NSDictionary*)manifest toPath:(NSString*)path error:(NSString**)errorOut {
    NSString* jsonStr = nil;
    NSString* sErr = nil;
    jsonStr = [self canonicalJsonStringForObject:manifest error:&sErr];
    if (!jsonStr) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Canonical serialization failed: %@", sErr];
        return NO;
    }
    
    NSData* data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length > 256 * 1024) {
        if (errorOut) *errorOut = @"Manifest exceeds maximum allowed size of 256KB.";
        return NO;
    }
    
    NSString* tmpPath = [path stringByAppendingPathExtension:@"tmp"];
    BOOL ok = [data writeToFile:tmpPath atomically:YES];
    if (!ok) {
        if (errorOut) *errorOut = @"Failed to write manifest temp file.";
        return NO;
    }
    
    int fd = open([tmpPath UTF8String], O_RDONLY);
    if (fd >= 0) {
        fsync(fd);
        close(fd);
    }
    
    if (rename([tmpPath UTF8String], [path UTF8String]) != 0) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Atomically renaming manifest failed: %s", strerror(errno)];
        unlink([tmpPath UTF8String]);
        return NO;
    }
    
    // Compute SHA256 and write manifest.sha256 companion file
    NSString* checksum = SHA256ForData(data);
    NSString* checksumPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"manifest.sha256"];
    NSString* tmpChecksumPath = [checksumPath stringByAppendingPathExtension:@"tmp"];
    
    NSError* cErr = nil;
    BOOL cOk = [checksum writeToFile:tmpChecksumPath atomically:YES encoding:NSUTF8StringEncoding error:&cErr];
    if (!cOk) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write sha256 temp file: %@", cErr.localizedDescription];
        return NO;
    }
    
    int cFd = open([tmpChecksumPath UTF8String], O_RDONLY);
    if (cFd >= 0) {
        fsync(cFd);
        close(cFd);
    }
    
    if (rename([tmpChecksumPath UTF8String], [checksumPath UTF8String]) != 0) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Atomically renaming sha256 failed: %s", strerror(errno)];
        unlink([tmpChecksumPath UTF8String]);
        return NO;
    }
    
    // Fsync the parent backup directory to persist the directory metadata changes
    NSString* parentDir = [path stringByDeletingLastPathComponent];
    int dirFd = open([parentDir UTF8String], O_RDONLY);
    if (dirFd >= 0) {
        fsync(dirFd);
        close(dirFd);
    }
    
    return YES;
}

- (NSDictionary*)loadManifestFromPath:(NSString*)path error:(NSString**)errorOut {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (errorOut) *errorOut = @"Manifest file missing.";
        return nil;
    }
    
    NSError* err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err];
    if (attrs) {
        unsigned long long fileSize = [attrs fileSize];
        if (fileSize > 256 * 1024) {
            if (errorOut) *errorOut = @"Manifest exceeds maximum allowed size of 256KB.";
            return nil;
        }
    }
    
    NSData* data = [NSData dataWithContentsOfFile:path options:0 error:&err];
    if (err || !data) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to read manifest: %@", err.localizedDescription];
        return nil;
    }
    
    NSDictionary* manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || !manifest) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Malformed JSON in manifest: %@", err.localizedDescription];
        return nil;
    }
    
    NSString* valErr = nil;
    if (![self validateManifestStructure:manifest error:&valErr]) {
        if (errorOut) *errorOut = valErr;
        return nil;
    }
    
    NSString* schemaVersion = manifest[@"schemaVersion"] ?: @"1.6.1";
    if ([schemaVersion isEqualToString:@"1.6.2"]) {
        NSString* checksumPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"manifest.sha256"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:checksumPath]) {
            if (errorOut) *errorOut = @"manifest.sha256 file missing.";
            return nil;
        }
        
        NSError* cErr = nil;
        NSString* expectedChecksum = [[NSString stringWithContentsOfFile:checksumPath encoding:NSUTF8StringEncoding error:&cErr] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (cErr || !expectedChecksum) {
            if (errorOut) *errorOut = @"Failed to read manifest.sha256.";
            return nil;
        }
        
        NSString* computedChecksum = SHA256ForData(data);
        if (![computedChecksum isEqualToString:expectedChecksum]) {
            if (errorOut) *errorOut = @"Manifest checksum verification failed.";
            return nil;
        }
    }
    
    return manifest;
}

static BOOL IsTextBinary(NSString* text) {
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

- (BOOL)createCheckpointForPaths:(NSArray<NSString*>*)paths
                         comboId:(NSString*)comboId
                            plan:(NSDictionary*)plan
                     manifestOut:(NSDictionary**)manifestOut
                    backupDirOut:(NSString**)backupDirOut
                           error:(NSString**)errorOut {
    NSString* ws = [_windowController workspacePath];
    if (ws.length == 0) {
        if (errorOut) *errorOut = @"Workspace path is empty.";
        return NO;
    }
    
    std::error_code ec;
    std::filesystem::path wsPath = std::filesystem::canonical(std::filesystem::path(StdStringFromNSString(ws)), ec);
    if (ec) {
        if (errorOut) *errorOut = @"Workspace path cannot be canonicalized.";
        return NO;
    }
    
    NSString* backupDir = [[NSHomeDirectory() stringByAppendingPathComponent:@".dietcode/backups"] stringByAppendingPathComponent:comboId];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:nil]) {
        if (errorOut) *errorOut = @"Failed to create backup directory.";
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0700)} ofItemAtPath:backupDir error:nil];
    
    NSMutableDictionary* manifest = [NSMutableDictionary dictionary];
    manifest[@"schemaVersion"] = @"1.6.2";
    manifest[@"comboId"] = comboId;
    manifest[@"workspaceRootHash"] = StableHashForString(ws);
    manifest[@"createdAt"] = ISODateString([NSDate date]);
    
    NSMutableArray* chipVersions = [NSMutableArray array];
    for (NSDictionary* step in plan[@"steps"] ?: @[]) {
        NSString* chip = step[@"chip"];
        NSString* version = [NSString stringWithFormat:@"%@@%@", chip, step[@"metadata"][@"version"] ?: @1];
        if (![chipVersions containsObject:version]) {
            [chipVersions addObject:version];
        }
    }
    manifest[@"chipVersions"] = chipVersions;
    
    NSMutableArray* filesArray = [NSMutableArray array];
    
    for (NSString* rawPath in paths) {
        NSString* absPath = AbsolutePathForRPCPath(rawPath, ws);
        
        if (!PathIsInsideWorkspace(absPath, ws)) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Path escapes workspace: %@", rawPath];
            [[NSFileManager defaultManager] removeItemAtPath:backupDir error:nil];
            return NO;
        }
        
        std::filesystem::path p(StdStringFromNSString(absPath));
        std::filesystem::path canonicalPath = std::filesystem::exists(p) ? std::filesystem::canonical(p, ec) : std::filesystem::weakly_canonical(p, ec);
        if (ec) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to canonicalize path: %@", rawPath];
            [[NSFileManager defaultManager] removeItemAtPath:backupDir error:nil];
            return NO;
        }
        
        std::filesystem::path rel = std::filesystem::relative(canonicalPath, wsPath, ec);
        if (ec) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to calculate relative path: %@", rawPath];
            [[NSFileManager defaultManager] removeItemAtPath:backupDir error:nil];
            return NO;
        }
        NSString* relPath = NSStringFromStdString(rel.string());
        
        NSMutableDictionary* fileEntry = [NSMutableDictionary dictionary];
        fileEntry[@"workspaceRelativePath"] = relPath;
        fileEntry[@"canonicalPathHash"] = StableHashForString(NSStringFromStdString(canonicalPath.string()));
        
        BOOL isOpen = NO;
        for (NSString* openPath in [self safeOpenFilePaths]) {
            if ([openPath isEqualToString:absPath]) {
                isOpen = YES;
                break;
            }
        }
        fileEntry[@"domain"] = isOpen ? @"buffer" : @"disk";
        
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:absPath];
        if (exists) {
            NSString* beforeText = [self safeTextForFileAtPath:absPath];
            if (beforeText == nil) {
                fileEntry[@"wasBinary"] = @YES;
                fileEntry[@"wasMissing"] = @NO;
                fileEntry[@"sizeBytes"] = @0;
                fileEntry[@"preimageHash"] = @"";
                fileEntry[@"expectedPostimageHash"] = @"";
                fileEntry[@"backupBlobHash"] = @"";
                fileEntry[@"newlineMode"] = @"lf";
            } else {
                BOOL isBin = IsTextBinary(beforeText);
                fileEntry[@"wasBinary"] = @(isBin);
                fileEntry[@"wasMissing"] = @NO;
                
                NSUInteger bytesCount = [beforeText lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                fileEntry[@"sizeBytes"] = @(bytesCount);
                
                NSString* pHash = StableHashForString(beforeText);
                fileEntry[@"preimageHash"] = pHash;
                fileEntry[@"expectedPostimageHash"] = pHash;
                fileEntry[@"backupBlobHash"] = pHash;
                
                BOOL isCrlf = [beforeText rangeOfString:@"\r\n"].location != NSNotFound;
                fileEntry[@"newlineMode"] = isCrlf ? @"crlf" : @"lf";
                
                if (!isBin) {
                    NSString* blobPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.blob", pHash]];
                    NSError* writeErr = nil;
                    BOOL writeOk = [beforeText writeToFile:blobPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
                    if (!writeOk) {
                        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write preimage blob: %@", writeErr.localizedDescription];
                        [[NSFileManager defaultManager] removeItemAtPath:backupDir error:nil];
                        return NO;
                    }
                    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:blobPath error:nil];
                    
                    int fd = open([blobPath UTF8String], O_RDONLY);
                    if (fd >= 0) {
                        fsync(fd);
                        close(fd);
                    }
                }
            }
        } else {
            fileEntry[@"wasBinary"] = @NO;
            fileEntry[@"wasMissing"] = @YES;
            fileEntry[@"sizeBytes"] = @0;
            fileEntry[@"preimageHash"] = @"";
            fileEntry[@"expectedPostimageHash"] = @"";
            fileEntry[@"backupBlobHash"] = @"";
            fileEntry[@"newlineMode"] = @"lf";
        }
        
        [filesArray addObject:fileEntry];
    }
    
    manifest[@"files"] = filesArray;
    
    NSString* manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.json"];
    NSString* mErr = nil;
    if (![self writeManifest:manifest toPath:manifestPath error:&mErr]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write manifest: %@", mErr];
        [[NSFileManager defaultManager] removeItemAtPath:backupDir error:nil];
        return NO;
    }
    
    if (manifestOut) *manifestOut = manifest;
    if (backupDirOut) *backupDirOut = backupDir;
    return YES;
}

- (BOOL)restorePatchFromManifest:(NSDictionary*)manifest
                       backupDir:(NSString*)backupDir
                         confirm:(BOOL)confirm
                           error:(NSString**)errorOut
                       errorCode:(NSString**)errorCodeOut {
    NSString* ws = [_windowController workspacePath];
    if (ws.length == 0) {
        if (errorCodeOut) *errorCodeOut = @"backup_workspace_mismatch";
        if (errorOut) *errorOut = @"No active workspace.";
        return NO;
    }
    
    NSString* manifestWsHash = manifest[@"workspaceRootHash"];
    if (![manifestWsHash isEqualToString:StableHashForString(ws)]) {
        if (errorCodeOut) *errorCodeOut = @"backup_workspace_mismatch";
        if (errorOut) *errorOut = @"Workspace mismatch: backup was created in a different workspace.";
        return NO;
    }
    
    NSString* manifestSession = manifest[@"sessionId"];
    if (manifestSession && _sessionToken && ![manifestSession isEqualToString:_sessionToken]) {
        if (!confirm) {
            if (errorCodeOut) *errorCodeOut = @"backup_manifest_invalid";
            if (errorOut) *errorOut = @"Session token mismatch. Re-run with confirm=true to override.";
            return NO;
        }
    }
    
    NSArray* files = manifest[@"files"] ?: @[];
    NSMutableDictionary* fileBlobs = [NSMutableDictionary dictionary];
    
    // First pass: validation (do not write any files)
    for (NSDictionary* fileEntry in files) {
        NSString* relPath = fileEntry[@"workspaceRelativePath"];
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        
        if (!PathIsInsideWorkspace(absPath, ws)) {
            if (errorCodeOut) *errorCodeOut = @"rollback_target_escaped";
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Target path escapes workspace: %@", relPath];
            return NO;
        }
        
        BOOL wasMissing = [fileEntry[@"wasMissing"] boolValue];
        BOOL wasBinary = [fileEntry[@"wasBinary"] boolValue];
        NSString* expectedPostHash = fileEntry[@"expectedPostimageHash"];
        NSString* preimageHash = fileEntry[@"preimageHash"];
        NSString* blobHash = fileEntry[@"backupBlobHash"];
        
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:absPath];
        
        if (wasMissing) {
            if (exists) {
                NSString* currentText = [self safeTextForFileAtPath:absPath];
                NSString* currentHash = StableHashForString(currentText ?: @"");
                if (![currentHash isEqualToString:expectedPostHash]) {
                    if ([self dirtyBufferExistsAtPath:absPath]) {
                        if (errorCodeOut) *errorCodeOut = @"rollback_buffer_conflict";
                    } else {
                        if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                    }
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Postimage hash mismatch for new file %@", relPath];
                    return NO;
                }

                if ([fileEntry[@"domain"] isEqualToString:@"buffer"]) {
                    NSError* readErr = nil;
                    NSString* diskText = [NSString stringWithContentsOfFile:absPath encoding:NSUTF8StringEncoding error:&readErr];
                    if (diskText) {
                        NSString* diskHash = StableHashForString(diskText);
                        if (![diskHash isEqualToString:expectedPostHash]) {
                            if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                            if (errorOut) *errorOut = [NSString stringWithFormat:@"Postimage hash mismatch on disk (modified externally) for new file %@", relPath];
                            return NO;
                        }
                    }
                }
            }
        } else {
            if (!exists) {
                if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                if (errorOut) *errorOut = [NSString stringWithFormat:@"File was deleted externally: %@", relPath];
                return NO;
            }
            
            NSString* currentText = [self safeTextForFileAtPath:absPath];
            if (currentText == nil) {
                if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to read current file content: %@", relPath];
                return NO;
            }
            
            if (IsTextBinary(currentText)) {
                if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                if (errorOut) *errorOut = [NSString stringWithFormat:@"File became binary: %@", relPath];
                return NO;
            }
            
            NSString* currentHash = StableHashForString(currentText);
            if (![currentHash isEqualToString:expectedPostHash]) {
                if ([self dirtyBufferExistsAtPath:absPath]) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_buffer_conflict";
                } else {
                    if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                }
                if (errorOut) *errorOut = [NSString stringWithFormat:@"Postimage hash mismatch for %@", relPath];
                return NO;
            }

            if ([fileEntry[@"domain"] isEqualToString:@"buffer"]) {
                NSError* readErr = nil;
                NSString* diskText = [NSString stringWithContentsOfFile:absPath encoding:NSUTF8StringEncoding error:&readErr];
                if (diskText == nil) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to read disk content for %@", relPath];
                    return NO;
                }
                NSString* diskHash = StableHashForString(diskText);
                if (![diskHash isEqualToString:preimageHash] && ![diskHash isEqualToString:expectedPostHash]) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_postimage_mismatch";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Postimage hash mismatch on disk (modified externally) for %@", relPath];
                    return NO;
                }
            }
            
            if (!wasBinary) {
                NSString* blobPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.blob", blobHash]];
                if (![[NSFileManager defaultManager] fileExistsAtPath:blobPath]) {
                    if (errorCodeOut) *errorCodeOut = @"backup_corrupt";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Preimage backup blob missing for %@", relPath];
                    return NO;
                }
                
                NSError* readErr = nil;
                NSString* blobText = [NSString stringWithContentsOfFile:blobPath encoding:NSUTF8StringEncoding error:&readErr];
                if (readErr || !blobText) {
                    if (errorCodeOut) *errorCodeOut = @"backup_corrupt";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to read preimage blob for %@", relPath];
                    return NO;
                }
                
                NSString* computedBlobHash = StableHashForString(blobText);
                if (![computedBlobHash isEqualToString:preimageHash]) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_preimage_mismatch";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Blob preimage hash integrity check failed for %@", relPath];
                    return NO;
                }
                
                fileBlobs[absPath] = blobText;
            }
        }
    }
    
    // Second pass: application
    for (NSDictionary* fileEntry in files) {
        NSString* relPath = fileEntry[@"workspaceRelativePath"];
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        BOOL wasMissing = [fileEntry[@"wasMissing"] boolValue];
        BOOL wasBinary = [fileEntry[@"wasBinary"] boolValue];
        
        if (wasMissing) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
                NSError* deleteErr = nil;
                [[NSFileManager defaultManager] removeItemAtPath:absPath error:&deleteErr];
                if (deleteErr) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_partial_failure";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to remove added file %@: %@", relPath, deleteErr.localizedDescription];
                    return NO;
                }
                
                NSString* currentText = [_windowController textForFileAtPath:absPath];
                if (currentText) {
                    [self safeReplaceTextInRange:NSMakeRange(0, currentText.length) withText:@"" forFileAtPath:absPath];
                }
            }
        } else {
            if (!wasBinary) {
                NSString* blobText = fileBlobs[absPath];
                NSString* currentText = [_windowController textForFileAtPath:absPath];
                BOOL ok = [self safeReplaceTextInRange:NSMakeRange(0, currentText.length) withText:blobText forFileAtPath:absPath];
                
                NSError* writeErr = nil;
                BOOL writeOk = [blobText writeToFile:absPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
                if (!writeOk && !ok) {
                    if (errorCodeOut) *errorCodeOut = @"rollback_partial_failure";
                    if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write rollback content to %@: %@", relPath, writeErr.localizedDescription];
                    return NO;
                }
            }
        }
    }
    
    return YES;
}

- (NSDictionary*)performRecoveryScan:(NSString**)errorOut {
    NSString* backupsDir = [NSHomeDirectory() stringByAppendingPathComponent:@".dietcode/backups"];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:backupsDir isDirectory:&isDir] || !isDir) {
        return @{ @"backups": @[] };
    }
    
    NSError* dirErr = nil;
    NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupsDir error:&dirErr];
    if (dirErr) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to list backups directory: %@", dirErr.localizedDescription];
        return nil;
    }
    
    NSMutableArray* backupsReport = [NSMutableArray array];
    NSString* currentWs = [_windowController workspacePath];
    
    for (NSString* comboId in contents) {
        NSString* backupDir = [backupsDir stringByAppendingPathComponent:comboId];
        BOOL isSubDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:backupDir isDirectory:&isSubDir] || !isSubDir) {
            continue;
        }
        
        NSString* manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.json"];
        NSString* mErr = nil;
        NSDictionary* manifest = [self loadManifestFromPath:manifestPath error:&mErr];
        if (!manifest) {
            NSString* status = @"invalid_manifest";
            if ([mErr isEqualToString:@"Manifest file missing."]) {
                status = @"manifest_missing";
            } else if ([mErr isEqualToString:@"manifest.sha256 file missing."]) {
                status = @"checksum_missing";
            } else if ([mErr isEqualToString:@"Manifest checksum verification failed."] || [mErr isEqualToString:@"Failed to read manifest.sha256."]) {
                status = @"checksum_mismatch";
            } else if ([mErr hasPrefix:@"Unsupported schema version"]) {
                status = @"unsupported_schema";
            } else if ([mErr hasPrefix:@"Manifest exceeds maximum"]) {
                status = @"invalid_manifest";
            }
            [backupsReport addObject:@{
                @"comboId": comboId,
                @"status": status,
                @"error": mErr ?: @"manifest.json missing or invalid"
            }];
            continue;
        }
        
        NSString* schemaVersion = manifest[@"schemaVersion"] ?: @"1.6.1";
        if (![schemaVersion isEqualToString:@"1.6.2"]) {
            [backupsReport addObject:@{
                @"comboId": comboId,
                @"status": @"unsupported_schema",
                @"error": [NSString stringWithFormat:@"Unsupported schema version: %@", schemaVersion]
            }];
            continue;
        }
        
        NSString* manifestWsHash = manifest[@"workspaceRootHash"];
        BOOL wsMatches = currentWs.length > 0 && [manifestWsHash isEqualToString:StableHashForString(currentWs)];
        if (!wsMatches) {
            [backupsReport addObject:@{
                @"comboId": comboId,
                @"status": @"workspace_mismatch",
                @"error": @"Workspace root hash mismatch."
            }];
            continue;
        }
        
        NSMutableArray* filesReport = [NSMutableArray array];
        NSString* finalStatus = @"valid";
        
        NSArray* files = manifest[@"files"] ?: @[];
        for (NSDictionary* fileEntry in files) {
            NSString* relPath = fileEntry[@"workspaceRelativePath"];
            NSString* absPath = currentWs.length > 0 ? AbsolutePathForRPCPath(relPath, currentWs) : nil;
            NSString* expectedPostHash = fileEntry[@"expectedPostimageHash"];
            NSString* preimageHash = fileEntry[@"preimageHash"];
            NSString* blobHash = fileEntry[@"backupBlobHash"];
            BOOL wasMissing = [fileEntry[@"wasMissing"] boolValue];
            
            NSMutableDictionary* fileRep = [NSMutableDictionary dictionary];
            fileRep[@"workspaceRelativePath"] = relPath;
            
            if (!wasMissing) {
                NSString* blobPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.blob", blobHash]];
                if (![[NSFileManager defaultManager] fileExistsAtPath:blobPath]) {
                    finalStatus = @"blob_missing";
                    break;
                }
                
                NSData* blobData = [NSData dataWithContentsOfFile:blobPath];
                if (!blobData) {
                    finalStatus = @"blob_missing";
                    break;
                }
                NSString* computedBlobHash = StableHashForData(blobData);
                if (![computedBlobHash isEqualToString:preimageHash]) {
                    finalStatus = @"blob_hash_mismatch";
                    break;
                }
            }
            
            if (!absPath || !PathIsInsideWorkspace(absPath, currentWs)) {
                finalStatus = @"workspace_mismatch";
                break;
            }
            
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:absPath];
            if (wasMissing) {
                if (exists) {
                    NSString* currentText = [self safeTextForFileAtPath:absPath];
                    NSString* currentHash = StableHashForString(currentText ?: @"");
                    if (![currentHash isEqualToString:expectedPostHash]) {
                        finalStatus = @"postimage_mismatch";
                    }
                    
                    if ([fileEntry[@"domain"] isEqualToString:@"buffer"]) {
                        NSData* diskData = [NSData dataWithContentsOfFile:absPath];
                        if (diskData) {
                            NSString* diskHash = StableHashForData(diskData);
                            if (![diskHash isEqualToString:expectedPostHash]) {
                                finalStatus = @"postimage_mismatch";
                            }
                        }
                    }
                }
            } else {
                if (!exists) {
                    finalStatus = @"postimage_mismatch";
                } else {
                    NSString* currentText = [self safeTextForFileAtPath:absPath];
                    if (currentText == nil || IsTextBinary(currentText)) {
                        finalStatus = @"postimage_mismatch";
                    } else {
                        NSString* currentHash = StableHashForString(currentText);
                        if (![currentHash isEqualToString:expectedPostHash]) {
                            finalStatus = @"postimage_mismatch";
                        }
                    }
                    
                    if ([fileEntry[@"domain"] isEqualToString:@"buffer"]) {
                        NSData* diskData = [NSData dataWithContentsOfFile:absPath];
                        if (!diskData) {
                            finalStatus = @"postimage_mismatch";
                        } else {
                            NSString* diskHash = StableHashForData(diskData);
                            if (![diskHash isEqualToString:preimageHash] && ![diskHash isEqualToString:expectedPostHash]) {
                                finalStatus = @"postimage_mismatch";
                            }
                        }
                    }
                }
            }
            
            fileRep[@"status"] = [finalStatus isEqualToString:@"postimage_mismatch"] ? @"mismatch" : @"match";
            [filesReport addObject:fileRep];
        }
        
        if ([finalStatus isEqualToString:@"valid"]) {
            BOOL allMatched = YES;
            for (NSDictionary* r in filesReport) {
                if ([r[@"status"] isEqualToString:@"mismatch"]) {
                    allMatched = NO;
                    break;
                }
            }
            finalStatus = allMatched ? @"postimage_match" : @"postimage_mismatch";
        }
        
        [backupsReport addObject:@{
            @"comboId": comboId,
            @"createdAt": manifest[@"createdAt"] ?: @"",
            @"status": finalStatus,
            @"files": filesReport
        }];
    }
    
    return @{ @"backups": backupsReport };
}


- (NSDictionary*)validatePatchAtPath:(NSString*)path patch:(NSString*)patch currentText:(NSString*)currentTextOverride {
    NSString* ws = [_windowController workspacePath];
    NSString* targetPath = AbsolutePathForRPCPath(path, ws);
    BOOL insideWorkspace = ws.length > 0 && PathIsInsideWorkspace(targetPath, ws);
    BOOL targetExists = targetPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:targetPath];
    NSArray* hunks = HunkSummariesFromPatch(patch ?: @"");
    NSInteger changedLineCount = ChangedLineCountFromHunks(hunks);
    BOOL requiresConfirmation = (patch.length > kMaxPatchBytesBeforeConfirmation) || changedLineCount > 200;

    NSMutableDictionary* result = [@{
        @"ok": @NO,
        @"targetFileExists": @(targetExists),
        @"insideWorkspace": @(insideWorkspace),
        @"patchAppliesCleanly": @NO,
        @"changedLineCount": @(changedLineCount),
        @"affectedHunks": hunks,
        @"affectedSymbols": @[],
        @"requiresConfirmation": @(requiresConfirmation),
        @"rejectedReason": @""
    } mutableCopy];

    if (!insideWorkspace) {
        result[@"rejectedReason"] = @"Target file is outside workspace.";
        return result;
    }
    if (!targetExists) {
        result[@"rejectedReason"] = @"Target file does not exist.";
        return result;
    }
    if (patch.length == 0) {
        result[@"rejectedReason"] = @"Patch is empty.";
        return result;
    }

    NSString* currentText = currentTextOverride ?: [_windowController textForFileAtPath:targetPath];
    if (!currentText) {
        result[@"rejectedReason"] = @"Target file is not readable.";
        return result;
    }

    NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:currentText extension:[[targetPath pathExtension] lowercaseString]];
    NSDictionary* preview = [DietCodeDiffAnalysisService previewPatchAtPath:targetPath patch:patch currentText:currentText symbols:symbols];
    BOOL clean = [preview[@"ok"] boolValue];
    result[@"patchAppliesCleanly"] = @(clean);
    result[@"affectedSymbols"] = AffectedSymbolsForPatch(patch, symbols);
    result[@"preview"] = preview;

    if (!clean) {
        result[@"rejectedReason"] = preview[@"error"] ?: @"Patch does not apply cleanly.";
        return result;
    }
    if ([preview[@"syntaxDanger"] boolValue]) {
        result[@"rejectedReason"] = preview[@"syntaxErrors"] ?: @"Patch introduces syntax risk.";
        return result;
    }

    result[@"ok"] = @YES;
    result[@"rejectedReason"] = @"";
    return result;
}

- (NSDictionary*)currentChangesInfo {
    NSString* ws = [_windowController workspacePath] ?: @"";
    NSDictionary* git = [_windowController gitStatusInfo] ?: @{};
    NSDictionary* diffInfo = ws.length > 0 ? [DietCodeDiffAnalysisService workspaceDiffInfo:ws] : @{};
    NSMutableArray* files = [NSMutableArray array];

    for (NSDictionary* file in diffInfo[@"files"] ?: @[]) {
        NSString* relPath = file[@"path"] ?: @"";
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        NSString* text = [_windowController textForFileAtPath:absPath] ?: @"";
        NSArray* symbols = text.length > 0 ? [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[absPath pathExtension] lowercaseString]] : @[];
        NSString* diff = [_windowController gitDiffForFile:absPath] ?: @"";
        NSMutableDictionary* enriched = [file mutableCopy];
        enriched[@"absolutePath"] = absPath ?: @"";
        enriched[@"affectedSymbols"] = AffectedSymbolsForPatch(diff, symbols);
        [files addObject:enriched];
    }

    NSArray* dirtyFiles = DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]);
    NSMutableArray* unsaved = [NSMutableArray array];
    for (NSString* dirtyPath in dirtyFiles) {
        [unsaved addObject:@{ @"path": dirtyPath }];
    }

    return @{
        @"modifiedFiles": files,
        @"unsavedBuffers": unsaved,
        @"stagedFiles": git[@"staged"] ?: @[],
        @"unstagedFiles": git[@"modified"] ?: @[],
        @"untrackedFiles": git[@"untracked"] ?: @[],
        @"totalAdded": diffInfo[@"totalAdded"] ?: @0,
        @"totalDeleted": diffInfo[@"totalDeleted"] ?: @0
    };
}

- (NSDictionary*)runVerificationCommand:(NSString*)command cwd:(NSString*)cwd {
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/zsh"];
    [task setArguments:@[@"-c", command]];
    
    NSString* ws = [self safeWorkspacePath];
    NSString* runCwd = cwd.length > 0 ? cwd : ws;
    if (runCwd.length > 0) {
        [task setCurrentDirectoryPath:runCwd];
    } else {
        [task setCurrentDirectoryPath:@"~"];
    }
    
    NSPipe* outPipe = [NSPipe pipe];
    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:errPipe];
    
    _lastVerifyCommand = [command copy];
    _lastVerifyStartedAt = [NSDate date];
    _lastVerifyFinishedAt = nil;
    _lastVerifyExitCode = nil;
    
    _lastVerifyStatus = @{
        @"command": command,
        @"state": @"running",
        @"exitCode": [NSNull null],
        @"passed": @NO,
        @"startedAt": ISODateString(_lastVerifyStartedAt)
    };
    
    @try {
        [_windowController appendControlLogLine:[NSString stringWithFormat:@"[Verify] Starting command: %@", command]];
        [task launch];
        [task waitUntilExit];
        
        _lastVerifyFinishedAt = [NSDate date];
        int status = [task terminationStatus];
        _lastVerifyExitCode = @(status);
        
        NSData* outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
        NSString* outStr = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
        
        NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
        NSString* errStr = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
        
        if (outStr.length > 0) {
            [_windowController appendControlLogLine:outStr];
        }
        if (errStr.length > 0) {
            [_windowController appendControlLogLine:[NSString stringWithFormat:@"[Error] %@", errStr]];
        }
        
        NSTimeInterval duration = [_lastVerifyFinishedAt timeIntervalSinceDate:_lastVerifyStartedAt];
        _lastVerifyStatus = @{
            @"command": command,
            @"state": @"complete",
            @"exitCode": @(status),
            @"passed": @(status == 0),
            @"startedAt": ISODateString(_lastVerifyStartedAt),
            @"finishedAt": ISODateString(_lastVerifyFinishedAt),
            @"durationMs": @((NSInteger)(duration * 1000.0))
        };
    } @catch (NSException* exception) {
        _lastVerifyFinishedAt = [NSDate date];
        _lastVerifyExitCode = @(-1);
        _lastVerifyStatus = @{
            @"command": command,
            @"state": @"complete",
            @"exitCode": @(-1),
            @"passed": @NO,
            @"startedAt": ISODateString(_lastVerifyStartedAt),
            @"finishedAt": ISODateString(_lastVerifyFinishedAt),
            @"error": exception.reason ?: @"Failed to launch verification task"
        };
    }
    return _lastVerifyStatus;
}

- (NSDictionary*)verificationStatus {
    return _lastVerifyStatus ?: @{
        @"command": @"",
        @"state": @"idle",
        @"exitCode": [NSNull null],
        @"passed": @NO
    };
}

- (NSDictionary*)contextSnapshotPayload {
    NSDictionary* git = [_windowController gitStatusInfo] ?: @{};
    NSArray* problems = [_windowController problemsList] ?: @[];
    return @{
        @"activeFile": [_windowController activeFilePath] ?: @"",
        @"openFiles": [_windowController openFilePaths] ?: @[],
        @"dirtyFiles": DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]),
        @"currentBranch": git[@"branch"] ?: @"",
        @"recentSearches": _windowController.sessionLastSearches ?: @[],
        @"recentCommands": _windowController.sessionRecentCommands ?: @[],
        @"problemCount": @(problems.count),
        @"changes": [self currentChangesInfo]
    };
}

- (NSArray<NSString*>*)verificationFailureLines {
    NSMutableArray* failures = [NSMutableArray array];
    NSString* output = [_windowController terminalOutput] ?: @"";
    NSArray<NSString*>* markers = @[@"error:", @"failed", @"failure", @"FAILED", @"Error:", @"Assertion"];
    [output enumerateLinesUsingBlock:^(NSString* line, BOOL*) {
        for (NSString* marker in markers) {
            if ([line rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [failures addObject:line];
                break;
            }
        }
    }];
    if (failures.count > 100) {
        return [failures subarrayWithRange:NSMakeRange(failures.count - 100, 100)];
    }
    return failures;
}

- (void)recordLastRPCPatchPaths:(NSArray<NSDictionary*>*)records {
    [_lastRPCPatchRecords removeAllObjects];
    [_lastRPCPatchRecords addObjectsFromArray:records ?: @[]];
}

- (BOOL)restorePatchRecords:(NSArray<NSDictionary*>*)records error:(NSString**)errorOut {
    NSString* ws = [_windowController workspacePath];
    if (ws.length == 0) {
        if (errorOut) *errorOut = @"No active workspace.";
        return NO;
    }
    
    // First pass: validation
    for (NSDictionary* record in records.reverseObjectEnumerator) {
        NSString* path = record[@"path"];
        NSString* beforeText = record[@"beforeText"];
        NSString* expectedPostHash = record[@"postHash"];
        NSString* beforeHash = record[@"beforeHash"];
        
        if (!path || beforeText == nil) {
            if (errorOut) *errorOut = @"Cannot restore patch because a target buffer record is invalid.";
            return NO;
        }
        
        NSString* absPath = AbsolutePathForRPCPath(path, ws);
        if (!PathIsInsideWorkspace(absPath, ws)) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Target path escapes workspace: %@", path];
            return NO;
        }
        
        NSString* currentText = [_windowController textForFileAtPath:absPath];
        if (currentText == nil) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Cannot restore patch because target buffer is unavailable: %@", path];
            return NO;
        }
        
        if (IsTextBinary(currentText)) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"File is binary: %@", path];
            return NO;
        }
        
        if (expectedPostHash.length > 0 && ![StableHashForString(currentText) isEqualToString:expectedPostHash]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Rollback conflict for %@: current buffer no longer matches the expected postimage.", path];
            return NO;
        }
        
        if (beforeHash.length > 0 && ![StableHashForString(beforeText) isEqualToString:beforeHash]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Preimage hash mismatch for %@", path];
            return NO;
        }
    }
    
    // Second pass: apply
    for (NSDictionary* record in records.reverseObjectEnumerator) {
        NSString* path = record[@"path"];
        NSString* beforeText = record[@"beforeText"];
        NSString* absPath = AbsolutePathForRPCPath(path, ws);
        NSString* currentText = [_windowController textForFileAtPath:absPath];
        BOOL ok = [self safeReplaceTextInRange:NSMakeRange(0, currentText.length) withText:beforeText forFileAtPath:absPath];
        if (!ok) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to restore %@", path];
            return NO;
        }
    }
    return YES;
}

- (BOOL)path:(NSString*)path isAllowedByScope:(NSDictionary*)scope {
    NSString* ws = [_windowController workspacePath];
    NSString* absPath = AbsolutePathForRPCPath(path, ws);
    if (!PathIsInsideWorkspace(absPath, ws)) return NO;
    std::error_code ec;
    std::filesystem::path rel = std::filesystem::relative(std::filesystem::path(StdStringFromNSString(absPath)), std::filesystem::path(StdStringFromNSString(ws)), ec);
    if (ec) return NO;
    std::string relPath = rel.string();
    std::string filename = std::filesystem::path(relPath).filename().string();
    NSArray* includes = scope[@"include"] ?: @[];
    NSArray* excludes = scope[@"exclude"] ?: @[];
    if (AnyPatternMatches(excludes, relPath, filename)) return NO;
    if (includes.count > 0 && !AnyPatternMatches(includes, relPath, filename)) return NO;
    return YES;
}

- (BOOL)dirtyBufferExistsAtPath:(NSString*)path {
    NSString* ws = [_windowController workspacePath];
    NSString* absPath = AbsolutePathForRPCPath(path, ws);
    for (id tab in _windowController.openTabs ?: @[]) {
        NSString* tabPath = [tab valueForKey:@"path"];
        BOOL dirty = [[tab valueForKey:@"dirty"] boolValue];
        if (dirty && [tabPath isEqualToString:absPath]) return YES;
    }
    return NO;
}

- (BOOL)task:(NSMutableDictionary*)task canConsumeStep:(NSDictionary*)step error:(NSString**)errorOut {
    if ([task[@"status"] isEqualToString:@"cancelled"] || [task[@"status"] isEqualToString:@"complete"]) {
        if (errorOut) *errorOut = @"Task is not active.";
        return NO;
    }
    NSDictionary* budget = task[@"budget"] ?: @{};
    NSDate* startedAt = task[@"startedAtDate"];
    NSInteger maxDuration = budget[@"maxDurationMs"] ? [budget[@"maxDurationMs"] integerValue] : 300000;
    if (startedAt && [[NSDate date] timeIntervalSinceDate:startedAt] * 1000.0 > maxDuration) {
        task[@"status"] = @"budget_exceeded";
        if (errorOut) *errorOut = @"Task exceeded maxDurationMs.";
        return NO;
    }
    NSString* type = step[@"type"] ?: @"";
    if ([type isEqualToString:@"patch"] || [type isEqualToString:@"patchBatch"]) {
        NSInteger maxPatchBatches = budget[@"maxPatchBatches"] ? [budget[@"maxPatchBatches"] integerValue] : 3;
        if ([task[@"patchBatchesUsed"] integerValue] >= maxPatchBatches) {
            if (errorOut) *errorOut = @"Task exceeded maxPatchBatches.";
            return NO;
        }
    }
    if ([type isEqualToString:@"verify"]) {
        NSInteger maxVerifyRuns = budget[@"maxVerifyRuns"] ? [budget[@"maxVerifyRuns"] integerValue] : 3;
        if ([task[@"verifyRunsUsed"] integerValue] >= maxVerifyRuns) {
            if (errorOut) *errorOut = @"Task exceeded maxVerifyRuns.";
            return NO;
        }
    }
    NSDictionary* scope = task[@"scope"] ?: @{};
    NSMutableSet* touched = task[@"filesTouchedSet"];
    NSMutableArray* candidatePaths = [NSMutableArray array];
    NSMutableArray* candidateAbsPaths = [NSMutableArray array];
    if (step[@"path"]) [candidatePaths addObject:step[@"path"]];
    for (NSDictionary* item in step[@"patches"] ?: @[]) {
        if (item[@"path"]) [candidatePaths addObject:item[@"path"]];
    }
    for (NSString* candidate in candidatePaths) {
        if (![self path:candidate isAllowedByScope:scope]) {
            if (errorOut) *errorOut = [NSString stringWithFormat:@"Path is outside task scope: %@", candidate];
            return NO;
        }
        [candidateAbsPaths addObject:AbsolutePathForRPCPath(candidate, [_windowController workspacePath]) ?: candidate];
    }
    NSInteger maxFilesTouched = budget[@"maxFilesTouched"] ? [budget[@"maxFilesTouched"] integerValue] : 4;
    NSMutableSet* projectedTouched = [touched mutableCopy];
    for (NSString* candidateAbs in candidateAbsPaths) {
        [projectedTouched addObject:candidateAbs];
    }
    if (projectedTouched.count > (NSUInteger)maxFilesTouched) {
        if (errorOut) *errorOut = @"Task exceeded maxFilesTouched.";
        return NO;
    }
    [touched unionSet:projectedTouched];
    return YES;
}

- (NSDictionary*)serializableTask:(NSMutableDictionary*)task {
    NSMutableDictionary* copy = [task mutableCopy];
    NSMutableArray* touched = [NSMutableArray array];
    for (NSString* pathValue in task[@"filesTouchedSet"] ?: [NSSet set]) {
        [touched addObject:pathValue];
    }
    copy[@"filesTouched"] = touched;
    [copy removeObjectForKey:@"filesTouchedSet"];
    [copy removeObjectForKey:@"startedAtDate"];
    return copy;
}

- (NSDictionary*)primitiveForWorkbenchStep:(NSDictionary*)step {
    NSString* type = step[@"type"] ?: @"";
    if ([type isEqualToString:@"readAround"]) return @{ @"method": @"file.readAround", @"params": step };
    if ([type isEqualToString:@"readRange"]) return @{ @"method": @"file.readRange", @"params": step };
    if ([type isEqualToString:@"searchFiles"]) return @{ @"method": @"search.files", @"params": step };
    if ([type isEqualToString:@"searchText"]) return @{ @"method": @"search.text", @"params": step };
    if ([type isEqualToString:@"patch"]) return @{ @"method": @"patch.apply", @"params": step };
    if ([type isEqualToString:@"patchBatch"]) return @{ @"method": @"patch.applyBatch", @"params": step };
    if ([type isEqualToString:@"verify"]) return @{ @"method": @"verify.run", @"params": step };
    if ([type isEqualToString:@"diffSummary"]) return @{ @"method": @"diff.summary", @"params": @{} };
    if ([type isEqualToString:@"failures"]) return @{ @"method": @"verify.failures", @"params": @{} };
    if ([type isEqualToString:@"contextSnapshot"]) return @{ @"method": @"context.snapshot", @"params": @{} };
    return @{};
}

- (NSDictionary*)executeWorkbenchStep:(NSDictionary*)step task:(NSMutableDictionary*)task {
    if ([step[@"confirm"] boolValue]) {
        return @{ @"ok": @NO, @"error": @{ @"code": @"confirmation_required", @"message": @"Combo steps cannot perform confirmed destructive operations." } };
    }
    NSString* err = nil;
    if (task && ![self task:task canConsumeStep:step error:&err]) {
        return @{ @"ok": @NO, @"error": @{ @"code": @"budget_exceeded", @"message": err ?: @"Task budget rejected step." } };
    }
    NSDictionary* primitive = [self primitiveForWorkbenchStep:step];
    NSString* method = primitive[@"method"];
    if (method.length == 0) {
        return @{ @"ok": @NO, @"error": @{ @"code": @"invalid_params", @"message": @"Unknown step type." } };
    }
    __block NSDictionary* result = nil;
    __block NSString* errCode = nil;
    __block NSString* errMsg = nil;
    __block NSString* paths = @"";
    [self executeMethod:method params:primitive[@"params"] ?: @{} outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&paths];
    if (errCode) {
        return @{ @"ok": @NO, @"method": method, @"error": @{ @"code": errCode, @"message": errMsg ?: @"" } };
    }
    if (task) {
        if ([method isEqualToString:@"patch.apply"] || [method isEqualToString:@"patch.applyBatch"]) {
            task[@"patchBatchesUsed"] = @([task[@"patchBatchesUsed"] integerValue] + 1);
        } else if ([method isEqualToString:@"verify.run"]) {
            task[@"verifyRunsUsed"] = @([task[@"verifyRunsUsed"] integerValue] + 1);
        }
    }
    return @{ @"ok": @YES, @"method": method, @"result": result ?: @{} };
}

- (NSDictionary*)repairContextForFailure:(NSString*)failure params:(NSDictionary*)params {
    NSMutableArray* files = [NSMutableArray array];
    for (NSDictionary* file in params[@"files"] ?: @[]) {
        NSString* path = file[@"path"];
        NSMutableArray* ranges = [NSMutableArray array];
        for (NSDictionary* range in file[@"ranges"] ?: @[]) {
            NSInteger start = [range[@"startLine"] integerValue];
            NSInteger end = [range[@"endLine"] integerValue];
            NSString* text = nil;
            NSString* absPath = AbsolutePathForRPCPath(path, [_windowController workspacePath]);
            NSString* full = [_windowController textForFileAtPath:absPath];
            if (full) text = TextForLineRange(LinesFromText(full), start, end);
            [ranges addObject:@{ @"startLine": @(start), @"endLine": @(end), @"text": text ?: @"" }];
        }
        [files addObject:@{ @"path": path ?: @"", @"ranges": ranges }];
    }
    return @{
        @"failure": failure ?: @"unknown",
        @"files": files,
        @"diagnostics": params[@"diagnostics"] ?: ([_windowController problemsList] ?: @[]),
        @"failures": [self verificationFailureLines]
    };
}

- (NSString*)permissionLevelForMethod:(NSString*)method params:(NSDictionary*)params {
    if ([method isEqualToString:@"git.discard"] ||
        [method isEqualToString:@"git.commit"] ||
        [method isEqualToString:@"changes.revertFile"] ||
        [method isEqualToString:@"workspace.openFolder"]) {
        return @"Destructive";
    }
    
    if ([method isEqualToString:@"editor.applyPatch"]) {
        BOOL confirmParam = [params[@"confirm"] boolValue];
        if (confirmParam) {
            return @"Destructive";
        }
    }
    if ([method isEqualToString:@"patch.apply"] || [method isEqualToString:@"patch.applyBatch"]) {
        if ([params[@"confirm"] boolValue]) {
            return @"Destructive";
        }
    }
    if ([method isEqualToString:@"combo.run"]) {
        NSDictionary* combo = params[@"combo"] ?: params;
        NSDictionary* policy = combo[@"policy"] ?: @{};
        for (NSString* perm in policy[@"permissions"] ?: @[]) {
            if (PermissionRank(perm) >= PermissionRank(@"destructive")) return @"Destructive";
        }
        for (NSDictionary* step in combo[@"steps"] ?: @[]) {
            NSString* chip = [self chipNameForStep:step];
            NSDictionary* meta = [self metadataForChip:chip];
            if (PermissionRank(meta[@"permission"] ?: @"read") >= PermissionRank(@"execute")) return @"Execute";
        }
        return @"Edit";
    }
    
    if ([method isEqualToString:@"terminal.run"]) {
        NSString* cwd = params[@"cwd"];
        NSString* ws = [_windowController workspacePath];
        if (cwd && ws) {
            std::filesystem::path cwdPath(StdStringFromNSString(cwd));
            std::filesystem::path wsPath(StdStringFromNSString(ws));
            auto cwdAbs = std::filesystem::weakly_canonical(cwdPath);
            auto wsAbs = std::filesystem::weakly_canonical(wsPath);
            auto rel = std::filesystem::relative(cwdAbs, wsAbs);
            if (rel.string().rfind("..", 0) == 0) {
                return @"Destructive";
            }
        }
        return @"Execute";
    }
    
    if ([method hasPrefix:@"terminal."] ||
        [method isEqualToString:@"verify.run"] ||
        [method isEqualToString:@"task.runLoop"] ||
        [method isEqualToString:@"edit.executePlan"] ||
        [method isEqualToString:@"combo.run"] ||
        [method isEqualToString:@"language.lint"] ||
        [method isEqualToString:@"language.format"]) {
        return @"Execute";
    }
    
    if ([method isEqualToString:@"editor.insertText"] || 
        [method isEqualToString:@"editor.replaceSelection"] || 
        [method isEqualToString:@"editor.replaceRange"] || 
        [method isEqualToString:@"editor.applyPatch"] || 
        [method isEqualToString:@"patch.apply"] ||
        [method isEqualToString:@"patch.applyBatch"] ||
        [method isEqualToString:@"patch.revertLast"] ||
        [method isEqualToString:@"combo.rollback"] ||
        [method isEqualToString:@"task.step"] ||
        [method isEqualToString:@"git.stage"] || 
        [method isEqualToString:@"git.unstage"] ||
        [method isEqualToString:@"editor.closeFile"] ||
        [method isEqualToString:@"problems.open"] ||
        [method isEqualToString:@"problems.clearSource"] ||
        [method isEqualToString:@"editor.setSelection"]) {
        return @"Edit";
    }
    
    return @"Read";
}

- (void)executeMethod:(NSString*)method 
               params:(NSDictionary*)params 
            outResult:(NSDictionary**)outResult 
           outErrCode:(NSString**)outErrCode 
          outErrMsg:(NSString**)outErrMsg
             outPaths:(NSString**)outPaths {
    
    NSString* path = params[@"path"];
    if (path &&
        ![method isEqualToString:@"workspace.openFolder"] &&
        ![method isEqualToString:@"diff.validatePatch"] &&
        ![method isEqualToString:@"diff.applyPatchPreview"] &&
        ![method isEqualToString:@"patch.validate"] &&
        ![method isEqualToString:@"patch.preview"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* checkedPath = AbsolutePathForRPCPath(path, ws);
        *outPaths = checkedPath;
        if (ws && !PathIsInsideWorkspace(checkedPath, ws)) {
            *outErrCode = @"outside_workspace";
            *outErrMsg = @"Target path is outside active workspace folder.";
            return;
        }
    }

    if ([method isEqualToString:@"rpc.ping"]) {
        *outResult = @{ @"pong": @YES, @"server": @"DietCodeControlServer", @"version": @"1.6" };
        return;
    }

    if ([method isEqualToString:@"rpc.methods"]) {
        NSMutableArray* names = [NSMutableArray array];
        for (NSDictionary* desc in [self rpcMethodDescriptions]) {
            [names addObject:desc[@"name"]];
        }
        *outResult = @{ @"methods": names };
        return;
    }

    if ([method isEqualToString:@"rpc.describe"]) {
        NSString* targetMethod = params[@"method"];
        if (targetMethod.length > 0) {
            NSDictionary* desc = [self descriptionForRPCMethod:targetMethod];
            if (desc.count == 0) {
                *outErrCode = @"method_not_found";
                *outErrMsg = [NSString stringWithFormat:@"The method '%@' is not defined.", targetMethod];
                return;
            }
            *outResult = @{ @"methods": @[desc] };
        } else {
            *outResult = @{ @"methods": [self rpcMethodDescriptions] };
        }
        return;
    }

    if ([method isEqualToString:@"chip.list"]) {
        *outResult = @{ @"schemaVersion": @"1.6", @"chips": [self chipRegistry] };
        return;
    }

    if ([method isEqualToString:@"chip.describe"]) {
        NSString* chip = params[@"chip"];
        NSDictionary* meta = [self metadataForChip:chip];
        if (!meta) {
            *outErrCode = @"unknown_chip";
            *outErrMsg = @"Unknown chip.";
            return;
        }
        *outResult = @{ @"schemaVersion": @"1.6", @"chip": meta };
        return;
    }

    if ([method isEqualToString:@"combo.validate"]) {
        NSDictionary* combo = params[@"combo"] ?: params;
        NSDictionary* plan = nil;
        NSArray<NSDictionary*>* errors = nil;
        BOOL valid = [self validateCombo:combo normalizedPlan:&plan errors:&errors];
        NSMutableDictionary* response = [@{ @"schemaVersion": @"1.6", @"valid": @(valid), @"errors": errors ?: @[] } mutableCopy];
        if (valid && plan) response[@"plan"] = plan;
        *outResult = response;
        return;
    }

    if ([method isEqualToString:@"combo.run"]) {
        if ([self activeComboCount] >= (NSUInteger)kMaxActiveCombos) {
            *outErrCode = @"resource_exhausted";
            *outErrMsg = @"Maximum active combo count reached.";
            return;
        }
        NSDictionary* combo = params[@"combo"] ?: params;
        NSDictionary* plan = nil;
        NSArray<NSDictionary*>* errors = nil;
        BOOL valid = [self validateCombo:combo normalizedPlan:&plan errors:&errors];
        if (!valid) {
            *outErrCode = @"invalid_combo";
            *outErrMsg = @"Combo validation failed.";
            *outResult = @{ @"schemaVersion": @"1.6", @"valid": @NO, @"errors": errors ?: @[] };
            return;
        }
        NSString* comboId = combo[@"comboId"] ?: (params[@"comboId"] ?: [NSString stringWithFormat:@"combo-%ld", (long)++_comboCounter]);
        if (_combos[comboId]) {
            *outErrCode = @"invalid_combo";
            *outErrMsg = @"comboId already exists in this session.";
            return;
        }
        NSDictionary* result = [self runComboWithPlan:plan comboId:comboId];
        *outResult = @{ @"schemaVersion": @"1.6", @"combo": result };
        return;
    }

    if ([method isEqualToString:@"combo.status"] || [method isEqualToString:@"combo.result"]) {
        NSString* comboId = params[@"comboId"];
        NSMutableDictionary* combo = comboId ? _combos[comboId] : nil;
        if (!combo) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown comboId.";
            return;
        }
        *outResult = @{ @"schemaVersion": @"1.6", @"combo": [self serializableCombo:combo] };
        return;
    }

    if ([method isEqualToString:@"combo.cancel"]) {
        NSString* comboId = params[@"comboId"];
        NSMutableDictionary* combo = comboId ? _combos[comboId] : nil;
        if (!combo) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown comboId.";
            return;
        }
        if ([combo[@"status"] isEqualToString:@"running"]) {
            combo[@"status"] = @"cancelled";
            combo[@"cancelledAt"] = ISODateString([NSDate date]);
        }
        *outResult = @{ @"schemaVersion": @"1.6", @"cancelled": @YES, @"combo": [self serializableCombo:combo] };
        return;
    }

    if ([method isEqualToString:@"combo.rollback"]) {
        NSString* comboId = params[@"comboId"];
        BOOL confirm = [params[@"confirm"] boolValue];
        
        if (comboId.length == 0) {
            comboId = _lastComboId;
        }
        
        if (comboId.length == 0) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No session combo transaction is available to roll back.";
            return;
        }
        
        NSString* backupDir = [[NSHomeDirectory() stringByAppendingPathComponent:@".dietcode/backups"] stringByAppendingPathComponent:comboId];
        NSString* manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.json"];
        
        NSString* mErr = nil;
        NSDictionary* manifest = [self loadManifestFromPath:manifestPath error:&mErr];
        if (!manifest) {
            if ([mErr isEqualToString:@"Manifest file missing."]) {
                *outErrCode = @"backup_manifest_missing";
            } else if ([mErr isEqualToString:@"manifest.sha256 file missing."] || [mErr isEqualToString:@"Manifest checksum verification failed."]) {
                *outErrCode = @"backup_corrupt";
            } else {
                *outErrCode = @"backup_manifest_invalid";
            }
            *outErrMsg = mErr ?: @"Manifest missing or invalid.";
            return;
        }
        
        NSString* schemaVersion = manifest[@"schemaVersion"] ?: @"1.6.1";
        if (![schemaVersion isEqualToString:@"1.6.2"]) {
            *outErrCode = @"backup_manifest_invalid";
            *outErrMsg = [NSString stringWithFormat:@"Unsupported schema version '%@'. Rollback is only supported for schema version 1.6.2.", schemaVersion];
            return;
        }
        
        NSString* rollbackErr = nil;
        NSString* rollbackErrorCode = nil;
        BOOL ok = [self restorePatchFromManifest:manifest backupDir:backupDir confirm:confirm error:&rollbackErr errorCode:&rollbackErrorCode];
        if (!ok) {
            *outErrCode = rollbackErrorCode ?: @"rollback_failed";
            *outErrMsg = rollbackErr ?: @"Rollback failed.";
            return;
        }
        
        NSMutableArray* paths = [NSMutableArray array];
        for (NSDictionary* fileEntry in manifest[@"files"] ?: @[]) {
            [paths addObject:fileEntry[@"workspaceRelativePath"] ?: @""];
        }
        *outResult = @{ @"schemaVersion": @"1.6.2", @"reverted": @YES, @"files": paths };
        return;
    }
    
    if ([method isEqualToString:@"recovery.scan"]) {
        NSString* errStr = nil;
        NSDictionary* report = [self performRecoveryScan:&errStr];
        if (errStr) {
            *outErrCode = @"internal_error";
            *outErrMsg = errStr;
            return;
        }
        *outResult = report;
        return;
    }
    
    if ([method isEqualToString:@"workspace.openFolder"]) {
        NSString* targetPath = params[@"path"];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath isDirectory:&isDir] || !isDir) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Target path is not a valid directory.";
            return;
        }
        [_windowController openWorkspaceFolder:targetPath];
        *outResult = @{ @"opened": @YES, @"path": targetPath };
        return;
    }
    
    if ([method isEqualToString:@"workspace.getRoot"]) {
        NSString* root = [_windowController workspacePath] ?: @"";
        *outResult = @{ @"path": root };
        return;
    }
    
    if ([method isEqualToString:@"workspace.listFiles"]) {
        NSString* ws = [_windowController workspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        
        std::string folder = StdStringFromNSString(ws);
        std::vector<std::string> relativePaths;
        std::error_code ec;
        
        int fileCount = 0;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (fileCount >= 1000) break;
            
            std::filesystem::path p = entry.path();
            std::string filename = p.filename().string();
            
            if (filename == ".git" || filename == "build" || filename == "dist" || 
                filename == "node_modules" || filename == "DerivedData") {
                continue;
            }
            
            bool skip = false;
            for (const auto& part : p) {
                std::string partStr = part.string();
                if (partStr == ".git" || partStr == "build" || partStr == "dist" || 
                    partStr == "node_modules" || partStr == "DerivedData") {
                    skip = true;
                    break;
                }
            }
            if (skip) continue;
            
            if (entry.is_regular_file()) {
                auto rel = std::filesystem::relative(p, folder);
                relativePaths.push_back(rel.string());
                fileCount++;
            }
        }
        
        NSMutableArray* filesArr = [NSMutableArray array];
        for (const auto& r : relativePaths) {
            [filesArr addObject:NSStringFromStdString(r)];
        }
        *outResult = @{ @"files": filesArr };
        return;
    }
    
    if ([method isEqualToString:@"workspace.grep"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* query = params[@"query"];
        if (!ws || !query || query.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Query string and workspace required.";
            return;
        }
        
        NSArray* includePatterns = params[@"include"] ?: @[];
        NSArray* excludePatterns = params[@"exclude"] ?: @[];
        BOOL caseSensitive = [params[@"caseSensitive"] boolValue];
        NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 200;
        if (maxResults > kMaxGrepResults) {
            *outErrCode = @"response_too_large";
            *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
            return;
        }
        
        std::string folder = StdStringFromNSString(ws);
        std::string stdQuery = StdStringFromNSString(query);
        NSMutableArray* matches = [NSMutableArray array];
        
        std::error_code ec;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (matches.count >= (NSUInteger)maxResults) break;
            
            if (entry.is_regular_file()) {
                std::filesystem::path p = entry.path();
                std::string filename = p.filename().string();
                std::string relPath = std::filesystem::relative(p, folder).string();
                
                BOOL skip = false;
                for (NSString* ex in excludePatterns) {
                    if (fnmatch([ex UTF8String], relPath.c_str(), FNM_CASEFOLD) == 0 ||
                        fnmatch([ex UTF8String], filename.c_str(), FNM_CASEFOLD) == 0) {
                        skip = true;
                        break;
                    }
                }
                if (filename == ".git" || filename == "node_modules" || filename == "build") skip = true;
                if (skip) continue;
                
                if (includePatterns.count > 0) {
                    BOOL matchesInclude = NO;
                    for (NSString* inc in includePatterns) {
                        if (fnmatch([inc UTF8String], relPath.c_str(), FNM_CASEFOLD) == 0 ||
                            fnmatch([inc UTF8String], filename.c_str(), FNM_CASEFOLD) == 0) {
                            matchesInclude = YES;
                            break;
                        }
                    }
                    if (!matchesInclude) continue;
                }
                
                NSString* readRes = [_windowController textForFileAtPath:NSStringFromStdString(p.string())];
                if (readRes) {
                    std::string content = StdStringFromNSString(readRes);
                    std::istringstream stream(content);
                    std::vector<std::string> fileLines;
                    std::string lineText;
                    while (std::getline(stream, lineText)) {
                        fileLines.push_back(lineText);
                    }

                    for (size_t lineIdx = 0; lineIdx < fileLines.size(); lineIdx++) {
                        lineText = fileLines[lineIdx];
                        size_t matchPos = std::string::npos;
                        if (caseSensitive) {
                            matchPos = lineText.find(stdQuery);
                        } else {
                            std::string lowerLine = lineText;
                            std::transform(lowerLine.begin(), lowerLine.end(), lowerLine.begin(), ::tolower);
                            std::string lowerQuery = stdQuery;
                            std::transform(lowerQuery.begin(), lowerQuery.end(), lowerQuery.begin(), ::tolower);
                            matchPos = lowerLine.find(lowerQuery);
                        }
                        
                        if (matchPos != std::string::npos) {
                            NSInteger lineNumber = (NSInteger)lineIdx + 1;
                            [matches addObject:@{
                                @"path": NSStringFromStdString(relPath),
                                @"line": @(lineNumber),
                                @"column": @(matchPos + 1),
                                @"preview": NSStringFromStdString(lineText),
                                @"contextBefore": ContextLines(fileLines, (NSInteger)lineIdx - 2, (NSInteger)lineIdx - 1),
                                @"contextAfter": ContextLines(fileLines, (NSInteger)lineIdx + 1, (NSInteger)lineIdx + 2)
                            }];
                            if (matches.count >= (NSUInteger)maxResults) break;
                        }
                    }
                }
            }
        }
        *outResult = @{ @"matches": matches };
        return;
    }
    
    if ([method isEqualToString:@"workspace.openFile"]) {
        NSString* absPath = AbsolutePathForRPCPath(params[@"path"], [_windowController workspacePath]);
        if (!absPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        [_windowController openFileAtPath:absPath line:1 column:1];
        *outResult = @{ @"opened": @YES, @"path": absPath };
        return;
    }
    
    if ([method isEqualToString:@"workspace.getRecentFiles"]) {
        NSArray* recents = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"RecentFiles"] ?: @[];
        *outResult = @{ @"files": recents };
        return;
    }

    // Search primitives
    if ([method isEqualToString:@"search.files"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* query = params[@"query"] ?: @"";
        if (!ws || query.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"query and workspace required.";
            return;
        }
        NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 100;
        if (maxResults > kMaxGrepResults) {
            *outErrCode = @"too_many_results";
            *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
            return;
        }
        std::string folder = StdStringFromNSString(ws);
        std::string needle = StdStringFromNSString([query lowercaseString]);
        NSArray* includes = params[@"include"] ?: @[];
        NSArray* excludes = params[@"exclude"] ?: @[];
        NSMutableArray* results = [NSMutableArray array];
        std::error_code ec;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (results.count >= (NSUInteger)maxResults) break;
            if (!entry.is_regular_file()) continue;
            std::filesystem::path p = entry.path();
            std::string relPath = std::filesystem::relative(p, folder).string();
            if (ShouldSkipSearchPath(p, relPath, includes, excludes)) continue;
            std::string lowerRel = relPath;
            std::transform(lowerRel.begin(), lowerRel.end(), lowerRel.begin(), ::tolower);
            size_t pos = lowerRel.find(needle);
            if (pos == std::string::npos) continue;
            double score = pos == 0 ? 1.0 : 0.75;
            if (p.filename().string().find(StdStringFromNSString(query)) != std::string::npos) score += 0.2;
            [results addObject:@{ @"path": NSStringFromStdString(relPath), @"score": @(MIN(score, 1.0)) }];
        }
        *outResult = @{ @"results": results };
        return;
    }

    if ([method isEqualToString:@"search.text"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* query = params[@"query"] ?: @"";
        if (!ws || query.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"query and workspace required.";
            return;
        }
        NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 200;
        if (maxResults > kMaxGrepResults) {
            *outErrCode = @"too_many_results";
            *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
            return;
        }
        NSInteger before = params[@"before"] ? [params[@"before"] integerValue] : 2;
        NSInteger after = params[@"after"] ? [params[@"after"] integerValue] : 2;
        BOOL caseSensitive = [params[@"caseSensitive"] boolValue];
        NSArray* includes = params[@"include"] ?: @[];
        NSArray* excludes = params[@"exclude"] ?: @[];
        std::string folder = StdStringFromNSString(ws);
        std::string needle = StdStringFromNSString(query);
        if (!caseSensitive) std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);
        NSMutableArray* results = [NSMutableArray array];
        std::error_code ec;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (results.count >= (NSUInteger)maxResults) break;
            if (!entry.is_regular_file()) continue;
            std::filesystem::path p = entry.path();
            std::string relPath = std::filesystem::relative(p, folder).string();
            if (ShouldSkipSearchPath(p, relPath, includes, excludes)) continue;
            NSString* text = [_windowController textForFileAtPath:NSStringFromStdString(p.string())];
            if (!text) continue;
            std::vector<std::string> lines;
            std::istringstream stream(StdStringFromNSString(text));
            std::string line;
            while (std::getline(stream, line)) lines.push_back(line);
            for (size_t i = 0; i < lines.size(); i++) {
                std::string haystack = lines[i];
                if (!caseSensitive) std::transform(haystack.begin(), haystack.end(), haystack.begin(), ::tolower);
                size_t pos = haystack.find(needle);
                if (pos == std::string::npos) continue;
                [results addObject:@{
                    @"path": NSStringFromStdString(relPath),
                    @"line": @(i + 1),
                    @"column": @(pos + 1),
                    @"preview": NSStringFromStdString(lines[i]),
                    @"contextBefore": ContextLines(lines, (NSInteger)i - before, (NSInteger)i - 1),
                    @"contextAfter": ContextLines(lines, (NSInteger)i + 1, (NSInteger)i + after)
                }];
                if (results.count >= (NSUInteger)maxResults) break;
            }
        }
        *outResult = @{ @"results": results };
        return;
    }

    if ([method isEqualToString:@"search.todo"]) {
        NSString* workspace = [_windowController workspacePath];
        if (!workspace) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        NSMutableDictionary* todoParams = [params mutableCopy] ?: [NSMutableDictionary dictionary];
        todoParams[@"query"] = @"TODO";
        NSArray* markers = @[@"TODO", @"FIXME", @"HACK", @"NOTE"];
        NSMutableArray* all = [NSMutableArray array];
        for (NSString* marker in markers) {
            NSMutableDictionary* markerParams = [todoParams mutableCopy];
            markerParams[@"query"] = marker;
            markerParams[@"maxResults"] = params[@"maxResults"] ?: @100;
            NSDictionary* subParams = markerParams;
            NSString* ws = workspace;
            NSInteger maxResults = [subParams[@"maxResults"] integerValue];
            if (maxResults > kMaxGrepResults) maxResults = kMaxGrepResults;
            std::string folder = StdStringFromNSString(ws);
            NSArray* includes = subParams[@"include"] ?: @[];
            NSArray* excludes = subParams[@"exclude"] ?: @[];
            std::string needle = StdStringFromNSString([marker lowercaseString]);
            std::error_code ec;
            for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
                if (all.count >= (NSUInteger)maxResults) break;
                if (!entry.is_regular_file()) continue;
                std::filesystem::path p = entry.path();
                std::string relPath = std::filesystem::relative(p, folder).string();
                if (ShouldSkipSearchPath(p, relPath, includes, excludes)) continue;
                NSString* text = [_windowController textForFileAtPath:NSStringFromStdString(p.string())];
                if (!text) continue;
                NSArray<NSString*>* lines = LinesFromText(text);
                for (NSUInteger i = 0; i < lines.count; i++) {
                    NSString* lower = [lines[i] lowercaseString];
                    NSRange r = [lower rangeOfString:NSStringFromStdString(needle)];
                    if (r.location == NSNotFound) continue;
                    [all addObject:@{
                        @"path": NSStringFromStdString(relPath),
                        @"line": @(i + 1),
                        @"column": @(r.location + 1),
                        @"marker": marker,
                        @"preview": lines[i]
                    }];
                    if (all.count >= (NSUInteger)maxResults) break;
                }
            }
        }
        *outResult = @{ @"results": all };
        return;
    }

    if ([method isEqualToString:@"search.diagnostics"]) {
        NSString* severity = [params[@"severity"] lowercaseString];
        NSString* source = params[@"source"];
        NSMutableArray* matches = [NSMutableArray array];
        for (NSDictionary* problem in [_windowController problemsList] ?: @[]) {
            if (severity.length > 0 && ![[problem[@"severity"] lowercaseString] isEqualToString:severity]) continue;
            if (source.length > 0 && ![problem[@"source"] isEqualToString:source]) continue;
            [matches addObject:problem];
        }
        *outResult = @{ @"results": matches };
        return;
    }

    // File reading primitives
    if ([method isEqualToString:@"file.read"] || [method isEqualToString:@"file.readRange"] || [method isEqualToString:@"file.readAround"] || [method isEqualToString:@"file.getChunks"] || [method isEqualToString:@"file.stat"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        NSString* text = [_windowController textForFileAtPath:targetPath];
        if (!text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"File is not readable.";
            return;
        }
        NSArray<NSString*>* lines = LinesFromText(text);
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:targetPath error:nil];
        NSUInteger sizeBytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        BOOL open = [[_windowController openFilePaths] containsObject:targetPath];
        BOOL dirty = [DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]) containsObject:targetPath];
        if ([method isEqualToString:@"file.stat"]) {
            *outResult = @{
                @"path": targetPath,
                @"sizeBytes": @(attrs.fileSize ?: sizeBytes),
                @"lineCount": @(lines.count),
                @"modified": @(attrs.fileModificationDate != nil),
                @"open": @(open),
                @"dirty": @(dirty)
            };
            return;
        }
        if ([method isEqualToString:@"file.read"]) {
            if (sizeBytes > kMaxFileTextBytes) {
                *outErrCode = @"file_too_large";
                *outErrMsg = @"File exceeds read cap; use file.getChunks or file.readRange.";
                return;
            }
            *outResult = @{ @"path": targetPath, @"text": text, @"lineCount": @(lines.count), @"sizeBytes": @(sizeBytes) };
            return;
        }
        if ([method isEqualToString:@"file.readRange"]) {
            NSInteger startLine = [params[@"startLine"] integerValue];
            NSInteger endLine = [params[@"endLine"] integerValue];
            NSString* rangeText = TextForLineRange(lines, startLine, endLine);
            if (!rangeText) {
                *outErrCode = @"invalid_range";
                *outErrMsg = @"Invalid line range.";
                return;
            }
            if ([rangeText lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kMaxFileTextBytes) {
                *outErrCode = @"response_too_large";
                *outErrMsg = @"Requested range exceeds response size cap.";
                return;
            }
            *outResult = @{ @"path": targetPath, @"startLine": @(startLine), @"endLine": @(endLine), @"text": rangeText };
            return;
        }
        if ([method isEqualToString:@"file.readAround"]) {
            NSInteger line = [params[@"line"] integerValue];
            NSInteger before = params[@"before"] ? [params[@"before"] integerValue] : 40;
            NSInteger after = params[@"after"] ? [params[@"after"] integerValue] : 80;
            NSInteger startLine = MAX(1, line - before);
            NSInteger endLine = MIN((NSInteger)lines.count, line + after);
            NSString* rangeText = TextForLineRange(lines, startLine, endLine);
            if (!rangeText || line < 1 || line > (NSInteger)lines.count) {
                *outErrCode = @"invalid_range";
                *outErrMsg = @"Invalid line.";
                return;
            }
            *outResult = @{ @"path": targetPath, @"startLine": @(startLine), @"endLine": @(endLine), @"text": rangeText };
            return;
        }
        if ([method isEqualToString:@"file.getChunks"]) {
            NSInteger chunkSize = params[@"chunkSize"] ? [params[@"chunkSize"] integerValue] : 120;
            if (chunkSize < 20) chunkSize = 20;
            if (chunkSize > 500) chunkSize = 500;
            NSMutableArray* chunks = [NSMutableArray array];
            for (NSInteger start = 1, idx = 0; start <= (NSInteger)lines.count; start += chunkSize, idx++) {
                NSInteger end = MIN(start + chunkSize - 1, (NSInteger)lines.count);
                NSString* preview = TextForLineRange(lines, start, MIN(end, start + 4)) ?: @"";
                if (preview.length > kMaxChunkPreviewLength) {
                    preview = [[preview substringToIndex:kMaxChunkPreviewLength] stringByAppendingString:@"..."];
                }
                [chunks addObject:@{ @"index": @(idx), @"startLine": @(start), @"endLine": @(end), @"preview": preview }];
            }
            *outResult = @{ @"path": targetPath, @"chunks": chunks };
            return;
        }
    }
    
    // Editor commands
    if ([method isEqualToString:@"editor.getActiveFile"]) {
        NSString* active = [_windowController activeFilePath] ?: @"";
        *outResult = @{ @"path": active };
        return;
    }
    
    if ([method isEqualToString:@"editor.getOpenFiles"]) {
        NSArray* list = [_windowController openFilePaths];
        *outResult = @{ @"files": list };
        return;
    }
    
    if ([method isEqualToString:@"editor.getText"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Open document path required.";
            return;
        }
        NSString* text = [_windowController textForFileAtPath:targetPath];
        if (!text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"File is not open and is not in workspace.";
            return;
        }
        NSUInteger textBytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (textBytes > kMaxFileTextBytes && ![params[@"allowLarge"] boolValue]) {
            *outErrCode = @"response_too_large";
            *outErrMsg = @"File text exceeds maximum RPC response size; pass allowLarge=true only when needed.";
            return;
        }
        *outResult = @{ @"text": text };
        return;
    }
    
    if ([method isEqualToString:@"editor.getSelection"]) {
        NSDictionary* sel = [_windowController activeSelectionInfo];
        if (sel.count == 0) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No active editor tab.";
            return;
        }
        *outResult = sel;
        return;
    }
    
    if ([method isEqualToString:@"editor.setSelection"]) {
        NSInteger start = [params[@"start"] integerValue];
        NSInteger end = [params[@"end"] integerValue];
        BOOL ok = [_windowController setActiveSelectionStart:start end:end];
        if (!ok) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Selection range indices out of bounds or no active editor.";
            return;
        }
        *outResult = @{ @"success": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.insertText"]) {
        NSString* text = params[@"text"];
        if (!text) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"text parameter required.";
            return;
        }
        BOOL ok = [_windowController insertTextAtActiveCursor:text];
        if (!ok) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"Failed to insert text in active editor buffer.";
            return;
        }
        *outResult = @{ @"inserted": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.replaceSelection"]) {
        NSString* text = params[@"text"];
        if (!text) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"text parameter required.";
            return;
        }
        BOOL ok = [_windowController replaceActiveSelectionWithText:text];
        if (!ok) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"Failed to replace selection.";
            return;
        }
        *outResult = @{ @"replaced": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.replaceRange"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        NSString* text = params[@"text"];
        NSInteger start = [params[@"start"] integerValue];
        NSInteger end = [params[@"end"] integerValue];
        if (!targetPath || !text || start < 0 || end < start) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path, text, start, and end parameters required.";
            return;
        }
        NSRange range = NSMakeRange(start, end - start);
        BOOL ok = [self safeReplaceTextInRange:range withText:text forFileAtPath:targetPath];
        if (!ok) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"Range is out of bounds or file is read-only.";
            return;
        }
        *outResult = @{ @"replaced": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.applyPatch"]) {
        NSString* targetPath = params[@"path"];
        NSString* patchStr = params[@"patch"];
        if (!targetPath || !patchStr) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSDictionary* validation = [self validatePatchAtPath:targetPath patch:patchStr currentText:nil];
        if (![validation[@"ok"] boolValue]) {
            *outErrCode = @"patch_failed";
            *outErrMsg = validation[@"rejectedReason"] ?: @"Patch validation failed.";
            return;
        }
        if ([validation[@"requiresConfirmation"] boolValue] && ![params[@"confirm"] boolValue]) {
            *outErrCode = @"confirmation_required";
            *outErrMsg = @"Patch is large or high impact; call diff.validatePatch and retry with confirm=true after review.";
            return;
        }
        NSString* ws = [_windowController workspacePath];
        NSString* absPath = AbsolutePathForRPCPath(targetPath, ws);
        NSString* beforeText = [_windowController textForFileAtPath:absPath];
        NSString* errStr = nil;
        BOOL ok = [_windowController applyPatchAtPath:absPath patchString:patchStr errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"patch_failed";
            *outErrMsg = errStr ?: @"Unknown patch application error.";
            return;
        }
        [self recordLastRPCPatchPaths:@[@{ @"path": absPath, @"beforeText": beforeText ?: @"" }]];
        *outResult = @{ @"patched": @YES, @"validation": validation };
        return;
    }
    
    if ([method isEqualToString:@"editor.saveFile"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Open document path required.";
            return;
        }
        [_windowController saveFileAtPath:targetPath];
        *outResult = @{ @"saved": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.closeFile"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Open document path required.";
            return;
        }
        [_windowController closeFileAtPath:targetPath];
        *outResult = @{ @"closed": @YES };
        return;
    }
    
    if ([method isEqualToString:@"editor.goto"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        NSInteger line = [params[@"line"] integerValue];
        NSInteger col = params[@"column"] ? [params[@"column"] integerValue] : 1;
        if (!targetPath || line <= 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and line parameters required.";
            return;
        }
        [_windowController openFileAtPath:targetPath line:line column:col];
        *outResult = @{ @"navigated": @YES };
        return;
    }
    
    // Analysis commands
    if ([method isEqualToString:@"analysis.workspaceSummary"]) {
        NSString* ws = [_windowController workspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }

        NSDictionary* git = [_windowController gitStatusInfo] ?: @{};
        NSMutableArray* modified = [NSMutableArray arrayWithArray:DirtyFilePathsFromTabs(_windowController.openTabs ?: @[])];
        for (NSString* key in @[@"modified", @"staged", @"untracked"]) {
            for (NSString* rel in git[key] ?: @[]) {
                NSString* abs = AbsolutePathForRPCPath(rel, ws);
                if (![modified containsObject:abs]) {
                    [modified addObject:abs];
                }
            }
        }

        NSArray* problems = [_windowController problemsList] ?: @[];
        *outResult = [DietCodeWorkspaceAnalysisService summaryOfWorkspace:ws
                                                                 openFiles:[_windowController openFilePaths]
                                                             modifiedFiles:modified
                                                               diagnostics:DiagnosticsSummaryFromProblems(problems)
                                                                 gitBranch:git[@"branch"]];
        return;
    }

    if ([method isEqualToString:@"analysis.searchRanked"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* query = params[@"query"];
        if (!ws || query.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Query string and workspace required.";
            return;
        }
        if (![_windowController.sessionLastSearches containsObject:query]) {
            [_windowController.sessionLastSearches insertObject:query atIndex:0];
            if (_windowController.sessionLastSearches.count > 50) {
                [_windowController.sessionLastSearches removeLastObject];
            }
        }

        NSInteger requestedMax = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : kMaxGrepResults;
        if (requestedMax > kMaxGrepResults) {
            *outErrCode = @"response_too_large";
            *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
            return;
        }
        NSArray* ranked = [DietCodeWorkspaceAnalysisService searchRankedForQuery:query
                                                                       workspace:ws
                                                                       openFiles:[_windowController openFilePaths]
                                                                     recentFiles:[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"RecentFiles"] ?: @[]
                                                                         include:params[@"include"] ?: @[]
                                                                         exclude:params[@"exclude"] ?: @[]
                                                                   caseSensitive:[params[@"caseSensitive"] boolValue]];
        NSInteger maxResults = MIN(requestedMax, (NSInteger)ranked.count);
        if (maxResults >= 0 && maxResults < (NSInteger)ranked.count) {
            ranked = [ranked subarrayWithRange:NSMakeRange(0, (NSUInteger)maxResults)];
        }
        *outResult = @{ @"results": ranked };
        return;
    }

    if ([method isEqualToString:@"analysis.fileSummary"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSString* text = [_windowController textForFileAtPath:targetPath] ?: @"";
        NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[targetPath pathExtension] lowercaseString]];
        *outResult = [DietCodeWorkspaceAnalysisService fileSummaryForPath:targetPath symbolsCount:symbols.count];
        return;
    }

    if ([method isEqualToString:@"analysis.relatedFiles"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        if (!ws || !targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Workspace and path required.";
            return;
        }
        *outResult = @{ @"files": [DietCodeWorkspaceAnalysisService relatedFilesForPath:targetPath workspace:ws] };
        return;
    }

    // Symbol commands
    if ([method isEqualToString:@"symbols.document"] || [method isEqualToString:@"symbols.outline"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSString* text = [_windowController textForFileAtPath:targetPath];
        if (!text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"File is not readable.";
            return;
        }
        *outResult = @{
            @"path": targetPath,
            @"symbols": [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[targetPath pathExtension] lowercaseString]]
        };
        return;
    }

    if ([method isEqualToString:@"symbols.activeDocument"]) {
        NSString* targetPath = [_windowController activeFilePath];
        NSString* text = targetPath ? [_windowController textForFileAtPath:targetPath] : nil;
        if (!targetPath || !text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No active readable file.";
            return;
        }
        *outResult = @{
            @"path": targetPath,
            @"symbols": [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[targetPath pathExtension] lowercaseString]]
        };
        return;
    }

    if ([method isEqualToString:@"symbols.references"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* symbol = params[@"symbol"];
        if (!ws || symbol.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"symbol and workspace required.";
            return;
        }
        NSArray* problems = [_windowController problemsList] ?: @[];
        NSMutableArray* diagFiles = [NSMutableArray array];
        for (NSDictionary* problem in problems) {
            NSString* abs = AbsolutePathForRPCPath(problem[@"path"], ws);
            if (abs.length > 0 && ![diagFiles containsObject:abs]) {
                [diagFiles addObject:abs];
            }
        }
        *outResult = @{
            @"symbol": symbol,
            @"references": [DietCodeSymbolIndexService referencesForSymbol:symbol
                                                                inWorkspace:ws
                                                                  openFiles:[_windowController openFilePaths]
                                                           diagnosticsFiles:diagFiles]
        };
        return;
    }

    if ([method isEqualToString:@"symbols.atCursor"]) {
        NSDictionary* sel = [_windowController activeSelectionInfo];
        NSString* targetPath = [_windowController activeFilePath];
        NSString* text = targetPath ? [_windowController textForFileAtPath:targetPath] : nil;
        if (!targetPath || !text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No active readable file.";
            return;
        }
        NSInteger cursor = [sel[@"start"] integerValue];
        NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[targetPath pathExtension] lowercaseString]];
        __block NSDictionary* match = @{};
        NSInteger currentLine = 1;
        NSUInteger boundedCursor = MIN((NSUInteger)MAX(cursor, 0), text.length);
        for (NSUInteger i = 0; i < boundedCursor; i++) {
            if ([text characterAtIndex:i] == '\n') currentLine++;
        }
        for (NSDictionary* symbolInfo in symbols) {
            NSInteger startLine = [symbolInfo[@"line"] integerValue];
            NSInteger endLine = [symbolInfo[@"endLine"] integerValue];
            if (currentLine >= startLine && currentLine <= endLine) {
                match = symbolInfo;
                break;
            }
        }
        *outResult = @{ @"path": targetPath, @"symbol": match };
        return;
    }

    // Diff commands
    if ([method isEqualToString:@"diff.workspaceInfo"] || [method isEqualToString:@"diff.stats"]) {
        NSString* ws = [_windowController workspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        *outResult = [DietCodeDiffAnalysisService workspaceDiffInfo:ws];
        return;
    }

    if ([method isEqualToString:@"diff.file"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: @"", ws);
        NSString* diff = [_windowController gitDiffForFile:targetPath];
        *outResult = @{ @"path": targetPath ?: @"", @"diff": diff ?: @"" };
        return;
    }

    if ([method isEqualToString:@"diff.current"]) {
        NSString* ws = [_windowController workspacePath] ?: @"";
        *outResult = @{
            @"changes": [self currentChangesInfo],
            @"unstagedDiff": RunGitOutput(ws, @[@"diff"]),
            @"stagedDiff": RunGitOutput(ws, @[@"diff", @"--cached"]),
            @"unsavedBuffers": [DietCodeBufferStateService snapshotForTabs:_windowController.openTabs ?: @[]]
        };
        return;
    }

    if ([method isEqualToString:@"diff.staged"]) {
        *outResult = @{ @"diff": RunGitOutput([_windowController workspacePath] ?: @"", @[@"diff", @"--cached"]) };
        return;
    }

    if ([method isEqualToString:@"diff.unstaged"]) {
        *outResult = @{ @"diff": RunGitOutput([_windowController workspacePath] ?: @"", @[@"diff"]) };
        return;
    }

    if ([method isEqualToString:@"diff.summary"]) {
        NSDictionary* changes = [self currentChangesInfo];
        *outResult = @{
            @"filesChanged": @([changes[@"modifiedFiles"] count]),
            @"addedLines": changes[@"totalAdded"] ?: @0,
            @"removedLines": changes[@"totalDeleted"] ?: @0,
            @"stagedFiles": @([changes[@"stagedFiles"] count]),
            @"unstagedFiles": @([changes[@"unstagedFiles"] count]),
            @"untrackedFiles": @([changes[@"untrackedFiles"] count])
        };
        return;
    }

    if ([method isEqualToString:@"diff.validatePatch"] || [method isEqualToString:@"diff.applyPatchPreview"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSDictionary* validation = [self validatePatchAtPath:targetPath patch:patchStr currentText:params[@"currentText"]];
        *outResult = @{ @"validation": validation };
        return;
    }

    if ([method isEqualToString:@"diff.previewPatch"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSString* currentText = params[@"currentText"] ?: [_windowController textForFileAtPath:targetPath];
        if (!currentText) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"File is not readable.";
            return;
        }
        NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:currentText extension:[[targetPath pathExtension] lowercaseString]];
        *outResult = [DietCodeDiffAnalysisService previewPatchAtPath:targetPath patch:patchStr currentText:currentText symbols:symbols];
        return;
    }

    // Patch primitives
    if ([method isEqualToString:@"patch.validate"] || [method isEqualToString:@"patch.preview"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        if ([patchStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > kMaxPatchBytes) {
            *outErrCode = @"patch_failed";
            *outErrMsg = @"Patch exceeds maximum RPC patch size.";
            return;
        }
        NSDictionary* validation = [self validatePatchAtPath:targetPath patch:patchStr currentText:params[@"currentText"]];
        NSDictionary* preview = PatchPreviewSummary(patchStr);
        if ([method isEqualToString:@"patch.validate"]) {
            *outResult = @{
                @"path": targetPath,
                @"applies": validation[@"patchAppliesCleanly"] ?: @NO,
                @"changedLines": validation[@"changedLineCount"] ?: @0,
                @"hunks": @([validation[@"affectedHunks"] count]),
                @"requiresConfirmation": validation[@"requiresConfirmation"] ?: @NO,
                @"validation": validation
            };
        } else {
            NSMutableDictionary* result = [preview mutableCopy];
            result[@"path"] = targetPath;
            result[@"validation"] = validation;
            *outResult = result;
        }
        return;
    }

    if ([method isEqualToString:@"patch.apply"]) {
        NSString* targetPath = params[@"path"];
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSDictionary* validation = [self validatePatchAtPath:targetPath patch:patchStr currentText:nil];
        if (![validation[@"ok"] boolValue]) {
            *outErrCode = @"patch_failed";
            *outErrMsg = validation[@"rejectedReason"] ?: @"Patch validation failed.";
            return;
        }
        if ([validation[@"requiresConfirmation"] boolValue] && ![params[@"confirm"] boolValue]) {
            *outErrCode = @"confirmation_required";
            *outErrMsg = @"Patch requires confirmation.";
            return;
        }
        NSString* ws = [_windowController workspacePath];
        NSString* absPath = AbsolutePathForRPCPath(targetPath, ws);
        NSString* beforeText = [_windowController textForFileAtPath:absPath];
        NSString* errStr = nil;
        BOOL ok = [_windowController applyPatchAtPath:absPath patchString:patchStr errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"patch_failed";
            *outErrMsg = errStr ?: @"Unknown patch application error.";
            return;
        }
        NSString* afterText = [_windowController textForFileAtPath:absPath] ?: @"";
        [self recordLastRPCPatchPaths:@[@{ @"path": absPath, @"beforeText": beforeText ?: @"", @"beforeHash": StableHashForString(beforeText ?: @""), @"postHash": StableHashForString(afterText) }]];
        *outResult = @{ @"patched": @YES, @"path": absPath, @"validation": validation };
        return;
    }

    if ([method isEqualToString:@"patch.applyBatch"]) {
        NSArray* patches = params[@"patches"];
        BOOL dryRun = params[@"dryRun"] ? [params[@"dryRun"] boolValue] : YES;
        if (![patches isKindOfClass:[NSArray class]] || patches.count == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"patches array required.";
            return;
        }
        if (patches.count > (NSUInteger)kMaxBatchPatchCount) {
            *outErrCode = @"too_many_results";
            *outErrMsg = [NSString stringWithFormat:@"Batch patch count exceeds limit of %ld.", (long)kMaxBatchPatchCount];
            return;
        }
        NSString* ws = [_windowController workspacePath];
        NSUInteger combinedBytes = 0;
        NSMutableArray* results = [NSMutableArray array];
        NSMutableArray* records = [NSMutableArray array];
        BOOL needsConfirm = NO;
        for (NSDictionary* item in patches) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"Each batch patch must be an object.";
                return;
            }
            NSString* relPath = item[@"path"];
            NSString* patchStr = item[@"patch"];
            if (relPath.length == 0 || patchStr.length == 0) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"Each batch patch requires path and patch.";
                return;
            }
            NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
            combinedBytes += [patchStr lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSDictionary* validation = [self validatePatchAtPath:absPath patch:patchStr currentText:nil];
            if ([validation[@"requiresConfirmation"] boolValue]) needsConfirm = YES;
            [results addObject:@{ @"path": absPath ?: @"", @"validation": validation }];
            if (![validation[@"ok"] boolValue]) {
                *outResult = @{ @"dryRun": @(dryRun), @"applied": @NO, @"results": results };
                return;
            }
            NSString* beforeText = [_windowController textForFileAtPath:absPath];
            [records addObject:@{ @"path": absPath ?: @"", @"beforeText": beforeText ?: @"", @"beforeHash": StableHashForString(beforeText ?: @""), @"patch": patchStr ?: @"" }];
        }
        if ((combinedBytes > kMaxPatchBytesBeforeConfirmation || needsConfirm) && ![params[@"confirm"] boolValue]) {
            *outErrCode = @"confirmation_required";
            *outErrMsg = @"Batch patch requires confirmation.";
            return;
        }
        if (dryRun) {
            *outResult = @{ @"dryRun": @YES, @"applied": @NO, @"results": results };
            return;
        }
        NSMutableArray* applied = [NSMutableArray array];
        for (NSDictionary* record in records) {
            NSString* errStr = nil;
            BOOL ok = [_windowController applyPatchAtPath:record[@"path"] patchString:record[@"patch"] errorOut:&errStr];
            if (!ok) {
                NSString* restoreErr = nil;
                [self restorePatchRecords:applied error:&restoreErr];
                *outErrCode = @"patch_failed";
                *outErrMsg = errStr ?: restoreErr ?: @"Batch patch failed.";
                return;
            }
            NSMutableDictionary* appliedRecord = [record mutableCopy];
            NSString* afterText = [_windowController textForFileAtPath:record[@"path"]] ?: @"";
            appliedRecord[@"postHash"] = StableHashForString(afterText);
            [applied addObject:appliedRecord];
        }
        [self recordLastRPCPatchPaths:applied];
        *outResult = @{ @"dryRun": @NO, @"applied": @YES, @"results": results };
        return;
    }

    if ([method isEqualToString:@"patch.revertLast"]) {
        if (_lastRPCPatchRecords.count == 0) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No RPC patch available to revert.";
            return;
        }
        NSString* errStr = nil;
        BOOL ok = [self restorePatchRecords:_lastRPCPatchRecords error:&errStr];
        if (!ok) {
            *outErrCode = [errStr hasPrefix:@"Rollback conflict"] ? @"rollback_conflict" : @"rollback_failed";
            *outErrMsg = errStr ?: @"Failed to revert last RPC patch.";
            return;
        }
        NSMutableArray* paths = [NSMutableArray array];
        for (NSDictionary* record in _lastRPCPatchRecords) {
            [paths addObject:record[@"path"] ?: @""];
        }
        [_lastRPCPatchRecords removeAllObjects];
        *outResult = @{ @"reverted": @YES, @"files": paths };
        return;
    }

    // Buffer commands
    if ([method isEqualToString:@"buffers.snapshot"]) {
        *outResult = @{ @"buffers": [DietCodeBufferStateService snapshotForTabs:_windowController.openTabs ?: @[]] };
        return;
    }

    if ([method isEqualToString:@"buffers.dirty"]) {
        *outResult = @{ @"files": DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]) };
        return;
    }

    if ([method isEqualToString:@"buffers.active"]) {
        NSString* pathValue = [_windowController activeFilePath] ?: @"";
        NSDictionary* selection = [_windowController activeSelectionInfo] ?: @{};
        *outResult = @{ @"path": pathValue, @"selection": selection };
        return;
    }

    if ([method isEqualToString:@"buffers.unsavedDiff"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        NSString* diff = @"";
        for (id tab in _windowController.openTabs ?: @[]) {
            if ([[tab valueForKey:@"path"] isEqualToString:targetPath]) {
                diff = [DietCodeBufferStateService unsavedDiffForTab:tab];
                break;
            }
        }
        *outResult = @{ @"path": targetPath ?: @"", @"diff": diff ?: @"" };
        return;
    }

    // Diagnostics commands
    if ([method isEqualToString:@"diagnostics.list"]) {
        NSArray* problems = [_windowController problemsList] ?: @[];
        *outResult = @{ @"diagnostics": problems };
        return;
    }

    if ([method isEqualToString:@"diagnostics.summary"]) {
        NSArray* problems = [_windowController problemsList] ?: @[];
        *outResult = DiagnosticsSummaryFromProblems(problems);
        return;
    }

    if ([method isEqualToString:@"diagnostics.cluster"]) {
        NSArray* problems = [_windowController problemsList] ?: @[];
        *outResult = @{ @"clusters": ClusterDiagnostics(problems) };
        return;
    }

    if ([method isEqualToString:@"diagnostics.forFile"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowController activeFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSMutableArray* matches = [NSMutableArray array];
        for (NSDictionary* problem in [_windowController problemsList] ?: @[]) {
            NSString* problemPath = AbsolutePathForRPCPath(problem[@"path"], ws);
            if ([problemPath isEqualToString:targetPath]) {
                [matches addObject:problem];
            }
        }
        *outResult = @{ @"path": targetPath, @"diagnostics": matches };
        return;
    }

    // Change set commands
    if ([method isEqualToString:@"changes.current"]) {
        *outResult = [self currentChangesInfo];
        return;
    }

    if ([method isEqualToString:@"changes.summary"]) {
        NSDictionary* changes = [self currentChangesInfo];
        *outResult = @{
            @"summary": @{
                @"modifiedFileCount": @([changes[@"modifiedFiles"] count]),
                @"unsavedBufferCount": @([changes[@"unsavedBuffers"] count]),
                @"stagedFileCount": @([changes[@"stagedFiles"] count]),
                @"unstagedFileCount": @([changes[@"unstagedFiles"] count]),
                @"untrackedFileCount": @([changes[@"untrackedFiles"] count]),
                @"totalAdded": changes[@"totalAdded"] ?: @0,
                @"totalDeleted": changes[@"totalDeleted"] ?: @0
            },
            @"changes": changes
        };
        return;
    }

    if ([method isEqualToString:@"changes.revertFile"]) {
        NSString* ws = [_windowController workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        BOOL ok = [_windowController gitDiscardFile:targetPath];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = @"Failed to revert file.";
            return;
        }
        *outResult = @{ @"reverted": @YES, @"path": targetPath };
        return;
    }

    // Session workflow commands
    if ([method isEqualToString:@"session.info"] || [method isEqualToString:@"session.workflowState"]) {
        NSString* ws = [_windowController workspacePath] ?: @"";
        NSDictionary* git = [_windowController gitStatusInfo] ?: @{};
        *outResult = @{
            @"workspace": ws,
            @"activeFile": [_windowController activeFilePath] ?: @"",
            @"openFiles": [_windowController openFilePaths] ?: @[],
            @"dirtyFiles": DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]),
            @"gitBranch": git[@"branch"] ?: @"",
            @"recentCommands": _windowController.sessionRecentCommands ?: @[],
            @"lastSearches": _windowController.sessionLastSearches ?: @[],
            @"terminalPid": @([_windowController terminalPid])
        };
        return;
    }

    if ([method isEqualToString:@"session.recentCommands"]) {
        *outResult = @{ @"commands": _windowController.sessionRecentCommands ?: @[] };
        return;
    }

    if ([method isEqualToString:@"session.lastSearches"]) {
        *outResult = @{ @"searches": _windowController.sessionLastSearches ?: @[] };
        return;
    }

    if ([method isEqualToString:@"session.clearHistory"]) {
        [_windowController.sessionRecentCommands removeAllObjects];
        [_windowController.sessionLastSearches removeAllObjects];
        *outResult = @{ @"cleared": @YES };
        return;
    }

    // Verification commands
    if ([method isEqualToString:@"verify.run"]) {
        NSString* command = params[@"command"] ?: @"";
        NSSet* allowed = [NSSet setWithArray:@[@"make test", @"make app", @"git diff --check"]];
        if (![allowed containsObject:command]) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"verify.run command must be one of: make test, make app, git diff --check.";
            return;
        }
        NSString* ws = [self safeWorkspacePath];
        NSString* cwd = params[@"cwd"] ?: ws;
        if (cwd.length > 0 && ws && !PathIsInsideWorkspace(cwd, ws)) {
            *outErrCode = @"outside_workspace";
            *outErrMsg = @"verify.run cwd must be inside workspace.";
            return;
        }
        NSDictionary* result = [self runVerificationCommand:command cwd:cwd];
        *outResult = result;
        return;
    }

    if ([method isEqualToString:@"verify.last"] || [method isEqualToString:@"verify.status"]) {
        NSDictionary* status = [self verificationStatus];
        if ([method isEqualToString:@"verify.last"]) {
            *outResult = @{
                @"command": status[@"command"] ?: @"",
                @"exitCode": status[@"exitCode"] ?: [NSNull null],
                @"startedAt": status[@"startedAt"] ?: @"",
                @"finishedAt": status[@"finishedAt"] ?: @"",
                @"durationMs": status[@"durationMs"] ?: @0,
                @"status": status
            };
        } else {
            *outResult = @{ @"command": _lastVerifyCommand ?: @"", @"status": status };
        }
        return;
    }

    if ([method isEqualToString:@"verify.failures"]) {
        *outResult = @{
            @"failures": [self verificationFailureLines],
            @"problems": [_windowController problemsList] ?: @[],
            @"status": [self verificationStatus]
        };
        return;
    }

    // Context primitives
    if ([method isEqualToString:@"context.snapshot"]) {
        NSDictionary* snapshot = [self contextSnapshotPayload];
        NSString* snapshotId = [NSString stringWithFormat:@"snapshot-%ld", (long)++_contextSnapshotCounter];
        _contextSnapshots[snapshotId] = snapshot;
        *outResult = @{ @"snapshotId": snapshotId, @"snapshot": snapshot };
        return;
    }

    if ([method isEqualToString:@"context.delta"]) {
        NSString* snapshotId = params[@"snapshotId"];
        NSDictionary* previous = snapshotId ? _contextSnapshots[snapshotId] : nil;
        if (!previous) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown snapshotId.";
            return;
        }
        NSDictionary* current = [self contextSnapshotPayload];
        NSMutableDictionary* changed = [NSMutableDictionary dictionary];
        for (NSString* key in current) {
            id oldValue = previous[key];
            id newValue = current[key];
            if (![oldValue isEqual:newValue]) {
                changed[key] = @{ @"before": oldValue ?: [NSNull null], @"after": newValue ?: [NSNull null] };
            }
        }
        *outResult = @{ @"snapshotId": snapshotId, @"changed": changed, @"current": current };
        return;
    }

    // Bounded combo primitives
    if ([method isEqualToString:@"task.start"]) {
        NSString* goal = params[@"goal"] ?: @"";
        if (goal.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"goal parameter required.";
            return;
        }
        NSString* taskId = [NSString stringWithFormat:@"task-%ld", (long)++_taskCounter];
        NSMutableDictionary* task = [@{
            @"taskId": taskId,
            @"goal": goal,
            @"scope": params[@"scope"] ?: @{},
            @"budget": params[@"budget"] ?: @{},
            @"verify": params[@"verify"] ?: @[],
            @"status": @"active",
            @"startedAt": ISODateString([NSDate date]),
            @"steps": [NSMutableArray array],
            @"results": [NSMutableArray array],
            @"patchBatchesUsed": @0,
            @"verifyRunsUsed": @0,
            @"filesTouched": [NSMutableArray array]
        } mutableCopy];
        task[@"startedAtDate"] = [NSDate date];
        task[@"filesTouchedSet"] = [NSMutableSet set];
        _tasks[taskId] = task;
        *outResult = @{ @"taskId": taskId, @"task": [self serializableTask:task] };
        return;
    }

    if ([method isEqualToString:@"task.status"] || [method isEqualToString:@"task.result"]) {
        NSString* taskId = params[@"taskId"];
        NSMutableDictionary* task = taskId ? _tasks[taskId] : nil;
        if (!task) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown taskId.";
            return;
        }
        NSDictionary* snapshot = [self serializableTask:task];
        *outResult = [method isEqualToString:@"task.result"] ? @{ @"result": snapshot, @"finalDiff": [self currentChangesInfo], @"verify": [self verificationStatus] } : @{ @"task": snapshot };
        return;
    }

    if ([method isEqualToString:@"task.cancel"]) {
        NSString* taskId = params[@"taskId"];
        NSMutableDictionary* task = taskId ? _tasks[taskId] : nil;
        if (!task) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown taskId.";
            return;
        }
        task[@"status"] = @"cancelled";
        task[@"cancelledAt"] = ISODateString([NSDate date]);
        *outResult = @{ @"cancelled": @YES, @"task": [self serializableTask:task] };
        return;
    }

    if ([method isEqualToString:@"task.step"]) {
        NSString* taskId = params[@"taskId"];
        NSMutableDictionary* task = taskId ? _tasks[taskId] : nil;
        NSDictionary* step = params[@"step"];
        if (!task || ![step isKindOfClass:[NSDictionary class]]) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"taskId and step object required.";
            return;
        }
        NSDictionary* stepResult = [self executeWorkbenchStep:step task:task];
        [task[@"steps"] addObject:step];
        [task[@"results"] addObject:stepResult];
        if (![stepResult[@"ok"] boolValue]) {
            task[@"status"] = @"blocked";
        }
        *outResult = @{ @"stepResult": stepResult, @"task": [self serializableTask:task] };
        return;
    }

    if ([method isEqualToString:@"task.runLoop"]) {
        NSString* taskId = params[@"taskId"];
        NSMutableDictionary* task = taskId ? _tasks[taskId] : nil;
        NSArray* steps = params[@"steps"] ?: @[];
        if (!task || ![steps isKindOfClass:[NSArray class]] || steps.count > kMaxPlanSteps) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"taskId and bounded steps array required.";
            return;
        }
        NSMutableArray* results = [NSMutableArray array];
        for (NSDictionary* step in steps) {
            if (![step isKindOfClass:[NSDictionary class]]) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"Every runLoop step must be an object.";
                return;
            }
            NSDictionary* stepResult = [self executeWorkbenchStep:step task:task];
            [task[@"steps"] addObject:step];
            [task[@"results"] addObject:stepResult];
            [results addObject:stepResult];
            if (![stepResult[@"ok"] boolValue]) {
                task[@"status"] = @"blocked";
                break;
            }
            if ([step[@"type"] isEqualToString:@"verify"]) {
                NSDictionary* status = [self verificationStatus];
                if ([status[@"state"] isEqualToString:@"complete"] && ![status[@"passed"] boolValue]) {
                    task[@"status"] = @"verify_failed";
                    break;
                }
            }
        }
        if ([task[@"status"] isEqualToString:@"active"]) {
            task[@"status"] = @"complete";
            task[@"completedAt"] = ISODateString([NSDate date]);
        }
        *outResult = @{ @"results": results, @"task": [self serializableTask:task], @"finalDiff": [self currentChangesInfo], @"verify": [self verificationStatus] };
        return;
    }

    if ([method isEqualToString:@"edit.plan"]) {
        NSArray* steps = params[@"steps"];
        if (![steps isKindOfClass:[NSArray class]] || steps.count == 0 || steps.count > kMaxPlanSteps) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"steps array required and must be bounded.";
            return;
        }
        for (NSDictionary* step in steps) {
            if (![step isKindOfClass:[NSDictionary class]] || [self primitiveForWorkbenchStep:step].count == 0) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"Plan contains unknown step type.";
                return;
            }
        }
        NSString* planId = [NSString stringWithFormat:@"plan-%ld", (long)++_editPlanCounter];
        NSDictionary* plan = @{ @"planId": planId, @"steps": steps, @"createdAt": ISODateString([NSDate date]) };
        _editPlans[planId] = plan;
        *outResult = @{ @"planId": planId, @"plan": plan };
        return;
    }

    if ([method isEqualToString:@"edit.executePlan"]) {
        NSString* planId = params[@"planId"];
        NSDictionary* plan = planId ? _editPlans[planId] : nil;
        NSArray* steps = params[@"steps"] ?: plan[@"steps"];
        NSString* taskId = params[@"taskId"];
        NSMutableDictionary* task = taskId ? _tasks[taskId] : nil;
        if (![steps isKindOfClass:[NSArray class]] || steps.count == 0 || steps.count > kMaxPlanSteps) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"planId or bounded steps array required.";
            return;
        }
        NSMutableArray* results = [NSMutableArray array];
        for (NSDictionary* step in steps) {
            NSDictionary* stepResult = [self executeWorkbenchStep:step task:task];
            [results addObject:stepResult];
            if (task) {
                [task[@"steps"] addObject:step];
                [task[@"results"] addObject:stepResult];
            }
            if (![stepResult[@"ok"] boolValue]) break;
        }
        *outResult = @{ @"results": results, @"finalDiff": [self currentChangesInfo], @"verify": [self verificationStatus] };
        return;
    }

    if ([method isEqualToString:@"repair.fromCompilerErrors"] ||
        [method isEqualToString:@"repair.fromTestFailures"] ||
        [method isEqualToString:@"repair.fromPatchFailure"]) {
        NSString* failure = @"patch";
        if ([method isEqualToString:@"repair.fromCompilerErrors"]) failure = @"compiler";
        else if ([method isEqualToString:@"repair.fromTestFailures"]) failure = @"test";
        *outResult = [self repairContextForFailure:failure params:params];
        return;
    }

    // Terminal commands
    if ([method isEqualToString:@"terminal.status"]) {
        pid_t pid = [_windowController terminalPid];
        *outResult = @{
            @"pid": @(pid),
            @"running": @(pid > 0),
            @"outputLength": @(([_windowController terminalOutput] ?: @"").length)
        };
        return;
    }

    if ([method isEqualToString:@"terminal.jobs"]) {
        pid_t pid = [_windowController terminalPid];
        NSArray* jobs = pid > 0 ? @[@{ @"id": @"terminal", @"pid": @(pid), @"status": @"running" }] : @[];
        *outResult = @{ @"jobs": jobs };
        return;
    }

    if ([method isEqualToString:@"terminal.history"]) {
        *outResult = @{ @"commands": _windowController.sessionRecentCommands ?: @[] };
        return;
    }

    if ([method isEqualToString:@"terminal.run"]) {
        NSString* command = params[@"command"];
        if (!command) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"command string required.";
            return;
        }
        NSString* cwd = params[@"cwd"];
        BOOL show = params[@"show"] ? [params[@"show"] boolValue] : YES;
        
        [_windowController runTerminalCommand:command cwd:cwd show:show];
        *outResult = @{ @"run": @YES, @"pid": @([_windowController terminalPid]) };
        return;
    }
    
    if ([method isEqualToString:@"terminal.stop"]) {
        [_windowController stopTerminalCommand];
        *outResult = @{ @"stopped": @YES };
        return;
    }
    
    if ([method isEqualToString:@"terminal.getOutput"]) {
        NSString* output = [_windowController terminalOutput] ?: @"";
        *outResult = @{ @"output": output };
        return;
    }
    
    if ([method isEqualToString:@"terminal.clear"]) {
        [_windowController clearTerminalOutput];
        *outResult = @{ @"cleared": @YES };
        return;
    }
    
    // Git commands
    if ([method isEqualToString:@"git.status"]) {
        NSDictionary* info = [_windowController gitStatusInfo];
        *outResult = info;
        return;
    }
    
    if ([method isEqualToString:@"git.diff"]) {
        NSString* targetPath = params[@"path"] ?: @"";
        NSString* diff = [_windowController gitDiffForFile:targetPath];
        *outResult = @{ @"diff": diff };
        return;
    }
    
    if ([method isEqualToString:@"git.stage"]) {
        NSString* targetPath = params[@"path"];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        BOOL ok = [_windowController gitStageFile:targetPath];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = @"Failed to stage file.";
            return;
        }
        *outResult = @{ @"staged": @YES };
        return;
    }
    
    if ([method isEqualToString:@"git.unstage"]) {
        NSString* targetPath = params[@"path"];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        BOOL ok = [_windowController gitUnstageFile:targetPath];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = @"Failed to unstage file.";
            return;
        }
        *outResult = @{ @"unstaged": @YES };
        return;
    }
    
    if ([method isEqualToString:@"git.discard"]) {
        NSString* targetPath = params[@"path"];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        BOOL ok = [_windowController gitDiscardFile:targetPath];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = @"Failed to discard file changes.";
            return;
        }
        *outResult = @{ @"discarded": @YES };
        return;
    }
    
    if ([method isEqualToString:@"git.commit"]) {
        NSString* message = params[@"message"];
        if (!message || message.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"message parameter required.";
            return;
        }
        NSString* errStr = nil;
        BOOL ok = [_windowController gitCommitWithMessage:message errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = errStr ?: @"Failed to commit staged changes.";
            return;
        }
        *outResult = @{ @"committed": @YES };
        return;
    }
    
    // Problems commands
    if ([method isEqualToString:@"problems.list"]) {
        NSArray* problems = [_windowController problemsList] ?: @[];
        *outResult = @{ @"problems": problems };
        return;
    }
    
    if ([method isEqualToString:@"problems.open"]) {
        NSString* problemId = params[@"id"];
        if (!problemId) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"id parameter required.";
            return;
        }
        [_windowController problemsOpen:problemId];
        *outResult = @{ @"opened": @YES };
        return;
    }
    
    if ([method isEqualToString:@"problems.clearSource"]) {
        NSString* source = params[@"source"];
        if (!source) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"source parameter required.";
            return;
        }
        [_windowController problemsClearSource:source];
        *outResult = @{ @"cleared": @YES };
        return;
    }
    
    // Language features commands
    if ([method isEqualToString:@"language.diagnostics"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        NSArray* diags = [_windowController languageDiagnosticsForPath:targetPath] ?: @[];
        *outResult = @{ @"diagnostics": diags };
        return;
    }
    
    if ([method isEqualToString:@"language.format"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        [_windowController formatFileAtPath:targetPath];
        *outResult = @{ @"formatted": @YES };
        return;
    }
    
    if ([method isEqualToString:@"language.lint"]) {
        NSString* targetPath = params[@"path"] ?: [_windowController activeFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        [_windowController lintFileAtPath:targetPath];
        *outResult = @{ @"linted": @YES };
        return;
    }
    
    if ([method isEqualToString:@"language.gotoDefinition"]) {
        if ([_windowController activeFilePath] == nil) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No active editor tab.";
            return;
        }
        [_windowController goToDefinitionClicked:nil];
        *outResult = @{ @"action_triggered": @YES };
        return;
    }
    
    *outErrCode = @"method_not_found";
    *outErrMsg = [NSString stringWithFormat:@"The method '%@' is not defined.", method];
}

- (void)sendSuccess:(NSString*)reqId result:(NSDictionary*)result clientFd:(int)clientFd {
    NSDictionary* resp = @{
        @"id": reqId,
        @"ok": @YES,
        @"result": result ?: @{}
    };
    [self sendResponse:resp clientFd:clientFd];
}

- (void)sendError:(NSString*)reqId code:(id)code message:(NSString*)message clientFd:(int)clientFd {
    NSNumber* numericCode = @(-32603); // default internal error
    NSString* stringCode = @"internal_error";
    if ([code isKindOfClass:[NSNumber class]]) {
        numericCode = code;
        if ([code integerValue] == -32601) stringCode = @"method_not_found";
        else if ([code integerValue] == -32600) stringCode = @"invalid_request";
    } else if ([code isKindOfClass:[NSString class]]) {
        stringCode = code;
        if ([stringCode isEqualToString:@"invalid_request"]) numericCode = @(-32600);
        else if ([stringCode isEqualToString:@"method_not_found"]) numericCode = @(-32601);
        else if ([stringCode isEqualToString:@"outside_workspace"] || [stringCode isEqualToString:@"outside_scope"]) numericCode = @(4001);
        else if ([stringCode isEqualToString:@"lock_conflict"] || [stringCode isEqualToString:@"dirty_buffer_conflict"]) numericCode = @(4002);
        else if ([stringCode isEqualToString:@"budget_exceeded"]) numericCode = @(4003);
        else if ([stringCode isEqualToString:@"verification_failed"] || [stringCode isEqualToString:@"verify_failed"] || [stringCode isEqualToString:@"patch_failed"]) numericCode = @(4004);
        else if ([stringCode isEqualToString:@"rollback_conflict"] || [stringCode isEqualToString:@"rollback_failed"]) numericCode = @(4005);
        else if ([stringCode isEqualToString:@"permission_denied"]) numericCode = @(4006);
    }
    
    NSDictionary* resp = @{
        @"id": reqId ?: @"unknown",
        @"ok": @NO,
        @"error": @{
            @"code": numericCode,
            @"string_code": stringCode,
            @"message": message ?: @""
        }
    };
    [self sendResponse:resp clientFd:clientFd];
}

- (void)sendResponse:(NSDictionary*)responseObj clientFd:(int)clientFd {
    NSError* err = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:responseObj options:0 error:&err];
    if (err || !data) return;
    if (data.length > kMaxResponseBytes && [responseObj[@"ok"] boolValue]) {
        NSDictionary* limitResp = @{
            @"id": responseObj[@"id"] ?: @"unknown",
            @"ok": @NO,
            @"error": @{
                @"code": @"response_too_large",
                @"message": @"Response exceeds maximum allowed size."
            }
        };
        data = [NSJSONSerialization dataWithJSONObject:limitResp options:0 error:&err];
        if (err || !data) return;
    }
    
    NSMutableData* lineData = [data mutableCopy];
    [lineData appendBytes:"\n" length:1];
    
    write(clientFd, lineData.bytes, lineData.length);
}

- (void)appendLogLine:(NSString*)line {
    [_windowController appendControlLogLine:line];
}

- (void)logAuditMethod:(NSString*)method 
                caller:(NSString*)caller 
            permission:(NSString*)permission 
              duration:(long long)duration 
                result:(NSString*)result 
                 paths:(NSString*)paths {
    
    NSString* homeDir = NSHomeDirectory();
    NSString* dietcodeDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    NSString* logPath = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log"];
    
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* attrErr = nil;
    NSDictionary* attrs = [fm attributesOfItemAtPath:logPath error:&attrErr];
    if (attrs) {
        unsigned long long size = [attrs fileSize];
        if (size >= 5 * 1024 * 1024) {
            NSString* logPath3 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.3"];
            NSString* logPath2 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.2"];
            NSString* logPath1 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.1"];
            
            if ([fm fileExistsAtPath:logPath3]) {
                [fm removeItemAtPath:logPath3 error:nil];
            }
            if ([fm fileExistsAtPath:logPath2]) {
                [fm moveItemAtPath:logPath2 toPath:logPath3 error:nil];
            }
            if ([fm fileExistsAtPath:logPath1]) {
                [fm moveItemAtPath:logPath1 toPath:logPath2 error:nil];
            }
            if ([fm fileExistsAtPath:logPath]) {
                [fm moveItemAtPath:logPath toPath:logPath1 error:nil];
            }
        }
    }
    
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString* timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString* logLine = [NSString stringWithFormat:@"[%@] caller: %@ | method: %@ | permission: %@ | duration: %lldms | result: %@ | paths: %@\n", 
                         timestamp, caller, method, permission, duration, result, paths ?: @""];
    
    if (logLine.length > 8192) {
        logLine = [[logLine substringToIndex:8191] stringByAppendingString:@"\n"];
    }
    
    std::ofstream out([logPath UTF8String], std::ios::app);
    if (out.is_open()) {
        out << [logLine UTF8String];
        out.close();
    }
}

@end
