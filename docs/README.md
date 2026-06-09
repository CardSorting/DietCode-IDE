# DietCode documentation

> **A local kernel experiment for preserving operational coherence across agent read, diff, patch, approval, and verification surfaces.**

[← Project overview](../README.md) · Baseline: `make coherence-core-v0.1`

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
| **Understand what DietCode does** (no install) | [Root README](../README.md) → [coherence tokens](coherence-tokens.md) |
| **Build the kernel and run coherence tests** | [getting-started.md](getting-started.md) |
| **Confirm my machine matches the release baseline** | [testing.md](testing.md) → `make coherence-core-v0.1` |
| **Fix a broken socket or coherence mismatch** | [troubleshooting.md](troubleshooting.md) |
| **Call kernel RPC from Python** | [kernel-rpc.md](kernel-rpc.md) → `scripts/dietcode_agent_client.py` |
| **Understand removed UI surfaces** | [archive-note.md](archive-note.md) |
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

| Doc | When to read | Audience |
|-----|--------------|----------|
| [coherence-tokens.md](coherence-tokens.md) | Canonical coherence token model (v0.1) | Everyone |
| [checkpoint-model.md](checkpoint-model.md) | Six-gate map, feature → checkpoint routing | Everyone |
| [architecture.md](architecture.md) | Kernel + control plane wiring | Developers |

### Checkpoint deep dives

| Gate | Plain English | Doc |
|------|---------------|-----|
| Coherence | Agent context bound to kernel revision | [coherence-tokens.md](coherence-tokens.md) |
| 2 Drift | Files changed while the agent was working | [workspace-drift.md](workspace-drift.md) |
| 3 Approval | Mutation requires explicit clearance | [approval-lifecycle.md](approval-lifecycle.md) |
| 5–6 Verify | Tests must pass before “done” | [verify-gate.md](verify-gate.md) |
| Recovery | Kernel restarted mid-task | [session-recovery.md](session-recovery.md) |
| Agent loop | Polling and RPC from code | [agent-ergonomics.md](agent-ergonomics.md) |

---

## Run and validate

| Doc | When to read |
|-----|--------------|
| [getting-started.md](getting-started.md) | First build, kernel socket, coherence baseline |
| [testing.md](testing.md) | `coherence-core-v0.1`, kernel harness ladder |
| [agent-environment.md](agent-environment.md) | Env vars, `~/.dietcode` paths, `restart-agent-server` |

### Quick health check

```bash
make coherence-core-v0.1
```

Proves kernel coherence tokens + recovery smoke + docs alignment on your Mac.

---

## Build agents and integrations

| Doc | When to read |
|-----|--------------|
| [kernel-rpc.md](kernel-rpc.md) | JSON-RPC methods, Python CLI |
| [agent-tooling.md](agent-tooling.md) | Read/mutate tool contracts |
| [agent-shell-tooling.md](agent-shell-tooling.md) | Bounded shell (`shell.rg`, `shell.catSmall`, …) |
| [runtime-invariants.md](runtime-invariants.md) | Sort order, stale writes, symlink policy |

---

## When something breaks

| Symptom | First step | Full guide |
|---------|------------|------------|
| “Kernel offline” / socket error | `make restart-agent-server-fast` | [troubleshooting.md](troubleshooting.md#kernel-socket) |
| Patch blocked — coherence | Re-read with `taskId` | [coherence-tokens.md](coherence-tokens.md) |
| Patch blocked — drift | Refresh workspace anchor | [workspace-drift.md](workspace-drift.md) |
| Unknown error code | Search catalog | [error-codes.md](error-codes.md) |

---

## Operations reference

| Doc | Purpose |
|-----|---------|
| [file-structure.md](file-structure.md) | Repository map |
| [archive-note.md](archive-note.md) | Removed cockpit / legacy UI / bridge surfaces |
| [troubleshooting.md](troubleshooting.md) | Full failure playbook |

---

## Outside `docs/`

| Path | Purpose |
|------|---------|
| [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md) | Adversarial benchmark track (parallel to coherence-core) |
| [benchmarks/agent_success/](../benchmarks/agent_success/) | Evaluation corpus |

---

## For maintainers

After changing kernel RPC surfaces or Makefile targets:

```bash
make test-docs-code-drift
```

Contract sources: `scripts/agent_contracts.py`, `scripts/test_docs_code_drift.py`.
