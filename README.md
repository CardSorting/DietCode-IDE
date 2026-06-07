<p align="center">
  <img src="resources/AppIcon.icns" width="128" height="128" alt="DietCode Logo">
</p>

<h1 align="center">DietCode IDE</h1>

<p align="center">
  <strong>The High-Fidelity, Agent-Native Coding Workspace.</strong><br>
  <em>Open. Code. Run. Save. Zero Surprise Compute.</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg" alt="Language">
</p>

---

**DietCode** is a native, lightweight IDE engineered for developers and autonomous agents who demand a high-performance, predictable, and local-first coding environment. It eliminates the "compute tax" of modern editors by stripping away hidden background indexing, telemetry, and extension-host overhead.

## 🤖 Built for Agents: The Headless Control Surface

Unlike editors with bolted-on AI plugins, DietCode is designed from the ground up as an **Agentic IDE**. It exposes a massive JSON-RPC surface over a local Unix socket, enabling external agents to perform high-fidelity workspace operations.

- **Deterministic Runtime:** Operations are executed as atomic **Chips**, which can be composed into stateful, recoverable **Combos**.
- **Deep Visibility:** Agents have native access to symbol outlines, diagnostic clusters, git status, and terminal scrollback.
- **Transactional Safety:** Built-in validation and rollback support for complex multi-file edits and patches.
- **Duplex Observability:** Real-time event subscriptions (LSP diagnostics, file saves, focus changes) via the socket.

## ⚡ Technical Architecture

DietCode follows a strict layered architecture to ensure portability and native performance:

- **Core (C++20):** Platform-agnostic domain logic, including the high-performance text buffer, search algorithms, and command registry.
- **Native Shell (Obj-C++/AppKit):** Zero-latency macOS integration using native Cocoa components for windows, menus, and the primary editing surface.
- **Control Server:** A dedicated thread managing the Unix socket, providing thread-safe access to the editor's state and infrastructure.
- **PTY Execution:** A native pseudo-terminal implementation for low-overhead subprocess management and interactive tool execution.

## 🧠 The "Diet" Philosophy

We prioritize **predictability** and **sovereignty**:
- 🚫 **No Background Indexing:** Symbols are indexed on-demand or during idle periods with explicit limits.
- 🚫 **No Extension Bloat:** Core features are built-in; no package managers or dependency hell.
- 🚫 **No Hidden Daemons:** When you quit DietCode, every related process dies.
- 🚫 **Privacy by Default:** Zero telemetry. Your code and interaction data never leave your machine.

## 🏗️ Repository Mapping

```text
docs/                 Technical specs, agent protocol, and architectural guides.
scripts/              Python SDK and integration test suites for the agent API.
src/core/             The portable C++20 editor core.
src/platform/macos/   AppKit shell, PTY terminal, and JSON-RPC control server.
src/editor/           Domain primitives: Buffer, Cursor, Selection, Undo/Redo.
src/filesystem/       Native I/O adapters and Git integration service.
.wiki/                The Sovereign Knowledge Ledger (Internal decision logs).
```

## 🛠️ Build & Development

DietCode uses standard platform tools for maximum transparency.

```bash
# Verify the core logic
make test

# Compile the native macOS bundle
make app

# Launch the IDE
make run
```

*See [docs/build-instructions.md](docs/build-instructions.md) for environment details.*

## 📄 License

DietCode is open-source software released under the [MIT License](LICENSE).

---

<p align="center">
  <em>Small tools are good tools. High-fidelity tools are better.</em>
</p>
