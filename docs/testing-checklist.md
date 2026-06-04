# Testing Checklist

## Pure C++ tests

- Text buffer initializes with one empty line.
- Text buffer splits lines predictably.
- Insert within a line.
- Insert multi-line text.
- Delete range within a line.
- Delete range across lines.
- Editor document dirty state.
- Save acknowledgement resets dirty state.
- Undo and redo.
- Find in file returns line/column matches.

## macOS manual tests

- App launches without opening a terminal or scanning folders.
- Welcome screen appears.
- New File opens editor.
- Typing updates dirty state.
- Save As writes a new file.
- Open File loads content.
- Save writes content.
- Window title shows unsaved indicator.
- Quitting with unsaved changes asks for confirmation.
- Canceling Save As leaves document open and dirty.
- File permission errors show a plain-language alert.

## Performance/trust checks

- No network on launch.
- No terminal process on launch.
- No recursive folder scan on launch.
- Idle CPU near zero.
- No hidden background job is started by the MVP.

## UX checks

- Primary actions are visible.
- Empty states explain what to do next.
- Menu items mirror visible actions.
- Beginner-facing labels avoid jargon.
- The user can tell whether their file is saved.
