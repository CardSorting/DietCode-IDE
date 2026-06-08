# DietCode checkpoint model

> **DietCode gives agents bounded autonomy through visible checkpoints.**

A checkpoint is a **single question** the control plane must answer before the agent proceeds or before a task can be called done. Every governed feature maps to exactly one checkpoint. If it does not map cleanly, it is control-plane hygiene or observability noise — not a new gate.

## The six checkpoints

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
| **Cockpit** | Verification panel (pending/failed); timeline `task.completed` |
| **Doc** | [governed-tasks.md](./governed-tasks.md), [verify-gate.md](./verify-gate.md) |

---

## Feature audit

| Feature | Checkpoint | Notes |
|---------|------------|-------|
| `file.read` hash anchors | 1 Context | |
| `workspace.snapshot` / `workspace.status` | 1 Context | Also feeds 2 |
| `workspace.refreshAnchor` | 1 → 2 | Recovery after drift |
| `workspace.drift.detected` | 2 Drift | |
| Drift panel | 2 Drift | |
| `continueAnyway` | 2 Drift | Operator override |
| `approval.*` RPCs | 3 Approval | |
| Approval panel | 3 Approval | |
| `awaiting_approval` task status | 3 Approval | |
| `patch.validate` / `patch.apply` | 4 Mutation | |
| `mutationReceipt` | 4 Mutation | |
| Diffs panel | 4 Mutation | Observability |
| `workspace.mutated` | 4 → 5 | Arms verification |
| `verify.run` | 5 Verification | |
| Verification panel | 5 Verification | |
| `verification_waived` | 5 Verification | Operator override |
| `task.completed` (governed) | 6 Completion | |
| Governed task registry | 6 Completion | Orchestrates 1–5 |

---

## Not checkpoints (noise bucket)

These support the control plane but are **not** separate gates. Do not add UI or docs that treat them as checkpoints.

| Feature | Role |
|---------|------|
| Kernel offline / reconnect | Transport hygiene |
| Bridge reconnected | Session recovery |
| SSE stale | Stream hygiene |
| Session export / clear | Ephemeral recovery ([session-recovery.md](./session-recovery.md)) |
| Task disconnected | Recovery after bridge restart |
| Log stream | Raw tail across all checkpoints — debug only |
| Chat panel | Task entry point — not a gate |
| Task timeline | Cross-checkpoint audit trail — not a gate |
| Benchmark / BroccoliQ journal | Offline reliability evaluation — parallel track |

If a proposed feature does not answer one of the six questions above, it probably belongs in the noise bucket or in the agent bridge — not the governed cockpit loop.

---

## Cockpit layout (checkpoint-aligned)

```text
[ Infrastructure banners ]     kernel offline, disconnected, bridge reconnected, SSE stale
[ Checkpoint 2 · Drift ]       when driftDetected
[ Checkpoint 5 · Verification] when verification_required / verification_failed
[ Chat ]                       submit governed task
[ Timeline + Diffs ]           4 Mutation observability + full trail
[ Approvals ]                  3 Approval
[ Logs ]                       noise bucket (optional debug)
```

---

## Agent ergonomics

Structured checkpoint state for agents and CI-style tooling:

- `GET /api/checkpoints` — active task
- `GET /api/tasks/:id/checkpoints` — per-task pipeline snapshot

Cockpit **CheckpointRail** mirrors GitHub Actions stage UX: six steps, explicit `passed` / `active` / `failed` / `blocked`.

See [agent-ergonomics.md](./agent-ergonomics.md).

## Production hardening (audit pass)

| Area | Implementation |
|------|----------------|
| Verify command | Auto-resolve `verify.sh`, `make test`, `npm test` ([verifyCommandResolver.ts](../cockpit/server/verifyCommandResolver.ts)) |
| Mutation diffs | `workspace.mutated` → session diff ring + Diff panel |
| Active task | Session prefers `verification_required` / `verification_failed` |
| Agent errors | `workspace_drift`, `approval_*` recovery hints in bridge |
| Hermes plugin | Emits `workspace.drift.detected` on drift block |
| No duplicate UI | Drift/verify banners removed — panels + rail only |

## Release baseline

Frozen control-loop gate (tag `checkpoint-core-v0.1`):

```bash
make checkpoint-core
```

Runs kernel + agent-bridge + cockpit builds, the 53-check `cockpit-smoke` vertical slice, checkpoint unit tests (resolver / session / checkpoints), and `test-docs-code-drift`.

## Related docs

| Doc | Checkpoint |
|-----|------------|
| [agent-ergonomics.md](./agent-ergonomics.md) | Agent-facing API |
| [workspace-drift.md](./workspace-drift.md) | 2 |
| [approval-lifecycle.md](./approval-lifecycle.md) | 3 |
| [verify-gate.md](./verify-gate.md) | 5, 6 |
| [governed-tasks.md](./governed-tasks.md) | 6 (orchestration) |
| [architecture.md](./architecture.md) | All (wiring) |
| [session-recovery.md](./session-recovery.md) | Noise bucket |
