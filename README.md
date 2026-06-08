<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode IDE</h1>

<p align="center">
  <strong>A native, local-first IDE with a deterministic agent control surface.</strong><br>
  <em>C++20 core. macOS shell. Unix-socket JSON-RPC for automation.</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg?style=for-the-badge" alt="Language">
</p>

---

## What this is

DietCode is a smaller, calmer, native macOS IDE for people who want a familiar editing workspace without the compute tax of modern Electron-based editors. It is local-first, offline-first, and built from a portable C++20 core with an Objective-C++ / AppKit shell.

The project also ships a **headless agent control surface**: a JSON-RPC server on a local Unix socket (`~/.dietcode/control.sock`) that exposes workspace search, patch application, diff inspection, terminal execution, and workspace state — with frozen contracts, NDJSON test harnesses, and a verification ladder.

> Open. Code. Run. Save. No jet engine.

Full product constraints and positioning: [Product Specification](docs/product-spec.md).

---

## What DietCode is not

Intentionally excluded to keep the footprint small:

- Electron, Chromium, Qt, or extension-host complexity
- Background repo-wide indexing, telemetry, or hidden daemons
- Semantic search, embeddings, fuzzy matching, or probabilistic ranking on agent surfaces
- Cloud defaults, account systems, or AI-by-default features

See [Anti-Scope Checklist](docs/anti-scope-checklist.md) and [MVP Scope](docs/mvp-scope.md).

---

## Agent control surface (current state)

The headless control runtime is hardened as a **deterministic local transaction kernel** (Passes I–VI). Agents interact through literal grep/search, validated patches with stale-write guards, monotonic workspace revision, and a frozen `tool.registry` of agent-safe methods.

| Capability | Methods / behavior |
|------------|-------------------|
| Literal search | `workspace.grep`, `search.literal`, `search.tokens`, `search.references` |
| Patch workflow | `patch.validate` → `expectBeforeHash` → `patch.apply` → `mutationReceipt` |
| Workspace state | `workspace.revision`, `workspace.snapshot`, `operation.status` |
| Batch mutations | `patch.applyBatch` with atomic rollback |
| Agent catalog | `tool.registry`, `tool.capabilities` |
| Quarantined | `search.semantic`, `analysis.searchRanked` → `4008` (use deterministic replacements) |

Canonical audit record: [Agent Runtime Audit](docs/agent-runtime-audit.md).

```bash
make app
make restart-agent-server          # required after C++ control-server changes
make verify-agent-runtime-full     # release-grade ladder
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
```

Python client and CLI shortcuts: [Headless Agent Control](docs/headless-agent-control.md).

---

## Quick start

### Prerequisites

- macOS 12+ (primary target)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3 (agent tests and integration scripts)

### Build and test

```bash
git clone <repo-url> DietCode-IDE
cd DietCode-IDE

make test          # C++ editor unit tests + offline agent self-test
make app           # build build/DietCode.app
```

### Run

```bash
make run           # interactive IDE
make headless      # headless control server (no window)
make agent-ready   # wait for socket + RPC readiness
make agent-status  # readiness JSON
```

### Verify agent runtime

```bash
make test-agent-offline            # no socket
make verify-agent-runtime          # daily ladder (14 checks)
make verify-agent-runtime-full     # release ladder (workflow + docs drift + closure)
```

Full target reference: [Build & Test System](docs/build-and-test-system.md).

---

## Architecture

```text
  [ Agents / scripts ]              [ Human developer ]
         |                                  |
   Unix socket JSON-RPC              Native Cocoa UI
         |                                  |
         v----------------------------------v
              MacControlServer (read + execution queues)
                         |
              Portable C++20 domain core
         (TextBuffer, Search, Undo, LSP client, Event bus)
                         |
              Infrastructure (Git, PTY, file watcher)
```

Layer details: [Technical Architecture](docs/technical-architecture.md), [Editor Internals](docs/editor-internals.md), [Expert Socket Server](docs/expert-socket-server.md).

Repository layout: [File Structure](docs/file-structure.md).

---

## Documentation

| Start here | Contents |
|------------|----------|
| [Documentation Index](docs/README.md) | Full map of all specs and guides |
| [Getting Started Tutorial](docs/getting-started-tutorial.md) | First build, run, and contribution |
| [Agent Integration Cookbook](docs/agent-integration-cookbook.md) | Python recipes for automation |
| [Agent Runtime Audit](docs/agent-runtime-audit.md) | Passes I–VI implementation record |
| [Build Instructions](docs/build-instructions.md) | Compile and run from source |
| [Testing Checklist](docs/testing-checklist.md) | Pre-merge verification |
| [FAQ & Troubleshooting](docs/faq-and-troubleshooting.md) | Common build and agent issues |
| [Maintainer Guide](docs/maintainer-guide.md) | How to extend RPC surfaces safely |

Historical decision logs: [Sovereign Knowledge Ledger](.wiki/index.md).

---

## Key Makefile targets

| Target | Purpose |
|--------|---------|
| `make app` | Build `build/DietCode.app` |
| `make test` | C++ unit tests + `agent-self-test` |
| `make restart-agent-server` | Rebuild and restart headless server |
| `make control-smoke` | Live RPC smoke (NDJSON) |
| `make test-grep-diff-tooling` | Pass I — grep/diff/patch contracts |
| `make test-runtime-determinism` | Pass II — stale writes, mutation receipts |
| `make test-transaction-kernel` | Pass III — revision, batch atomicity |
| `make test-harness-realism` | Pass IV — symlinks, transport, concurrency |
| `make test-deterministic-retrieval` | Pass V — semantic quarantine, tool registry |
| `make test-agent-workflow-smoke` | Pass VI — end-to-end agent workflows |
| `make release-check-agent-runtime` | Release gate |

---

## License

DietCode is open-source software released under the [MIT License](LICENSE).
