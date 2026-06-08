<p align="center">
  <img src="resources/logo.svg" width="180" height="180" alt="DietCode Logo">
</p>

<h1 align="center">DietCode</h1>

<p align="center">
  <strong>A governed local mutation runtime — not a web UI, not another editor.</strong><br>
  <em>C++ kernel · cockpit control plane · agent bridge · visible checkpoints</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4CAF50.svg?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg?style=for-the-badge" alt="Platform">
  <img src="https://img.shields.io/badge/baseline-checkpoint--core--v0.1-blue.svg?style=for-the-badge" alt="Baseline">
</p>

---

## What DietCode is

DietCode is the **local control plane for agentic software work** on macOS.

```text
dietcode-kernel   Headless C++ runtime — sole workspace mutation authority
cockpit bridge    HTTP API + session store — governed task plane
cockpit UI        Vite + React — checkpoints you can see and steer
agent-bridge      TypeScript workflows for external agents (Hermes, scripts, CI)
```

**Hard rule:** The cockpit never edits files. Only `dietcode-kernel` mutates the workspace.

No Electron in the cockpit path. No cloud defaults. The legacy AppKit editor in `legacy_ui/` is optional — it is not the product surface.

> DietCode is not “a web UI.” It is a governed local mutation runtime, proven by a 53-check vertical slice across npm, Make, and verify.sh workspaces.

---

## The control loop

Six checkpoints between agent intent and “done”:

```text
1. Context       Did the agent read valid state?
2. Drift         Did the workspace change underneath it?
3. Approval      Is this mutation allowed?
4. Mutation      Did the patch apply cleanly?
5. Verification  Did the result pass?
6. Completion    Can this task be called done?
```

Full map: [docs/checkpoint-model.md](docs/checkpoint-model.md)

```text
prompt → read → drift check → approval → patch → verify → completed
```

Agent exit does **not** mean done. Tasks reach `completed` only after verification passes or is explicitly waived.

---

## Quick start

```bash
git clone <repo> && cd DietCode-IDE

# Frozen baseline (build + 53-check vertical slice + unit tests + docs drift)
make checkpoint-core

# Day-to-day development
make kernel
make restart-agent-server-fast
cd cockpit && npm install && npm run dev   # UI + bridge on :9477
```

| Command | Purpose |
|---------|---------|
| `make checkpoint-core` | Release gate — tag `checkpoint-core-v0.1` |
| `make cockpit-smoke` | 53-check vertical slice only |
| `make kernel` | Build `build/dietcode-kernel` |
| `make restart-agent-server-fast` | Restart kernel socket (no rebuild) |
| `make agent-bridge-fast` | Build TypeScript agent bridge |
| `make cockpit` | Build cockpit UI + server types |

Details: [docs/getting-started.md](docs/getting-started.md) · [docs/testing.md](docs/testing.md)

---

## Current baseline (`checkpoint-core-v0.1`)

| Layer | Status |
|-------|--------|
| **Kernel** | Headless; JSON-RPC on `~/.dietcode/control.sock` |
| **Cockpit** | Checkpoint rail, drift panel, approval panel, verify gate, diff ring |
| **Bridge** | Governed tasks, session recovery, checkpoint API |
| **Safety** | Supervised approvals (autonomy 3), drift gate, verify gate |
| **Recovery** | Bounded session restore after bridge reload |
| **Validation** | `cockpit-smoke` — npm-test, make-test, verify-sh fixtures |

```bash
make checkpoint-core   # must pass before Hermes / benchmark work moves
```

---

## Architecture (one screen)

```text
Human / agent
    ↓
Cockpit UI  ──SSE──┐
    ↓              │
POST /api/tasks    │
    ↓              │
Bridge (tsx)  ─────┘
    ↓ Unix socket + session token
dietcode-kernel
    ↓
Workspace (patches, verify, git, shell)
```

Wiring: [docs/architecture.md](docs/architecture.md)

---

## Documentation

| Doc | Read when |
|-----|-----------|
| [docs/README.md](docs/README.md) | Full index |
| [checkpoint-model.md](docs/checkpoint-model.md) | Canonical six-gate map |
| [getting-started.md](docs/getting-started.md) | Build, run cockpit, kernel socket |
| [testing.md](docs/testing.md) | Make targets, `checkpoint-core`, smoke |
| [governed-tasks.md](docs/governed-tasks.md) | `POST /api/tasks`, modes, events |
| [agent-ergonomics.md](docs/agent-ergonomics.md) | `GET /api/checkpoints`, agent loop |
| [agent-bridge.md](docs/agent-bridge.md) | TypeScript bridge for agents |
| [kernel-rpc.md](docs/kernel-rpc.md) | RPC surface, CLI, permissions |
| [troubleshooting.md](docs/troubleshooting.md) | Socket, token, drift, verify failures |

Checkpoint deep dives: [workspace-drift](docs/workspace-drift.md) · [approval-lifecycle](docs/approval-lifecycle.md) · [verify-gate](docs/verify-gate.md) · [session-recovery](docs/session-recovery.md)

---

## Optional: Hermes + legacy app

Hermes Agent integration is **optional** — not required for the checkpoint loop.

```bash
make app                              # legacy AppKit bundle + kernel resources
make smoke-agent-chat-live            # bounded Hermes edit (separate from cockpit-smoke)
```

See [integrations/README.md](integrations/README.md).

---

## Reliability evaluation (parallel track)

Adversarial mutation benchmarks live under `benchmarks/agent_success/`. They evaluate runtime reliability; they are **not** the cockpit checkpoint gate.

- [AGENT_RUNTIME_RELIABILITY.md](AGENT_RUNTIME_RELIABILITY.md)
- [benchmarks/agent_success/README.md](benchmarks/agent_success/README.md)

Run separately from `make checkpoint-core`.

---

## Repository layout

```text
src/kernel/                  dietcode-kernel entry + workspace adapter
src/platform/macos/control/  JSON-RPC server (MacControlServer)
cockpit/                     React UI + bridge server (tsx)
agent-bridge/                @dietcode/agent-bridge package
scripts/                     Harnesses, cockpit-smoke, dietcode_agent_client.py
scripts/fixtures/cockpit_smoke/   Vertical-slice fixture repos
legacy_ui/                   Optional native editor (not cockpit)
integrations/                Hermes plugin sync boundary
```

[docs/file-structure.md](docs/file-structure.md)

---

## License

MIT — see [LICENSE](LICENSE).
