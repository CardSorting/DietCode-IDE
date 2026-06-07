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
#include <fcntl.h>
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
#import "MacControlServer+Private.hpp"

static NSString* DietCodeReadTextFileForControlServer(NSString* path) {
    if (path.length == 0) return nil;
    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSError* error = nil;
    return [NSString stringWithContentsOfFile:path usedEncoding:&encoding error:&error];
}

@interface DietCodeClientConnection : NSObject
@property (nonatomic, assign) int fd;
@property (nonatomic, assign) BOOL readEOF;
@property (nonatomic, assign) NSInteger pendingRequestsCount;
@property (nonatomic, strong) NSMutableSet<NSString*>* subscriptions;
@end

@implementation DietCodeClientConnection
- (instancetype)init {
    self = [super init];
    if (self) {
        _subscriptions = [NSMutableSet set];
    }
    return self;
}
@end

@interface DietCodeControlServer ()

- (void)acceptLoop;
- (void)handleClient:(DietCodeClientConnection*)conn;
- (void)processRequest:(const std::string&)requestStr connection:(DietCodeClientConnection*)conn;
- (void)markConnectionEOF:(DietCodeClientConnection*)conn;
- (void)decrementPendingRequestsForConnection:(DietCodeClientConnection*)conn;
- (NSString*)permissionLevelForMethod:(NSString*)method params:(NSDictionary*)params;
- (void)sendError:(NSString*)reqId code:(id)code message:(NSString*)message clientFd:(int)clientFd;
- (void)sendSuccess:(NSString*)reqId result:(NSDictionary*)result clientFd:(int)clientFd;
- (NSString*)chipNameForStep:(NSDictionary*)step;
- (NSDictionary*)paramsForComboStep:(NSDictionary*)step;
- (NSArray<NSDictionary*>*)rpcMethodDescriptions;
- (NSDictionary*)descriptionForRPCMethod:(NSString*)method;
- (NSArray<NSDictionary*>*)chipRegistry;
- (NSDictionary*)metadataForChip:(NSString*)chip;
- (NSDictionary*)primitiveForChip:(NSString*)chip params:(NSDictionary*)params;

@end

@implementation DietCodeControlServer

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
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleTerminalOutputUpdate:)
                                                     name:kDietCodeTerminalOutputDidUpdateNotification
                                                   object:nil];
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
    NSString* text = [_windowBridge textForFileAtPath:path];
    if (text) return text;
    return DietCodeReadTextFileForControlServer(path);
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
    
    mode_t oldUmask = umask(0077);
    
    NSString* token = [NSString stringWithFormat:@"%08x%08x%08x%08x", 
                       arc4random(), arc4random(), arc4random(), arc4random()];
    NSString* tokenPath = [dcDir stringByAppendingPathComponent:@"session.token"];
    unlink([tokenPath UTF8String]);
    
    int tokenFd = open([tokenPath UTF8String], O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (tokenFd >= 0) {
        NSData* tokenData = [token dataUsingEncoding:NSUTF8StringEncoding];
        write(tokenFd, tokenData.bytes, tokenData.length);
        close(tokenFd);
    } else {
        [token writeToFile:tokenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:tokenPath error:nil];
    _sessionToken = [token copy];
    
    // Unix socket setup
    NSString* sockPathStr = [dcDir stringByAppendingPathComponent:@"control.sock"];
    const char* sockPath = [sockPathStr UTF8String];
    
    _serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (_serverFd < 0) {
        [self appendLogLine:@"[Error] Failed to create Unix socket."];
        umask(oldUmask);
        return;
    }
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(sockPath) >= sizeof(addr.sun_path)) {
        [self appendLogLine:[NSString stringWithFormat:@"[Error] Unix socket path is too long: %lu bytes (max %lu bytes). Can't bind.", strlen(sockPath), sizeof(addr.sun_path) - 1]];
        close(_serverFd);
        _serverFd = -1;
        umask(oldUmask);
        return;
    }
    strncpy(addr.sun_path, sockPath, sizeof(addr.sun_path) - 1);
    
    unlink(sockPath);
    
    if (bind(_serverFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        [self appendLogLine:@"[Error] Failed to bind Unix socket."];
        close(_serverFd);
        _serverFd = -1;
        umask(oldUmask);
        return;
    }
    
    chmod(sockPath, 0600);
    umask(oldUmask);
    
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
        
        // Agent Attribution & Rationale
        NSString* agentId = req[@"agentId"] ?: params[@"agentId"];
        if (![agentId isKindOfClass:[NSString class]]) agentId = nil;
        NSString* rationale = req[@"rationale"] ?: params[@"rationale"];
        if (![rationale isKindOfClass:[NSString class]]) rationale = nil;
        
        NSString* caller = agentId ?: @"unix_socket";
        NSString* permission = [self permissionLevelForMethod:method params:params];
        
        if ([method isEqualToString:@"event.subscribe"]) {
            @synchronized(self) {
                NSArray* types = params[@"types"];
                if ([types isKindOfClass:[NSArray class]]) {
                    for (NSString* t in types) {
                        if ([t isKindOfClass:[NSString class]]) [conn.subscriptions addObject:t];
                    }
                }
            }
            [self sendSuccess:reqId result:@{ @"subscribed": @YES } clientFd:clientFd];
            [self decrementPendingRequestsForConnection:conn];
            return;
        }
        
        if ([method isEqualToString:@"event.unsubscribe"]) {
            @synchronized(self) {
                NSArray* types = params[@"types"];
                if ([types isKindOfClass:[NSArray class]]) {
                    for (NSString* t in types) {
                        if ([t isKindOfClass:[NSString class]]) [conn.subscriptions removeObject:t];
                    }
                }
            }
            [self sendSuccess:reqId result:@{ @"unsubscribed": @YES } clientFd:clientFd];
            [self decrementPendingRequestsForConnection:conn];
            return;
        }
        
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
                NSMutableString* alertMsg = [NSMutableString stringWithFormat:@"An external agent is requesting to execute a destructive command:\n\nMethod: %@\nParams: %@", method, params];
                if (rationale.length > 0) {
                    [alertMsg appendFormat:@"\n\nRationale: %@", rationale];
                }
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
        return YES;
    }
    if ([method isEqualToString:@"workspace.openFolder"]) {
        return NO;
    }
    
    NSString* path = params[@"path"];
    if (path) {
        NSString* checkedPath = AbsolutePathForRPCPath(path, ws);
        if (!PathIsInsideWorkspace(checkedPath, ws)) {
            return NO;
        }
    }
    
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

- (NSDictionary*)repairContextForFailure:(NSString*)failure params:(NSDictionary*)params outErrCode:(NSString**)outErrCode outErrMsg:(NSString**)outErrMsg {
    NSString* ws = [self safeWorkspacePath];
    if (ws.length == 0) {
        if (outErrCode) *outErrCode = @"invalid_request";
        if (outErrMsg) *outErrMsg = @"No open workspace.";
        return nil;
    }

    NSMutableArray* files = [NSMutableArray array];
    NSArray* requestedFiles = params[@"files"] ?: @[];
    if (![requestedFiles isKindOfClass:[NSArray class]]) {
        if (outErrCode) *outErrCode = @"invalid_params";
        if (outErrMsg) *outErrMsg = @"files must be an array.";
        return nil;
    }

    for (NSDictionary* file in requestedFiles) {
        if (![file isKindOfClass:[NSDictionary class]]) {
            if (outErrCode) *outErrCode = @"invalid_params";
            if (outErrMsg) *outErrMsg = @"Every files entry must be an object.";
            return nil;
        }
        NSString* path = file[@"path"];
        if (![path isKindOfClass:[NSString class]]) {
            if (outErrCode) *outErrCode = @"invalid_params";
            if (outErrMsg) *outErrMsg = @"Every files entry requires string path.";
            return nil;
        }
        NSString* absPath = AbsolutePathForRPCPath(path, ws);
        if (absPath.length == 0) {
            if (outErrCode) *outErrCode = @"invalid_params";
            if (outErrMsg) *outErrMsg = @"Every files entry requires path.";
            return nil;
        }
        if (!PathIsInsideWorkspace(absPath, ws)) {
            if (outErrCode) *outErrCode = @"outside_workspace";
            if (outErrMsg) *outErrMsg = @"Repair context file path is outside workspace.";
            return nil;
        }
        NSString* full = [self safeTextForFileAtPath:absPath];
        if (!full) {
            if (outErrCode) *outErrCode = @"invalid_request";
            if (outErrMsg) *outErrMsg = [NSString stringWithFormat:@"Repair context file is not readable: %@", path];
            return nil;
        }
        NSArray<NSString*>* lines = LinesFromText(full);
        NSMutableArray* ranges = [NSMutableArray array];
        NSArray* requestedRanges = file[@"ranges"] ?: @[];
        if (![requestedRanges isKindOfClass:[NSArray class]]) {
            if (outErrCode) *outErrCode = @"invalid_params";
            if (outErrMsg) *outErrMsg = @"ranges must be an array.";
            return nil;
        }
        for (NSDictionary* range in requestedRanges) {
            if (![range isKindOfClass:[NSDictionary class]]) {
                if (outErrCode) *outErrCode = @"invalid_params";
                if (outErrMsg) *outErrMsg = @"Every ranges entry must be an object.";
                return nil;
            }
            if (range[@"startLine"] == nil || range[@"endLine"] == nil) {
                if (outErrCode) *outErrCode = @"invalid_params";
                if (outErrMsg) *outErrMsg = @"Repair context ranges require startLine and endLine.";
                return nil;
            }
            NSInteger start = [range[@"startLine"] integerValue];
            NSInteger end = [range[@"endLine"] integerValue];
            if (start <= 0 || end <= 0) {
                if (outErrCode) *outErrCode = @"invalid_params";
                if (outErrMsg) *outErrMsg = @"Repair context range lines must be positive integers.";
                return nil;
            }
            NSString* text = TextForLineRange(lines, start, end);
            if (!text) {
                if (outErrCode) *outErrCode = @"invalid_range";
                if (outErrMsg) *outErrMsg = @"Repair context range is outside the file.";
                return nil;
            }
            [ranges addObject:@{ @"startLine": @(start), @"endLine": @(end), @"text": text }];
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
            NSString* checkedCwd = AbsolutePathForRPCPath(cwd, ws);
            std::filesystem::path cwdPath(StdStringFromNSString(checkedCwd));
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

    // Route based on namespace prefixes to respective categories
    if ([method hasPrefix:@"workspace."] || [method hasPrefix:@"file."] || [method hasPrefix:@"search."]) {
        [self executeFileMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
    } else if ([method hasPrefix:@"editor."] || [method hasPrefix:@"buffers."] || [method hasPrefix:@"changes."] || [method hasPrefix:@"diff."] || [method hasPrefix:@"patch."]) {
        [self executeEditorMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
    } else if ([method hasPrefix:@"git."]) {
        [self executeGitMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
    } else if ([method hasPrefix:@"terminal."] || [method hasPrefix:@"verify."]) {
        [self executeTerminalMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
    } else {
        [self executeContextMethod:method params:params outResult:outResult outErrCode:outErrCode outErrMsg:outErrMsg outPaths:outPaths];
    }
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
    NSNumber* numericCode = @(-32603);
    NSString* stringCode = @"internal_error";
    if ([code isKindOfClass:[NSNumber class]]) {
        numericCode = code;
        if ([code integerValue] == -32601) stringCode = @"method_not_found";
        else if ([code integerValue] == -32600) stringCode = @"invalid_request";
    } else if ([code isKindOfClass:[NSString class]]) {
        stringCode = code;
        if ([stringCode isEqualToString:@"invalid_request"]) numericCode = @(-32600);
        else if ([stringCode isEqualToString:@"method_not_found"]) numericCode = @(-32601);
        else if ([stringCode isEqualToString:@"invalid_params"] || [stringCode isEqualToString:@"invalid_range"]) numericCode = @(-32602);
        else if ([stringCode isEqualToString:@"request_too_large"] || [stringCode isEqualToString:@"response_too_large"] || [stringCode isEqualToString:@"too_many_results"] || [stringCode isEqualToString:@"file_too_large"]) numericCode = @(413);
        else if ([stringCode isEqualToString:@"not_found"]) numericCode = @(404);
        else if ([stringCode isEqualToString:@"already_exists"]) numericCode = @(409);
        else if ([stringCode isEqualToString:@"outside_workspace"] || [stringCode isEqualToString:@"outside_scope"]) numericCode = @(4001);
        else if ([stringCode isEqualToString:@"lock_conflict"] || [stringCode isEqualToString:@"dirty_buffer_conflict"]) numericCode = @(4002);
        else if ([stringCode isEqualToString:@"budget_exceeded"]) numericCode = @(4003);
        else if ([stringCode isEqualToString:@"verification_failed"] || [stringCode isEqualToString:@"verify_failed"] || [stringCode isEqualToString:@"patch_failed"]) numericCode = @(4004);
        else if ([stringCode isEqualToString:@"rollback_conflict"] || [stringCode isEqualToString:@"rollback_failed"]) numericCode = @(4005);
        else if ([stringCode isEqualToString:@"permission_denied"]) numericCode = @(4006);
        else if ([stringCode isEqualToString:@"task_not_active"]) numericCode = @(4007);
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

- (void)notifyEvent:(NSString*)type detail:(NSString*)detail {
    NSDictionary* notification = @{
        @"method": @"event.emitted",
        @"params": @{
            @"type": type ?: @"unknown",
            @"detail": detail ?: @""
        }
    };
    NSData* data = [NSJSONSerialization dataWithJSONObject:notification options:0 error:nil];
    if (!data) return;
    
    NSMutableData* frame = [data mutableCopy];
    [frame appendBytes:"\n" length:1];
    
    @synchronized(self) {
        NSMutableArray* deadConns = [NSMutableArray array];
        for (DietCodeClientConnection* conn in [_activeConnections allValues]) {
            if ([conn.subscriptions containsObject:type] || [conn.subscriptions containsObject:@"*"]) {
                ssize_t written = write(conn.fd, frame.bytes, frame.length);
                if (written < 0) {
                    if (errno == EPIPE || errno == EBADF) {
                        [deadConns addObject:@(conn.fd)];
                    }
                }
            }
        }
        for (NSNumber* fdNum in deadConns) {
            DietCodeClientConnection* conn = _activeConnections[fdNum];
            if (conn) {
                close(conn.fd);
                [_activeConnections removeObjectForKey:fdNum];
            }
        }
    }
}

@end
