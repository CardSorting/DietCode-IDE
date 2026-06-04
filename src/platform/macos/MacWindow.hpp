#pragma once

#import <Cocoa/Cocoa.h>

@interface DietCodeWindowController : NSWindowController <NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;
- (void)newFile:(id)sender;
- (void)openFile:(id)sender;
- (void)saveFile:(id)sender;
- (void)saveFileAs:(id)sender;
- (void)showWelcome:(id)sender;
- (BOOL)hasUnsavedChanges;
- (BOOL)confirmCloseIfNeeded;

// Actions for vNext features
- (void)openFolder:(id)sender;
- (void)toggleSidebar:(id)sender;
- (void)toggleTerminal:(id)sender;
- (void)runCurrentFile:(id)sender;
- (void)stopCurrentFile:(id)sender;
- (void)showCommandPalette:(id)sender;
- (void)goToLine:(id)sender;
- (void)nextTab:(id)sender;
- (void)previousTab:(id)sender;
- (void)cleanupProcesses;
- (void)openFileAtPath:(NSString*)path line:(NSInteger)line column:(NSInteger)column;
- (void)closeActiveTabAction:(id)sender;

@end

