#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#include "filesystem/GitService.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (Git)

- (void)setupGitUI {
    NSStackView* gitStack = [[NSStackView alloc] init];
    [gitStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [gitStack setSpacing:8];
    [gitStack setEdgeInsets:NSEdgeInsetsMake(12, 12, 12, 12)];
    [gitStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.gitSidebarView addSubview:gitStack];

    [NSLayoutConstraint activateConstraints:@[
        [gitStack.leadingAnchor constraintEqualToAnchor:self.gitSidebarView.leadingAnchor],
        [gitStack.trailingAnchor constraintEqualToAnchor:self.gitSidebarView.trailingAnchor],
        [gitStack.topAnchor constraintEqualToAnchor:self.gitSidebarView.topAnchor],
        [gitStack.bottomAnchor constraintEqualToAnchor:self.gitSidebarView.bottomAnchor]
    ]];

    [gitStack addArrangedSubview:MakeLabel(@"GIT WORKFLOW", 13, NSFontWeightBold)];

    NSStackView* branchRow = [[NSStackView alloc] init];
    [branchRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [branchRow setSpacing:8];
    [branchRow setDistribution:NSStackViewDistributionFill];
    
    self.gitBranchLabel = MakeLabel(@"Branch: unknown", 12, NSFontWeightRegular);
    [self.gitBranchLabel setTextColor:[NSColor secondaryLabelColor]];
    [self.gitBranchLabel setAccessibilityLabel:@"Git current branch label"];
    [branchRow addArrangedSubview:self.gitBranchLabel];
    
    NSButton* gitRefreshBtn = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(gitRefreshClicked:)];
    [gitRefreshBtn setBezelStyle:NSBezelStyleRecessed];
    [gitRefreshBtn setControlSize:NSControlSizeSmall];
    [gitRefreshBtn setAccessibilityLabel:@"Refresh git changes list"];
    [branchRow addArrangedSubview:gitRefreshBtn];
    
    [gitStack addArrangedSubview:branchRow];

    NSScrollView* gitScroll = [[NSScrollView alloc] init];
    [gitScroll setHasVerticalScroller:YES];
    [gitScroll setHasHorizontalScroller:NO];
    [gitScroll setBorderType:NSNoBorder];
    [gitScroll setTranslatesAutoresizingMaskIntoConstraints:NO];
    [gitStack addArrangedSubview:gitScroll];

    self.gitChangesTableView = [[NSTableView alloc] initWithFrame:gitScroll.bounds];
    [self.gitChangesTableView setHeaderView:nil];
    NSTableColumn* gitCol = [[NSTableColumn alloc] initWithIdentifier:@"GitChangeColumn"];
    [self.gitChangesTableView addTableColumn:gitCol];
    [self.gitChangesTableView setDataSource:self];
    [self.gitChangesTableView setDelegate:self];
    [self.gitChangesTableView setDoubleAction:@selector(gitChangesDoubleClicked:)];
    [self.gitChangesTableView setTarget:self];
    [self.gitChangesTableView setAccessibilityLabel:@"Git changes list"];
    [gitScroll setDocumentView:self.gitChangesTableView];

    NSMenu* gitCtxMenu = [[NSMenu alloc] initWithTitle:@"GitActions"];
    [gitCtxMenu addItemWithTitle:@"Stage File" action:@selector(gitStageSelected:) keyEquivalent:@""];
    [gitCtxMenu addItemWithTitle:@"Unstage File" action:@selector(gitUnstageSelected:) keyEquivalent:@""];
    [gitCtxMenu addItemWithTitle:@"Discard Changes" action:@selector(gitDiscardSelected:) keyEquivalent:@""];
    [gitCtxMenu addItem:[NSMenuItem separatorItem]];
    [gitCtxMenu addItemWithTitle:@"Show Diff" action:@selector(gitDiffSelected:) keyEquivalent:@""];
    [self.gitChangesTableView setMenu:gitCtxMenu];

    self.gitCommitMessageField = [[NSTextField alloc] init];
    [self.gitCommitMessageField setPlaceholderString:@"Commit message..."];
    [self.gitCommitMessageField setFont:[NSFont systemFontOfSize:12]];
    [self.gitCommitMessageField setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.gitCommitMessageField setAccessibilityLabel:@"Git commit message input"];
    [gitStack addArrangedSubview:self.gitCommitMessageField];

    NSButton* commitBtn = MakeButton(@"Commit Changes", self, @selector(gitCommitClicked:));
    [commitBtn setAccessibilityLabel:@"Commit changed files button"];
    [gitStack addArrangedSubview:commitBtn];

    self.gitEmptyStateView = [[NSView alloc] init];
    NSStackView* gitEsStack = [[NSStackView alloc] init];
    [gitEsStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [gitEsStack setSpacing:8];
    [gitEsStack setEdgeInsets:NSEdgeInsetsMake(20, 12, 20, 12)];
    [gitEsStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.gitEmptyStateView addSubview:gitEsStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [gitEsStack.leadingAnchor constraintEqualToAnchor:self.gitEmptyStateView.leadingAnchor],
        [gitEsStack.trailingAnchor constraintEqualToAnchor:self.gitEmptyStateView.trailingAnchor],
        [gitEsStack.topAnchor constraintEqualToAnchor:self.gitEmptyStateView.topAnchor]
    ]];
    
    NSTextField* gitEsLabel = MakeLabel(@"No changed files.", 12, NSFontWeightRegular);
    [gitEsLabel setTextColor:[NSColor secondaryLabelColor]];
    [gitEsLabel setAlignment:NSTextAlignmentCenter];
    [gitEsStack addArrangedSubview:gitEsLabel];
    
    [self.gitSidebarView addSubview:self.gitEmptyStateView];
    [self.gitEmptyStateView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [NSLayoutConstraint activateConstraints:@[
        [self.gitEmptyStateView.leadingAnchor constraintEqualToAnchor:gitScroll.leadingAnchor],
        [self.gitEmptyStateView.trailingAnchor constraintEqualToAnchor:gitScroll.trailingAnchor],
        [self.gitEmptyStateView.topAnchor constraintEqualToAnchor:gitScroll.topAnchor],
        [self.gitEmptyStateView.bottomAnchor constraintEqualToAnchor:gitScroll.bottomAnchor]
    ]];
}

- (void)refreshGitStatus {
    if (self.openedFolderPath == nil) {
        self.gitBranchName = @"";
        self.gitBranchLabel.stringValue = @"Branch: none";
        self.gitChanges = [NSMutableArray array];
        self.gitChangesDict = [NSMutableDictionary dictionary];
        [self.gitChangesTableView reloadData];
        self.gitEmptyStateView.hidden = NO;
        return;
    }
    
    std::string path = StdStringFromNSString(self.openedFolderPath);
    auto result = dietcode::filesystem::GitService::getStatus(path);
    
    self.gitBranchName = NSStringFromStdString(result.branch);
    if (self.gitBranchName.length > 0) {
        self.gitBranchLabel.stringValue = [NSString stringWithFormat:@"Branch: %@", self.gitBranchName];
    } else {
        self.gitBranchLabel.stringValue = @"Branch: none (not a git repo)";
    }
    
    NSMutableArray* staged = [NSMutableArray array];
    NSMutableArray* unstaged = [NSMutableArray array];
    NSMutableDictionary* changesMap = [NSMutableDictionary dictionary];
    for (const auto& c : result.changes) {
        NSString* statusStr = NSStringFromStdString(c.status);
        NSString* relPath = NSStringFromStdString(c.path);
        NSDictionary* dict = @{
            @"status": statusStr,
            @"path": relPath,
            @"staged": @(c.staged)
        };
        if (c.staged) {
            [staged addObject:dict];
        } else {
            [unstaged addObject:dict];
        }
        changesMap[relPath] = dict;
    }
    
    [staged sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1[@"path"] compare:obj2[@"path"]];
    }];
    [unstaged sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1[@"path"] compare:obj2[@"path"]];
    }];
    
    NSMutableArray* combined = [NSMutableArray array];
    if (staged.count > 0) {
        [combined addObject:@{@"isHeader": @YES, @"title": @"Staged Changes"}];
        [combined addObjectsFromArray:staged];
    }
    if (unstaged.count > 0) {
        [combined addObject:@{@"isHeader": @YES, @"title": @"Changes"}];
        [combined addObjectsFromArray:unstaged];
    }
    
    self.gitChanges = combined;
    self.gitChangesDict = changesMap;
    [self.gitChangesTableView reloadData];
    
    self.gitEmptyStateView.hidden = (staged.count > 0 || unstaged.count > 0);
}

- (void)gitRefreshClicked:(id)sender {
    [self refreshGitStatus];
}

- (void)gitChangesDoubleClicked:(id)sender {
    NSInteger row = [self.gitChangesTableView selectedRow];
    if (row >= 0 && row < (NSInteger)self.gitChanges.count) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) return;
    }
    [self gitDiffSelected:sender];
}

- (void)gitStageSelected:(id)sender {
    NSInteger row = [self.gitChangesTableView selectedRow];
    if (row >= 0 && row < (NSInteger)self.gitChanges.count) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) return;
        NSString* relPath = item[@"path"];
        std::string workspace = StdStringFromNSString(self.openedFolderPath);
        std::string file = StdStringFromNSString(relPath);
        std::string errorOut;
        if (dietcode::filesystem::GitService::stageFile(workspace, file, errorOut)) {
            [self refreshGitStatus];
        } else {
            NSString* detail = NSStringFromStdString(errorOut);
            [self showErrorAlert:@"Git Error" message:detail.length > 0 ? detail : [NSString stringWithFormat:@"Failed to stage file '%@'.", relPath]];
        }
    }
}

- (void)gitUnstageSelected:(id)sender {
    NSInteger row = [self.gitChangesTableView selectedRow];
    if (row >= 0 && row < (NSInteger)self.gitChanges.count) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) return;
        NSString* relPath = item[@"path"];
        std::string workspace = StdStringFromNSString(self.openedFolderPath);
        std::string file = StdStringFromNSString(relPath);
        std::string errorOut;
        if (dietcode::filesystem::GitService::unstageFile(workspace, file, errorOut)) {
            [self refreshGitStatus];
        } else {
            NSString* detail = NSStringFromStdString(errorOut);
            [self showErrorAlert:@"Git Error" message:detail.length > 0 ? detail : [NSString stringWithFormat:@"Failed to unstage file '%@'.", relPath]];
        }
    }
}

- (void)gitDiscardSelected:(id)sender {
    if (self.isHeadless) return;
    NSInteger row = [self.gitChangesTableView selectedRow];
    if (row >= 0 && row < (NSInteger)self.gitChanges.count) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) return;
        NSString* relPath = item[@"path"];
        
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Discard Changes?"];
        [alert setInformativeText:[NSString stringWithFormat:@"Are you sure you want to discard all local changes to '%@'? This action cannot be undone.", relPath]];
        [alert addButtonWithTitle:@"Discard"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert setAlertStyle:NSAlertStyleWarning];
        
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            std::string workspace = StdStringFromNSString(self.openedFolderPath);
            std::string file = StdStringFromNSString(relPath);
            std::string errorOut;
            if (dietcode::filesystem::GitService::discardChanges(workspace, file, errorOut)) {
                [self refreshGitStatus];
                
                for (DietCodeTabState* tab in self.openTabs) {
                    if (tab.path) {
                        NSString* absPath = [self.openedFolderPath stringByAppendingPathComponent:relPath];
                        if ([tab.path isEqualToString:absPath]) {
                            const auto result = self->fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(tab.path)));
                            if (result.ok) {
                                [tab.textView setString:NSStringFromStdString(result.contents)];
                                tab.dirty = NO;
                                [self updateTabHeaderLayout];
                                [self updateWindowTitleAndStatus];
                            }
                        }
                    }
                }
            } else {
                NSString* detail = NSStringFromStdString(errorOut);
                [self showErrorAlert:@"Git Error" message:detail.length > 0 ? detail : [NSString stringWithFormat:@"Failed to discard changes for '%@'.", relPath]];
            }
        }
    }
}

- (void)gitDiffSelected:(id)sender {
    NSInteger row = [self.gitChangesTableView selectedRow];
    if (row >= 0 && row < (NSInteger)self.gitChanges.count) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) return;
        NSString* relPath = item[@"path"];
        BOOL staged = [item[@"staged"] boolValue];
        
        std::string workspace = StdStringFromNSString(self.openedFolderPath);
        std::string file = StdStringFromNSString(relPath);
        std::string diffText = dietcode::filesystem::GitService::getDiff(workspace, file, staged);
        
        NSString* pseudoPath = [NSString stringWithFormat:@"[Diff] %@", relPath];
        
        DietCodeTabState* existingTab = nil;
        for (DietCodeTabState* tab in self.openTabs) {
            if ([tab.path isEqualToString:pseudoPath]) {
                existingTab = tab;
                break;
            }
        }
        
        NSString* nsDiff = NSStringFromStdString(diffText);
        if (nsDiff.length == 0) {
            nsDiff = @"No changes to display.";
        }
        
        if (existingTab) {
            [self activateTab:existingTab];
            [existingTab.textView setString:nsDiff];
            [self applyDiffColoring:existingTab.textView];
        } else {
            [self showEditorWithText:nsDiff path:pseudoPath dirty:NO];
        }
    }
}

- (void)gitCommitClicked:(id)sender {
    if (!self.openedFolderPath) return;
    
    NSString* msg = [self.gitCommitMessageField stringValue];
    msg = [msg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (msg.length == 0) {
        [self showErrorAlert:@"Git Error" message:@"Please enter a commit message."];
        return;
    }
    
    std::string stdWorkspace = StdStringFromNSString(self.openedFolderPath);
    std::string stdMsg = StdStringFromNSString(msg);
    std::string errorOut;
    
    if (dietcode::filesystem::GitService::commit(stdWorkspace, stdMsg, errorOut)) {
        [self.gitCommitMessageField setStringValue:@""];
        [self refreshGitStatus];
        [self logOutput:@"[Git] Committed successfully.\n"];
    } else {
        [self showErrorAlert:@"Git Error" message:[NSString stringWithFormat:@"Commit failed: %s", errorOut.c_str()]];
    }
}

- (void)applyDiffColoring:(NSTextView*)textView {
    NSString* text = textView.string;
    NSTextStorage* storage = textView.textStorage;
    [storage beginEditing];
    
    [storage removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, storage.length)];
    
    NSArray* lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger currentIdx = 0;
    
    for (NSString* rawLine in lines) {
        NSRange lineRange = NSMakeRange(currentIdx, rawLine.length);
        if (rawLine.length > 0) {
            unichar firstChar = [rawLine characterAtIndex:0];
            if (firstChar == '+') {
                [storage addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor] range:lineRange];
            } else if (firstChar == '-') {
                [storage addAttribute:NSForegroundColorAttributeName value:[NSColor systemRedColor] range:lineRange];
            } else if (firstChar == '@') {
                [storage addAttribute:NSForegroundColorAttributeName value:[NSColor systemBlueColor] range:lineRange];
            }
        }
        currentIdx += rawLine.length + 1;
    }
    
    [storage endEditing];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.gitChangesTableView) {
        return self.gitChanges.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.gitChangesTableView) {
        NSDictionary* item = self.gitChanges[row];
        if ([item[@"isHeader"] boolValue]) {
            NSTableCellView* view = [tableView makeViewWithIdentifier:@"GitHeaderCell" owner:self];
            if (view == nil) {
                view = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
                view.identifier = @"GitHeaderCell";
                NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 2, 224, 20)];
                [tf setBordered:NO];
                [tf setDrawsBackground:NO];
                [tf setEditable:NO];
                [tf setFont:[NSFont boldSystemFontOfSize:11]];
                [tf setTextColor:[NSColor secondaryLabelColor]];
                view.textField = tf;
                [view addSubview:tf];
            }
            view.textField.stringValue = [item[@"title"] uppercaseString];
            return view;
        }
        
        NSTableCellView* view = [tableView makeViewWithIdentifier:@"GitChangeCell" owner:self];
        if (view == nil) {
            view = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 240, 30)];
            view.identifier = @"GitChangeCell";
            
            NSTextField* statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 6, 24, 18)];
            [statusField setBordered:NO];
            [statusField setDrawsBackground:YES];
            [statusField setEditable:NO];
            [statusField setFont:[NSFont boldSystemFontOfSize:10]];
            [statusField setAlignment:NSTextAlignmentCenter];
            statusField.identifier = @"StatusBadge";
            [view addSubview:statusField];
            
            NSTextField* pathField = [[NSTextField alloc] initWithFrame:NSMakeRect(36, 5, 200, 20)];
            [pathField setBordered:NO];
            [pathField setDrawsBackground:NO];
            [pathField setEditable:NO];
            [pathField setFont:[NSFont systemFontOfSize:12]];
            [pathField setLineBreakMode:NSLineBreakByTruncatingMiddle];
            [pathField setAutoresizingMask:NSViewWidthSizable];
            pathField.identifier = @"PathLabel";
            view.textField = pathField;
            [view addSubview:pathField];
        }
        
        NSString* status = item[@"status"];
        NSString* path = item[@"path"];
        BOOL staged = [item[@"staged"] boolValue];
        
        NSTextField* statusField = nil;
        NSTextField* pathField = nil;
        for (NSView* sub in view.subviews) {
            if ([sub.identifier isEqualToString:@"StatusBadge"]) {
                statusField = (NSTextField*)sub;
            } else if ([sub.identifier isEqualToString:@"PathLabel"]) {
                pathField = (NSTextField*)sub;
            }
        }
        
        if (statusField) {
            statusField.stringValue = status;
            if ([status isEqualToString:@"M"]) {
                statusField.backgroundColor = [NSColor systemOrangeColor];
            } else if ([status isEqualToString:@"A"] || [status isEqualToString:@"??"]) {
                statusField.backgroundColor = [NSColor systemGreenColor];
            } else if ([status isEqualToString:@"D"]) {
                statusField.backgroundColor = [NSColor systemRedColor];
            } else {
                statusField.backgroundColor = [NSColor systemGrayColor];
            }
            statusField.textColor = [NSColor whiteColor];
            statusField.wantsLayer = YES;
            statusField.layer.cornerRadius = 3.0;
        }
        
        if (pathField) {
            pathField.stringValue = path;
            pathField.textColor = staged ? [NSColor labelColor] : [NSColor secondaryLabelColor];
            [pathField setFont:staged ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12]];
        }
        
        return view;
    }
    return nil;
}

@end
