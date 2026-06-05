#import <Foundation/Foundation.h>
#include "LSPClient.hpp"
#include <atomic>
#include <iostream>
#include <unistd.h>
#include <unordered_map>

// --- LSP Reader Interface ---
@interface DietCodeLSPReader : NSObject
@property (nonatomic, strong) NSFileHandle* fileHandle;
@property (nonatomic, copy) void (^messageHandler)(NSDictionary*);
@property (nonatomic, copy) void (^errorHandler)(NSString*);
- (instancetype)initWithFileHandle:(NSFileHandle*)fh;
- (void)start;
- (void)stop;
@end

@implementation DietCodeLSPReader {
    NSMutableData* buffer_;
    BOOL running_;
    NSThread* thread_;
}

- (instancetype)initWithFileHandle:(NSFileHandle*)fh {
    self = [super init];
    if (self) {
        _fileHandle = fh;
        buffer_ = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)start {
    running_ = YES;
    thread_ = [[NSThread alloc] initWithTarget:self selector:@selector(runLoop) object:nil];
    [thread_ start];
}

- (void)stop {
    running_ = NO;
    [thread_ cancel];
}

- (void)runLoop {
    @autoreleasepool {
        while (running_ && !thread_.isCancelled) {
            NSData* data = nil;
            @try {
                data = [self.fileHandle readDataOfLength:4096];
            } @catch (NSException* e) {
                if (self.errorHandler) {
                    self.errorHandler([NSString stringWithFormat:@"Read error: %@", e.reason]);
                }
                break;
            }
            
            if (data.length == 0) {
                break; // Closed pipe
            }
            
            @synchronized (self) {
                [buffer_ appendData:data];
                [self processBuffer];
            }
        }
    }
}

- (void)processBuffer {
    while (buffer_.length > 0) {
        const char* bytes = (const char*)buffer_.bytes;
        NSUInteger len = buffer_.length;
        
        std::string bufStr(bytes, len);
        size_t headerEnd = bufStr.find("\r\n\r\n");
        if (headerEnd == std::string::npos) {
            break; // Wait for full headers
        }
        
        std::string headers = bufStr.substr(0, headerEnd);
        size_t clPos = headers.find("Content-Length:");
        if (clPos == std::string::npos) {
            [buffer_ replaceBytesInRange:NSMakeRange(0, headerEnd + 4) withBytes:NULL length:0];
            continue;
        }
        
        size_t valStart = clPos + 15;
        while (valStart < headers.size() && (headers[valStart] == ' ' || headers[valStart] == '\t')) {
            valStart++;
        }
        size_t valEnd = valStart;
        while (valEnd < headers.size() && headers[valEnd] >= '0' && headers[valEnd] <= '9') {
            valEnd++;
        }
        
        if (valEnd == valStart) {
            [buffer_ replaceBytesInRange:NSMakeRange(0, headerEnd + 4) withBytes:NULL length:0];
            continue;
        }
        
        int contentLength = std::stoi(headers.substr(valStart, valEnd - valStart));
        NSUInteger totalMessageLength = headerEnd + 4 + contentLength;
        
        if (buffer_.length < totalMessageLength) {
            break; // Wait for full body
        }
        
        NSData* bodyData = [buffer_ subdataWithRange:NSMakeRange(headerEnd + 4, contentLength)];
        
        NSError* err = nil;
        NSDictionary* json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&err];
        if (json && [json isKindOfClass:[NSDictionary class]]) {
            if (self.messageHandler) {
                self.messageHandler(json);
            }
        }
        
        [buffer_ replaceBytesInRange:NSMakeRange(0, totalMessageLength) withBytes:NULL length:0];
    }
}
@end


// --- LSP Client Manager Interface ---
@interface DietCodeLSPClientManager : NSObject
@property (nonatomic, copy) NSString* serverPath;
@property (nonatomic, copy) NSString* workspacePath;
@property (nonatomic, copy) NSString* language;
@property (nonatomic, strong) NSTask* task;
@property (nonatomic, strong) NSPipe* stdinPipe;
@property (nonatomic, strong) NSPipe* stdoutPipe;
@property (nonatomic, strong) DietCodeLSPReader* reader;
@property (nonatomic, assign) int nextRequestId;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, dispatch_semaphore_t>* pendingRequests;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, NSDictionary*>* pendingResponses;
@property (nonatomic, copy) void (^diagnosticHandler)(NSString*, NSArray*);
@property (nonatomic, copy) void (^errorHandler)(NSString*);

- (instancetype)initWithServerPath:(NSString*)serverPath workspacePath:(NSString*)workspacePath language:(NSString*)language;
- (BOOL)start;
- (void)stop;
- (NSDictionary*)sendRequest:(NSString*)method params:(NSDictionary*)params;
- (void)sendNotification:(NSString*)method params:(NSDictionary*)params;
@end

@implementation DietCodeLSPClientManager

- (instancetype)initWithServerPath:(NSString*)serverPath workspacePath:(NSString*)workspacePath language:(NSString*)language {
    self = [super init];
    if (self) {
        _serverPath = [serverPath copy];
        _workspacePath = [workspacePath copy];
        _language = [language copy];
        _nextRequestId = 1;
        _pendingRequests = [NSMutableDictionary dictionary];
        _pendingResponses = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)start {
    self.task = [[NSTask alloc] init];
    [self.task setLaunchPath:self.serverPath];
    
    // Configure arguments per language
    if ([self.language isEqualToString:@"python"]) {
        [self.task setArguments:@[@"--stdio"]];
    } else if ([self.language isEqualToString:@"javascript"] || [self.language isEqualToString:@"typescript"]) {
        [self.task setArguments:@[@"--stdio"]];
    }
    
    [self.task setCurrentDirectoryPath:self.workspacePath];
    
    self.stdinPipe = [NSPipe pipe];
    self.stdoutPipe = [NSPipe pipe];
    [self.task setStandardInput:self.stdinPipe];
    [self.task setStandardOutput:self.stdoutPipe];
    
    @try {
        [self.task launch];
    } @catch (NSException* e) {
        if (self.errorHandler) {
            self.errorHandler([NSString stringWithFormat:@"Failed to launch %@: %@", self.serverPath, e.reason]);
        }
        return NO;
    }
    
    self.reader = [[DietCodeLSPReader alloc] initWithFileHandle:[self.stdoutPipe fileHandleForReading]];
    __weak DietCodeLSPClientManager* weakSelf = self;
    self.reader.messageHandler = ^(NSDictionary* msg) {
        [weakSelf handleIncomingMessage:msg];
    };
    self.reader.errorHandler = ^(NSString* err) {
        if (weakSelf.errorHandler) {
            weakSelf.errorHandler(err);
        }
    };
    [self.reader start];
    
    [self initializeLSP];
    
    return YES;
}

- (void)stop {
    [self.reader stop];
    if (self.task && self.task.isRunning) {
        [self.task terminate];
    }
}

- (void)initializeLSP {
    NSString* rootUri = [NSString stringWithFormat:@"file://%@", self.workspacePath];
    NSDictionary* params = @{
        @"processId": @(getpid()),
        @"rootPath": self.workspacePath,
        @"rootUri": rootUri,
        @"capabilities": @{
            @"textDocument": @{
                @"completion": @{
                    @"completionItem": @{
                        @"snippetSupport": @NO
                    }
                }
            }
        }
    };
    
    NSDictionary* initResult = [self sendRequest:@"initialize" params:params];
    if (initResult) {
        [self sendNotification:@"initialized" params:@{}];
    }
}

- (NSDictionary*)sendRequest:(NSString*)method params:(NSDictionary*)params {
    int reqId = 0;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    @synchronized (self) {
        reqId = self.nextRequestId++;
        self.pendingRequests[@(reqId)] = sema;
    }
    
    NSDictionary* payload = @{
        @"jsonrpc": @"2.0",
        @"id": @(reqId),
        @"method": method,
        @"params": params
    };
    
    [self writePayload:payload];
    
    int timeoutMs = [method isEqualToString:@"initialize"] ? 10000 : 5000;
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutMs * NSEC_PER_MSEC));
    long waitRes = dispatch_semaphore_wait(sema, timeout);
    
    NSDictionary* response = nil;
    @synchronized (self) {
        [self.pendingRequests removeObjectForKey:@(reqId)];
        response = self.pendingResponses[@(reqId)];
        if (response) {
            [self.pendingResponses removeObjectForKey:@(reqId)];
        }
    }
    
    if (waitRes != 0) {
        return nil;
    }
    
    return response;
}

- (void)sendNotification:(NSString*)method params:(NSDictionary*)params {
    NSDictionary* payload = @{
        @"jsonrpc": @"2.0",
        @"method": method,
        @"params": params
    };
    [self writePayload:payload];
}

- (void)writePayload:(NSDictionary*)payload {
    NSError* err = nil;
    NSData* body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&err];
    if (!body) return;
    
    NSString* header = [NSString stringWithFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)body.length];
    NSData* headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    
    @try {
        [[self.stdinPipe fileHandleForWriting] writeData:headerData];
        [[self.stdinPipe fileHandleForWriting] writeData:body];
    } @catch (NSException* e) {
        // Log error
    }
}

- (void)handleIncomingMessage:(NSDictionary*)msg {
    NSNumber* reqId = msg[@"id"];
    if (reqId != nil && ![reqId isKindOfClass:[NSNull class]]) {
        dispatch_semaphore_t sema = nil;
        @synchronized (self) {
            sema = self.pendingRequests[reqId];
            if (sema) {
                self.pendingResponses[reqId] = msg;
            }
        }
        if (sema) {
            dispatch_semaphore_signal(sema);
        }
    } else {
        NSString* method = msg[@"method"];
        NSDictionary* params = msg[@"params"];
        if ([method isEqualToString:@"textDocument/publishDiagnostics"]) {
            NSString* uri = params[@"uri"];
            NSArray* diagnostics = params[@"diagnostics"];
            
            NSString* filePath = uri;
            if ([uri hasPrefix:@"file://"]) {
                filePath = [uri substringFromIndex:7];
                filePath = [filePath stringByRemovingPercentEncoding];
            }
            
            if (self.diagnosticHandler) {
                self.diagnosticHandler(filePath, diagnostics);
            }
        }
    }
}
@end


// --- LSPClient C++ Implementation ---
namespace dietcode::lsp {

class LSPClient::Impl {
public:
    std::string language;
    std::string serverPath;
    std::string workspacePath;
    std::function<void(const std::string&, const std::vector<Diagnostic>&)> diagCallback;
    std::function<void(const std::string&)> errCallback;
    
    DietCodeLSPClientManager* manager;
    bool running = false;

    // Thread-safe flag to guard ObjC block captures. When the LSPClient is
    // destroyed, alive_ is set to false so that any in-flight blocks from
    // the reader thread no-op instead of dereferencing a dangling pointer.
    std::shared_ptr<std::atomic<bool>> alive = std::make_shared<std::atomic<bool>>(true);

    // Per-document version counters for LSP spec compliance (S-10).
    std::unordered_map<std::string, int> documentVersions;
};

LSPClient::LSPClient(const std::string& language, const std::string& serverPath, const std::string& workspacePath,
                     std::function<void(const std::string&, const std::vector<Diagnostic>&)> diagnosticCallback,
                     std::function<void(const std::string&)> errorCallback)
    : impl_(std::make_unique<Impl>()) {
    impl_->language = language;
    impl_->serverPath = serverPath;
    impl_->workspacePath = workspacePath;
    impl_->diagCallback = diagnosticCallback;
    impl_->errCallback = errorCallback;
    
    NSString* sPath = [NSString stringWithUTF8String:serverPath.c_str()];
    NSString* wPath = [NSString stringWithUTF8String:workspacePath.c_str()];
    NSString* lang = [NSString stringWithUTF8String:language.c_str()];
    
    impl_->manager = [[DietCodeLSPClientManager alloc] initWithServerPath:sPath workspacePath:wPath language:lang];
    
    // Capture a weak (shared_ptr) reference to the alive flag so blocks can
    // safely check whether the Impl is still valid. This prevents
    // use-after-free when blocks fire after LSPClient destruction.
    std::weak_ptr<std::atomic<bool>> weakAlive = impl_->alive;
    Impl* rawImpl = impl_.get();
    impl_->manager.diagnosticHandler = ^(NSString* filePath, NSArray* diagnostics) {
        auto alivePtr = weakAlive.lock();
        if (!alivePtr || !alivePtr->load()) return;
        std::vector<Diagnostic> diags;
        for (NSDictionary* d in diagnostics) {
            Diagnostic diag;
            NSDictionary* range = d[@"range"];
            NSDictionary* start = range[@"start"];
            diag.line = [start[@"line"] intValue] + 1; // LSP line is 0-based
            diag.column = [start[@"character"] intValue] + 1; // LSP column is 0-based
            diag.message = std::string([d[@"message"] ?: @"" UTF8String]);
            
            int severityCode = [d[@"severity"] intValue];
            if (severityCode == 1) diag.severity = "error";
            else if (severityCode == 2) diag.severity = "warning";
            else if (severityCode == 3) diag.severity = "info";
            else diag.severity = "hint";
            
            diags.push_back(diag);
        }
        rawImpl->diagCallback(std::string([filePath UTF8String]), diags);
    };
    
    impl_->manager.errorHandler = ^(NSString* err) {
        auto alivePtr = weakAlive.lock();
        if (!alivePtr || !alivePtr->load()) return;
        rawImpl->errCallback(std::string([err UTF8String]));
    };
}

LSPClient::~LSPClient() {
    if (impl_) {
        impl_->alive->store(false);
        stop();
    }
}

LSPClient::LSPClient(LSPClient&&) noexcept = default;
LSPClient& LSPClient::operator=(LSPClient&&) noexcept = default;

bool LSPClient::start() {
    if (impl_->running) return true;
    BOOL ok = [impl_->manager start];
    if (ok) {
        impl_->running = true;
    }
    return ok;
}

void LSPClient::stop() {
    if (!impl_->running) return;
    [impl_->manager stop];
    impl_->running = false;
}

bool LSPClient::isRunning() const {
    return impl_->running;
}

void LSPClient::didOpen(const std::string& filePath, const std::string& text) {
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    NSString* langId = @"plaintext";
    if (impl_->language == "cpp") langId = @"cpp";
    else if (impl_->language == "python") langId = @"python";
    else if (impl_->language == "javascript" || impl_->language == "typescript") langId = @"typescript";
    
    impl_->documentVersions[filePath] = 1;
    [impl_->manager sendNotification:@"textDocument/didOpen" params:@{
        @"textDocument": @{
            @"uri": uri,
            @"languageId": langId,
            @"version": @1,
            @"text": [NSString stringWithUTF8String:text.c_str()]
        }
    }];
}

void LSPClient::didChange(const std::string& filePath, const std::string& text) {
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    int version = ++(impl_->documentVersions[filePath]);
    [impl_->manager sendNotification:@"textDocument/didChange" params:@{
        @"textDocument": @{
            @"uri": uri,
            @"version": @(version)
        },
        @"contentChanges": @[
            @{ @"text": [NSString stringWithUTF8String:text.c_str()] }
        ]
    }];
}

void LSPClient::didClose(const std::string& filePath) {
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    [impl_->manager sendNotification:@"textDocument/didClose" params:@{
        @"textDocument": @{
            @"uri": uri
        }
    }];
    impl_->documentVersions.erase(filePath);
}

void LSPClient::didSave(const std::string& filePath) {
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    [impl_->manager sendNotification:@"textDocument/didSave" params:@{
        @"textDocument": @{
            @"uri": uri
        }
    }];
}

std::vector<CompletionItem> LSPClient::getCompletions(const std::string& filePath, int line, int column) {
    std::vector<CompletionItem> result;
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    
    NSDictionary* resp = [impl_->manager sendRequest:@"textDocument/completion" params:@{
        @"textDocument": @{ @"uri": uri },
        @"position": @{ @"line": @(line - 1), @"character": @(column - 1) }
    }];
    
    if (!resp) return result;
    
    id itemsVal = resp[@"result"];
    NSArray* items = nil;
    if ([itemsVal isKindOfClass:[NSArray class]]) {
        items = itemsVal;
    } else if ([itemsVal isKindOfClass:[NSDictionary class]]) {
        items = itemsVal[@"items"];
    }
    
    for (NSDictionary* item in items) {
        CompletionItem c;
        c.label = std::string([item[@"label"] ?: @"" UTF8String]);
        c.detail = std::string([item[@"detail"] ?: @"" UTF8String]);
        c.insertText = std::string([item[@"insertText"] ?: item[@"label"] ?: @"" UTF8String]);
        result.push_back(c);
    }
    
    return result;
}

DefinitionLocation LSPClient::getDefinition(const std::string& filePath, int line, int column) {
    DefinitionLocation def;
    def.line = -1;
    def.column = -1;
    
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    NSDictionary* resp = [impl_->manager sendRequest:@"textDocument/definition" params:@{
        @"textDocument": @{ @"uri": uri },
        @"position": @{ @"line": @(line - 1), @"character": @(column - 1) }
    }];
    
    if (!resp) return def;
    
    id resVal = resp[@"result"];
    NSDictionary* loc = nil;
    if ([resVal isKindOfClass:[NSArray class]]) {
        if ([resVal count] > 0) {
            loc = resVal[0];
        }
    } else if ([resVal isKindOfClass:[NSDictionary class]]) {
        loc = resVal;
    }
    
    if (loc) {
        NSString* targetUri = loc[@"uri"];
        NSDictionary* range = loc[@"range"];
        NSDictionary* start = range[@"start"];
        
        def.uri = std::string([targetUri UTF8String]);
        if ([targetUri hasPrefix:@"file://"]) {
            NSString* path = [targetUri substringFromIndex:7];
            path = [path stringByRemovingPercentEncoding];
            def.filePath = std::string([path UTF8String]);
        } else {
            def.filePath = def.uri;
        }
        
        def.line = [start[@"line"] intValue] + 1;
        def.column = [start[@"character"] intValue] + 1;
    }
    
    return def;
}

std::vector<DocumentSymbol> LSPClient::getDocumentSymbols(const std::string& filePath) {
    std::vector<DocumentSymbol> result;
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    
    NSDictionary* resp = [impl_->manager sendRequest:@"textDocument/documentSymbol" params:@{
        @"textDocument": @{ @"uri": uri }
    }];
    
    if (!resp) return result;
    
    NSArray* symbols = resp[@"result"];
    if (![symbols isKindOfClass:[NSArray class]]) return result;
    
    for (NSDictionary* sym in symbols) {
        DocumentSymbol s;
        s.name = std::string([sym[@"name"] ?: @"" UTF8String]);
        
        int kindCode = [sym[@"kind"] intValue];
        // simple mapping of kind
        switch (kindCode) {
            case 1: s.kind = "File"; break;
            case 2: s.kind = "Module"; break;
            case 3: s.kind = "Namespace"; break;
            case 4: s.kind = "Package"; break;
            case 5: s.kind = "Class"; break;
            case 6: s.kind = "Method"; break;
            case 7: s.kind = "Property"; break;
            case 8: s.kind = "Field"; break;
            case 9: s.kind = "Constructor"; break;
            case 10: s.kind = "Enum"; break;
            case 11: s.kind = "Interface"; break;
            case 12: s.kind = "Function"; break;
            case 13: s.kind = "Variable"; break;
            case 14: s.kind = "Constant"; break;
            default: s.kind = "Symbol"; break;
        }
        
        // Symbol range — start position
        NSDictionary* range = sym[@"range"] ?: sym[@"location"][@"range"];
        if (range) {
            NSDictionary* start = range[@"start"];
            s.line = [start[@"line"] intValue] + 1;
            s.column = [start[@"character"] intValue] + 1;
            NSDictionary* end = range[@"end"];
            if (end) {
                s.endLine = [end[@"line"] intValue] + 1;
                s.endColumn = [end[@"character"] intValue] + 1;
            }
        } else {
            s.line = 1;
            s.column = 1;
        }
        
        result.push_back(s);
    }
    
    return result;
}

std::string LSPClient::getHover(const std::string& filePath, int line, int column) {
    NSString* uri = [NSString stringWithFormat:@"file://%@", [NSString stringWithUTF8String:filePath.c_str()]];
    
    NSDictionary* resp = [impl_->manager sendRequest:@"textDocument/hover" params:@{
        @"textDocument": @{ @"uri": uri },
        @"position": @{ @"line": @(line - 1), @"character": @(column - 1) }
    }];
    
    if (!resp) return "";
    
    id resultVal = resp[@"result"];
    if ([resultVal isKindOfClass:[NSDictionary class]]) {
        id contents = resultVal[@"contents"];
        if ([contents isKindOfClass:[NSString class]]) {
            return std::string([contents UTF8String]);
        } else if ([contents isKindOfClass:[NSDictionary class]]) {
            return std::string([contents[@"value"] ?: @"" UTF8String]);
        } else if ([contents isKindOfClass:[NSArray class]]) {
            std::string hoverText = "";
            for (id item in contents) {
                if ([item isKindOfClass:[NSString class]]) {
                    hoverText += std::string([item UTF8String]) + "\n";
                } else if ([item isKindOfClass:[NSDictionary class]]) {
                    hoverText += std::string([item[@"value"] ?: @"" UTF8String]) + "\n";
                }
            }
            return hoverText;
        }
    }
    
    return "";
}

} // namespace dietcode::lsp
