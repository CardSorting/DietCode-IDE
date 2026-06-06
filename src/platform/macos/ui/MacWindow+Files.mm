#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"
#include "utils/PathExclusion.hpp"

using namespace dietcode::platform::macos;
using namespace dietcode::utils;

@implementation DietCodeWindowController (Files)

- (void)setupFilesUI {
    NSTextField* filesTitle = MakeLabel(@"FILES", 11, NSFontWeightBold);
    [filesTitle setTextColor:[NSColor secondaryLabelColor]];
    [filesTitle setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.filesSidebarView addSubview:filesTitle];

    NSScrollView* treeScroll = [[NSScrollView alloc] init];
    [treeScroll setHasVerticalScroller:YES];
    [treeScroll setDrawsBackground:NO];
    [treeScroll setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.filesSidebarView addSubview:treeScroll];

    self.fileTreeView = [[DietCodeOutlineView alloc] init];
    [self.fileTreeView setHeaderView:nil];
    [self.fileTreeView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
    [self.fileTreeView setDataSource:self];
    [self.fileTreeView setDelegate:self];
    [self.fileTreeView setDoubleAction:@selector(fileTreeDoubleClicked:)];
    [self.fileTreeView setTarget:self];
    
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"FileColumn"];
    [self.fileTreeView addTableColumn:col];
    [self.fileTreeView setOutlineTableColumn:col];
    
    [treeScroll setDocumentView:self.fileTreeView];

    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"FileActions"];
    [fileMenu addItemWithTitle:@"New File…" action:@selector(newFileClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"New Folder…" action:@selector(newFolderClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Rename…" action:@selector(renameFileClicked:) keyEquivalent:@""];
    [fileMenu addItemWithTitle:@"Delete" action:@selector(deleteFileClicked:) keyEquivalent:@""];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Reveal in Finder" action:@selector(revealInFinderClicked:) keyEquivalent:@""];
    [self.fileTreeView setMenu:fileMenu];

    self.fileTreeEmptyStateView = [[NSView alloc] init];
    [self.fileTreeEmptyStateView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.filesSidebarView addSubview:self.fileTreeEmptyStateView];
    
    NSTextField* emptyLabel = MakeLabel(@"No folder open.\nOpen a folder to see files.", 13, NSFontWeightRegular);
    [emptyLabel setAlignment:NSTextAlignmentCenter];
    [emptyLabel setTextColor:[NSColor secondaryLabelColor]];
    [emptyLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.fileTreeEmptyStateView addSubview:emptyLabel];

    NSButton* openFolderBtn = MakeButton(@"Open Folder...", self, @selector(openFolder:));
    [openFolderBtn setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.fileTreeEmptyStateView addSubview:openFolderBtn];

    [NSLayoutConstraint activateConstraints:@[
        [filesTitle.topAnchor constraintEqualToAnchor:self.filesSidebarView.topAnchor constant:10],
        [filesTitle.leadingAnchor constraintEqualToAnchor:self.filesSidebarView.leadingAnchor constant:15],
        
        [treeScroll.topAnchor constraintEqualToAnchor:filesTitle.bottomAnchor constant:10],
        [treeScroll.leadingAnchor constraintEqualToAnchor:self.filesSidebarView.leadingAnchor],
        [treeScroll.trailingAnchor constraintEqualToAnchor:self.filesSidebarView.trailingAnchor],
        [treeScroll.bottomAnchor constraintEqualToAnchor:self.filesSidebarView.bottomAnchor],
        
        [self.fileTreeEmptyStateView.topAnchor constraintEqualToAnchor:treeScroll.topAnchor],
        [self.fileTreeEmptyStateView.leadingAnchor constraintEqualToAnchor:treeScroll.leadingAnchor],
        [self.fileTreeEmptyStateView.trailingAnchor constraintEqualToAnchor:treeScroll.trailingAnchor],
        [self.fileTreeEmptyStateView.bottomAnchor constraintEqualToAnchor:treeScroll.bottomAnchor],
        
        [emptyLabel.centerXAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.centerXAnchor],
        [emptyLabel.centerYAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.centerYAnchor constant:-20],
        
        [openFolderBtn.centerXAnchor constraintEqualToAnchor:self.fileTreeEmptyStateView.centerXAnchor],
        [openFolderBtn.topAnchor constraintEqualToAnchor:emptyLabel.bottomAnchor constant:15]
    ]];
    
    [self refreshFilesTree:nil];
}

- (void)openFile:(id)sender {
    auto selected = self->fileDialog_.openFile();
    if (selected) {
        [self openFileFromPath:NSStringFromStdString(selected->string())];
    }
}

- (void)openFolder:(id)sender {
    // Note: MacFileDialog currently doesn't support folder selection in the same way.
    // For now, use openFile() as a proxy or stick to the original plan if it used NSOpenPanel.
    // Actually, the original code used NSOpenPanel directly for folders.
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    if ([panel runModal] == NSModalResponseOK) {
        [self openWorkspaceFolder:[[panel URL] path]];
    }
}

- (void)newFile:(id)sender {
    [self showEditorWithText:@"" path:nil dirty:YES];
}

- (void)saveFile:(id)sender {
    if (self.activeTab) {
        [self saveTab:self.activeTab];
    }
}

- (void)saveTab:(DietCodeTabState*)tab {
    if (!tab.path) {
        [self saveFileAs:nil];
        return;
    }
    
    NSString* content = [tab.textView string];
    NSError* err = nil;
    if ([content writeToFile:tab.path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        tab.dirty = NO;
        [self updateTabHeaderLayout];
        [self updateWindowTitleAndStatus];
        [self deleteBackupForTab:tab];
        [self notifyAgentEvent:@"DocumentSaved" detail:tab.path];
    } else {
        [self showErrorAlert:@"Save Failed" message:err.localizedDescription];
    }
}

- (void)saveFileAs:(id)sender {
    if (!self.activeTab) return;
    
    auto selected = self->fileDialog_.saveFile();
    if (selected) {
        NSString* path = NSStringFromStdString(selected->string());
        self.activeTab.path = path;
        self.activeTab.title = [path lastPathComponent];
        [self saveTab:self.activeTab];
    }
}

- (void)openFileFromPath:(NSString*)path {
    const auto result = self->fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(path)));
    if (result.ok) {
        [self showEditorWithText:NSStringFromStdString(result.contents) path:path dirty:NO];
        [self addToRecentFiles:path];
        [self promptLanguageFeaturesIfNeeded:path];
    }
}

- (void)openFileAtPath:(NSString*)path line:(NSInteger)line column:(NSInteger)column {
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        [self openWorkspaceFolder:path];
        return;
    }
    BOOL found = NO;
    for (DietCodeTabState* tab in self.openTabs) {
        if ([tab.path isEqualToString:path]) {
            [self activateTab:tab];
            found = YES;
            break;
        }
    }
    
    if (!found) {
        NSError* err = nil;
        NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err];
        unsigned long long fileSize = [attrs fileSize];
        BOOL useLargeFileMode = NO;
        
        if (fileSize >= 50 * 1024 * 1024) {
            if (self.isHeadless) {
                useLargeFileMode = YES;
            } else {
                NSAlert* alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Large File Warning"];
                [alert setInformativeText:[NSString stringWithFormat:@"The file '%@' is %.1f MB. Opening large files normally can cause the editor to become laggy and unresponsive.\n\nWould you like to open it in Large File Mode (Read-Only) to keep scrolling responsive?", [path lastPathComponent], (double)fileSize / (1024.0 * 1024.0)]];
                [alert addButtonWithTitle:@"Open in Large File Mode (Recommended)"];
                [alert addButtonWithTitle:@"Open Normally"];
                [alert addButtonWithTitle:@"Cancel"];
                [alert setAlertStyle:NSAlertStyleWarning];
                
                NSModalResponse res = [alert runModal];
                if (res == NSAlertThirdButtonReturn) {
                    return; // Cancel opening
                }
                if (res == NSAlertFirstButtonReturn) {
                    useLargeFileMode = YES;
                }
            }
        }
        
        if (useLargeFileMode) {
            self.forceLargeFileModeForNextOpen = YES;
        }
        
        const auto result = fileService_.readTextFile(std::filesystem::path(StdStringFromNSString(path)));
        if (!result.ok) {
            self.forceLargeFileModeForNextOpen = NO;
            return;
        }
        [self showEditorWithText:NSStringFromStdString(result.contents) path:path dirty:NO];
        
        if (attrs) {
            self.activeTab.lastModifiedDate = attrs.fileModificationDate;
        }
        [self addToRecentFiles:path];
        if (!useLargeFileMode) {
            [self promptLanguageFeaturesIfNeeded:path];
        }
    }
    
    if (self.textView) {
        [self jumpToLine:line column:column];
    }
}

- (void)openWorkspaceFolder:(NSString*)path {
    self.openedFolderPath = path;
    [self addToRecentFolders:self.openedFolderPath];
    [self refreshFilesTree:nil];
    [self selectActivity:@"files"];
    [self notifyAgentEvent:@"DocumentOpened" detail:path];
}

- (void)refreshFilesTree:(id)sender {
    [self.directoryCache removeAllObjects];
    [self.fileTreeView reloadData];
    self.fileTreeEmptyStateView.hidden = (self.openedFolderPath != nil);
}

- (void)addToRecentFolders:(NSString*)path {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* recents = [[defaults stringArrayForKey:@"RecentFolders"] mutableCopy] ?: [NSMutableArray array];
    [recents removeObject:path];
    [recents insertObject:path atIndex:0];
    if (recents.count > 10) [recents removeLastObject];
    [defaults setObject:recents forKey:@"RecentFolders"];
}

- (void)addToRecentFiles:(NSString*)path {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* recents = [[defaults stringArrayForKey:@"RecentFiles"] mutableCopy] ?: [NSMutableArray array];
    [recents removeObject:path];
    [recents insertObject:path atIndex:0];
    if (recents.count > 20) [recents removeLastObject];
    [defaults setObject:recents forKey:@"RecentFiles"];
}

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

- (void)newFileClicked:(id)sender {
    if (self.isHeadless) return;
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
    if (self.isHeadless) return;
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
    if (self.isHeadless) return;
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
            [self showErrorWithTitle:@"Rename failed" message:error.localizedDescription];
        } else {
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
    if (self.isHeadless) return;
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
            [self showErrorWithTitle:@"Delete failed" message:error.localizedDescription];
        } else {
            DietCodeTabState* toClose = nil;
            for (DietCodeTabState* tab in self.openTabs) {
                if ([tab.path isEqualToString:path]) {
                    toClose = tab;
                    break;
                }
            }
            if (toClose) {
                toClose.dirty = NO;
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

// NSOutlineViewDataSource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    NSString* path = (item == nil) ? self.openedFolderPath : (NSString*)item;
    if (!path) return 0;
    
    NSArray* children = self.directoryCache[path];
    if (!children) {
        NSMutableArray* list = [NSMutableArray array];
        NSError* error = nil;
        NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
        for (NSString* name in contents) {
            NSString* fullPath = [path stringByAppendingPathComponent:name];
            if (!isPathExcluded(std::filesystem::path(StdStringFromNSString(fullPath)))) {
                [list addObject:fullPath];
            }
        }
        [list sortUsingSelector:@selector(localizedStandardCompare:)];
        self.directoryCache[path] = list;
        children = list;
    }
    return children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    NSString* path = (item == nil) ? self.openedFolderPath : (NSString*)item;
    return self.directoryCache[path][index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    BOOL isDir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:(NSString*)item isDirectory:&isDir] && isDir;
}

// NSOutlineViewDelegate
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSString* path = (NSString*)item;
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    
    NSTableCellView* cell = [outlineView makeViewWithIdentifier:@"FileCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        cell.identifier = @"FileCell";
        
        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 2, 16, 16)];
        [cell addSubview:iv];
        cell.imageView = iv;
        
        NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 0, 80, 20)];
        [tf setBezeled:NO];
        [tf setDrawsBackground:NO];
        [tf setEditable:NO];
        [cell addSubview:tf];
        cell.textField = tf;
    }
    
    cell.textField.stringValue = [path lastPathComponent];
    NSString* iconName = isDir ? @"folder" : @"doc";
    cell.imageView.image = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil];
    
    return cell;
}

@end
