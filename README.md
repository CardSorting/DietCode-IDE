<p align="center">
  <img src="resources/logo.svg" width="160" height="160" alt="DietCode logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>Supervise AI code changes on your Mac — with visible checkpoints, not blind trust.</strong><br><br>
  <strong>DietCode is air-traffic control for AI edits:</strong><br>
  a governed local mutation runtime that clears each workspace change through visible operational checkpoints.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/baseline-checkpoint--core--v0.1-blue.svg?style=flat-square" alt="checkpoint-core-v0.1">
</p>

<p align="center">
  <a href="#i-want-to">I want to…</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#the-six-checkpoints">Checkpoints</a> ·
  <a href="#documentation">Docs</a> ·
  <a href="#troubleshooting">Help</a>
</p>

---

## How DietCode handles failure

DietCode does not paper over operational failure. When the control loop breaks, you see it immediately — the system never implies an agent is still operating safely when it is not.

| Situation | What you see |
|-----------|--------------|
| Task loses connection | Visible disconnect — not a silent hang |
| Approval times out | Explicit expiry — not an assumed “yes” |
| Files changed mid-task | Drift gate blocks the patch |
| Tests fail | Verify gate blocks completion |
| Bridge restarted | Stale-session warning + recovery path |
| Recovery needed | Your intent required — no auto-resume into danger |

One kernel holds mutation authority. The Cockpit never edits files directly — only `dietcode-kernel` mutates your workspace. Agent exit does **not** mean the job succeeded; tasks complete only after verify passes or is explicitly waived.

---

## I want to…

| I want to… | Start here |
|------------|------------|
| **Understand the idea** (no install) | [Brief](docs/brief.md) → [philosophy](docs/philosophy.md) → [checkpoints](#the-six-checkpoints) |
| **Run DietCode on my Mac** | [Quick start](#quick-start) → [getting started](docs/getting-started.md) |
| **Watch an agent task in the UI** | [Quick start](#quick-start) → [governed tasks](docs/governed-tasks.md) |
| **Know if my install is healthy** | `make checkpoint-core` → [testing guide](docs/testing.md) |
| **Fix something broken** | [Troubleshooting](#troubleshooting) → [troubleshooting.md](docs/troubleshooting.md) |
| **Wire my own agent or CI** | [agent bridge](docs/agent-bridge.md) → [kernel RPC](docs/kernel-rpc.md) |
| **Use Hermes / legacy app chat** | [integrations](integrations/README.md) *(optional)* |

Full doc index: [docs/README.md](docs/README.md)

---

## What DietCode is

A **local-first control plane** on macOS: one trusted tower sequences reads, approvals, patches, and verification while you watch from the Cockpit.

| Layer | Role |
|-------|------|
| **Kernel** (`dietcode-kernel`) | Sole authority that changes files |
| **Bridge** | Governed tasks + session recovery |
| **Cockpit** | Steering, approvals, checkpoint visibility |
| **Agent bridge** | How Hermes, scripts, and CI request changes safely |

```text
You or an AI agent → Cockpit → Bridge → dietcode-kernel → your project
```

**Not** a web IDE, **not** a chat window that silently edits files, **not** cloud-hosted. The optional AppKit editor in `legacy_ui/` is legacy compatibility — the product surface is the checkpointed control loop.

| Typical AI tool | DietCode |
|-----------------|----------|
| Agent edits opaquely | One kernel mutates; everything else requests clearance |
| Chat ends → assume success | Task open until verify clears |
| Conflicts found late | Drift gate blocks stale patches |
| Restart loses context | Bridge restores bounded session state |
| Failures in logs | Cockpit shows blocked gates and disconnects |

Architecture detail: [architecture.md](docs/architecture.md)

---

## The six checkpoints

Every governed task clears six gates before it can be called **done**:

| # | Checkpoint | Question |
|---|------------|----------|
| 1 | **Context** | Did the agent read valid state? |
| 2 | **Drift** | Did the workspace change underneath it? |
| 3 | **Approval** | Is this mutation allowed? |
| 4 | **Mutation** | Did the patch apply cleanly? |
| 5 | **Verification** | Did the result pass? |
| 6 | **Completion** | Can this task be called done? |

```text
prompt → read → drift → approval → patch → verify → completed
```

Deep dive: [checkpoint-model.md](docs/checkpoint-model.md) · [drift](docs/workspace-drift.md) · [approval](docs/approval-lifecycle.md) · [verify](docs/verify-gate.md) · [recovery](docs/session-recovery.md)

---

## Quick start

**Prerequisites:** macOS, Xcode CLT, Node.js 20+, Python 3.11+ — [getting-started.md](docs/getting-started.md)

### 1. Clone and validate the baseline

```bash
git clone <repo>
cd DietCode-IDE
make checkpoint-core
```

Proves kernel, bridge, cockpit, checkpoint APIs, recovery, and the 53-check vertical slice on your machine. Tag: **checkpoint-core-v0.1**.

### 2. Start development

```bash
make kernel
make restart-agent-server-fast
cd cockpit && npm install && npm run dev
```

| Surface | URL |
|---------|-----|
| Cockpit UI | http://localhost:5173 |
| Bridge API | http://127.0.0.1:9477 |

### 3. Submit a task

Open the Cockpit, point at a workspace, submit a bounded change, and watch the checkpoint rail advance. API: [governed-tasks.md](docs/governed-tasks.md)

---

## Core commands

| Command | What it does |
|---------|--------------|
| `make checkpoint-core` | Full baseline gate — run before trusting an install |
| `make cockpit-smoke` | 53-check vertical slice only |
| `make kernel` | Build `build/dietcode-kernel` |
| `make restart-agent-server-fast` | Restart kernel socket (no rebuild) |
| `make agent-bridge-fast` | Build TypeScript bridge |
| `make cockpit` | Production UI + server build |

More: [testing.md](docs/testing.md)

### checkpoint-core-v0.1

| Layer | Status |
|-------|--------|
| Kernel | Headless JSON-RPC — sole mutation authority |
| Cockpit | Checkpoint rail, drift/approval/verify panels |
| Bridge | Session recovery, governed tasks, SSE |
| Safety | Drift · approval · verify gates |
| Validation | `make cockpit-smoke` (53 checks) |

```bash
make checkpoint-core   # must pass before checkpoint model changes
```

---

## Documentation

| Job | Docs |
|-----|------|
| **Concept** | [brief](docs/brief.md) · [philosophy](docs/philosophy.md) · [whitepaper](docs/whitepaper.md) |
| **Learn** | [checkpoint-model](docs/checkpoint-model.md) · [architecture](docs/architecture.md) · [governed-tasks](docs/governed-tasks.md) |
| **Run** | [getting-started](docs/getting-started.md) · [testing](docs/testing.md) · [troubleshooting](docs/troubleshooting.md) |
| **Build** | [agent-bridge](docs/agent-bridge.md) · [kernel-rpc](docs/kernel-rpc.md) · [integrations](docs/integrations.md) |

Index: [docs/README.md](docs/README.md)

---

## Troubleshooting

| Symptom | First command |
|---------|---------------|
| Kernel offline | `make restart-agent-server-fast` |
| Stale binary after `git pull` | `make kernel && make restart-agent-server-fast` |
| Drift blocks patch | Refresh context in Cockpit — [workspace-drift.md](docs/workspace-drift.md) |
| Task stuck before “completed” | [verify-gate.md](docs/verify-gate.md) |
| Install health unknown | `make checkpoint-core` |

Full playbook: [troubleshooting.md](docs/troubleshooting.md) · [error-codes.md](docs/error-codes.md)

---

## Optional integrations

Hermes and legacy agent-chat are optional — the checkpoint loop does not depend on any model provider.

```bash
make app
make smoke-agent-chat-live   # separate from cockpit-smoke
```

[integrations/README.md](integrations/README.md) · Research benchmarks: [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)

---

## Repository layout

```text
src/kernel/                     Kernel entry
src/platform/macos/control/     JSON-RPC server
cockpit/                        UI + bridge
agent-bridge/                   Agent workflows
scripts/                        Harnesses + cockpit-smoke
legacy_ui/                      Optional native editor
integrations/                   Hermes plugin
```

[file-structure.md](docs/file-structure.md)

---

## License

MIT — see [LICENSE](LICENSE).
