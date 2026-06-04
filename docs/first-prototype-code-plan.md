# First Prototype Code Plan

## Goal

Build the smallest serious vertical slice that proves DietCode can be a native, quiet IDE:

1. Launch.
2. Welcome.
3. New or open file.
4. Edit.
5. Save.
6. See saved/unsaved state.
7. Quit safely.

## Step order

1. Create product docs and scope guardrails.
2. Add C++20 source layout.
3. Implement pure `TextBuffer`.
4. Implement pure `EditorDocument` dirty/undo model.
5. Implement pure find-in-file.
6. Add no-dependency tests.
7. Add AppKit main window and menus.
8. Add welcome view.
9. Add native text editor view.
10. Add native file dialogs.
11. Add file read/write adapters.
12. Wire status and dirty state.
13. Build and test.
14. Update `.wiki/`.

## Non-goals for first prototype

- Custom text renderer.
- Folder tree.
- Integrated terminal.
- Run current file.
- Syntax highlighting.
- LSP.
- Extensions.
- AI.
- Marketplace.
- Background indexing.
