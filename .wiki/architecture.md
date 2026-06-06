# Architecture Ledger

## Layer map

DietCode follows a layered architecture with a portable C++20 core and a thin native platform shell.

### Pure editor/domain logic

Files:

- `src/editor/Cursor.hpp`
- `src/editor/Selection.hpp`
- `src/editor/TextBuffer.hpp`
- `src/editor/TextBuffer.cpp`
- `src/editor/UndoRedo.hpp`
- `src/editor/EditorDocument.hpp`
- `src/editor/EditorDocument.cpp`
- `src/editor/EditorController.hpp`
- `src/editor/EditorViewModel.hpp`
- `src/search/SearchResult.hpp`
- `src/search/FindInFile.hpp`
- `src/search/FindInFile.cpp`
- `src/syntax/Language.hpp`
- `src/syntax/Token.hpp`
- `src/syntax/Tokenizer.hpp`
- `src/syntax/Highlighter.hpp`
- `src/syntax/Theme.hpp`

Verified boundary:

- These files do not import AppKit/Cocoa.
- These files do not open dialogs.
- These files do not spawn processes.
- These files do not perform network calls.
- The pure editor/search behavior is covered by `tests/test_editor.cpp`.

### Core orchestration

Files:

- `src/core/AppState.hpp`
- `src/core/Command.hpp`
- `src/core/CommandRegistry.hpp`
- `src/core/Config.hpp`
- `src/core/Event.hpp`
- `src/core/Logger.hpp`

Verified boundary:

- Core defines state, commands, config, events, and logging concepts.
- Core does not import AppKit/Cocoa.
- Core does not directly perform filesystem or process operations.

### Infrastructure and platform adapters

Files:

- `src/filesystem/FileService.hpp`
- `src/filesystem/FileService.cpp`
- `src/filesystem/FileTree.hpp`
- `src/filesystem/FileWatcher.hpp`
- `src/filesystem/RecentFiles.hpp`
- `src/filesystem/PathUtils.hpp`
- `src/platform/Platform.hpp`
- `src/platform/Window.hpp`
- `src/platform/NativeMenu.hpp`
- `src/platform/FileDialog.hpp`
- `src/platform/Clipboard.hpp`
- `src/platform/Font.hpp`
- `src/platform/Accessibility.hpp`
- `src/platform/macos/control/MacControlSupport.hpp`
- `src/platform/macos/control/MacControlPathSecurity.hpp`
- `src/platform/macos/control/MacControlSerialization.hpp`
- `src/platform/macos/control/MacControlDiffParsing.hpp`
- `src/platform/macos/control/MacControlRecoveryStore.hpp`
- `src/platform/macos/control/MacControlSearchService.hpp`
- `src/platform/macos/control/MacControlPatchService.hpp`
- `src/platform/macos/control/MacControlTaskRuntime.hpp`
- `src/platform/macos/control/MacControlComboRuntime.hpp`
- `src/platform/macos/control/MacControlRoutingPolicy.hpp`
- `src/platform/macos/control/MacControlMethodCatalog.hpp`
- `src/platform/macos/control/MacControlWindowBridge.hpp`
- `src/platform/macos/ui/*.hpp`
- `src/platform/macos/services/*.hpp`
- `src/platform/macos/**/*.mm`

Verified boundary:

- Disk I/O is isolated in `FileService`.
- Native macOS APIs are isolated in `src/platform/macos/`.
- AppKit file dialogs are isolated in `MacFileDialog`.
- Native clipboard access is isolated in `MacClipboard`.
- `FileWatcher` cannot be started in the current scaffold, preserving the no-background-watcher MVP rule.

### Platform-neutral UI state

Files:

- `src/ui/AppShell.hpp`
- `src/ui/Layout.hpp`
- `src/ui/ActivityBar.hpp`
- `src/ui/Sidebar.hpp`
- `src/ui/EditorArea.hpp`
- `src/ui/Tabs.hpp`
- `src/ui/StatusBar.hpp`
- `src/ui/CommandPalette.hpp`
- `src/ui/WelcomeScreen.hpp`
- `src/ui/SettingsView.hpp`
- `src/ui/BottomPanel.hpp`
- `src/ui/Dialogs.hpp`

Verified boundary:

- UI headers define presentation state and copy.
- UI headers do not perform file I/O.
- UI headers do not spawn processes.

### Plumbing

Files:

- `src/utils/StringUtils.hpp`

Verified boundary:

- Contains stateless helper functions only.

## macOS Prototype Native Integration

The macOS shell integrates native AppKit components:

- `NSApplication` & `NSAppDelegate` (lifecycle management, clean teardown of child processes)
- `NSWindow` & `NSWindowController` (focus border tracking, tab management)
- `NSMenu` (custom keyboard shortcuts, theme switching toggles)
- `NSOpenPanel` & `NSSavePanel` (sandbox-compliant file/folder dialogs)
- `NSTextView` (enhanced with high-contrast text attributes, background layout threads for large files)
- `NSOutlineView` (subclassed as `DietCodeOutlineView` to support keyboard Return to open/toggle items)
- `NSSplitView` (constrained to 150px - 400px widths and stable heights via delegate layout logic)
- `NSTabView` (tabbed workspace editor documents and bottom panel logs)
- `NSScrollView`, `NSButton`, `NSTextField` (for settings, panels, welcome screen actions)

This architecture maintains a dependency-free AppKit/C++ vertical slice, prioritizing responsiveness and macOS platform standards before committing to custom text renderers.

## No-hidden-compute audit

Verified by source inspection of the completed prototype:

- **No unsolicited network APIs**: DietCode does not perform automatic updates, telemetry transmission, or remote system lookups.
- **On-demand interactive terminals**: A local interactive PTY terminal process is started *only* when the terminal panel is toggled and used by the user, and compilation tasks spawn `NSTask` on-demand.
- **Clean subprocess lifecycle**: All spawned subprocesses (PTY shell, runner tasks) are forcibly terminated upon application exit to prevent resource leaks.
- **Lazy folder workspace loading**: Rather than scanning entire projects recursively on startup, workspace files are read and cached lazily as outline tree nodes are expanded by the user.
- **No background file watchers or indexers**: The application avoids background indexing threads, maintaining zero CPU overhead when idle.
- **No extensions or AI systems**: The workspace has no extension host, marketplace code, or hidden AI compute workloads.

