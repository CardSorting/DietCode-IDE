#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Tabs)

- (void)showEditorWithText:(NSString*)text path:(NSString*)path dirty:(BOOL)isDirty {
    if (path != nil) {
        for (DietCodeTabState* tab in self.openTabs) {
            if ([tab.path isEqualToString:path]) {
                [self activateTab:tab];
                if (isDirty) {
                    [tab.textView setString:text];
                    tab.dirty = YES;
                    [self updateTabHeaderLayout];
                }
                return;
            }
        }
    }

    self.editorHostView.hidden = NO;
    self.hasDocument = YES;

    DietCodeTabState* tab = [[DietCodeTabState alloc] init];
    tab.path = path;
    tab.title = path == nil ? @"Untitled" : [path lastPathComponent];
    tab.dirty = isDirty;
    tab.isReadOnly = NO;
    tab.isDiff = NO;
    tab.isLargeFile = NO;
    
    if (self.forceLargeFileModeForNextOpen) {
        tab.isLargeFile = YES;
        tab.isReadOnly = YES;
        self.forceLargeFileModeForNextOpen = NO;
    }
    
    if (path && [path hasPrefix:@"[Diff]"]) {
        tab.isReadOnly = YES;
        tab.isDiff = YES;
    }

    NSScrollView* scroll = [[NSScrollView alloc] init];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:YES];
    [scroll setAutohidesScrollers:NO];
    [scroll setBorderType:NSNoBorder];
    
    DietCodeEditorTextView* editor = [[DietCodeEditorTextView alloc] init];
    [editor setMinSize:NSMakeSize(0.0, 0.0)];
    [editor setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor setVerticallyResizable:YES];
    [editor setHorizontallyResizable:YES];
    [editor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [editor.textContainer setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [editor.textContainer setWidthTracksTextView:tab.isLargeFile ? NO : self.currentWordWrap];
    [editor setFont:[NSFont monospacedSystemFontOfSize:self.currentFontSize weight:NSFontWeightRegular]];
    [editor setRichText:NO];
    [editor setAutomaticQuoteSubstitutionEnabled:NO];
    [editor setAutomaticDashSubstitutionEnabled:NO];
    [editor setAutomaticTextReplacementEnabled:NO];
    [editor setAllowsUndo:YES];
    [editor setDelegate:self];
    [editor setEditable:!tab.isReadOnly];
    [editor setAccessibilityLabel:[NSString stringWithFormat:@"Editor for %@", tab.title]];
    
    self.loadingDocument = YES;
    [editor setString:text ?: @""];
    self.loadingDocument = NO;
    
    if (tab.isDiff) {
        [self applyDiffColoring:editor];
    }
    
    [scroll setDocumentView:editor];
    
    if (tab.isLargeFile) {
        [scroll setRulersVisible:NO];
    } else {
        [scroll setHasVerticalRuler:YES];
        [scroll setRulersVisible:YES];
        DietCodeLineNumberRulerView* ruler = [[DietCodeLineNumberRulerView alloc] initWithScrollView:scroll];
        [scroll setVerticalRulerView:ruler];
    }

    tab.scrollView = scroll;
    tab.textView = editor;
    
    [self.openTabs addObject:tab];

    NSTabViewItem* tabItem = [[NSTabViewItem alloc] initWithIdentifier:tab];
    [tabItem setView:scroll];
    [self.editorTabView addTabViewItem:tabItem];

    [self createTabHeaderButton:tab];
    [self activateTab:tab];
    
    if (path && !tab.isReadOnly && !tab.isDiff) {
        NSString* language = [self detectLanguage:path];
        if (language) {
            dietcode::lsp::LSPClient* client = [self lspClientForLanguage:language];
            if (client && client->isRunning()) {
                client->didOpen(StdStringFromNSString(path), StdStringFromNSString(text));
            }
        }
    }
    [self saveOpenTabsState];
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

    NSClickGestureRecognizer* click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(tabHeaderClicked:)];
    [tabBtn addGestureRecognizer:click];
    tabBtn.identifier = [NSString stringWithFormat:@"%p", tab];
    tab.tabButtonView = tabBtn;

    [self.tabHeaderStack addArrangedSubview:tabBtn];
    [self updateTabHeaderLayout];
}

- (void)tabHeaderClicked:(NSClickGestureRecognizer*)recognizer {
    NSString* ident = recognizer.view.identifier;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([[NSString stringWithFormat:@"%p", tab] isEqualToString:ident]) {
            [self activateTab:tab];
            break;
        }
    }
}

- (void)closeTabButtonClicked:(NSButton*)sender {
    NSString* ident = sender.identifier;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([[NSString stringWithFormat:@"%p", tab] isEqualToString:ident]) {
            [self closeTab:tab];
            break;
        }
    }
}

- (void)activateTab:(DietCodeTabState*)tab {
    self.activeTab = tab;
    self.textView = tab.textView;
    
    for (NSTabViewItem* item in [self.editorTabView tabViewItems]) {
        if (item.identifier == tab) {
            [self.editorTabView selectTabViewItem:item];
            break;
        }
    }

    [[self window] makeFirstResponder:tab.textView];
    [self updateTabHeaderLayout];
    [self updateWindowTitleAndStatus];
    [self checkExternalStatusForTab:tab];
}

- (void)closeTab:(DietCodeTabState*)tab {
    if (tab.dirty) {
        if (self.isHeadless) {
            [self deleteBackupForTab:tab];
        } else {
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
                return;
            }
        }
    }

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveBackupForTab:) object:tab];
    [self deleteBackupForTab:tab];

    NSString* closedPath = tab.path;
    [self.openTabs removeObject:tab];
    [self saveOpenTabsState];
    if (closedPath) {
        [self notifyAgentEvent:@"DocumentClosed" detail:closedPath];
    }
    [tab.tabButtonView removeFromSuperview];
    
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
        [self showWelcome:nil];
    }
}

- (void)updateTabHeaderLayout {
    BOOL isDark = [self isDarkTheme];

    for (DietCodeTabState* tab in self.openTabs) {
        NSStackView* btn = (NSStackView*)tab.tabButtonView;
        if (!btn) continue;
        NSTextField* titleL = (NSTextField*)[btn arrangedSubviews][0];
        
        if (tab == self.activeTab) {
            [btn.layer setBackgroundColor:(isDark ? [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] CGColor] : [[NSColor whiteColor] CGColor])];
            [titleL setTextColor:[NSColor textColor]];
        } else {
            [btn.layer setBackgroundColor:(isDark ? [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] CGColor] : [[NSColor colorWithCalibratedWhite:0.88 alpha:1.0] CGColor])];
            [titleL setTextColor:[NSColor secondaryLabelColor]];
        }
        
        NSString* displayTitle = tab.dirty ? [NSString stringWithFormat:@"● %@", tab.title] : tab.title;
        [titleL setStringValue:displayTitle];
    }
}

- (void)saveOpenTabsState {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* paths = [NSMutableArray array];
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.path && ![tab.path hasPrefix:@"[Diff]"]) {
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
    
    DietCodeTabState* activeTabToRestore = nil;
    for (NSString* path in paths) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            unsigned long long fileSize = [attrs fileSize];
            if (fileSize >= 50 * 1024 * 1024) {
                self.forceLargeFileModeForNextOpen = YES;
            }
            
            const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(path)));
            if (result.ok) {
                [self showEditorWithText:NSStringFromStdString(result.contents) path:path dirty:NO];
                if (attrs) {
                    self.activeTab.lastModifiedDate = attrs.fileModificationDate;
                }
                if ([path isEqualToString:activePath]) {
                    activeTabToRestore = self.activeTab;
                }
            }
        }
    }
    
    if (activeTabToRestore) {
        [self activateTab:activeTabToRestore];
    } else if (self.openTabs.count > 0) {
        [self activateTab:[self.openTabs lastObject]];
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

- (void)closeActiveTabAction:(id)sender {
    if (self.activeTab != nil) {
        [self closeTab:self.activeTab];
    } else {
        [[self window] close];
    }
}

- (BOOL)hasUnsavedChanges {
    for (DietCodeTabState* tab in self.openTabs) {
        if (tab.dirty) return YES;
    }
    return NO;
}

- (BOOL)confirmCloseIfNeeded {
    if (![self hasUnsavedChanges]) return YES;
    
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Unsaved Changes"];
    [alert setInformativeText:@"There are files with unsaved changes. Do you want to save them before closing?"];
    [alert addButtonWithTitle:@"Save All"];
    [alert addButtonWithTitle:@"Discard All"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSModalResponse res = [alert runModal];
    if (res == NSAlertFirstButtonReturn) {
        for (DietCodeTabState* tab in self.openTabs) {
            if (tab.dirty) [self saveTab:tab];
        }
        return YES;
    } else if (res == NSAlertSecondButtonReturn) {
        return YES;
    }
    return NO;
}

@end
