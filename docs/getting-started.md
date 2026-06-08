# Getting started

> **Goal:** Build DietCode, open the Cockpit, and run one governed task end-to-end.

[← Doc index](README.md) · [← README](../README.md#quick-start)

| Step | What you do | What you should see |
|------|-------------|---------------------|
| 1 | [Prerequisites](#prerequisites) | Tools installed |
| 2 | [Build the kernel](#1-build-the-kernel) | Socket at `~/.dietcode/control.sock` |
| 3 | [Run the Cockpit](#2-run-the-cockpit) | UI at http://localhost:5173 |
| 4 | [Open a workspace](#3-open-a-workspace) | Project bound to kernel session |
| 5 | [Submit a task](#4-submit-a-governed-task) | Checkpoint rail advances |
| 6 | [Prove the baseline](#5-prove-the-baseline-optional-but-recommended) | `checkpoint-core` green |

---

## Prerequisites

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`clang++`, `make`)
- Node.js 20+ (Cockpit + agent-bridge)
- Python 3.11+ (harnesses, `dietcode_agent_client.py`)

---

## 1. Build the kernel

The kernel is the **only** component allowed to change files on disk.

```bash
make kernel
./build/dietcode-kernel --ensure-socket
```

| Path | Role |
|------|------|
| `~/.dietcode/control.sock` | Unix socket — how bridge and CLI talk to the kernel |
| `~/.dietcode/session.token` | Auth token (mode `0600`) |

**Verify it is alive:**

```bash
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
```

You should get a successful ping response. If not, see [troubleshooting.md](troubleshooting.md#kernel-socket).

---

## 2. Run the Cockpit

```bash
cd cockpit && npm install && npm run dev
```

| Surface | URL | Use for |
|---------|-----|---------|
| **Cockpit UI** | http://localhost:5173 | Watch tasks, approve edits, run verify |
| **Bridge API** | http://127.0.0.1:9477 | `POST /api/tasks`, scripts, integrations |

Production build (no Vite dev server):

```bash
make cockpit
cd cockpit && npm run bridge    # bridge only, after build
```

---

## 3. Open a workspace

Tell the kernel which project folder to govern:

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.openFolder \
  --params '{"path":"/path/to/your/project"}'
```

At default supervision level, opening a folder may **queue for approval**. Resolve in the Cockpit **Approvals** panel or via `approval.resolve` RPC. See [approval-lifecycle.md](approval-lifecycle.md).

---

## 4. Submit a governed task

**In the Cockpit chat**, describe a bounded change — e.g. *“Change probe.py VALUE from 1 to 2”*.

**Or via API:**

```bash
curl -s -X POST http://127.0.0.1:9477/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"message":"Fix probe VALUE","workspace":"/path/to/project","mode":"supervised"}'
```

**What to watch in the UI:**

```text
read → drift check → your approval → patch applied → verify runs → completed
```

Poll checkpoints: `GET /api/tasks/:id/checkpoints`.  
Full API: [governed-tasks.md](governed-tasks.md).

> **Remember:** The agent finishing does not mean the task succeeded. Completion requires verify to pass or be explicitly waived.

---

## 5. Prove the baseline (optional but recommended)

Before trusting your install for real work:

```bash
make checkpoint-core
```

This runs kernel + bridge + cockpit builds, the **53-check** `cockpit-smoke` vertical slice, checkpoint unit tests, and docs alignment (`make test-docs-code-drift`).  
Release tag when green: `checkpoint-core-v0.1`.

Details: [testing.md](testing.md)

---

## Restart kernel after C++ changes

```bash
make restart-agent-server-fast    # fast — no rebuild
make restart-agent-server         # rebuild kernel + restart
```

A stale kernel binary causes `method_not_found` errors (e.g. missing `workspace.status`). Always restart after pulling C++ changes.

Documented in [agent-environment.md](agent-environment.md).

---

## Optional: legacy app + Hermes

Not required for the Cockpit checkpoint loop.

```bash
make app
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
```

See [integrations.md](integrations.md) and [integrations/README.md](../integrations/README.md).

---

## Next steps

| I want to… | Doc |
|------------|-----|
| Understand the six gates | [checkpoint-model.md](checkpoint-model.md) |
| See how components connect | [architecture.md](architecture.md) |
| Run all test targets | [testing.md](testing.md) |
| Fix something broken | [troubleshooting.md](troubleshooting.md) |
