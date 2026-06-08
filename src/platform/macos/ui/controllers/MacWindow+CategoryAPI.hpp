#pragma once

#import <Cocoa/Cocoa.h>
#include "core/LSPClient.hpp"

@class DietCodeTabState;
@class DietCodeWindowController;

// Named category interfaces — implementations live in MacWindow+*.mm category files.
// Declaring methods here (not on the primary @interface) avoids -Wincomplete-implementation
// and -Wobjc-protocol-method-implementation when the core class is DietCodeWindowController (Core).

@interface DietCodeWindowController (Core)
- (void)updateWindowTitleAndStatus;
- (void)showErrorWithTitle:(NSString*)title
              whatHappened:(NSString*)whatHappened
                  nextStep:(NSString*)nextStep
                    safety:(NSString*)safety
                   details:(NSString*)details;
- (void)showErrorWithTitle:(NSString*)title message:(NSString*)message;
- (void)jumpToLine:(NSInteger)lineNumber;
- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)colNumber;
@end

@interface DietCodeWindowController (Tabs)
- (BOOL)hasUnsavedChanges;
- (BOOL)confirmCloseIfNeeded;
- (void)nextTab:(id)sender;
- (void)previousTab:(id)sender;
- (void)closeActiveTabAction:(id)sender;
- (void)showEditorWithText:(NSString*)text path:(NSString*)path dirty:(BOOL)isDirty;
- (void)createTabHeaderButton:(DietCodeTabState*)tab;
- (void)activateTab:(DietCodeTabState*)tab;
- (void)closeTab:(DietCodeTabState*)tab;
- (void)updateTabHeaderLayout;
- (void)saveOpenTabsState;
- (void)restoreOpenTabs;
@end

@interface DietCodeWindowController (Files)
- (void)newFile:(id)sender;
- (void)openFile:(id)sender;
- (void)saveFile:(id)sender;
- (void)saveFileAs:(id)sender;
- (void)saveTab:(DietCodeTabState*)tab;
- (void)openFolder:(id)sender;
- (void)openFileAtPath:(NSString*)path line:(NSInteger)line column:(NSInteger)column;
- (void)openWorkspaceFolder:(NSString*)path;
- (void)openFileFromPath:(NSString*)path;
- (void)refreshFilesTree:(id)sender;
- (void)addToRecentFolders:(NSString*)path;
- (void)addToRecentFiles:(NSString*)path;
- (NSString*)getSelectedOutlinePath;
- (void)setupFilesUI;
@end

@interface DietCodeWindowController (Layout)
- (void)buildInterface;
- (void)buildBottomTabViews;
- (void)prepareSidebarPanels;
- (void)setupActivityBar;
- (void)applyThemeColors;
- (BOOL)isDarkTheme;
- (BOOL)isHighContrastTheme;
- (void)updateFocusBorders;
- (void)addPlaceholder:(NSString*)placeholder toTextView:(NSTextView*)textView;
- (void)updatePlaceholderVisibility:(NSTextView*)textView;
- (void)selectActivity:(NSString*)activity;
@end

@interface DietCodeWindowController (RunTerminal)
- (void)runCurrentFile:(id)sender;
- (void)stopCurrentFile:(id)sender;
- (void)setupRunUI;
- (void)runCPPCompilation:(NSString*)filePath;
- (void)executeTask:(NSString*)launchPath arguments:(NSArray*)args;
- (void)updateRunStatus:(NSString*)status success:(BOOL)ok;
- (void)appendOutputText:(NSString*)text;
- (void)setupTerminalProcess;
- (void)appendTerminalText:(NSString*)text;
- (void)ensureTerminalProcess;
@end

@interface DietCodeWindowController (CommandPalette)
- (void)showCommandPalette:(id)sender;
- (void)setupCommandPalette;
- (void)filterPaletteActions:(NSString*)query;
- (void)closePaletteHUD;
@end

@interface DietCodeWindowController (AgentAPI)
- (NSString*)workspacePath;
- (NSArray<NSString*>*)openFilePaths;
- (NSString*)activeFilePath;
- (NSString*)textForFileAtPath:(NSString*)path;
- (BOOL)replaceTextInRange:(NSRange)range withText:(NSString*)text forFileAtPath:(NSString*)path;
- (BOOL)applyPatchAtPath:(NSString*)path patchString:(NSString*)patchString errorOut:(NSString**)errorOut;
- (void)saveFileAtPath:(NSString*)path;
- (void)closeFileAtPath:(NSString*)path;
- (pid_t)terminalPid;
- (BOOL)runTerminalCommand:(NSString*)command cwd:(NSString*)cwd show:(BOOL)show errorOut:(NSString**)errorOut;
- (void)stopTerminalCommand;
- (NSString*)terminalOutput;
- (void)clearTerminalOutput;
- (NSDictionary*)gitStatusInfo;
- (NSString*)gitDiffForFile:(NSString*)path;
- (BOOL)gitStageFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitUnstageFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitDiscardFile:(NSString*)path errorOut:(NSString**)errorOut;
- (BOOL)gitCommitWithMessage:(NSString*)message errorOut:(NSString**)errorOut;
- (BOOL)writeFileAtPath:(NSString*)path content:(NSString*)content errorOut:(NSString**)errorOut;
- (NSArray<NSDictionary*>*)problemsList;
- (void)problemsOpen:(NSString*)problemId;
- (void)problemsClearSource:(NSString*)source;
- (NSArray*)languageDiagnosticsForPath:(NSString*)path;
- (void)formatFileAtPath:(NSString*)path;
- (void)lintFileAtPath:(NSString*)path;
- (void)restartLSPForLanguage:(NSString*)lang;
- (void)appendControlLogLine:(NSString*)line;
- (void)setControlActiveCommand:(NSString*)method caller:(NSString*)caller;
- (void)showBottomPanelTab:(NSString*)identifier;
- (void)updateControlStatusIndicator;
- (NSDictionary*)activeSelectionInfo;
- (BOOL)setActiveSelectionStart:(NSInteger)start end:(NSInteger)end;
- (BOOL)insertTextAtActiveCursor:(NSString*)text;
- (BOOL)replaceActiveSelectionWithText:(NSString*)text;
- (void)notifyAgentEvent:(NSString*)type detail:(NSString*)detail;
@end

@interface DietCodeWindowController (Git)
- (void)setupGitUI;
- (void)refreshGitStatus;
- (void)applyDiffColoring:(NSTextView*)textView;
@end

@interface DietCodeWindowController (Settings)
- (void)setupSettingsUI;
@end

@interface DietCodeWindowController (Diagnostics)
- (void)setupErrorsUI;
- (void)handleDiagnostics:(NSArray*)newDiags forFile:(NSString*)filePath source:(NSString*)source;
- (NSArray*)diagnosticsForTabPath:(NSString*)path lineNumber:(NSUInteger)line;
- (void)updateDiagnosticsHighlightsForTab:(DietCodeTabState*)tab;
- (void)rebuildProblemsPanel;
- (NSArray*)parseCompilerOutput:(NSString*)output;
@end

@interface DietCodeWindowController (Language)
- (void)goToDefinitionClicked:(id)sender;
- (NSString*)detectLanguage:(NSString*)path;
- (dietcode::lsp::LSPClient*)lspClientForLanguage:(NSString*)language;
- (void)startLSPForLanguage:(NSString*)language;
- (void)stopLSPForLanguage:(NSString*)language;
- (NSString*)autoDetectBinaryForLanguage:(NSString*)language type:(NSString*)type;
- (void)promptLanguageFeaturesIfNeeded:(NSString*)filePath;
- (void)formatTab:(DietCodeTabState*)tab;
- (void)runLinterForTab:(DietCodeTabState*)tab;
- (NSMutableArray*)parseLinterOutput:(NSString*)output errorOutput:(NSString*)errorOutput language:(NSString*)language filePath:(NSString*)filePath;
- (void)handleMouseHoverInTextView:(NSTextView*)textView atPoint:(NSPoint)point;
- (void)logOutput:(NSString*)text;
- (void)showErrorAlert:(NSString*)title message:(NSString*)message;
- (BOOL)checkAndPromptLSPForLanguage:(NSString*)language filePath:(NSString*)filePath;
@end

@interface DietCodeWindowController (Search)
- (void)setupSearchUI;
- (void)appendSearchResult:(NSString*)text;
- (void)navigateFromProblemsOrSearchText:(NSString*)line sender:(id)sender;
@end

@interface DietCodeWindowController (Recovery)
- (NSString*)getBackupDirectory;
- (void)saveBackupForTab:(DietCodeTabState*)tab;
- (void)deleteBackupForTab:(DietCodeTabState*)tab;
- (void)checkForRecoverableFiles;
- (void)checkExternalStatusForTab:(DietCodeTabState*)tab;
@end
