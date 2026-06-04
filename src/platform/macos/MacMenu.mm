#include "platform/macos/MacMenu.hpp"
#include "platform/macos/MacWindow.hpp"

#import <Cocoa/Cocoa.h>

@implementation DietCodeMenuBuilder

+ (NSMenuItem*)itemWithTitle:(NSString*)title action:(SEL)action key:(NSString*)key modifiers:(NSEventModifierFlags)modifiers target:(id)target {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    [item setKeyEquivalentModifierMask:modifiers];
    [item setTarget:target];
    return item;
}

+ (void)installMainMenuWithTarget:(DietCodeWindowController*)target {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"DietCode"];

    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"DietCode"];
    [appMenu addItemWithTitle:@"About DietCode" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Settings…" action:nil keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit DietCode" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];

    NSMenuItem* fileMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileMenuItem];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItem:[self itemWithTitle:@"New File" action:@selector(newFile:) key:@"n" modifiers:NSEventModifierFlagCommand target:target]];
    [fileMenu addItem:[self itemWithTitle:@"Open File…" action:@selector(openFile:) key:@"o" modifiers:NSEventModifierFlagCommand target:target]];
    [fileMenu addItem:[self itemWithTitle:@"Open Folder… (Phase 2)" action:nil key:@"" modifiers:0 target:nil]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self itemWithTitle:@"Save" action:@selector(saveFile:) key:@"s" modifiers:NSEventModifierFlagCommand target:target]];
    [fileMenu addItem:[self itemWithTitle:@"Save As…" action:@selector(saveFileAs:) key:@"S" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift target:target]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self itemWithTitle:@"Close Tab" action:@selector(performClose:) key:@"w" modifiers:NSEventModifierFlagCommand target:nil]];
    [fileMenuItem setSubmenu:fileMenu];

    NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editMenuItem];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Find" action:@selector(performTextFinderAction:) keyEquivalent:@"f"];
    [editMenuItem setSubmenu:editMenu];

    NSMenuItem* selectionMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:selectionMenuItem];
    NSMenu* selectionMenu = [[NSMenu alloc] initWithTitle:@"Selection"];
    [selectionMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [selectionMenuItem setSubmenu:selectionMenu];

    NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:viewMenuItem];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItem:[self itemWithTitle:@"Open Welcome" action:@selector(showWelcome:) key:@"" modifiers:0 target:target]];
    [viewMenu addItemWithTitle:@"Command Palette… (Phase 2)" action:nil keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Toggle Sidebar (Phase 1B)" action:nil keyEquivalent:@"b"];
    [viewMenuItem setSubmenu:viewMenu];

    NSMenuItem* goMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:goMenuItem];
    NSMenu* goMenu = [[NSMenu alloc] initWithTitle:@"Go"];
    [goMenu addItemWithTitle:@"Go to Line… (Phase 2)" action:nil keyEquivalent:@"g"];
    [goMenuItem setSubmenu:goMenu];

    NSMenuItem* runMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:runMenuItem];
    NSMenu* runMenu = [[NSMenu alloc] initWithTitle:@"Run"];
    [runMenu addItemWithTitle:@"Run Current File (Phase 3)" action:nil keyEquivalent:@"r"];
    [runMenuItem setSubmenu:runMenu];

    NSMenuItem* terminalMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:terminalMenuItem];
    NSMenu* terminalMenu = [[NSMenu alloc] initWithTitle:@"Terminal"];
    [terminalMenu addItemWithTitle:@"Toggle Terminal (Phase 3)" action:nil keyEquivalent:@"`"];
    [terminalMenuItem setSubmenu:terminalMenu];

    NSMenuItem* helpMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:helpMenuItem];
    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    [helpMenu addItem:[self itemWithTitle:@"Open Welcome" action:@selector(showWelcome:) key:@"" modifiers:0 target:target]];
    [helpMenu addItemWithTitle:@"Learn DietCode Basics (Phase 4)" action:nil keyEquivalent:@""];
    [helpMenuItem setSubmenu:helpMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
