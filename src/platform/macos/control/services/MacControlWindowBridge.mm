#import "MacControlWindowBridge.hpp"
#import "MacWindow.hpp"
#import "MacWindow+Private.hpp"

@implementation DietCodeControlWindowBridge {
    __weak DietCodeWindowController* _controller;
}

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller {
    self = [super init];
    if (self) {
        _controller = controller;
    }
    return self;
}

- (NSString*)workspacePath {
    if ([NSThread isMainThread]) return [_controller workspacePath];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller workspacePath]; });
    return res;
}

- (NSString*)textForFileAtPath:(NSString*)path {
    if ([NSThread isMainThread]) return [_controller textForFileAtPath:path];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller textForFileAtPath:path]; });
    return res;
}

- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path {
    if ([NSThread isMainThread]) return [_controller replaceTextInRange:range withText:text forFileAtPath:path];
    __block BOOL res = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller replaceTextInRange:range withText:text forFileAtPath:path]; });
    return res;
}

- (NSArray<NSString*>*)openFilePaths {
    if ([NSThread isMainThread]) return [_controller openFilePaths];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller openFilePaths]; });
    return res;
}

- (NSArray<NSDictionary*>*)problemsList {
    if ([NSThread isMainThread]) return [_controller problemsList];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller problemsList]; });
    return res;
}

- (NSString*)activeFilePath {
    if ([NSThread isMainThread]) return [_controller activeFilePath];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller activeFilePath]; });
    return res;
}

- (NSArray*)openTabs {
    if ([NSThread isMainThread]) return [_controller.openTabs copy];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller.openTabs copy]; });
    return res;
}

- (NSDictionary*)gitStatusInfo {
    if ([NSThread isMainThread]) return [_controller gitStatusInfo];
    __block NSDictionary* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller gitStatusInfo]; });
    return res;
}

- (NSString*)gitDiffForFile:(NSString*)path {
    if ([NSThread isMainThread]) return [_controller gitDiffForFile:path];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller gitDiffForFile:path]; });
    return res;
}

- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut {
    if ([NSThread isMainThread]) return [_controller applyPatchAtPath:path patchString:patchString errorOut:errorOut];
    __block BOOL res = NO;
    __block NSString* err = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        res = [_controller applyPatchAtPath:path patchString:patchString errorOut:&err];
    });
    if (errorOut) *errorOut = err;
    return res;
}

- (NSDictionary*)activeSelectionInfo {
    if ([NSThread isMainThread]) return [_controller activeSelectionInfo];
    __block NSDictionary* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller activeSelectionInfo]; });
    return res;
}

- (NSString*)terminalOutput {
    if ([NSThread isMainThread]) return [_controller terminalOutput];
    __block NSString* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller terminalOutput]; });
    return res;
}

- (NSArray*)sessionRecentCommands {
    if ([NSThread isMainThread]) return [_controller.sessionRecentCommands copy];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller.sessionRecentCommands copy]; });
    return res;
}

- (NSArray*)sessionLastSearches {
    if ([NSThread isMainThread]) return [_controller.sessionLastSearches copy];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller.sessionLastSearches copy]; });
    return res;
}

- (pid_t)terminalPid {
    if ([NSThread isMainThread]) return [_controller terminalPid];
    __block pid_t res = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller terminalPid]; });
    return res;
}

- (NSArray*)languageDiagnosticsForPath:(NSString*)path {
    if ([NSThread isMainThread]) return [_controller languageDiagnosticsForPath:path];
    __block NSArray* res = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller languageDiagnosticsForPath:path]; });
    return res;
}

- (NSInteger)agentAutonomyLevel {
    if ([NSThread isMainThread]) return [_controller agentAutonomyLevel];
    __block NSInteger res = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{ res = [_controller agentAutonomyLevel]; });
    return res;
}

- (NSString*)hoverAtLocation:(NSString*)path line:(NSInteger)line column:(NSInteger)column {
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
