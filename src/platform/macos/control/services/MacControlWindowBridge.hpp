#pragma once

#import <Cocoa/Cocoa.h>

@class DietCodeWindowController;

@interface DietCodeControlWindowBridge : NSObject

- (instancetype)initWithWindowController:(DietCodeWindowController*)controller;
- (NSString*)workspacePath;
- (NSString*)textForFileAtPath:(NSString*)path;
- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path;
- (NSArray<NSString*>*)openFilePaths;
- (NSArray<NSDictionary*>*)problemsList;
- (NSString*)activeFilePath;
- (NSArray*)openTabs;
- (NSDictionary*)gitStatusInfo;
- (NSString*)gitDiffForFile:(NSString*)path;
- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut;
- (NSDictionary*)activeSelectionInfo;
- (NSString*)terminalOutput;
- (NSArray*)sessionRecentCommands;
- (NSArray*)sessionLastSearches;
- (pid_t)terminalPid;
- (NSArray*)languageDiagnosticsForPath:(NSString*)path;
- (NSInteger)agentAutonomyLevel;

@end
