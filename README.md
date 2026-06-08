# DietCode

**A governed local mutation runtime for agentic software work.**
Not a web UI. Not another editor.

C++ kernel · cockpit control plane · agent bridge · visible checkpoints

---

## What DietCode Is

DietCode is a local-first control plane for autonomous and semi-autonomous software mutation on macOS.

It separates:

* **workspace authority**
* **agent orchestration**
* **human oversight**
* **verification**
* **UI visualization**

into explicit layers with visible operational checkpoints.

```text
dietcode-kernel
  Headless C++ runtime
  Sole workspace mutation authority

cockpit bridge
  HTTP + SSE governed task plane
  Session recovery + checkpoint state

cockpit UI
  Vite + React control surface
  Drift / approval / verification checkpoints

agent-bridge
  TypeScript workflows for external agents
  Hermes, scripts, CI, deterministic runners
```

Hard rule:

> The cockpit never edits files directly.
> Only `dietcode-kernel` mutates the workspace.

DietCode is not an IDE replacement.
The optional AppKit editor under `legacy_ui/` exists only as a compatibility layer.

The product surface is the checkpointed control loop.

---

## The Control Loop

DietCode inserts six visible checkpoints between agent intent and “done.”

```text
1. Context
   Did the agent read valid state?

2. Drift
   Did the workspace change underneath it?

3. Approval
   Is this mutation allowed?

4. Mutation
   Did the patch apply cleanly?

5. Verification
   Did the result pass?

6. Completion
   Can this task actually be called done?
```

Full reference:

[docs/checkpoint-model.md](docs/checkpoint-model.md)

Operational flow:

```text
prompt
  ↓
read
  ↓
drift check
  ↓
approval
  ↓
patch
  ↓
verify
  ↓
completed
```

Agent exit does not imply success.

Tasks only reach `completed` after:

* verification passes
* or verification is explicitly waived

---

## Why DietCode Exists

Most agent tooling collapses workspace mutation, orchestration, and UI into a single opaque system.

DietCode separates them.

The goal is not fully autonomous coding.

The goal is:

> bounded autonomy through visible checkpoints.

DietCode treats agent mutation as an operational problem:

* verify state before mutation
* surface dangerous transitions
* pause when supervision is required
* recover cleanly after failure
* never silently continue after the control loop breaks

---

## Quick Start

```bash
git clone <repo>
cd DietCode-IDE

# frozen baseline
make checkpoint-core
```

`checkpoint-core` validates the full governed pipeline:

* kernel
* bridge
* cockpit
* checkpoint APIs
* recovery semantics
* smoke fixtures
* verification routing

Daily development:

```bash
make kernel
make restart-agent-server-fast

cd cockpit
npm install
npm run dev
```

Cockpit:

```text
http://localhost:5173
```

---

## Core Commands

| Command                          | Purpose                       |
| -------------------------------- | ----------------------------- |
| `make checkpoint-core`           | Frozen production baseline    |
| `make cockpit-smoke`             | 53-check vertical slice       |
| `make kernel`                    | Build `build/dietcode-kernel` |
| `make restart-agent-server-fast` | Restart kernel socket         |
| `make agent-bridge-fast`         | Build TypeScript bridge       |
| `make cockpit`                   | Build cockpit UI + server     |

References:

[docs/getting-started.md](docs/getting-started.md) · [docs/testing.md](docs/testing.md)

---

## Current Baseline

### checkpoint-core-v0.1

| Layer      | Status                                   |
| ---------- | ---------------------------------------- |
| Kernel     | Headless JSON-RPC runtime                |
| Cockpit    | Checkpoint rail + governed task UI       |
| Bridge     | Session recovery + governed tasks        |
| Safety     | Drift gate + approval gate + verify gate |
| Recovery   | Bounded session restore                  |
| Validation | 53-check vertical slice                  |

Before checkpoint model changes:

```bash
make checkpoint-core
```

must pass.

---

## Architecture

```text
Human / agent
      ↓
Cockpit UI
      ↓
Bridge (HTTP + SSE)
      ↓
dietcode-kernel
      ↓
Workspace
```

Kernel responsibilities:

* file mutation
* patch application
* verification execution
* workspace state
* drift anchoring
* approval enforcement

Cockpit responsibilities:

* task steering
* checkpoint visualization
* approvals
* verification controls
* recovery UI

Agents never mutate the workspace directly.

All mutation flows through the kernel.

Detailed architecture:

[docs/architecture.md](docs/architecture.md)

---

## Reliability Philosophy

DietCode does not attempt to hide operational failure.

If the control loop breaks:

* tasks disconnect visibly
* approvals expire explicitly
* drift blocks mutation
* verification blocks completion
* stale sessions surface warnings
* recovery requires operator intent

The system should never imply an agent is still safely operating when it is not.

---

## Documentation

| Document              | Purpose                             |
| --------------------- | ----------------------------------- |
| [docs/README.md](docs/README.md) | Documentation index                 |
| [checkpoint-model.md](docs/checkpoint-model.md) | Canonical checkpoint model          |
| [getting-started.md](docs/getting-started.md) | Build + startup                     |
| [testing.md](docs/testing.md)          | Smoke + baseline validation         |
| [governed-tasks.md](docs/governed-tasks.md)   | Task API + lifecycle                |
| [agent-ergonomics.md](docs/agent-ergonomics.md) | Agent recovery + checkpoint polling |
| [kernel-rpc.md](docs/kernel-rpc.md)       | RPC surface                         |
| [troubleshooting.md](docs/troubleshooting.md)  | Failure recovery                    |

Deep dives:

[workspace-drift](docs/workspace-drift.md) · [approval-lifecycle](docs/approval-lifecycle.md) · [verify-gate](docs/verify-gate.md) · [session-recovery](docs/session-recovery.md)

---

## Optional Integrations

Hermes integration is optional.

The checkpoint loop functions independently of any single model provider or agent runtime.

```bash
make app
make smoke-agent-chat-live
```

Integration docs:

[integrations/README.md](integrations/README.md)

---

## Repository Layout

```text
src/kernel/
  Headless kernel runtime

src/platform/macos/control/
  JSON-RPC server

cockpit/
  React cockpit + bridge

agent-bridge/
  TypeScript agent workflows

scripts/
  Harnesses + smoke tests

legacy_ui/
  Optional native editor

integrations/
  External agent integrations
```

---

## License

MIT License — see [LICENSE](LICENSE).
