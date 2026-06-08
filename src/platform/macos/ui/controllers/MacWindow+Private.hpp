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

@property(nonatomic, strong) NSSplitView* horizontalSplit;
@property(nonatomic, strong) NSSplitView* verticalSplit;

@property(nonatomic, strong) NSView* filesSidebarView;
@property(nonatomic, strong) NSView* searchSidebarView;
@property(nonatomic, strong) NSView* runSidebarView;
@property(nonatomic, strong) NSView* errorsSidebarView;
@property(nonatomic, strong) NSView* settingsSidebarView;
@property(nonatomic, copy) NSString* currentActivity;
@property(nonatomic, strong) NSButton* lastSelectedActivityBtn;

@property(nonatomic, strong) DietCodeOutlineView* fileTreeView;
@property(nonatomic, strong) NSView* fileTreeEmptyStateView;
@property(nonatomic, copy) NSString* openedFolderPath;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSArray<NSString*>*>* directoryCache;

@property(nonatomic, strong) DietCodeTabState* activeTab;
@property(nonatomic, strong) NSTabView* editorTabView;
@property(nonatomic, strong) NSScrollView* tabHeaderScrollView;
@property(nonatomic, strong) NSStackView* tabHeaderStack;

@property(nonatomic, strong) NSTabView* bottomTabView;
@property(nonatomic, strong) DietCodeTerminalTextView* terminalTextView;
@property(nonatomic, strong) NSTextView* outputTextView;
@property(nonatomic, strong) NSTextView* errorsTextView;
@property(nonatomic, strong) NSTextView* searchResultsTextView;
@property(nonatomic, strong) NSView* bottomPanel;

@property(nonatomic, strong) DietCodeCommandPalettePanel* commandPalettePanel;
@property(nonatomic, strong) NSTextField* paletteSearchField;
@property(nonatomic, strong) NSTableView* paletteTableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* commandPaletteActions;
@property(nonatomic, strong) NSArray<NSDictionary*>* filteredCommandPaletteActions;

@property(nonatomic, strong) NSTask* currentRunTask;
@property(nonatomic, strong) NSTextField* runStatusLabel;
@property(nonatomic, strong) NSTextField* runExplanationLabel;

@property(nonatomic, assign) BOOL searchCancelled;

@property(nonatomic, strong) NSTextField* fontSizeField;
@property(nonatomic, strong) NSButton* wordWrapBtn;
@property(nonatomic, strong) NSButton* autoSaveBtn;
@property(nonatomic, strong) NSPopUpButton* themePopUp;
@property(nonatomic, assign) NSInteger currentFontSize;
@property(nonatomic, assign) BOOL currentWordWrap;
@property(nonatomic, assign) BOOL currentAutoSave;
@property(nonatomic, assign) NSInteger currentThemeIndex;

@property(nonatomic, strong) NSView* gitSidebarView;
@property(nonatomic, strong) NSTextField* gitBranchLabel;
@property(nonatomic, strong) NSTableView* gitChangesTableView;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* gitChanges;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary*>* gitChangesDict;
@property(nonatomic, strong) NSTextField* gitCommitMessageField;
@property(nonatomic, strong) NSView* gitEmptyStateView;
@property(nonatomic, copy) NSString* gitBranchName;

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
@property(nonatomic, assign) BOOL current_lint_on_save;
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

@property(nonatomic, strong) NSMutableDictionary<NSString*, NSMutableArray<NSDictionary*>*>* diagnosticsDict;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* unifiedDiagnostics;
@property(nonatomic, assign) BOOL forceLargeFileModeForNextOpen;

@property(nonatomic, strong) NSTextField* controlActiveLabel;
@property(nonatomic, strong) NSTextView* controlLogTextView;
@property(nonatomic, strong) NSTextField* controlStatusLabel;
@property(nonatomic, strong) NSButton* externalControlBtn;
@property(nonatomic, strong) NSPopUpButton* agentAutonomyBtn;
@property(nonatomic, strong) id controlServer;

@end
