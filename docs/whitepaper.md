# DietCode governed mutation runtime

**Technical whitepaper for the kernel/coherence-core archive**

Version 1.0 · June 2026 · Baseline **coherence-core-v0.1**  
Philosophy: [philosophy.md](philosophy.md) · Brief: [brief.md](brief.md)

---

## Abstract

Autonomous coding agents introduce a structural problem: **mutation**, **orchestration**, and **operator visibility** are typically fused into a single opaque interface. Operators cannot see which safety precondition failed, whether the workspace changed mid-task, or whether “done” means verified or merely attempted.

DietCode is a **governed local mutation kernel** for macOS, preserved as a **coherence-core archive**. A headless C++ process (`dietcode-kernel`) holds sole workspace mutation authority. Agents integrate through JSON-RPC (`scripts/dietcode_agent_client.py`) — they request clearance; they do not write files directly. Operational coherence is enforced via task-scoped coherence tokens before drift, approval, and verify gates.

The runtime enforces **six checkpoints** between agent intent and task completion. Agent process exit does not imply success.

This document specifies problem framing, design principles, architecture, wire contracts, recovery semantics, and the frozen **coherence-core-v0.1** baseline. Adversarial evaluation is a separate frozen research track at [benchmarks/agent_success/WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md).

---

## 1. Problem statement

### 1.1 Four confounded questions

| # | Question |
|---|----------|
| Q1 | Who is allowed to mutate the workspace? |
| Q2 | Under what preconditions may a mutation proceed? |
| Q3 | How does the operator observe progress and failure? |
| Q4 | When may a task be called *done*? |

When Q1–Q4 collapse into chat, operators develop false confidence.

### 1.2 Failure modes

- **Stale context** — patch based on files that changed after read
- **Wrong-file mutation** — correct pattern, wrong path
- **Silent success** — agent exits while tests fail
- **Authority leakage** — multiple writers without a single gate
- **Unbounded session** — restart loses safe resume semantics

DietCode addresses these as **control-plane** failures.

### 1.3 Design goal

> **Bounded autonomy through visible checkpoints** — air-traffic control for AI edits.

---

## 2. Design principles

### 2.1 Single mutation authority

Only `dietcode-kernel` applies patches. Agents propose via RPC.

### 2.2 Checkpoints as gates

Each capability maps to one of six questions (§3). Non-gate features belong in transport hygiene or observability.

### 2.3 Legible failure

Blocks surface `string_code`, `recovery_hint`, `nextRecommendedCommand` ([error-codes.md](error-codes.md)).

### 2.4 Completion is a system state

| State | Meaning |
|-------|---------|
| Agent exited | Process ended — **not** completion |
| `verification_required` | Mutation occurred; verify pending |
| `verified` | Verify passed |
| `completed` | Checkpoint 6 cleared |

### 2.5 Local-first trust boundary

macOS process + Unix socket + local workspace. No cloud kernel required.

### 2.6 Frozen baseline provability

```bash
make validate
```

Tag: **coherence-core-v0.1**.

---

## 3. Checkpoint model

| # | Name | Question |
|---|------|----------|
| 1 | Context | Did the agent read valid state? |
| 2 | Drift | Did the workspace change underneath it? |
| 3 | Approval | Is this mutation allowed? |
| 4 | Mutation | Did the patch apply cleanly? |
| 5 | Verification | Did the result pass? |
| 6 | Completion | Can this task be called done? |

Noise bucket (not gates): kernel reconnect, session reload, log tail, benchmark journal. See [checkpoint-model.md](checkpoint-model.md).

---

## 4. System architecture

```text
┌─────────────────────────────────────────────────────────┐
│  Agents / harnesses / CI (Python)                       │
│  dietcode_agent_client.py · dietcode_coherence.py       │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON + session.token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel                                        │
│  MacControlServer · coherence · WorkspaceSession        │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

Experimental cockpit, HTTP bridge, and TypeScript agent-bridge were archived after proving the model. See [archive-note.md](archive-note.md).

Detail: [architecture.md](architecture.md).

### 4.1 Responsibilities

| Component | Owns |
|-----------|------|
| Kernel | Mutation, coherence tokens, drift, approvals, verify |
| Python CLI | RPC transport, harness orchestration, recovery helpers |

### 4.2 Governed path

```text
file.read (taskId) → coherence token
  → patch.apply → approval if supervised
  → workspace.mutated → verify.run
  → harness marks completed
```

Recovery smoke: `scripts/coherence_recovery_smoke.py`.

---

## 5. Wire contracts

### 5.1 Kernel RPC

```json
{
  "id": "uuid",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": {},
  "token": "<session.token>"
}
```

Catalog: [kernel-rpc.md](kernel-rpc.md).

### 5.2 Coherence (v0.1)

Issuing reads with `taskId`: `file.read`, `file.readBatch`, `file.readRange`, `file.readAround`, `file.stat`, `workspace.status`.

Mutations require `coherenceTokenId` + `expectedWorkspaceRevision`. Stale → `coherence_mismatch`.

Detail: [coherence-tokens.md](coherence-tokens.md).

### 5.3 Autonomy default

Level **3 (supervised)**. Destructive RPCs queue `approvalRequired` until `approval.resolve`.

---

## 6. Recovery and session semantics

Kernel persists bounded state under `~/.dietcode/session/`:

- `pending_approvals.json`
- `recent_events.ndjson`
- `recent_diffs.json`

On kernel restart, harnesses call `make restart-agent-server-fast` and `--wait-ready`. No silent auto-resume into drift or verify failure.

Detail: [session-recovery.md](session-recovery.md).

Python coherence recovery: `scripts/dietcode_coherence.py`.

---

## 7. Verification routing

After mutation, `workspace.mutated` arms checkpoint 5. `dietcode_verification_authority.py` resolves:

1. `./verify.sh`
2. `make test`
3. `npm test`

Detail: [verify-gate.md](verify-gate.md).

---

## 8. Release baseline

### 8.1 validate / coherence-core

```bash
make validate
```

| Step | Proves |
|------|--------|
| `test-coherence-tokens-fast` | Issuance + `coherence_mismatch` enforcement |
| `coherence-recovery-smoke-fast` | Stale block → refresh → retry → verify |
| `test-docs-code-drift` | Docs ↔ contracts lock |

### 8.2 Parallel research track

`benchmarks/agent_success/` — frozen adversarial results. Does not gate coherence-core. See [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md).

---

## 9. Comparison

| Pattern | Limitation | DietCode |
|---------|------------|----------|
| Chat-native plugin | Unclear mutation authority | Kernel-only writes |
| Agent exits → done | Verify may not run | Verify gate |
| File watcher heuristics | Reactive, not gated | Drift gate before patch |
| Cloud sandbox | Remote trust boundary | Local socket + approvals |

---

## 10. Threat framing

| Risk | Mitigation |
|------|------------|
| Unauthorized write | Single kernel authority |
| Stale patch | Coherence + drift + hash validation |
| Symlink escape | Shell/search policies |
| Unverified ship | Verify gate |
| Token leakage | `0600` socket dir |

---

## 11. Limitations

- **macOS only** at this baseline
- **Not** a general-purpose IDE — UI archived
- **Not** model-specific — any RPC client may integrate
- **Not** fully autonomous — bounded by design
- **Python integration path** in-tree; TypeScript bridge removed

---

## 12. Conclusion

DietCode reframes agentic coding as **governed mutation**: one authority, coherence tokens, six checkpoints, legible failure, completion tied to verification.

Run `make validate` on your machine. Tag **coherence-core-v0.1** when green.

---

## References

| Document | Content |
|----------|---------|
| [philosophy.md](philosophy.md) | Values |
| [checkpoint-model.md](checkpoint-model.md) | Gate specification |
| [coherence-tokens.md](coherence-tokens.md) | Coherence model |
| [kernel-rpc.md](kernel-rpc.md) | RPC reference |
| [testing.md](testing.md) | Validation ladder |
| [archive-note.md](archive-note.md) | Removed surfaces |
