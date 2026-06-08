#import "DietCodeLegacyWindowBridge.hpp"
#import "WorkspaceSessionBridge.hpp"
#include "kernel/workspace/WorkspaceSession.hpp"
#import "MacWindow.hpp"
#import "MacWindow+Private.hpp"

@implementation DietCodeLegacyWindowBridge {
    __weak DietCodeWindowController* _controller;
}

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller {
    DietCodeWorkspaceSession* session = [[DietCodeWorkspaceSession alloc] init];
    if (controller.workspacePath.length > 0) {
        [session setWorkspaceRoot:controller.workspacePath];
    }
    self = [super initWithWorkspaceSession:session windowController:nil];
    if (self) {
        _controller = controller;
        __weak DietCodeWindowController* weakController = controller;
        session.cppSession->setEditorTextOverlay(
            [weakController](const std::string& absolutePath) -> std::optional<std::string> {
                DietCodeWindowController* strong = weakController;
                if (!strong) return std::nullopt;
                NSString* path = [NSString stringWithUTF8String:absolutePath.c_str()];
                NSString* text = [strong textForFileAtPath:path];
                if (text.length == 0) return std::nullopt;
                return std::string([text UTF8String]);
            });
    }
    return self;
}

- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path {
    if (_controller) {
        if ([NSThread isMainThread]) {
            if ([_controller replaceTextInRange:range withText:text forFileAtPath:path]) return YES;
        } else {
            __block BOOL res = NO;
            dispatch_sync(dispatch_get_main_queue(), ^{
                res = [_controller replaceTextInRange:range withText:text forFileAtPath:path];
            });
            if (res) return YES;
        }
    }
    return [super replaceTextInRange:range withText:text forFileAtPath:path];
}

- (NSArray<NSString*>*)openFilePaths {
    if (!_controller) return [super openFilePaths];
    if ([NSThread isMainThread]) return [_controller openFilePaths];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller openFilePaths]; });
    return res ?: @[];
}

- (NSArray<NSDictionary*>*)problemsList {
    if (!_controller) return [super problemsList];
    if ([NSThread isMainThread]) return [_controller problemsList];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller problemsList]; });
    return res ?: @[];
}

- (NSString*)activeFilePath {
    if (!_controller) return [super activeFilePath];
    if ([NSThread isMainThread]) return [_controller activeFilePath] ?: @"";
    __block NSString* res = @"";
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller activeFilePath] ?: @""; });
    return res;
}

- (NSArray*)openTabs {
    if (!_controller) return [super openTabs];
    if ([NSThread isMainThread]) return [_controller.openTabs copy];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller.openTabs copy]; });
    return res ?: @[];
}

- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut {
    if (_controller) {
        if ([NSThread isMainThread]) {
            if ([_controller applyPatchAtPath:path patchString:patchString errorOut:errorOut]) return YES;
        } else {
            __block BOOL res = NO;
            __block NSString* err = nil;
            dispatch_sync(dispatch_get_main_queue(), ^{
                res = [_controller applyPatchAtPath:path patchString:patchString errorOut:&err];
            });
            if (res) {
                if (errorOut) *errorOut = nil;
                return YES;
            }
            if (errorOut && err) *errorOut = err;
        }
    }
    return [super applyPatchAtPath:path patchString:patchString errorOut:errorOut];
}

- (NSDictionary*)activeSelectionInfo {
    if (!_controller) return [super activeSelectionInfo];
    if ([NSThread isMainThread]) return [_controller activeSelectionInfo];
    __block NSDictionary* res = @{};
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller activeSelectionInfo] ?: @{}; });
    return res;
}

- (NSString*)terminalOutput {
    if (!_controller) return [super terminalOutput];
    if ([NSThread isMainThread]) return [_controller terminalOutput] ?: @"";
    __block NSString* res = @"";
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller terminalOutput] ?: @""; });
    return res;
}

- (pid_t)terminalPid {
    if (!_controller) return [super terminalPid];
    if ([NSThread isMainThread]) return [_controller terminalPid];
    __block pid_t res = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller terminalPid]; });
    return res;
}

- (NSArray*)languageDiagnosticsForPath:(NSString*)path {
    if (!_controller) return [super languageDiagnosticsForPath:path];
    if ([NSThread isMainThread]) return [_controller languageDiagnosticsForPath:path];
    __block NSArray* res = @[];
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller languageDiagnosticsForPath:path] ?: @[]; });
    return res;
}

- (NSInteger)agentAutonomyLevel {
    if (!_controller) return [super agentAutonomyLevel];
    if ([NSThread isMainThread]) return [_controller agentAutonomyLevel];
    __block NSInteger res = [super agentAutonomyLevel];
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller agentAutonomyLevel]; });
    return res;
}

- (NSString*)hoverAtLocation:(NSString*)path line:(NSInteger)line column:(NSInteger)column {
    if (!_controller) return [super hoverAtLocation:path line:line column:column];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString* lang = [_controller detectLanguage:path];
        dietcode::lsp::LSPClient* client = [_controller lspClientForLanguage:lang];
        if (client && client->isRunning()) {
            std::string hover = client->getHover([path UTF8String], (int)line, (int)column);
            res = [NSString stringWithUTF8String:hover.c_str()];
        }
    });
    return res;
}

- (NSArray*)completionsAtLocation:(NSString*)path line:(NSInteger)line column:(NSInteger)column {
    if (!_controller) return [super completionsAtLocation:path line:line column:column];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString* lang = [_controller detectLanguage:path];
        dietcode::lsp::LSPClient* client = [_controller lspClientForLanguage:lang];
        if (client && client->isRunning()) {
            auto items = client->getCompletions([path UTF8String], (int)line, (int)column);
            NSMutableArray* list = [NSMutableArray array];
            for (const auto& item : items) {
                [list addObject:@{
                    @"label": [NSString stringWithUTF8String:item.label.c_str()],
                    @"detail": [NSString stringWithUTF8String:item.detail.c_str()],
                    @"insertText": [NSString stringWithUTF8String:item.insertText.c_str()]
                }];
            }
            res = list;
        }
    });
    return res;
}

- (NSDictionary*)definitionAtLocation:(NSString*)path line:(NSInteger)line column:(NSInteger)column {
    if (!_controller) return [super definitionAtLocation:path line:line column:column];
    __block NSDictionary* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString* lang = [_controller detectLanguage:path];
        dietcode::lsp::LSPClient* client = [_controller lspClientForLanguage:lang];
        if (client && client->isRunning()) {
            auto def = client->getDefinition([path UTF8String], (int)line, (int)column);
            if (def.line != -1) {
                res = @{
                    @"path": [NSString stringWithUTF8String:def.filePath.c_str()],
                    @"line": @(def.line),
                    @"column": @(def.column)
                };
            }
        }
    });
    return res;
}

- (NSArray*)lspSymbolsForFile:(NSString*)path {
    if (!_controller) return [super lspSymbolsForFile:path];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString* lang = [_controller detectLanguage:path];
        dietcode::lsp::LSPClient* client = [_controller lspClientForLanguage:lang];
        if (client && client->isRunning()) {
            auto symbols = client->getDocumentSymbols([path UTF8String]);
            NSMutableArray* list = [NSMutableArray array];
            for (const auto& s : symbols) {
                [list addObject:@{
                    @"name": [NSString stringWithUTF8String:s.name.c_str()],
                    @"kind": [NSString stringWithUTF8String:s.kind.c_str()],
                    @"line": @(s.line),
                    @"column": @(s.column),
                    @"endLine": @(s.endLine),
                    @"endColumn": @(s.endColumn)
                }];
            }
            res = list;
        }
    });
    return res;
}

@end
