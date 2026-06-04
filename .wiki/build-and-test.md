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

## Manual testing still required

The app bundle builds, but these UI behaviors still need manual runtime validation:

- Welcome window display.
- New File button/menu action.
- Open File native dialog.
- Text editing in `NSTextView`.
- Save and Save As writing to disk.
- Unsaved close confirmation.
- File error alerts.
- Status bar cursor updates.
