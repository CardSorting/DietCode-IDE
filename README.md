<p align="center">
  <img src="resources/logo.svg" width="160" height="160" alt="DietCode logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>Supervise AI code changes on your Mac — with visible checkpoints, not blind trust.</strong><br>
  <em>A governed local mutation runtime · not a web UI · not another editor</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/baseline-checkpoint--core--v0.1-blue.svg?style=flat-square" alt="checkpoint-core-v0.1">
</p>

<p align="center">
  <a href="#in-30-seconds">Overview</a> ·
  <a href="#i-want-to">I want to…</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#the-six-checkpoints">Checkpoints</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#troubleshooting">Help</a>
</p>

---

## In 30 seconds

When an AI agent edits your project, you usually cannot see **where** it is in the process, **what** it already changed, or **whether** the result actually works.

**DietCode fixes that.**

It runs on your Mac, keeps a single trusted component in charge of file changes, and walks every task through **six visible checkpoints** — read, drift, approval, patch, verify, done. You can pause, approve, reject, or recover at each step. The agent finishing does **not** mean the job succeeded.

> **Plain English:** DietCode is air-traffic control for AI edits — not the plane, not the airport terminal, but the tower that clears each move before it lands.

**Hard rule:** The cockpit UI never edits files. Only `dietcode-kernel` mutates your workspace.

---

## I want to…

Pick the path that matches you. Each link is the canonical next step.

| I want to… | Start here |
|------------|------------|
| **Understand the idea** (no install) | [The six checkpoints](#the-six-checkpoints) → [checkpoint model](docs/checkpoint-model.md) |
| **Run DietCode on my Mac** | [Quick start](#quick-start) → [getting started](docs/getting-started.md) |
| **Watch an agent task in the UI** | [Quick start](#quick-start) → open Cockpit → [governed tasks](docs/governed-tasks.md) |
| **Know if my install is healthy** | `make checkpoint-core` → [testing guide](docs/testing.md) |
| **Fix something broken** | [Troubleshooting](#troubleshooting) → [troubleshooting.md](docs/troubleshooting.md) |
| **Wire my own agent or CI** | [agent bridge](docs/agent-bridge.md) → [kernel RPC](docs/kernel-rpc.md) |
| **Use Hermes / legacy app chat** | [integrations](integrations/README.md) *(optional — not required for the checkpoint loop)* |

Full doc index: [docs/README.md](docs/README.md)

---

## What DietCode is

DietCode is a **local-first control plane** for autonomous and semi-autonomous software work on macOS. It separates concerns that most AI tools merge into one opaque stack:

| Layer | Role | In everyday terms |
|-------|------|-------------------|
| **Kernel** (`dietcode-kernel`) | Sole authority that changes files | The only component allowed to touch your project |
| **Bridge** | Task orchestration + session recovery | Remembers where a task left off after a restart |
| **Cockpit** | Web UI for steering and visibility | The dashboard you watch and click |
| **Agent bridge** | TypeScript workflows for external agents | How Hermes, scripts, or CI talk to the kernel safely |

```text
You or an AI agent
        ↓
   Cockpit (browser)     ← see drift, approvals, verify status
        ↓
   Bridge (HTTP + SSE)   ← governed tasks, checkpoints, recovery
        ↓
   dietcode-kernel       ← patches, tests, approvals, drift checks
        ↓
   Your project folder
```

### What DietCode is not

| Not this | Why |
|----------|-----|
| A replacement for VS Code / Xcode | The optional AppKit editor in `legacy_ui/` is legacy compatibility only |
| A chat window that silently edits files | Tasks are bounded runs with explicit gates |
| A cloud IDE | Everything runs locally on your Mac |
| “Done” when the model stops talking | Tasks complete only after verify passes or is explicitly waived |

The product surface is the **checkpointed control loop**, not another text editor.

---

## The six checkpoints

Every governed task must answer six questions before it can honestly be called **done**. Each question has a matching panel, event, or gate in the Cockpit.

| # | Checkpoint | Plain English | Technical question |
|---|------------|---------------|-------------------|
| 1 | **Context** | Did the agent read the right files? | Did the agent read valid state? |
| 2 | **Drift** | Did the repo change while the agent was working? | Did the workspace change underneath it? |
| 3 | **Approval** | Are you OK with this edit? | Is this mutation allowed? |
| 4 | **Mutation** | Did the patch apply cleanly? | Did the patch apply without error? |
| 5 | **Verification** | Do tests still pass? | Did the result pass? |
| 6 | **Completion** | Can we mark this task finished? | Can this task actually be called done? |

```text
Your prompt
    ↓  read files          (1 Context)
    ↓  drift check         (2 Drift)     ← blocks if files changed unexpectedly
    ↓  your approval       (3 Approval)  ← you approve or reject
    ↓  apply patch         (4 Mutation)
    ↓  run tests           (5 Verification)
    ↓  task completed      (6 Completion) ← only after verify passes or is waived
```

Deep dive: [checkpoint-model.md](docs/checkpoint-model.md) · Per-gate guides: [drift](docs/workspace-drift.md) · [approval](docs/approval-lifecycle.md) · [verify](docs/verify-gate.md) · [recovery](docs/session-recovery.md)

---

## Why DietCode exists

Most agent tools collapse **mutation**, **orchestration**, and **UI** into a single black box. When something goes wrong, you discover it late — or not at all.

DietCode treats AI coding as an **operations** problem:

- **Verify** state before mutating
- **Surface** risky transitions instead of hiding them
- **Pause** when human supervision is required
- **Recover** cleanly after failure or reload
- **Never** silently continue after the control loop breaks

The goal is not fully autonomous coding. The goal is **bounded autonomy through visible checkpoints**.

### How this differs from typical AI coding tools

| Typical pattern | DietCode pattern |
|-----------------|------------------|
| Agent edits files directly or opaquely | One kernel mutates; everything else requests changes |
| Chat ends → assume success | Task stays open until verify gate clears |
| File conflicts discovered late | Drift gate blocks stale patches early |
| Restart loses context | Bridge restores bounded session state |
| Failures buried in logs | Cockpit shows disconnect, expiry, and blocked gates |

---

## Quick start

### Prerequisites

- macOS with Xcode Command Line Tools
- Node.js 20+ and Python 3.11+ (see [getting-started.md](docs/getting-started.md))

### 1. Clone and validate the frozen baseline

```bash
git clone <repo>
cd DietCode-IDE
make checkpoint-core
```

`checkpoint-core` proves the full governed pipeline works on your machine: kernel, bridge, cockpit, checkpoint APIs, recovery, smoke fixtures, and verification routing. Baseline tag: **checkpoint-core-v0.1**.

### 2. Start daily development

```bash
make kernel
make restart-agent-server-fast

cd cockpit
npm install
npm run dev
```

| Surface | URL | What you use it for |
|---------|-----|---------------------|
| **Cockpit UI** | http://localhost:5173 | Watch tasks, approve edits, run verify |
| **Bridge API** | http://127.0.0.1:9477 | Scripts and integrations (`POST /api/tasks`) |

### 3. Open a project and submit a task

1. Open the Cockpit in your browser.
2. Point it at a workspace folder (or use the chat panel).
3. Submit a task — e.g. *“Change VALUE from 1 to 2 in probe.py”*.
4. Watch the checkpoint rail: drift → approval → patch → verify → completed.

Task API details: [governed-tasks.md](docs/governed-tasks.md)

---

## Core commands

| Command | Who uses it | What it does |
|---------|-------------|--------------|
| `make checkpoint-core` | Everyone before trusting an install | Full baseline gate (kernel + bridge + smoke + docs) |
| `make cockpit-smoke` | Developers | 53-check vertical slice only |
| `make kernel` | Developers | Build `build/dietcode-kernel` |
| `make restart-agent-server-fast` | Everyone when the socket is stale | Restart kernel without full rebuild |
| `make agent-bridge-fast` | Agent authors | Build TypeScript bridge package |
| `make cockpit` | Developers | Production build of UI + server |

More targets: [testing.md](docs/testing.md) · First-run walkthrough: [getting-started.md](docs/getting-started.md)

---

## Current baseline

### checkpoint-core-v0.1

| Layer | Status |
|-------|--------|
| **Kernel** | Headless JSON-RPC runtime — sole mutation authority |
| **Cockpit** | Checkpoint rail, drift/approval/verify panels, governed task UI |
| **Bridge** | Session recovery, governed tasks, SSE event stream |
| **Safety** | Drift gate · approval gate · verify gate |
| **Recovery** | Bounded session restore after bridge reload |
| **Validation** | 53-check vertical slice (`make cockpit-smoke`) |

Before changing the checkpoint model or shipping new control-plane behavior:

```bash
make checkpoint-core   # must pass
```

---

## Architecture

```text
Human operator  ──watch/approve──►  Cockpit UI (React)
Agent / script  ──POST task────►  Bridge (HTTP + SSE)
                                        │
                                        ▼
                              dietcode-kernel (C++)
                                        │
                                        ▼
                              Workspace on disk
```

| Component | Owns |
|-----------|------|
| **Kernel** | File mutation, patch apply, verify execution, drift anchoring, approval enforcement |
| **Cockpit** | Task steering, checkpoint visualization, approvals, verify controls, recovery UI |
| **Agents** | Read and propose — they never write to disk directly |

Wiring and RPC flow: [architecture.md](docs/architecture.md)

---

## Reliability philosophy

DietCode does not paper over operational failure.

When the control loop breaks, you should see it immediately:

| Situation | What you see |
|-----------|--------------|
| Task loses connection | Visible disconnect — not a silent hang |
| Approval times out | Explicit expiry — not an assumed “yes” |
| Files changed mid-task | Drift gate blocks the patch |
| Tests fail | Verify gate blocks completion |
| Bridge restarted | Stale-session warning + recovery path |
| Recovery needed | Requires your intent — no auto-resume into danger |

The system should never imply an agent is still operating safely when it is not.

---

## Documentation

Docs are grouped by **job**, not by filename.

### Learn the model

| Doc | Read when |
|-----|-----------|
| [checkpoint-model.md](docs/checkpoint-model.md) | You want the canonical six-gate map |
| [architecture.md](docs/architecture.md) | You want kernel ↔ bridge ↔ UI wiring |
| [governed-tasks.md](docs/governed-tasks.md) | You want the task API and lifecycle |

### Run and validate

| Doc | Read when |
|-----|-----------|
| [getting-started.md](docs/getting-started.md) | First build, socket, workspace open |
| [testing.md](docs/testing.md) | `checkpoint-core`, `cockpit-smoke`, harness targets |
| [troubleshooting.md](docs/troubleshooting.md) | Socket offline, drift blocks, verify failures |

### Build agents and integrations

| Doc | Read when |
|-----|-----------|
| [agent-bridge.md](docs/agent-bridge.md) | TypeScript workflows for external agents |
| [agent-ergonomics.md](docs/agent-ergonomics.md) | Checkpoint polling and agent recovery |
| [kernel-rpc.md](docs/kernel-rpc.md) | JSON-RPC methods and CLI |
| [integrations.md](docs/integrations.md) | Hermes plugin overview |

Index of all docs: [docs/README.md](docs/README.md)

---

## Troubleshooting

| Symptom | First command |
|---------|---------------|
| Kernel offline / socket error | `make restart-agent-server-fast` |
| Stale binary after `git pull` | `make kernel && make restart-agent-server-fast` |
| Drift blocks my patch | Refresh context in Cockpit or see [workspace-drift.md](docs/workspace-drift.md) |
| Task stuck before “completed” | Check verify gate — [verify-gate.md](docs/verify-gate.md) |
| Not sure install is healthy | `make checkpoint-core` |

Full playbook: [troubleshooting.md](docs/troubleshooting.md) · Error codes: [error-codes.md](docs/error-codes.md)

---

## Optional integrations

Hermes and the legacy AppKit agent-chat sidebar are **optional**. The checkpoint loop does not depend on any single model provider.

```bash
make app                    # legacy app bundle + kernel resources
make smoke-agent-chat-live  # live Hermes edit proof (separate from cockpit-smoke)
```

See [integrations/README.md](integrations/README.md).

### Reliability evaluation (research track)

Adversarial mutation benchmarks live under `benchmarks/agent_success/`. They evaluate runtime reliability under stress — a parallel track, not the cockpit checkpoint gate.

- [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)
- [benchmarks/agent_success/README.md](benchmarks/agent_success/README.md)

Run separately from `make checkpoint-core`.

---

## Repository layout

```text
src/kernel/                     Headless kernel entry
src/platform/macos/control/     JSON-RPC server (mutation authority)
cockpit/                        React UI + bridge server
agent-bridge/                   TypeScript agent workflows
scripts/                        Harnesses, cockpit-smoke, CLI client
scripts/fixtures/cockpit_smoke/ Vertical-slice fixture repos
legacy_ui/                      Optional native editor (not the product surface)
integrations/                   Hermes plugin sync boundary
```

Detailed map: [file-structure.md](docs/file-structure.md)

---

## License

MIT License — see [LICENSE](LICENSE).
