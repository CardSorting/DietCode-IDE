DietCode
========

DietCode is a lightweight, native, VSCode-like IDE prototype for people who want a familiar coding workspace without surprise compute cost.

Product promise:

> Open. Code. Run. Save. No jet engine.

DietCode is macOS-first in this repository. It uses C++20 for the portable core and Objective-C++/AppKit for the native shell. The MVP intentionally avoids Electron, Chromium, Qt, SDL, ImGui, package managers, telemetry, cloud accounts, background indexing, extension hosts, AI defaults, hidden daemons, and automatic sync.

Current prototype goals
-----------------------

- Native macOS window and menu bar.
- Calm welcome screen with obvious beginner actions.
- New File, Open File, Save, and Save As.
- Editable native text surface for the first vertical slice.
- Unsaved-change indicator.
- Simple status bar.
- Pure C++ editor/search primitives with no third-party test framework.
- Documentation that preserves the product boundary before feature growth.

Repository map
--------------

```text
docs/                 Product, UX, architecture, performance, and testing docs
src/core/             Application orchestration models and command registry
src/editor/           Pure C++ editor domain primitives
src/filesystem/       File I/O adapters
src/platform/         Platform contracts
src/platform/macos/   AppKit Objective-C++ shell
src/search/           Pure search models and algorithms
src/syntax/           Lightweight syntax model scaffolding
src/ui/               Platform-neutral UI view models/concepts
src/utils/            Stateless helpers
tests/                No-dependency C++ test runner
.wiki/                Sovereign Knowledge Ledger
```

Build quick start
-----------------

Requirements:

- macOS
- Xcode Command Line Tools with `clang++` and `make`

Commands:

```sh
make test
make app
make run
```

See `docs/build-instructions.md` for details.

Scope guard
-----------

DietCode v1 does not include extensions, LSP, debugger, remote containers, cloud sync, account login, AI chat, marketplace, background embeddings, or automatic project graph generation.

Small tools are good tools.
