#include "MacWindow.hpp"

#include "../../filesystem/FileService.hpp"
#include "MacFileDialog.hpp"
#include "../../search/FindInFile.hpp"

#import <Cocoa/Cocoa.h>

#include <util.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <thread>
#include <mutex>
#include <vector>
#include <string>
#include <filesystem>
#include <optional>
#include <algorithm>
#include <fstream>
#include <unordered_map>

// Extern environment for shell exec
extern char** environ;

// --- Line Number Ruler View Interface ---
@interface DietCodeLineNumberRulerView : NSRulerView
- (instancetype)initWithScrollView:(NSScrollView*)scrollView;
@end

@implementation DietCodeLineNumberRulerView

- (instancetype)initWithScrollView:(NSScrollView*)scrollView {
    self = [super initWithScrollView:scrollView orientation:NSVerticalRuler];
    if (self) {
        self.clientView = scrollView.documentView;
        self.ruleThickness = 45.0;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rulerNeedsDisplay:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:scrollView.contentView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rulerNeedsDisplay:)
                                                     name:NSTextDidChangeNotification
                                                   object:scrollView.documentView];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rulerNeedsDisplay:(NSNotification*)notification {
    [self setNeedsDisplay:YES];
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView* textView = (NSTextView*)self.clientView;
    if (![textView isKindOfClass:[NSTextView class]]) {
        return;
    }
    
    NSLayoutManager* layoutManager = textView.layoutManager;
    NSTextContainer* textContainer = textView.textContainer;
    NSString* content = textView.string;
    
    BOOL isDark = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        isDark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    }
    
    if (isDark) {
        [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] set];
    }
    NSRectFill(self.bounds);
    
    NSRect visibleRect = [self.scrollView.contentView bounds];
    NSPoint containerOrigin = textView.textContainerOrigin;
    NSRect textRect = NSOffsetRect(visibleRect, -containerOrigin.x, -containerOrigin.y);
    
    NSRange glyphRange = [layoutManager glyphRangeForBoundingRect:textRect inTextContainer:textContainer];
    NSRange charRange = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    
    if (charRange.length == 0 && content.length > 0) {
        return;
    }
    
    NSUInteger lineNumber = 1;
    for (NSUInteger i = 0; i < charRange.location && i < content.length; i++) {
        if ([content characterAtIndex:i] == '\n') {
            lineNumber++;
        }
    }
    
    NSDictionary* attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: isDark ? [NSColor colorWithCalibratedWhite:0.5 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.4 alpha:1.0]
    };
    
    NSUInteger index = charRange.location;
    while (index < NSMaxRange(charRange)) {
        NSRange lineRange = [content lineRangeForRange:NSMakeRange(index, 0)];
        NSRange glyphLineRange = [layoutManager glyphRangeForCharacterRange:lineRange actualCharacterRange:NULL];
        
        NSUInteger rectCount = 0;
        NSRectArray rects = [layoutManager rectArrayForGlyphRange:glyphLineRange
                                          withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
                                                   inTextContainer:textContainer
                                                         rectCount:&rectCount];
        
        if (rectCount > 0) {
            CGFloat y = rects[0].origin.y + containerOrigin.y - visibleRect.origin.y;
            NSString* numStr = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
            NSSize size = [numStr sizeWithAttributes:attrs];
            NSRect textFrame = NSMakeRect(self.ruleThickness - size.width - 8, y + 2, size.width, size.height);
            [numStr drawInRect:textFrame withAttributes:attrs];
        }
        
        lineNumber++;
        index = NSMaxRange(lineRange);
    }
    
    if (NSMaxRange(charRange) == content.length && content.length > 0 && [content characterAtIndex:content.length - 1] == '\n') {
        NSRange endRange = NSMakeRange(content.length, 0);
        NSRange glyphEndRange = [layoutManager glyphRangeForCharacterRange:endRange actualCharacterRange:NULL];
        NSRect lineRect = [layoutManager lineFragmentUsedRectForGlyphAtIndex:glyphEndRange.location effectiveRange:NULL];
        CGFloat y = lineRect.origin.y + containerOrigin.y - visibleRect.origin.y;
        NSString* numStr = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize size = [numStr sizeWithAttributes:attrs];
        NSRect textFrame = NSMakeRect(self.ruleThickness - size.width - 8, y + 2, size.width, size.height);
        [numStr drawInRect:textFrame withAttributes:attrs];
    }
}

@end


// --- Outline View with Return key navigation support ---
@interface DietCodeOutlineView : NSOutlineView
@end

@implementation DietCodeOutlineView
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 36) { // Return key
        NSInteger row = [self selectedRow];
        if (row >= 0) {
            id target = [self target];
            SEL action = [self doubleAction];
            if (target && action && [target respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [target performSelector:action withObject:self];
#pragma clang diagnostic pop
                return;
            }
        }
    }
    [super keyDown:event];
}
@end


// --- Tab State Helper Class ---
@interface DietCodeTabState : NSObject
@property (nonatomic, copy) NSString* path;
@property (nonatomic, copy) NSString* title;
@property (nonatomic, strong) NSScrollView* scrollView;
@property (nonatomic, strong) NSTextView* textView;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, strong) NSView* tabButtonView;
@property (nonatomic, strong) NSDate* lastModifiedDate;
@end

@implementation DietCodeTabState
@end


// --- Terminal Text View ---
@interface DietCodeTerminalTextView : NSTextView
@property (nonatomic, assign) int masterFd;
@end

@implementation DietCodeTerminalTextView

- (void)keyDown:(NSEvent*)event {
    NSString* chars = event.characters;
    if (chars.length > 0 && self.masterFd >= 0) {
        const char* utf8 = [chars UTF8String];
        write(self.masterFd, utf8, strlen(utf8));
    }
}

- (void)insertText:(id)insertString replacementRange:(NSRange)replacementRange {
    if ([insertString isKindOfClass:[NSString class]] && self.masterFd >= 0) {
        const char* utf8 = [insertString UTF8String];
        write(self.masterFd, utf8, strlen(utf8));
    }
}

@end


// --- Command Palette Borderless HUD Panel ---
@interface DietCodeCommandPalettePanel : NSPanel
@end

@implementation DietCodeCommandPalettePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end


// --- Main Window Controller Implementation ---
@interface DietCodeWindowController ()
@property(nonatomic, strong) NSView* rootView;
@property(nonatomic, strong) NSStackView* activityBar;
@property(nonatomic, strong) NSView* sidebarView;
@property(nonatomic, strong) NSView* sidebarInnerView;
@property(nonatomic, strong) NSView* editorHostView;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, assign) BOOL hasDocument;
@property(nonatomic, assign) BOOL loadingDocument;
@property(nonatomic, strong) NSTextView* textView;

// Split Views
@property(nonatomic, strong) NSSplitView* horizontalSplit;
@property(nonatomic, strong) NSSplitView* verticalSplit;

// Navigation & Sidebar panels
@property(nonatomic, strong) NSView* filesSidebarView;
@property(nonatomic, strong) NSView* searchSidebarView;
@property(nonatomic, strong) NSView* runSidebarView;
@property(nonatomic, strong) NSView* errorsSidebarView;
@property(nonatomic, strong) NSView* settingsSidebarView;
@property(nonatomic, copy) NSString* currentActivity;
@property(nonatomic, strong) NSButton* lastSelectedActivityBtn;

// File Tree & Outline View
@property(nonatomic, strong) DietCodeOutlineView* fileTreeView;
@property(nonatomic, strong) NSView* fileTreeEmptyStateView;
@property(nonatomic, copy) NSString* openedFolderPath;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSArray<NSString*>*>* directoryCache;

// Tabbed Editor State
@property(nonatomic, strong) NSMutableArray<DietCodeTabState*>* openTabs;
@property(nonatomic, strong) DietCodeTabState* activeTab;
@property(nonatomic, strong) NSTabView* editorTabView;
@property(nonatomic, strong) NSScrollView* tabHeaderScrollView;
@property(nonatomic, strong) NSStackView* tabHeaderStack;

// Bottom Panel
@property(nonatomic, strong) NSTabView* bottomTabView;
@property(nonatomic, strong) DietCodeTerminalTextView* terminalTextView;
@property(nonatomic, strong) NSTextView* outputTextView;
@property(nonatomic, strong) NSTextView* errorsTextView;
@property(nonatomic, strong) NSTextView* searchResultsTextView;
@property(nonatomic, strong) NSView* bottomPanel;

// Command Palette Popup
@property(nonatomic, strong) DietCodeCommandPalettePanel* commandPalettePanel;
@property(nonatomic, strong) NSTextField* paletteSearchField;
@property(nonatomic, strong) NSTableView* paletteTableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* commandPaletteActions;
@property(nonatomic, strong) NSArray<NSDictionary*>* filteredCommandPaletteActions;

// Run Process
@property(nonatomic, strong) NSTask* currentRunTask;
@property(nonatomic, strong) NSTextField* runStatusLabel;
@property(nonatomic, strong) NSTextField* runExplanationLabel;

// Search Flags
@property(nonatomic, assign) BOOL searchCancelled;

// Preferences Settings variables
@property(nonatomic, strong) NSTextField* fontSizeField;
@property(nonatomic, strong) NSButton* wordWrapBtn;
@property(nonatomic, strong) NSButton* autoSaveBtn;
@property(nonatomic, strong) NSPopUpButton* themePopUp;
@property(nonatomic, assign) NSInteger currentFontSize;
@property(nonatomic, assign) BOOL currentWordWrap;
@property(nonatomic, assign) BOOL currentAutoSave;
@property(nonatomic, assign) NSInteger currentThemeIndex; // 0: System, 1: Light, 2: Dark

@end

namespace {

NSString* NSStringFromStdString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string StdStringFromNSString(NSString* value) {
    if (value == nil) {
        return {};
    }
    return std::string([value UTF8String]);
}

NSTextField* MakeLabel(NSString* text, CGFloat fontSize, NSFontWeight weight) {
    NSTextField* label = [NSTextField labelWithString:text];
    [label setFont:[NSFont systemFontOfSize:fontSize weight:weight]];
    [label setLineBreakMode:NSLineBreakByWordWrapping];
    [label setMaximumNumberOfLines:0];
    return label;
}

NSButton* MakeButton(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    [button setBezelStyle:NSBezelStyleRounded];
    [button setControlSize:NSControlSizeLarge];
    return button;
}

bool isPathExcluded(const std::filesystem::path& path) {
    std::string name = path.filename().string();
    if (name == "node_modules" || name == ".git" || name == "dist" ||
        name == "build" || name == ".next" || name == "vendor" ||
        name == "__pycache__") {
        return true;
    }
    for (const auto& part : path) {
        std::string partStr = part.string();
        if (partStr == "node_modules" || partStr == ".git" || partStr == "dist" ||
            partStr == "build" || partStr == ".next" || partStr == "vendor" ||
            partStr == "__pycache__") {
            return true;
        }
    }
    return false;
}

} // namespace

@implementation DietCodeWindowController {
    dietcode::filesystem::FileService fileService_;
    dietcode::platform::macos::MacFileDialog fileDialog_;
    int terminalMasterFd_;
    pid_t terminalPid_;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1150, 780);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    [window setTitle:@"DietCode"];
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        [window setDelegate:self];
        _openTabs = [NSMutableArray array];
        _directoryCache = [NSMutableDictionary dictionary];
        terminalMasterFd_ = -1;
        terminalPid_ = -1;
        
        // Load Settings from NSUserDefaults
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        _currentFontSize = [defaults integerForKey:@"FontSize"] ?: 14;
        _currentWordWrap = [defaults boolForKey:@"WordWrap"];
        _currentAutoSave = [defaults boolForKey:@"AutoSave"];
        _currentThemeIndex = [defaults integerForKey:@"ThemeIndex"];
        
        [self buildInterface];
        [self showWelcome:nil];
        [self selectActivity:@"files"];
        [self updateWindowTitleAndStatus];
        [self setupTerminalProcess];
        [self setupCommandPalette];
        [self checkForRecoverableFiles];
        if (self.openTabs.count == 0) {
            [self restoreOpenTabs];
        }
    }
    return self;
}

- (void)buildInterface {
    self.rootView = [[NSView alloc] initWithFrame:[[self window] contentView].bounds];
    [self.rootView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self window] setContentView:self.rootView];

    // Main layout: Horizontal stack of [Activity Bar | NSSplitView]
    NSStackView* mainHorizontal = [[NSStackView alloc] initWithFrame:self.rootView.bounds];
    [mainHorizontal setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [mainHorizontal setSpacing:0];
    [mainHorizontal setDistribution:NSStackViewDistributionFill];
    [mainHorizontal setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.rootView addSubview:mainHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [mainHorizontal.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [mainHorizontal.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [mainHorizontal.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [mainHorizontal.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor]
    ]];

    // 1. Activity Bar (Leftmost panel)
    self.activityBar = [[NSStackView alloc] init];
    [self.activityBar setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [self.activityBar setAlignment:NSLayoutAttributeCenterX];
    [self.activityBar setSpacing:12];
    [self.activityBar setEdgeInsets:NSEdgeInsetsMake(16, 8, 16, 8)];
    [self.activityBar setWantsLayer:YES];
    [self.activityBar.widthAnchor constraintEqualToConstant:76].active = YES;
    
    NSArray<NSDictionary*>* activities = @[
        @{@"id": @"files", @"label": @"Files"},
        @{@"id": @"search", @"label": @"Search"},
        @{@"id": @"run", @"label": @"Run"},
        @{@"id": @"errors", @"label": @"Errors"},
        @{@"id": @"settings", @"label": @"Settings"}
    ];
    for (NSDictionary* act in activities) {
        NSButton* item = [NSButton buttonWithTitle:act[@"label"] target:self action:@selector(activityButtonClicked:)];
        [item setBezelStyle:NSBezelStyleTexturedRounded];
        [item setControlSize:NSControlSizeRegular];
        [item setToolTip:act[@"label"]];
        [item setIdentifier:act[@"id"]];
        [self.activityBar addArrangedSubview:item];
    }
    [mainHorizontal addArrangedSubview:self.activityBar];

    // 2. Main NSSplitView (Horizontal splitting: left sidebar, right pane)
    self.horizontalSplit = [[NSSplitView alloc] init];
    [self.horizontalSplit setVertical:YES];
    [self.horizontalSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [self.horizontalSplit setDelegate:self];
    [self.horizontalSplit setTranslatesAutoresizingMaskIntoConstraints:NO];
    [mainHorizontal addArrangedSubview:self.horizontalSplit];

    // Left pane: Sidebar
    self.sidebarView = [[NSView alloc] init];
    [self.sidebarView setWantsLayer:YES];
    [self.sidebarView.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [self.sidebarView.widthAnchor constraintLessThanOrEqualToConstant:400].active = YES;
    [self.horizontalSplit addSubview:self.sidebarView];

    // Right pane: Right container view for editor + bottom panel vertical split
    NSView* rightContainer = [[NSView alloc] init];
    [rightContainer setWantsLayer:YES];
    [self.horizontalSplit addSubview:rightContainer];

    // Sidebar Inner panel view hierarchy
    self.sidebarInnerView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    [self.sidebarInnerView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.sidebarView addSubview:self.sidebarInnerView];

    // Vertical NSSplitView inside Right container (Top editor, bottom output panel)
    self.verticalSplit = [[NSSplitView alloc] initWithFrame:rightContainer.bounds];
    [self.verticalSplit setVertical:NO];
    [self.verticalSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [self.verticalSplit setDelegate:self];
    [self.verticalSplit setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [rightContainer addSubview:self.verticalSplit];

    // Top Pane: Editor area container
    NSView* editorAreaContainer = [[NSView alloc] init];
    [editorAreaContainer setWantsLayer:YES];
    [self.verticalSplit addSubview:editorAreaContainer];

    // Layout custom Tab Bar at the top of the editor container
    self.tabHeaderScrollView = [[NSScrollView alloc] init];
    [self.tabHeaderScrollView setHasHorizontalScroller:YES];
    [self.tabHeaderScrollView setHasVerticalScroller:NO];
    [self.tabHeaderScrollView setDrawsBackground:YES];
    [self.tabHeaderScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.tabHeaderScrollView.heightAnchor constraintEqualToConstant:38].active = YES;
    [editorAreaContainer addSubview:self.tabHeaderScrollView];

    self.tabHeaderStack = [[NSStackView alloc] init];
    [self.tabHeaderStack setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [self.tabHeaderStack setSpacing:4];
    [self.tabHeaderStack setEdgeInsets:NSEdgeInsetsMake(4, 8, 4, 8)];
    [self.tabHeaderScrollView setDocumentView:self.tabHeaderStack];

    // Editor tab view below tab bar
    self.editorTabView = [[NSTabView alloc] init];
    [self.editorTabView setTabViewType:NSNoTabsNoBorder];
    [self.editorTabView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [editorAreaContainer addSubview:self.editorTabView];

    self.editorHostView = [[NSView alloc] init];
    [self.editorHostView setWantsLayer:YES];
    [self.editorHostView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.editorTabView addSubview:self.editorHostView]; // Add as welcome parent

    [NSLayoutConstraint activateConstraints:@[
        [self.tabHeaderScrollView.leadingAnchor constraintEqualToAnchor:editorAreaContainer.leadingAnchor],
        [self.tabHeaderScrollView.trailingAnchor constraintEqualToAnchor:editorAreaContainer.trailingAnchor],
        [self.tabHeaderScrollView.topAnchor constraintEqualToAnchor:editorAreaContainer.topAnchor],
        
        [self.editorTabView.leadingAnchor constraintEqualToAnchor:editorAreaContainer.leadingAnchor],
        [self.editorTabView.trailingAnchor constraintEqualToAnchor:editorAreaContainer.trailingAnchor],
        [self.editorTabView.topAnchor constraintEqualToAnchor:self.tabHeaderScrollView.bottomAnchor],
        [self.editorTabView.bottomAnchor constraintEqualToAnchor:editorAreaContainer.bottomAnchor]
    ]];

    // Bottom Pane: Bottom Panel
    self.bottomPanel = [[NSView alloc] init];
    [self.bottomPanel setWantsLayer:YES];
    [self.bottomPanel.heightAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    [self.verticalSplit addSubview:self.bottomPanel];

    // Tab view inside bottom panel
    self.bottomTabView = [[NSTabView alloc] init];
    [self.bottomTabView setTabViewType:NSNoTabsNoBorder];
    [self.bottomTabView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.bottomPanel addSubview:self.bottomTabView];

    // Bottom tab bar buttons
    NSStackView* bottomBar = [[NSStackView alloc] init];
    [bottomBar setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [bottomBar setSpacing:12];
    [bottomBar setEdgeInsets:NSEdgeInsetsMake(4, 12, 4, 12)];
    [bottomBar setWantsLayer:YES];
    [bottomBar setTranslatesAutoresizingMaskIntoConstraints:NO];
    [bottomBar.heightAnchor constraintEqualToConstant:32].active = YES;
    [self.bottomPanel addSubview:bottomBar];

    NSArray<NSDictionary*>* bottomTabs = @[
        @{@"id": @"terminal", @"label": @"Terminal"},
        @{@"id": @"output", @"label": @"Output"},
        @{@"id": @"errors", @"label": @"Errors"},
        @{@"id": @"search", @"label": @"Search Results"}
    ];
    for (NSDictionary* bt in bottomTabs) {
        NSButton* btn = [NSButton buttonWithTitle:bt[@"label"] target:self action:@selector(bottomTabButtonClicked:)];
        [btn setBezelStyle:NSBezelStyleRecessed];
        [btn setIdentifier:bt[@"id"]];
        if ([bt[@"id"] isEqualToString:@"terminal"]) {
            [btn setHighlighted:YES];
        }
        [bottomBar addArrangedSubview:btn];
    }

    [NSLayoutConstraint activateConstraints:@[
        [bottomBar.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor],
        [bottomBar.trailingAnchor constraintEqualToAnchor:self.bottomPanel.trailingAnchor],
        [bottomBar.topAnchor constraintEqualToAnchor:self.bottomPanel.topAnchor],
        
        [self.bottomTabView.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor],
        [self.bottomTabView.trailingAnchor constraintEqualToAnchor:self.bottomPanel.trailingAnchor],
        [self.bottomTabView.topAnchor constraintEqualToAnchor:bottomBar.bottomAnchor],
        [self.bottomTabView.bottomAnchor constraintEqualToAnchor:self.bottomPanel.bottomAnchor]
    ]];

    // Create Bottom Tab contents
    [self buildBottomTabViews];

    // 3. Status Bar (Global bottom indicator)
    self.statusLabel = [NSTextField labelWithString:@"No file open • Saved • Plain Text • Line 1, Column 1"];
    [self.statusLabel setFont:[NSFont systemFontOfSize:12]];
    [self.statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [self.statusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSView* statusBar = [[NSView alloc] init];
    [statusBar setWantsLayer:YES];
    [statusBar.heightAnchor constraintEqualToConstant:30].active = YES;
    [statusBar addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor]
    ]];
    
    // Replace vertical stack with dynamic splits + status bar
    NSStackView* verticalMain = [[NSStackView alloc] init];
    [verticalMain setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [verticalMain setSpacing:0];
    [verticalMain setDistribution:NSStackViewDistributionFill];
    [self.rootView addSubview:verticalMain];
    [verticalMain setTranslatesAutoresizingMaskIntoConstraints:NO];
    [NSLayoutConstraint activateConstraints:@[
        [verticalMain.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [verticalMain.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [verticalMain.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [verticalMain.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor]
    ]];

    [verticalMain addArrangedSubview:mainHorizontal];
    [verticalMain addArrangedSubview:statusBar];
    
    // Sidebar panels prep
    [self prepareSidebarPanels];
    
    // Apply styling colors
    [self applyThemeColors];
}

- (void)buildBottomTabViews {
    // Terminal Tab
    NSScrollView* termScroll = [[NSScrollView alloc] init];
    [termScroll setHasVerticalScroller:YES];
    self.terminalTextView = [[DietCodeTerminalTextView alloc] initWithFrame:termScroll.bounds];
    [self.terminalTextView setMinSize:NSMakeSize(0.0, 0.0)];
    [self.terminalTextView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [self.terminalTextView setVerticallyResizable:YES];
    [self.terminalTextView setHorizontallyResizable:NO];
    [self.terminalTextView setAutoresizingMask:NSViewWidthSizable];
    [self.terminalTextView setEditable:YES];
    [self.terminalTextView setRichText:NO];
    [self.terminalTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [termScroll setDocumentView:self.terminalTextView];
    
    NSTabViewItem* termItem = [[NSTabViewItem alloc] initWithIdentifier:@"terminal"];
    [termItem setView:termScroll];
    [self.bottomTabView addTabViewItem:termItem];

    // Output Tab
    NSScrollView* outScroll = [[NSScrollView alloc] init];
    [outScroll setHasVerticalScroller:YES];
    self.outputTextView = [[NSTextView alloc] initWithFrame:outScroll.bounds];
    [self.outputTextView setEditable:NO];
    [self.outputTextView setRichText:NO];
    [self.outputTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [outScroll setDocumentView:self.outputTextView];
    [self addPlaceholder:@"No output yet.\nRun a file to see output here." toTextView:self.outputTextView];
    [self updatePlaceholderVisibility:self.outputTextView];
    
    NSTabViewItem* outItem = [[NSTabViewItem alloc] initWithIdentifier:@"output"];
    [outItem setView:outScroll];
    [self.bottomTabView addTabViewItem:outItem];

    // Errors Tab
    NSScrollView* errScroll = [[NSScrollView alloc] init];
    [errScroll setHasVerticalScroller:YES];
    self.errorsTextView = [[NSTextView alloc] initWithFrame:errScroll.bounds];
    [self.errorsTextView setEditable:NO];
    [self.errorsTextView setRichText:NO];
    [self.errorsTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [errScroll setDocumentView:self.errorsTextView];
    [self addPlaceholder:@"No compiler errors.\nRun a file to check for problems." toTextView:self.errorsTextView];
    [self updatePlaceholderVisibility:self.errorsTextView];
    
    NSTabViewItem* errItem = [[NSTabViewItem alloc] initWithIdentifier:@"errors"];
    [errItem setView:errScroll];
    [self.bottomTabView addTabViewItem:errItem];

    // Search Results Tab
    NSScrollView* searchScroll = [[NSScrollView alloc] init];
    [searchScroll setHasVerticalScroller:YES];
    self.searchResultsTextView = [[NSTextView alloc] initWithFrame:searchScroll.bounds];
    [self.searchResultsTextView setEditable:NO];
    [self.searchResultsTextView setRichText:NO];
    [self.searchResultsTextView setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [searchScroll setDocumentView:self.searchResultsTextView];
    [self addPlaceholder:@"No search results.\nEnter a term in the Search sidebar and click Search." toTextView:self.searchResultsTextView];
    [self updatePlaceholderVisibility:self.searchResultsTextView];
    
    NSTabViewItem* searchItem = [[NSTabViewItem alloc] initWithIdentifier:@"search"];
    [searchItem setView:searchScroll];
    [self.bottomTabView addTabViewItem:searchItem];
}

- (void)bottomTabButtonClicked:(NSButton*)sender {
    NSString* identifier = sender.identifier;
    for (NSButton* btn in [sender.superview subviews]) {
        [btn setHighlighted:NO];
    }
    [sender setHighlighted:YES];
    [self.bottomTabView selectTabViewItemWithIdentifier:identifier];
}

- (void)prepareSidebarPanels {
    // 1. Files panel
    self.filesSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    NSStackView* filesStack = [[NSStackView alloc] init];
    [filesStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [filesStack setSpacing:8];
    [filesStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [filesStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.filesSidebarView addSubview:filesStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [filesStack.leadingAnchor constraintEqualToAnchor:self.filesSidebarView.leadingAnchor],
        [filesStack.trailingAnchor constraintEqualToAnchor:self.filesSidebarView.trailingAnchor],
        [filesStack.topAnchor constraintEqualToAnchor:self.filesSidebarView.topAnchor],
        [filesStack.bottomAnchor constraintEqualToAnchor:self.filesSidebarView.bottomAnchor]
    ]];

    NSTextField* fTitle = MakeLabel(@"WORKSPACE", 13, NSFontWeightBold);
    [fTitle setTextColor:[NSColor secondaryLabelColor]];
    [filesStack addArrangedSubview:fTitle];

    // Folder tree Toolbar
    NSStackView* filesToolbar = [[NSStackView alloc] init];
    [filesToolbar setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [filesToolbar setSpacing:6];
    
    NSButton* newFileBtn = [NSButton buttonWithTitle:@"New File" target:self action:@selector(newFileClicked:)];
    [newFileBtn setBezelStyle:NSBezelStyleRecessed];
    NSButton* newFolderBtn = [NSButton buttonWithTitle:@"New Folder" target:self action:@selector(newFolderClicked:)];
    [newFolderBtn setBezelStyle:NSBezelStyleRecessed];
    NSButton* refreshBtn = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refreshFilesTree:)];
    [refreshBtn setBezelStyle:NSBezelStyleRecessed];
    
    [filesToolbar addArrangedSubview:newFileBtn];
    [filesToolbar addArrangedSubview:newFolderBtn];
    [filesToolbar addArrangedSubview:refreshBtn];
    [filesStack addArrangedSubview:filesToolbar];

    // NSOutlineView scroll content
    NSScrollView* outlineScroll = [[NSScrollView alloc] init];
    [outlineScroll setHasVerticalScroller:YES];
    [outlineScroll setHasHorizontalScroller:YES];
    [outlineScroll setTranslatesAutoresizingMaskIntoConstraints:NO];
    [filesStack addArrangedSubview:outlineScroll];
    
    self.fileTreeView = [[DietCodeOutlineView alloc] initWithFrame:outlineScroll.bounds];
    [self.fileTreeView setHeaderView:nil];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"FileColumn"];
    col.title = @"Files";
    [self.fileTreeView addTableColumn:col];
    [self.fileTreeView setOutlineTableColumn:col];
    [self.fileTreeView setDataSource:self];
    [self.fileTreeView setDelegate:self];
    [self.fileTreeView setAutoresizesOutlineColumn:YES];
    
    // Set Double Click to open file or toggle folder
    [self.fileTreeView setDoubleAction:@selector(fileTreeDoubleClicked:)];
    [self.fileTreeView setTarget:self];
    
    // Add Context Menu
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"FileActions"];
    [fileMenu addItemWithTitle:@"New File…" action:@selector(newFileClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"New Folder…" action:@selector(newFolderClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Rename…" action:@selector(renameFileClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Delete" action:@selector(deleteFileClicked:) keyEquivalent:@""];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Reveal in Finder" action:@selector(revealInFinderClicked:) keyEquivalent:@""];
    [self.fileTreeView setMenu:fileMenu];
    
    [outlineScroll setDocumentView:self.fileTreeView];

    // Create empty state for files tree view
    self.fileTreeEmptyStateView = [[NSView alloc] init];
    NSStackView* esStack = [[NSStackView alloc] init];
    [esStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [esStack setSpacing:8];
    [esStack setEdgeInsets:NSEdgeInsetsMake(20, 12, 20, 12)];
    [esStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.fileTreeEmptyStateView addSubview:esStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [esStack.leadingAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.leadingAnchor],
        [esStack.trailingAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.trailingAnchor],
        [esStack.topAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.topAnchor]
    ]];
    
    NSTextField* esLabel = MakeLabel(@"No folder open.\nOpen a folder to browse files.", 12, NSFontWeightRegular);
    [esLabel setTextColor:[NSColor secondaryLabelColor]];
    [esLabel setAlignment:NSTextAlignmentCenter];
    [esStack addArrangedSubview:esLabel];
    
    NSButton* esBtn = MakeButton(@"Open Folder...", self, @selector(openFolder:));
    [esStack addArrangedSubview:esBtn];
    
    [self.filesSidebarView addSubview:self.fileTreeEmptyStateView];
    [self.fileTreeEmptyStateView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [NSLayoutConstraint activateConstraints:@[
        [self.fileTreeEmptyStateView.leadingAnchor constraintEqualToAnchor:outlineScroll.leadingAnchor],
        [self.fileTreeEmptyStateView.trailingAnchor constraintEqualToAnchor:outlineScroll.trailingAnchor],
        [self.fileTreeEmptyStateView.topAnchor constraintEqualToAnchor:outlineScroll.topAnchor],
        [self.fileTreeEmptyStateView.bottomAnchor constraintEqualToAnchor:outlineScroll.bottomAnchor]
    ]];
    
    // Toggle visibility depending on whether a folder is open
    BOOL hasFolder = (self.openedFolderPath != nil);
    [self.fileTreeEmptyStateView setHidden:hasFolder];
    [outlineScroll setHidden:!hasFolder];

    // 2. Search Panel
    self.searchSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    NSStackView* searchStack = [[NSStackView alloc] init];
    [searchStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [searchStack setSpacing:12];
    [searchStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [searchStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.searchSidebarView addSubview:searchStack];

    [NSLayoutConstraint activateConstraints:@[
        [searchStack.leadingAnchor constraintEqualToAnchor:self.searchSidebarView.leadingAnchor],
        [searchStack.trailingAnchor constraintEqualToAnchor:self.searchSidebarView.trailingAnchor],
        [searchStack.topAnchor constraintEqualToAnchor:self.searchSidebarView.topAnchor]
    ]];

    [searchStack addArrangedSubview:MakeLabel(@"SEARCH WORKSPACE", 13, NSFontWeightBold)];
    
    NSTextField* searchField = [[NSTextField alloc] init];
    [searchField setPlaceholderString:@"Search term..."];
    [searchField setIdentifier:@"SearchInput"];
    [searchStack addArrangedSubview:searchField];

    NSButton* caseCheck = [NSButton buttonWithTitle:@"Case Sensitive" target:nil action:nil];
    [caseCheck setButtonType:NSButtonTypeSwitch];
    [caseCheck setIdentifier:@"CaseSensitive"];
    [searchStack addArrangedSubview:caseCheck];

    NSStackView* searchButtons = [[NSStackView alloc] init];
    [searchButtons setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [searchButtons setSpacing:8];
    
    NSButton* startSearchBtn = [NSButton buttonWithTitle:@"Search" target:self action:@selector(startWorkspaceSearch:)];
    [startSearchBtn setBezelStyle:NSBezelStyleRounded];
    NSButton* cancelSearchBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelWorkspaceSearch:)];
    [cancelSearchBtn setBezelStyle:NSBezelStyleRounded];
    [searchButtons addArrangedSubview:startSearchBtn];
    [searchButtons addArrangedSubview:cancelSearchBtn];
    [searchStack addArrangedSubview:searchButtons];

    // 3. Run Panel
    self.runSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    NSStackView* runStack = [[NSStackView alloc] init];
    [runStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [runStack setSpacing:16];
    [runStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [runStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.runSidebarView addSubview:runStack];

    [NSLayoutConstraint activateConstraints:@[
        [runStack.leadingAnchor constraintEqualToAnchor:self.runSidebarView.leadingAnchor],
        [runStack.trailingAnchor constraintEqualToAnchor:self.runSidebarView.trailingAnchor],
        [runStack.topAnchor constraintEqualToAnchor:self.runSidebarView.topAnchor]
    ]];

    [runStack addArrangedSubview:MakeLabel(@"RUN PROGRAM", 13, NSFontWeightBold)];
    
    NSButton* runBtn = [NSButton buttonWithTitle:@"Run File" target:self action:@selector(runCurrentFile:)];
    [runBtn setBezelStyle:NSBezelStyleRounded];
    [runBtn setControlSize:NSControlSizeLarge];
    
    NSButton* stopBtn = [NSButton buttonWithTitle:@"Stop File" target:self action:@selector(stopCurrentFile:)];
    [stopBtn setBezelStyle:NSBezelStyleRounded];
    [stopBtn setControlSize:NSControlSizeLarge];
    [stopBtn setEnabled:NO];
    
    [runStack addArrangedSubview:runBtn];
    [runStack addArrangedSubview:stopBtn];
    
    self.runStatusLabel = MakeLabel(@"Ready to run", 13, NSFontWeightRegular);
    [self.runStatusLabel setTextColor:[NSColor secondaryLabelColor]];
    self.runExplanationLabel = MakeLabel(@"", 12, NSFontWeightRegular);
    [self.runExplanationLabel setTextColor:[NSColor systemOrangeColor]];
    
    [runStack addArrangedSubview:self.runStatusLabel];
    [runStack addArrangedSubview:self.runExplanationLabel];

    // 4. Errors Panel
    self.errorsSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    NSStackView* errStack = [[NSStackView alloc] init];
    [errStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [errStack setSpacing:12];
    [errStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [errStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.errorsSidebarView addSubview:errStack];

    [NSLayoutConstraint activateConstraints:@[
        [errStack.leadingAnchor constraintEqualToAnchor:self.errorsSidebarView.leadingAnchor],
        [errStack.trailingAnchor constraintEqualToAnchor:self.errorsSidebarView.trailingAnchor],
        [errStack.topAnchor constraintEqualToAnchor:self.errorsSidebarView.topAnchor]
    ]];

    [errStack addArrangedSubview:MakeLabel(@"COMPILER PROBLEMS", 13, NSFontWeightBold)];
    NSTextField* problemsHelp = MakeLabel(@"Compiler errors and run logs will appear in the bottom panel under Errors. Keep compiler runs quiet and clean.", 12, NSFontWeightRegular);
    [problemsHelp setTextColor:[NSColor secondaryLabelColor]];
    [errStack addArrangedSubview:problemsHelp];

    // 5. Settings Panel
    self.settingsSidebarView = [[NSView alloc] initWithFrame:self.sidebarView.bounds];
    NSStackView* setStack = [[NSStackView alloc] init];
    [setStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [setStack setSpacing:14];
    [setStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [setStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.settingsSidebarView addSubview:setStack];

    [NSLayoutConstraint activateConstraints:@[
        [setStack.leadingAnchor constraintEqualToAnchor:self.settingsSidebarView.leadingAnchor],
        [setStack.trailingAnchor constraintEqualToAnchor:self.settingsSidebarView.trailingAnchor],
        [setStack.topAnchor constraintEqualToAnchor:self.settingsSidebarView.topAnchor]
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
}

- (void)applyThemeColors {
    BOOL isDark = [self isDarkTheme];
    BOOL isHighContrast = [self isHighContrastTheme];
    
    // Set Window Appearance
    NSAppearance* app = nil;
    if (@available(macOS 10.14, *)) {
        if (self.currentThemeIndex == 1) {
            app = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        } else if (self.currentThemeIndex == 2) {
            app = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else if (self.currentThemeIndex == 3) {
            app = [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastAqua];
        } else if (self.currentThemeIndex == 4) {
            app = [NSAppearance appearanceNamed:NSAppearanceNameAccessibilityHighContrastDarkAqua];
        }
        [[self window] setAppearance:app];
    }
    
    // Colors
    NSColor* bg = nil;
    NSColor* sidebarBg = nil;
    NSColor* editorBg = nil;
    NSColor* textColor = nil;
    NSColor* statusBg = nil;
    NSColor* statusText = nil;
    
    if (isHighContrast) {
        if (isDark) {
            bg = [NSColor blackColor];
            sidebarBg = [NSColor colorWithCalibratedWhite:0.05 alpha:1.0];
            editorBg = [NSColor blackColor];
            textColor = [NSColor whiteColor];
            statusBg = [NSColor colorWithCalibratedWhite:0.05 alpha:1.0];
            statusText = [NSColor whiteColor];
        } else {
            bg = [NSColor whiteColor];
            sidebarBg = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
            editorBg = [NSColor whiteColor];
            textColor = [NSColor blackColor];
            statusBg = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
            statusText = [NSColor blackColor];
        }
    } else {
        if (isDark) {
            bg = [NSColor colorWithCalibratedWhite:0.08 alpha:1.0];
            sidebarBg = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
            editorBg = [NSColor colorWithCalibratedWhite:0.15 alpha:1.0];
            textColor = [NSColor textColor];
            statusBg = [NSColor colorWithCalibratedWhite:0.10 alpha:1.0];
            statusText = [NSColor secondaryLabelColor];
        } else {
            bg = [NSColor colorWithCalibratedWhite:0.94 alpha:1.0];
            sidebarBg = [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
            editorBg = [NSColor textBackgroundColor];
            textColor = [NSColor textColor];
            statusBg = [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];
            statusText = [NSColor secondaryLabelColor];
        }
    }
    
    [self.activityBar setWantsLayer:YES];
    [self.sidebarView setWantsLayer:YES];
    [self.bottomPanel setWantsLayer:YES];
    [self.activityBar.layer setBackgroundColor:[bg CGColor]];
    [self.sidebarView.layer setBackgroundColor:[sidebarBg CGColor]];
    [self.bottomPanel.layer setBackgroundColor:[sidebarBg CGColor]];
    
    // Set status bar bg/text colors
    NSView* statusBar = [self.statusLabel superview];
    [statusBar setWantsLayer:YES];
    [statusBar.layer setBackgroundColor:[statusBg CGColor]];
    [self.statusLabel setTextColor:statusText];
    
    // Rulers and editor backgrounds
    for (DietCodeTabState* tab in self.openTabs) {
        [tab.scrollView.verticalRulerView setNeedsDisplay:YES];
        [tab.textView setBackgroundColor:editorBg];
        [tab.textView setTextColor:textColor];
        [tab.textView setInsertionPointColor:textColor];
        
        // Selection color
        if (isHighContrast) {
            tab.textView.selectedTextAttributes = @{
                NSBackgroundColorAttributeName: isDark ? [NSColor yellowColor] : [NSColor blueColor],
                NSForegroundColorAttributeName: isDark ? [NSColor blackColor] : [NSColor whiteColor]
            };
        } else {
            tab.textView.selectedTextAttributes = @{};
        }
    }
    
    // Output, errors, terminal text views
    NSArray<NSTextView*>* extraTextViews = @[self.terminalTextView, self.outputTextView, self.errorsTextView, self.searchResultsTextView];
    for (NSTextView* tv in extraTextViews) {
        [tv setBackgroundColor:editorBg];
        [tv setTextColor:textColor];
        [tv setInsertionPointColor:textColor];
        
        if (isHighContrast) {
            tv.selectedTextAttributes = @{
                NSBackgroundColorAttributeName: isDark ? [NSColor yellowColor] : [NSColor blueColor],
                NSForegroundColorAttributeName: isDark ? [NSColor blackColor] : [NSColor whiteColor]
            };
        } else {
            tv.selectedTextAttributes = @{};
        }
    }
    
    [self updateTabHeaderLayout];
    [self updateFocusBorders];
}

- (void)activityButtonClicked:(NSButton*)sender {
    NSString* activity = sender.identifier;
    [self selectActivity:activity];
}

- (void)selectActivity:(NSString*)activity {
    // Un-highlight old
    if (self.lastSelectedActivityBtn) {
        [self.lastSelectedActivityBtn setHighlighted:NO];
    }
    
    // Toggle sidebar if clicking active
    if ([self.currentActivity isEqualToString:activity]) {
        [self toggleSidebar:nil];
        return;
    }
    
    // Find button
    NSButton* targetBtn = nil;
    for (NSButton* btn in [self.activityBar arrangedSubviews]) {
        if ([btn.identifier isEqualToString:activity]) {
            targetBtn = btn;
            break;
        }
    }
    [targetBtn setHighlighted:YES];
    self.lastSelectedActivityBtn = targetBtn;
    self.currentActivity = activity;
    
    // Uncollapse if collapsed
    if ([self.horizontalSplit isSubviewCollapsed:self.sidebarView]) {
        [self toggleSidebar:nil];
    }
    
    // Switch inner view
    for (NSView* sv in [self.sidebarInnerView subviews]) {
        [sv removeFromSuperview];
    }
    
    NSView* targetView = nil;
    if ([activity isEqualToString:@"files"]) {
        targetView = self.filesSidebarView;
    } else if ([activity isEqualToString:@"search"]) {
        targetView = self.searchSidebarView;
    } else if ([activity isEqualToString:@"run"]) {
        targetView = self.runSidebarView;
    } else if ([activity isEqualToString:@"errors"]) {
        targetView = self.errorsSidebarView;
    } else if ([activity isEqualToString:@"settings"]) {
        targetView = self.settingsSidebarView;
    }
    
    if (targetView) {
        [targetView setFrame:self.sidebarInnerView.bounds];
        [targetView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self.sidebarInnerView addSubview:targetView];
    }
}

- (void)toggleSidebar:(id)sender {
    BOOL collapsed = [self.horizontalSplit isSubviewCollapsed:self.sidebarView];
    if (collapsed) {
        // Expand
        [self.sidebarView setHidden:NO];
        CGFloat width = self.sidebarView.bounds.size.width;
        if (width < 50) {
            width = 250;
        }
        [self.horizontalSplit setPosition:width ofDividerAtIndex:0];
    } else {
        // Collapse
        [self.sidebarView setHidden:YES];
    }
    [self.horizontalSplit adjustSubviews];
}

- (void)toggleTerminal:(id)sender {
    BOOL collapsed = [self.verticalSplit isSubviewCollapsed:self.bottomPanel];
    if (collapsed) {
        [self.bottomPanel setHidden:NO];
        CGFloat height = self.bottomPanel.bounds.size.height;
        if (height < 50) {
            height = 180;
        }
        [self.verticalSplit setPosition:self.verticalSplit.bounds.size.height - height ofDividerAtIndex:0];
    } else {
        [self.bottomPanel setHidden:YES];
    }
    [self.verticalSplit adjustSubviews];
}

// --- Tabbed Editor Management ---

- (void)showEditorWithText:(NSString*)text path:(NSString*)path dirty:(BOOL)isDirty {
    // If tab is already open with this path, select it
    if (path != nil) {
        for (DietCodeTabState* tab in self.openTabs) {
            if ([tab.path isEqualToString:path]) {
                [self activateTab:tab];
                return;
            }
        }
    }

    // Hide welcome
    self.editorHostView.hidden = YES;
    self.hasDocument = YES;

    // Create custom tab
    DietCodeTabState* tab = [[DietCodeTabState alloc] init];
    tab.path = path;
    tab.title = path == nil ? @"Untitled" : [path lastPathComponent];
    tab.dirty = isDirty;

    // Create NSScrollView & NSTextView
    NSScrollView* scrollView = [[NSScrollView alloc] init];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:NO];
    [scrollView setBorderType:NSNoBorder];
    
    NSTextView* editor = [[NSTextView alloc] init];
    [editor setMinSize:NSMakeSize(0.0, 0.0)];
    [editor setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor setVerticallyResizable:YES];
    [editor setHorizontallyResizable:YES];
    [editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [editor.textContainer setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor.textContainer setWidthTracksTextView:self.currentWordWrap];
    [editor setFont:[NSFont monospacedSystemFontOfSize:self.currentFontSize weight:NSFontWeightRegular]];
    [editor setRichText:NO];
    [editor setAutomaticQuoteSubstitutionEnabled:NO];
    [editor setAutomaticDashSubstitutionEnabled:NO];
    [editor setAutomaticTextReplacementEnabled:NO];
    [editor setAllowsUndo:YES];
    [editor setDelegate:self];
    
    self.loadingDocument = YES;
    [editor setString:text ?: @""];
    self.loadingDocument = NO;
    
    [scrollView setDocumentView:editor];
    
    // Add vertical line numbers ruler view
    [scrollView setHasVerticalRuler:YES];
    [scrollView setRulersVisible:YES];
    DietCodeLineNumberRulerView* ruler = [[DietCodeLineNumberRulerView alloc] initWithScrollView:scrollView];
    [scrollView setVerticalRulerView:ruler];

    tab.scrollView = scrollView;
    tab.textView = editor;
    
    // Add to open tabs array
    [self.openTabs addObject:tab];

    // Build NSTabViewItem
    NSTabViewItem* tabItem = [[NSTabViewItem alloc] initWithIdentifier:tab];
    [tabItem setView:scrollView];
    [self.editorTabView addTabViewItem:tabItem];

    // Add Tab Header Button
    [self createTabHeaderButton:tab];

    // Select/Activate tab
    [self activateTab:tab];
}

- (void)createTabHeaderButton:(DietCodeTabState*)tab {
    NSStackView* tabBtn = [[NSStackView alloc] init];
    [tabBtn setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [tabBtn setSpacing:6];
    [tabBtn setEdgeInsets:NSEdgeInsetsMake(2, 8, 2, 8)];
    [tabBtn setWantsLayer:YES];
    
    NSTextField* titleLabel = MakeLabel(tab.title, 12, NSFontWeightRegular);
    [tabBtn addArrangedSubview:titleLabel];
    
    NSButton* closeBtn = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeTabButtonClicked:)];
    [closeBtn setBezelStyle:NSBezelStyleRecessed];
    [closeBtn setControlSize:NSControlSizeMini];
    [closeBtn setIdentifier:[NSString stringWithFormat:@"%p", tab]];
    [closeBtn setAccessibilityLabel:[NSString stringWithFormat:@"Close %@", tab.title]];
    [tabBtn setAccessibilityRole:@"AXTab"];
    [tabBtn setAccessibilityLabel:tab.title];
    [tabBtn addArrangedSubview:closeBtn];

    // Gesture recognizer for click select
    NSClickGestureRecognizer* click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(tabHeaderClicked:)];
    [tabBtn addGestureRecognizer:click];
    tabBtn.identifier = [NSString stringWithFormat:@"%p", tab];
    tab.tabButtonView = tabBtn;

    [self.tabHeaderStack addArrangedSubview:tabBtn];
    [self updateTabHeaderLayout];
}

- (void)tabHeaderClicked:(NSClickGestureRecognizer*)gesture {
    NSView* tabBtn = gesture.view;
    NSString* tabPtrStr = tabBtn.identifier;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([[NSString stringWithFormat:@"%p", tab] isEqualToString:tabPtrStr]) {
            [self activateTab:tab];
            break;
        }
    }
}

- (void)closeTabButtonClicked:(NSButton*)sender {
    NSString* tabPtrStr = sender.identifier;
    DietCodeTabState* targetTab = nil;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([[NSString stringWithFormat:@"%p", tab] isEqualToString:tabPtrStr]) {
            targetTab = tab;
            break;
        }
    }
    if (targetTab) {
        [self closeTab:targetTab];
    }
}

- (void)closeTab:(DietCodeTabState*)tab {
    if (tab.dirty) {
        // Prompt save
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[NSString stringWithFormat:@"Save changes to %@?", tab.title]];
        [alert setInformativeText:@"Your file has unsaved changes. You can save them or close without saving."];
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Close Without Saving"];
        [alert addButtonWithTitle:@"Cancel"];
        NSModalResponse res = [alert runModal];
        if (res == NSAlertFirstButtonReturn) {
            [self saveTab:tab];
        } else if (res == NSAlertSecondButtonReturn) {
            [self deleteBackupForTab:tab];
        } else if (res == NSAlertThirdButtonReturn) {
            return; // Cancel
        }
    }

    // Cancel pending perform requests and delete backup
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveBackupForTab:) object:tab];
    [self deleteBackupForTab:tab];

    // Remove from array and headers
    [self.openTabs removeObject:tab];
    [self saveOpenTabsState];
    [tab.tabButtonView removeFromSuperview];
    
    // Remove from NSTabView
    NSTabViewItem* targetItem = nil;
    for (NSTabViewItem* item in [self.editorTabView tabViewItems]) {
        if (item.identifier == tab) {
            targetItem = item;
            break;
        }
    }
    if (targetItem) {
        [self.editorTabView removeTabViewItem:targetItem];
    }

    if (self.openTabs.count > 0) {
        if (self.activeTab == tab) {
            [self activateTab:[self.openTabs lastObject]];
        } else {
            [self updateTabHeaderLayout];
        }
    } else {
        self.activeTab = nil;
        self.textView = nil;
        self.hasDocument = NO;
        self.editorHostView.hidden = NO;
        [self showWelcome:nil];
    }
}

- (void)activateTab:(DietCodeTabState*)tab {
    self.activeTab = tab;
    self.textView = tab.textView;
    
    // Select NSTabViewItem
    for (NSTabViewItem* item in [self.editorTabView tabViewItems]) {
        if (item.identifier == tab) {
            [self.editorTabView selectTabViewItem:item];
            break;
        }
    }

    [[self window] makeFirstResponder:tab.textView];
    [self updateTabHeaderLayout];
    [self updateWindowTitleAndStatus];
}

- (void)updateTabHeaderLayout {
    BOOL isDark = NO;
    if (@available(macOS 10.14, *)) {
        NSAppearanceName appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        isDark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    }

    for (DietCodeTabState* tab in self.openTabs) {
        NSStackView* btn = (NSStackView*)tab.tabButtonView;
        NSTextField* titleL = (NSTextField*)[btn arrangedSubviews][0];
        
        // Highlight active tab
        if (tab == self.activeTab) {
            [btn.layer setBackgroundColor:(isDark ? [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] CGColor] : [[NSColor whiteColor] CGColor])];
            [titleL setTextColor:[NSColor textColor]];
        } else {
            [btn.layer setBackgroundColor:(isDark ? [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] CGColor] : [[NSColor colorWithCalibratedWhite:0.88 alpha:1.0] CGColor])];
            [titleL setTextColor:[NSColor secondaryLabelColor]];
        }
        
        // Show dirty indicator
        NSString* displayTitle = tab.dirty ? [NSString stringWithFormat:@"● %@", tab.title] : tab.title;
        [titleL setStringValue:displayTitle];
    }
}

- (void)nextTab:(id)sender {
    if (self.openTabs.count <= 1) return;
    NSUInteger index = [self.openTabs indexOfObject:self.activeTab];
    if (index == NSNotFound) return;
    NSUInteger nextIndex = (index + 1) % self.openTabs.count;
    [self activateTab:self.openTabs[nextIndex]];
}

- (void)previousTab:(id)sender {
    if (self.openTabs.count <= 1) return;
    NSUInteger index = [self.openTabs indexOfObject:self.activeTab];
    if (index == NSNotFound) return;
    NSUInteger prevIndex = (index + self.openTabs.count - 1) % self.openTabs.count;
    [self activateTab:self.openTabs[prevIndex]];
}

- (void)windowDidUpdate:(NSNotification *)notification {
    [self updateFocusBorders];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self refreshFilesTree:nil];
    if (self.activeTab) {
        [self checkExternalStatusForTab:self.activeTab];
    }
}

- (BOOL)isDarkTheme {
    if (self.currentThemeIndex == 2 || self.currentThemeIndex == 4) {
        return YES;
    }
    if (self.currentThemeIndex == 0) {
        if (@available(macOS 10.14, *)) {
            NSAppearanceName appearance = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            return [appearance isEqualToString:NSAppearanceNameDarkAqua];
        }
    }
    return NO;
}

- (BOOL)isHighContrastTheme {
    return (self.currentThemeIndex == 3 || self.currentThemeIndex == 4);
}

- (void)updateFocusBorders {
    id responder = [[self window] firstResponder];
    BOOL isDark = [self isDarkTheme];
    BOOL isHighContrast = [self isHighContrastTheme];
    
    NSColor* normalBorder = [NSColor clearColor];
    NSColor* activeBorder = nil;
    
    if (isHighContrast) {
        activeBorder = isDark ? [NSColor whiteColor] : [NSColor blackColor];
        normalBorder = isDark ? [NSColor colorWithCalibratedWhite:0.2 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.8 alpha:1.0];
    } else {
        activeBorder = [NSColor keyboardFocusIndicatorColor];
    }
    
    // Update editor borders
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.scrollView) {
            [tab.scrollView setWantsLayer:YES];
            if (responder == tab.textView) {
                [tab.scrollView.layer setBorderColor:[activeBorder CGColor]];
                [tab.scrollView.layer setBorderWidth:isHighContrast ? 2.0 : 1.5];
            } else {
                [tab.scrollView.layer setBorderColor:[normalBorder CGColor]];
                [tab.scrollView.layer setBorderWidth:isHighContrast ? 1.0 : 0.0];
            }
        }
    }
    
    // Update outline view border
    NSView* fileTreeScroll = [self.fileTreeView superview].superview;
    if ([fileTreeScroll isKindOfClass:[NSScrollView class]]) {
        [fileTreeScroll setWantsLayer:YES];
        if (responder == self.fileTreeView) {
            [fileTreeScroll.layer setBorderColor:[activeBorder CGColor]];
            [fileTreeScroll.layer setBorderWidth:isHighContrast ? 2.0 : 1.5];
        } else {
            [fileTreeScroll.layer setBorderColor:[normalBorder CGColor]];
            [fileTreeScroll.layer setBorderWidth:isHighContrast ? 1.0 : 0.0];
        }
    }
    
    // Update terminal border
    NSView* termScroll = [self.terminalTextView superview].superview;
    if ([termScroll isKindOfClass:[NSScrollView class]]) {
        [termScroll setWantsLayer:YES];
        if (responder == self.terminalTextView) {
            [termScroll.layer setBorderColor:[activeBorder CGColor]];
            [termScroll.layer setBorderWidth:isHighContrast ? 2.0 : 1.5];
        } else {
            [termScroll.layer setBorderColor:[normalBorder CGColor]];
            [termScroll.layer setBorderWidth:isHighContrast ? 1.0 : 0.0];
        }
    }
}

- (void)cancelOperation:(id)sender {
    if (self.commandPalettePanel.isVisible) {
        [self closePaletteHUD];
        return;
    }
    
    id responder = [[self window] firstResponder];
    if (responder == self.fileTreeView || responder == self.paletteSearchField || [responder isDescendantOf:self.sidebarView]) {
        [self.sidebarView setHidden:YES];
        [self.horizontalSplit adjustSubviews];
        if (self.textView) {
            [[self window] makeFirstResponder:self.textView];
        }
        return;
    }
    
    if (responder == self.terminalTextView || [responder isDescendantOf:self.bottomPanel]) {
        [self.bottomPanel setHidden:YES];
        [self.verticalSplit adjustSubviews];
        if (self.textView) {
            [[self window] makeFirstResponder:self.textView];
        }
        return;
    }
}

- (NSString*)getBackupDirectory {
    NSString* home = NSHomeDirectory();
    NSString* dir = [home stringByAppendingPathComponent:@".dietcode/backups"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)saveBackupForTab:(DietCodeTabState*)tab {
    if (!tab.dirty) return;
    
    NSString* backupDir = [self getBackupDirectory];
    NSString* key = tab.path ? tab.path : [NSString stringWithFormat:@"Untitled-%p", tab];
    NSString* safeKey = [[key dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    safeKey = [safeKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString* backupPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bak", safeKey]];
    
    NSString* originalPathStr = tab.path ? tab.path : @"[Untitled]";
    NSString* titleStr = tab.title;
    NSString* text = [tab.textView string];
    
    NSString* backupContent = [NSString stringWithFormat:@"%@\n%@\n%@", originalPathStr, titleStr, text];
    
    NSError* error = nil;
    [backupContent writeToFile:backupPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        NSLog(@"Failed to write recovery backup: %@", error.localizedDescription);
    }
}

- (void)deleteBackupForTab:(DietCodeTabState*)tab {
    NSString* backupDir = [self getBackupDirectory];
    NSString* key = tab.path ? tab.path : [NSString stringWithFormat:@"Untitled-%p", tab];
    NSString* safeKey = [[key dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    safeKey = [safeKey stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString* backupPath = [backupDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bak", safeKey]];
    
    [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
}

- (void)checkForRecoverableFiles {
    NSString* backupDir = [self getBackupDirectory];
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDir error:nil];
    NSMutableArray* backups = [NSMutableArray array];
    
    for (NSString* file in files) {
        if ([file hasSuffix:@".bak"]) {
            NSString* path = [backupDir stringByAppendingPathComponent:file];
            [backups addObject:path];
        }
    }
    
    if (backups.count == 0) return;
    
    [self showRecoveryDialogWithBackups:backups];
}

- (void)showRecoveryDialogWithBackups:(NSArray<NSString*>*)backupPaths {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Unclean Shutdown Detected"];
    [alert setInformativeText:@"DietCode closed unexpectedly. Unsaved work was found. Would you like to restore or discard these files?"];
    [alert addButtonWithTitle:@"Restore"];
    [alert addButtonWithTitle:@"Discard"];
    
    NSStackView* stack = [[NSStackView alloc] init];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setAlignment:NSLayoutAttributeLeading];
    [stack setSpacing:4];
    
    for (NSString* backupPath in backupPaths) {
        NSString* content = [NSString stringWithContentsOfFile:backupPath encoding:NSUTF8StringEncoding error:nil];
        if (!content) continue;
        
        NSArray* lines = [content componentsSeparatedByString:@"\n"];
        if (lines.count < 2) continue;
        
        NSString* originalPath = lines[0];
        NSString* title = lines[1];
        
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:backupPath error:nil];
        NSDate* modDate = attrs.fileModificationDate;
        NSDateFormatter* df = [[NSDateFormatter alloc] init];
        [df setDateStyle:NSDateFormatterShortStyle];
        [df setTimeStyle:NSDateFormatterShortStyle];
        NSString* dateStr = [df stringFromDate:modDate];
        
        NSString* labelText = [NSString stringWithFormat:@"• %@ (%@) — Saved: %@", title, originalPath, dateStr];
        NSTextField* label = MakeLabel(labelText, 11, NSFontWeightRegular);
        [stack addArrangedSubview:label];
    }
    
    [alert setAccessoryView:stack];
    [alert setAlertStyle:NSAlertStyleWarning];
    
    NSModalResponse res = [alert runModal];
    if (res == NSAlertFirstButtonReturn) {
        for (NSString* backupPath in backupPaths) {
            NSString* content = [NSString stringWithContentsOfFile:backupPath encoding:NSUTF8StringEncoding error:nil];
            if (!content) continue;
            
            NSArray* lines = [content componentsSeparatedByString:@"\n"];
            if (lines.count < 2) continue;
            
            NSString* originalPath = lines[0];
            NSRange contentRange = NSMakeRange(2, lines.count - 2);
            NSArray* contentLines = [lines subarrayWithRange:contentRange];
            NSString* fileContent = [contentLines componentsJoinedByString:@"\n"];
            
            NSString* pathVal = [originalPath isEqualToString:@"[Untitled]"] ? nil : originalPath;
            
            [self showEditorWithText:fileContent path:pathVal dirty:YES];
            [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
        }
    } else {
        for (NSString* backupPath in backupPaths) {
            [[NSFileManager defaultManager] removeItemAtPath:backupPath error:nil];
        }
    }
}

- (void)checkExternalStatusForTab:(DietCodeTabState*)tab {
    if (tab.path == nil) return;
    
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:tab.path isDirectory:&isDir]) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Deleted Externally"];
        [alert setInformativeText:[NSString stringWithFormat:@"The file '%@' has been deleted externally. Would you like to keep the editor open or close it?", tab.title]];
        [alert addButtonWithTitle:@"Keep Open"];
        [alert addButtonWithTitle:@"Close Tab"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        NSModalResponse res = [alert runModal];
        if (res == NSAlertSecondButtonReturn) {
            tab.dirty = NO;
            [self closeTab:tab];
        } else {
            tab.path = nil;
            tab.title = [NSString stringWithFormat:@"%@ (Deleted)", tab.title];
            tab.dirty = YES;
            [self updateTabHeaderLayout];
            [self updateWindowTitleAndStatus];
        }
        return;
    }
    
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tab.path error:nil];
    NSDate* diskModDate = attrs.fileModificationDate;
    if (tab.lastModifiedDate && [diskModDate compare:tab.lastModifiedDate] == NSOrderedDescending) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Modified Externally"];
        [alert setInformativeText:[NSString stringWithFormat:@"The file '%@' has been modified by another program. Do you want to reload it and discard your local edits?", tab.title]];
        [alert addButtonWithTitle:@"Reload File"];
        [alert addButtonWithTitle:@"Ignore"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        NSModalResponse res = [alert runModal];
        if (res == NSAlertFirstButtonReturn) {
            const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(tab.path)));
            if (result.ok) {
                self.loadingDocument = YES;
                [tab.textView setString:NSStringFromStdString(result.contents)];
                self.loadingDocument = NO;
                tab.dirty = NO;
                tab.lastModifiedDate = diskModDate;
                [self updateTabHeaderLayout];
                [self updateWindowTitleAndStatus];
            }
        } else {
            tab.lastModifiedDate = diskModDate;
        }
    }
}

- (void)saveOpenTabsState {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* paths = [NSMutableArray array];
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.path) {
            [paths addObject:tab.path];
        }
    }
    [defaults setObject:paths forKey:@"OpenTabsPaths"];
    if (self.activeTab && self.activeTab.path) {
        [defaults setObject:self.activeTab.path forKey:@"ActiveTabPath"];
    } else {
        [defaults removeObjectForKey:@"ActiveTabPath"];
    }
    [defaults synchronize];
}

- (void)restoreOpenTabs {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray* paths = [defaults stringArrayForKey:@"OpenTabsPaths"];
    NSString* activePath = [defaults stringForKey:@"ActiveTabPath"];
    
    if (paths.count == 0) return;
    
    DietCodeTabState* activeTab = nil;
    for (NSString* path in paths) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(path)));
            if (result.ok) {
                [self showEditorWithText:NSStringFromStdString(result.contents) path:path dirty:NO];
                
                NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
                self.activeTab.lastModifiedDate = attrs.fileModificationDate;
                
                if ([path isEqualToString:activePath]) {
                    activeTab = self.activeTab;
                }
            }
        }
    }
    
    if (activeTab) {
        [self activateTab:activeTab];
    } else if (self.openTabs.count > 0) {
        [self activateTab:[self.openTabs lastObject]];
    }
}

- (void)addPlaceholder:(NSString*)placeholder toTextView:(NSTextView*)textView {
    NSTextField* label = [NSTextField labelWithString:placeholder];
    [label setFont:[NSFont systemFontOfSize:13]];
    [label setTextColor:[NSColor placeholderTextColor]];
    [label setLineBreakMode:NSLineBreakByWordWrapping];
    [label setAlignment:NSTextAlignmentCenter];
    [label setTranslatesAutoresizingMaskIntoConstraints:NO];
    [textView addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:textView.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:textView.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:textView.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:textView.trailingAnchor constant:-20]
    ]];
    
    [label setIdentifier:@"PlaceholderLabel"];
}

- (void)updatePlaceholderVisibility:(NSTextView*)textView {
    NSTextField* placeholder = nil;
    for (NSView* subview in [textView subviews]) {
        if ([subview.identifier isEqualToString:@"PlaceholderLabel"]) {
            placeholder = (NSTextField*)subview;
            break;
        }
    }
    if (placeholder) {
        [placeholder setHidden:(textView.string.length > 0)];
    }
}

- (void)addToRecentFolders:(NSString*)path {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* recents = [[defaults stringArrayForKey:@"RecentFolders"] mutableCopy] ?: [NSMutableArray array];
    [recents removeObject:path];
    [recents insertObject:path atIndex:0];
    if (recents.count > 5) {
        [recents removeLastObject];
    }
    [defaults setObject:recents forKey:@"RecentFolders"];
    [defaults synchronize];
}

- (void)addToRecentFiles:(NSString*)path {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* recents = [[defaults stringArrayForKey:@"RecentFiles"] mutableCopy] ?: [NSMutableArray array];
    [recents removeObject:path];
    [recents insertObject:path atIndex:0];
    if (recents.count > 5) {
        [recents removeLastObject];
    }
    [defaults setObject:recents forKey:@"RecentFiles"];
    [defaults synchronize];
}

- (void)openRecentFolderClicked:(NSButton*)sender {
    NSString* path = sender.identifier;
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        self.openedFolderPath = path;
        [self.directoryCache removeAllObjects];
        [self.fileTreeView reloadData];
        [self selectActivity:@"files"];
        [self addToRecentFolders:path];
        [self refreshFilesTree:nil];
    } else {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray* recents = [[defaults stringArrayForKey:@"RecentFolders"] mutableCopy];
        [recents removeObject:path];
        [defaults setObject:recents forKey:@"RecentFolders"];
        [defaults synchronize];
        [self showWelcome:nil];
    }
}

- (void)applyLargeFileModeForTab:(DietCodeTabState*)tab readOnly:(BOOL)readOnly {
    [tab.textView.textContainer setWidthTracksTextView:NO];
    [tab.textView.textContainer setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    
    if (readOnly) {
        [tab.textView setEditable:NO];
    }
    
    [tab.scrollView setRulersVisible:NO];
    [tab.textView.layoutManager setBackgroundLayoutEnabled:YES];
    [self updateWindowTitleAndStatus];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    if (splitView == self.horizontalSplit) {
        return subview == self.sidebarView;
    } else if (splitView == self.verticalSplit) {
        return subview == self.bottomPanel;
    }
    return NO;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview {
    if (splitView == self.horizontalSplit) {
        return subview != self.sidebarView;
    } else if (splitView == self.verticalSplit) {
        return subview != self.bottomPanel;
    }
    return YES;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.horizontalSplit && dividerIndex == 0) {
        return 150;
    }
    return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.horizontalSplit && dividerIndex == 0) {
        return 400;
    }
    return proposedMaximumPosition;
}

- (void)newFile:(id)sender {
    [self showEditorWithText:@"" path:nil dirty:YES];
}

- (void)openFile:(id)sender {
    std::optional<std::filesystem::path> selected = fileDialog_.openFile();
    if (!selected.has_value()) {
        return;
    }
    [self openFileFromPath:NSStringFromStdString(selected->string())];
}

- (void)openFileFromPath:(NSString*)path {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        [self showErrorWithTitle:@"File Not Found"
                    whatHappened:@"The file does not exist at the specified path."
                          nextStep:@"Check the file path or make sure it has not been moved."
                            safety:@"No files were changed."
                           details:[NSString stringWithFormat:@"Path: %@", path]];
        return;
    }
    if (isDir) {
        [self showErrorWithTitle:@"Cannot Open Directory"
                    whatHappened:@"The path points to a directory, not a file."
                          nextStep:@"Use Open Folder... to browse directories."
                            safety:@"No files were changed."
                           details:[NSString stringWithFormat:@"Path: %@", path]];
        return;
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [self showErrorWithTitle:@"Permission Denied"
                    whatHappened:@"DietCode does not have permission to read this file."
                          nextStep:@"Check the file's permissions in Finder."
                            safety:@"No files were changed."
                           details:[NSString stringWithFormat:@"Path: %@", path]];
        return;
    }

    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = [attrs fileSize];
    unsigned long long threshold = 50 * 1024 * 1024; // 50MB
    
    BOOL openReadOnly = NO;
    BOOL isLargeFile = NO;
    
    if (fileSize >= threshold) {
        isLargeFile = YES;
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Large File Warning"];
        [alert setInformativeText:@"This file is large, so some features are reduced to keep DietCode responsive."];
        [alert addButtonWithTitle:@"Open"];
        [alert addButtonWithTitle:@"Open Read-Only"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        NSModalResponse res = [alert runModal];
        if (res == NSAlertThirdButtonReturn) {
            return; // Cancel
        } else if (res == NSAlertSecondButtonReturn) {
            openReadOnly = YES;
        }
    }

    const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(path)));
    if (!result.ok) {
        [self showErrorWithTitle:@"Could not open file."
                    whatHappened:@"DietCode could not read this file."
                          nextStep:@"Try a different file or check that you have permission to open it."
                            safety:@"No files were changed."
                           details:NSStringFromStdString(result.error)];
        return;
    }

    [self showEditorWithText:NSStringFromStdString(result.contents)
                        path:path
                       dirty:NO];
    
    self.activeTab.lastModifiedDate = attrs.fileModificationDate;
    
    if (isLargeFile) {
        [self applyLargeFileModeForTab:self.activeTab readOnly:openReadOnly];
    }
    
    [self addToRecentFiles:path];
}

- (void)openFolder:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Choose a directory workspace for DietCode."];

    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = [[panel URLs] firstObject];
        if (url != nil && [url path] != nil) {
            self.openedFolderPath = [url path];
            [self addToRecentFolders:self.openedFolderPath];
            [self refreshFilesTree:nil];
            [self selectActivity:@"files"];
        }
    }
}

- (void)saveFile:(id)sender {
    if (self.activeTab == nil) return;
    [self saveTab:self.activeTab];
}

- (void)saveTab:(DietCodeTabState*)tab {
    if (tab.path == nil) {
        std::optional<std::filesystem::path> selected = fileDialog_.saveFile();
        if (!selected.has_value()) {
            return;
        }
        tab.path = NSStringFromStdString(selected->string());
        tab.title = [tab.path lastPathComponent];
    }
    
    // Check if directory exists and write permission is granted
    NSString* dir = [tab.path stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
        [self showErrorWithTitle:@"Folder Not Found"
                    whatHappened:@"The parent folder for this file path does not exist."
                          nextStep:@"Use Save As to choose a different folder."
                            safety:@"Your changes are still open in DietCode."
                           details:[NSString stringWithFormat:@"Folder: %@", dir]];
        return;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:tab.path] && ![[NSFileManager defaultManager] isWritableFileAtPath:tab.path]) {
        [self showErrorWithTitle:@"Permission Denied"
                    whatHappened:@"The file exists but is write-protected."
                          nextStep:@"Change the file's write permissions or use Save As to choose another path."
                            safety:@"Your changes are still open in DietCode."
                           details:[NSString stringWithFormat:@"Path: %@", tab.path]];
        return;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:dir] && ![[NSFileManager defaultManager] isWritableFileAtPath:dir]) {
        [self showErrorWithTitle:@"Permission Denied"
                    whatHappened:@"DietCode does not have permission to write to this folder."
                          nextStep:@"Choose a folder where you have write access."
                            safety:@"Your changes are still open in DietCode."
                           details:[NSString stringWithFormat:@"Folder: %@", dir]];
        return;
    }
    
    const std::string contents = StdStringFromNSString([tab.textView string]);
    const auto result = fileService_.writeTextFile(std::filesystem::path(StdStringFromNSString(tab.path)), contents);
    if (!result.ok) {
        [self showErrorWithTitle:@"Could not save file."
                    whatHappened:@"DietCode could not write to this location."
                          nextStep:@"Try Save As and choose another folder."
                            safety:@"Your changes are still open in DietCode."
                           details:NSStringFromStdString(result.error)];
        return;
    }

    tab.dirty = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveBackupForTab:) object:tab];
    [self deleteBackupForTab:tab];
    
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:tab.path error:nil];
    tab.lastModifiedDate = attrs.fileModificationDate;
    
    [self saveOpenTabsState];
    [self updateTabHeaderLayout];
    [self updateWindowTitleAndStatus];
    [self refreshFilesTree:nil]; // Reload in case it was a new file
}

- (void)saveFileAs:(id)sender {
    if (self.activeTab == nil) return;
    
    std::optional<std::filesystem::path> selected = fileDialog_.saveFile();
    if (!selected.has_value()) {
        return;
    }
    
    NSString* newPath = NSStringFromStdString(selected->string());
    
    // Check if this path is already open in another tab
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab != self.activeTab && [tab.path isEqualToString:newPath]) {
            NSAlert* alert = [[NSAlert alloc] init];
            [alert setMessageText:@"File Already Open"];
            [alert setInformativeText:[NSString stringWithFormat:@"'%@' is already open in another tab. Please close that tab first, or save to a different file.", [newPath lastPathComponent]]];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            return;
        }
    }
    
    [self deleteBackupForTab:self.activeTab];
    
    self.activeTab.path = newPath;
    self.activeTab.title = [self.activeTab.path lastPathComponent];
    [self saveTab:self.activeTab];
}

// --- Text view changes ---
- (void)textDidChange:(NSNotification*)notification {
    if (!self.loadingDocument && self.activeTab != nil) {
        self.activeTab.dirty = YES;
        [self updateTabHeaderLayout];
        [self updateWindowTitleAndStatus];
        
        if (self.currentAutoSave) {
            [self saveTab:self.activeTab];
        } else {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveBackupForTab:) object:self.activeTab];
            [self performSelector:@selector(saveBackupForTab:) withObject:self.activeTab afterDelay:1.0];
        }
        [self saveOpenTabsState];
    }
}

- (void)textViewDidChangeSelection:(NSNotification*)notification {
    [self updateWindowTitleAndStatus];
}

- (BOOL)hasUnsavedChanges {
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.dirty) return YES;
    }
    return NO;
}

- (BOOL)confirmCloseIfNeeded {
    if (![self hasUnsavedChanges]) {
        return YES;
    }

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Save your changes before closing?"];
    [alert setInformativeText:@"Your files have unsaved changes. You can save them, keep editing, or close without saving."];
    [alert addButtonWithTitle:@"Save All"];
    [alert addButtonWithTitle:@"Keep Editing"];
    [alert addButtonWithTitle:@"Close Without Saving"];
    [alert setAlertStyle:NSAlertStyleWarning];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        for (DietCodeTabState* tab in [self.openTabs copy]) {
            [self saveTab:tab];
        }
        return ![self hasUnsavedChanges];
    }
    if (response == NSAlertSecondButtonReturn) {
        return NO;
    }
    
    // Reset dirty flags to force quit and delete backups
    for (DietCodeTabState* tab in self.openTabs) {
        [self deleteBackupForTab:tab];
        tab.dirty = NO;
    }
    return YES;
}

- (void)windowWillClose:(NSNotification*)notification {
    [NSApp terminate:nil];
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
    return [self confirmCloseIfNeeded];
}

- (void)updateWindowTitleAndStatus {
    NSString* displayName = self.activeTab == nil ? @"No active document" : self.activeTab.title;
    NSString* dirtyPrefix = [self hasUnsavedChanges] ? @"● " : @"";
    NSString* title = self.activeTab != nil ? [NSString stringWithFormat:@"%@%@ — DietCode", dirtyPrefix, displayName] : @"DietCode";
    [[self window] setTitle:title];

    NSString* savedState = (self.activeTab && self.activeTab.dirty) ? @"Unsaved" : @"Saved";
    NSString* cursorText = @"Line 1, Column 1";
    NSString* langText = @"Plain Text";
    
    if (self.textView != nil) {
        NSRange selected = [self.textView selectedRange];
        NSString* content = [self.textView string] ?: @"";
        NSUInteger line = 1;
        NSUInteger column = 1;
        NSUInteger index = 0;
        while (index < selected.location && index < [content length]) {
            unichar ch = [content characterAtIndex:index];
            if (ch == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
            index += 1;
        }
        cursorText = [NSString stringWithFormat:@"Line %lu, Column %lu", (unsigned long)line, (unsigned long)column];
        
        // Simple language detection based on extension
        if (self.activeTab.path != nil) {
            NSString* ext = [[self.activeTab.path pathExtension] lowercaseString];
            if ([ext isEqualToString:@"py"]) {
                langText = @"Python";
            } else if ([ext isEqualToString:@"cpp"] || [ext isEqualToString:@"cc"] || [ext isEqualToString:@"hpp"] || [ext isEqualToString:@"h"]) {
                langText = @"C++";
            } else if ([ext isEqualToString:@"js"]) {
                langText = @"JavaScript";
            } else if ([ext isEqualToString:@"md"]) {
                langText = @"Markdown";
            } else if ([ext isEqualToString:@"sh"] || [ext isEqualToString:@"zsh"]) {
                langText = @"Shell Script";
            }
        }
    }

    [self.statusLabel setStringValue:[NSString stringWithFormat:@"%@ • %@ • %@ • %@", displayName, savedState, langText, cursorText]];
}

- (void)showErrorWithTitle:(NSString*)title
              whatHappened:(NSString*)whatHappened
                  nextStep:(NSString*)nextStep
                    safety:(NSString*)safety
                   details:(NSString*)details {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:title];
    NSString* informative = [NSString stringWithFormat:@"%@\n\n%@\n\n%@\n\nDetails: %@", whatHappened, nextStep, safety, details ?: @"No extra details."];
    [alert setInformativeText:informative];
    [alert addButtonWithTitle:@"OK"];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert runModal];
}

// --- Preferences Actions ---

- (void)settingsChanged:(id)sender {
    NSInteger newSize = [self.fontSizeField integerValue];
    if (newSize >= 10 && newSize <= 24) {
        self.currentFontSize = newSize;
    }
    
    self.currentWordWrap = ([self.wordWrapBtn state] == NSControlStateValueOn);
    self.currentAutoSave = ([self.autoSaveBtn state] == NSControlStateValueOn);
    
    // Save to NSUserDefaults
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentFontSize forKey:@"FontSize"];
    [defaults setBool:self.currentWordWrap forKey:@"WordWrap"];
    [defaults setBool:self.currentAutoSave forKey:@"AutoSave"];
    [defaults synchronize];
    
    // Live update editor font & wrap
    for (DietCodeTabState* tab in self.openTabs) {
        [tab.textView setFont:[NSFont monospacedSystemFontOfSize:self.currentFontSize weight:NSFontWeightRegular]];
        [tab.textView.textContainer setWidthTracksTextView:self.currentWordWrap];
    }
}

- (void)themeChanged:(NSPopUpButton*)sender {
    self.currentThemeIndex = [sender indexOfSelectedItem];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.currentThemeIndex forKey:@"ThemeIndex"];
    [defaults synchronize];
    
    [self applyThemeColors];
}

// --- Folder Outline View Datasource & Delegate ---

- (NSArray<NSString*>*)childrenOfDirectory:(NSString*)path {
    if (path == nil) {
        return @[];
    }
    
    NSArray<NSString*>* cached = self.directoryCache[path];
    if (cached != nil) {
        return cached;
    }
    
    NSError* error = nil;
    NSArray<NSString*>* filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (error != nil || filenames == nil) {
        return @[];
    }
    
    NSMutableArray<NSString*>* fullPaths = [NSMutableArray array];
    for (NSString* file in filenames) {
        if ([file hasPrefix:@"."] || isPathExcluded(std::filesystem::path(StdStringFromNSString(file)))) {
            continue;
        }
        [fullPaths addObject:[path stringByAppendingPathComponent:file]];
    }
    
    [fullPaths sortUsingComparator:^NSComparisonResult(NSString* a, NSString* b) {
        BOOL aDir = NO;
        BOOL bDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:a isDirectory:&aDir];
        [[NSFileManager defaultManager] fileExistsAtPath:b isDirectory:&bDir];
        if (aDir != bDir) {
            return aDir ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a compare:b options:NSCaseInsensitiveSearch];
    }];
    
    self.directoryCache[path] = fullPaths;
    return fullPaths;
}

- (NSInteger)outlineView:(NSOutlineView*)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) {
        if (self.openedFolderPath == nil) return 0;
        return [self childrenOfDirectory:self.openedFolderPath].count;
    }
    return [self childrenOfDirectory:(NSString*)item].count;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:(NSString*)item isDirectory:&isDir];
    return isDir;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        return [self childrenOfDirectory:self.openedFolderPath][index];
    }
    return [self childrenOfDirectory:(NSString*)item][index];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSString* path = (NSString*)item;
    NSTableCellView* cellView = [outlineView makeViewWithIdentifier:@"FileCell" owner:self];
    if (cellView == nil) {
        cellView = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        cellView.identifier = @"FileCell";
        
        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 2, 16, 16)];
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 0, 200, 18)];
        [tf setBordered:NO];
        [tf setDrawsBackground:NO];
        [tf setEditable:NO];
        [tf setSelectable:NO];
        [tf setFont:[NSFont systemFontOfSize:12]];
        
        cellView.imageView = iv;
        cellView.textField = tf;
        [cellView addSubview:iv];
        [cellView addSubview:tf];
    }
    
    NSString* name = [path lastPathComponent];
    cellView.textField.stringValue = name;
    
    NSImage* icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    [icon setSize:NSMakeSize(16, 16)];
    cellView.imageView.image = icon;
    
    return cellView;
}

- (void)fileTreeDoubleClicked:(id)sender {
    NSInteger row = [self.fileTreeView clickedRow];
    if (row >= 0) {
        NSString* path = [self.fileTreeView itemAtRow:row];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
            if (isDir) {
                if ([self.fileTreeView isItemExpanded:path]) {
                    [self.fileTreeView collapseItem:path];
                } else {
                    [self.fileTreeView expandItem:path];
                }
            } else {
                [self openFileFromPath:path];
            }
        }
    }
}

- (void)refreshFilesTree:(id)sender {
    [self.directoryCache removeAllObjects];
    [self.fileTreeView reloadData];
    
    BOOL hasFolder = (self.openedFolderPath != nil);
    [self.fileTreeEmptyStateView setHidden:hasFolder];
    [[self.fileTreeView superview].superview setHidden:!hasFolder];
}

// Outline Context Actions

- (NSString*)getSelectedOutlinePath {
    NSInteger row = [self.fileTreeView clickedRow];
    if (row < 0) {
        row = [self.fileTreeView selectedRow];
    }
    if (row >= 0) {
        return [self.fileTreeView itemAtRow:row];
    }
    return self.openedFolderPath;
}

- (void)newFileClicked:(id)sender {
    NSString* targetDir = [self getSelectedOutlinePath];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:targetDir isDirectory:&isDir];
    if (!isDir) {
        targetDir = [targetDir stringByDeletingLastPathComponent];
    }
    if (targetDir == nil) return;

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"New File"];
    [alert setInformativeText:@"Enter name for new file:"];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@"untitled.txt"];
    [alert setAccessoryView:input];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* name = [input stringValue];
        NSString* fullPath = [targetDir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createFileAtPath:fullPath contents:[NSData data] attributes:nil];
        [self refreshFilesTree:nil];
        [self openFileFromPath:fullPath];
    }
}

- (void)newFolderClicked:(id)sender {
    NSString* targetDir = [self getSelectedOutlinePath];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:targetDir isDirectory:&isDir];
    if (!isDir) {
        targetDir = [targetDir stringByDeletingLastPathComponent];
    }
    if (targetDir == nil) return;

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"New Folder"];
    [alert setInformativeText:@"Enter name for new directory:"];
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:@"NewFolder"];
    [alert setAccessoryView:input];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* name = [input stringValue];
        NSString* fullPath = [targetDir stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:nil];
        [self refreshFilesTree:nil];
    }
}

- (void)renameFileClicked:(id)sender {
    NSString* path = [self getSelectedOutlinePath];
    if (path == nil || [path isEqualToString:self.openedFolderPath]) return;

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Rename File"];
    [alert setInformativeText:@"Enter new name:"];
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:[path lastPathComponent]];
    [alert setAccessoryView:input];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* newName = [input stringValue];
        NSString* newPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        NSError* error = nil;
        [[NSFileManager defaultManager] moveItemAtPath:path toPath:newPath error:&error];
        if (error != nil) {
            [self showErrorWithTitle:@"Rename failed" whatHappened:@"Could not rename file." nextStep:@"Check permission and valid name." safety:@"Your file is safe." details:error.localizedDescription];
        } else {
            // Update open tab path if renaming an opened file
            for (DietCodeTabState* tab in self.openTabs) {
                if ([tab.path isEqualToString:path]) {
                    tab.path = newPath;
                    tab.title = newName;
                }
            }
            [self refreshFilesTree:nil];
            [self updateTabHeaderLayout];
            [self updateWindowTitleAndStatus];
        }
    }
}

- (void)deleteFileClicked:(id)sender {
    NSString* path = [self getSelectedOutlinePath];
    if (path == nil || [path isEqualToString:self.openedFolderPath]) return;

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Confirm Delete"];
    [alert setInformativeText:[NSString stringWithFormat:@"Are you sure you want to delete %@? This cannot be undone.", [path lastPathComponent]]];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSError* error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        if (error != nil) {
            [self showErrorWithTitle:@"Delete failed" whatHappened:@"Could not remove file." nextStep:@"Check file locking/permissions." safety:@"File may still exist." details:error.localizedDescription];
        } else {
            // Close tab if deleted
            DietCodeTabState* toClose = nil;
            for (DietCodeTabState* tab in self.openTabs) {
                if ([tab.path isEqualToString:path]) {
                    toClose = tab;
                    break;
                }
            }
            if (toClose) {
                toClose.dirty = NO; // Force close
                [self closeTab:toClose];
            }
            [self refreshFilesTree:nil];
        }
    }
}

- (void)revealInFinderClicked:(id)sender {
    NSString* path = [self getSelectedOutlinePath];
    if (path != nil) {
        [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
    }
}

// --- Workspace Search Background Thread Implementation ---

- (void)startWorkspaceSearch:(id)sender {
    if (self.openedFolderPath == nil) {
        [self appendSearchResult:@"Please open a folder workspace first.\n"];
        [self selectActivity:@"search"];
        return;
    }
    
    NSView* searchPanel = self.searchSidebarView;
    NSTextField* searchInput = nil;
    NSButton* caseCheck = nil;
    
    for (NSView* v in [[searchPanel subviews][0] arrangedSubviews]) {
        if ([v.identifier isEqualToString:@"SearchInput"]) {
            searchInput = (NSTextField*)v;
        } else if ([v.identifier isEqualToString:@"CaseSensitive"]) {
            caseCheck = (NSButton*)v;
        }
    }
    
    NSString* query = searchInput.stringValue;
    if (query.length == 0) return;
    
    BOOL caseSensitive = (caseCheck.state == NSControlStateValueOn);
    
    // Clear old
    [self.searchResultsTextView setString:@""];
    [self updatePlaceholderVisibility:self.searchResultsTextView];
    self.searchCancelled = NO;
    
    [self selectActivity:@"search"];
    [self.bottomTabView selectTabViewItemWithIdentifier:@"search"];
    [self.bottomPanel setHidden:NO];
    
    [self appendSearchResult:[NSString stringWithFormat:@"Searching for '%@' in %@...\n\n", query, self.openedFolderPath]];

    std::string stdQuery = StdStringFromNSString(query);
    std::string folder = StdStringFromNSString(self.openedFolderPath);
    
    // Run async background dispatch queue
    __weak DietCodeWindowController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DietCodeWindowController* strongSelf = weakSelf;
        if (!strongSelf) return;
        
        std::error_code ec;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(folder, ec)) {
            if (strongSelf.searchCancelled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [strongSelf appendSearchResult:@"\nSearch cancelled.\n"];
                });
                return;
            }
            
            if (entry.is_regular_file()) {
                std::filesystem::path p = entry.path();
                if (isPathExcluded(p)) {
                    continue;
                }
                
                // Read text and find matches
                auto readRes = strongSelf->fileService_.readTextFile(p);
                if (readRes.ok) {
                    dietcode::editor::TextBuffer tempBuf(readRes.contents);
                    auto matches = dietcode::search::findInFile(tempBuf, stdQuery, {.caseSensitive = (bool)caseSensitive});
                    if (!matches.empty()) {
                        NSString* filePath = NSStringFromStdString(p.string());
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [strongSelf appendSearchResult:[NSString stringWithFormat:@"File: %@\n", filePath]];
                            for (const auto& m : matches) {
                                [strongSelf appendSearchResult:[NSString stringWithFormat:@"  Line %zu, Col %zu: %s\n", m.line + 1, m.column + 1, m.lineText.c_str()]];
                            }
                            [strongSelf appendSearchResult:@"\n"];
                        });
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf appendSearchResult:@"Search finished.\n"];
        });
    });
}

- (void)cancelWorkspaceSearch:(id)sender {
    self.searchCancelled = YES;
}

- (void)appendSearchResult:(NSString*)text {
    NSTextStorage* storage = self.searchResultsTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor textColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.searchResultsTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    [self updatePlaceholderVisibility:self.searchResultsTextView];
}

// --- Run and Output Pipeline ---

- (void)runCurrentFile:(id)sender {
    if (self.activeTab == nil) return;
    
    // Save first
    [self saveTab:self.activeTab];
    if (self.activeTab.path == nil) return;
    
    NSString* filePath = self.activeTab.path;
    NSString* ext = [[filePath pathExtension] lowercaseString];
    
    [self.outputTextView setString:@""];
    [self.errorsTextView setString:@""];
    [self updatePlaceholderVisibility:self.outputTextView];
    [self updatePlaceholderVisibility:self.errorsTextView];
    
    [self.bottomTabView selectTabViewItemWithIdentifier:@"output"];
    [self.bottomPanel setHidden:NO];
    [self.runStatusLabel setStringValue:@"Running..."];
    [self.runExplanationLabel setStringValue:@""];
    
    // Enable/disable buttons
    for (NSView* v in [[self.runSidebarView subviews][0] arrangedSubviews]) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* b = (NSButton*)v;
            if ([b.title isEqualToString:@"Run File"]) [b setEnabled:NO];
            if ([b.title isEqualToString:@"Stop File"]) [b setEnabled:YES];
        }
    }
    
    NSString* command = nil;
    NSArray* args = nil;
    
    if ([ext isEqualToString:@"py"]) {
        command = @"/usr/bin/python3";
        args = @[filePath];
    } else if ([ext isEqualToString:@"js"]) {
        command = @"/usr/local/bin/node";
        // fallback search in PATH
        if (![[NSFileManager defaultManager] fileExistsAtPath:command]) {
            command = @"/usr/bin/env";
            args = @[@"node", filePath];
        } else {
            args = @[filePath];
        }
    } else if ([ext isEqualToString:@"cpp"] || [ext isEqualToString:@"cc"]) {
        // Compile first
        [self runCPPCompilation:filePath];
        return;
    } else {
        // Default run shell script
        command = @"/bin/zsh";
        args = @[filePath];
    }
    
    [self executeTask:command arguments:args];
}

- (void)runCPPCompilation:(NSString*)filePath {
    [self.runStatusLabel setStringValue:@"Compiling C++..."];
    
    NSString* outPath = @"/tmp/dietcode_cpp_run";
    NSTask* compileTask = [[NSTask alloc] init];
    [compileTask setLaunchPath:@"/usr/bin/clang++"];
    [compileTask setArguments:@[@"-std=c++20", @"-Wall", @"-Wextra", filePath, @"-o", outPath]];
    
    NSPipe* errPipe = [NSPipe pipe];
    [compileTask setStandardError:errPipe];
    [compileTask setStandardOutput:errPipe];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            [compileTask launch];
            [compileTask waitUntilExit];
            
            NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
            NSString* errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (compileTask.terminationStatus == 0) {
                    // Success compile! Now run
                    [self executeTask:outPath arguments:@[]];
                } else {
                    [self appendErrorText:errText];
                    [self updateRunStatus:@"Compilation Failed" success:NO];
                    [self.bottomTabView selectTabViewItemWithIdentifier:@"errors"];
                }
            });
        } @catch (NSException* exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendErrorText:@"Could not launch compiler /usr/bin/clang++\n"];
                [self updateRunStatus:@"Compiler not found" success:NO];
            });
        }
    });
}

- (void)executeTask:(NSString*)launchPath arguments:(NSArray*)args {
    self.currentRunTask = [[NSTask alloc] init];
    [self.currentRunTask setLaunchPath:launchPath];
    [self.currentRunTask setArguments:args];
    
    NSPipe* pipe = [NSPipe pipe];
    [self.currentRunTask setStandardOutput:pipe];
    [self.currentRunTask setStandardError:pipe];
    
    NSFileHandle* file = [pipe fileHandleForReading];
    
    @try {
        [self.currentRunTask launch];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (true) {
                NSData* data = [file availableData];
                if (data.length == 0) break;
                NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendOutputText:text];
                });
            }
            [self.currentRunTask waitUntilExit];
            int status = self.currentRunTask.terminationStatus;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateRunStatus:[NSString stringWithFormat:@"Finished (Exit Code %d)", status] success:(status == 0)];
            });
        });
    } @catch (NSException* e) {
        [self appendOutputText:[NSString stringWithFormat:@"Failed to run file: %@\n", e.reason]];
        [self updateRunStatus:@"Runtime not found" success:NO];
        [self.runExplanationLabel setStringValue:@"Ensure compiler or runtime (Python/Node) is installed and available."];
    }
}

- (void)stopCurrentFile:(id)sender {
    if (self.currentRunTask && [self.currentRunTask isRunning]) {
        [self.currentRunTask terminate];
        [self updateRunStatus:@"Stopped" success:NO];
    }
}

- (void)updateRunStatus:(NSString*)status success:(BOOL)ok {
    [self.runStatusLabel setStringValue:status];
    [self.runExplanationLabel setStringValue:ok ? @"Executed successfully" : @"Execution stopped or returned errors."];
    
    for (NSView* v in [[self.runSidebarView subviews][0] arrangedSubviews]) {
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton* b = (NSButton*)v;
            if ([b.title isEqualToString:@"Run File"]) [b setEnabled:YES];
            if ([b.title isEqualToString:@"Stop File"]) [b setEnabled:NO];
        }
    }
}

- (void)appendOutputText:(NSString*)text {
    NSTextStorage* storage = self.outputTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor textColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.outputTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    [self updatePlaceholderVisibility:self.outputTextView];
}

- (void)appendErrorText:(NSString*)text {
    NSTextStorage* storage = self.errorsTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor systemRedColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.errorsTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
    [self updatePlaceholderVisibility:self.errorsTextView];
}

// --- Interactive PTY Terminal Creator ---

- (void)setupTerminalProcess {
    struct termios ios;
    memset(&ios, 0, sizeof(ios));
    cfmakeraw(&ios);
    ios.c_cflag |= CS8;
    
    int masterFd = -1;
    pid_t pid = forkpty(&masterFd, NULL, &ios, NULL);
    if (pid < 0) {
        [self appendTerminalText:@"Could not launch local pseudo-terminal pty.\n"];
        return;
    }
    
    if (pid == 0) {
        // Child shell
        setenv("TERM", "xterm-256color", 1);
        char* argv[] = { (char*)"/bin/zsh", (char*)"-l", NULL };
        execve(argv[0], argv, environ);
        // sh Fallback
        char* argvSh[] = { (char*)"/bin/sh", NULL };
        execve(argvSh[0], argvSh, environ);
        exit(1);
    }
    
    // Parent PTY manager
    terminalMasterFd_ = masterFd;
    terminalPid_ = pid;
    self.terminalTextView.masterFd = masterFd;
    
    // Start background reader thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buf[1024];
        while (true) {
            ssize_t bytes = read(masterFd, buf, sizeof(buf) - 1);
            if (bytes <= 0) break;
            buf[bytes] = '\0';
            
            // Safe UTF8 conversion
            NSString* text = [NSString stringWithUTF8String:buf];
            if (text == nil) {
                text = [[NSString alloc] initWithBytes:buf length:bytes encoding:NSASCIIStringEncoding];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendTerminalText:text];
            });
        }
    });
}

- (void)appendTerminalText:(NSString*)text {
    NSTextStorage* storage = self.terminalTextView.textStorage;
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSForegroundColorAttributeName: [NSColor textColor],
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
    }]];
    [storage endEditing];
    [self.terminalTextView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

// --- Command Palette Panel ---

- (void)setupCommandPalette {
    self.commandPaletteActions = [NSMutableArray arrayWithArray:@[
        @{@"title": @"File: New File", @"action": @"newFile:"},
        @{@"title": @"File: Open File...", @"action": @"openFile:"},
        @{@"title": @"File: Open Folder...", @"action": @"openFolder:"},
        @{@"title": @"File: Save", @"action": @"saveFile:"},
        @{@"title": @"File: Save As...", @"action": @"saveFileAs:"},
        @{@"title": @"View: Toggle Sidebar", @"action": @"toggleSidebar:"},
        @{@"title": @"View: Toggle Terminal", @"action": @"toggleTerminal:"},
        @{@"title": @"View: Open Welcome Screen", @"action": @"showWelcome:"},
        @{@"title": @"Run: Run Current File", @"action": @"runCurrentFile:"},
        @{@"title": @"Go: Go to Line...", @"action": @"goToLine:"},
        @{@"title": @"Settings: Open Settings", @"action": @"openSettingsAction"}
    ]];
    self.filteredCommandPaletteActions = self.commandPaletteActions;

    NSRect frame = NSMakeRect(0, 0, 500, 320);
    self.commandPalettePanel = [[DietCodeCommandPalettePanel alloc] initWithContentRect:frame
                                                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                                               backing:NSBackingStoreBuffered
                                                                                 defer:NO];
    [self.commandPalettePanel setTitleVisibility:NSWindowTitleHidden];
    [self.commandPalettePanel setTitlebarAppearsTransparent:YES];
    [self.commandPalettePanel setHasShadow:YES];
    [self.commandPalettePanel setOpaque:NO];
    [self.commandPalettePanel setBackgroundColor:[NSColor clearColor]];

    NSVisualEffectView* effect = [[NSVisualEffectView alloc] initWithFrame:frame];
    [effect setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [effect setMaterial:NSVisualEffectMaterialHUDWindow];
    [effect setState:NSVisualEffectStateActive];
    [effect setWantsLayer:YES];
    [effect.layer setCornerRadius:10.0];
    [self.commandPalettePanel setContentView:effect];

    // Search Box
    self.paletteSearchField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 280, 476, 28)];
    [self.paletteSearchField setPlaceholderString:@"Type a command to run..."];
    [self.paletteSearchField setFont:[NSFont systemFontOfSize:14]];
    [self.paletteSearchField setBordered:NO];
    [self.paletteSearchField setDrawsBackground:NO];
    [self.paletteSearchField setTarget:self];
    [self.paletteSearchField setAction:@selector(paletteSearchChanged:)];
    [self.paletteSearchField setDelegate:self];
    [self.paletteSearchField setAccessibilityLabel:@"Command palette search field"];
    [effect addSubview:self.paletteSearchField];

    // Scrollable command table list
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 12, 476, 256)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setDrawsBackground:NO];
    [effect addSubview:scroll];

    self.paletteTableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    [self.paletteTableView setHeaderView:nil];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"CommandCol"];
    col.width = 476;
    [self.paletteTableView addTableColumn:col];
    [self.paletteTableView setDataSource:self];
    [self.paletteTableView setDelegate:self];
    [self.paletteTableView setAccessibilityLabel:@"Command palette suggestions list"];
    [scroll setDocumentView:self.paletteTableView];
}

- (void)showCommandPalette:(id)sender {
    NSRect parentFrame = [[self window] frame];
    CGFloat x = parentFrame.origin.x + (parentFrame.size.width - 500) / 2;
    CGFloat y = parentFrame.origin.y + parentFrame.size.height - 350;
    [self.commandPalettePanel setFrameOrigin:NSMakePoint(x, y)];

    [self.paletteSearchField setStringValue:@""];
    [self filterPaletteActions:@""];
    
    [[self window] addChildWindow:self.commandPalettePanel ordered:NSWindowAbove];
    [self.commandPalettePanel makeKeyAndOrderFront:self];
    [self.commandPalettePanel makeFirstResponder:self.paletteSearchField];
}

- (void)paletteSearchChanged:(id)sender {
    [self filterPaletteActions:self.paletteSearchField.stringValue];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.paletteSearchField) {
        [self filterPaletteActions:self.paletteSearchField.stringValue];
    }
}

- (void)filterPaletteActions:(NSString*)query {
    if (query.length == 0) {
        self.filteredCommandPaletteActions = self.commandPaletteActions;
    } else {
        NSMutableArray* res = [NSMutableArray array];
        for (NSDictionary* act in self.commandPaletteActions) {
            NSString* title = act[@"title"];
            if ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [res addObject:act];
            }
        }
        self.filteredCommandPaletteActions = res;
    }
    [self.paletteTableView reloadData];
    if (self.filteredCommandPaletteActions.count > 0) {
        [self.paletteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

// TableView DataSource/Delegate for Command Palette

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.paletteTableView) {
        return self.filteredCommandPaletteActions.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.paletteTableView) {
        NSTableCellView* view = [tableView makeViewWithIdentifier:@"CommandCell" owner:self];
        if (view == nil) {
            view = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 476, 24)];
            view.identifier = @"CommandCell";
            NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 2, 460, 20)];
            [tf setBordered:NO];
            [tf setDrawsBackground:NO];
            [tf setEditable:NO];
            [tf setFont:[NSFont systemFontOfSize:13]];
            view.textField = tf;
            [view addSubview:tf];
        }
        view.textField.stringValue = self.filteredCommandPaletteActions[row][@"title"];
        return view;
    }
    return nil;
}

// Intercept Key Events in Search Field
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control == self.paletteSearchField) {
        if (commandSelector == @selector(moveDown:)) {
            NSInteger row = [self.paletteTableView selectedRow];
            if (row < (NSInteger)self.filteredCommandPaletteActions.count - 1) {
                [self.paletteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
                [self.paletteTableView scrollRowToVisible:row + 1];
            }
            return YES;
        } else if (commandSelector == @selector(moveUp:)) {
            NSInteger row = [self.paletteTableView selectedRow];
            if (row > 0) {
                [self.paletteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
                [self.paletteTableView scrollRowToVisible:row - 1];
            }
            return YES;
        } else if (commandSelector == @selector(insertNewline:)) {
            NSInteger row = [self.paletteTableView selectedRow];
            if (row >= 0 && row < (NSInteger)self.filteredCommandPaletteActions.count) {
                NSDictionary* actionDict = self.filteredCommandPaletteActions[row];
                [self closePaletteHUD];
                
                // Execute command
                NSString* actionSelStr = actionDict[@"action"];
                if ([actionSelStr isEqualToString:@"openSettingsAction"]) {
                    [self selectActivity:@"settings"];
                } else {
                    SEL selector = NSSelectorFromString(actionSelStr);
                    if ([self respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [self performSelector:selector withObject:nil];
#pragma clang diagnostic pop
                    }
                }
            }
            return YES;
        } else if (commandSelector == @selector(cancelOperation:)) {
            [self closePaletteHUD];
            return YES;
        }
    }
    return NO;
}

- (void)closePaletteHUD {
    [[self window] removeChildWindow:self.commandPalettePanel];
    [self.commandPalettePanel orderOut:nil];
    if (self.textView) {
        [[self window] makeFirstResponder:self.textView];
    }
}

// --- Go to Line Alert dialog ---

- (void)goToLine:(id)sender {
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Go to Line"];
    [alert setInformativeText:@"Enter target line number:"];
    [alert addButtonWithTitle:@"Jump"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger line = [input integerValue];
        if (line > 0 && self.textView != nil) {
            [self jumpToLine:line];
        }
    }
}

- (void)jumpToLine:(NSInteger)lineNumber {
    NSString* content = [self.textView string];
    NSUInteger currentLine = 1;
    NSUInteger index = 0;
    NSUInteger targetIndex = NSNotFound;
    
    if (lineNumber == 1) {
        targetIndex = 0;
    } else {
        while (index < [content length]) {
            unichar ch = [content characterAtIndex:index];
            if (ch == '\n') {
                currentLine++;
                if (currentLine == (NSUInteger)lineNumber) {
                    targetIndex = index + 1;
                    break;
                }
            }
            index++;
        }
    }
    
    if (targetIndex != NSNotFound && targetIndex <= [content length]) {
        NSRange lineRange = [content lineRangeForRange:NSMakeRange(targetIndex, 0)];
        [self.textView setSelectedRange:NSMakeRange(targetIndex, 0)];
        [self.textView scrollRangeToVisible:lineRange];
        [[self window] makeFirstResponder:self.textView];
    }
}

// --- Welcome Screen view setup ---

- (void)showWelcome:(id)sender {
    if (sender != nil && ![self confirmCloseIfNeeded]) {
        return;
    }

    self.hasDocument = NO;
    self.activeTab = nil;
    self.textView = nil;
    [self updateWindowTitleAndStatus];
    
    // Clear editor hosts and show welcome inner
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

    NSTextField* title = MakeLabel(@"Welcome to DietCode", 34, NSFontWeightBold);
    NSTextField* subtitle = MakeLabel(@"A quiet place to write and run code. Nothing runs unless you ask.", 17, NSFontWeightRegular);
    [subtitle setTextColor:[NSColor secondaryLabelColor]];

    NSTextField* helper = MakeLabel(@"Start by opening a folder workspace or creating/editing a file. Your workspace files will appear in Files on the left.", 14, NSFontWeightRegular);
    [helper setTextColor:[NSColor secondaryLabelColor]];

    NSButton* openFolderBtn = MakeButton(@"Open Folder", self, @selector(openFolder:));
    [openFolderBtn setToolTip:@"Browse and open a full workspace directory."];
    
    NSButton* openButton = MakeButton(@"Open File", self, @selector(openFile:));
    [openButton setToolTip:@"Edit an existing file."];
    
    NSButton* newButton = MakeButton(@"New File", self, @selector(newFile:));
    [newButton setToolTip:@"Start with a blank file."];

    [welcome addArrangedSubview:title];
    [welcome addArrangedSubview:subtitle];

    NSStackView* horizontalWelcome = [[NSStackView alloc] init];
    [horizontalWelcome setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [horizontalWelcome setAlignment:NSLayoutAttributeTop];
    [horizontalWelcome setSpacing:40];
    [welcome addArrangedSubview:horizontalWelcome];
    
    // Left column: Actions
    NSStackView* leftCol = [[NSStackView alloc] init];
    [leftCol setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [leftCol setAlignment:NSLayoutAttributeLeading];
    [leftCol setSpacing:12];
    [horizontalWelcome addArrangedSubview:leftCol];
    
    [leftCol addArrangedSubview:helper];
    [leftCol addArrangedSubview:openFolderBtn];
    [leftCol addArrangedSubview:openButton];
    [leftCol addArrangedSubview:newButton];
    
    // Right column: Recents
    NSStackView* rightCol = [[NSStackView alloc] init];
    [rightCol setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [rightCol setAlignment:NSLayoutAttributeLeading];
    [rightCol setSpacing:12];
    [horizontalWelcome addArrangedSubview:rightCol];
    
    NSTextField* recentsTitle = MakeLabel(@"Recent Projects", 16, NSFontWeightBold);
    [rightCol addArrangedSubview:recentsTitle];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray* recentFolders = [defaults stringArrayForKey:@"RecentFolders"];
    
    if (recentFolders.count > 0) {
        for (NSString* folder in recentFolders) {
            NSButton* btn = [NSButton buttonWithTitle:[folder lastPathComponent] target:self action:@selector(openRecentFolderClicked:)];
            [btn setBezelStyle:NSBezelStyleRecessed];
            [btn setToolTip:folder];
            [btn setIdentifier:folder];
            [rightCol addArrangedSubview:btn];
        }
    } else {
        NSTextField* emptyRecents = MakeLabel(@"No recent folders open yet.", 12, NSFontWeightRegular);
        [emptyRecents setTextColor:[NSColor secondaryLabelColor]];
        [rightCol addArrangedSubview:emptyRecents];
    }
}

- (void)cleanupProcesses {
    if (self.currentRunTask && [self.currentRunTask isRunning]) {
        [self.currentRunTask terminate];
    }
    if (terminalPid_ > 0) {
        kill(terminalPid_, SIGHUP);
    }
}

@end
