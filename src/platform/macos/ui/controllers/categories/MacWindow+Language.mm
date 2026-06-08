#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#include "utils/LanguageDetection.hpp"

using namespace dietcode::platform::macos;
using namespace dietcode::utils;

@implementation DietCodeWindowController (Language)

- (NSString*)detectLanguage:(NSString*)path {
    std::string lang = detectLanguage(StdStringFromNSString(path));
    return lang.empty() ? nil : NSStringFromStdString(lang);
}

- (dietcode::lsp::LSPClient*)lspClientForLanguage:(NSString*)language {
    if ([language isEqualToString:@"cpp"]) {
        return cppLspClient_;
    } else if ([language isEqualToString:@"python"]) {
        return pythonLspClient_;
    } else if ([language isEqualToString:@"javascript"]) {
        return tsLspClient_;
    }
    return nullptr;
}

- (NSString*)autoDetectBinaryForLanguage:(NSString*)language type:(NSString*)type {
    NSString* binaryName = nil;
    if ([language isEqualToString:@"cpp"]) {
        if ([type isEqualToString:@"lsp"]) binaryName = @"clangd";
        else if ([type isEqualToString:@"formatter"]) binaryName = @"clang-format";
        else if ([type isEqualToString:@"linter"]) binaryName = @"clang-tidy";
    } else if ([language isEqualToString:@"python"]) {
        if ([type isEqualToString:@"lsp"]) binaryName = @"pyright-langserver";
        else if ([type isEqualToString:@"formatter"]) binaryName = @"black";
        else if ([type isEqualToString:@"linter"]) binaryName = @"ruff";
    } else if ([language isEqualToString:@"javascript"] || [language isEqualToString:@"typescript"]) {
        if ([type isEqualToString:@"lsp"]) binaryName = @"typescript-language-server";
        else if ([type isEqualToString:@"formatter"]) binaryName = @"prettier";
        else if ([type isEqualToString:@"linter"]) binaryName = @"eslint";
    }
    
    if (!binaryName) return nil;
    return FindBinaryPath(binaryName, nil);
}

- (void)startLSPForLanguage:(NSString*)language {
    dietcode::lsp::LSPClient* client = [self lspClientForLanguage:language];
    if (client && client->isRunning()) {
        return;
    }
    
    NSString* serverPath = nil;
    if ([language isEqualToString:@"cpp"]) {
        serverPath = self.clangdPath;
    } else if ([language isEqualToString:@"python"]) {
        serverPath = self.pyrightPath;
    } else if ([language isEqualToString:@"javascript"]) {
        serverPath = self.tsserverPath;
    }
    
    if (!serverPath || serverPath.length == 0) {
        serverPath = [self autoDetectBinaryForLanguage:language type:@"lsp"];
    }
    
    if (!serverPath || ![[NSFileManager defaultManager] isExecutableFileAtPath:serverPath]) {
        [self logOutput:[NSString stringWithFormat:@"[LSP] Error: LSP binary not found or not executable at '%@'\n", serverPath]];
        return;
    }
    
    std::string stdServerPath = StdStringFromNSString(serverPath);
    std::string stdWorkspacePath = self.openedFolderPath ? StdStringFromNSString(self.openedFolderPath) : "";
    if (stdWorkspacePath.empty() && self.activeTab && self.activeTab.path) {
        stdWorkspacePath = std::filesystem::path(StdStringFromNSString(self.activeTab.path)).parent_path().string();
    }
    
    __weak DietCodeWindowController* weakSelf = self;
    
    auto diagCallback = [weakSelf](const std::string& filePath, const std::vector<dietcode::lsp::Diagnostic>& diagnostics) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DietCodeWindowController* strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSString* nsFilePath = NSStringFromStdString(filePath);
            NSMutableArray* list = [NSMutableArray array];
            for (const auto& diag : diagnostics) {
                [list addObject:@{
                    @"line": @(diag.line),
                    @"column": @(diag.column),
                    @"message": NSStringFromStdString(diag.message),
                    @"severity": NSStringFromStdString(diag.severity)
                }];
            }
            [strongSelf handleDiagnostics:list forFile:nsFilePath source:@"lsp"];
        });
    };
    
    auto errorCallback = [weakSelf, language](const std::string& errorMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DietCodeWindowController* strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf logOutput:[NSString stringWithFormat:@"[LSP] [%@] Error: %s\n", language, errorMsg.c_str()]];
        });
    };
    
    dietcode::lsp::LSPClient* newClient = new dietcode::lsp::LSPClient(
        StdStringFromNSString(language),
        stdServerPath,
        stdWorkspacePath,
        diagCallback,
        errorCallback
    );
    
    if ([language isEqualToString:@"cpp"]) {
        if (cppLspClient_) { cppLspClient_->stop(); delete cppLspClient_; }
        cppLspClient_ = newClient;
    } else if ([language isEqualToString:@"python"]) {
        if (pythonLspClient_) { pythonLspClient_->stop(); delete pythonLspClient_; }
        pythonLspClient_ = newClient;
    } else if ([language isEqualToString:@"javascript"]) {
        if (tsLspClient_) { tsLspClient_->stop(); delete tsLspClient_; }
        tsLspClient_ = newClient;
    }
    
    if (newClient->start()) {
        [self logOutput:[NSString stringWithFormat:@"[LSP] [%@] Started server: %@\n", language, serverPath]];
        if (self.activeTab && self.activeTab.path) {
            NSString* activeLang = [self detectLanguage:self.activeTab.path];
            if ([activeLang isEqualToString:language]) {
                newClient->didOpen(StdStringFromNSString(self.activeTab.path), StdStringFromNSString([self.activeTab.textView string]));
            }
        }
    } else {
        [self logOutput:[NSString stringWithFormat:@"[LSP] [%@] Failed to start server at: %@\n", language, serverPath]];
    }
}

- (void)stopLSPForLanguage:(NSString*)language {
    if ([language isEqualToString:@"cpp"] && cppLspClient_) {
        cppLspClient_->stop();
        delete cppLspClient_;
        cppLspClient_ = nullptr;
    } else if ([language isEqualToString:@"python"] && pythonLspClient_) {
        pythonLspClient_->stop();
        delete pythonLspClient_;
        pythonLspClient_ = nullptr;
    } else if ([language isEqualToString:@"javascript"] && tsLspClient_) {
        tsLspClient_->stop();
        delete tsLspClient_;
        tsLspClient_ = nullptr;
    }
}

- (void)promptLanguageFeaturesIfNeeded:(NSString*)filePath {
    NSString* language = [self detectLanguage:filePath];
    if (!language) return;
    
    NSString* targetFolder = nil;
    if (self.openedFolderPath && [filePath hasPrefix:self.openedFolderPath]) {
        targetFolder = self.openedFolderPath;
    } else {
        targetFolder = [filePath stringByDeletingLastPathComponent];
    }
    if (!targetFolder) return;
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* lspSettings = [defaults dictionaryForKey:@"LspSettings"] ?: @{};
    
    NSString* key = [NSString stringWithFormat:@"%@:%@", targetFolder, language];
    NSString* choice = lspSettings[key];
    
    if ([choice isEqualToString:@"enable"]) {
        [self startLSPForLanguage:language];
    }
}

- (BOOL)checkAndPromptLSPForLanguage:(NSString*)language filePath:(NSString*)filePath {
    NSString* targetFolder = nil;
    if (self.openedFolderPath && [filePath hasPrefix:self.openedFolderPath]) {
        targetFolder = self.openedFolderPath;
    } else {
        targetFolder = [filePath stringByDeletingLastPathComponent];
    }
    if (!targetFolder) return NO;
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* lspSettings = [defaults dictionaryForKey:@"LspSettings"] ?: @{};
    
    NSString* key = [NSString stringWithFormat:@"%@:%@", targetFolder, language];
    NSString* choice = lspSettings[key];
    
    if ([choice isEqualToString:@"enable"]) {
        [self startLSPForLanguage:language];
        return YES;
    } else if ([choice isEqualToString:@"disable"]) {
        [self logOutput:[NSString stringWithFormat:@"[Language Features] Disabled for this folder. Enable in Settings to run.\n"]];
        return NO;
    }
    
    if (self.isHeadless) {
        if (![choice isEqualToString:@"enable"]) {
            NSMutableDictionary* newLspSettings = [lspSettings mutableCopy];
            newLspSettings[key] = @"enable";
            [defaults setObject:newLspSettings forKey:@"LspSettings"];
            [defaults synchronize];
        }
        [self startLSPForLanguage:language];
        return YES;
    }
    
    NSAlert* alert = [[NSAlert alloc] init];
    NSString* langName = [language isEqualToString:@"cpp"] ? @"C++" : ([language isEqualToString:@"python"] ? @"Python" : @"JavaScript/TypeScript");
    [alert setMessageText:[NSString stringWithFormat:@"Enable %@ Language Features?", langName]];
    [alert setInformativeText:[NSString stringWithFormat:@"Would you like to enable autocompletion, diagnostics, formatting, and definition lookup for %@ files in this folder?\n\nFolder: %@", langName, targetFolder]];
    [alert addButtonWithTitle:@"Enable"];
    [alert addButtonWithTitle:@"Not Now"];
    [alert addButtonWithTitle:@"Disable for this Folder"];
    
    NSInteger response = [alert runModal];
    
    NSMutableDictionary* newLspSettings = [lspSettings mutableCopy];
    BOOL enabled = NO;
    if (response == NSAlertFirstButtonReturn) {
        newLspSettings[key] = @"enable";
        [self startLSPForLanguage:language];
        enabled = YES;
    } else if (response == NSAlertSecondButtonReturn) {
        newLspSettings[key] = @"not_now";
    } else {
        newLspSettings[key] = @"disable";
    }
    
    [defaults setObject:newLspSettings forKey:@"LspSettings"];
    [defaults synchronize];
    return enabled;
}

- (void)formatTab:(DietCodeTabState*)tab {
    if (!tab || !tab.path) return;
    NSString* language = [self detectLanguage:tab.path];
    if (!language) return;
    
    NSString* formatterPath = nil;
    NSArray* formatterArgs = nil;
    
    if ([language isEqualToString:@"cpp"]) {
        formatterPath = self.clangFormatPath;
        formatterArgs = @[@"-assume-filename", tab.path];
    } else if ([language isEqualToString:@"python"]) {
        formatterPath = self.blackPath;
        formatterArgs = @[@"-", @"--stdin-filename", tab.path];
    } else if ([language isEqualToString:@"javascript"]) {
        formatterPath = self.prettierPath;
        formatterArgs = @[@"--stdin-filepath", tab.path];
    }
    
    if (!formatterPath || formatterPath.length == 0) {
        formatterPath = [self autoDetectBinaryForLanguage:language type:@"formatter"];
        if (!formatterPath) return;
    }
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:formatterPath]) {
        return;
    }
    
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:formatterPath];
    [task setArguments:formatterArgs];
    
    NSPipe* inPipe = [NSPipe pipe];
    NSPipe* outPipe = [NSPipe pipe];
    [task setStandardInput:inPipe];
    [task setStandardOutput:outPipe];
    
    NSString* originalText = [tab.textView string];
    NSData* inData = [originalText dataUsingEncoding:NSUTF8StringEncoding];
    
    @try {
        [task launch];
        [[inPipe fileHandleForWriting] writeData:inData];
        [[inPipe fileHandleForWriting] closeFile];
        
        NSData* outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
        [task waitUntilExit];
        
        if (task.terminationStatus == 0) {
            NSString* formatted = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
            if (formatted && ![formatted isEqualToString:originalText]) {
                [tab.textView setString:formatted];
                tab.dirty = YES;
                [self updateTabHeaderLayout];
            }
        }
    } @catch (NSException* e) {}
}

- (void)runLinterForTab:(DietCodeTabState*)tab {
    if (!tab || !tab.path) return;
    NSString* language = [self detectLanguage:tab.path];
    if (!language) return;
    
    NSString* linterPath = nil;
    NSArray* linterArgs = nil;
    
    if ([language isEqualToString:@"cpp"]) {
        linterPath = self.clangTidyPath;
        linterArgs = @[tab.path];
    } else if ([language isEqualToString:@"python"]) {
        linterPath = self.ruffPath;
        linterArgs = @[@"check", tab.path];
    } else if ([language isEqualToString:@"javascript"]) {
        linterPath = self.eslintPath;
        linterArgs = @[@"--format", @"compact", tab.path];
    }
    
    if (!linterPath || linterPath.length == 0) {
        linterPath = [self autoDetectBinaryForLanguage:language type:@"linter"];
        if (!linterPath) return;
    }
    
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:linterPath]) {
        return;
    }
    
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:linterPath];
    [task setArguments:linterArgs];
    
    NSPipe* outPipe = [NSPipe pipe];
    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:errPipe];
    
    __weak DietCodeWindowController* weakSelf = self;
    NSString* pathCopy = [tab.path copy];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            [task launch];
            NSData* outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
            NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            
            NSString* output = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
            NSString* errorOutput = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                DietCodeWindowController* strongSelf = weakSelf;
                if (!strongSelf) return;
                NSMutableArray* diags = [strongSelf parseLinterOutput:output errorOutput:errorOutput language:language filePath:pathCopy];
                [strongSelf handleDiagnostics:diags forFile:pathCopy source:@"linter"];
            });
        } @catch (NSException* e) {}
    });
}

- (NSMutableArray*)parseLinterOutput:(NSString*)output errorOutput:(NSString*)errorOutput language:(NSString*)language filePath:(NSString*)filePath {
    NSMutableArray* diags = [NSMutableArray array];
    NSString* fullText = [NSString stringWithFormat:@"%@\n%@", output, errorOutput];
    NSArray* lines = [fullText componentsSeparatedByString:@"\n"];
    
    for (NSString* line in lines) {
        if (line.length == 0) continue;
        
        NSArray* parts = [line componentsSeparatedByString:@":"];
        if (parts.count >= 4) {
            NSInteger lineNum = [parts[1] integerValue];
            NSInteger colNum = [parts[2] integerValue];
            if (lineNum > 0) {
                NSString* message = [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@":"];
                [diags addObject:@{
                    @"line": @(lineNum),
                    @"column": @(colNum),
                    @"message": [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
                    @"severity": [message.lowercaseString containsString:@"error"] ? @"error" : @"warning"
                }];
            }
        }
    }
    return diags;
}

- (void)goToDefinitionClicked:(id)sender {
    if (!self.activeTab.path || !self.textView) return;

    NSRange selected = self.textView.selectedRange;
    NSString* content = self.textView.string ?: @"";
    NSUInteger line = 1, col = 1, idx = 0;
    while (idx < selected.location && idx < content.length) {
        if ([content characterAtIndex:idx] == '\n') { line++; col = 1; }
        else col++;
        idx++;
    }

    NSString* language = [self detectLanguage:self.activeTab.path];
    dietcode::lsp::LSPClient* client = [self lspClientForLanguage:language];
    if (!client || !client->isRunning()) {
        [self showErrorAlert:@"Go to Definition" message:@"Language server is not running for this file."];
        return;
    }

    auto def = client->getDefinition(StdStringFromNSString(self.activeTab.path), (int)line, (int)col);
    if (def.line < 1) {
        [self showErrorAlert:@"Go to Definition" message:@"No definition found at the cursor."];
        return;
    }

    NSString* targetPath = NSStringFromStdString(def.filePath);
    [self openFileAtPath:targetPath line:def.line column:def.column];
}

- (void)handleMouseHoverInTextView:(NSTextView*)textView atPoint:(NSPoint)point {
    if (!self.activeTab || !self.activeTab.path) return;
    
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSTextContainer *textContainer = textView.textContainer;
    NSPoint containerPoint = NSMakePoint(point.x - textView.textContainerOrigin.x, point.y - textView.textContainerOrigin.y);
    
    NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:containerPoint inTextContainer:textContainer];
    NSUInteger charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    
    if (charIndex >= textView.string.length) return;
    
    NSString* language = [self detectLanguage:self.activeTab.path];
    dietcode::lsp::LSPClient* client = [self lspClientForLanguage:language];
    if (client && client->isRunning()) {
        NSString* content = textView.string;
        NSUInteger line = 1, col = 1, idx = 0;
        while (idx < charIndex) {
            if ([content characterAtIndex:idx] == '\n') { line++; col = 1; }
            else col++;
            idx++;
        }
        
        std::string hover = client->getHover(StdStringFromNSString(self.activeTab.path), (int)line, (int)col);
        if (!hover.empty()) {
            [textView setToolTip:NSStringFromStdString(hover)];
        } else {
            [textView setToolTip:nil];
        }
    }
}

- (void)logOutput:(NSString*)text {
    [self appendOutputText:text];
}

- (void)showErrorAlert:(NSString*)title message:(NSString*)message {
    if (self.isHeadless) {
        NSLog(@"ERROR: %@ - %@", title, message);
        return;
    }
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert runModal];
}

@end
