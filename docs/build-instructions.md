# Build Instructions

## Requirements

- macOS.
- Xcode Command Line Tools.
- `clang++`.
- `make`.

No third-party package manager is required for the MVP.

## Run tests

```sh
make test
```

This compiles a small no-dependency C++ test runner for pure editor/search code.

## Build app bundle

```sh
make app
```

The app bundle is created at:

```text
build/DietCode.app
```

## Launch app

```sh
make run
```

## Clean generated files

```sh
make clean
```

## Build philosophy

- Use platform build tools only.
- Keep the Makefile understandable.
- Avoid package managers for the MVP.
- Add CMake only when multi-platform complexity requires it.
