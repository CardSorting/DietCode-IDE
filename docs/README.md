# DietCode documentation

> **DietCode gives agents bounded autonomy through visible checkpoints.**

Project overview: [root README](../README.md).  
Release baseline: `make checkpoint-core` (tag `checkpoint-core-v0.1`).

---

## Start here

| Doc | Purpose |
|-----|---------|
| [checkpoint-model.md](checkpoint-model.md) | **Canonical** — six gates, feature map, noise bucket |
| [getting-started.md](getting-started.md) | Build kernel, run cockpit, open a workspace |
| [testing.md](testing.md) | `checkpoint-core`, `cockpit-smoke`, harness targets |
| [architecture.md](architecture.md) | Kernel, bridge, cockpit wiring |

---

## Governed control loop

| Doc | Checkpoint |
|-----|------------|
| [governed-tasks.md](governed-tasks.md) | 6 — task orchestration, `POST /api/tasks` |
| [workspace-drift.md](workspace-drift.md) | 2 — drift detection and recovery |
| [approval-lifecycle.md](approval-lifecycle.md) | 3 — supervised mutations |
| [verify-gate.md](verify-gate.md) | 5–6 — verify before completion |
| [session-recovery.md](session-recovery.md) | Noise bucket — bridge reload, session files |
| [agent-ergonomics.md](agent-ergonomics.md) | Agent-facing checkpoint API |

---

## Agents and kernel

| Doc | Purpose |
|-----|---------|
| [agent-bridge.md](agent-bridge.md) | TypeScript bridge — workflows, CLI, packaging |
| [kernel-rpc.md](kernel-rpc.md) | JSON-RPC methods, permissions, Python CLI |
| [agent-tooling.md](agent-tooling.md) | Read/mutate tool contracts (frozen key sets) |
| [agent-shell-tooling.md](agent-shell-tooling.md) | Bounded shell tools |
| [error-codes.md](error-codes.md) | `string_code` catalog + recovery hints |
| [runtime-invariants.md](runtime-invariants.md) | Sort order, stale writes, symlink policy |
| [agent-environment.md](agent-environment.md) | Env vars, config paths, socket |

---

## Operations

| Doc | Purpose |
|-----|---------|
| [file-structure.md](file-structure.md) | Repository map |
| [troubleshooting.md](troubleshooting.md) | Common failures |
| [integrations.md](integrations.md) | Hermes plugin (optional) |

---

## Outside `docs/`

| Path | Purpose |
|------|---------|
| [integrations/README.md](../integrations/README.md) | Hermes enable + agent chat bundle |
| [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) | Adversarial benchmark track |
| [benchmarks/agent_success/](../benchmarks/agent_success/) | Evaluation corpus |

---

## Doc hygiene

After changing agent-runtime surfaces:

```bash
make test-docs-code-drift
```

Contract sources: `scripts/agent_contracts.py`, `scripts/test_docs_code_drift.py`.
