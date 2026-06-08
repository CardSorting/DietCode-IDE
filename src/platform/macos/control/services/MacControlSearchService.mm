#import "MacControlSearchService.hpp"
#import "MacControlWindowBridge.hpp"
#import "MacControlSupport.hpp"
#import "MacControlPathSecurity.hpp"
#import "MacControlSerialization.hpp"
#import "WorkspaceAnalysisService.hpp"
#import "SymbolIndexService.hpp"

#include <filesystem>
#include <vector>
#include <string>
#include <sstream>
#include <algorithm>
#include <fnmatch.h>

using namespace dietcode::platform::macos;

static const NSInteger kMaxSearchContextLines = 20;
static const NSInteger kMaxSearchSessionFilesPerPoll = 500;

// POLICY: Symlinks are never followed during workspace search traversal (filesSkippedSymlink).
static std::vector<std::filesystem::path> CollectSortedSearchFilePaths(
    const std::string& folder,
    NSArray* includePatterns,
    NSArray* excludePatterns,
    NSInteger* scannedFiles,
    NSInteger* skippedOversize,
    NSInteger* skippedExcluded,
    NSInteger* skippedSymlink) {
    std::vector<std::filesystem::path> paths;
    std::error_code ec;
    std::filesystem::recursive_directory_iterator it(folder, ec);
    std::filesystem::recursive_directory_iterator end;
    for (; it != end && !ec; it.increment(ec)) {
        const auto& entry = *it;
        std::filesystem::path p = entry.path();
        std::string filename = p.filename().string();
        std::string relForDir = std::filesystem::relative(p, folder, ec).string();
        if (entry.is_symlink(ec)) {
            (*skippedSymlink)++;
            it.disable_recursion_pending();
            continue;
        }
        if (entry.is_directory(ec)) {
            if (it.depth() >= kMaxSearchDepth || ShouldPruneSearchDirectory(p, relForDir, excludePatterns)) {
                it.disable_recursion_pending();
            }
            continue;
        }
        if (!entry.is_regular_file(ec)) continue;
        (*scannedFiles)++;
        if (*scannedFiles > kMaxSearchScanFiles) break;
        BOOL skip = NO;
        for (NSString* ex in excludePatterns) {
            if (fnmatch([ex UTF8String], relForDir.c_str(), FNM_CASEFOLD) == 0 ||
                fnmatch([ex UTF8String], filename.c_str(), FNM_CASEFOLD) == 0) {
                skip = YES;
                break;
            }
        }
        if (filename == ".git" || filename == "node_modules" || filename == "build") skip = YES;
        if (skip) {
            (*skippedExcluded)++;
            continue;
        }
        if (includePatterns.count > 0) {
            BOOL matchesInclude = NO;
            for (NSString* inc in includePatterns) {
                if (fnmatch([inc UTF8String], relForDir.c_str(), FNM_CASEFOLD) == 0 ||
                    fnmatch([inc UTF8String], filename.c_str(), FNM_CASEFOLD) == 0) {
                    matchesInclude = YES;
                    break;
                }
            }
            if (!matchesInclude) {
                (*skippedExcluded)++;
                continue;
            }
        }
        if (!FileIsWithinSearchReadCap(p)) {
            (*skippedOversize)++;
            continue;
        }
        paths.push_back(p);
    }
    std::sort(paths.begin(), paths.end(), [](const std::filesystem::path& a, const std::filesystem::path& b) {
        return a.string() < b.string();
    });
    return paths;
}

@interface MacGrepSession : NSObject
@property (nonatomic, copy) NSString* searchId;
@property (nonatomic, copy) NSString* query;
@property (nonatomic, copy) NSArray* filePaths;
@property (nonatomic, assign) NSInteger currentFileIndex;
@property (nonatomic, assign) BOOL caseSensitive;
@property (nonatomic, strong) NSDate* createdAt;
@end

@implementation MacGrepSession
@end

@implementation MacControlSearchService {
    DietCodeControlWindowBridge* _windowBridge;
    NSMutableDictionary<NSString*, MacGrepSession*>* _activeGrepSessions;
    NSInteger _searchSessionCounter;
}

- (instancetype)initWithWindowBridge:(DietCodeControlWindowBridge*)windowBridge {
    self = [super init];
    if (self) {
        _windowBridge = windowBridge;
        _activeGrepSessions = [NSMutableDictionary dictionary];
        _searchSessionCounter = 0;
    }
    return self;
}

- (NSDictionary*)startGrepSession:(NSDictionary*)params 
                       outErrCode:(NSString**)outErrCode 
                        outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [_windowBridge workspacePath];
    NSString* query = params[@"query"];
    if (!ws || !query || query.length == 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"Query string and workspace required.";
        return nil;
    }

    NSArray* includePatterns = params[@"include"] ?: @[];
    NSArray* excludePatterns = params[@"exclude"] ?: @[];
    BOOL caseSensitive = [params[@"caseSensitive"] boolValue];

    std::string folder = StdStringFromNSString(ws);
    NSMutableArray* filePaths = [NSMutableArray array];

    std::error_code ec;
    std::filesystem::recursive_directory_iterator it(folder, ec);
    std::filesystem::recursive_directory_iterator end;
    for (; it != end && !ec; it.increment(ec)) {
        const auto& entry = *it;
        std::filesystem::path p = entry.path();
        std::string filename = p.filename().string();
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (entry.is_directory(ec)) {
            if (it.depth() >= kMaxSearchDepth || ShouldPruneSearchDirectory(p, relPath, excludePatterns)) {
                it.disable_recursion_pending();
            }
            continue;
        }
        if (entry.is_regular_file()) {
            if (ShouldSkipSearchPath(p, relPath, includePatterns, excludePatterns)) continue;
            [filePaths addObject:NSStringFromStdString(p.string())];
        }
    }

    NSString* searchId = [NSString stringWithFormat:@"search-%ld", (long)++_searchSessionCounter];
    MacGrepSession* session = [[MacGrepSession alloc] init];
    session.searchId = searchId;
    session.query = query;
    session.filePaths = filePaths;
    session.currentFileIndex = 0;
    session.caseSensitive = caseSensitive;
    session.createdAt = [NSDate date];

    _activeGrepSessions[searchId] = session;

    return @{
        @"searchId": searchId,
        @"totalFiles": @(filePaths.count),
        @"query": query
    };
}

- (NSDictionary*)nextGrepResults:(NSDictionary*)params 
                      outErrCode:(NSString**)outErrCode 
                       outErrMsg:(NSString**)outErrMsg {
    NSString* searchId = params[@"searchId"];
    MacGrepSession* session = searchId ? _activeGrepSessions[searchId] : nil;
    if (!session) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"Unknown or expired searchId.";
        return nil;
    }

    NSInteger maxFiles = params[@"maxFiles"] ? [params[@"maxFiles"] integerValue] : 50;
    if (maxFiles <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxFiles must be greater than zero.";
        return nil;
    }
    if (maxFiles > kMaxSearchSessionFilesPerPoll) {
        *outErrCode = @"response_too_large";
        *outErrMsg = [NSString stringWithFormat:@"maxFiles exceeds limit of %ld.", (long)kMaxSearchSessionFilesPerPoll];
        return nil;
    }

    NSMutableArray* matches = [NSMutableArray array];
    NSInteger filesProcessed = 0;
    NSString* ws = [_windowBridge workspacePath];
    std::string stdQuery = StdStringFromNSString(session.query);

    while (session.currentFileIndex < (NSInteger)session.filePaths.count && filesProcessed < maxFiles) {
        NSString* absPath = session.filePaths[session.currentFileIndex];
        session.currentFileIndex++;
        filesProcessed++;

        NSString* readRes = TextForSearchAtPath([_windowBridge textForFileAtPath:absPath], absPath, nil);
        if (readRes) {
            std::string content = StdStringFromNSString(readRes);
            std::istringstream stream(content);
            std::vector<std::string> fileLines;
            std::string lineText;
            while (std::getline(stream, lineText)) {
                fileLines.push_back(lineText);
            }

            NSUInteger currentOffset = 0;
            std::string relPath = std::filesystem::relative(std::filesystem::path([absPath UTF8String]), std::filesystem::path([ws UTF8String])).string();

            for (size_t lineIdx = 0; lineIdx < fileLines.size(); lineIdx++) {
                lineText = fileLines[lineIdx];
                NSArray* spans = LiteralMatchSpans(lineText, stdQuery, session.caseSensitive);

                if (spans.count > 0) {
                    NSMutableArray* enrichedSpans = [NSMutableArray array];
                    for (NSDictionary* span in spans) {
                        NSMutableDictionary* s = [span mutableCopy];
                        s[@"offset"] = @(currentOffset + [span[@"columnStart"] integerValue] - 1);
                        s[@"length"] = @([span[@"columnEnd"] integerValue] - [span[@"columnStart"] integerValue] + 1);
                        [enrichedSpans addObject:s];
                    }

                    NSInteger lineNumber = (NSInteger)lineIdx + 1;
                    NSString* preview = NSStringFromStdString(lineText);
                    [matches addObject:@{
                        @"path": NSStringFromStdString(relPath),
                        @"line": @(lineNumber),
                        @"column": enrichedSpans.firstObject[@"columnStart"] ?: @1,
                        @"matchSpans": enrichedSpans,
                        @"preview": preview,
                        @"contextBefore": ContextLines(fileLines, (NSInteger)lineIdx - 2, (NSInteger)lineIdx - 1),
                        @"contextAfter": ContextLines(fileLines, (NSInteger)lineIdx + 1, (NSInteger)lineIdx + 2)
                    }];
                }
                currentOffset += lineText.length() + 1;
            }
        }
    }

    BOOL finished = (session.currentFileIndex >= (NSInteger)session.filePaths.count);
    if (finished) {
        [_activeGrepSessions removeObjectForKey:searchId];
    }

    return @{
        @"searchId": searchId,
        @"matches": matches,
        @"filesProcessed": @(filesProcessed),
        @"totalFiles": @(session.filePaths.count),
        @"currentFileIndex": @(session.currentFileIndex),
        @"finished": @(finished)
    };
}

- (NSDictionary*)cancelGrepSession:(NSDictionary*)params 
                        outErrCode:(NSString**)outErrCode 
                         outErrMsg:(NSString**)outErrMsg {
    NSString* searchId = params[@"searchId"];
    if (searchId && _activeGrepSessions[searchId]) {
        [_activeGrepSessions removeObjectForKey:searchId];
        return @{ @"searchId": searchId, @"cancelled": @YES };
    }
    return @{ @"cancelled": @NO };
}

- (NSDictionary*)workspaceGrep:(NSDictionary*)params
                    outErrCode:(NSString**)outErrCode
                     outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [_windowBridge workspacePath];
    NSString* query = params[@"query"];
    if (!ws || !query || query.length == 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"Query string and workspace required.";
        return nil;
    }
    
    NSArray* includePatterns = params[@"include"] ?: @[];
    NSArray* excludePatterns = params[@"exclude"] ?: @[];
    BOOL caseSensitive = [params[@"caseSensitive"] boolValue];
    NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 200;
    NSInteger resultOffset = params[@"resultOffset"] ? MAX([params[@"resultOffset"] integerValue], 0) : 0;
    if (maxResults <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxResults must be greater than zero.";
        return nil;
    }
    if (maxResults > kMaxGrepResults) {
        *outErrCode = @"response_too_large";
        *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
        return nil;
    }
    
    std::string folder = StdStringFromNSString(ws);
    std::string stdQuery = StdStringFromNSString(query);
    NSMutableArray* matches = [NSMutableArray array];
    BOOL truncated = NO;
    BOOL scanLimitReached = NO;
    NSInteger totalMatchesSeen = 0;
    BOOL hasMore = NO;
    NSInteger filesRead = 0;
    NSInteger filesSkippedUnreadable = 0;
    NSInteger filesSkippedBinary = 0;
    NSInteger filesReadFromDisk = 0;
    NSInteger filesReadFromEditor = 0;
    NSInteger filesSkippedOversize = 0;
    NSInteger filesSkippedExcluded = 0;
    NSInteger filesSkippedSymlink = 0;
    CFAbsoluteTime scanStarted = CFAbsoluteTimeGetCurrent();
    
    NSInteger scannedFiles = 0;
    std::vector<std::filesystem::path> sortedPaths = CollectSortedSearchFilePaths(
        folder, includePatterns, excludePatterns, &scannedFiles, &filesSkippedOversize, &filesSkippedExcluded, &filesSkippedSymlink);
    if (scannedFiles > kMaxSearchScanFiles) scanLimitReached = YES;
    std::error_code ec;
    for (const auto& p : sortedPaths) {
        if (hasMore) break;
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (ec) continue;
        {
            NSString* absPath = NSStringFromStdString(p.string());
            NSString* readSource = nil;
            NSString* readRes = TextForSearchAtPath([_windowBridge textForFileAtPath:absPath], absPath, &readSource);
            if (!readRes) {
                NSString* editorProbe = [_windowBridge textForFileAtPath:absPath];
                if (editorProbe.length > 0 && IsTextBinary(editorProbe)) {
                    filesSkippedBinary++;
                } else {
                    filesSkippedUnreadable++;
                }
                continue;
            }
            filesRead++;
            if ([readSource isEqualToString:@"disk"]) filesReadFromDisk++;
            else if ([readSource isEqualToString:@"editor"]) filesReadFromEditor++;
            {
                NSUInteger currentOffset = 0;
                std::string content = StdStringFromNSString(readRes);
                std::istringstream stream(content);
                std::vector<std::string> fileLines;
                std::string lineText;
                while (std::getline(stream, lineText)) {
                    fileLines.push_back(lineText);
                }

                for (size_t lineIdx = 0; lineIdx < fileLines.size(); lineIdx++) {
                    lineText = fileLines[lineIdx];
                    NSArray* spans = LiteralMatchSpans(lineText, stdQuery, caseSensitive);
                    
                    if (spans.count > 0) {
                        NSInteger resultIndex = totalMatchesSeen++;
                        if (resultIndex < resultOffset) {
                            currentOffset += lineText.length() + 1;
                            continue;
                        }
                        if (matches.count >= (NSUInteger)maxResults) {
                            truncated = YES;
                            hasMore = YES;
                            break;
                        }
                        
                        NSMutableArray* enrichedSpans = [NSMutableArray array];
                        for (NSDictionary* span in spans) {
                            NSMutableDictionary* s = [span mutableCopy];
                            s[@"offset"] = @(currentOffset + [span[@"columnStart"] integerValue] - 1);
                            s[@"length"] = @([span[@"columnEnd"] integerValue] - [span[@"columnStart"] integerValue] + 1);
                            [enrichedSpans addObject:s];
                        }

                        NSInteger lineNumber = (NSInteger)lineIdx + 1;
                        NSDictionary* firstSpan = enrichedSpans.firstObject;
                        NSString* preview = NSStringFromStdString(lineText);
                        [matches addObject:@{
                            @"resultIndex": @(resultIndex),
                            @"path": NSStringFromStdString(relPath),
                            @"line": @(lineNumber),
                            @"column": firstSpan[@"columnStart"] ?: @1,
                            @"matchSpans": enrichedSpans,
                            @"matchCountOnLine": @(spans.count),
                            @"preview": preview,
                            @"lineSha256": StableHashForString(preview),
                            @"contextBefore": ContextLines(fileLines, (NSInteger)lineIdx - 2, (NSInteger)lineIdx - 1),
                            @"contextAfter": ContextLines(fileLines, (NSInteger)lineIdx + 1, (NSInteger)lineIdx + 2)
                        }];
                    }
                    currentOffset += lineText.length() + 1;
                }
            }
        }
    }
    id nextOffset = hasMore ? @(resultOffset + (NSInteger)matches.count) : [NSNull null];
    return @{
        @"matches": matches,
        @"query": query,
        @"mode": @"literal_substring",
        @"caseSensitive": @(caseSensitive),
        @"maxResults": @(maxResults),
        @"resultOffset": @(resultOffset),
        @"nextResultOffset": nextOffset,
        @"hasMore": @(hasMore),
        @"truncated": @(truncated || scanLimitReached),
        @"scanLimitReached": @(scanLimitReached),
        @"scannedFiles": @(MIN(scannedFiles, kMaxSearchScanFiles)),
        @"filesRead": @(filesRead),
        @"filesSkippedUnreadable": @(filesSkippedUnreadable),
        @"filesSkippedBinary": @(filesSkippedBinary),
        @"filesReadFromDisk": @(filesReadFromDisk),
        @"filesReadFromEditor": @(filesReadFromEditor),
        @"filesSkippedOversize": @(filesSkippedOversize),
        @"filesSkippedExcluded": @(filesSkippedExcluded),
        @"filesSkippedSymlink": @(filesSkippedSymlink),
        @"symlinkPolicy": @"skip_never_follow",
        @"sortOrder": @"path_line_column",
        @"scanDurationMs": @((NSInteger)round((CFAbsoluteTimeGetCurrent() - scanStarted) * 1000.0))
    };
}

- (NSDictionary*)searchFiles:(NSDictionary*)params 
                  outErrCode:(NSString**)outErrCode 
                   outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [_windowBridge workspacePath];
    NSString* query = params[@"query"] ?: @"";
    if (!ws || query.length == 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"query and workspace required.";
        return nil;
    }
    NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 100;
    if (maxResults <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxResults must be greater than zero.";
        return nil;
    }
    if (maxResults > kMaxGrepResults) {
        *outErrCode = @"too_many_results";
        *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
        return nil;
    }
    std::string folder = StdStringFromNSString(ws);
    std::string needle = StdStringFromNSString([query lowercaseString]);
    NSArray* includes = params[@"include"] ?: @[];
    NSArray* excludes = params[@"exclude"] ?: @[];
    NSMutableArray* results = [NSMutableArray array];
    std::error_code ec;
    NSInteger scannedFiles = 0;
    std::filesystem::recursive_directory_iterator it(folder, ec);
    std::filesystem::recursive_directory_iterator end;
    for (; it != end && !ec; it.increment(ec)) {
        const auto& entry = *it;
        if (results.count >= (NSUInteger)maxResults) break;
        std::filesystem::path p = entry.path();
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (entry.is_directory(ec)) {
            if (it.depth() >= kMaxSearchDepth || ShouldPruneSearchDirectory(p, relPath, excludes)) {
                it.disable_recursion_pending();
            }
            continue;
        }
        if (!entry.is_regular_file()) continue;
        if (++scannedFiles > kMaxSearchScanFiles) break;
        if (ShouldSkipSearchPath(p, relPath, includes, excludes)) continue;
        std::string lowerRel = relPath;
        std::transform(lowerRel.begin(), lowerRel.end(), lowerRel.begin(), ::tolower);
        size_t pos = lowerRel.find(needle);
        if (pos == std::string::npos) continue;
        double score = pos == 0 ? 1.0 : 0.75;
        if (p.filename().string().find(StdStringFromNSString(query)) != std::string::npos) score += 0.2;
        [results addObject:@{ @"path": NSStringFromStdString(relPath), @"score": @(MIN(score, 1.0)) }];
    }
    return @{ @"results": results };
}

- (NSDictionary*)searchText:(NSDictionary*)params 
                 outErrCode:(NSString**)outErrCode 
                  outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [_windowBridge workspacePath];
    NSString* query = params[@"query"] ?: @"";
    if (!ws || query.length == 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"query and workspace required.";
        return nil;
    }
    NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 200;
    if (maxResults <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxResults must be greater than zero.";
        return nil;
    }
    if (maxResults > kMaxGrepResults) {
        *outErrCode = @"too_many_results";
        *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
        return nil;
    }
    NSInteger before = params[@"before"] ? [params[@"before"] integerValue] : 2;
    NSInteger after = params[@"after"] ? [params[@"after"] integerValue] : 2;
    if (before < 0 || after < 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"before and after must be non-negative integers.";
        return nil;
    }
    if (before > kMaxSearchContextLines || after > kMaxSearchContextLines) {
        *outErrCode = @"response_too_large";
        *outErrMsg = [NSString stringWithFormat:@"before and after must be <= %ld.", (long)kMaxSearchContextLines];
        return nil;
    }
    NSInteger resultOffset = params[@"resultOffset"] ? MAX([params[@"resultOffset"] integerValue], 0) : 0;
    BOOL caseSensitive = [params[@"caseSensitive"] boolValue];
    NSArray* includes = params[@"include"] ?: @[];
    NSArray* excludes = params[@"exclude"] ?: @[];
    std::string folder = StdStringFromNSString(ws);
    std::string needle = StdStringFromNSString(query);
    NSMutableArray* results = [NSMutableArray array];
    std::error_code ec;
    BOOL truncated = NO;
    BOOL scanLimitReached = NO;
    NSInteger totalMatchesSeen = 0;
    BOOL hasMore = NO;
    NSInteger filesRead = 0;
    NSInteger filesSkippedUnreadable = 0;
    NSInteger filesSkippedBinary = 0;
    NSInteger filesReadFromDisk = 0;
    NSInteger filesReadFromEditor = 0;
    NSInteger filesSkippedOversize = 0;
    NSInteger filesSkippedExcluded = 0;
    NSInteger filesSkippedSymlink = 0;
    CFAbsoluteTime scanStarted = CFAbsoluteTimeGetCurrent();
    NSInteger scannedFiles = 0;
    std::vector<std::filesystem::path> sortedPaths = CollectSortedSearchFilePaths(
        folder, includes, excludes, &scannedFiles, &filesSkippedOversize, &filesSkippedExcluded, &filesSkippedSymlink);
    if (scannedFiles > kMaxSearchScanFiles) scanLimitReached = YES;
    for (const auto& p : sortedPaths) {
        if (hasMore) break;
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (ec) continue;
        NSString* absPath = NSStringFromStdString(p.string());
        NSString* readSource = nil;
        NSString* text = TextForSearchAtPath([_windowBridge textForFileAtPath:absPath], absPath, &readSource);
        if (!text) {
            NSString* editorProbe = [_windowBridge textForFileAtPath:absPath];
            if (editorProbe.length > 0 && IsTextBinary(editorProbe)) filesSkippedBinary++;
            else filesSkippedUnreadable++;
            continue;
        }
        filesRead++;
        if ([readSource isEqualToString:@"disk"]) filesReadFromDisk++;
        else if ([readSource isEqualToString:@"editor"]) filesReadFromEditor++;
        std::vector<std::string> lines;
        std::istringstream stream(StdStringFromNSString(text));
        std::string line;
        while (std::getline(stream, line)) lines.push_back(line);
        for (size_t i = 0; i < lines.size(); i++) {
            NSArray* spans = LiteralMatchSpans(lines[i], needle, caseSensitive);
            if (spans.count == 0) continue;
            NSInteger resultIndex = totalMatchesSeen++;
            if (resultIndex < resultOffset) continue;
            if (results.count >= (NSUInteger)maxResults) {
                truncated = YES;
                hasMore = YES;
                break;
            }
            NSDictionary* firstSpan = spans.firstObject;
            NSString* preview = NSStringFromStdString(lines[i]);
            [results addObject:@{
                @"resultIndex": @(resultIndex),
                @"path": NSStringFromStdString(relPath),
                @"line": @(i + 1),
                @"column": firstSpan[@"columnStart"] ?: @1,
                @"matchSpans": spans,
                @"matchCountOnLine": @(spans.count),
                @"preview": preview,
                @"lineSha256": StableHashForString(preview),
                @"contextBefore": ContextLines(lines, (NSInteger)i - before, (NSInteger)i - 1),
                @"contextAfter": ContextLines(lines, (NSInteger)i + 1, (NSInteger)i + after)
            }];
        }
    }
    id nextOffset = hasMore ? @(resultOffset + (NSInteger)results.count) : [NSNull null];
    return @{
        @"results": results,
        @"query": query,
        @"mode": @"literal_substring",
        @"caseSensitive": @(caseSensitive),
        @"maxResults": @(maxResults),
        @"resultOffset": @(resultOffset),
        @"nextResultOffset": nextOffset,
        @"hasMore": @(hasMore),
        @"truncated": @(truncated || scanLimitReached),
        @"scanLimitReached": @(scanLimitReached),
        @"scannedFiles": @(MIN(scannedFiles, kMaxSearchScanFiles)),
        @"filesRead": @(filesRead),
        @"filesSkippedUnreadable": @(filesSkippedUnreadable),
        @"filesSkippedBinary": @(filesSkippedBinary),
        @"filesReadFromDisk": @(filesReadFromDisk),
        @"filesReadFromEditor": @(filesReadFromEditor),
        @"filesSkippedOversize": @(filesSkippedOversize),
        @"filesSkippedExcluded": @(filesSkippedExcluded),
        @"filesSkippedSymlink": @(filesSkippedSymlink),
        @"symlinkPolicy": @"skip_never_follow",
        @"sortOrder": @"path_line_column",
        @"scanDurationMs": @((NSInteger)round((CFAbsoluteTimeGetCurrent() - scanStarted) * 1000.0))
    };
}

- (NSDictionary*)searchTodo:(NSDictionary*)params 
                 outErrCode:(NSString**)outErrCode 
                  outErrMsg:(NSString**)outErrMsg {
    NSString* workspace = [_windowBridge workspacePath];
    if (!workspace) {
        *outErrCode = @"invalid_request";
        *outErrMsg = @"No open workspace.";
        return nil;
    }
    NSArray* markers = @[@"TODO", @"FIXME", @"HACK", @"NOTE"];
    NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 100;
    if (maxResults <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxResults must be greater than zero.";
        return nil;
    }
    if (maxResults > kMaxGrepResults) {
        *outErrCode = @"too_many_results";
        *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
        return nil;
    }
    NSArray* includes = params[@"include"] ?: @[];
    NSArray* excludes = params[@"exclude"] ?: @[];
    std::string folder = StdStringFromNSString(workspace);
    NSMutableArray* all = [NSMutableArray array];
    BOOL truncated = NO;
    BOOL scanLimitReached = NO;
    NSInteger filesRead = 0;
    NSInteger filesSkippedUnreadable = 0;
    NSInteger filesSkippedBinary = 0;
    NSInteger filesReadFromDisk = 0;
    NSInteger filesReadFromEditor = 0;
    NSInteger filesSkippedOversize = 0;
    NSInteger filesSkippedExcluded = 0;
    NSInteger filesSkippedSymlink = 0;
    CFAbsoluteTime scanStarted = CFAbsoluteTimeGetCurrent();
    NSInteger scannedFiles = 0;
    std::vector<std::filesystem::path> sortedPaths = CollectSortedSearchFilePaths(
        folder, includes, excludes, &scannedFiles, &filesSkippedOversize, &filesSkippedExcluded, &filesSkippedSymlink);
    if (scannedFiles > kMaxSearchScanFiles) scanLimitReached = YES;
    std::error_code ec;
    for (const auto& p : sortedPaths) {
        if (all.count >= (NSUInteger)maxResults) {
            truncated = YES;
            break;
        }
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (ec) continue;
        NSString* absPath = NSStringFromStdString(p.string());
        NSString* readSource = nil;
        NSString* text = TextForSearchAtPath([_windowBridge textForFileAtPath:absPath], absPath, &readSource);
        if (!text) {
            NSString* editorProbe = [_windowBridge textForFileAtPath:absPath];
            if (editorProbe.length > 0 && IsTextBinary(editorProbe)) filesSkippedBinary++;
            else filesSkippedUnreadable++;
            continue;
        }
        filesRead++;
        if ([readSource isEqualToString:@"disk"]) filesReadFromDisk++;
        else if ([readSource isEqualToString:@"editor"]) filesReadFromEditor++;
        NSArray<NSString*>* lines = LinesFromText(text);
        for (NSUInteger i = 0; i < lines.count; i++) {
            if (all.count >= (NSUInteger)maxResults) {
                truncated = YES;
                break;
            }
            NSString* lower = [lines[i] lowercaseString];
            for (NSString* marker in markers) {
                NSRange r = [lower rangeOfString:[marker lowercaseString]];
                if (r.location == NSNotFound) continue;
                [all addObject:@{
                    @"resultIndex": @(all.count),
                    @"path": NSStringFromStdString(relPath),
                    @"line": @(i + 1),
                    @"column": @(r.location + 1),
                    @"marker": marker,
                    @"preview": lines[i],
                    @"lineSha256": StableHashForString(lines[i])
                }];
                if (all.count >= (NSUInteger)maxResults) {
                    truncated = YES;
                    break;
                }
            }
        }
    }
    return @{
        @"results": all,
        @"mode": @"literal_marker_scan",
        @"markers": markers,
        @"maxResults": @(maxResults),
        @"truncated": @(truncated || scanLimitReached),
        @"scanLimitReached": @(scanLimitReached),
        @"scannedFiles": @(MIN(scannedFiles, kMaxSearchScanFiles)),
        @"filesRead": @(filesRead),
        @"filesSkippedUnreadable": @(filesSkippedUnreadable),
        @"filesSkippedBinary": @(filesSkippedBinary),
        @"filesReadFromDisk": @(filesReadFromDisk),
        @"filesReadFromEditor": @(filesReadFromEditor),
        @"filesSkippedOversize": @(filesSkippedOversize),
        @"filesSkippedExcluded": @(filesSkippedExcluded),
        @"filesSkippedSymlink": @(filesSkippedSymlink),
        @"symlinkPolicy": @"skip_never_follow",
        @"sortOrder": @"path_line_column",
        @"scanDurationMs": @((NSInteger)round((CFAbsoluteTimeGetCurrent() - scanStarted) * 1000.0))
    };
}

- (NSDictionary*)searchSemantic:(NSDictionary*)params 
                     outErrCode:(NSString**)outErrCode 
                      outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [_windowBridge workspacePath];
    NSString* query = params[@"query"];
    if (!ws || !query || query.length == 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"query and workspace required.";
        return nil;
    }
    
    NSInteger maxResults = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 50;
    maxResults = MIN(MAX(1, maxResults), 100);
    
    // 1. Get ranked literal matches
    NSArray* ranked = [DietCodeWorkspaceAnalysisService searchRankedForQuery:query 
                                                                   workspace:ws 
                                                                   openFiles:[_windowBridge openTabs] 
                                                                 recentFiles:@[] 
                                                                     include:@[] 
                                                                     exclude:@[] 
                                                               caseSensitive:NO];
    
    // 2. Get symbol references
    NSArray* references = [DietCodeSymbolIndexService referencesForSymbol:query 
                                                              inWorkspace:ws 
                                                                openFiles:[_windowBridge openTabs] 
                                                         diagnosticsFiles:@[]];
    
    NSMutableArray* combined = [NSMutableArray array];
    NSMutableSet* seen = [NSMutableSet set];
    
    for (NSDictionary* ref in references) {
        if (combined.count >= (NSUInteger)maxResults) break;
        NSString* key = [NSString stringWithFormat:@"%@:%@", ref[@"path"], ref[@"line"]];
        if (![seen containsObject:key]) {
            [combined addObject:@{
                @"path": ref[@"path"],
                @"line": ref[@"line"],
                @"column": ref[@"column"],
                @"preview": ref[@"preview"] ?: @"",
                @"score": @([ref[@"score"] doubleValue] + 2.0), // Boost symbol matches
                @"type": @"symbol_reference"
            }];
            [seen addObject:key];
        }
    }
    
    for (NSDictionary* item in ranked) {
        if (combined.count >= (NSUInteger)maxResults) break;
        for (NSDictionary* match in item[@"matches"] ?: @[]) {
            if (combined.count >= (NSUInteger)maxResults) break;
            NSString* key = [NSString stringWithFormat:@"%@:%@", item[@"path"], match[@"line"]];
            if (![seen containsObject:key]) {
                [combined addObject:@{
                    @"path": item[@"path"],
                    @"line": match[@"line"],
                    @"column": match[@"column"],
                    @"preview": match[@"preview"] ?: @"",
                    @"score": item[@"score"],
                    @"type": @"ranked_literal"
                }];
                [seen addObject:key];
            }
        }
    }
    
    [combined sortUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        return [b[@"score"] compare:a[@"score"]];
    }];
    
    return @{ @"results": combined, @"query": query };
}

- (NSDictionary*)searchDiagnostics:(NSDictionary*)params 
                        outErrCode:(NSString**)outErrCode 
                         outErrMsg:(NSString**)outErrMsg {
    NSString* severity = [params[@"severity"] lowercaseString];
    NSString* source = params[@"source"];
    NSMutableArray* matches = [NSMutableArray array];
    for (NSDictionary* problem in [_windowBridge problemsList] ?: @[]) {
        if (severity.length > 0 && ![[problem[@"severity"] lowercaseString] isEqualToString:severity]) continue;
        if (source.length > 0 && ![problem[@"source"] isEqualToString:source]) continue;
        [matches addObject:problem];
    }
    return @{ @"results": matches };
}

@end
