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

@implementation MacControlSearchService {
    DietCodeControlWindowBridge* _windowBridge;
}

- (instancetype)initWithWindowBridge:(DietCodeControlWindowBridge*)windowBridge {
    self = [super init];
    if (self) {
        _windowBridge = windowBridge;
    }
    return self;
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
    
    std::error_code ec;
    std::filesystem::recursive_directory_iterator it(folder, ec);
    std::filesystem::recursive_directory_iterator end;
    NSInteger scannedFiles = 0;
    for (; it != end && !ec; it.increment(ec)) {
        const auto& entry = *it;
        if (hasMore) break;
        std::filesystem::path p = entry.path();
        std::string filename = p.filename().string();
        std::string relForDir = std::filesystem::relative(p, folder, ec).string();
        if (entry.is_directory(ec)) {
            if (it.depth() >= kMaxSearchDepth || ShouldPruneSearchDirectory(p, relForDir, excludePatterns)) {
                it.disable_recursion_pending();
            }
            continue;
        }
        if (entry.is_regular_file()) {
            if (++scannedFiles > kMaxSearchScanFiles) {
                scanLimitReached = YES;
                break;
            }
            std::string relPath = relForDir;
            
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
            if (!FileIsWithinSearchReadCap(p)) continue;
            
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
            
            NSString* readRes = [_windowBridge textForFileAtPath:NSStringFromStdString(p.string())];
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
                    NSArray* spans = LiteralMatchSpans(lineText, stdQuery, caseSensitive);
                    
                    if (spans.count > 0) {
                        NSInteger resultIndex = totalMatchesSeen++;
                        if (resultIndex < resultOffset) {
                            continue;
                        }
                        if (matches.count >= (NSUInteger)maxResults) {
                            truncated = YES;
                            hasMore = YES;
                            break;
                        }
                        NSInteger lineNumber = (NSInteger)lineIdx + 1;
                        NSDictionary* firstSpan = spans.firstObject;
                        NSString* preview = NSStringFromStdString(lineText);
                        [matches addObject:@{
                            @"resultIndex": @(resultIndex),
                            @"path": NSStringFromStdString(relPath),
                            @"line": @(lineNumber),
                            @"column": firstSpan[@"columnStart"] ?: @1,
                            @"matchSpans": spans,
                            @"matchCountOnLine": @(spans.count),
                            @"preview": preview,
                            @"lineSha256": StableHashForString(preview),
                            @"contextBefore": ContextLines(fileLines, (NSInteger)lineIdx - 2, (NSInteger)lineIdx - 1),
                            @"contextAfter": ContextLines(fileLines, (NSInteger)lineIdx + 1, (NSInteger)lineIdx + 2)
                        }];
                    }
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
        @"scannedFiles": @(MIN(scannedFiles, kMaxSearchScanFiles))
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
    NSInteger scannedFiles = 0;
    BOOL truncated = NO;
    BOOL scanLimitReached = NO;
    NSInteger totalMatchesSeen = 0;
    BOOL hasMore = NO;
    std::filesystem::recursive_directory_iterator it(folder, ec);
    std::filesystem::recursive_directory_iterator end;
    for (; it != end && !ec; it.increment(ec)) {
        const auto& entry = *it;
        if (hasMore) break;
        std::filesystem::path p = entry.path();
        std::string relPath = std::filesystem::relative(p, folder, ec).string();
        if (entry.is_directory(ec)) {
            if (it.depth() >= kMaxSearchDepth || ShouldPruneSearchDirectory(p, relPath, excludes)) {
                it.disable_recursion_pending();
            }
            continue;
        }
        if (!entry.is_regular_file()) continue;
        if (++scannedFiles > kMaxSearchScanFiles) {
            scanLimitReached = YES;
            break;
        }
        if (ShouldSkipSearchPath(p, relPath, includes, excludes)) continue;
        if (!FileIsWithinSearchReadCap(p)) continue;
        NSString* text = [_windowBridge textForFileAtPath:NSStringFromStdString(p.string())];
        if (!text) continue;
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
        @"scannedFiles": @(MIN(scannedFiles, kMaxSearchScanFiles))
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
    NSMutableDictionary* todoParams = [params mutableCopy] ?: [NSMutableDictionary dictionary];
    todoParams[@"query"] = @"TODO";
    NSArray* markers = @[@"TODO", @"FIXME", @"HACK", @"NOTE"];
    NSMutableArray* all = [NSMutableArray array];
    NSInteger requestedMax = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : 100;
    if (requestedMax <= 0) {
        *outErrCode = @"invalid_params";
        *outErrMsg = @"maxResults must be greater than zero.";
        return nil;
    }
    if (requestedMax > kMaxGrepResults) {
        *outErrCode = @"too_many_results";
        *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
        return nil;
    }
    for (NSString* marker in markers) {
        NSMutableDictionary* markerParams = [todoParams mutableCopy];
        markerParams[@"query"] = marker;
        markerParams[@"maxResults"] = @(requestedMax);
        NSDictionary* subParams = markerParams;
        NSString* ws = workspace;
        NSInteger maxResults = [subParams[@"maxResults"] integerValue];
        std::string folder = StdStringFromNSString(ws);
        NSArray* includes = subParams[@"include"] ?: @[];
        NSArray* excludes = subParams[@"exclude"] ?: @[];
        std::string needle = StdStringFromNSString([marker lowercaseString]);
        std::error_code ec;
        NSInteger scannedFiles = 0;
        std::filesystem::recursive_directory_iterator it(folder, ec);
        std::filesystem::recursive_directory_iterator end;
        for (; it != end && !ec; it.increment(ec)) {
            const auto& entry = *it;
            if (all.count >= (NSUInteger)maxResults) break;
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
            if (!FileIsWithinSearchReadCap(p)) continue;
            NSString* text = [_windowBridge textForFileAtPath:NSStringFromStdString(p.string())];
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
    return @{ @"results": all };
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
