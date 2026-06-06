#pragma once

#import "MacWindow.hpp"
#include "filesystem/FileService.hpp"
#include "MacFileDialog.hpp"
#include "core/LSPClient.hpp"

@class DietCodeTabState;
@class DietCodeOutlineView;
@class DietCodeTerminalTextView;
@class DietCodeCommandPalettePanel;
@class DietCodeNavigationTextView;

@interface DietCodeWindowController () {
@public
    dietcode::filesystem::FileService fileService_;
    dietcode::platform::macos::MacFileDialog fileDialog_;
    int terminalMasterFd_;
    pid_t terminalPid_;
    dietcode::lsp::LSPClient* cppLspClient_;
    dietcode::lsp::LSPClient* pythonLspClient_;
    dietcode::lsp::LSPClient* tsLspClient_;
}

@property(nonatomic, strong) NSView* rootView;
@property(nonatomic, strong) NSStackView* activityBar;
@property(nonatomic, strong) NSView* sidebarView;
@property(nonatomic, strong) NSView* sidebarInnerView;
@property(nonatomic, strong) NSView* editorHostView;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, assign) BOOL hasDocument;
@property(nonatomic, assign) BOOL loadingDocument;
@property(nonatomic, strong) NSTextView* textView;

// Split Views
@property(nonatomic, strong) NSSplitView* horizontalSplit;
@property(nonatomic, strong) NSSplitView* verticalSplit;

// Navigation & Sidebar panels
@property(nonatomic, strong) NSView* filesSidebarView;
@property(nonatomic, strong) NSView* searchSidebarView;
@property(nonatomic, strong) NSView* runSidebarView;
@property(nonatomic, strong) NSView* errorsSidebarView;
@property(nonatomic, strong) NSView* settingsSidebarView;
@property(nonatomic, copy) NSString* currentActivity;
@property(nonatomic, strong) NSButton* lastSelectedActivityBtn;

// File Tree & Outline View
@property(nonatomic, strong) DietCodeOutlineView* fileTreeView;
@property(nonatomic, strong) NSView* fileTreeEmptyStateView;
@property(nonatomic, copy) NSString* openedFolderPath;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSArray<NSString*>*>* directoryCache;

// Tabbed Editor State
@property(nonatomic, strong) DietCodeTabState* activeTab;
@property(nonatomic, strong) NSTabView* editorTabView;
@property(nonatomic, strong) NSScrollView* tabHeaderScrollView;
@property(nonatomic, strong) NSStackView* tabHeaderStack;

// Bottom Panel
@property(nonatomic, strong) NSTabView* bottomTabView;
@property(nonatomic, strong) DietCodeTerminalTextView* terminalTextView;
@property(nonatomic, strong) NSTextView* outputTextView;
@property(nonatomic, strong) NSTextView* errorsTextView;
@property(nonatomic, strong) NSTextView* searchResultsTextView;
@property(nonatomic, strong) NSView* bottomPanel;

// Command Palette Popup
@property(nonatomic, strong) DietCodeCommandPalettePanel* commandPalettePanel;
@property(nonatomic, strong) NSTextField* paletteSearchField;
@property(nonatomic, strong) NSTableView* paletteTableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* commandPaletteActions;
@property(nonatomic, strong) NSArray<NSDictionary*>* filteredCommandPaletteActions;

// Run Process
@property(nonatomic, strong) NSTask* currentRunTask;
@property(nonatomic, strong) NSTextField* runStatusLabel;
@property(nonatomic, strong) NSTextField* runExplanationLabel;

// Search Flags
@property(nonatomic, assign) BOOL searchCancelled;

// Preferences Settings variables
@property(nonatomic, strong) NSTextField* fontSizeField;
@property(nonatomic, strong) NSButton* wordWrapBtn;
@property(nonatomic, strong) NSButton* autoSaveBtn;
@property(nonatomic, strong) NSPopUpButton* themePopUp;
@property(nonatomic, assign) NSInteger currentFontSize;
@property(nonatomic, assign) BOOL currentWordWrap;
@property(nonatomic, assign) BOOL currentAutoSave;
@property(nonatomic, assign) NSInteger currentThemeIndex; // 0: System, 1: Light, 2: Dark

// Git properties
@property(nonatomic, strong) NSView* gitSidebarView;
@property(nonatomic, strong) NSTextField* gitBranchLabel;
@property(nonatomic, strong) NSTableView* gitChangesTableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* gitChanges;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary*>* gitChangesDict;
@property(nonatomic, strong) NSTextField* gitCommitMessageField;
@property(nonatomic, strong) NSView* gitEmptyStateView;
@property(nonatomic, copy) NSString* gitBranchName;

// Language Features Settings properties
@property(nonatomic, strong) NSButton* formatOnSaveBtn;
@property(nonatomic, strong) NSButton* lintOnSaveBtn;
@property(nonatomic, strong) NSButton* diagnosticsBtn;
@property(nonatomic, strong) NSTextField* clangdPathField;
@property(nonatomic, strong) NSTextField* pyrightPathField;
@property(nonatomic, strong) NSTextField* tsserverPathField;
@property(nonatomic, strong) NSTextField* clangFormatPathField;
@property(nonatomic, strong) NSTextField* blackPathField;
@property(nonatomic, strong) NSTextField* prettierPathField;
@property(nonatomic, strong) NSTextField* clangTidyPathField;
@property(nonatomic, strong) NSTextField* ruffPathField;
@property(nonatomic, strong) NSTextField* eslintPathField;

@property(nonatomic, assign) BOOL currentFormatOnSave;
@property(nonatomic, assign) BOOL current_lint_on_save; // Fixed typo in property name if any
@property(nonatomic, assign) BOOL currentLintOnSave;
@property(nonatomic, assign) BOOL currentDiagnosticsEnabled;
@property(nonatomic, copy) NSString* clangdPath;
@property(nonatomic, copy) NSString* pyrightPath;
@property(nonatomic, copy) NSString* tsserverPath;
@property(nonatomic, copy) NSString* clangFormatPath;
@property(nonatomic, copy) NSString* blackPath;
@property(nonatomic, copy) NSString* prettierPath;
@property(nonatomic, copy) NSString* clangTidyPath;
@property(nonatomic, copy) NSString* ruffPath;
@property(nonatomic, copy) NSString* eslintPath;

// Diagnostics properties
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSMutableArray<NSDictionary*>*>* diagnosticsDict;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* unifiedDiagnostics;
@property(nonatomic, assign) BOOL forceLargeFileModeForNextOpen;

// Control Surface properties
@property(nonatomic, strong) NSTextField* controlActiveLabel;
@property(nonatomic, strong) NSTextView* controlLogTextView;
@property(nonatomic, strong) NSTextField* controlStatusLabel;
@property(nonatomic, strong) NSButton* externalControlBtn;
@property(nonatomic, strong) NSPopUpButton* agentAutonomyBtn;
@property(nonatomic, strong) id controlServer; // Typed loosely as id to avoid cyclic header imports

// Layout & UI
- (void)buildInterface;
- (void)buildBottomTabViews;
- (void)prepareSidebarPanels;
- (void)setupFilesUI;
- (void)setupSearchUI;
- (void)setupRunUI;
- (void)setupGitUI;
- (void)setupSettingsUI;
- (void)setupErrorsUI;
- (void)setupActivityBar;
- (void)applyThemeColors;
- (BOOL)isDarkTheme;
- (BOOL)isHighContrastTheme;
- (void)updateFocusBorders;
- (void)addPlaceholder:(NSString*)placeholder toTextView:(NSTextView*)textView;
- (void)updatePlaceholderVisibility:(NSTextView*)textView;
- (void)selectActivity:(NSString*)activity;
- (void)updateWindowTitleAndStatus;
- (void)showErrorWithTitle:(NSString*)title
              whatHappened:(NSString*)whatHappened
                  nextStep:(NSString*)nextStep
                    safety:(NSString*)safety
                   details:(NSString*)details;
- (void)showErrorWithTitle:(NSString*)title message:(NSString*)message;

// Tab Management
- (void)showEditorWithText:(NSString*)text path:(NSString*)path dirty:(BOOL)isDirty;
- (void)createTabHeaderButton:(DietCodeTabState*)tab;
- (void)activateTab:(DietCodeTabState*)tab;
- (void)closeTab:(DietCodeTabState*)tab;
- (void)updateTabHeaderLayout;
- (void)saveOpenTabsState;
- (void)restoreOpenTabs;
- (void)saveTab:(DietCodeTabState*)tab;

// Files & Recent
- (void)openFileFromPath:(NSString*)path;
- (void)addToRecentFolders:(NSString*)path;
- (void)addToRecentFiles:(NSString*)path;
- (void)refreshFilesTree:(id)sender;
- (NSString*)getSelectedOutlinePath;
- (void)openWorkspaceFolder:(NSString*)path;

// Git
- (void)refreshGitStatus;
- (void)applyDiffColoring:(NSTextView*)textView;

// Language & Diagnostics
- (NSString*)detectLanguage:(NSString*)path;
- (dietcode::lsp::LSPClient*)lspClientForLanguage:(NSString*)language;
- (void)startLSPForLanguage:(NSString*)language;
- (void)stopLSPForLanguage:(NSString*)language;
- (NSString*)autoDetectBinaryForLanguage:(NSString*)language type:(NSString*)type;
- (void)promptLanguageFeaturesIfNeeded:(NSString*)filePath;
- (void)handleDiagnostics:(NSArray*)newDiags forFile:(NSString*)filePath source:(NSString*)source;
- (NSArray*)diagnosticsForTabPath:(NSString*)path lineNumber:(NSUInteger)line;
- (void)updateDiagnosticsHighlightsForTab:(DietCodeTabState*)tab;
- (void)rebuildProblemsPanel;
- (void)formatTab:(DietCodeTabState*)tab;
- (void)runLinterForTab:(DietCodeTabState*)tab;
- (NSMutableArray*)parseLinterOutput:(NSString*)output errorOutput:(NSString*)errorOutput language:(NSString*)language filePath:(NSString*)filePath;
- (NSArray*)parseCompilerOutput:(NSString*)output;
- (void)logOutput:(NSString*)text;
- (void)showErrorAlert:(NSString*)title message:(NSString*)message;
- (BOOL)checkAndPromptLSPForLanguage:(NSString*)language filePath:(NSString*)filePath;
- (BOOL)isLanguageFeaturesEnabledForPath:(NSString*)filePath language:(NSString*)language;
- (void)handleMouseHoverInTextView:(NSTextView*)textView atPoint:(NSPoint)point;

// Search
- (void)appendSearchResult:(NSString*)text;
- (void)navigateFromProblemsOrSearchText:(NSString*)line sender:(id)sender;

// Run & Terminal
- (void)runCPPCompilation:(NSString*)filePath;
- (void)executeTask:(NSString*)launchPath arguments:(NSArray*)args;
- (void)updateRunStatus:(NSString*)status success:(BOOL)ok;
- (void)appendOutputText:(NSString*)text;
- (void)setupTerminalProcess;
- (void)appendTerminalText:(NSString*)text;
- (void)ensureTerminalProcess;

// Recovery
- (NSString*)getBackupDirectory;
- (void)saveBackupForTab:(DietCodeTabState*)tab;
- (void)deleteBackupForTab:(DietCodeTabState*)tab;
- (void)checkForRecoverableFiles;
- (void)checkExternalStatusForTab:(DietCodeTabState*)tab;

// Command Palette
- (void)setupCommandPalette;
- (void)filterPaletteActions:(NSString*)query;
- (void)closePaletteHUD;

// RPC / Agent
- (void)notifyAgentEvent:(NSString*)type detail:(NSString*)detail;

@end
