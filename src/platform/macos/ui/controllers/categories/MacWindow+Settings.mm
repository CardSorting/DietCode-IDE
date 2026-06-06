#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Settings)

- (void)setupSettingsUI {
    NSScrollView* setScroll = [[NSScrollView alloc] initWithFrame:self.settingsSidebarView.bounds];
    [setScroll setHasVerticalScroller:YES];
    [setScroll setHasHorizontalScroller:NO];
    [setScroll setBorderType:NSNoBorder];
    [setScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.settingsSidebarView addSubview:setScroll];

    NSStackView* setStack = [[NSStackView alloc] init];
    [setStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [setStack setSpacing:12];
    [setStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [setStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [setScroll setDocumentView:setStack];

    [NSLayoutConstraint activateConstraints:@[
        [setStack.leadingAnchor constraintEqualToAnchor:setScroll.leadingAnchor],
        [setStack.trailingAnchor constraintEqualToAnchor:setScroll.trailingAnchor],
        [setStack.topAnchor constraintEqualToAnchor:setScroll.topAnchor]
    ]];

    [setStack addArrangedSubview:MakeLabel(@"IDE PREFERENCES", 13, NSFontWeightBold)];

    // Font Size
    [setStack addArrangedSubview:MakeLabel(@"Font Size (10-24):", 12, NSFontWeightRegular)];
    self.fontSizeField = [[NSTextField alloc] init];
    [self.fontSizeField setStringValue:[NSString stringWithFormat:@"%ld", (long)self.currentFontSize]];
    [self.fontSizeField setTarget:self];
    [self.fontSizeField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.fontSizeField];

    // Word Wrap
    self.wordWrapBtn = [NSButton buttonWithTitle:@"Enable Word Wrap" target:self action:@selector(settingsChanged:)];
    [self.wordWrapBtn setButtonType:NSButtonTypeSwitch];
    [self.wordWrapBtn setState:(self.currentWordWrap ? NSControlStateValueOn : NSControlStateValueOff)];
    [setStack addArrangedSubview:self.wordWrapBtn];

    // Theme Picker
    [setStack addArrangedSubview:MakeLabel(@"Color Theme:", 12, NSFontWeightRegular)];
    self.themePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 150, 24) pullsDown:NO];
    [self.themePopUp addItemsWithTitles:@[@"System", @"Light", @"Dark", @"High Contrast Light", @"High Contrast Dark"]];
    [self.themePopUp selectItemAtIndex:self.currentThemeIndex];
    [self.themePopUp setTarget:self];
    [self.themePopUp setAction:@selector(themeChanged:)];
    [setStack addArrangedSubview:self.themePopUp];
    
    // Auto Save
    self.autoSaveBtn = [NSButton buttonWithTitle:@"Enable Auto Save" target:self action:@selector(settingsChanged:)];
    [self.autoSaveBtn setButtonType:NSButtonTypeSwitch];
    [self.autoSaveBtn setState:(self.currentAutoSave ? NSControlStateValueOn : NSControlStateValueOff)];
    [setStack addArrangedSubview:self.autoSaveBtn];

    [setStack addArrangedSubview:MakeLabel(@"LANGUAGE FEATURES", 13, NSFontWeightBold)];

    // Format on Save
    self.formatOnSaveBtn = [NSButton buttonWithTitle:@"Format on Save" target:self action:@selector(settingsChanged:)];
    [self.formatOnSaveBtn setButtonType:NSButtonTypeSwitch];
    [self.formatOnSaveBtn setState:(self.currentFormatOnSave ? NSControlStateValueOn : NSControlStateValueOff)];
    [setStack addArrangedSubview:self.formatOnSaveBtn];

    // Lint on Save
    self.lintOnSaveBtn = [NSButton buttonWithTitle:@"Lint on Save" target:self action:@selector(settingsChanged:)];
    [self.lintOnSaveBtn setButtonType:NSButtonTypeSwitch];
    [self.lintOnSaveBtn setState:(self.currentLintOnSave ? NSControlStateValueOn : NSControlStateValueOff)];
    [setStack addArrangedSubview:self.lintOnSaveBtn];

    // Diagnostics Enabled
    self.diagnosticsBtn = [NSButton buttonWithTitle:@"Enable Diagnostics" target:self action:@selector(settingsChanged:)];
    [self.diagnosticsBtn setButtonType:NSButtonTypeSwitch];
    [self.diagnosticsBtn setState:(self.currentDiagnosticsEnabled ? NSControlStateValueOn : NSControlStateValueOff)];
    [setStack addArrangedSubview:self.diagnosticsBtn];

    [setStack addArrangedSubview:MakeLabel(@"LSP BINARY PATHS", 13, NSFontWeightBold)];

    // Clangd Path
    [setStack addArrangedSubview:MakeLabel(@"C++ clangd path:", 11, NSFontWeightRegular)];
    self.clangdPathField = [[NSTextField alloc] init];
    [self.clangdPathField setStringValue:self.clangdPath ?: @""];
    [self.clangdPathField setTarget:self];
    [self.clangdPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.clangdPathField];

    // Pyright Path
    [setStack addArrangedSubview:MakeLabel(@"Python pyright path:", 11, NSFontWeightRegular)];
    self.pyrightPathField = [[NSTextField alloc] init];
    [self.pyrightPathField setStringValue:self.pyrightPath ?: @""];
    [self.pyrightPathField setTarget:self];
    [self.pyrightPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.pyrightPathField];

    // TS Server Path
    [setStack addArrangedSubview:MakeLabel(@"TS typescript-language-server path:", 11, NSFontWeightRegular)];
    self.tsserverPathField = [[NSTextField alloc] init];
    [self.tsserverPathField setStringValue:self.tsserverPath ?: @""];
    [self.tsserverPathField setTarget:self];
    [self.tsserverPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.tsserverPathField];

    [setStack addArrangedSubview:MakeLabel(@"FORMATTERS", 13, NSFontWeightBold)];

    // ClangFormat Path
    [setStack addArrangedSubview:MakeLabel(@"C++ clang-format path:", 11, NSFontWeightRegular)];
    self.clangFormatPathField = [[NSTextField alloc] init];
    [self.clangFormatPathField setStringValue:self.clangFormatPath ?: @""];
    [self.clangFormatPathField setTarget:self];
    [self.clangFormatPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.clangFormatPathField];

    // Black Path
    [setStack addArrangedSubview:MakeLabel(@"Python black path:", 11, NSFontWeightRegular)];
    self.blackPathField = [[NSTextField alloc] init];
    [self.blackPathField setStringValue:self.blackPath ?: @""];
    [self.blackPathField setTarget:self];
    [self.blackPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.blackPathField];

    // Prettier Path
    [setStack addArrangedSubview:MakeLabel(@"Prettier path:", 11, NSFontWeightRegular)];
    self.prettierPathField = [[NSTextField alloc] init];
    [self.prettierPathField setStringValue:self.prettierPath ?: @""];
    [self.prettierPathField setTarget:self];
    [self.prettierPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.prettierPathField];

    [setStack addArrangedSubview:MakeLabel(@"LINTERS", 13, NSFontWeightBold)];

    // ClangTidy Path
    [setStack addArrangedSubview:MakeLabel(@"C++ clang-tidy path:", 11, NSFontWeightRegular)];
    self.clangTidyPathField = [[NSTextField alloc] init];
    [self.clangTidyPathField setStringValue:self.clangTidyPath ?: @""];
    [self.clangTidyPathField setTarget:self];
    [self.clangTidyPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.clangTidyPathField];

    // Ruff Path
    [setStack addArrangedSubview:MakeLabel(@"Python ruff path:", 11, NSFontWeightRegular)];
    self.ruffPathField = [[NSTextField alloc] init];
    [self.ruffPathField setStringValue:self.ruffPath ?: @""];
    [self.ruffPathField setTarget:self];
    [self.ruffPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.ruffPathField];

    // Eslint Path
    [setStack addArrangedSubview:MakeLabel(@"ESLint path:", 11, NSFontWeightRegular)];
    self.eslintPathField = [[NSTextField alloc] init];
    [self.eslintPathField setStringValue:self.eslintPath ?: @""];
    [self.eslintPathField setTarget:self];
    [self.eslintPathField setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.eslintPathField];

    [setStack addArrangedSubview:MakeLabel(@"EXTERNAL CONTROL", 13, NSFontWeightBold)];
    self.externalControlBtn = [NSButton buttonWithTitle:@"Enable External Control" target:self action:@selector(settingsChanged:)];
    [self.externalControlBtn setButtonType:NSButtonTypeSwitch];
    [self.externalControlBtn setState:(self.externalControlEnabled ? NSControlStateValueOn : NSControlStateValueOff)];
    [self.externalControlBtn setAccessibilityLabel:@"Enable external control agent socket"];
    [setStack addArrangedSubview:self.externalControlBtn];
    
    [setStack addArrangedSubview:MakeLabel(@"Agent Autonomy Level:", 11, NSFontWeightRegular)];
    self.agentAutonomyBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    [self.agentAutonomyBtn addItemsWithTitles:@[@"Prompt on Destructive", @"Permissionless (Full)", @"Bounded Autonomy"]];
    [self.agentAutonomyBtn selectItemAtIndex:self.agentAutonomyLevel];
    [self.agentAutonomyBtn setTarget:self];
    [self.agentAutonomyBtn setAction:@selector(settingsChanged:)];
    [setStack addArrangedSubview:self.agentAutonomyBtn];
}

- (void)openSettingsAction:(id)sender {
    [self selectActivity:@"settings"];
}

- (void)settingsChanged:(id)sender {
    NSInteger newSize = [self.fontSizeField integerValue];
    if (newSize >= 10 && newSize <= 24) {
        self.currentFontSize = newSize;
    }
    
    self.currentWordWrap = ([self.wordWrapBtn state] == NSControlStateValueOn);
    self.currentAutoSave = ([self.autoSaveBtn state] == NSControlStateValueOn);
    
    self.currentFormatOnSave = ([self.formatOnSaveBtn state] == NSControlStateValueOn);
    self.currentLintOnSave = ([self.lintOnSaveBtn state] == NSControlStateValueOn);
    self.currentDiagnosticsEnabled = ([self.diagnosticsBtn state] == NSControlStateValueOn);
    
    self.clangdPath = self.clangdPathField.stringValue;
    self.pyrightPath = self.pyrightPathField.stringValue;
    self.tsserverPath = self.tsserverPathField.stringValue;
    
    self.clangFormatPath = self.clangFormatPathField.stringValue;
    self.blackPath = self.blackPathField.stringValue;
    self.prettierPath = self.prettierPathField.stringValue;
    
    self.clangTidyPath = self.clangTidyPathField.stringValue;
    self.ruffPath = self.ruffPathField.stringValue;
    self.eslintPath = self.eslintPathField.stringValue;
    
    BOOL newControlVal = ([self.externalControlBtn state] == NSControlStateValueOn);
    if (newControlVal != self.externalControlEnabled) {
        self.externalControlEnabled = newControlVal;
        // Logic to start/stop control server
        [self updateControlStatusIndicator];
    }
    
    self.agentAutonomyLevel = [self.agentAutonomyBtn indexOfSelectedItem];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentFontSize forKey:@"FontSize"];
    [defaults setBool:self.currentWordWrap forKey:@"WordWrap"];
    [defaults setBool:self.currentAutoSave forKey:@"AutoSave"];
    
    [defaults setBool:self.currentFormatOnSave forKey:@"FormatOnSave"];
    [defaults setBool:self.currentLintOnSave forKey:@"LintOnSave"];
    [defaults setBool:self.currentDiagnosticsEnabled forKey:@"DiagnosticsEnabled"];
    [defaults setBool:self.externalControlEnabled forKey:@"ExternalControlEnabled"];
    [defaults setInteger:self.agentAutonomyLevel forKey:@"AgentAutonomyLevel"];
    
    [defaults setObject:self.clangdPath forKey:@"ClangdPath"];
    [defaults setObject:self.pyrightPath forKey:@"PyrightPath"];
    [defaults setObject:self.tsserverPath forKey:@"TsserverPath"];
    
    [defaults setObject:self.clangFormatPath forKey:@"ClangFormatPath"];
    [defaults setObject:self.blackPath forKey:@"BlackPath"];
    [defaults setObject:self.prettierPath forKey:@"PrettierPath"];
    
    [defaults setObject:self.clangTidyPath forKey:@"ClangTidyPath"];
    [defaults setObject:self.ruffPath forKey:@"RuffPath"];
    [defaults setObject:self.eslintPath forKey:@"EslintPath"];
    
    [defaults synchronize];
    
    for (DietCodeTabState* tab in self.openTabs) {
        [tab.textView setFont:[NSFont monospacedSystemFontOfSize:self.currentFontSize weight:NSFontWeightRegular]];
        [tab.textView.textContainer setWidthTracksTextView:tab.isLargeFile ? NO : self.currentWordWrap];
        [self updateDiagnosticsHighlightsForTab:tab];
    }
    
    [self rebuildProblemsPanel];
}

- (void)themeChanged:(NSPopUpButton*)sender {
    self.currentThemeIndex = [sender indexOfSelectedItem];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentThemeIndex forKey:@"ThemeIndex"];
    [defaults synchronize];
    
    [self applyThemeColors];
}

@end
