#import "MacWindow.hpp"
#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#import "MacControlServer.hpp"

#include <util.h>
#include <unistd.h>

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.openTabs = [NSMutableArray array];
        self.directoryCache = [NSMutableDictionary dictionary];
        self.diagnosticsDict = [NSMutableDictionary dictionary];
        self.unifiedDiagnostics = [NSMutableArray array];
        self.sessionLastSearches = [NSMutableArray array];
        self.sessionRecentCommands = [NSMutableArray array];
        self.controlServer = [[DietCodeControlServer alloc] initWithWindowController:self]; // legacy bridge + shared workspace session
        
        self.currentFontSize = 13;
        self.currentWordWrap = YES;
        self.currentAutoSave = NO;
        self.currentThemeIndex = 0;
        
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:@"FontSize"]) self.currentFontSize = [defaults integerForKey:@"FontSize"];
        if ([defaults objectForKey:@"WordWrap"]) self.currentWordWrap = [defaults boolForKey:@"WordWrap"];
        if ([defaults objectForKey:@"AutoSave"]) self.currentAutoSave = [defaults boolForKey:@"AutoSave"];
        if ([defaults objectForKey:@"ThemeIndex"]) self.currentThemeIndex = [defaults integerForKey:@"ThemeIndex"];
        
        self.clangdPath = [defaults stringForKey:@"ClangdPath"] ?: @"";
        self.pyrightPath = [defaults stringForKey:@"PyrightPath"] ?: @"";
        self.tsserverPath = [defaults stringForKey:@"TsserverPath"] ?: @"";
        self.clangFormatPath = [defaults stringForKey:@"ClangFormatPath"] ?: @"";
        self.blackPath = [defaults stringForKey:@"BlackPath"] ?: @"";
        self.prettierPath = [defaults stringForKey:@"PrettierPath"] ?: @"";
        self.clangTidyPath = [defaults stringForKey:@"ClangTidyPath"] ?: @"";
        self.ruffPath = [defaults stringForKey:@"RuffPath"] ?: @"";
        self.eslintPath = [defaults stringForKey:@"EslintPath"] ?: @"";
        self.externalControlEnabled = [defaults boolForKey:@"ExternalControlEnabled"];
        self.agentAutonomyLevel = [defaults integerForKey:@"AgentAutonomyLevel"];

        terminalPid_ = -1;
        terminalMasterFd_ = -1;
        [self.controlServer start];
    }
    return self;
}

- (void)loadWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"DietCode";
    self.window.delegate = self;
    self.window.minSize = NSMakeSize(800, 600);
    [self.window center];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self buildInterface];
    [self setupCommandPalette];
    [self updateWindowTitleAndStatus];
    [self restoreOpenTabs];
    
    if (self.openTabs.count == 0) {
        [self showWelcome:nil];
    }
    
    [self checkForRecoverableFiles];
}

- (void)dealloc {
    [self cleanupProcesses];
}

- (void)cleanupProcesses {
    if (self.currentRunTask && [self.currentRunTask isRunning]) {
        [self.currentRunTask terminate];
    }
    if (terminalPid_ > 0) {
        kill(terminalPid_, SIGHUP);
    }
    if (terminalMasterFd_ > 0) {
        close(terminalMasterFd_);
        terminalMasterFd_ = -1;
    }
    if (cppLspClient_) { cppLspClient_->stop(); delete cppLspClient_; }
    if (pythonLspClient_) { pythonLspClient_->stop(); delete pythonLspClient_; }
    if (tsLspClient_) { tsLspClient_->stop(); delete tsLspClient_; }
}

- (void)showWelcome:(id)sender {
    if (sender != nil && ![self confirmCloseIfNeeded]) return;

    self.hasDocument = NO;
    self.activeTab = nil;
    self.textView = nil;
    [self updateWindowTitleAndStatus];
    
    for (NSView* v in [self.editorHostView subviews]) {
        [v removeFromSuperview];
    }
    self.editorHostView.hidden = NO;

    NSStackView* welcome = [[NSStackView alloc] init];
    [welcome setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [welcome setAlignment:NSLayoutAttributeLeading];
    [welcome setSpacing:16];
    [welcome setEdgeInsets:NSEdgeInsetsMake(48, 56, 48, 56)];
    [welcome setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.editorHostView addSubview:welcome];

    [NSLayoutConstraint activateConstraints:@[
        [welcome.leadingAnchor constraintEqualToAnchor:self.editorHostView.leadingAnchor],
        [welcome.trailingAnchor constraintEqualToAnchor:self.editorHostView.trailingAnchor],
        [welcome.topAnchor constraintEqualToAnchor:self.editorHostView.topAnchor]
    ]];

    [welcome addArrangedSubview:MakeLabel(@"Welcome to DietCode", 34, NSFontWeightBold)];
    NSTextField* subtitle = MakeLabel(@"A quiet place to write and run code. Nothing runs unless you ask.", 17, NSFontWeightRegular);
    [subtitle setTextColor:[NSColor secondaryLabelColor]];
    [welcome addArrangedSubview:subtitle];

    NSStackView* actions = [[NSStackView alloc] init];
    [actions setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [actions setAlignment:NSLayoutAttributeLeading];
    [actions setSpacing:12];
    [welcome addArrangedSubview:actions];

    [actions addArrangedSubview:MakeButton(@"Open Folder...", self, @selector(openFolder:))];
    [actions addArrangedSubview:MakeButton(@"Open File...", self, @selector(openFile:))];
    [actions addArrangedSubview:MakeButton(@"New File", self, @selector(newFile:))];
}

- (void)toggleSidebar:(id)sender {
    BOOL collapsed = [self.horizontalSplit isSubviewCollapsed:self.sidebarView];
    if (collapsed) {
        [self.sidebarView setHidden:NO];
        [self.horizontalSplit setPosition:250 ofDividerAtIndex:1];
    } else {
        [self.sidebarView setHidden:YES];
    }
}

- (void)toggleTerminal:(id)sender {
    BOOL collapsed = [self.verticalSplit isSubviewCollapsed:self.bottomPanel];
    if (collapsed) {
        [self.bottomPanel setHidden:NO];
        [self.verticalSplit setPosition:self.verticalSplit.bounds.size.height - 200 ofDividerAtIndex:0];
        [self showBottomPanelTab:@"terminal"];
        [self ensureTerminalProcess];
    } else {
        [self.bottomPanel setHidden:YES];
    }
}

- (void)goToLine:(id)sender {
    if (self.isHeadless) return;
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Go to Line"];
    [alert setInformativeText:@"Enter target line number:"];
    [alert addButtonWithTitle:@"Jump"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    [alert setAccessoryView:input];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger line = [input integerValue];
        if (line > 0 && self.textView) [self jumpToLine:line];
    }
}

@end

@implementation DietCodeWindowController (Core)

- (void)jumpToLine:(NSInteger)lineNumber {
    [self jumpToLine:lineNumber column:1];
}

- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)colNumber {
    NSString* content = [self.textView string];
    NSUInteger currentLine = 1;
    NSUInteger index = 0;
    NSUInteger targetIndex = NSNotFound;
    
    if (lineNumber <= 1) {
        targetIndex = 0;
    } else {
        while (index < [content length]) {
            if ([content characterAtIndex:index] == '\n') {
                currentLine++;
                if (currentLine == (NSUInteger)lineNumber) {
                    targetIndex = index + 1;
                    break;
                }
            }
            index++;
        }
    }
    
    if (targetIndex != NSNotFound) {
        NSUInteger finalIndex = targetIndex + (colNumber > 0 ? (colNumber - 1) : 0);
        if (finalIndex > content.length) finalIndex = content.length;
        
        NSRange lineRange = [content lineRangeForRange:NSMakeRange(targetIndex, 0)];
        [self.textView setSelectedRange:NSMakeRange(finalIndex, 0)];
        [self.textView scrollRangeToVisible:lineRange];
        [[self window] makeFirstResponder:self.textView];
    }
    
    if (self.activeTab.path) {
        [self notifyAgentEvent:@"DocumentOpened" detail:self.activeTab.path];
    }
}

- (void)updateWindowTitleAndStatus {
    NSString* displayName = self.activeTab == nil ? @"No active document" : self.activeTab.title;
    NSString* dirtyPrefix = [self hasUnsavedChanges] ? @"● " : @"";
    NSString* title = self.activeTab != nil ? [NSString stringWithFormat:@"%@%@ — DietCode", dirtyPrefix, displayName] : @"DietCode";
    [[self window] setTitle:title];

    NSString* savedState = (self.activeTab && self.activeTab.dirty) ? @"Unsaved" : @"Saved";
    NSString* cursorText = @"Line 1, Column 1";
    
    if (self.textView) {
        NSRange selected = [self.textView selectedRange];
        NSString* content = [self.textView string] ?: @"";
        NSUInteger line = 1, col = 1, idx = 0;
        while (idx < selected.location && idx < content.length) {
            if ([content characterAtIndex:idx] == '\n') { line++; col = 1; }
            else col++;
            idx++;
        }
        cursorText = [NSString stringWithFormat:@"Line %lu, Column %lu", (unsigned long)line, (unsigned long)col];
    }

    [self.statusLabel setStringValue:[NSString stringWithFormat:@"%@ • %@ • %@", displayName, savedState, cursorText]];
}

- (void)showErrorWithTitle:(NSString*)title
              whatHappened:(NSString*)whatHappened
                  nextStep:(NSString*)nextStep
                    safety:(NSString*)safety
                   details:(NSString*)details {
    if (self.isHeadless) {
        NSLog(@"[Error] %@: %@", title, details ?: whatHappened);
        return;
    }
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@\n\n%@", whatHappened, nextStep, safety]];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert runModal];
}

- (void)showErrorWithTitle:(NSString*)title message:(NSString*)message {
    [self showErrorAlert:title message:message];
}

@end
