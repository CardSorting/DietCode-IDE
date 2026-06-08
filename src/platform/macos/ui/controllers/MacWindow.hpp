#pragma once

#import <Cocoa/Cocoa.h>

@interface DietCodeWindowController : NSWindowController <NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;
- (void)showWelcome:(id)sender;
- (void)toggleSidebar:(id)sender;
- (void)toggleTerminal:(id)sender;
- (void)goToLine:(id)sender;
- (void)cleanupProcesses;

@property(nonatomic, assign) BOOL externalControlEnabled;
@property(nonatomic, assign) NSInteger agentAutonomyLevel;
@property(nonatomic, assign) BOOL isHeadless;
@property(nonatomic, strong) NSMutableArray* openTabs;
@property(nonatomic, strong) NSMutableArray<NSString*>* sessionRecentCommands;
@property(nonatomic, strong) NSMutableArray<NSString*>* sessionLastSearches;

@end

#import "MacWindow+CategoryAPI.hpp"
