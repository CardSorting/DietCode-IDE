# Changelog

## 2026-06-08 — Concept papers deepened (brief, philosophy, whitepaper v1.1)

- Archive-as-deliverable framing, coherence-before-drift exposition, validate proof hierarchy
- Philosophy: archive honesty, zombie-product refusal, evidence falsification table
- Whitepaper: archive strategy §1, validation matrix, expanded coherence §5

## 2026-06-08 — Full docs rewrite (kernel/coherence-core strategy)

- Rewrote README + all 23 `docs/*.md` for kernel/coherence-core archive positioning
- Removed cockpit/bridge/IDE framing; Python CLI as sole integration path
- `make validate` documented as primary health check across docs
- ARCHIVE.md aligned with new documentation strategy

## 2026-06-08 — Incremental kernel build + validate speed fix

- Makefile kernel build now uses per-file object compilation (`build/obj/`) instead of monolithic recompile (~45s → ~1s incremental)
- `coherence-core-v0.1` / `validate` build kernel once, then `restart-agent-server-fast` + fast test targets (no redundant full rebuild per sub-make)

## 2026-06-08 — Benchmark + wiki archive cleanup (pass 6)

- Added `benchmarks/agent_success/ARCHIVE_NOTE.md`; archive banners on RESULTS*.md and WHITEPAPER §9
- Replaced stale `make agent-bridge-fast` / `benchmark-agent-success*` references in frozen reports
- `.wiki/architecture.md` reframed as historical ledger with active kernel tree table
- Verify allowlist `make app` → `make kernel` in `docs/kernel-rpc.md` and `MacControlSupport.mm`

## 2026-06-08 — CI + validate gate (pass 5)

- Added `make validate` (`coherence-core-v0.1` + `test-docs-code-drift`)
- Added `.github/workflows/coherence-core.yml` (macOS CI)
- Fixed `dietcode_mutation_authority.collect_bridge_patch_events` — no longer imports removed `dietcode_agent_bundle`
- Docs: `testing.md` benchmark section points at frozen `benchmarks/` tree

## 2026-06-08 — Editor scaffold prune (pass 4)

### Removed orphaned C++ (not used by kernel)
- `src/editor/`, `src/search/`, `src/syntax/`, `src/ui/`, `src/core/`, `src/utils/`
- `src/filesystem/FileWatcher.*`, `tests/test_editor.cpp`
- Kernel build no longer links `LSPClient.mm` or `FileWatcher.mm`
- `make test` now runs `agent-self-test` only; added `ARCHIVE.md` index

## 2026-06-08 — Kernel/coherence-core archive

### Removed experimental surfaces
- Archived and removed `cockpit/`, `legacy_ui/`, `agent-bridge/`, `integrations/`
- Makefile now targets kernel-only build + `coherence-core-v0.1` gate
- Docs reframed as kernel/coherence methodology (`docs/archive-note.md`)

### Preserved
- `dietcode-kernel`, coherence token implementation, RPC harnesses
- `make coherence-core-v0.1` baseline (coherence tokens + recovery smoke)

## 2026-06-04 — Phase 4 Hardening: Stability and Accessibility

### Added keyboard accessibility & VoiceOver
- Added Return key navigation inside `NSOutlineView` using a subclass `DietCodeOutlineView` to open files and toggle folders.
- Added Next Tab (`Ctrl+Tab`) and Previous Tab (`Ctrl+Shift+Tab`) menu items and handlers for editor tab navigation.
- Added Escape (`cancelOperation:`) panel dismissal support for sidebar and bottom panels.
- Added visible focus borders highlighting active panels (editor scroll views, outline views, and terminal scroll views).
- Added accessibility labels and roles for tab headers, tab close buttons, and command palette inputs/lists.

### Added High Contrast themes
- Added **High Contrast Light** and **High Contrast Dark** theme options in preference settings alongside standard Light/Dark/System options.
- Configured stark black/white colors, highly visible selection attributes, text-colored cursors, and custom tab outlines.
- Synchronized theme updating for all text displays (editor, terminal, output console, compiler errors, search results, line ruler, and status bar).

### Added crash recovery & snapshots
- Added automatic temporary recovery snapshot saving to `~/.dietcode/backups/` on a 1-second debounce for dirty files.
- Added Recovery dialog on unclean launch displaying original paths, titles, and modification timestamps with options to **Restore** or **Discard**.
- Added warnings for Save As collisions and external file deletions or modifications upon tab/window focus.

### Added Large File Mode
- Added size checks. Files >= 50MB prompt a warning with options to Open, Open Read-Only, or Cancel.
- Optimized large file view by disabling word wrap, hiding rulers, and enabling background layout threads.

### Added onboarding recents & empty states
- Added "Recent Projects" list to the Welcome screen showing the 5 most recently opened folder workspaces, persisted via `NSUserDefaults`.
- Added friendly placeholders overlayed on empty file tree sidebars, runner outputs, compiler error logs, and search result text views.

### Added stability and cleanup polish
- Implemented `NSSplitViewDelegate` methods to properly constrain the sidebar width (150px - 400px), keep sidebar/terminal heights fixed on window resizing, and resolve layout jumps.
- Restored open tabs and active tab state from previous session on launch.
- Terminated running compiler compilation tasks and interactive PTY terminals on application quit.

## 2026-06-04 — Greenfield DietCode prototype foundation

### Added product documentation

- Added `README.md` with product promise, repository map, build quick start, and scope guard.
- Added `docs/product-spec.md` for product thesis, users, constraints, platform targets, and quality bar.
- Added `docs/ux-navigation-map.md` for familiar IDE layout, beginner labels, first-launch copy, and navigation audit questions.
- Added `docs/beginner-onboarding-flow.md` for optional tutorial behavior and first-run defaults.
- Added `docs/accessibility-checklist.md` for keyboard, focus, label, contrast, and macOS native-control accessibility requirements.
- Added `docs/performance-budget.md` for startup, idle, memory, search, and folder-opening constraints.
- Added `docs/technical-architecture.md` for C++20 portable core, native shells, and layer responsibilities.
- Added `docs/mvp-scope.md` for Phase 1 and Phase 1A acceptance criteria.
- Added `docs/phase-roadmap.md` for Phase 0 through Phase 5.
- Added `docs/file-structure.md` for intended repository structure.
- Added `docs/macos-implementation-plan.md` for AppKit vertical-slice strategy.
- Added `docs/build-instructions.md` for `make test`, `make app`, `make run`, and `make clean`.
- Added `docs/first-prototype-code-plan.md` for implementation order and first-prototype non-goals.
- Added `docs/testing-checklist.md` for C++ tests, macOS manual tests, trust checks, and UX checks.
- Added `docs/anti-scope-checklist.md` for rejected v1 systems.
- Added `docs/navigation-audit.md` for familiar editor patterns and screen review rules.
- Added `docs/trust-and-safety-rules.md` for no-hidden-compute rules and error structure.
- Added `docs/command-catalog.md` for initial command names, menus, shortcuts, descriptions, and phases.

### Added portable C++ scaffolding

- Added `src/core/AppState.hpp` with app-level config, editor controller, activity selection, sidebar state, bottom-panel state, and opened-folder field.
- Added `src/core/Command.hpp` with command metadata and risk classification.
- Added `src/core/CommandRegistry.hpp` with registration, lookup, execution, and listing support.
- Added `src/core/Config.hpp` with theme, density, font, tab, wrap, autosave, and beginner-mode settings.
- Added `src/core/Event.hpp` with initial app event types.
- Added `src/core/Logger.hpp` with in-memory info/warn/error entries.
- Added `src/editor/Cursor.hpp` with cursor position comparison.
- Added `src/editor/Selection.hpp` with text range normalization.
- Added `src/editor/TextBuffer.hpp` and `src/editor/TextBuffer.cpp` with line-based text storage, insert, erase, replace, range text, clamping, and string conversion.
- Added `src/editor/UndoRedo.hpp` with a simple text-snapshot undo/redo stack.
- Added `src/editor/EditorDocument.hpp` and `src/editor/EditorDocument.cpp` with buffer ownership, dirty state, optional path, text mutation, undo/redo, and save acknowledgment.
- Added `src/editor/EditorController.hpp` with active-document management.
- Added `src/editor/EditorViewModel.hpp` with editor title, dirty state, line/column, and language fields.
- Added `src/search/SearchResult.hpp`, `src/search/FindInFile.hpp`, and `src/search/FindInFile.cpp` with case-insensitive and case-sensitive find-in-file support.
- Added `src/search/WorkspaceSearch.hpp` with future folder search result and options structures.
- Added `src/syntax/Language.hpp`, `src/syntax/Token.hpp`, `src/syntax/Tokenizer.hpp`, `src/syntax/Highlighter.hpp`, and `src/syntax/Theme.hpp` as lightweight syntax scaffolding.
- Added `src/utils/StringUtils.hpp` with stateless lowercase and suffix helpers.

### Added filesystem and platform contracts

- Added `src/filesystem/FileService.hpp` and `src/filesystem/FileService.cpp` with text file read/write and existence checks.
- Added `src/filesystem/FileTree.hpp` for future lazy file tree nodes.
- Added `src/filesystem/FileWatcher.hpp` with no start implementation, preserving the MVP no-hidden-watcher boundary.
- Added `src/filesystem/RecentFiles.hpp` for future recent entries.
- Added `src/filesystem/PathUtils.hpp` for path display names.
- Added `src/platform/Platform.hpp`, `src/platform/Window.hpp`, `src/platform/NativeMenu.hpp`, `src/platform/FileDialog.hpp`, `src/platform/Clipboard.hpp`, `src/platform/Font.hpp`, and `src/platform/Accessibility.hpp` as platform abstraction headers.

### Added platform-neutral UI state models

- Added `src/ui/AppShell.hpp` for shell visibility state.
- Added `src/ui/Layout.hpp` for comfortable layout metrics.
- Added `src/ui/ActivityBar.hpp` with beginner activity items: Files, Search, Run, Errors, Settings.
- Added `src/ui/Sidebar.hpp` with Files empty-state copy.
- Added `src/ui/EditorArea.hpp` with welcome/editor flags.
- Added `src/ui/Tabs.hpp` with tab title, active, and dirty state.
- Added `src/ui/StatusBar.hpp` with file, saved state, language, and cursor fields.
- Added `src/ui/CommandPalette.hpp` with visibility/query state.
- Added `src/ui/WelcomeScreen.hpp` with DietCode welcome copy and actions.
- Added `src/ui/SettingsView.hpp` with config-backed state.
- Added `src/ui/BottomPanel.hpp` with output/terminal/errors/search-results tabs.
- Added `src/ui/Dialogs.hpp` with structured user-facing error copy.

### Added macOS native prototype

- Added `resources/Info.plist` for `DietCode.app` metadata.
- Added `src/platform/macos/main.mm` to start `NSApplication`.
- Added `src/platform/macos/MacAppDelegate.hpp` and `src/platform/macos/MacAppDelegate.mm` to create the main window, install menus, show the window, and confirm termination.
- Added `src/platform/macos/MacWindow.hpp` and `src/platform/macos/MacWindow.mm` with native window, beginner-labeled activity bar, Files sidebar, welcome screen, native `NSTextView` editor, status bar, New File, Open File, Save, Save As, unsaved-state title indicator, cursor status, plain-language file errors, and unsaved-close confirmation.
- Added `src/platform/macos/MacMenu.hpp` and `src/platform/macos/MacMenu.mm` with native menu bar entries for DietCode, File, Edit, Selection, View, Go, Run, Terminal, and Help.
- Added `src/platform/macos/MacFileDialog.hpp` and `src/platform/macos/MacFileDialog.mm` using `NSOpenPanel` and `NSSavePanel`.
- Added `src/platform/macos/MacClipboard.hpp` and `src/platform/macos/MacClipboard.mm` using `NSPasteboard`.
- Added `src/platform/macos/MacTextRendering.mm` placeholder documenting that custom CoreText/CoreGraphics rendering is deferred beyond Phase 1A.

### Added build and tests

- Added `Makefile` with `app`, `run`, `test`, `clean`, and `all` targets.
- Added `tests/test_editor.cpp` with no-dependency tests for text buffer basics, document dirty/undo/redo behavior, and find-in-file behavior.
- Added `.gitignore` to ignore generated build artifacts and local OS/editor files.

### Verified

- Ran `make test`; all editor tests passed.
- Ran `make clean && make test && make app`; tests passed and app bundle built successfully.

### Follow-up safety fixes

- Updated `src/platform/macos/MacWindow.mm` so `Open Welcome` confirms unsaved changes before replacing the editor with the welcome screen.
- Updated `src/platform/macos/MacWindow.mm` so choosing `Close Without Saving` clears the dirty flag before allowing close/discard flows, avoiding a second quit prompt.
- Updated `src/platform/macos/MacWindow.mm` so document loading sets `loadingDocument` before populating `NSTextView`, preventing opened files from being marked dirty during initial text assignment.
