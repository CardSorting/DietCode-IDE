#import "MacControlServer.hpp"
#import "MacWindow.hpp"
#import <CommonCrypto/CommonDigest.h>
#import "SymbolIndexService.hpp"
#import "DiffAnalysisService.hpp"
#import "WorkspaceAnalysisService.hpp"
#import "BufferStateService.hpp"
#import "SubprocessRunner.hpp"

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
#include <signal.h>
#include <algorithm>
#include <cctype>
#include "filesystem/PathUtils.hpp"

#import "MacControlSupport.hpp"
#import "MacControlPathSecurity.hpp"
#import "MacControlSerialization.hpp"
#import "MacControlDiffParsing.hpp"
#import "MacControlWindowBridge.hpp"
#import "MacControlRoutingPolicy.hpp"
#import "MacControlMethodCatalog.hpp"
#import "MacControlSearchService.hpp"
#import "MacControlRecoveryStore.hpp"
#import "MacControlPatchService.hpp"
#import "MacControlTaskRuntime.hpp"
#import "MacControlComboRuntime.hpp"

@interface DietCodeClientConnection : NSObject
@property (nonatomic, assign) int fd;
@property (nonatomic, assign) BOOL readEOF;
@property (nonatomic, assign) NSInteger pendingRequestsCount;
@end

@implementation DietCodeClientConnection
@end

@interface DietCodeControlServer ()

- (void)acceptLoop;
- (void)handleClient:(DietCodeClientConnection*)conn;
- (void)processRequest:(const std::string&)requestStr connection:(DietCodeClientConnection*)conn;
- (void)markConnectionEOF:(DietCodeClientConnection*)conn;
- (void)decrementPendingRequestsForConnection:(DietCodeClientConnection*)conn;
- (NSString*)permissionLevelForMethod:(NSString*)method params:(NSDictionary*)params;
- (void)executeMethod:(NSString*)method params:(NSDictionary*)params outResult:(NSDictionary**)outResult outErrCode:(NSString**)outErrCode outErrMsg:(NSString**)outErrMsg outPaths:(NSString**)outPaths;
- (void)sendError:(NSString*)reqId code:(id)code message:(NSString*)message clientFd:(int)clientFd;
- (void)sendSuccess:(NSString*)reqId result:(NSDictionary*)result clientFd:(int)clientFd;
- (void)logAuditMethod:(NSString*)method caller:(NSString*)caller permission:(NSString*)permission duration:(long long)duration result:(NSString*)result paths:(NSString*)paths;
- (NSString*)chipNameForStep:(NSDictionary*)step;
- (NSDictionary*)paramsForComboStep:(NSDictionary*)step;
- (NSArray<NSDictionary*>*)rpcMethodDescriptions;
- (NSDictionary*)descriptionForRPCMethod:(NSString*)method;
- (NSArray<NSDictionary*>*)chipRegistry;
- (NSDictionary*)metadataForChip:(NSString*)chip;
- (NSDictionary*)primitiveForChip:(NSString*)chip params:(NSDictionary*)params;

- (BOOL)isDestructiveRequestSafe:(NSString*)method params:(NSDictionary*)params;
- (NSDictionary*)currentChangesInfo;
- (NSDictionary*)runVerificationCommand:(NSString*)command cwd:(NSString*)cwd;
- (NSDictionary*)verificationStatus;
- (NSDictionary*)contextSnapshotPayload;
- (NSArray<NSString*>*)verificationFailureLines;
- (BOOL)path:(NSString*)path isAllowedByScope:(NSDictionary*)scope;
- (BOOL)dirtyBufferExistsAtPath:(NSString*)path;
- (NSDictionary*)repairContextForFailure:(NSString*)failure params:(NSDictionary*)params;

@end

@implementation DietCodeControlServer {
    DietCodeControlWindowBridge* _windowBridge;
    MacControlRecoveryStore* _recoveryStore;
    MacControlSearchService* _searchService;
    MacControlPatchService* _patchService;
    MacControlTaskRuntime* _taskRuntime;
    int _serverFd;
    NSThread* _acceptThread;
    NSString* _lastVerifyCommand;
    NSDate* _lastVerifyStartedAt;
    NSDate* _lastVerifyFinishedAt;
    NSNumber* _lastVerifyExitCode;
    NSMutableDictionary<NSString*, NSDictionary*>* _contextSnapshots;
    NSInteger _contextSnapshotCounter;
    NSMutableDictionary<NSString*, NSDictionary*>* _editPlans;
    NSInteger _editPlanCounter;
    MacControlComboRuntime* _comboRuntime;
    NSInteger _comboCounter;
    NSMutableDictionary<NSNumber*, DietCodeClientConnection*>* _activeConnections;
    NSString* _sessionToken;
    dispatch_queue_t _executionQueue;
    dispatch_queue_t _readQueue;
    BOOL _globalMutationLock;
    NSDictionary* _lastVerifyStatus;
    NSString* _lastComboId;
}

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller {
    self = [super init];
    if (self) {
        _windowController = controller;
        _windowBridge = [[DietCodeControlWindowBridge alloc] initWithWindowController:controller];
        _searchService = [[MacControlSearchService alloc] initWithWindowBridge:_windowBridge];
        _recoveryStore = [[MacControlRecoveryStore alloc] initWithWindowBridge:_windowBridge];
        _patchService = [[MacControlPatchService alloc] initWithWindowBridge:_windowBridge];
        
        __weak DietCodeControlServer* weakSelf = self;
        _taskRuntime = [[MacControlTaskRuntime alloc] initWithWindowBridge:_windowBridge
                                                              patchService:_patchService
                                                             searchService:_searchService
                                                                  executor:^(NSString* method, NSDictionary* params, NSDictionary** outResult, NSString** outErrCode, NSString** outErrMsg, NSString** outPaths) {
            [weakSelf executeMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
        }];
        
        _comboRuntime = [[MacControlComboRuntime alloc] initWithWindowBridge:_windowBridge
                                                               recoveryStore:_recoveryStore
                                                                patchService:_patchService
                                                                 taskRuntime:_taskRuntime
                                                                    executor:^(NSString *method, NSDictionary *params, NSDictionary *__autoreleasing *outResult, NSString *__autoreleasing *outErrCode, NSString *__autoreleasing *outErrMsg, NSString *__autoreleasing *outPaths) {
            [weakSelf executeMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
        }];

        _isRunning = NO;
        _serverFd = -1;
        _contextSnapshots = [NSMutableDictionary dictionary];
        _contextSnapshotCounter = 0;
        _activeConnections = [NSMutableDictionary dictionary];
        _sessionToken = nil;
        _executionQueue = dispatch_queue_create("com.dietcode.runtime.execution", DISPATCH_QUEUE_SERIAL);
        _readQueue = dispatch_queue_create("com.dietcode.runtime.read", DISPATCH_QUEUE_CONCURRENT);
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
    return [_windowBridge workspacePath];
}

- (NSString*)safeTextForFileAtPath:(NSString*)path {
    return [_windowBridge textForFileAtPath:path];
}

- (BOOL)safeReplaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path {
    return [_windowBridge replaceTextInRange:range withText:text forFileAtPath:path];
}

- (NSArray<NSString*>*)safeOpenFilePaths {
    return [_windowBridge openFilePaths];
}

- (NSArray<NSDictionary*>*)safeProblemsList {
    return [_windowBridge problemsList];
}

- (NSString*)safeActiveFilePath {
    return [_windowBridge activeFilePath];
}

- (NSArray*)safeOpenTabs {
    return [_windowBridge openTabs];
}

- (NSDictionary*)safeGitStatusInfo {
    return [_windowBridge gitStatusInfo];
}

- (NSString*)safeGitDiffForFile:(NSString*)path {
    return [_windowBridge gitDiffForFile:path];
}

- (NSDictionary*)safeActiveSelectionInfo {
    return [_windowBridge activeSelectionInfo];
}

- (NSString*)safeTerminalOutput {
    return [_windowBridge terminalOutput];
}

- (NSArray*)safeSessionRecentCommands {
    return [_windowBridge sessionRecentCommands];
}

- (NSArray*)safeSessionLastSearches {
    return [_windowBridge sessionLastSearches];
}

- (pid_t)safeTerminalPid {
    return [_windowBridge terminalPid];
}

- (NSArray*)safeLanguageDiagnosticsForPath:(NSString*)path {
    return [_windowBridge languageDiagnosticsForPath:path];
}

- (NSInteger)safeAgentAutonomyLevel {
    return [_windowBridge agentAutonomyLevel];
}

- (void)start {
    if (_isRunning) return;
    
    signal(SIGPIPE, SIG_IGN);
    
    NSString* homeDir = NSHomeDirectory();
    NSString* dcDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
    
    // Pre-verify ~/.dietcode directory owner and symlink safety
    struct stat st;
    if (lstat([dcDir UTF8String], &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            [self appendLogLine:@"[Error] ~/.dietcode is a symbolic link. Aborting for security."];
            return;
        }
        if (st.st_uid != getuid()) {
            [self appendLogLine:@"[Error] ~/.dietcode is owned by a different user. Aborting for security."];
            return;
        }
    } else {
        [[NSFileManager defaultManager] createDirectoryAtPath:dcDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700)} error:nil];
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0700)} ofItemAtPath:dcDir error:nil];
    
    // Generate session token
    NSString* token = [NSString stringWithFormat:@"%08x%08x%08x%08x", 
                       arc4random(), arc4random(), arc4random(), arc4random()];
    NSString* tokenPath = [dcDir stringByAppendingPathComponent:@"session.token"];
    unlink([tokenPath UTF8String]); // Prevent symlink overwrite write exploits
    [token writeToFile:tokenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:tokenPath error:nil];
    _sessionToken = [token copy];
    
    NSString* sockPathStr = [dcDir stringByAppendingPathComponent:@"control.sock"];
    const char* sockPath = [sockPathStr UTF8String];
    
    _serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_serverFd < 0) {
        [self appendLogLine:@"[Error] Failed to create Unix socket."];
        return;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(sockPath) >= sizeof(addr.sun_path)) {
        [self appendLogLine:[NSString stringWithFormat:@"[Error] Unix socket path is too long: %lu bytes (max %lu bytes). Can't bind.", strlen(sockPath), sizeof(addr.sun_path) - 1]];
        close(_serverFd);
        _serverFd = -1;
        return;
    }
    strncpy(addr.sun_path, sockPath, sizeof(addr.sun_path) - 1);
    
    unlink(sockPath); // Delete stale socket if any
    
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
    
    @synchronized(self) {
        for (NSNumber* fdNum in _activeConnections) {
            DietCodeClientConnection* conn = _activeConnections[fdNum];
            shutdown(conn.fd, SHUT_RDWR);
        }
    }
    
    NSString* dcDir = [NSHomeDirectory() stringByAppendingPathComponent:@".dietcode"];
    unlink([[dcDir stringByAppendingPathComponent:@"control.sock"] UTF8String]);
    unlink([[dcDir stringByAppendingPathComponent:@"session.token"] UTF8String]);
    
    [self appendLogLine:@"[System] External Control Server stopped."];
    [_windowController setControlActiveCommand:nil caller:nil];
}

- (void)acceptLoop {
    while (_isRunning && _serverFd >= 0) {
        @autoreleasepool {
            struct sockaddr_un clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientFd = accept(_serverFd, (struct sockaddr*)&clientAddr, &clientLen);
            if (clientFd < 0) {
                if (!_isRunning) return;
                if (errno != EINTR) {
                    [self appendLogLine:[NSString stringWithFormat:@"[Error] accept() failed with errno %d: %s", errno, strerror(errno)]];
                }
                usleep(100000); // 100ms backoff on error
            } else {
                int optval = 1;
                setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &optval, sizeof(optval));
                
                DietCodeClientConnection* conn = [[DietCodeClientConnection alloc] init];
                conn.fd = clientFd;
                conn.readEOF = NO;
                conn.pendingRequestsCount = 0;
                
                @synchronized(self) {
                    if (!_isRunning) {
                        close(clientFd);
                    } else {
                        _activeConnections[@(clientFd)] = conn;
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [self handleClient:conn];
                        });
                    }
                }
            }
        }
    }
}

- (BOOL)isReadQueueMethod:(NSString*)method {
    return MacControlIsReadQueueMethod(method);
}


- (dispatch_queue_t)queueForRequestLine:(const std::string&)line {
    NSData* data = [NSData dataWithBytes:line.data() length:line.size()];
    NSDictionary* req = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString* method = [req isKindOfClass:[NSDictionary class]] ? req[@"method"] : nil;
    return [self isReadQueueMethod:method] ? _readQueue : _executionQueue;
}

- (void)handleClient:(DietCodeClientConnection*)conn {
    int clientFd = conn.fd;
    std::string buffer;
    char readBuf[4096];
    BOOL connectionActive = YES;
    
    while (_isRunning && connectionActive) {
        @autoreleasepool {
            ssize_t bytes = read(clientFd, readBuf, sizeof(readBuf));
            if (bytes < 0) {
                if (errno == EINTR) {
                    continue;
                }
                connectionActive = NO;
            } else if (bytes == 0) {
                connectionActive = NO;
            } else {
                buffer.append(readBuf, bytes);
                if (buffer.size() > kMaxRequestBytes) {
                    [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
                    buffer.clear();
                    connectionActive = NO;
                } else {
                    size_t newlinePos;
                    while ((newlinePos = buffer.find('\n')) != std::string::npos) {
                        std::string line = buffer.substr(0, newlinePos);
                        buffer.erase(0, newlinePos + 1);
                        
                        if (line.empty()) continue;
                        if (line.size() > kMaxRequestBytes) {
                            [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
                            continue;
                        }
                        
                        @synchronized(self) {
                            conn.pendingRequestsCount++;
                        }
                        
                        dispatch_async([self queueForRequestLine:line], ^{
                            @autoreleasepool {
                                [self processRequest:line connection:conn];
                            }
                        });
                    }
                }
            }
        }
    }
    
    [self markConnectionEOF:conn];
}

- (void)markConnectionEOF:(DietCodeClientConnection*)conn {
    BOOL shouldClose = NO;
    @synchronized(self) {
        conn.readEOF = YES;
        if (conn.pendingRequestsCount == 0) {
            shouldClose = YES;
            [_activeConnections removeObjectForKey:@(conn.fd)];
        }
    }
    if (shouldClose) {
        close(conn.fd);
    }
}

- (void)decrementPendingRequestsForConnection:(DietCodeClientConnection*)conn {
    BOOL shouldClose = NO;
    @synchronized(self) {
        conn.pendingRequestsCount--;
        if (conn.readEOF && conn.pendingRequestsCount == 0) {
            shouldClose = YES;
            [_activeConnections removeObjectForKey:@(conn.fd)];
        }
    }
    if (shouldClose) {
        close(conn.fd);
    }
}

- (void)processRequest:(const std::string&)requestStr connection:(DietCodeClientConnection*)conn {
    @try {
        int clientFd = conn.fd;
        auto startTime = std::chrono::high_resolution_clock::now();
        if (requestStr.size() > kMaxRequestBytes) {
            [self sendError:@"unknown" code:@"request_too_large" message:@"Request exceeds maximum allowed size." clientFd:clientFd];
            [self logAuditMethod:@"invalid" caller:@"unknown" permission:@"none" duration:0 result:@"request_too_large" paths:@""];
            return;
        }
        
        NSData* reqData = [NSData dataWithBytes:requestStr.data() length:requestStr.size()];
        NSError* jsonErr = nil;
        id reqObj = [NSJSONSerialization JSONObjectWithData:reqData options:0 error:&jsonErr];
        if (jsonErr || ![reqObj isKindOfClass:[NSDictionary class]]) {
            [self sendError:@"unknown" code:@"invalid_request" message:@"Malformed JSON request object." clientFd:clientFd];
            [self logAuditMethod:@"invalid" caller:@"unknown" permission:@"none" duration:0 result:@"failed" paths:@""];
            return;
        }
        
        NSDictionary* req = (NSDictionary*)reqObj;
        NSString* reqId = RequestIdString(req[@"id"]);
        id methodObj = req[@"method"];
        if (![methodObj isKindOfClass:[NSString class]] || [methodObj length] == 0) {
            [self sendError:reqId code:@"invalid_request" message:@"Malformed JSON or missing method." clientFd:clientFd];
            [self logAuditMethod:@"invalid" caller:@"unknown" permission:@"none" duration:0 result:@"failed" paths:@""];
            return;
        }
        NSString* method = (NSString*)methodObj;
        id paramsObj = req[@"params"];
        if (paramsObj && ![paramsObj isKindOfClass:[NSDictionary class]]) {
            [self sendError:reqId code:@"invalid_params" message:@"params must be a JSON object." clientFd:clientFd];
            [self logAuditMethod:method caller:@"unknown" permission:@"none" duration:0 result:@"invalid_params" paths:@""];
            return;
        }
        NSDictionary* params = paramsObj ?: @{};
        id schemaObj = req[@"schemaVersion"];
        if (schemaObj && (![schemaObj isKindOfClass:[NSString class]] ||
                          (![(NSString*)schemaObj isEqualToString:@"1.6"] && ![(NSString*)schemaObj isEqualToString:@"1.6.2"]))) {
            [self sendError:reqId code:@"invalid_request" message:@"Unsupported RPC schemaVersion." clientFd:clientFd];
            [self logAuditMethod:method caller:@"unknown" permission:@"none" duration:0 result:@"invalid_schema" paths:@""];
            return;
        }
        
        // Validate session token
        id tokenObj = req[@"token"];
        NSString* token = [tokenObj isKindOfClass:[NSString class]] ? (NSString*)tokenObj : nil;
        if (!_sessionToken || !token || ![token isEqualToString:_sessionToken]) {
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
            NSInteger autonomy = [self safeAgentAutonomyLevel];
            if (autonomy == 1 || _windowController.isHeadless) {
                allowed = YES;
            } else if (autonomy == 2) {
                allowed = [self isDestructiveRequestSafe:method params:params];
            } else {
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
            }
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
        
        // Check if the method runs on a worker queue or needs main-thread mutation APIs.
        BOOL isBackgroundMethod = [method isEqualToString:@"verify.run"] ||
                                  [self isReadQueueMethod:method] ||
                                  [method isEqualToString:@"combo.run"] ||
                                  [method isEqualToString:@"combo.status"] ||
                                  [method isEqualToString:@"combo.result"] ||
                                  [method isEqualToString:@"combo.cancel"] ||
                                  [method isEqualToString:@"combo.rollback"] ||
                                  [method isEqualToString:@"verify.last"] ||
                                  [method isEqualToString:@"verify.status"] ||
                                  [method isEqualToString:@"verify.failures"] ||
                                  [method isEqualToString:@"context.snapshot"] ||
                                  [method isEqualToString:@"context.delta"] ||
                                  [method isEqualToString:@"task.start"] ||
                                  [method isEqualToString:@"task.status"] ||
                                  [method isEqualToString:@"task.result"] ||
                                  [method isEqualToString:@"task.cancel"] ||
                                  [method isEqualToString:@"task.step"] ||
                                  [method isEqualToString:@"task.runLoop"] ||
                                  [method isEqualToString:@"edit.plan"] ||
                                  [method isEqualToString:@"edit.executePlan"];
        
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
    } @finally {
        [self decrementPendingRequestsForConnection:conn];
    }
}

- (NSArray<NSDictionary*>*)rpcMethodDescriptions {
    return MacControlRPCMethodDescriptions();
}

- (NSDictionary*)descriptionForRPCMethod:(NSString*)method {
    return MacControlDescriptionForRPCMethod(method);
}

- (NSArray<NSDictionary*>*)chipRegistry {
    return MacControlChipRegistry();
}

- (NSDictionary*)metadataForChip:(NSString*)chip {
    return MacControlMetadataForChip(chip);
}

- (NSDictionary*)primitiveForChip:(NSString*)chip params:(NSDictionary*)params {
    return MacControlPrimitiveForChip(chip, params);
}

- (NSString*)chipNameForStep:(NSDictionary*)step {
    NSString* chip = step[@"chip"];
    if (chip.length > 0) return CanonicalChipName(chip);
    NSDictionary* primitive = [_taskRuntime primitiveForWorkbenchStep:step];
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



- (BOOL)isDestructiveRequestSafe:(NSString*)method params:(NSDictionary*)params {
    NSString* ws = [self safeWorkspacePath];
    if (!ws) return NO;
    
    if ([method isEqualToString:@"git.commit"]) {
        return YES; // Git commit inside the active workspace repo is safe
    }
    if ([method isEqualToString:@"workspace.openFolder"]) {
        return NO; // Opening a new workspace is unsafe / outside current bounds
    }
    
    // Check path parameter if present
    NSString* path = params[@"path"];
    if (path) {
        NSString* checkedPath = AbsolutePathForRPCPath(path, ws);
        if (!PathIsInsideWorkspace(checkedPath, ws)) {
            return NO;
        }
    }
    
    // Check patch.applyBatch which has a 'patches' parameter
    if ([method isEqualToString:@"patch.applyBatch"]) {
        NSArray* patches = params[@"patches"];
        if ([patches isKindOfClass:[NSArray class]]) {
            for (NSDictionary* patchDict in patches) {
                if ([patchDict isKindOfClass:[NSDictionary class]]) {
                    NSString* pPath = patchDict[@"path"];
                    if (pPath) {
                        NSString* checkedPath = AbsolutePathForRPCPath(pPath, ws);
                        if (!PathIsInsideWorkspace(checkedPath, ws)) {
                            return NO;
                        }
                    }
                }
            }
        }
    }
    
    // Check combo.run steps
    if ([method isEqualToString:@"combo.run"]) {
        NSDictionary* comboReq = params[@"combo"] ?: params;
        for (NSDictionary* step in comboReq[@"steps"] ?: @[]) {
            NSString* chip = step[@"chip"];
            if (chip.length == 0) continue;
            NSDictionary* stepParams = step[@"params"];
            if ([chip isEqualToString:@"patch.apply"]) {
                NSString* pPath = stepParams[@"path"];
                if (pPath) {
                    NSString* checkedPath = AbsolutePathForRPCPath(pPath, ws);
                    if (!PathIsInsideWorkspace(checkedPath, ws)) return NO;
                }
            }
            if ([chip isEqualToString:@"patch.applyBatch"]) {
                for (NSDictionary* p in stepParams[@"patches"] ?: @[]) {
                    NSString* pPath = p[@"path"];
                    if (pPath) {
                        NSString* checkedPath = AbsolutePathForRPCPath(pPath, ws);
                        if (!PathIsInsideWorkspace(checkedPath, ws)) return NO;
                    }
                }
            }
        }
    }
    
    return YES;
}

- (NSDictionary*)currentChangesInfo {
    NSString* ws = [_windowBridge workspacePath] ?: @"";
    NSDictionary* git = [self safeGitStatusInfo] ?: @{};
    NSDictionary* diffInfo = ws.length > 0 ? [DietCodeDiffAnalysisService workspaceDiffInfo:ws] : @{};
    NSMutableArray* files = [NSMutableArray array];

    for (NSDictionary* file in diffInfo[@"files"] ?: @[]) {
        NSString* relPath = file[@"path"] ?: @"";
        NSString* absPath = AbsolutePathForRPCPath(relPath, ws);
        NSString* text = [self safeTextForFileAtPath:absPath] ?: @"";
        NSArray* symbols = text.length > 0 ? [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[absPath pathExtension] lowercaseString]] : @[];
        NSString* diff = [self safeGitDiffForFile:absPath] ?: @"";
        NSMutableDictionary* enriched = [file mutableCopy];
        enriched[@"absolutePath"] = absPath ?: @"";
        enriched[@"affectedSymbols"] = AffectedSymbolsForPatch(diff, symbols);
        [files addObject:enriched];
    }

    NSArray* dirtyFiles = DirtyFilePathsFromTabs([self safeOpenTabs] ?: @[]);
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
    NSString* ws = [self safeWorkspacePath];
    NSString* runCwd = cwd.length > 0 ? cwd : ws;
    
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
    
    [self appendLogLine:[NSString stringWithFormat:@"[Verify] Starting command: %@", command]];

    std::vector<std::string> args = {"-c", [command UTF8String]};
    using namespace dietcode::platform::macos;
    SubprocessResult res = SubprocessRunner::run("/bin/zsh", args, [runCwd UTF8String] ?: "", 60.0);
    
    _lastVerifyFinishedAt = [NSDate date];
    _lastVerifyExitCode = @(res.exitCode);
    
    if (res.timedOut) {
        _lastVerifyStatus = @{
            @"command": command,
            @"state": @"complete",
            @"exitCode": @(-2),
            @"passed": @NO,
            @"startedAt": ISODateString(_lastVerifyStartedAt),
            @"finishedAt": ISODateString(_lastVerifyFinishedAt),
            @"error": @"Command timed out after 60s"
        };
        [self appendLogLine:@"[Verify] Error: Command timed out after 60s"];
        return _lastVerifyStatus;
    }

    if (!res.stdOut.empty()) {
        [self appendLogLine:[NSString stringWithUTF8String:res.stdOut.c_str()]];
    }
    if (!res.stdErr.empty()) {
        [self appendLogLine:[NSString stringWithFormat:@"[Stderr] %s", res.stdErr.c_str()]];
    }
    
    NSTimeInterval duration = [_lastVerifyFinishedAt timeIntervalSinceDate:_lastVerifyStartedAt];
    _lastVerifyStatus = @{
        @"command": command,
        @"state": @"complete",
        @"exitCode": @(res.exitCode),
        @"passed": @(res.exitCode == 0),
        @"startedAt": ISODateString(_lastVerifyStartedAt),
        @"finishedAt": ISODateString(_lastVerifyFinishedAt),
        @"durationMs": @((NSInteger)(duration * 1000.0))
    };
    
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
    NSDictionary* git = [self safeGitStatusInfo] ?: @{};
    NSArray* problems = [self safeProblemsList] ?: @[];
    return @{
        @"activeFile": [self safeActiveFilePath] ?: @"",
        @"openFiles": [self safeOpenFilePaths] ?: @[],
        @"dirtyFiles": DirtyFilePathsFromTabs([self safeOpenTabs] ?: @[]),
        @"currentBranch": git[@"branch"] ?: @"",
        @"recentSearches": [self safeSessionLastSearches] ?: @[],
        @"recentCommands": [self safeSessionRecentCommands] ?: @[],
        @"problemCount": @(problems.count),
        @"changes": [self currentChangesInfo]
    };
}

- (NSArray<NSString*>*)verificationFailureLines {
    NSMutableArray* failures = [NSMutableArray array];
    NSString* output = [self safeTerminalOutput] ?: @"";
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

- (BOOL)path:(NSString*)path isAllowedByScope:(NSDictionary*)scope {
    NSString* ws = [self safeWorkspacePath];
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
    NSString* ws = [self safeWorkspacePath];
    NSString* absPath = AbsolutePathForRPCPath(path, ws);
    for (id tab in [self safeOpenTabs] ?: @[]) {
        NSString* tabPath = [tab valueForKey:@"path"];
        BOOL dirty = [[tab valueForKey:@"dirty"] boolValue];
        if (dirty && [tabPath isEqualToString:absPath]) return YES;
    }
    return NO;
}

- (NSDictionary*)repairContextForFailure:(NSString*)failure params:(NSDictionary*)params {
    NSString* ws = [self safeWorkspacePath];
    NSMutableArray* files = [NSMutableArray array];
    for (NSDictionary* file in params[@"files"] ?: @[]) {
        NSString* path = file[@"path"];
        NSMutableArray* ranges = [NSMutableArray array];
        for (NSDictionary* range in file[@"ranges"] ?: @[]) {
            NSInteger start = [range[@"startLine"] integerValue];
            NSInteger end = [range[@"endLine"] integerValue];
            NSString* text = nil;
            NSString* absPath = AbsolutePathForRPCPath(path, ws);
            NSString* full = [self safeTextForFileAtPath:absPath];
            if (full) text = TextForLineRange(LinesFromText(full), start, end);
            [ranges addObject:@{ @"startLine": @(start), @"endLine": @(end), @"text": text ?: @"" }];
        }
        [files addObject:@{ @"path": path ?: @"", @"ranges": ranges }];
    }
    return @{
        @"failure": failure ?: @"unknown",
        @"files": files,
        @"diagnostics": params[@"diagnostics"] ?: ([self safeProblemsList] ?: @[]),
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
        NSString* ws = [self safeWorkspacePath];
        if (cwd && ws) {
            std::error_code ec;
            std::filesystem::path cwdPath(StdStringFromNSString(cwd));
            std::filesystem::path wsPath(StdStringFromNSString(ws));
            auto cwdAbs = std::filesystem::weakly_canonical(cwdPath, ec);
            if (ec) return @"Destructive";
            auto wsAbs = std::filesystem::weakly_canonical(wsPath, ec);
            if (ec) return @"Destructive";
            auto rel = std::filesystem::relative(cwdAbs, wsAbs, ec);
            if (ec || rel.string().rfind("..", 0) == 0 || rel.is_absolute()) {
                return @"Destructive";
            }
        }
        return @"Execute";
    }

    if ([method isEqualToString:@"terminal.status"] ||
        [method isEqualToString:@"terminal.jobs"] ||
        [method isEqualToString:@"terminal.history"] ||
        [method isEqualToString:@"terminal.getOutput"]) {
        return @"Read";
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
        [method isEqualToString:@"file.write"] ||
        [method isEqualToString:@"file.create"] ||
        [method isEqualToString:@"patch.revertLast"] ||
        [method isEqualToString:@"combo.rollback"] ||
        [method isEqualToString:@"task.step"] ||
        [method isEqualToString:@"git.stage"] || 
        [method isEqualToString:@"git.unstage"] ||
        [method isEqualToString:@"editor.closeFile"] ||
        [method isEqualToString:@"problems.open"] ||
        [method isEqualToString:@"problems.clearSource"] ||
        [method isEqualToString:@"editor.setSelection"] ||
        [method isEqualToString:@"recovery.deleteBackup"] ||
        [method isEqualToString:@"recovery.prune"]) {
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
        NSString* ws = [self safeWorkspacePath];
        NSString* checkedPath = AbsolutePathForRPCPath(path, ws);
        *outPaths = checkedPath;
        if (ws && !PathIsInsideWorkspace(checkedPath, ws)) {
            *outErrCode = @"outside_workspace";
            *outErrMsg = @"Target path is outside active workspace folder.";
            return;
        }
    }

    if ([method isEqualToString:@"rpc.ping"]) {
        *outResult = @{ @"pong": @YES, @"server": @"DietCodeControlServer", @"version": kDietCodeAppVersion };
        return;
    }

    if ([method isEqualToString:@"rpc.version"]) {
        *outResult = @{
            @"appVersion": kDietCodeAppVersion,
            @"controlProtocolVersion": @"1.6",
            @"transactionSchemaVersion": @"1.6.2",
            @"supportedRollbackSchemas": @[@"1.6.2"],
            @"supportedInspectOnlySchemas": @[@"1.6.1"]
        };
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
        NSDictionary* plan = params[@"combo"] ?: params;
        NSDictionary* normalizedPlan = nil;
        NSArray* errors = nil;
        BOOL ok = [_comboRuntime validateCombo:plan normalizedPlan:&normalizedPlan errors:&errors];
        *outResult = @{
            @"ok": @(ok),
            @"errors": errors ?: @[],
            @"plan": normalizedPlan ?: @{}
        };
        return;
    }

    if ([method isEqualToString:@"combo.run"]) {
        NSDictionary* comboReq = params[@"combo"] ?: params;
        NSString* comboId = comboReq[@"comboId"] ?: [NSString stringWithFormat:@"combo-%ld", (long)++_comboCounter];
        
        NSDictionary* plan = nil;
        NSArray* errors = nil;
        if (![_comboRuntime validateCombo:comboReq normalizedPlan:&plan errors:&errors]) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"Combo validation failed.";
            *outResult = @{ @"errors": errors ?: @[] };
            return;
        }

        if ([_comboRuntime activeComboCount] >= (NSUInteger)kMaxActiveCombos) {
            *outErrCode = @"resource_exhausted";
            *outErrMsg = @"Maximum number of active combos reached.";
            return;
        }

        *outResult = [_comboRuntime runComboWithPlan:plan comboId:comboId sessionToken:_sessionToken];
        return;
    }

    if ([method isEqualToString:@"combo.status"] || [method isEqualToString:@"combo.result"]) {
        NSString* comboId = params[@"comboId"];
        if (comboId.length == 0) {
            comboId = _comboRuntime.lastComboId;
        }
        NSDictionary* combo = comboId ? _comboRuntime.combos[comboId] : nil;
        if (!combo) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown comboId.";
            return;
        }
        *outResult = combo;
        return;
    }

    if ([method isEqualToString:@"combo.list"]) {
        NSMutableArray* list = [NSMutableArray array];
        for (NSDictionary* c in [_comboRuntime.combos allValues]) {
            [list addObject:[_comboRuntime serializableCombo:[c mutableCopy]]];
        }
        *outResult = @{ @"combos": list };
        return;
    }

    if ([method isEqualToString:@"combo.cancel"]) {
        NSString* comboId = params[@"comboId"];
        NSMutableDictionary* combo = comboId ? [_comboRuntime.combos[comboId] mutableCopy] : nil;
        if (!combo) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Unknown comboId.";
            return;
        }
        combo[@"status"] = @"cancelled";
        *outResult = @{ @"cancelled": @YES };
        return;
    }

    if ([method isEqualToString:@"combo.rollback"]) {
        NSString* comboId = params[@"comboId"];
        BOOL confirm = [params[@"confirm"] boolValue];
        
        if (comboId.length == 0) {
            comboId = _comboRuntime.lastComboId;
        }
        
        if (comboId.length == 0) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No session combo transaction is available to roll back.";
            return;
        }
        
        NSString* backupDir = [[NSHomeDirectory() stringByAppendingPathComponent:@".dietcode/backups"] stringByAppendingPathComponent:comboId];
        NSString* manifestPath = [backupDir stringByAppendingPathComponent:@"manifest.json"];
        
        NSString* mErr = nil;
        NSDictionary* manifest = [_recoveryStore loadManifestFromPath:manifestPath error:&mErr];
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
        BOOL ok = [_recoveryStore restorePatchFromManifest:manifest backupDir:backupDir confirm:confirm sessionToken:_sessionToken error:&rollbackErr errorCode:&rollbackErrorCode];
        if (!ok) {
            *outErrCode = rollbackErrorCode ?: @"rollback_failed";
            *outErrMsg = rollbackErr ?: @"Rollback failed.";
            return;
        }
        
        NSMutableArray* pathsArr = [NSMutableArray array];
        for (NSDictionary* fileEntry in manifest[@"files"] ?: @[]) {
            [pathsArr addObject:fileEntry[@"workspaceRelativePath"] ?: @""];
        }
        *outResult = @{ @"schemaVersion": @"1.6.2", @"reverted": @YES, @"files": pathsArr };
        return;
    }
    
    if ([method isEqualToString:@"recovery.scan"]) {
        NSString* errStr = nil;
        NSDictionary* report = [_recoveryStore performRecoveryScan:&errStr];
        if (errStr) {
            *outErrCode = @"internal_error";
            *outErrMsg = errStr;
            return;
        }
        *outResult = report;
        return;
    }

    if ([method isEqualToString:@"recovery.schemaInfo"]) {
        *outResult = @{
            @"transactionSchemaVersion": @"1.6.2",
            @"supportedRollbackSchemas": @[@"1.6.2"],
            @"supportedInspectOnlySchemas": @[@"1.6.1"]
        };
        return;
    }

    if ([method isEqualToString:@"recovery.list"]) {
        NSString* errStr = nil;
        NSArray* backups = [_recoveryStore listBackupsQuickWithActiveCombos:_comboRuntime.combos error:&errStr];
        if (errStr) {
            *outErrCode = @"internal_error";
            *outErrMsg = errStr;
            return;
        }
        *outResult = @{ @"backups": backups };
        return;
    }

    if ([method isEqualToString:@"recovery.deleteBackup"]) {
        NSString* comboId = params[@"comboId"];
        if (!comboId) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"comboId parameter required.";
            return;
        }
        BOOL confirm = [params[@"confirm"] boolValue];
        NSString* errStr = nil;
        NSString* errCode = nil;
        if (![_recoveryStore deleteBackupWithId:comboId confirm:confirm activeCombos:_comboRuntime.combos error:&errStr errorCode:&errCode]) {
            *outErrCode = errCode ?: @"delete_failed";
            *outErrMsg = errStr ?: @"Failed to delete backup.";
            return;
        }
        *outResult = @{ @"deleted": @YES, @"comboId": comboId };
        
        // Audit log the deletion
        NSString* backupDir = [[NSHomeDirectory() stringByAppendingPathComponent:@".dietcode/backups"] stringByAppendingPathComponent:comboId];
        [self logAuditMethod:@"recovery.deleteBackup" caller:@"unix_socket" permission:@"Edit" duration:0 result:@"success" paths:[NSString stringWithFormat:@"deleted comboId: %@ | path: %@", comboId, backupDir]];
        return;
    }

    if ([method isEqualToString:@"recovery.prune"]) {
        NSNumber* keepLastN = params[@"keepLastN"];
        NSNumber* olderThanDays = params[@"olderThanDays"];
        if (!params[@"dryRun"]) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"dryRun parameter required.";
            return;
        }
        BOOL dryRun = [params[@"dryRun"] boolValue];
        BOOL confirmInvalid = [params[@"confirmInvalid"] boolValue];
        
        NSString* errStr = nil;
        NSDictionary* pruneReport = [_recoveryStore pruneBackupsWithKeepLastN:keepLastN olderThanDays:olderThanDays dryRun:dryRun confirmInvalid:confirmInvalid activeCombos:_comboRuntime.combos error:&errStr];
        if (errStr) {
            *outErrCode = @"internal_error";
            *outErrMsg = errStr;
            return;
        }
        *outResult = pruneReport;
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
        BOOL ok = [_windowController writeFileAtPath:targetPath content:content errorOut:&errStr];
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
    
    // Editor commands
    if ([method isEqualToString:@"editor.getActiveFile"]) {
        NSString* active = [self safeActiveFilePath] ?: @"";
        *outResult = @{ @"path": active };
        return;
    }
    
    if ([method isEqualToString:@"editor.getOpenFiles"]) {
        NSArray* list = [self safeOpenFilePaths];
        *outResult = @{ @"files": list };
        return;
    }
    
    if ([method isEqualToString:@"editor.getText"]) {
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Open document path required.";
            return;
        }
        NSString* text = [self safeTextForFileAtPath:targetPath];
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
        NSDictionary* sel = [self safeActiveSelectionInfo];
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
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSString* errStr = nil;
        NSString* errCode = nil;
        NSDictionary* result = [_patchService applyPatch:params error:&errStr errorCode:&errCode];
        if (!result) {
            *outErrCode = errCode ?: @"patch_failed";
            *outErrMsg = errStr ?: @"Patch application failed.";
            return;
        }
        *outResult = result;
        return;
    }
    
    if ([method isEqualToString:@"editor.saveFile"]) {
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSString* ws = [self safeWorkspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }

        NSDictionary* git = [self safeGitStatusInfo] ?: @{};
        NSMutableArray* modified = [NSMutableArray arrayWithArray:DirtyFilePathsFromTabs([self safeOpenTabs] ?: @[])];
        for (NSString* key in @[@"modified", @"staged", @"untracked"]) {
            for (NSString* rel in git[key] ?: @[]) {
                NSString* abs = AbsolutePathForRPCPath(rel, ws);
                if (![modified containsObject:abs]) {
                    [modified addObject:abs];
                }
            }
        }

        NSArray* problems = [self safeProblemsList] ?: @[];
        *outResult = [DietCodeWorkspaceAnalysisService summaryOfWorkspace:ws
                                                                 openFiles:[self safeOpenFilePaths]
                                                             modifiedFiles:modified
                                                               diagnostics:DiagnosticsSummaryFromProblems(problems)
                                                                 gitBranch:git[@"branch"]];
        return;
    }

    if ([method isEqualToString:@"analysis.searchRanked"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* query = params[@"query"];
        if (!ws || query.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"Query string and workspace required.";
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![_windowController.sessionLastSearches containsObject:query]) {
                [_windowController.sessionLastSearches insertObject:query atIndex:0];
                if (_windowController.sessionLastSearches.count > 50) {
                    [_windowController.sessionLastSearches removeLastObject];
                }
            }
        });

        NSInteger requestedMax = params[@"maxResults"] ? [params[@"maxResults"] integerValue] : kMaxGrepResults;
        if (requestedMax > kMaxGrepResults) {
            *outErrCode = @"response_too_large";
            *outErrMsg = [NSString stringWithFormat:@"maxResults exceeds limit of %ld.", (long)kMaxGrepResults];
            return;
        }
        NSArray* ranked = [DietCodeWorkspaceAnalysisService searchRankedForQuery:query
                                                                       workspace:ws
                                                                       openFiles:[self safeOpenFilePaths]
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
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [self safeActiveFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSString* text = [self safeTextForFileAtPath:targetPath] ?: @"";
        NSArray* symbols = [DietCodeSymbolIndexService symbolsForFileContent:text extension:[[targetPath pathExtension] lowercaseString]];
        *outResult = [DietCodeWorkspaceAnalysisService fileSummaryForPath:targetPath symbolsCount:symbols.count];
        return;
    }

    if ([method isEqualToString:@"analysis.relatedFiles"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [self safeActiveFilePath], ws);
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
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [self safeActiveFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSString* text = [self safeTextForFileAtPath:targetPath];
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
        NSString* targetPath = [self safeActiveFilePath];
        NSString* text = targetPath ? [self safeTextForFileAtPath:targetPath] : nil;
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
        NSString* ws = [self safeWorkspacePath];
        NSString* symbol = params[@"symbol"];
        if (!ws || symbol.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"symbol and workspace required.";
            return;
        }
        NSArray* problems = [self safeProblemsList] ?: @[];
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
                                                                  openFiles:[self safeOpenFilePaths]
                                                           diagnosticsFiles:diagFiles]
        };
        return;
    }

    if ([method isEqualToString:@"symbols.atCursor"]) {
        NSDictionary* sel = [self safeActiveSelectionInfo];
        NSString* targetPath = [self safeActiveFilePath];
        NSString* text = targetPath ? [self safeTextForFileAtPath:targetPath] : nil;
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
        NSString* ws = [self safeWorkspacePath];
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        *outResult = [DietCodeDiffAnalysisService workspaceDiffInfo:ws];
        return;
    }

    if ([method isEqualToString:@"diff.file"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: @"", ws);
        NSString* diff = [self safeGitDiffForFile:targetPath];
        *outResult = @{
            @"path": targetPath ?: @"",
            @"diff": diff ?: @"",
            @"mode": @"literal_git_diff",
            @"sha256": StableHashForString(diff ?: @"")
        };
        return;
    }

    if ([method isEqualToString:@"diff.chunk"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* source = [params[@"source"] lowercaseString] ?: @"unstaged";
        NSInteger offset = params[@"offset"] ? [params[@"offset"] integerValue] : 0;
        NSInteger maxBytes = params[@"maxBytes"] ? [params[@"maxBytes"] integerValue] : 64 * 1024;
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        NSString* diff = @"";
        NSString* absPath = @"";
        if ([source isEqualToString:@"staged"]) {
            diff = RunGitOutput(ws, @[@"diff", @"--cached"]);
        } else if ([source isEqualToString:@"unstaged"]) {
            diff = RunGitOutput(ws, @[@"diff"]);
        } else if ([source isEqualToString:@"file"]) {
            absPath = AbsolutePathForRPCPath(params[@"path"] ?: @"", ws);
            if (!absPath) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"path required when source=file.";
                return;
            }
            diff = [self safeGitDiffForFile:absPath] ?: @"";
        } else {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"source must be one of unstaged, staged, or file.";
            return;
        }
        NSMutableDictionary* chunk = [TextChunkResponse(diff ?: @"", offset, maxBytes) mutableCopy];
        chunk[@"source"] = source;
        chunk[@"path"] = absPath ?: @"";
        chunk[@"mode"] = @"literal_git_diff_chunk";
        chunk[@"encoding"] = @"utf-8";
        *outResult = chunk;
        return;
    }

    if ([method isEqualToString:@"diff.hunks"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* source = [params[@"source"] lowercaseString] ?: @"unstaged";
        NSInteger maxHunks = params[@"maxHunks"] ? [params[@"maxHunks"] integerValue] : 500;
        NSInteger hunkOffset = params[@"hunkOffset"] ? [params[@"hunkOffset"] integerValue] : 0;
        BOOL includeLines = [params[@"includeLines"] boolValue];
        NSInteger maxLinesPerHunk = params[@"maxLinesPerHunk"] ? [params[@"maxLinesPerHunk"] integerValue] : 200;
        if (!ws) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No open workspace.";
            return;
        }
        NSString* diff = @"";
        NSString* absPath = @"";
        if ([source isEqualToString:@"staged"]) {
            diff = RunGitOutput(ws, @[@"diff", @"--cached"]);
        } else if ([source isEqualToString:@"unstaged"]) {
            diff = RunGitOutput(ws, @[@"diff"]);
        } else if ([source isEqualToString:@"file"]) {
            absPath = AbsolutePathForRPCPath(params[@"path"] ?: @"", ws);
            if (!absPath) {
                *outErrCode = @"invalid_params";
                *outErrMsg = @"path required when source=file.";
                return;
            }
            diff = [self safeGitDiffForFile:absPath] ?: @"";
        } else {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"source must be one of unstaged, staged, or file.";
            return;
        }
        NSMutableDictionary* response = [UnifiedDiffHunksResponse(diff ?: @"", maxHunks, hunkOffset, includeLines, maxLinesPerHunk) mutableCopy];
        response[@"source"] = source;
        response[@"path"] = absPath ?: @"";
        response[@"mode"] = @"literal_unified_diff_hunks";
        response[@"sha256"] = StableHashForString(diff ?: @"");
        *outResult = response;
        return;
    }

    if ([method isEqualToString:@"diff.current"]) {
        NSString* ws = [self safeWorkspacePath] ?: @"";
        *outResult = @{
            @"changes": [self currentChangesInfo],
            @"unstagedDiff": RunGitOutput(ws, @[@"diff"]),
            @"stagedDiff": RunGitOutput(ws, @[@"diff", @"--cached"]),
            @"unsavedBuffers": [DietCodeBufferStateService snapshotForTabs:[self safeOpenTabs] ?: @[]]
        };
        return;
    }

    if ([method isEqualToString:@"diff.staged"]) {
        NSString* diff = RunGitOutput([self safeWorkspacePath] ?: @"", @[@"diff", @"--cached"]);
        *outResult = @{ @"diff": diff, @"mode": @"literal_git_diff", @"sha256": StableHashForString(diff ?: @"") };
        return;
    }

    if ([method isEqualToString:@"diff.unstaged"]) {
        NSString* diff = RunGitOutput([self safeWorkspacePath] ?: @"", @[@"diff"]);
        *outResult = @{ @"diff": diff, @"mode": @"literal_git_diff", @"sha256": StableHashForString(diff ?: @"") };
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
        NSString* ws = [_windowBridge workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowBridge activeFilePath], ws);
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSDictionary* validation = [_patchService validatePatchAtPath:targetPath patch:patchStr currentText:params[@"currentText"]];
        *outResult = @{ @"validation": validation };
        return;
    }

    if ([method isEqualToString:@"diff.previewPatch"]) {
        NSString* ws = [_windowBridge workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowBridge activeFilePath], ws);
        NSString* patchStr = params[@"patch"];
        if (!targetPath || patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path and patch parameters required.";
            return;
        }
        NSString* currentText = params[@"currentText"] ?: [_windowBridge textForFileAtPath:targetPath];
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
    if ([method isEqualToString:@"patch.chunk"]) {
        NSString* patchStr = params[@"patch"] ?: @"";
        NSInteger offset = params[@"offset"] ? [params[@"offset"] integerValue] : 0;
        NSInteger maxBytes = params[@"maxBytes"] ? [params[@"maxBytes"] integerValue] : 64 * 1024;
        if (patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"patch parameter required.";
            return;
        }
        NSMutableDictionary* chunk = [TextChunkResponse(patchStr, offset, maxBytes) mutableCopy];
        chunk[@"mode"] = @"literal_patch_chunk";
        chunk[@"encoding"] = @"utf-8";
        *outResult = chunk;
        return;
    }

    if ([method isEqualToString:@"patch.hunks"]) {
        NSString* patchStr = params[@"patch"] ?: @"";
        NSInteger maxHunks = params[@"maxHunks"] ? [params[@"maxHunks"] integerValue] : 500;
        NSInteger hunkOffset = params[@"hunkOffset"] ? [params[@"hunkOffset"] integerValue] : 0;
        BOOL includeLines = [params[@"includeLines"] boolValue];
        NSInteger maxLinesPerHunk = params[@"maxLinesPerHunk"] ? [params[@"maxLinesPerHunk"] integerValue] : 200;
        if (patchStr.length == 0) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"patch parameter required.";
            return;
        }
        NSMutableDictionary* response = [UnifiedDiffHunksResponse(patchStr, maxHunks, hunkOffset, includeLines, maxLinesPerHunk) mutableCopy];
        response[@"mode"] = @"literal_unified_diff_hunks";
        response[@"sha256"] = StableHashForString(patchStr ?: @"");
        *outResult = response;
        return;
    }

    if ([method isEqualToString:@"patch.validate"] || [method isEqualToString:@"patch.preview"]) {
        NSString* ws = [_windowBridge workspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [_windowBridge activeFilePath], ws);
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
        NSDictionary* validation = [_patchService validatePatchAtPath:targetPath patch:patchStr currentText:params[@"currentText"]];
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

    if ([method isEqualToString:@"patch.apply"] || [method isEqualToString:@"editor.applyPatch"]) {
        NSString* errStr = nil;
        NSString* errCode = nil;
        NSDictionary* result = [_patchService applyPatch:params error:&errStr errorCode:&errCode];
        if (!result) {
            *outErrCode = errCode ?: @"patch_failed";
            *outErrMsg = errStr ?: @"Patch application failed.";
            return;
        }
        *outResult = result;
        return;
    }

    if ([method isEqualToString:@"patch.applyBatch"]) {
        NSString* errStr = nil;
        NSString* errCode = nil;
        NSDictionary* result = [_patchService applyPatchBatch:params error:&errStr errorCode:&errCode];
        if (!result) {
            *outErrCode = errCode ?: @"patch_failed";
            *outErrMsg = errStr ?: @"Batch patch application failed.";
            return;
        }
        *outResult = result;
        return;
    }

    if ([method isEqualToString:@"patch.revertLast"]) {
        NSString* errStr = nil;
        NSString* errCode = nil;
        NSDictionary* result = [_patchService revertLastPatchWithError:&errStr errorCode:&errCode];
        if (!result) {
            *outErrCode = errCode ?: @"rollback_failed";
            *outErrMsg = errStr ?: @"Failed to revert last RPC patch.";
            return;
        }
        *outResult = result;
        return;
    }

    // Buffer commands
    if ([method isEqualToString:@"buffers.snapshot"]) {
        *outResult = @{ @"buffers": [DietCodeBufferStateService snapshotForTabs:[self safeOpenTabs] ?: @[]] };
        return;
    }

    if ([method isEqualToString:@"buffers.dirty"]) {
        *outResult = @{ @"files": DirtyFilePathsFromTabs([self safeOpenTabs] ?: @[]) };
        return;
    }

    if ([method isEqualToString:@"buffers.active"]) {
        NSString* pathValue = [self safeActiveFilePath] ?: @"";
        NSDictionary* selection = [self safeActiveSelectionInfo] ?: @{};
        *outResult = @{ @"path": pathValue, @"selection": selection };
        return;
    }

    if ([method isEqualToString:@"buffers.unsavedDiff"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [self safeActiveFilePath], ws);
        NSString* diff = @"";
        for (id tab in [self safeOpenTabs] ?: @[]) {
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
        NSArray* problems = [self safeProblemsList] ?: @[];
        *outResult = @{ @"diagnostics": problems };
        return;
    }

    if ([method isEqualToString:@"diagnostics.summary"]) {
        NSArray* problems = [self safeProblemsList] ?: @[];
        *outResult = DiagnosticsSummaryFromProblems(problems);
        return;
    }

    if ([method isEqualToString:@"diagnostics.cluster"]) {
        NSArray* problems = [self safeProblemsList] ?: @[];
        *outResult = @{ @"clusters": ClusterDiagnostics(problems) };
        return;
    }

    if ([method isEqualToString:@"diagnostics.forFile"]) {
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"] ?: [self safeActiveFilePath], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter or active file required.";
            return;
        }
        NSMutableArray* matches = [NSMutableArray array];
        for (NSDictionary* problem in [self safeProblemsList] ?: @[]) {
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
        NSString* ws = [self safeWorkspacePath];
        NSString* targetPath = AbsolutePathForRPCPath(params[@"path"], ws);
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        NSString* errStr = nil;
        BOOL ok = [_windowController gitDiscardFile:targetPath errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = errStr ?: @"Failed to revert file.";
            return;
        }
        *outResult = @{ @"reverted": @YES, @"path": targetPath };
        return;
    }

    // Session workflow commands
    if ([method isEqualToString:@"session.info"] || [method isEqualToString:@"session.workflowState"]) {
        __block NSString* ws = nil;
        __block NSString* activeFile = nil;
        __block NSArray* openFiles = nil;
        __block NSArray* dirtyFiles = nil;
        __block NSArray* recentCmds = nil;
        __block NSArray* lastSearches = nil;
        __block pid_t termPid = 0;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            ws = [_windowController workspacePath];
            activeFile = [_windowController activeFilePath];
            openFiles = [_windowController openFilePaths];
            dirtyFiles = DirtyFilePathsFromTabs(_windowController.openTabs ?: @[]);
            recentCmds = [_windowController.sessionRecentCommands copy];
            lastSearches = [_windowController.sessionLastSearches copy];
            termPid = [_windowController terminalPid];
        });
        
        NSDictionary* git = [self safeGitStatusInfo] ?: @{};
        *outResult = @{
            @"workspace": ws ?: @"",
            @"activeFile": activeFile ?: @"",
            @"openFiles": openFiles ?: @[],
            @"dirtyFiles": dirtyFiles ?: @[],
            @"gitBranch": git[@"branch"] ?: @"",
            @"recentCommands": recentCmds ?: @[],
            @"lastSearches": lastSearches ?: @[],
            @"terminalPid": @(termPid)
        };
        return;
    }

    if ([method isEqualToString:@"session.recentCommands"]) {
        NSArray* recentCmds = [self safeSessionRecentCommands];
        *outResult = @{ @"commands": recentCmds ?: @[] };
        return;
    }

    if ([method isEqualToString:@"session.lastSearches"]) {
        NSArray* lastSearches = [self safeSessionLastSearches];
        *outResult = @{ @"searches": lastSearches ?: @[] };
        return;
    }

    if ([method isEqualToString:@"session.clearHistory"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_windowController.sessionRecentCommands removeAllObjects];
            [_windowController.sessionLastSearches removeAllObjects];
        });
        *outResult = @{ @"cleared": @YES };
        return;
    }

    // Verification commands
    if ([method isEqualToString:@"verify.run"]) {
        NSString* command = params[@"command"] ?: @"";
        NSArray<NSString*>* allowed = VerifyCommandsAllowlist();
        if (!VerifyCommandIsAllowed(command, allowed)) {
            *outErrCode = @"invalid_params";
            *outErrMsg = [NSString stringWithFormat:@"verify.run command must match one of the AgentVerifyCommands prefixes: %@.", [allowed componentsJoinedByString:@", "]];
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
            @"problems": [self safeProblemsList] ?: @[],
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
        *outResult = [_taskRuntime startTask:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"task.status"] || [method isEqualToString:@"task.result"]) {
        *outResult = [_taskRuntime taskStatus:params result:[method isEqualToString:@"task.result"] outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"task.cancel"]) {
        *outResult = [_taskRuntime cancelTask:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"task.step"]) {
        *outResult = [_taskRuntime taskStep:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"task.runLoop"]) {
        *outResult = [_taskRuntime taskRunLoop:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"edit.plan"]) {
        *outResult = [_taskRuntime editPlan:params outErrCode:outErrCode outErrMsg:outErrMsg];
        return;
    }

    if ([method isEqualToString:@"edit.executePlan"]) {
        *outResult = [_taskRuntime editExecutePlan:params outErrCode:outErrCode outErrMsg:outErrMsg];
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
        pid_t pid = [self safeTerminalPid];
        *outResult = @{
            @"pid": @(pid),
            @"running": @(pid > 0),
            @"outputLength": @(([self safeTerminalOutput] ?: @"").length)
        };
        return;
    }

    if ([method isEqualToString:@"terminal.jobs"]) {
        pid_t pid = [self safeTerminalPid];
        NSArray* jobs = pid > 0 ? @[@{ @"id": @"terminal", @"pid": @(pid), @"status": @"running" }] : @[];
        *outResult = @{ @"jobs": jobs };
        return;
    }

    if ([method isEqualToString:@"terminal.history"]) {
        *outResult = @{ @"commands": [self safeSessionRecentCommands] ?: @[] };
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
        
        NSString* errStr = nil;
        BOOL ok = [_windowController runTerminalCommand:command cwd:cwd show:show errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"terminal_failed";
            *outErrMsg = errStr ?: @"Failed to start terminal command.";
            return;
        }
        *outResult = @{ @"run": @YES, @"pid": @([self safeTerminalPid]) };
        return;
    }
    
    if ([method isEqualToString:@"terminal.stop"]) {
        [_windowController stopTerminalCommand];
        *outResult = @{ @"stopped": @YES };
        return;
    }
    
    if ([method isEqualToString:@"terminal.getOutput"]) {
        NSString* output = [self safeTerminalOutput] ?: @"";
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
        NSDictionary* info = [self safeGitStatusInfo];
        *outResult = info;
        return;
    }
    
    if ([method isEqualToString:@"git.diff"]) {
        NSString* targetPath = params[@"path"] ?: @"";
        NSString* diff = [self safeGitDiffForFile:targetPath];
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
        NSString* errStr = nil;
        BOOL ok = [_windowController gitStageFile:targetPath errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = errStr ?: @"Failed to stage file.";
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
        NSString* errStr = nil;
        BOOL ok = [_windowController gitUnstageFile:targetPath errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = errStr ?: @"Failed to unstage file.";
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
        NSString* errStr = nil;
        BOOL ok = [_windowController gitDiscardFile:targetPath errorOut:&errStr];
        if (!ok) {
            *outErrCode = @"git_failed";
            *outErrMsg = errStr ?: @"Failed to discard file changes.";
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
        NSArray* problems = [self safeProblemsList] ?: @[];
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
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
        if (!targetPath) {
            *outErrCode = @"invalid_params";
            *outErrMsg = @"path parameter required.";
            return;
        }
        NSArray* diags = [self safeLanguageDiagnosticsForPath:targetPath] ?: @[];
        *outResult = @{ @"diagnostics": diags };
        return;
    }
    
    if ([method isEqualToString:@"language.format"]) {
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSString* targetPath = params[@"path"] ?: [self safeActiveFilePath];
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
        NSDictionary* sel = [self safeActiveSelectionInfo] ?: @{};
        NSString* targetPath = [self safeActiveFilePath];
        NSString* text = targetPath ? [self safeTextForFileAtPath:targetPath] : nil;
        if (!targetPath || !text) {
            *outErrCode = @"invalid_request";
            *outErrMsg = @"No active readable editor tab.";
            return;
        }
        NSString* symbol = params[@"symbol"];
        if (symbol.length == 0) {
            symbol = WordAtOffset(text, [sel[@"start"] integerValue]);
        }
        if (symbol.length == 0) {
            *outResult = @{ @"found": @NO, @"symbol": @"", @"definition": @{}, @"candidates": @[] };
            return;
        }
        NSString* ws = [self safeWorkspacePath];
        NSArray* problems = [self safeProblemsList] ?: @[];
        NSMutableArray* diagFiles = [NSMutableArray array];
        for (NSDictionary* problem in problems) {
            NSString* abs = AbsolutePathForRPCPath(problem[@"path"], ws);
            if (abs.length > 0 && ![diagFiles containsObject:abs]) {
                [diagFiles addObject:abs];
            }
        }
        NSArray* references = [DietCodeSymbolIndexService referencesForSymbol:symbol
                                                                   inWorkspace:ws
                                                                     openFiles:[self safeOpenFilePaths]
                                                              diagnosticsFiles:diagFiles];
        NSDictionary* best = @{};
        for (NSDictionary* candidate in references) {
            NSString* preview = [candidate[@"preview"] lowercaseString] ?: @"";
            NSString* lowerSymbol = [symbol lowercaseString];
            if ([preview containsString:[NSString stringWithFormat:@"def %@", lowerSymbol]] ||
                [preview containsString:[NSString stringWithFormat:@"class %@", lowerSymbol]] ||
                [preview containsString:[NSString stringWithFormat:@"function %@", lowerSymbol]] ||
                [preview containsString:[NSString stringWithFormat:@"%@(", lowerSymbol]]) {
                best = candidate;
                break;
            }
        }
        if (best.count == 0 && references.count > 0) {
            best = references[0];
        }
        *outResult = @{ @"found": @(best.count > 0), @"symbol": symbol, @"definition": best, @"candidates": references };
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
        else if ([stringCode isEqualToString:@"invalid_params"]) numericCode = @(-32602);
        else if ([stringCode isEqualToString:@"request_too_large"] || [stringCode isEqualToString:@"response_too_large"] || [stringCode isEqualToString:@"too_many_results"] || [stringCode isEqualToString:@"file_too_large"]) numericCode = @(413);
        else if ([stringCode isEqualToString:@"not_found"]) numericCode = @(404);
        else if ([stringCode isEqualToString:@"already_exists"]) numericCode = @(409);
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
                @"code": @(413),
                @"string_code": @"response_too_large",
                @"message": @"Response exceeds maximum allowed size."
            }
        };
        data = [NSJSONSerialization dataWithJSONObject:limitResp options:0 error:&err];
        if (err || !data) return;
    }
    
    NSMutableData* lineData = [data mutableCopy];
    [lineData appendBytes:"\n" length:1];
    
    @synchronized(self) {
        write(clientFd, lineData.bytes, lineData.length);
    }
}

- (void)appendLogLine:(NSString*)line {
    if ([NSThread isMainThread]) {
        [_windowController appendControlLogLine:line];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [_windowController appendControlLogLine:line];
    });
}

- (void)logAuditMethod:(NSString*)method 
                caller:(NSString*)caller 
            permission:(NSString*)permission 
              duration:(long long)duration 
                result:(NSString*)result 
                 paths:(NSString*)paths {
    @synchronized (self) {
        NSString* homeDir = NSHomeDirectory();
        NSString* dietcodeDir = [homeDir stringByAppendingPathComponent:@".dietcode"];
        NSString* logPath = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log"];
        
        NSString* logPath3 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.3"];
        NSString* logPath2 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.2"];
        NSString* logPath1 = [dietcodeDir stringByAppendingPathComponent:@"control_audit.log.1"];
        
        // Hardening: verify log paths are not symlinks and belong to current user
        NSArray* pathsToCheck = @[logPath, logPath1, logPath2, logPath3];
        for (NSString* p in pathsToCheck) {
            struct stat st;
            if (lstat([p UTF8String], &st) == 0) {
                if (S_ISLNK(st.st_mode) || st.st_uid != getuid()) {
                    unlink([p UTF8String]);
                }
            }
        }
        
        NSFileManager* fm = [NSFileManager defaultManager];
        NSError* attrErr = nil;
        NSDictionary* attrs = [fm attributesOfItemAtPath:logPath error:&attrErr];
        if (attrs) {
            unsigned long long size = [attrs fileSize];
            if (size >= 5 * 1024 * 1024) {
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
}

@end
