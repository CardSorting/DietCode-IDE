# Build and Test Ledger

## Build system

Build file:

- `Makefile`

Targets:

- `make test` — builds and runs the pure C++ editor/search test runner.
- `make app` — builds `build/DietCode.app` using `clang++`, C++20, Objective-C++ ARC, and the Cocoa framework.
- `make run` — builds and opens the app bundle.
- `make clean` — removes `build/`.
- `make all` — builds app and tests.

## Verified commands

### Test-only verification

Command:

```sh
make test
```

Observed output:

```text
All DietCode editor tests passed.
```

### Clean build verification

Command:

```sh
make clean && make test && make app
```

Observed facts:

- `build/` was removed.
- `build/test_editor` was rebuilt.
- `build/test_editor` ran successfully.
- `build/DietCode.app/Contents/Info.plist` was copied from `resources/Info.plist`.
- `build/DietCode.app/Contents/MacOS/DietCode` was built successfully.

### Post-ledger safety-fix verification

After unsaved-change flow fixes in `src/platform/macos/MacWindow.mm`, the following command was run again:

```sh
make clean && make test && make app
```

Observed facts:

- The no-dependency editor/search tests still passed.
- The macOS app bundle still built successfully.

## Test coverage currently present

File:

- `tests/test_editor.cpp`

Covered behaviors:

- Empty text buffer starts with one empty line.
- Single-line text insertion.
- Multi-line text insertion.
- Cross-line erase and merge.
- Editor document starts clean when constructed with text.
- Document insert marks dirty.
- Undo restores previous text.
- Redo restores next text.
- `markSaved` clears dirty state.
- Case-insensitive find returns expected matches.
- Case-sensitive find returns expected matches.

## Manual Verification Checklist

The application requires runtime verification of native macOS AppKit user flows:

### 1. Core Editor Operations
- **Welcome Screen**: Launches on clean start, offers "New File", "Open File", and "Open Folder" options.
- **Recent Projects**: Displays up to 5 previously opened folders on the Welcome Screen; clicking one loads that workspace.
- **Editing & Save Loop**: Typing in the editor updates dirty state (unsaved dot in window title, status bar). Cmd+S saves to disk; Cmd+Shift+S triggers "Save As".
- **External Changes**: Modifying or deleting an open file externally shows a conflict dialog upon window/tab focus.

### 2. Keyboard Navigation & Focus
- **Sidebar Navigation**: Navigating folders in the sidebar file tree using Arrow keys; pressing **Return** opens the selected file or expands/collapses folders.
- **Tab Switching**: Pressing **Ctrl+Tab** switches to the next document tab; **Ctrl+Shift+Tab** switches to the previous tab.
- **Panel Dismissal**: Pressing **Escape** dismisses the sidebar or bottom panel when the keyboard focus is inside them.
- **Visual Focus Borders**: High-contrast outline borders dynamically redraw around the active panel (Editor, Sidebar, or Terminal/Output console) when navigating via Tab/mouse.

### 3. VoiceOver & Screen Readers
- Accessibility roles and labels are populated for custom controls:
  - Close buttons on tabs have descriptions.
  - Tab button items declare `@"AXTab"` accessibility roles.
  - Interactive input fields and buttons have helpful labels.

### 4. High Contrast & Styling
- Opening Preferences and choosing **High Contrast Light** or **High Contrast Dark** switches all panels (editor text, line ruler, sidebar, terminal, console outputs, status bar) to stark contrasting color configurations.
- Selection attributes set a bright yellow (for Dark theme) or blue (for Light theme) highlight for legibility.

### 5. Crash Recovery Snapshots
- Edit a file without saving (wait 1 second for debounced backup).
- Kill the app process.
- Restart the app. A Recovery Dialog should display original file metadata and offer to **Restore** or **Discard**.
- Select **Restore** to reload changes back into the active session.

### 6. Large File Handling
- Open a file >= 50MB. A warning dialog should present options to **Open**, **Open Read-Only**, or **Cancel**.
- Select **Open** and verify that the editor remains responsive (wrapping disabled, rulers hidden, background text layout calculations enabled).

### 7. Process Cleanup
- Launch an interactive terminal via **Terminal -> Toggle Terminal**.
- Run a compiler or long-running command.
- Quit DietCode. Verify in Activity Monitor that no orphan `zsh` or compiler processes associated with DietCode remain active.

