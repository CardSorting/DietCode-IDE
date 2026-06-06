#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Layout)

- (void)buildInterface {
    self.rootView = [[NSView alloc] init];
    self.window.contentView = self.rootView;

    self.horizontalSplit = [[NSSplitView alloc] init];
    [self.horizontalSplit setVertical:YES];
    [self.horizontalSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [self.horizontalSplit setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.rootView addSubview:self.horizontalSplit];

    [NSLayoutConstraint activateConstraints:@[
        [self.horizontalSplit.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [self.horizontalSplit.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [self.horizontalSplit.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [self.horizontalSplit.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor constant:-22]
    ]];

    // Activity Bar
    [self setupActivityBar];

    // Sidebar
    self.sidebarView = [[NSView alloc] init];
    [self.sidebarView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.sidebarView.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [self.horizontalSplit addSubview:self.sidebarView];

    self.sidebarInnerView = [[NSView alloc] init];
    [self.sidebarInnerView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.sidebarView addSubview:self.sidebarInnerView];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarInnerView.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor],
        [self.sidebarInnerView.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
        [self.sidebarInnerView.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
        [self.sidebarInnerView.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor]
    ]];

    // Main Content (Vertical Split: Editor / Bottom Panel)
    self.verticalSplit = [[NSSplitView alloc] init];
    [self.verticalSplit setVertical:NO];
    [self.verticalSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [self.verticalSplit setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.horizontalSplit addSubview:self.verticalSplit];

    // Editor Area
    self.editorHostView = [[NSView alloc] init];
    [self.editorHostView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.verticalSplit addSubview:self.editorHostView];

    // Bottom Panel
    self.bottomPanel = [[NSView alloc] init];
    [self.bottomPanel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.bottomPanel.heightAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
    [self.verticalSplit addSubview:self.bottomPanel];
    self.bottomPanel.hidden = YES;

    // Status Bar
    NSView* statusBar = [[NSView alloc] init];
    [statusBar setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.rootView addSubview:statusBar];
    [NSLayoutConstraint activateConstraints:@[
        [statusBar.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:22]
    ]];

    self.statusLabel = MakeLabel(@"Ready", 11, NSFontWeightRegular);
    [self.statusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [statusBar addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:10],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor]
    ]];

    [self prepareSidebarPanels];
    [self buildBottomTabViews];
    [self applyThemeColors];
}

- (void)setupActivityBar {
    self.activityBar = [[NSStackView alloc] init];
    [self.activityBar setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [self.activityBar setAlignment:NSLayoutAttributeCenterX];
    [self.activityBar setSpacing:10];
    [self.activityBar setEdgeInsets:NSEdgeInsetsMake(10, 0, 10, 0)];
    [self.activityBar setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.activityBar.widthAnchor constraintEqualToConstant:48].active = YES;
    [self.horizontalSplit addSubview:self.activityBar];

    auto addActivityBtn = [&](NSString* icon, NSString* activity, NSString* tooltip) {
        NSButton* btn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:icon accessibilityDescription:tooltip] target:self action:@selector(activityButtonClicked:)];
        [btn setIdentifier:activity];
        [btn setBezelStyle:NSBezelStyleRegularSquare];
        [btn setBordered:NO];
        [btn setToolTip:tooltip];
        [btn.widthAnchor constraintEqualToConstant:32].active = YES;
        [btn.heightAnchor constraintEqualToConstant:32].active = YES;
        [self.activityBar addArrangedSubview:btn];
        
        if ([activity isEqualToString:@"files"]) {
            self.lastSelectedActivityBtn = btn;
            [btn setEnabled:NO];
        }
    };

    addActivityBtn(@"doc.on.doc", @"files", @"Files (Cmd+Shift+E)");
    addActivityBtn(@"magnifyingglass", @"search", @"Search (Cmd+Shift+F)");
    addActivityBtn(@"sourcecontrol", @"git", @"Source Control (Cmd+Shift+G)");
    addActivityBtn(@"play.circle", @"run", @"Run and Debug (Cmd+Shift+D)");
    addActivityBtn(@"gearshape", @"settings", @"Settings (Cmd+,)");
}

- (void)activityButtonClicked:(NSButton*)sender {
    [self selectActivity:sender.identifier];
}

- (void)selectActivity:(NSString*)activity {
    if ([self.currentActivity isEqualToString:activity]) {
        BOOL hidden = [self.horizontalSplit isSubviewCollapsed:self.sidebarView];
        [self.horizontalSplit setPosition:hidden ? 250 : 0 ofDividerAtIndex:1];
        return;
    }
    
    self.currentActivity = activity;
    
    for (NSView* v in self.activityBar.arrangedSubviews) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* btn = (NSButton*)v;
            [btn setEnabled:![btn.identifier isEqualToString:activity]];
            if (![btn isEnabled]) self.lastSelectedActivityBtn = btn;
        }
    }
    
    [self.filesSidebarView setHidden:![activity isEqualToString:@"files"]];
    [self.searchSidebarView setHidden:![activity isEqualToString:@"search"]];
    [self.gitSidebarView setHidden:![activity isEqualToString:@"git"]];
    [self.runSidebarView setHidden:![activity isEqualToString:@"run"]];
    [self.settingsSidebarView setHidden:![activity isEqualToString:@"settings"]];
    
    [self.horizontalSplit setPosition:250 ofDividerAtIndex:1];
}

- (void)buildBottomTabViews {
    self.bottomTabView = [[NSTabView alloc] init];
    [self.bottomTabView setTabViewType:NSNoTabsNoBorder];
    [self.bottomTabView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.bottomPanel addSubview:self.bottomTabView];

    NSStackView* bottomHeader = [[NSStackView alloc] init];
    [bottomHeader setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [bottomHeader setAlignment:NSLayoutAttributeCenterY];
    [bottomHeader setSpacing:15];
    [bottomHeader setEdgeInsets:NSEdgeInsetsMake(0, 10, 0, 10)];
    [bottomHeader setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.bottomPanel addSubview:bottomHeader];

    [NSLayoutConstraint activateConstraints:@[
        [bottomHeader.topAnchor constraintEqualToAnchor:self.bottomPanel.topAnchor],
        [bottomHeader.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor],
        [bottomHeader.trailingAnchor constraintEqualToAnchor:self.bottomPanel.trailingAnchor],
        [bottomHeader.heightAnchor constraintEqualToConstant:30],
        [self.bottomTabView.topAnchor constraintEqualToAnchor:bottomHeader.bottomAnchor],
        [self.bottomTabView.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor],
        [self.bottomTabView.trailingAnchor constraintEqualToAnchor:self.bottomPanel.trailingAnchor],
        [self.bottomTabView.bottomAnchor constraintEqualToAnchor:self.bottomPanel.bottomAnchor]
    ]];

    auto addBottomTab = [&](NSString* title, NSString* identifier, NSView* contentView) {
        NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:identifier];
        [item setLabel:title];
        [item setView:contentView];
        [self.bottomTabView addTabViewItem:item];

        NSButton* btn = [NSButton buttonWithTitle:title target:self action:@selector(bottomTabClicked:)];
        [btn setIdentifier:identifier];
        [btn setBezelStyle:NSBezelStyleRecessed];
        [btn setControlSize:NSControlSizeSmall];
        [bottomHeader addArrangedSubview:btn];
    };

    // Terminal
    NSScrollView* termScroll = [[NSScrollView alloc] init];
    [termScroll setHasVerticalScroller:YES];
    [termScroll setDrawsBackground:NO];
    self.terminalTextView = [[DietCodeTerminalTextView alloc] init];
    [self.terminalTextView setEditable:YES];
    [self.terminalTextView setRichText:NO];
    [self.terminalTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [termScroll setDocumentView:self.terminalTextView];
    addBottomTab(@"Terminal", @"terminal", termScroll);

    // Output
    NSScrollView* outputScroll = [[NSScrollView alloc] init];
    [outputScroll setHasVerticalScroller:YES];
    [outputScroll setDrawsBackground:NO];
    self.outputTextView = [[NSTextView alloc] init];
    [self.outputTextView setEditable:NO];
    [self.outputTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [outputScroll setDocumentView:self.outputTextView];
    addBottomTab(@"Output", @"output", outputScroll);

    // Problems
    NSScrollView* errorScroll = [[NSScrollView alloc] init];
    [errorScroll setHasVerticalScroller:YES];
    [errorScroll setDrawsBackground:NO];
    self.errorsTextView = [[DietCodeNavigationTextView alloc] init];
    [self.errorsTextView setEditable:NO];
    [self.errorsTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    ((DietCodeNavigationTextView*)self.errorsTextView).navigationTarget = self;
    [errorScroll setDocumentView:self.errorsTextView];
    [self addPlaceholder:@"No problems detected in the workspace." toTextView:self.errorsTextView];
    addBottomTab(@"Problems", @"errors", errorScroll);

    // Search Results
    NSScrollView* searchResultsScroll = [[NSScrollView alloc] init];
    [searchResultsScroll setHasVerticalScroller:YES];
    [searchResultsScroll setDrawsBackground:NO];
    self.searchResultsTextView = [[DietCodeNavigationTextView alloc] init];
    [self.searchResultsTextView setEditable:NO];
    [self.searchResultsTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    ((DietCodeNavigationTextView*)self.searchResultsTextView).navigationTarget = self;
    [searchResultsScroll setDocumentView:self.searchResultsTextView];
    [self addPlaceholder:@"Search results will appear here." toTextView:self.searchResultsTextView];
    addBottomTab(@"Search Results", @"search_results", searchResultsScroll);

    // Close button
    NSButton* closeBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close Panel"] target:self action:@selector(toggleTerminal:)];
    [closeBtn setBezelStyle:NSBezelStyleInline];
    [closeBtn setBordered:NO];
    [bottomHeader addArrangedSubview:closeBtn];
}

- (void)bottomTabClicked:(NSButton*)sender {
    [self showBottomPanelTab:sender.identifier];
}

- (void)prepareSidebarPanels {
    self.filesSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    self.searchSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    self.gitSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    self.runSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    self.settingsSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    
    for (NSView* v in @[self.filesSidebarView, self.searchSidebarView, self.gitSidebarView, self.runSidebarView, self.settingsSidebarView]) {
        [v setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self.sidebarInnerView addSubview:v];
        [NSLayoutConstraint activateConstraints:@[
            [v.leadingAnchor constraintEqualToAnchor:self.sidebarInnerView.leadingAnchor],
            [v.trailingAnchor constraintEqualToAnchor:self.sidebarInnerView.trailingAnchor],
            [v.topAnchor constraintEqualToAnchor:self.sidebarInnerView.topAnchor],
            [v.bottomAnchor constraintEqualToAnchor:self.sidebarInnerView.bottomAnchor]
        ]];
        [v setHidden:YES];
    }
    
    [self setupFilesUI];
    [self setupSearchUI];
    [self setupGitUI];
    [self setupRunUI];
    [self setupSettingsUI];
    
    [self.filesSidebarView setHidden:NO];
    self.currentActivity = @"files";
}

- (void)applyThemeColors {
    BOOL isDark = [self isDarkTheme];
    NSColor* bgColor = isDark ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.98 alpha:1.0];
    NSColor* sidebarColor = isDark ? [NSColor colorWithCalibratedWhite:0.15 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
    NSColor* activityColor = isDark ? [NSColor colorWithCalibratedWhite:0.10 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];

    [self.rootView setWantsLayer:YES];
    self.rootView.layer.backgroundColor = bgColor.CGColor;

    [self.activityBar setWantsLayer:YES];
    self.activityBar.layer.backgroundColor = activityColor.CGColor;

    [self.sidebarView setWantsLayer:YES];
    self.sidebarView.layer.backgroundColor = sidebarColor.CGColor;

    [self.bottomPanel setWantsLayer:YES];
    self.bottomPanel.layer.backgroundColor = bgColor.CGColor;
}

- (BOOL)isDarkTheme {
    if (self.currentThemeIndex == 1) return NO;
    if (self.currentThemeIndex == 2) return YES;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [appearance isEqualToString:NSAppearanceNameDarkAqua];
    }
    return NO;
}

- (BOOL)isHighContrastTheme {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldIncreaseContrast];
}

- (void)updateFocusBorders {
}

- (void)addPlaceholder:(NSString*)placeholder toTextView:(NSTextView*)textView {
    if (textView.string.length == 0) {
        [textView setString:placeholder];
        [textView setTextColor:[NSColor placeholderTextColor]];
    }
}

- (void)updatePlaceholderVisibility:(NSTextView*)textView {
}

@end
