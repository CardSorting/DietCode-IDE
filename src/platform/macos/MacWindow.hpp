#pragma once

#import <Cocoa/Cocoa.h>

@class DietCodeEditorViewDelegate;

@interface DietCodeWindowController : NSWindowController <NSWindowDelegate, NSTextViewDelegate>

- (instancetype)init;
- (void)newFile:(id)sender;
- (void)openFile:(id)sender;
- (void)saveFile:(id)sender;
- (void)saveFileAs:(id)sender;
- (void)showWelcome:(id)sender;
- (BOOL)hasUnsavedChanges;
- (BOOL)confirmCloseIfNeeded;

@end
