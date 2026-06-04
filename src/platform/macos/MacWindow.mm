#include "platform/macos/MacWindow.hpp"

#include "filesystem/FileService.hpp"
#include "platform/macos/MacFileDialog.hpp"

#import <Cocoa/Cocoa.h>

#include <filesystem>
#include <optional>
#include <string>

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

} // namespace

@interface DietCodeWindowController ()
@property(nonatomic, strong) NSView* rootView;
@property(nonatomic, strong) NSStackView* activityBar;
@property(nonatomic, strong) NSView* sidebarView;
@property(nonatomic, strong) NSView* editorHostView;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSTextView* textView;
@property(nonatomic, assign) BOOL dirty;
@property(nonatomic, assign) BOOL loadingDocument;
@property(nonatomic, assign) BOOL hasDocument;
@property(nonatomic, copy) NSString* currentPath;
@end

@implementation DietCodeWindowController {
    dietcode::filesystem::FileService fileService_;
    dietcode::platform::macos::MacFileDialog fileDialog_;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1120, 740);
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
        _dirty = NO;
        _loadingDocument = NO;
        _hasDocument = NO;
        [self buildInterface];
        [self showWelcome:nil];
        [self updateWindowTitleAndStatus];
    }
    return self;
}

- (void)buildInterface {
    self.rootView = [[NSView alloc] initWithFrame:[[self window] contentView].bounds];
    [self.rootView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self window] setContentView:self.rootView];

    NSStackView* vertical = [[NSStackView alloc] initWithFrame:self.rootView.bounds];
    [vertical setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [vertical setSpacing:0];
    [vertical setDistribution:NSStackViewDistributionFill];
    [vertical setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.rootView addSubview:vertical];

    [NSLayoutConstraint activateConstraints:@[
        [vertical.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [vertical.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [vertical.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [vertical.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor]
    ]];

    NSStackView* horizontal = [[NSStackView alloc] init];
    [horizontal setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [horizontal setSpacing:0];
    [horizontal setDistribution:NSStackViewDistributionFill];
    [vertical addArrangedSubview:horizontal];

    self.activityBar = [[NSStackView alloc] init];
    [self.activityBar setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [self.activityBar setAlignment:NSLayoutAttributeCenterX];
    [self.activityBar setSpacing:8];
    [self.activityBar setEdgeInsets:NSEdgeInsetsMake(12, 8, 12, 8)];
    [self.activityBar setWantsLayer:YES];
    [self.activityBar.layer setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.94 alpha:1.0] CGColor]];
    [self.activityBar.widthAnchor constraintEqualToConstant:104].active = YES;

    NSArray<NSString*>* activities = @[@"Files", @"Search", @"Run", @"Errors", @"Settings"];
    for (NSString* label in activities) {
        NSButton* item = [NSButton buttonWithTitle:label target:nil action:nil];
        [item setBezelStyle:NSBezelStyleTexturedRounded];
        [item setControlSize:NSControlSizeRegular];
        [item setToolTip:label];
        [self.activityBar addArrangedSubview:item];
    }

    self.sidebarView = [[NSView alloc] init];
    [self.sidebarView setWantsLayer:YES];
    [self.sidebarView.layer setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.98 alpha:1.0] CGColor]];
    [self.sidebarView.widthAnchor constraintEqualToConstant:260].active = YES;
    [self buildSidebar];

    self.editorHostView = [[NSView alloc] init];
    [self.editorHostView setWantsLayer:YES];
    [self.editorHostView.layer setBackgroundColor:[[NSColor textBackgroundColor] CGColor]];

    [horizontal addArrangedSubview:self.activityBar];
    [horizontal addArrangedSubview:self.sidebarView];
    [horizontal addArrangedSubview:self.editorHostView];

    self.statusLabel = [NSTextField labelWithString:@"No file open • Saved • Plain Text • Line 1, Column 1"];
    [self.statusLabel setFont:[NSFont systemFontOfSize:12]];
    [self.statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [self.statusLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSView* statusBar = [[NSView alloc] init];
    [statusBar setWantsLayer:YES];
    [statusBar.layer setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.93 alpha:1.0] CGColor]];
    [statusBar.heightAnchor constraintEqualToConstant:30].active = YES;
    [statusBar addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor]
    ]];
    [vertical addArrangedSubview:statusBar];
}

- (void)buildSidebar {
    NSStackView* stack = [[NSStackView alloc] init];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setSpacing:12];
    [stack setEdgeInsets:NSEdgeInsetsMake(18, 16, 18, 16)];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.sidebarView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.sidebarView.bottomAnchor]
    ]];

    NSTextField* title = MakeLabel(@"Files", 18, NSFontWeightSemibold);
    NSTextField* empty = MakeLabel(@"Open a folder to see your files here. For this first prototype, start with Open File or New File.", 13, NSFontWeightRegular);
    [empty setTextColor:[NSColor secondaryLabelColor]];

    NSButton* newFileButton = MakeButton(@"New File", self, @selector(newFile:));
    NSButton* openFileButton = MakeButton(@"Open File", self, @selector(openFile:));

    [stack addArrangedSubview:title];
    [stack addArrangedSubview:empty];
    [stack addArrangedSubview:newFileButton];
    [stack addArrangedSubview:openFileButton];
}

- (void)clearEditorHost {
    NSArray<NSView*>* subviews = [self.editorHostView.subviews copy];
    for (NSView* subview in subviews) {
        [subview removeFromSuperview];
    }
}

- (void)showWelcome:(id)sender {
    if (sender != nil && ![self confirmCloseIfNeeded]) {
        return;
    }

    self.hasDocument = NO;
    self.currentPath = nil;
    self.dirty = NO;
    self.textView = nil;
    [self clearEditorHost];

    NSStackView* welcome = [[NSStackView alloc] init];
    [welcome setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [welcome setAlignment:NSLayoutAttributeLeading];
    [welcome setSpacing:16];
    [welcome setEdgeInsets:NSEdgeInsetsMake(48, 56, 48, 56)];
    [welcome setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.editorHostView addSubview:welcome];

    [NSLayoutConstraint activateConstraints:@[
        [welcome.leadingAnchor constraintEqualToAnchor:self.editorHostView.leadingAnchor],
        [welcome.trailingAnchor constraintLessThanOrEqualToAnchor:self.editorHostView.trailingAnchor],
        [welcome.topAnchor constraintEqualToAnchor:self.editorHostView.topAnchor]
    ]];

    NSTextField* title = MakeLabel(@"Welcome to DietCode", 34, NSFontWeightBold);
    NSTextField* subtitle = MakeLabel(@"A quiet place to write and run code. Nothing runs unless you ask.", 17, NSFontWeightRegular);
    [subtitle setTextColor:[NSColor secondaryLabelColor]];

    NSTextField* helper = MakeLabel(@"Start by opening a file or creating a new one. Your files will appear in Files on the left when folder browsing is added.", 14, NSFontWeightRegular);
    [helper setTextColor:[NSColor secondaryLabelColor]];

    NSButton* openButton = MakeButton(@"Open File", self, @selector(openFile:));
    [openButton setToolTip:@"Edit an existing file."];
    NSButton* newButton = MakeButton(@"New File", self, @selector(newFile:));
    [newButton setToolTip:@"Start with a blank file."];

    NSButton* folderButton = MakeButton(@"Open Folder (Phase 2)", nil, nil);
    [folderButton setEnabled:NO];
    [folderButton setToolTip:@"Folder browsing is planned for Phase 2."];

    [welcome addArrangedSubview:title];
    [welcome addArrangedSubview:subtitle];
    [welcome addArrangedSubview:helper];
    [welcome addArrangedSubview:openButton];
    [welcome addArrangedSubview:newButton];
    [welcome addArrangedSubview:folderButton];

    [self updateWindowTitleAndStatus];
}

- (void)showEditorWithText:(NSString*)text path:(NSString*)path dirty:(BOOL)isDirty {
    [self clearEditorHost];
    self.hasDocument = YES;
    self.currentPath = path;
    self.dirty = isDirty;

    NSScrollView* scrollView = [[NSScrollView alloc] init];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutohidesScrollers:NO];
    [scrollView setBorderType:NSNoBorder];
    [scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSTextView* editor = [[NSTextView alloc] init];
    [editor setMinSize:NSMakeSize(0.0, 0.0)];
    [editor setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor setVerticallyResizable:YES];
    [editor setHorizontallyResizable:YES];
    [editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [editor.textContainer setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor.textContainer setWidthTracksTextView:NO];
    [editor setFont:[NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular]];
    [editor setRichText:NO];
    [editor setAutomaticQuoteSubstitutionEnabled:NO];
    [editor setAutomaticDashSubstitutionEnabled:NO];
    [editor setAutomaticTextReplacementEnabled:NO];
    [editor setAllowsUndo:YES];
    [editor setDelegate:self];

    self.loadingDocument = YES;
    [editor setString:text ?: @""];
    [editor setAccessibilityLabel:@"DietCode editor"];

    self.textView = editor;
    [scrollView setDocumentView:editor];
    [self.editorHostView addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:self.editorHostView.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.editorHostView.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.editorHostView.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.editorHostView.bottomAnchor]
    ]];
    self.loadingDocument = NO;

    [[self window] makeFirstResponder:editor];
    [self updateWindowTitleAndStatus];
}

- (void)newFile:(id)sender {
    if (![self confirmCloseIfNeeded]) {
        return;
    }
    [self showEditorWithText:@"" path:nil dirty:YES];
}

- (void)openFile:(id)sender {
    if (![self confirmCloseIfNeeded]) {
        return;
    }

    std::optional<std::filesystem::path> selected = fileDialog_.openFile();
    if (!selected.has_value()) {
        return;
    }

    const auto result = fileService_.readTextFile(*selected);
    if (!result.ok) {
        [self showErrorWithTitle:@"Could not open file."
                    whatHappened:@"DietCode could not read this file."
                        nextStep:@"Try a different file or check that you have permission to open it."
                          safety:@"No files were changed."
                         details:NSStringFromStdString(result.error)];
        return;
    }

    [self showEditorWithText:NSStringFromStdString(result.contents)
                        path:NSStringFromStdString(selected->string())
                       dirty:NO];
}

- (void)saveFile:(id)sender {
    if (!self.hasDocument || self.textView == nil) {
        return;
    }

    if (self.currentPath == nil) {
        [self saveFileAs:sender];
        return;
    }

    [self writeCurrentTextToPath:self.currentPath];
}

- (void)saveFileAs:(id)sender {
    if (!self.hasDocument || self.textView == nil) {
        return;
    }

    std::optional<std::filesystem::path> selected = fileDialog_.saveFile();
    if (!selected.has_value()) {
        return;
    }

    self.currentPath = NSStringFromStdString(selected->string());
    [self writeCurrentTextToPath:self.currentPath];
}

- (void)writeCurrentTextToPath:(NSString*)path {
    const std::string contents = StdStringFromNSString([self.textView string]);
    const auto result = fileService_.writeTextFile(std::filesystem::path(StdStringFromNSString(path)), contents);
    if (!result.ok) {
        [self showErrorWithTitle:@"Could not save file."
                    whatHappened:@"DietCode could not write to this location."
                        nextStep:@"Try Save As and choose another folder."
                          safety:@"Your changes are still open in DietCode."
                         details:NSStringFromStdString(result.error)];
        return;
    }

    self.dirty = NO;
    [self updateWindowTitleAndStatus];
}

- (void)textDidChange:(NSNotification*)notification {
    if (!self.loadingDocument && self.hasDocument) {
        self.dirty = YES;
        [self updateWindowTitleAndStatus];
    }
}

- (BOOL)hasUnsavedChanges {
    return self.hasDocument && self.dirty;
}

- (BOOL)confirmCloseIfNeeded {
    if (![self hasUnsavedChanges]) {
        return YES;
    }

    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Save your changes before closing?"];
    [alert setInformativeText:@"Your file has unsaved changes. You can save them, keep editing, or close without saving."];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Keep Editing"];
    [alert addButtonWithTitle:@"Close Without Saving"];
    [alert setAlertStyle:NSAlertStyleWarning];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [self saveFile:nil];
        return ![self hasUnsavedChanges];
    }
    if (response == NSAlertSecondButtonReturn) {
        return NO;
    }
    self.dirty = NO;
    return YES;
}

- (void)windowWillClose:(NSNotification*)notification {
    [NSApp terminate:nil];
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
    return [self confirmCloseIfNeeded];
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

- (void)updateWindowTitleAndStatus {
    NSString* displayName = self.currentPath == nil ? @"Untitled" : [[self.currentPath lastPathComponent] length] > 0 ? [self.currentPath lastPathComponent] : self.currentPath;
    NSString* dirtyPrefix = self.dirty ? @"● " : @"";
    NSString* title = self.hasDocument ? [NSString stringWithFormat:@"%@%@ — DietCode", dirtyPrefix, displayName] : @"DietCode";
    [[self window] setTitle:title];

    NSString* savedState = self.dirty ? @"Unsaved" : @"Saved";
    NSString* fileName = self.hasDocument ? displayName : @"No file open";
    NSString* cursorText = @"Line 1, Column 1";
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
        cursorText = [NSString stringWithFormat:@"Line %lu, Column %lu", static_cast<unsigned long>(line), static_cast<unsigned long>(column)];
    }

    [self.statusLabel setStringValue:[NSString stringWithFormat:@"%@ • %@ • Plain Text • %@", fileName, savedState, cursorText]];
}

- (void)textViewDidChangeSelection:(NSNotification*)notification {
    [self updateWindowTitleAndStatus];
}

@end
