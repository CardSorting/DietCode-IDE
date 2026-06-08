<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode IDE</h1>

<p align="center">
  <strong>A native, local-first macOS IDE with a bundled agent control stack.</strong><br>
  <em>C++20 core · AppKit shell · Agent Bridge · deterministic runtime journal</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg?style=for-the-badge" alt="Language">
</p>

---

## What this is

DietCode is a smaller, calmer, native macOS IDE — local-first, offline-first, built from a portable C++20 core with an Objective-C++ / AppKit shell. No Electron. No background indexing tax. No cloud defaults.

It also ships a **deterministic agent control stack**: a C++ mutation kernel behind a Unix-socket JSON-RPC runtime, wrapped by a **bundled Agent Bridge** that gives external agents a stable TypeScript API and CLI. You install one app; agents get safe search, patch, and observability workflows without calling raw RPC.

> Open. Code. Run. Save. No jet engine.

Product positioning: [Product Specification](docs/product-spec.md).

---

## Strategy: one app, three layers

```text
  [ External agents ]     [ Human developer ]
         |                        |
   Agent Bridge              Native Cocoa UI
   (TypeScript, bundled)     (editor, tabs, terminal)
         |                        |
         +------------+-----------+
                      |
            DietCode Runtime RPC
            (~/.dietcode/control.sock)
                      |
         +------------+-----------+
         |                        |
   C++ mutation kernel    BroccoliQ runtime journal
   (patch, stale guards)  (timeline, receipts, replay)
```

| Layer | Role | Who uses it |
|-------|------|-------------|
| **Agent Bridge** | Stable workflows — `safePatchFile`, `searchLiteral`, error normalization | External / local agents |
| **Runtime RPC** | JSON-RPC dispatch, queues, contracts | Bridge adapters (not agent code) |
| **C++ kernel** | Mutation authority — `expectBeforeHash`, receipts, atomic batch | Source of truth for all writes |

**Agent rule:** use the [Agent Bridge](docs/agent-bridge.md) or `dietcode-agent-client` — not raw `patch.apply` / `search.*` RPC from agent code.

Full architecture: [Agent Bridge Architecture](docs/agent-bridge-architecture.md) · C++ audit: [Agent Runtime Audit](docs/agent-runtime-audit.md).

---

## Agent Bridge (preferred integration)

The bridge ships inside `DietCode.app` at `Contents/Resources/agent-bridge/`. CLI launcher: `Contents/Resources/bin/dietcode-agent-client`.

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({ startApp: false });
await bridge.connect();

await bridge.searchLiteral('expectBeforeHash', { maxResults: 10 });
const outcome = await bridge.safePatchFile('src/foo.ts', unifiedDiff);

await bridge.close();
```

```bash
# After make app
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client patch safe-file src/foo.ts /tmp/foo.patch
```

| Bridge method | What it does |
|---------------|--------------|
| `connect()` | Socket, readiness, capability detection, workspace bootstrap |
| `searchLiteral` / `searchTokens` / `searchPaths` | Deterministic search (no semantic layer) |
| `safePatchFile` / `safePatchBatch` | Validate → `expectBeforeHash` → apply with receipts |
| `getOperationStatus` | Timeout-safe mutation replay |
| `getTimeline` / `getRecentActivity` | Runtime journal surfaces |
| `verifyFast()` | Quick health probe |

Integration recipes: [Agent Bridge Integration Guide](docs/agent-bridge-integration-guide.md) · Audit record: [Agent Bridge Audit](docs/agent-bridge-audit.md).

---

## Runtime guarantees (under the bridge)

The C++ control surface is hardened as a **deterministic local transaction kernel**:

| Guarantee | Mechanism |
|-----------|-----------|
| Stale-write detection | `expectBeforeHash` → `stale_content` |
| Mutation proof | `mutationReceipt`, `batchMutationReceipt` |
| Idempotent replay | `operation.status` by `idempotencyKey` |
| Monotonic revision | `workspace.revision`, `workspace.snapshot` |
| Deterministic search | Literal / token / path match — sorted, no scores |
| Semantic quarantine | `search.semantic` → `4008`; use bridge search methods |
| Partial-success honesty | `complete`, `partial`, `warnings`, `recoveryHint` |

Maintainers and harnesses may still use the Python client for raw RPC and contract tests: [Headless Agent Control](docs/headless-agent-control.md).

---

## What DietCode is not

- Electron, Chromium, Qt, or extension-host complexity
- Background repo-wide indexing, telemetry, or hidden daemons
- Semantic search, embeddings, fuzzy matching, or probabilistic ranking on agent surfaces
- Cloud defaults, account systems, or AI-by-default features
- A separate agent SDK to install — the bridge is bundled in the app

See [Anti-Scope Checklist](docs/anti-scope-checklist.md) and [MVP Scope](docs/mvp-scope.md).

---

## Quick start

### Prerequisites

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Node.js 18+ (bridge build; bundled in app after `make app`)
- Python 3 (maintainer harnesses and contract tests)

### Build

```bash
git clone <repo-url> DietCode-IDE
cd DietCode-IDE

make test          # C++ unit tests + offline agent self-test
make app           # DietCode.app + bundled agent-bridge
```

### Run the IDE

```bash
make run           # open DietCode.app
make headless      # control server only (no window)
make agent-ready   # wait for socket + RPC readiness
```

### Develop against the bridge

```bash
make restart-agent-server          # required after C++ control-server changes
make agent-bridge-fast             # compile TypeScript only
make test-agent-bridge-fast        # offline bridge tests (fast loop)

build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile --no-start
```

### Verify before merge

```bash
make test-agent-offline
make verify-agent-runtime          # daily ladder (14 checks)
make test-agent-bridge             # bridge offline + live + audit
make verify-agent-runtime-full     # release ladder (workflows + drift + bridge)
```

Full target reference: [Build & Test System](docs/build-and-test-system.md) · Pre-merge checklist: [Testing Checklist](docs/testing-checklist.md).

---

## Repository layout

```text
DietCode-IDE/
  src/                 # Portable C++20 core + macOS control server + UI
  agent-bridge/        # @dietcode/agent-bridge (bundled into the app)
  scripts/             # Python RPC client, contract tests, verification ladders
  docs/                # Specifications and guides
  resources/           # App bundle assets, CLI launcher template
  tests/               # C++ editor unit tests
  Makefile             # Build + all verification targets
```

Details: [File Structure](docs/file-structure.md) · C++ layers: [Technical Architecture](docs/technical-architecture.md).

---

## Documentation

| Audience | Start here |
|----------|------------|
| **Agent authors** | [Agent Bridge](docs/agent-bridge.md) → [Integration Guide](docs/agent-bridge-integration-guide.md) |
| **IDE contributors** | [Getting Started Tutorial](docs/getting-started-tutorial.md) → [Build Instructions](docs/build-instructions.md) |
| **Maintainers** | [Maintainer Guide](docs/maintainer-guide.md) → [Agent Runtime Audit](docs/agent-runtime-audit.md) |
| **Everyone** | [Documentation Index](docs/README.md) · [FAQ & Troubleshooting](docs/faq-and-troubleshooting.md) |

### Agent bridge

| Doc | Contents |
|-----|----------|
| [Agent Bridge](docs/agent-bridge.md) | Overview, public API, CLI |
| [Agent Bridge Architecture](docs/agent-bridge-architecture.md) | Layers, transport, connect lifecycle |
| [Agent Bridge Integration Guide](docs/agent-bridge-integration-guide.md) | TypeScript recipes, error handling |
| [Agent Bridge Audit](docs/agent-bridge-audit.md) | Pass I–II record and verification |

### Runtime and contracts

| Doc | Contents |
|-----|----------|
| [Agent Runtime Audit](docs/agent-runtime-audit.md) | C++ kernel Passes I–VI |
| [Headless Agent Control](docs/headless-agent-control.md) | Raw RPC reference (maintainers) |
| [Runtime Invariants](docs/runtime-invariants.md) | Stale writes, sort order, receipts |
| [Error Codes](docs/error-codes.md) | `string_code` + recovery hints |
| [BroccoliQ Runtime Memory](docs/broccoliq-runtime-memory.md) | Journal semantics |

---

## Key Makefile targets

| Target | Purpose |
|--------|---------|
| `make app` | Build `DietCode.app` + bundle `agent-bridge` |
| `make test` | C++ unit tests + offline agent self-test |
| `make agent-bridge-fast` | Compile TypeScript bridge only |
| `make test-agent-bridge-fast` | Offline bridge tests (no socket) |
| `make test-agent-bridge` | Bridge offline + live workflows + audit |
| `make restart-agent-server` | Rebuild and restart control server |
| `make verify-agent-runtime` | Daily verification ladder |
| `make verify-agent-runtime-full` | Release ladder (includes bridge) |
| `make release-check-agent-runtime` | Release gate |

Per-pass C++ suites: `make test-grep-diff-tooling` (I) through `make test-agent-workflow-smoke` (VI) — see [Agent Runtime Audit](docs/agent-runtime-audit.md).

---

## License

DietCode is open-source software released under the [MIT License](LICENSE).
