# MVP Scope

## Phase 1 required features

- Native window.
- Welcome screen.
- Open file.
- New file.
- Edit text.
- Save.
- Save As.
- Unsaved changes indicator.
- Tabs, at least basic active document representation.
- Line numbers later within Phase 1B/custom editor.
- Cursor movement through native editor in first vertical slice.
- Mouse selection through native editor.
- Keyboard selection through native editor.
- Copy/paste through native editor.
- Undo/redo through native editor and pure editor tests.
- Find in file.
- Status bar.
- Basic settings.
- Light/dark theme awareness.
- Graceful file errors.

## MVP acceptance criteria

A user can:

1. Open DietCode.
2. Click Open File.
3. Edit a file.
4. Save the file.
5. Open another file in a tab in Phase 1B.
6. Use Find.
7. See line/column.
8. Change font size.
9. Quit without losing unsaved work.

## Phase 1A acceptance criteria for this repository

- App launches on macOS.
- Welcome screen appears.
- New File creates an editable untitled document.
- Open File loads file contents.
- Save writes current content.
- Save As writes to selected path.
- Window title/status show unsaved state.
- No background scan, no network, no terminal process.
