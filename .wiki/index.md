# Sovereign Knowledge Ledger — DietCode

## Current verified state

DietCode is a fully functional macOS-first native IDE prototype, now hardened with Phase 4 (Stability and Accessibility) systems. The codebase features a layered C++20 core, a native Cocoa/AppKit shell, PTY interactive terminal execution, auto-recovery snapshots, large-file performance modes, full keyboard/VoiceOver support, and built-in High Contrast accessibility themes.

## Verified deliverables

- Product, UX, and performance specifications in `docs/`.
- Portable C++20 core (document models, buffer manipulation, simple undo stack, text searching) in `src/`.
- Native Cocoa/AppKit integration (windows, menus, file outlines, terminals, custom drawing) in `src/platform/macos/`.
- Auto-recovery backing store at `~/.dietcode/backups/`.
- No-dependency unit tests in `tests/test_editor.cpp`.
- Clean Makefile with targets to build, test, run, and clean the application.

## Verified build state

Command executed successfully:

```sh
make clean && make test && make app
```

Observed result:

- `make test` compiles and runs the suite, producing: `All DietCode editor tests passed.`
- `make app` compiles all C++ and Objective-C++ sources into a native, warning-free application bundle `build/DietCode.app`.


## Navigation

- See `.wiki/changelog.md` for exact changes.
- See `.wiki/architecture.md` for layer mapping and boundaries.
- See `.wiki/build-and-test.md` for verified commands.
- See `.wiki/decisions.md` for product and implementation decisions.
