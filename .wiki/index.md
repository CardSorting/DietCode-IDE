# Sovereign Knowledge Ledger — DietCode

## Current verified state

DietCode is a greenfield macOS-first native IDE prototype. The repository now contains product documentation, a layered C++20/Objective-C++ source scaffold, pure editor/search primitives, a native AppKit vertical slice, no-dependency tests, and Makefile-based build commands.

## Verified deliverables

- Product and UX documentation exists in `docs/`.
- Build instructions exist in `README.md` and `docs/build-instructions.md`.
- C++20 core/editor/search/filesystem scaffolding exists under `src/`.
- macOS Objective-C++ AppKit shell exists under `src/platform/macos/`.
- Native app bundle build target exists in `Makefile`.
- No-dependency C++ test target exists in `Makefile`.
- Build outputs are ignored by `.gitignore`.

## Verified build state

Command executed successfully:

```sh
make clean && make test && make app
```

Observed result:

- `make test` compiled and ran `build/test_editor`.
- Test output: `All DietCode editor tests passed.`
- `make app` built `build/DietCode.app/Contents/MacOS/DietCode` without reported warnings after the final warning cleanup.

## Navigation

- See `.wiki/changelog.md` for exact changes.
- See `.wiki/architecture.md` for layer mapping and boundaries.
- See `.wiki/build-and-test.md` for verified commands.
- See `.wiki/decisions.md` for product and implementation decisions.
