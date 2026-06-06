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
- (void)goToDefinitionClicked:(id)sender;

// --- Agent Control Surface v1.1 Programmatic API ---
@property(nonatomic, assign) BOOL externalControlEnabled;
@property(nonatomic, assign) NSInteger agentAutonomyLevel;
@property(nonatomic, assign) BOOL isHeadless;
@property(nonatomic, strong) NSMutableArray* openTabs;
@property(nonatomic, strong) NSMutableArray<NSString*>* sessionRecentCommands;
@property(nonatomic, strong) NSMutableArray<NSString*>* sessionLastSearches;

// Workspace
- (NSString*)workspacePath;
- (void)openWorkspaceFolder:(NSString*)path;
- (NSArray<NSString*>*)openFilePaths;
- (NSString*)activeFilePath;
- (NSString*)textForFileAtPath:(NSString*)path;
- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path;
- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut;
- (void)saveFileAtPath:(NSString*)path;
- (void)closeFileAtPath:(NSString*)path;
- (void)jumpToLine:(NSInteger)line column:(NSInteger)column;

// Terminal
- (pid_t)terminalPid;
- (BOOL)runTerminalCommand:(NSString*)command cwd:(NSString*)cwd show:(BOOL)show errorOut:(NSString**)errorOut;
- (void)stopTerminalCommand;
- (NSString*)terminalOutput;
- (void)clearTerminalOutput;

// Git
- (NSDictionary*)gitStatusInfo;
- (NSString*)gitDiffForFile:(NSString*)path;
- (BOOL)gitStageFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitUnstageFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitDiscardFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitCommitWithMessage:(NSString*)message errorOut:(NSString**)errorOut;

// File I/O (agent-facing)
- (BOOL)writeFileAtPath:(NSString*)path content:(NSString*)content errorOut:(NSString**)errorOut;

// Problems
- (NSArray<NSDictionary*>*)problemsList;
- (void)problemsOpen:(NSString*)problemId;
- (void)problemsClearSource:(NSString*)source;

// Language Features
- (NSArray*)languageDiagnosticsForPath:(NSString*)path;
- (void)formatFileAtPath:(NSString*)path;
- (void)lintFileAtPath:(NSString*)path;
- (void)restartLSPForLanguage:(NSString*)lang;
- (void)stopLSPForLanguage:(NSString*)lang;

// UI Logging
- (void)appendControlLogLine:(NSString*)line;
- (void)setControlActiveCommand:(NSString*)method caller:(NSString*)caller;
- (void)showBottomPanelTab:(NSString*)identifier;
- (void)updateControlStatusIndicator;

// Selection / Cursor Helpers for RPC
- (NSDictionary*)activeSelectionInfo;
- (BOOL)setActiveSelectionStart:(NSInteger)start end:(NSInteger)end;
- (BOOL)insertTextAtActiveCursor:(NSString*)text;
- (BOOL)replaceActiveSelectionWithText:(NSString*)text;

@end


