#import "MacWindow+Private.hpp"
#import "MacWindowUtilities.hpp"
#import "MacEditorComponents.hpp"

using namespace dietcode::platform::macos;

@implementation DietCodeWindowController (CommandPalette)

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
        @{@"title": @"Settings: Open Settings", @"action": @"openSettingsAction:"}
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

- (void)filterPaletteActions:(NSString*)query {
    if ([query hasPrefix:@"@"]) {
        if (self.activeTab && self.activeTab.path) {
            NSString* language = [self detectLanguage:self.activeTab.path];
            if (language) {
                dietcode::lsp::LSPClient* client = [self lspClientForLanguage:language];
                if (client && client->isRunning()) {
                    std::string file = StdStringFromNSString(self.activeTab.path);
                    auto symbols = client->getDocumentSymbols(file);
                    
                    NSString* filterQuery = [query substringFromIndex:1];
                    NSMutableArray* res = [NSMutableArray array];
                    for (const auto& s : symbols) {
                        NSString* name = NSStringFromStdString(s.name);
                        NSString* kind = NSStringFromStdString(s.kind);
                        NSString* title = [NSString stringWithFormat:@"%@ (%@)", name, kind];
                        
                        if (filterQuery.length == 0 || [title rangeOfString:filterQuery options:NSCaseInsensitiveSearch].location != NSNotFound) {
                            [res addObject:@{
                                @"title": title,
                                @"action": @"jumpToSymbolAction:",
                                @"symbol": @{
                                    @"path": self.activeTab.path,
                                    @"line": @(s.line),
                                    @"column": @(s.column)
                                }
                            }];
                        }
                    }
                    self.filteredCommandPaletteActions = res;
                    [self.paletteTableView reloadData];
                    if (self.filteredCommandPaletteActions.count > 0) {
                        [self.paletteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                    }
                    return;
                }
            }
        }
        
        self.filteredCommandPaletteActions = @[@{
            @"title": @"No document symbols available (LSP not active)",
            @"action": @"noop:"
        }];
        [self.paletteTableView reloadData];
        return;
    }
    
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

- (void)closePaletteHUD {
    [[self window] removeChildWindow:self.commandPalettePanel];
    [self.commandPalettePanel orderOut:nil];
    if (self.textView) {
        [[self window] makeFirstResponder:self.textView];
    }
}

// NSTableViewDelegate / DataSource for Palette
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
                NSDictionary* act = self.filteredCommandPaletteActions[row];
                NSString* actionStr = act[@"action"];
                if ([actionStr isEqualToString:@"jumpToSymbolAction:"]) {
                    NSDictionary* sym = act[@"symbol"];
                    [self openFileAtPath:sym[@"path"] line:[sym[@"line"] integerValue] column:[sym[@"column"] integerValue]];
                } else if (![actionStr isEqualToString:@"noop:"]) {
                    SEL sel = NSSelectorFromString(actionStr);
                    if ([self respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [self performSelector:sel withObject:nil];
#pragma clang diagnostic pop
                    }
                }
                [self closePaletteHUD];
            }
            return YES;
        } else if (commandSelector == @selector(cancelOperation:)) {
            [self closePaletteHUD];
            return YES;
        }
    }
    return NO;
}

@end
