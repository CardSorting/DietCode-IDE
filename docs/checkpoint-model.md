# DietCode checkpoint model

> **DietCode gives agents bounded autonomy through visible checkpoints.**

[← Doc index](README.md) · [← README overview](../README.md#the-six-checkpoints)

A checkpoint is a **single question** the control plane must answer before the agent proceeds or before a task can be called done. Every governed feature maps to exactly one checkpoint. If it does not map cleanly, it is control-plane hygiene or observability noise — not a new gate.

## The six checkpoints

| # | Name | Plain English | Technical question |
|---|------|---------------|-------------------|
| 1 | **Context** | Did the agent read the right files? | Did the agent read valid state? |
| 2 | **Drift** | Did the repo change while the agent worked? | Did the workspace change underneath it? |
| 3 | **Approval** | Are you OK with this edit? | Is this mutation allowed? |
| 4 | **Mutation** | Did the patch apply cleanly? | Did the patch apply without error? |
| 5 | **Verification** | Do tests still pass? | Did the result pass? |
| 6 | **Completion** | Can we mark this task finished? | Can this task be called done? |

```text
1. Context   — Did the agent read valid state?
2. Drift     — Did the workspace change underneath it?
3. Approval  — Is this mutation allowed?
4. Mutation  — Did the patch apply cleanly?
5. Verification — Did the result pass?
6. Completion — Can this task be called done?
```

```text
Agent reads files
    ↓ (1) Context anchors set
Agent proposes patch
    ↓ (2) Drift gate — refresh or continue
    ↓ (3) Approval gate — approve or reject
    ↓ (4) Mutation — patch.apply + receipt
    ↓ (5) Verification — verify.run or waive
    ↓ (6) Completion — verified / waived → task done
```

---

## 1. Context checkpoint

**Question:** Did the agent read valid state?

| | |
|--|--|
| **Kernel** | `file.read*`, `workspace.snapshot`, `workspace.status`, `patch.validate` (`expectBeforeHash`) |
| **Mechanism** | Hash anchors on read; snapshot/revision for point-in-time state |
| **Block** | Implicit — stale reads surface at checkpoint 2 (drift) or 4 (patch hash mismatch) |
| **Cockpit** | No dedicated panel — state visible in drift panel after failure, timeline `tool.call.*` |
| **Recovery** | `workspace.refreshAnchor` (re-read and re-anchor tracked files) |

Context is **foundational**, not a blocking modal. Invalid context becomes visible when drift or mutation gates fire.

---

## 2. Drift checkpoint

**Question:** Did the workspace change underneath the agent?

| | |
|--|--|
| **Kernel** | `workspace.status`, `workspace.refreshAnchor`, `workspace.continueAnyway`; blocks Edit/Destructive when `driftDetected` |
| **Events** | `workspace.drift.detected` |
| **States** | `requiresContextRefresh`, `contextRefreshId`, `affectedFiles` |
| **Cockpit** | **Drift panel** — affected files, Refresh context, Continue anyway, Cancel task |
| **Doc** | [workspace-drift.md](./workspace-drift.md) |

**Not drift:** Re-running verify belongs to checkpoint 5.

---

## 3. Approval checkpoint

**Question:** Is this mutation allowed?

| | |
|--|--|
| **Kernel** | `approval.list`, `approval.get`, `approval.resolve`; `approvalRequired` on destructive RPCs |
| **Events** | `approval.required`, `approval.resolved` |
| **Task status** | `awaiting_approval` |
| **Cockpit** | **Approvals panel** — preview, approve, reject |
| **Doc** | [approval-lifecycle.md](./approval-lifecycle.md) |

Expired approvals without a decision are still checkpoint 3 — surfaced via infrastructure banner until refreshed.

---

## 4. Mutation checkpoint

**Question:** Did the patch apply cleanly?

| | |
|--|--|
| **Kernel** | `patch.validate` → `patch.apply` / `patch.applyBatch`; `mutationReceipt`, `workspace.revision` |
| **Events** | `workspace.mutated`, `file.diff` |
| **Block** | `stale_content`, `patch_failed`, drift gate (2), approval gate (3) |
| **Cockpit** | **Diffs panel** + timeline `file.diff` / `workspace.mutated` |
| **Agent** | Agent Bridge `safePatchFile` workflow |

A successful mutation always emits `workspace.mutated`, which arms checkpoint 5.

---

## 5. Verification checkpoint

**Question:** Did the result pass?

| | |
|--|--|
| **Kernel** | `verify.run`, `verify.status`; emits `verify.completed` or `verify.failed` |
| **Task validity** | `verification_required` → `verified` / `verification_failed` / `verification_waived` |
| **Cockpit** | **Verification panel** — Run verify, Show failing output, Waive, Retry, Cancel |
| **Doc** | [verify-gate.md](./verify-gate.md) |

**Waive** is an explicit operator override at this checkpoint only — not a bypass of drift or approval.

---

## 6. Completion checkpoint

**Question:** Can this task be called done?

| | |
|--|--|
| **Rule** | Agent exit ≠ done. Done requires checkpoint 5 passed or waived, or no mutations (5 skipped). |
| **Task status** | `completed` only when `verificationState` is `verified`, `verification_waived`, or `none` |
| **Events** | `task.completed`, `task.verified`, `task.verification_waived` |
| **Harness** | `verify.run` + NDJSON `task.completed` |
| **Doc** | [verify-gate.md](./verify-gate.md), [kernel-rpc.md](./kernel-rpc.md) |

---

## Feature audit

| Feature | Checkpoint | Notes |
|---------|------------|-------|
| `file.read` hash anchors | 1 Context | |
| `workspace.snapshot` / `workspace.status` | 1 Context | Also feeds 2 |
| `workspace.refreshAnchor` | 1 → 2 | Recovery after drift |
| `workspace.drift.detected` | 2 Drift | |
| `continueAnyway` | 2 Drift | Operator override |
| `coherence_mismatch` | — | Pre-drift stale context |
| `approval.*` RPCs | 3 Approval | |
| `awaiting_approval` task status | 3 Approval | |
| `patch.validate` / `patch.apply` | 4 Mutation | |
| `mutationReceipt` | 4 Mutation | |
| `workspace.mutated` | 4 → 5 | Arms verification |
| `verify.run` | 5 Verification | |
| `verification_waived` | 5 Verification | Operator override |
| `task.completed` (harness) | 6 Completion | |
| Coherence recovery smoke | — | Proves refresh + retry path |

---

## Not checkpoints (noise bucket)

These support the control plane but are **not** separate gates. Do not add UI or docs that treat them as checkpoints.

| Feature | Role |
|---------|------|
| Kernel offline / reconnect | Transport hygiene |
| Kernel restart | Session recovery ([session-recovery.md](./session-recovery.md)) |
| Log stream | Raw tail across all checkpoints — debug only |
| NDJSON harness events | Cross-checkpoint audit trail — not a gate |
| Benchmark / BroccoliQ journal | Offline reliability evaluation — parallel track |

If a proposed feature does not answer one of the six questions above, it probably belongs in the noise bucket — not the governed kernel loop.

---

## Agent ergonomics

Structured checkpoint state for agents and CI-style tooling via kernel RPC:

- `workspace.status` — drift + verify snapshot
- `approval.list` — pending approvals
- `verify.status` — verification gate

See [agent-ergonomics.md](./agent-ergonomics.md).

## Coherence hardening (v0.1)

| Area | Implementation |
|------|----------------|
| Coherence tokens | `MacControlCoherenceTokens.mm` — issuance on task-scoped reads |
| Recovery loop | `scripts/dietcode_coherence.py` — stale block, refresh, retry |
| Verify command | `dietcode_verification_authority.py` — `verify.sh` → `make test` → `npm test` |
| Agent errors | `coherence_mismatch`, `workspace_drift`, `approval_*` recovery hints |
| Release gate | `make coherence-core-v0.1` |

## Release baseline

Frozen coherence gate (tag `coherence-core-v0.1`):

```bash
make coherence-core-v0.1
```

Runs live kernel coherence token tests (`test-coherence-tokens`) and the deterministic recovery smoke (`coherence-recovery-smoke-fast`). See [testing.md](./testing.md).

## Related docs

| Doc | Checkpoint |
|-----|------------|
| [agent-ergonomics.md](./agent-ergonomics.md) | Agent-facing API |
| [workspace-drift.md](./workspace-drift.md) | 2 |
| [approval-lifecycle.md](./approval-lifecycle.md) | 3 |
| [verify-gate.md](./verify-gate.md) | 5, 6 |
| [kernel-rpc.md](./kernel-rpc.md) | RPC orchestration |
| [architecture.md](./architecture.md) | All (wiring) |
| [session-recovery.md](./session-recovery.md) | Noise bucket |
