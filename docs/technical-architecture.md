# Technical Architecture

## Architecture summary

DietCode has a portable C++20 core and thin native platform shells. The macOS shell uses Objective-C++ and AppKit. The Windows shell will later use Win32 and DirectWrite. Linux will be approached honestly later.

## Layer model

### Domain / editor logic

Location:

- `src/editor/`
- `src/search/`
- `src/syntax/`

Responsibilities:

- Text buffer.
- Cursor and selection.
- Undo/redo.
- Search result models.
- Lightweight language/token models.

Rules:

- No AppKit.
- No filesystem dialogs.
- No process APIs.
- Testable without mocks.

### Core / orchestration

Location:

- `src/core/`

Responsibilities:

- App state.
- Config.
- Commands.
- Command registry.
- Events.
- Logging.

Rules:

- Orchestrates; does not implement platform I/O.
- Talks to infrastructure through interfaces or small adapters.

### Infrastructure / external world

Location:

- `src/filesystem/`
- `src/platform/`
- `src/platform/macos/`
- `src/run/` later

Responsibilities:

- File reads/writes.
- Native windows.
- Native menus.
- Native file dialogs.
- Native clipboard.
- Process running later.

### UI / presentation models

Location:

- `src/ui/`

Responsibilities:

- App shell concepts.
- Layout concepts.
- Status bar model.
- Welcome screen copy and actions.
- Sidebar and tab models.

### Plumbing / stateless helpers

Location:

- `src/utils/`

Responsibilities:

- String helpers.
- UTF-8 safety helpers.
- Small pure utilities.

## macOS vertical slice strategy

The first prototype uses `NSTextView` as the visible editing surface. This keeps the MVP native, dependency-free, accessible, and usable quickly. Pure C++ editor primitives are still implemented and tested, but custom text rendering is deferred until the document lifecycle and navigation model are stable.

## Why this is industry-standard

Text editors are difficult. Native text controls provide accessibility, keyboard editing, selection, scrolling, clipboard, and IME behavior immediately. DietCode should prove its product loop first: launch, welcome, open, edit, save, and status.

## Future custom editor renderer

When replacing `NSTextView`, the custom editor must:

- Render visible lines only.
- Use predictable monospace measurement.
- Handle common UTF-8 safely.
- Provide selection, cursor, keyboard navigation, and mouse selection.
- Preserve accessibility behavior.
- Avoid full Unicode perfection in v1.
