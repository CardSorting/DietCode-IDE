#pragma once

#import <Cocoa/Cocoa.h>

// --- Line Number Ruler View Interface ---
@interface DietCodeLineNumberRulerView : NSRulerView
- (instancetype)initWithScrollView:(NSScrollView*)scrollView;
@end

// --- Outline View with Return key navigation support ---
@interface DietCodeOutlineView : NSOutlineView
@end

// --- Tab State Helper Class ---
@interface DietCodeTabState : NSObject
@property (nonatomic, strong) NSString* path;
@property (nonatomic, strong) NSString* title;
@property (nonatomic, strong) NSScrollView* scrollView;
@property (nonatomic, strong) NSTextView* textView;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, strong) NSView* tabButtonView;
@property (nonatomic, strong) NSDate* lastModifiedDate;
@property (nonatomic, assign) BOOL isReadOnly;
@property (nonatomic, assign) BOOL isDiff;
@property (nonatomic, assign) BOOL isLargeFile;
@end

// --- Custom Text Views for Navigation and Editor ---
@interface DietCodeNavigationTextView : NSTextView
@property (nonatomic, weak) id navigationTarget;
@end

@interface DietCodeEditorTextView : NSTextView
@end

// --- Terminal Text View ---
@interface DietCodeTerminalTextView : NSTextView
@property (nonatomic, assign) int masterFd;
@end

// --- Command Palette Borderless HUD Panel ---
@interface DietCodeCommandPalettePanel : NSPanel
@end
