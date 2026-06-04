# macOS-First Implementation Plan

## Native shell

The macOS shell uses Objective-C++ and AppKit:

- `NSApplication`
- `NSWindow`
- `NSMenu`
- `NSOpenPanel`
- `NSSavePanel`
- `NSTextView`
- `NSScrollView`
- `NSButton`
- `NSTextField`

## Phase 1A vertical slice

1. Start `NSApplication` from `main.mm`.
2. Create `DietCodeAppDelegate`.
3. Build native menus with standard shortcuts.
4. Create a main window.
5. Show an AppKit welcome screen.
6. Wire New File, Open File, Save, Save As.
7. Use `NSTextView` as the first editor surface.
8. Track current path and dirty state.
9. Update title and status bar.
10. Confirm before quitting with unsaved changes.

## Why `NSTextView` first

It provides native keyboard editing, selection, copy/paste, undo, scrolling, accessibility, and IME behavior immediately. This lets DietCode validate the product loop before investing in a custom renderer.

## Later custom renderer

When the MVP shell is stable, replace the visible editor behind a stable editor interface. Use CoreText/CoreGraphics for text measurement and drawing. Render visible lines only.

## No hidden compute rules

On startup, the macOS app must not:

- Start a terminal.
- Scan a folder.
- Start a watcher.
- Spawn a compiler or interpreter.
- Make a network request.
- Load extension hosts.
