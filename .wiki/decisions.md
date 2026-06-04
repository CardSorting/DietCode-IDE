# Decision Ledger

## Decision: macOS first, native shell

DietCode Phase 1 targets macOS using Objective-C++ and AppKit. This matches the product constraint of a native desktop app without Electron, Chromium, Qt, SDL, ImGui, or third-party dependencies.

## Decision: use `NSTextView` for Phase 1A

The first usable prototype uses native `NSTextView` instead of a custom text renderer.

Reason:

- Native text editing gives keyboard editing, selection, scrolling, undo, clipboard, accessibility roles, and IME behavior immediately.
- A custom editor renderer is a known high-risk subsystem.
- DietCode needs to prove the product loop first: launch, welcome, open, edit, save, status, and safe quit.

Future direction:

- Replace the visible editor behind stable interfaces later with a CoreText/CoreGraphics custom renderer that renders visible lines only.

## Decision: no third-party test framework

Tests use a tiny custom runner in `tests/test_editor.cpp` to preserve the no-third-party-dependency MVP constraint.

## Decision: no background watcher in MVP scaffold

`src/filesystem/FileWatcher.hpp` exists only as a placeholder with `start()` deleted. This preserves architecture space for later file watching while making it impossible for the current prototype to start a hidden watcher.

## Decision: command/documentation first

The repository includes product docs, command catalog, navigation audit, trust/safety rules, and anti-scope checklist before feature growth. This is intentional scope control: DietCode should not accidentally become VSCode again.

## Decision: disabled phase-later UI is explicit

The macOS menu and welcome screen include disabled labels such as `Open Folder (Phase 2)` and `Run Current File (Phase 3)`. This communicates roadmap direction without implementing expensive or scope-expanding systems prematurely.

## Decision: welcome navigation must respect unsaved work

The welcome screen is a safe navigation destination, not a destructive reset. `Open Welcome` now confirms unsaved changes before replacing an active dirty editor. This keeps the beginner-friendly welcome pattern without violating the file-safety rule.

## Decision: generated build output ignored

`.gitignore` ignores `build/`, `.DS_Store`, object files, debug symbol bundles, swap files, and temporary files. The verified app build exists locally after the build command but is not intended as source-controlled content.

## Decision: Keyboard Tab Switching uses Ctrl+Tab and Ctrl+Shift+Tab

macOS natively reserves Cmd+Tab for system-level application switching. Using Ctrl+Tab (next) and Ctrl+Shift+Tab (previous) for editor tab switching avoids conflict with macOS shortcuts while aligning with traditional multi-tab document/browser experiences.

## Decision: Backup Snapshots Debounced to `~/.dietcode/backups/`

To protect users from unsaved work loss during unexpected crashes or power loss without incurring constant disk write overhead, a 1-second debounced save mechanism was built. The backup is stored in a structured path inside a hidden user folder `~/.dietcode/backups/` with custom `.bak` headers, keeping it self-contained and avoiding polluting user project directories.

## Decision: Large File Mode (LFM) Threshold set to 50MB

Files greater than or equal to 50MB prompt a user warning on open. If opened, word wrapping is disabled, rulers are hidden, and AppKit's background layout calculation thread is activated. This keeps the UI thread responsive and prevents scrolling/typing lockups on heavy files.

## Decision: Synchronized High Contrast Themes

High contrast themes (Light and Dark) are essential for accessibility. Choosing a theme through Preferences synchronizes text attributes, selection highlights, cursors, backgrounds, outline borders, and console text views across all panels simultaneously using Cocoa KVO/notification-like synchronization, without introducing complex theme engine libraries.

## Decision: Escape Key as Global Panel Dismissal Handler (`cancelOperation:`)

Escape key handles panel closure (sidebar or bottom console) when focus resides within them. By implementing `cancelOperation:`, we inspect the current window first responder and gracefully hide the relevant panels, avoiding complex global key event monitors or hotkey interceptors.

## Decision: Process Cleanup on Exit

Orphan processes (e.g. interactive PTY terminals or background build runner tasks) could cause resource leaks and lock up file handles on macOS. Hooking into `applicationWillTerminate:` ensures all active subprocesses (terminal pids and runner task instances) are explicitly sent SIGHUP/terminate signals on app termination.

## Decision: Focus State Custom Drawing

To provide a visible focus indicator for screen readers and keyboard users, active panels are enclosed in high contrast borders. Rather than injecting custom layout containers, we hook into window update events to draw dynamic overlays or toggle custom view layer borders.

