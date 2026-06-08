# DietCode documentation

> **Supervise AI code changes with visible checkpoints — not blind trust.**

[← Project overview](../README.md) · Baseline: `make checkpoint-core` (tag `checkpoint-core-v0.1`)

<p align="center">
  <a href="#i-want-to">I want to…</a> ·
  <a href="#learn-the-model">Learn</a> ·
  <a href="#run-and-validate">Run</a> ·
  <a href="#build-agents">Build</a> ·
  <a href="#when-something-breaks">Fix</a>
</p>

---

## I want to…

| I want to… | Go here |
|------------|---------|
| **Understand what DietCode does** (no install) | [Root README](../README.md#in-30-seconds) → [checkpoint model](checkpoint-model.md) |
| **Install and open the Cockpit** | [getting-started.md](getting-started.md) |
| **Confirm my machine matches the release baseline** | [testing.md](testing.md) → `make checkpoint-core` |
| **Submit a task and watch checkpoints** | [governed-tasks.md](governed-tasks.md) |
| **Fix a broken socket, drift block, or stuck task** | [troubleshooting.md](troubleshooting.md) |
| **Connect Hermes or the legacy app** | [integrations.md](integrations.md) → [integrations/README.md](../integrations/README.md) |
| **Build my own agent on the bridge** | [agent-bridge.md](agent-bridge.md) → [kernel-rpc.md](kernel-rpc.md) |
| **Look up an error code** | [error-codes.md](error-codes.md) |

---

## Concept papers

| Doc | When to read | Length |
|-----|--------------|--------|
| [brief.md](brief.md) | Executive companion — start here for the idea | ~5 min |
| [philosophy.md](philosophy.md) | Why governed mutation; values and refusals | ~20 min |
| [whitepaper.md](whitepaper.md) | Full runtime architecture and contracts | ~45 min |

---

## Learn the model

Start with the **six checkpoints** — every other doc maps to one of them.

| Doc | When to read | Audience |
|-----|--------------|----------|
| [brief.md](brief.md) | Fastest orientation before the spec | Everyone |
| [checkpoint-model.md](checkpoint-model.md) | Canonical gate map, feature → checkpoint routing | Everyone |
| [architecture.md](architecture.md) | Kernel, bridge, Cockpit wiring and ports | Developers |
| [governed-tasks.md](governed-tasks.md) | `POST /api/tasks`, modes, SSE events | Operators + integrators |

### Checkpoint deep dives

| Gate | Plain English | Doc |
|------|---------------|-----|
| 2 Drift | Files changed while the agent was working | [workspace-drift.md](workspace-drift.md) |
| 3 Approval | You must approve before the edit lands | [approval-lifecycle.md](approval-lifecycle.md) |
| 5–6 Verify | Tests must pass before “done” | [verify-gate.md](verify-gate.md) |
| Recovery | Bridge restarted mid-task | [session-recovery.md](session-recovery.md) |
| Agent loop | Polling checkpoints from code | [agent-ergonomics.md](agent-ergonomics.md) |

---

## Run and validate

| Doc | When to read |
|-----|--------------|
| [getting-started.md](getting-started.md) | First build, kernel socket, workspace, Cockpit URLs |
| [testing.md](testing.md) | `checkpoint-core`, `cockpit-smoke`, harness ladder |
| [agent-environment.md](agent-environment.md) | Env vars, `~/.dietcode` paths, `restart-agent-server` |

### Quick health check

```bash
make checkpoint-core
```

Proves kernel + bridge + cockpit + 53-check vertical slice + docs alignment on your Mac.

---

## Build agents and integrations

| Doc | When to read |
|-----|--------------|
| [agent-bridge.md](agent-bridge.md) | TypeScript workflows, packaging, `safePatchFile` |
| [kernel-rpc.md](kernel-rpc.md) | JSON-RPC methods, Python CLI |
| [agent-tooling.md](agent-tooling.md) | Read/mutate tool contracts |
| [agent-shell-tooling.md](agent-shell-tooling.md) | Bounded shell (`shell.rg`, `shell.catSmall`, …) |
| [runtime-invariants.md](runtime-invariants.md) | Sort order, stale writes, symlink policy |
| [integrations.md](integrations.md) | Hermes plugin overview |

---

## When something breaks

| Symptom | First step | Full guide |
|---------|------------|------------|
| “Kernel offline” / socket error | `make restart-agent-server-fast` | [troubleshooting.md](troubleshooting.md#kernel-socket) |
| Patch blocked — drift | Refresh context in Cockpit | [workspace-drift.md](workspace-drift.md) |
| Task stuck on approval | Cockpit Approvals panel | [approval-lifecycle.md](approval-lifecycle.md) |
| Agent finished but task not done | Run verify | [verify-gate.md](verify-gate.md) |
| Unknown error code | Search catalog | [error-codes.md](error-codes.md) |

---

## Operations reference

| Doc | Purpose |
|-----|---------|
| [file-structure.md](file-structure.md) | Repository map |
| [troubleshooting.md](troubleshooting.md) | Full failure playbook |

---

## Outside `docs/`

| Path | Purpose |
|------|---------|
| [integrations/README.md](../integrations/README.md) | Hermes enable script + agent chat bundle |
| [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) | Adversarial benchmark track (parallel to checkpoint-core) |
| [benchmarks/agent_success/](../benchmarks/agent_success/) | Evaluation corpus + whitepaper |

---

## For maintainers

After changing agent-runtime surfaces or Makefile targets:

```bash
make test-docs-code-drift
```

Contract sources: `scripts/agent_contracts.py`, `scripts/test_docs_code_drift.py`.
