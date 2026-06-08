<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>A native, local-first macOS coding environment with a bundled deterministic agent runtime.</strong><br>
  <em>C++20 core · AppKit shell · Agent Bridge · auditable Agent Chat · runtime journal · reliability evaluation</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/language-C%2B%2B20-orange.svg?style=for-the-badge" alt="Language">
</p>

---

## What this is

DietCode is a smaller, calmer, native macOS coding environment built from a portable C++20 core with an Objective-C++ / AppKit shell.

No Electron. No Chromium. No background indexing tax. No cloud defaults.

**Open. Code. Run. Save. No jet engine.**

You install one app. Humans get a native editor. Agents get a deterministic operating layer — search, patch, verify, and recover against a live workspace through a stable Agent Bridge API, with an **auditable Agent Chat** path for Hermes in the IDE.

---

## Two products in one app

| Surface | Who | What they get |
|---------|-----|----------------|
| **Native IDE** | Human developers | Editor, tabs, terminal, git — Cocoa UI over the C++ core |
| **Agent runtime** | Local / external agents | Bridge workflows, mutation receipts, runtime journal, recovery |
| **Agent Chat** | IDE users + CI | Hermes sidebar wired to `dietcode_ide` with a four-layer trust audit |

The kernel decides what happened. The runtime journal remembers what happened. Agent Chat proves *which workspace*, *which path*, *which diff*, and *whether verification passed*.

---

## Agent Chat — auditable, not just chat

The Agent Chat sidebar (⌘⇧A) runs real Hermes sessions through the bundled stack:

```text
Sidebar → dietcode-agent-chat → Hermes → dietcode_ide → Agent Bridge → DietCode runtime
```

Each run emits **four authority layers**. Together they answer: did the agent edit the right workspace, through the approved path, with an inspectable diff, and pass executable verification afterward?

| Authority | When | Invariant |
|-----------|------|-----------|
| **Workspace** | Before Hermes | `requestedWorkspace == workspaceRootObserved` |
| **Mutation** | After Hermes | Changed files explained by bridge patch telemetry |
| **Diff** | After mutation audit | Visible diff changed set == mutation reported files |
| **Verification** | After diff audit | `verify.sh` (or override) passes after final mutation |

```text
open folder
  → workspace authority (fail fast on mismatch)
  → Hermes + dietcode_ide.patch
  → mutation authority (bridge telemetry vs disk)
  → diff authority (unified diff vs mutation set)
  → verification authority (verify.sh after mutation)
  → sidebar status + persisted run artifacts
```

Run artifacts live **outside the workspace**:

```text
~/.dietcode/agent-chat/runs/<run_id>/
  diff.patch
  verify.stdout.log
  verify.stderr.log
  verification.json
```

### Enable and use (installed app)

```bash
/Applications/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor

/Applications/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project \
  --prompt "inspect this project" \
  --format json
```

From source:

```bash
make app
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project --prompt "fix the failing test" --format json
```

Sidebar shows workspace status, mutation path, verification result, **View Diff**, and **View Verify Log**.

Full contract, CLI flags, and enforcement: [Agent Chat Sidebar](docs/agent-chat-sidebar.md).

### Prove it (release verification)

```bash
make smoke-agent-chat-live              # live Hermes edit + all four authorities
make test-agent-chat-workspace-switch   # workspace authority
make test-mutation-authority
make test-diff-authority
make test-verification-authority
make verify-agent-chat-sidebar          # sidebar + bundled artifact checks
make verify-hermes-bridge               # Hermes + bridge integration ladder
make verify-agent-runtime-full          # full release ladder
```

Skip live Hermes in CI: `AGENT_CHAT_LIVE=0 make smoke-agent-chat-live`

---

## Architecture

```text
  [ External agents ]     [ Human + Agent Chat sidebar ]
         |                            |
   Agent Bridge                 Native Cocoa UI
   (TypeScript, bundled)        (editor, ⌘⇧A chat)
         |                            |
         +-------------+--------------+
                       |
             DietCode Runtime RPC
             (~/.dietcode/control.sock)
                       |
         +-------------+--------------+
         |                            |
   C++ mutation kernel      BroccoliQ runtime journal
   (patch, stale guards)     (timeline, receipts, replay)
                       |
             Agent Success Benchmark
             (traps, orchestrator, traces, gates)
```

| Layer | Role |
|-------|------|
| **Agent Bridge** | Stable workflows — `safePatchFile`, `searchLiteral`, recovery; emits `mutation.patch.applied` telemetry |
| **Runtime RPC** | JSON-RPC dispatch, queues, frozen contracts |
| **C++ mutation kernel** | Mutation authority — `expectBeforeHash`, receipts, atomic batch |
| **Runtime journal** | Durable operation memory, timeline, replay, diagnostics |
| **Agent Chat** | Bounded Hermes path with workspace / mutation / diff / verification audit |
| **Agent benchmark** | Adversarial evaluation, contract orchestration, mutation provenance |

Deep dive: [Agent Bridge Architecture](docs/agent-bridge-architecture.md) · [Technical Architecture](docs/technical-architecture.md) · [Agent Runtime Reliability](AGENT_RUNTIME_RELIABILITY.md).

---

## Bundled agent CLIs

All live in `DietCode.app/Contents/Resources/bin/` after `make app`.

| CLI | Role |
|-----|------|
| `dietcode-agent-client` | Bridge launcher — search, patch, verify, timeline |
| `dietcode-enable-agent` | Install Hermes plugin, backup config, doctor |
| `dietcode-agent-chat` | Bounded Hermes chat with `dietcode_ide` guardrails + authority JSON |

Works from `/Applications/DietCode.app`, `~/Applications/DietCode.app`, and `build/DietCode.app` without a source checkout.

---

## Agent Bridge (preferred integration)

Agents should use the bridge or bundled CLI — **not** raw runtime RPC.

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({ startApp: false });
await bridge.connect();

await bridge.searchLiteral('expectBeforeHash', { maxResults: 10 });

const outcome = await bridge.safePatchFile('src/foo.ts', unifiedDiff);

await bridge.close();
```

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client patch safe-file \
  src/foo.ts /tmp/foo.patch
```

| Workflow | Purpose |
|----------|---------|
| `connect()` | Runtime readiness + capability detection |
| `searchLiteral()` / `searchTokens()` / `searchPaths()` | Deterministic retrieval |
| `safePatchFile()` / `safePatchBatch()` | Validate → `expectBeforeHash` → apply |
| `getOperationStatus()` | Timeout-safe replay recovery |
| `getTimeline()` | Runtime journal stream |
| `verifyFast()` | Quick runtime health check |

Docs: [Agent Bridge](docs/agent-bridge.md) · [Integration Guide](docs/agent-bridge-integration-guide.md) · [Bridge Audit](docs/agent-bridge-audit.md).

---

## Runtime guarantees

The runtime behaves as a deterministic local transaction kernel for bounded autonomous mutation.

| Guarantee | Mechanism |
|-----------|-----------|
| Stale-write rejection | `expectBeforeHash` → `stale_content` |
| Mutation proof | `mutationReceipt`, `batchMutationReceipt` |
| Replay safety | `operation.status` + `idempotencyKey` |
| Monotonic revisions | `workspace.revision` |
| Durable runtime memory | BroccoliQ runtime journal |
| Deterministic retrieval | literal / token / path search only |
| Semantic quarantine | `search.semantic` → `4008` |
| Honest partial success | `complete`, `partial`, `warnings` |
| Safe batch mutation | atomic apply + rollback proof |
| Agent Chat audit | four-authority chain on every sidebar run |

Canonical audit: [Agent Runtime Audit](docs/agent-runtime-audit.md). RPC reference: [Headless Agent Control](docs/headless-agent-control.md).

---

## Agent Runtime Reliability (v1.0)

DietCode includes a **research-grade evaluation harness** for bounded agent code mutation — adversarial traps, adaptive orchestration, replayable mutation traces, and enforced release gates. Not a pass-rate leaderboard; a defensible artifact.

**Start here:** [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)

```text
benchmark → adversarial traps → orchestrator → semantic repair
  → traces → provenance → replay → gates → negative gates → audit verdict
```

| Milestone | Achievement |
|-----------|-------------|
| 40-task corpus | Reference **80/80** solvability (001–030 + 051–060 nightmare) |
| Contract ladder | Static profiles → nightmare **9/10** at `contract_full` |
| Adaptive orchestrator | Three-axis escalation → nightmare **10/10** |
| Mutation traces | SLSA-style provenance per orchestrated run |
| Release gates | `make benchmark-contract-release-check` |
| Production audit | [AUDIT v1.0](benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md) |

```bash
make test-agent-benchmark-schema          # offline schema + audit tests
make benchmark-contract-release-check     # v1.0 release gate (requires server)
```

Tag: `agent-runtime-reliability-v1.0` · Docs: [benchmarks/agent_success/README.md](benchmarks/agent_success/README.md)

**v1.0 is frozen.** Future benchmark work goes on the **v1.1 experimental** line.

---

## Core philosophy

- local-first
- deterministic behavior
- inspectable runtime surfaces
- explicit recovery paths
- bounded autonomous mutation
- auditable agent edits (workspace → bridge → diff → verify)
- no hidden ranking or semantic heuristics
- no background indexing daemons
- no cloud dependency

DietCode is not Electron, Chromium, Qt, extension-host infrastructure, semantic-search tooling, or “AI that edits files behind your back.”

See [Anti-Scope Checklist](docs/anti-scope-checklist.md) · [MVP Scope](docs/mvp-scope.md).

---

## Quick start

### Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Node.js 18+ (bridge build; bundled after `make app`)
- Python 3 (harnesses + benchmark)
- Hermes (installed on demand via `dietcode-enable-agent`; not vendored in repo)

### Build and run

```bash
git clone <repo-url> DietCode-IDE
cd DietCode-IDE

make test
make app
make run
```

Headless runtime:

```bash
make headless
make agent-ready
```

Enable Agent Chat (Hermes + plugin):

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
```

---

## Development workflow

After C++ runtime changes:

```bash
make restart-agent-server
```

Fast bridge iteration:

```bash
make agent-bridge-fast
make test-agent-bridge-fast
```

Agent Chat bundle (no full rebuild):

```bash
make agent-chat-bundle
make test-dietcode-agent-chat
```

Daily runtime ladder:

```bash
make verify-agent-runtime
```

Full release ladder (includes Agent Chat smoke + verification authority):

```bash
make verify-agent-runtime-full
```

Agent reliability benchmark:

```bash
make test-agent-benchmark-schema
make benchmark-contract-orchestrator
make benchmark-contract-release-check
```

Details: [Build & Test System](docs/build-and-test-system.md) · [Testing Checklist](docs/testing-checklist.md).

---

## Repository layout

```text
DietCode-IDE/
  AGENT_RUNTIME_RELIABILITY.md   # v1.0 research release entry point
  src/                           # C++20 core + AppKit runtime/UI
    platform/macos/MacAgentSidebar.mm
  runtime/memory/                # BroccoliQ runtime journal
  agent-bridge/                  # Bundled TypeScript bridge + mutation telemetry
  integrations/hermes-dietcode-plugin/   # Hermes dietcode_ide plugin source
  scripts/
    dietcode_agent_chat.py       # Bounded chat CLI
    dietcode_*_authority.py      # Workspace / mutation / diff / verification audit
    smoke_agent_chat_live.py     # Live four-authority smoke
  benchmarks/agent_success/      # Agent reliability evaluation harness
  docs/                          # Specifications and architecture docs
  tests/                         # C++ editor tests
  resources/bin/                 # Bundled CLI launchers
```

[File Structure](docs/file-structure.md)

---

## Documentation

### Agent Chat

- [Agent Chat Sidebar](docs/agent-chat-sidebar.md) — trust loop, CLI contract, smoke, sidebar UX
- [Integrations](integrations/README.md) — Hermes plugin, enable-agent, installed-app flow

### Agent Bridge

- [Agent Bridge](docs/agent-bridge.md)
- [Agent Bridge Architecture](docs/agent-bridge-architecture.md)
- [Agent Bridge Integration Guide](docs/agent-bridge-integration-guide.md)
- [Agent Bridge Audit](docs/agent-bridge-audit.md)

### Agent Runtime Reliability

- [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)
- [Benchmark README](benchmarks/agent_success/README.md)
- [WHITEPAPER](benchmarks/agent_success/WHITEPAPER.md)
- [AUDIT v1.0](benchmarks/agent_success/AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md)

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
- [Getting Started Tutorial](docs/getting-started-tutorial.md)
- [FAQ & Troubleshooting](docs/faq-and-troubleshooting.md)
- [Maintainer Guide](docs/maintainer-guide.md)

---

## License

DietCode is open-source software released under the [MIT License](LICENSE).
