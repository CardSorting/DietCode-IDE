#import "MacControlServer+Private.hpp"
#import "MacWindow.hpp"
#import "MacControlSupport.hpp"
#import "MacControlPathSecurity.hpp"
#import "filesystem/PathUtils.hpp"

#include <filesystem>
#include <vector>
#include <string>

static const NSInteger kMaxReadAroundContextLines = 500;

@implementation DietCodeControlServer (File)

- (void)executeFileMethod:(NSString*)method 
                   params:(NSDictionary*)params 
                outResult:(NSDictionary**)outResult 
               outErrCode:(NSString**)outErrCode 
              outErrMsg:(NSString**)outErrMsg
                 outPaths:(NSString**)outPaths {
    
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
        [self.windowController openWorkspaceFolder:targetPath];
        *outResult = @{ @"opened": @YES, @"path": targetPath };
        return;
    }
    
    if ([method isEqualToString:@"workspace.getRoot"]) {
        NSString* root = [self safeWorkspacePath] ?: @"";
        *outResult = @{ @"path": root };
        return;
    }
    
    if ([method isEqualToString:@"workspace.listFiles"]) {
        NSString* ws = [self safeWorkspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        
        std::filesystem::path folder([ws UTF8String]);
        std::vector<std::string> relativePaths;
        
        dietcode::filesystem::traverseDirectory(folder, [&](const std::filesystem::directory_entry& entry, int depth, bool& skipRecursion, bool& stop) {
            if (relativePaths.size() >= 1000) {
                stop = true;
                return;
            }
            
            std::filesystem::path p = entry.path();
            std::string filename = p.filename().string();
            if (entry.is_directory()) {
                if (depth >= kMaxSearchDepth || 
                    filename == ".git" || filename == "build" || filename == "dist" || 
                    filename == "node_modules" || filename == "DerivedData") {
                    skipRecursion = true;
                }
                return;
            }
            
            if (entry.is_regular_file()) {
                std::error_code ec;
                auto rel = std::filesystem::relative(p, folder, ec);
                if (!ec) {
                    relativePaths.push_back(rel.string());
                }
            }
        });
        
        NSMutableArray* filesArr = [NSMutableArray array];
        for (const auto& r : relativePaths) {
            [filesArr addObject:NSStringFromStdString(r)];
        }
        *outResult = @{ @"files": filesArr };
        return;
    }
    
    if ([method isEqualToString:@"workspace.grep"]) {
        *outResult = [_searchService workspaceGrep:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }
    
    if ([method isEqualToString:@"workspace.openFile"]) {
        NSString* absPath = AbsolutePathForRPCPath(params[@"path"], [self safeWorkspacePath]);
        if (!absPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
            *outErrCode = @"not_found";
            *outErrMsg = [NSString stringWithFormat:@"File does not exist: %@", absPath];
            return;
        }
        [self.windowController openFileAtPath:absPath line:1 column:1];
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
        *outResult = [_searchService searchFiles:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"search.text"]) {
        *outResult = [_searchService searchText:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"search.todo"]) {
        *outResult = [_searchService searchTodo:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"search.semantic"]) {
        *outResult = [_searchService searchSemantic:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"search.diagnostics"]) {
        *outResult = [_searchService searchDiagnostics:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    // File reading primitives
    if ([method isEqualToString:@"file.read"] || [method isEqualToString:@"file.readRange"] || [method isEqualToString:@"file.readAround"] || [method isEqualToString:@"file.getChunks"] || [method isEqualToString:@"file.stat"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        NSString* text = [self safeTextForFileAtPath:targetPath];
        if (!text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"File is not readable.";
            return;
        }
        NSArray<NSString*>* lines = LinesFromText(text);
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:targetPath error:nil];
        NSUInteger sizeBytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        BOOL open = [[self safeOpenFilePaths] containsObject:targetPath];
        BOOL dirty = [DirtyFilePathsFromTabs([self safeOpenTabs] ?: @[]) containsObject:targetPath];
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
            if (params[@"startLine"] == nil || params[@"endLine"] == nil) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"startLine and endLine parameters required.";
                return;
            }
            NSInteger startLine = [params[@"startLine"] integerValue];
            NSInteger endLine = [params[@"endLine"] integerValue];
            if (startLine <= 0 || endLine <= 0) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"startLine and endLine must be positive integers (1-indexed).";
                return;
            }
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
            if (line <= 0) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"line parameter must be a positive integer (1-indexed).";
                return;
            }
            NSInteger before = params[@"before"] ? [params[@"before"] integerValue] : 40;
            NSInteger after = params[@"after"] ? [params[@"after"] integerValue] : 80;
            if (before < 0 || after < 0) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"before and after must be non-negative integers.";
                return;
            }
            if (before > kMaxReadAroundContextLines || after > kMaxReadAroundContextLines) {
                *outErrCode = @"response_too_large";
                *outErrMsg = [NSString stringWithFormat:@"before and after must be <= %ld.", (long)kMaxReadAroundContextLines];
                return;
            }
            NSInteger startLine = MAX(1, line - before);
            NSInteger endLine = MIN((NSInteger)lines.count, line + after);
            NSString* rangeText = TextForLineRange(lines, startLine, endLine);
            if (!rangeText || line > (NSInteger)lines.count) {
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

    if ([method isEqualToString:@"file.write"] || [method isEqualToString:@"file.create"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"], ws);
        NSString* content = params[@"content"];
        if (targetPath.length == 0 || ![content isKindOfClass:[NSString class]]) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and content parameters required.";
            return;
        }
        if (!PathIsInsideWorkspace(targetPath, ws)) {
            *outErrCode = @"outside_workspace";
            *outErrMsg = @"Target path must be inside workspace.";
            return;
        }
        NSUInteger contentBytes = [content lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (contentBytes > kMaxFileTextBytes) {
            *outErrCode = @"file_too_large";
            *outErrMsg = @"Content exceeds write cap.";
            return;
        }
        BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:targetPath];
        if ([method isEqualToString:@"file.create"] && existed) {
            *outErrCode = @"already_exists";
            *outErrMsg = [NSString stringWithFormat:@"File already exists: %@", targetPath];
            return;
        }
        NSString* beforeText = existed ? [self safeTextForFileAtPath:targetPath] : @"";
        if (existed && beforeText == nil) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"Existing file is not readable as UTF-8 text.";
            return;
        }
        NSString* errStr = nil;
        BOOL ok = [self.windowController writeFileAtPath:targetPath content:content errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"write_failed";
            *outErrMsg = errStr ?: @"Failed to write file.";
            return;
        }
        NSString* afterText = [self safeTextForFileAtPath:targetPath] ?: content;
        [_patchService recordMutationRecords:@[@{
            @"path": targetPath,
            @"beforeText": beforeText ?: @"",
            @"beforeHash": StableHashForString(beforeText ?: @""),
            @"postHash": StableHashForString(afterText ?: @""),
            @"existed": @(existed)
        }]];
        NSString* key = [method isEqualToString:@"file.create"] ? @"created" : @"written";
        *outResult = @{ key: @YES, @"path": targetPath, @"sizeBytes": @(contentBytes) };
        return;
    }
}

@end
