#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#include "filesystem/GitService.hpp"

#include <util.h>
#include <unistd.h>

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (AgentAPI)

- (void)notifyAgentEvent:(NSString*)type detail:(NSString*)detail {
    if (self.controlServer) {
        if ([self.controlServer respondsToSelector:@selector(notifyEvent:detail:)]) {
            [self.controlServer performSelector:@selector(notifyEvent:detail:) withObject:type withObject:detail];
        }
    }
}

- (void)setIsHeadless:(BOOL)isHeadless {
    self.isHeadless = isHeadless;
}

- (NSString*)workspacePath {
    return self.openedFolderPath;
}

- (NSArray<NSString*>*)openFilePaths {
    NSMutableArray* paths = [NSMutableArray array];
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.path) [paths addObject:tab.path];
    }
    return paths;
}

- (NSString*)activeFilePath {
    return self.activeTab.path;
}

- (NSString*)textForFileAtPath:(NSString*)path {
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            return tab.textView.string;
        }
    }
    return nil;
}

- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path {
    DietCodeTabState* targetTab = nil;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            targetTab = tab;
            break;
        }
    }
    if (!targetTab || targetTab.isReadOnly) return NO;
    NSTextView* tv = targetTab.textView;
    if (range.location + range.length <= tv.string.length) {
        if ([tv shouldChangeTextInRange:range replacementString:text]) {
            [tv.textStorage replaceCharactersInRange:range withString:text];
            [tv didChangeText];
            return YES;
        }
    }
    return NO;
}

- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut {
    DietCodeTabState* targetTab = nil;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            targetTab = tab;
            break;
        }
    }
    if (!targetTab || targetTab.isReadOnly) {
        if (errorOut) *errorOut = @"File is not open or is read-only.";
        return NO;
    }
    
    NSString* currentText = [targetTab.textView string];
    NSString* tempDir = NSTemporaryDirectory() ?: @"/tmp";
    NSString* tempSrcPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_patch_src_%u.txt", arc4random()]];
    NSString* tempDiffPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"dietcode_patch_diff_%u.diff", arc4random()]];
    
    NSError* err = nil;
    unlink([tempSrcPath UTF8String]);
    [currentText writeToFile:tempSrcPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write temp source: %@", err.localizedDescription];
        return NO;
    }
    unlink([tempDiffPath UTF8String]);
    [patchString writeToFile:tempDiffPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write temp patch: %@", err.localizedDescription];
        return NO;
    }
    
    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/patch"];
    [task setArguments:@[@"--silent", tempSrcPath, tempDiffPath]];
    
    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardError:errPipe];
    [task setStandardOutput:errPipe];
    
    [task launch];
    NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    if (status != 0) {
        NSString* errMsg = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:tempDiffPath error:nil];
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Patch failed with exit status %d: %@", status, errMsg];
        return NO;
    }
    
    NSString* patchedText = [NSString stringWithContentsOfFile:tempSrcPath encoding:NSUTF8StringEncoding error:&err];
    [[NSFileManager defaultManager] removeItemAtPath:tempSrcPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:tempDiffPath error:nil];
    
    if (err || !patchedText) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to read patched output: %@", err ? err.localizedDescription : @"Unknown error"];
        return NO;
    }
    
    NSTextView* tv = targetTab.textView;
    NSRange sel = tv.selectedRange;
    NSRect visibleRect = tv.visibleRect;
    
    [tv setString:patchedText];
    targetTab.dirty = YES;
    
    if (sel.location <= tv.string.length) {
        tv.selectedRange = sel;
    }
    [tv scrollRectToVisible:visibleRect];
    [self updateWindowTitleAndStatus];
    return YES;
}

- (void)saveFileAtPath:(NSString*)path {
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            [self saveTab:tab];
            break;
        }
    }
}

- (void)closeFileAtPath:(NSString*)path {
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            [self closeTab:tab];
            break;
        }
    }
}

- (void)jumpToLine:(NSInteger)line column:(NSInteger)column {
    if (self.activeTab.path) {
        [self openFileAtPath:self.activeTab.path line:line column:column];
    }
}

- (pid_t)terminalPid {
    return terminalPid_;
}

- (BOOL)runTerminalCommand:(NSString*)command cwd:(NSString*)cwd show:(BOOL)show errorOut:(NSString**)errorOut {
    if (command.length == 0) {
        if (errorOut) *errorOut = @"Command string required.";
        return NO;
    }
    NSString* runCwd = cwd ?: self.openedFolderPath ?: NSHomeDirectory();
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:runCwd isDirectory:&isDir] || !isDir) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Terminal cwd is not a directory: %@", runCwd];
        return NO;
    }
    if (![self.sessionRecentCommands containsObject:command]) {
        [self.sessionRecentCommands insertObject:command atIndex:0];
        if (self.sessionRecentCommands.count > 50) {
            [self.sessionRecentCommands removeLastObject];
        }
    }
    [self ensureTerminalProcess];
    if (terminalMasterFd_ < 0 || terminalPid_ <= 0) {
        if (errorOut) *errorOut = @"Terminal process is not available.";
        return NO;
    }
    if (show) {
        [self showBottomPanelTab:@"terminal"];
    }
    NSString* quotedCwd = [NSString stringWithFormat:@"'%@'", [runCwd stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
    NSString* cmdStr = [NSString stringWithFormat:@"cd %@ && %@\n", quotedCwd, command];
    const char* utf8 = [cmdStr UTF8String];
    ssize_t written = write(terminalMasterFd_, utf8, strlen(utf8));
    if (written < 0) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write command to terminal: %s", strerror(errno)];
        return NO;
    }
    return YES;
}

- (void)stopTerminalCommand {
    if (terminalPid_ > 0) {
        kill(terminalPid_, SIGINT);
    }
}

- (NSString*)terminalOutput {
    return [self.terminalTextView string];
}

- (void)clearTerminalOutput {
    [self.terminalTextView setString:@""];
}

- (NSDictionary*)gitStatusInfo {
    if (self.openedFolderPath == nil) return @{};
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    auto res = dietcode::filesystem::GitService::getStatus(ws);
    
    NSMutableArray* staged = [NSMutableArray array];
    NSMutableArray* modified = [NSMutableArray array];
    NSMutableArray* untracked = [NSMutableArray array];
    
    for (const auto& c : res.changes) {
        NSString* path = NSStringFromStdString(c.path);
        if (c.staged) {
            [staged addObject:path];
        } else {
            if (c.status == "??" || c.status == "Untracked") {
                [untracked addObject:path];
            } else {
                [modified addObject:path];
            }
        }
    }
    
    return @{
        @"branch": NSStringFromStdString(res.branch),
        @"staged": staged,
        @"modified": modified,
        @"untracked": untracked
    };
}

- (NSString*)gitDiffForFile:(NSString*)path {
    if (self.openedFolderPath == nil) return @"";
    NSString* relPath = path;
    if ([path isAbsolutePath] && [path hasPrefix:self.openedFolderPath]) {
        relPath = [path substringFromIndex:self.openedFolderPath.length];
        if ([relPath hasPrefix:@"/"]) {
            relPath = [relPath substringFromIndex:1];
        }
    }
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    std::string rel = StdStringFromNSString(relPath);
    std::string unstagedDiff = dietcode::filesystem::GitService::getDiff(ws, rel, false);
    std::string stagedDiff = dietcode::filesystem::GitService::getDiff(ws, rel, true);
    return [NSString stringWithFormat:@"%s\n%s", stagedDiff.c_str(), unstagedDiff.c_str()];
}

- (BOOL)gitStageFile:(NSString*)path errorOut:(NSString**)errorOut {
    if (self.openedFolderPath == nil) {
        if (errorOut) *errorOut = @"No open folder workspace.";
        return NO;
    }
    NSString* relPath = path;
    if ([path isAbsolutePath] && [path hasPrefix:self.openedFolderPath]) {
        relPath = [path substringFromIndex:self.openedFolderPath.length];
        if ([relPath hasPrefix:@"/"]) {
            relPath = [relPath substringFromIndex:1];
        }
    }
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    std::string rel = StdStringFromNSString(relPath);
    std::string err;
    BOOL ok = dietcode::filesystem::GitService::stageFile(ws, rel, err);
    if (ok) [self refreshGitStatus];
    else if (errorOut) *errorOut = NSStringFromStdString(err);
    return ok;
}

- (BOOL)gitUnstageFile:(NSString*)path errorOut:(NSString**)errorOut {
    if (self.openedFolderPath == nil) {
        if (errorOut) *errorOut = @"No open folder workspace.";
        return NO;
    }
    NSString* relPath = path;
    if ([path isAbsolutePath] && [path hasPrefix:self.openedFolderPath]) {
        relPath = [path substringFromIndex:self.openedFolderPath.length];
        if ([relPath hasPrefix:@"/"]) {
            relPath = [relPath substringFromIndex:1];
        }
    }
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    std::string rel = StdStringFromNSString(relPath);
    std::string err;
    BOOL ok = dietcode::filesystem::GitService::unstageFile(ws, rel, err);
    if (ok) [self refreshGitStatus];
    else if (errorOut) *errorOut = NSStringFromStdString(err);
    return ok;
}

- (BOOL)gitDiscardFile:(NSString*)path errorOut:(NSString**)errorOut {
    if (self.openedFolderPath == nil) {
        if (errorOut) *errorOut = @"No open folder workspace.";
        return NO;
    }
    NSString* absPath = path;
    NSString* relPath = path;
    if ([path isAbsolutePath]) {
        if ([path hasPrefix:self.openedFolderPath]) {
            relPath = [path substringFromIndex:self.openedFolderPath.length];
            if ([relPath hasPrefix:@"/"]) {
                relPath = [relPath substringFromIndex:1];
            }
        }
    } else {
        absPath = [self.openedFolderPath stringByAppendingPathComponent:path];
    }
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    std::string rel = StdStringFromNSString(relPath);
    std::string err;
    BOOL ok = dietcode::filesystem::GitService::discardChanges(ws, rel, err);
    if (ok) {
        [self refreshGitStatus];
        for (DietCodeTabState* tab in self.openTabs) {
            if ([tab.path isEqualToString:absPath]) {
                const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(tab.path)));
                if (result.ok) {
                    self.loadingDocument = YES;
                    [tab.textView setString:NSStringFromStdString(result.contents)];
                    self.loadingDocument = NO;
                    tab.dirty = NO;
                    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tab.path error:nil];
                    tab.lastModifiedDate = attrs.fileModificationDate;
                    [self updateTabHeaderLayout];
                    [self updateWindowTitleAndStatus];
                }
            }
        }
    }
    else if (errorOut) *errorOut = NSStringFromStdString(err);
    return ok;
}

- (BOOL)gitCommitWithMessage:(NSString*)message errorOut:(NSString**)errorOut {
    if (self.openedFolderPath == nil) {
        if (errorOut) *errorOut = @"No open folder workspace.";
        return NO;
    }
    std::string ws = StdStringFromNSString(self.openedFolderPath);
    std::string msg = StdStringFromNSString(message);
    std::string err;
    BOOL ok = dietcode::filesystem::GitService::commit(ws, msg, err);
    if (ok) {
        [self refreshGitStatus];
    } else {
        if (errorOut) *errorOut = NSStringFromStdString(err);
    }
    return ok;
}

- (BOOL)writeFileAtPath:(NSString*)path content:(NSString*)content errorOut:(NSString**)errorOut {
    if (path.length == 0 || !content) {
        if (errorOut) *errorOut = @"Path and content are required.";
        return NO;
    }
    DietCodeTabState* openTab = nil;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            if (tab.isReadOnly) {
                if (errorOut) *errorOut = @"File is open read-only.";
                return NO;
            }
            openTab = tab;
            break;
        }
    }
    NSString* parent = [path stringByDeletingLastPathComponent];
    NSError* err = nil;
    if (parent.length > 0 &&
        ![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&err]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to create parent directory: %@", err.localizedDescription];
        return NO;
    }
    if (![content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Failed to write file: %@", err.localizedDescription];
        return NO;
    }
    if (openTab) {
        NSRange sel = openTab.textView.selectedRange;
        [openTab.textView setString:content];
        if (sel.location <= content.length) {
            openTab.textView.selectedRange = sel;
        }
        openTab.dirty = NO;
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        openTab.lastModifiedDate = attrs.fileModificationDate;
    }
    [self refreshFilesTree:nil];
    [self refreshGitStatus];
    [self updateTabHeaderLayout];
    [self updateWindowTitleAndStatus];
    return YES;
}

- (NSArray<NSDictionary*>*)problemsList {
    NSMutableArray* list = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.unifiedDiagnostics.count; i++) {
        NSDictionary* d = self.unifiedDiagnostics[i];
        NSString* relPath = d[@"path"];
        if (self.openedFolderPath && [relPath hasPrefix:self.openedFolderPath]) {
            relPath = [relPath substringFromIndex:self.openedFolderPath.length];
            if ([relPath hasPrefix:@"/"]) relPath = [relPath substringFromIndex:1];
        }
        NSString* source = d[@"source"] ?: @"unknown";
        NSNumber* line = d[@"line"] ?: @(1);
        NSNumber* column = d[@"column"] ?: @(1);
        NSString* message = d[@"message"] ?: @"";
        [list addObject:@{
            @"id": StableDiagnosticId(source, relPath, line, column, message),
            @"source": source,
            @"severity": d[@"severity"] ?: @"info",
            @"path": relPath,
            @"line": line,
            @"column": column,
            @"message": message
        }];
    }
    return list;
}

- (void)problemsOpen:(NSString*)problemId {
    for (NSDictionary* problem in [self problemsList]) {
        if ([problem[@"id"] isEqualToString:problemId]) {
            NSString* path = problem[@"path"];
            if (self.openedFolderPath && path.length > 0 && ![path isAbsolutePath]) {
                path = [self.openedFolderPath stringByAppendingPathComponent:path];
            }
            [self openFileAtPath:path line:[problem[@"line"] integerValue] column:[problem[@"column"] integerValue]];
            return;
        }
    }
}

- (void)problemsClearSource:(NSString*)source {
    for (NSString* filePath in [self.diagnosticsDict allKeys]) {
        NSMutableArray* list = self.diagnosticsDict[filePath];
        NSMutableArray* fileToRemove = [NSMutableArray array];
        for (NSDictionary* d in list) {
            if ([d[@"source"] isEqualToString:source]) {
                [fileToRemove addObject:d];
            }
        }
        [list removeObjectsInArray:fileToRemove];
    }
    [self rebuildProblemsPanel];
}

- (NSArray*)languageDiagnosticsForPath:(NSString*)path {
    NSMutableArray* list = [NSMutableArray array];
    NSArray* fileDiags = self.diagnosticsDict[path];
    for (NSDictionary* d in fileDiags) {
        if ([d[@"source"] isEqualToString:@"lsp"]) {
            [list addObject:d];
        }
    }
    return list;
}

- (void)formatFileAtPath:(NSString*)path {
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            [self formatTab:tab];
            break;
        }
    }
}

- (void)lintFileAtPath:(NSString*)path {
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            [self runLinterForTab:tab];
            break;
        }
    }
}

- (void)restartLSPForLanguage:(NSString*)lang {
    [self stopLSPForLanguage:lang];
    [self startLSPForLanguage:lang];
}

- (void)appendControlLogLine:(NSString*)line {
    if (self.isHeadless) {
        NSLog(@"%@", line);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextStorage* storage = self.controlLogTextView.textStorage;
        [storage beginEditing];
        [storage appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"] attributes:@{
            NSForegroundColorAttributeName: [NSColor textColor],
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
        }]];
        [storage endEditing];
        [self.controlLogTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    });
}

- (void)setControlActiveCommand:(NSString*)method caller:(NSString*)caller {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (method) {
            [self.controlActiveLabel setStringValue:[NSString stringWithFormat:@"Active Command: %@ (Caller: %@)", method, caller]];
        } else {
            [self.controlActiveLabel setStringValue:@"Active Command: Idle"];
        }
    });
}

- (void)showBottomPanelTab:(NSString*)identifier {
    self.bottomPanel.hidden = NO;
    [self.bottomTabView selectTabViewItemWithIdentifier:identifier];
}

- (void)updateControlStatusIndicator {
    if (self.externalControlEnabled) {
        [self.controlStatusLabel setStringValue:@"● Control: Active"];
        [self.controlStatusLabel setTextColor:[NSColor systemGreenColor]];
    } else {
        [self.controlStatusLabel setStringValue:@"● Control: Disabled"];
        [self.controlStatusLabel setTextColor:[NSColor disabledControlTextColor]];
    }
}

- (NSDictionary*)activeSelectionInfo {
    DietCodeTabState* tab = self.activeTab;
    if (!tab) return @{};
    NSRange r = tab.textView.selectedRange;
    NSString* text = @"";
    if (r.location + r.length <= tab.textView.string.length) {
        text = [tab.textView.string substringWithRange:r] ?: @"";
    }
    return @{
        @"text": text,
        @"start": @(r.location),
        @"end": @(r.location + r.length)
    };
}

- (BOOL)setActiveSelectionStart:(NSInteger)start end:(NSInteger)end {
    DietCodeTabState* tab = self.activeTab;
    if (!tab) return NO;
    if (start < 0 || end < start || end > (NSInteger)tab.textView.string.length) return NO;
    tab.textView.selectedRange = NSMakeRange(start, end - start);
    return YES;
}

- (BOOL)insertTextAtActiveCursor:(NSString*)text {
    DietCodeTabState* tab = self.activeTab;
    if (!tab || tab.isReadOnly) return NO;
    return [self replaceTextInRange:tab.textView.selectedRange withText:text forFileAtPath:tab.path];
}

- (BOOL)replaceActiveSelectionWithText:(NSString*)text {
    DietCodeTabState* tab = self.activeTab;
    if (!tab || tab.isReadOnly) return NO;
    return [self replaceTextInRange:tab.textView.selectedRange withText:text forFileAtPath:tab.path];
}

@end
