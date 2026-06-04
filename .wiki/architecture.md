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
- `src/platform/macos/*.hpp`
- `src/platform/macos/*.mm`

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

## macOS Phase 1A behavior

The macOS prototype uses native AppKit controls:

- `NSApplication`
- `NSWindow`
- `NSMenu`
- `NSOpenPanel`
- `NSSavePanel`
- `NSTextView`
- `NSScrollView`
- `NSButton`
- `NSTextField`

This intentionally prioritizes a usable, native, accessible editor loop before a custom text renderer.

## No-hidden-compute audit

Verified by source inspection of the created prototype:

- No network APIs are used.
- No terminal process is started.
- No folder scan occurs at startup.
- No file watcher is started.
- No extension host exists.
- No AI/agent/marketplace code exists.
- Folder opening is represented only as disabled/phase-later UI copy in the first prototype.
