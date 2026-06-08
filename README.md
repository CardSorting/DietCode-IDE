<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>A native, local-first macOS coding environment with a bundled deterministic agent runtime.</strong><br>
  <em>C++20 core · AppKit shell · Agent Bridge · runtime journal · adversarial reliability evaluation</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg?style=for-the-badge" alt="Language">
</p>

---

## What this is

DietCode is a smaller, calmer, native macOS coding environment built from a portable C++20 core with an Objective-C++ / AppKit shell.

No Electron.  
No Chromium.  
No background indexing tax.  
No cloud defaults.

**Open. Code. Run. Save.**  
No jet engine.

DietCode also ships with a bundled deterministic agent runtime: a hardened local control stack that allows external or local agents to safely search, patch, verify, recover, and replay mutations against a live workspace through a stable Agent Bridge API.

You install one app.

- Humans get a native editor.
- Agents get a deterministic operating layer.

---

## Core idea

Most “AI IDEs” optimize for generation throughput.

DietCode optimizes for **bounded mutation reliability**.

The project is built around a different assumption:

> Before agents become more autonomous, their runtime boundaries must become more explicit, observable, replayable, and enforceable.

DietCode treats agent mutation as a runtime systems problem, not an autocomplete problem.

**The kernel decides what happened.**  
**The runtime journal remembers what happened.**  
**The benchmark proves mutation stayed bounded.**

---

## Agent Runtime Reliability (v1.0)

DietCode includes a replayable adversarial evaluation harness for bounded agent code mutation.

This is not a leaderboard benchmark.

It is a runtime reliability system with:

- adversarial mutation traps
- adaptive orchestration
- semantic repair protocols
- replayable mutation traces
- release gates
- negative gate tests
- provenance verification
- runtime contract escalation

**Start here:**

- [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)
- [benchmarks/agent_success/README.md](benchmarks/agent_success/README.md)

Evaluation pipeline:

```text
benchmark
  → adversarial traps
  → orchestrator
  → semantic repair
  → traces
  → provenance
  → replay
  → release gates
  → negative gates
  → audit verdict
```

### Reliability milestones

| Milestone | Result |
|-----------|--------|
| Base corpus | 40-task solvability corpus |
| Adversarial layer | Explicit trap classification + recovery telemetry |
| Nightmare tier | Concurrent mutation, stale state, rollback, semantic preservation |
| Contract ladder | Progressive runtime visibility profiles |
| Adaptive orchestrator | Three-axis escalation (visibility, protocol, semantic repair) |
| Mutation traces | Replayable provenance artifacts |
| Release gates | Automated reliability verification ladder |
| Production audit | [AUDIT v1.0](benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md) |

### Validation

```bash
# Offline schema + audit verification
make test-agent-benchmark-schema

# Full reliability release gate
make benchmark-contract-release-check
```

Release tag: `agent-runtime-reliability-v1.0`

**v1.0 is frozen.** Experimental benchmark work continues on the **v1.1** line.

---

## Architecture

```text
 [ External agents ]        [ Human developer ]
          |                         |
     Agent Bridge              Native Cocoa UI
     (bundled TS layer)        (editor, tabs, terminal)
          |                         |
          +------------+------------+
                       |
             DietCode Runtime RPC
             (~/.dietcode/control.sock)
                       |
          +------------+------------+
          |                         |
    C++ mutation kernel      BroccoliQ runtime journal
    (authority + replay)     (timeline, receipts, recovery)
                       |
              Agent Reliability Harness
              (traps, orchestration, provenance)
```

| Layer | Responsibility |
|-------|----------------|
| Agent Bridge | Stable deterministic workflows for agents |
| Runtime RPC | JSON-RPC dispatch, contracts, queues |
| Mutation kernel | Atomic mutation authority and rollback |
| Runtime journal | Durable operation memory and replay |
| Reliability harness | Adversarial evaluation and release gates |

Further reading:

- [Agent Bridge Architecture](docs/agent-bridge-architecture.md)
- [Technical Architecture](docs/technical-architecture.md)
- [Agent Runtime Reliability](AGENT_RUNTIME_RELIABILITY.md)

---

## Core philosophy

DietCode is built around a small set of constraints:

- local-first operation
- deterministic runtime behavior
- explicit recovery paths
- inspectable mutation surfaces
- bounded autonomous mutation
- replayable runtime history
- stable operational contracts
- zero cloud dependency
- zero hidden indexing infrastructure

The runtime intentionally prefers deterministic and inspectable workflows over opaque retrieval systems or probabilistic patch pipelines.

---

## Runtime guarantees

The runtime behaves as a deterministic local transaction kernel for bounded autonomous mutation.

| Guarantee | Mechanism |
|-----------|-----------|
| Stale-write rejection | `expectBeforeHash` → `stale_content` |
| Atomic mutation | transaction receipts + rollback |
| Replay safety | `operation.status` + `idempotencyKey` |
| Workspace authority | explicit runtime workspace verification |
| Mutation authority | bridge patch telemetry |
| Diff authority | visible diff reconciliation |
| Verification authority | executable post-mutation verification |
| Durable runtime memory | BroccoliQ runtime journal |
| Deterministic retrieval | literal / token / path search only |
| Semantic quarantine | `search.semantic` → `4008` |
| Honest partial success | `complete`, `partial`, `warnings` |
| Release reliability | adversarial gates + replay traces |

Canonical references:

- [Agent Runtime Audit](docs/agent-runtime-audit.md)
- [Runtime Invariants](docs/runtime-invariants.md)
- [Headless Agent Control](docs/headless-agent-control.md)
- [BroccoliQ Runtime Memory](docs/broccoliq-runtime-memory.md)

---

## Agent Bridge (preferred integration)

The Agent Bridge ships inside `DietCode.app`.

Agents should use the bridge or bundled CLI — **not** raw runtime RPC.

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({
  startApp: false,
});

await bridge.connect();

await bridge.searchLiteral('expectBeforeHash', {
  maxResults: 10,
});

const outcome = await bridge.safePatchFile(
  'src/foo.ts',
  unifiedDiff,
);

await bridge.close();
```

CLI examples:

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile

build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast

build/DietCode.app/Contents/Resources/bin/dietcode-agent-client patch safe-file \
  src/foo.ts \
  /tmp/foo.patch
```

### Bridge workflows

| Method | Purpose |
|--------|---------|
| `connect()` | Runtime readiness + capability detection |
| `searchLiteral()` | Deterministic literal search |
| `searchTokens()` | Exact token search |
| `searchPaths()` | Deterministic path search |
| `safePatchFile()` | Validate → reconcile → apply |
| `safePatchBatch()` | Atomic batch mutation |
| `getOperationStatus()` | Replay-safe recovery |
| `getTimeline()` | Runtime journal stream |
| `verifyFast()` | Runtime health check |

References:

- [Agent Bridge](docs/agent-bridge.md)
- [Integration Guide](docs/agent-bridge-integration-guide.md)
- [Bridge Audit](docs/agent-bridge-audit.md)

---

## Agent Chat (Hermes in IDE)

DietCode includes a native **Agent Chat sidebar** (⌘⇧A) wired to the bundled `dietcode-agent-chat` CLI.

This is a real bounded mutation loop:

```text
sidebar
  → Hermes
  → dietcode_ide
  → Agent Bridge
  → runtime mutation kernel
  → verification
```

Not a mock shell wrapper.  
Not direct file writes.  
Not hidden background mutation.

### Authority chain

Each run is auditable through four explicit runtime authority layers:

| Authority | Proves |
|-----------|--------|
| Workspace authority | Agent edited the intended workspace |
| Mutation authority | Edits occurred through the approved bridge path |
| Diff authority | Exact changed-file set is inspectable |
| Verification authority | Executable verification passed after mutation |

Run artifacts persist outside the workspace at `~/.dietcode/agent-chat/runs/<run_id>/` (`diff.patch`, verify logs, `verification.json`).

### Enable Hermes

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
```

### Run chat directly

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project \
  --prompt "inspect this project" \
  --format json
```

### Reliability ladder

```bash
make smoke-agent-chat-live
make test-agent-chat-workspace-switch
make test-mutation-authority
make test-diff-authority
make test-verification-authority
make verify-hermes-bridge
make verify-agent-runtime-full
```

See:

- [Agent Chat Sidebar](docs/agent-chat-sidebar.md)
- [Hermes Integration](integrations/README.md)
- [Agent Runtime Reliability](AGENT_RUNTIME_RELIABILITY.md)

---

## What DietCode is not

DietCode is not:

- Electron
- Chromium
- Qt
- extension-host infrastructure
- embeddings-based retrieval
- semantic ranking infrastructure
- cloud-native IDE infrastructure
- telemetry-first tooling
- hidden background orchestration
- “AI that edits files behind your back”

The runtime intentionally prioritizes inspectability, bounded mutation, replayability, and deterministic operational behavior.

See:

- [Anti-Scope Checklist](docs/anti-scope-checklist.md)
- [MVP Scope](docs/mvp-scope.md)

---

## Quick start

### Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Node.js 18+ (bridge build only; bundled after `make app`)
- Python 3 (benchmark + harness tooling)
- Hermes (installed on demand via `dietcode-enable-agent`; not vendored in repo)

### Build

```bash
git clone <repo-url> DietCode-IDE
cd DietCode-IDE

make test
make app
```

### Run

```bash
make run
```

Headless runtime:

```bash
make headless
make agent-ready
```

---

## Development workflow

After runtime changes:

```bash
make restart-agent-server
```

Fast bridge iteration:

```bash
make agent-bridge-fast
make test-agent-bridge-fast
```

Agent Chat bundle:

```bash
make agent-chat-bundle
make test-dietcode-agent-chat
```

Daily runtime ladder:

```bash
make verify-agent-runtime
```

Full release ladder:

```bash
make verify-agent-runtime-full
```

Reliability benchmark:

```bash
make test-agent-benchmark-schema
make benchmark-contract-orchestrator
make benchmark-contract-release-check
```

Details: [Build & Test System](docs/build-and-test-system.md) · [Testing Checklist](docs/testing-checklist.md)

---

## Repository layout

```text
DietCode-IDE/
  AGENT_RUNTIME_RELIABILITY.md
  src/
  runtime/memory/
  agent-bridge/
  integrations/hermes-dietcode-plugin/
  benchmarks/agent_success/
  scripts/
  docs/
  tests/
  resources/
```

[File Structure](docs/file-structure.md)

---

## Documentation

### Reliability

- [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)
- [Benchmark README](benchmarks/agent_success/README.md)
- [WHITEPAPER](benchmarks/agent_success/WHITEPAPER.md)
- [AUDIT v1.0](benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md)
- [Reliability case](docs/agent-runtime-reliability-case.md)

### Agent Chat

- [Agent Chat Sidebar](docs/agent-chat-sidebar.md)
- [Hermes Integration](integrations/README.md)

### Agent Bridge

- [Agent Bridge](docs/agent-bridge.md)
- [Agent Bridge Architecture](docs/agent-bridge-architecture.md)
- [Integration Guide](docs/agent-bridge-integration-guide.md)
- [Bridge Audit](docs/agent-bridge-audit.md)

### Runtime

- [Agent Runtime Audit](docs/agent-runtime-audit.md)
- [Runtime Invariants](docs/runtime-invariants.md)
- [Headless Agent Control](docs/headless-agent-control.md)
- [BroccoliQ Runtime Memory](docs/broccoliq-runtime-memory.md)
- [Error Codes](docs/error-codes.md)

### Development

- [Documentation Index](docs/README.md)
- [Build & Test System](docs/build-and-test-system.md)
- [Testing Checklist](docs/testing-checklist.md)
- [Maintainer Guide](docs/maintainer-guide.md)
- [Getting Started Tutorial](docs/getting-started-tutorial.md)
- [FAQ & Troubleshooting](docs/faq-and-troubleshooting.md)

---

## License

DietCode is open-source software released under the [MIT License](LICENSE).
