#import "MacControlServer.hpp"
#import "MacWindow.hpp"
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
    std::filesystem::path pathAbs = std::filesystem::weakly_canonical(std::filesystem::path(StdStringFromNSString(path)), ec);
    if (ec) return NO;
    std::filesystem::path wsAbs = std::filesystem::weakly_canonical(std::filesystem::path(StdStringFromNSString(workspace)), ec);
    if (ec) return NO;
    auto rel = std::filesystem::relative(pathAbs, wsAbs, ec);
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

@implementation DietCodeControlServer {
    int _serverFd;
    NSThread* _acceptThread;
    NSString* _lastVerifyCommand;
}

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller {
    self = [super init];
    if (self) {
        _windowController = controller;
        _isRunning = NO;
        _serverFd = -1;
    }
    return self;
}

- (void)start {
    if (_isRunning) return;
    
    NSString* homeDir = NSHomeDirectory();
    NSString* dcDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dcDir withIntermediateDirectories:YES attributes:nil error:nil];
    
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
            [self processRequest:line clientFd:clientFd];
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
    
    NSString* caller = @"unix_socket";
    NSString* permission = [self permissionLevelForMethod:method params:params];
    [_windowController setControlActiveCommand:method caller:caller];
    
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
        [_windowController setControlActiveCommand:nil caller:caller];
        
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
    
    dispatch_semaphore_t execSem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self executeMethod:method params:params outResult:&result outErrCode:&errCode outErrMsg:&errMsg outPaths:&affectedPaths];
        dispatch_semaphore_signal(execSem);
    });
    dispatch_semaphore_wait(execSem, DISPATCH_TIME_FOREVER);
    
    [_windowController setControlActiveCommand:nil caller:caller];
    
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
            @{ @"name": @"workspace.getRoot", @"permission": @"Read", @"params": @{}, @"returns": @{ @"path": @"string" } },
            @{ @"name": @"workspace.openFolder", @"permission": @"Destructive", @"params": @{ @"path": @"directory path" }, @"returns": @{ @"opened": @"boolean" } },
            @{ @"name": @"workspace.listFiles", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
            @{ @"name": @"workspace.grep", @"permission": @"Read", @"params": @{ @"query": @"string", @"maxResults": @"number <= 500 optional" }, @"returns": @{ @"matches": @"array with contextBefore/contextAfter" } },
            @{ @"name": @"workspace.openFile", @"permission": @"Read", @"params": @{ @"path": @"string" }, @"returns": @{ @"opened": @"boolean" } },
            @{ @"name": @"workspace.getRecentFiles", @"permission": @"Read", @"params": @{}, @"returns": @{ @"files": @"array" } },
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

- (NSDictionary*)verificationStatus {
    NSString* output = [_windowController terminalOutput] ?: @"";
    NSString* command = _lastVerifyCommand ?: @"";
    NSString* markerPrefix = [NSString stringWithFormat:@"[DietCode verify] command=%@ exit=", command];
    NSRange range = [output rangeOfString:markerPrefix options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return @{
            @"command": command,
            @"state": command.length > 0 ? @"running_or_unknown" : @"idle",
            @"exitCode": [NSNull null],
            @"passed": @NO
        };
    }
    NSUInteger start = NSMaxRange(range);
    NSUInteger end = start;
    while (end < output.length) {
        unichar c = [output characterAtIndex:end];
        if (c < '0' || c > '9') break;
        end++;
    }
    NSInteger exitCode = [[output substringWithRange:NSMakeRange(start, end - start)] integerValue];
    return @{
        @"command": command,
        @"state": @"complete",
        @"exitCode": @(exitCode),
        @"passed": @(exitCode == 0)
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
        [method isEqualToString:@"language.lint"] ||
        [method isEqualToString:@"language.format"]) {
        return @"Execute";
    }
    
    if ([method isEqualToString:@"editor.insertText"] || 
        [method isEqualToString:@"editor.replaceSelection"] || 
        [method isEqualToString:@"editor.replaceRange"] || 
        [method isEqualToString:@"editor.applyPatch"] || 
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
        ![method isEqualToString:@"diff.applyPatchPreview"]) {
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
        *outResult = @{ @"pong": @YES, @"server": @"DietCodeControlServer", @"version": @"1.3" };
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
        NSString* absPath = params[@"path"];
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
        BOOL ok = [_windowController replaceTextInRange:range withText:text forFileAtPath:targetPath];
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
        NSString* errStr = nil;
        BOOL ok = [_windowController applyPatchAtPath:targetPath patchString:patchStr errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"patch_failed";
            *outErrMsg = errStr ?: @"Unknown patch application error.";
            return;
        }
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
        _lastVerifyCommand = [command copy];
        NSString* shellCommand = [NSString stringWithFormat:@"%@; printf '\\n[DietCode verify] command=%@ exit=%%s\\n' \"$?\"", command, command];
        [_windowController runTerminalCommand:shellCommand cwd:[_windowController workspacePath] show:YES];
        *outResult = @{ @"started": @YES, @"command": command, @"visible": @YES, @"stoppable": @YES };
        return;
    }

    if ([method isEqualToString:@"verify.last"] || [method isEqualToString:@"verify.status"]) {
        NSDictionary* status = [self verificationStatus];
        *outResult = @{ @"command": _lastVerifyCommand ?: @"", @"status": status };
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

- (void)sendError:(NSString*)reqId code:(NSString*)code message:(NSString*)message clientFd:(int)clientFd {
    NSDictionary* resp = @{
        @"id": reqId,
        @"ok": @NO,
        @"error": @{
            @"code": code,
            @"message": message
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
    NSString* logPath = [[homeDir stringByAppendingPathComponent:@".dietcode"] stringByAppendingPathComponent:@"control_audit.log"];
    
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString* timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString* logLine = [NSString stringWithFormat:@"[%@] caller: %@ | method: %@ | permission: %@ | duration: %lldms | result: %@ | paths: %@\n", 
                         timestamp, caller, method, permission, duration, result, paths ?: @""];
    
    std::ofstream out([logPath UTF8String], std::ios::app);
    if (out.is_open()) {
        out << [logLine UTF8String];
        out.close();
    }
}

@end
