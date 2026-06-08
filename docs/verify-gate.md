# Verify gate semantics

**Checkpoints 5–6 · Verification & completion** — *Did the result pass? Can this task be called done?*

Canonical loop: [checkpoint-model.md](./checkpoint-model.md).

A governed task is **not done** when the agent stops. It is done when the workspace is **verified** or **explicitly waived**.

## Task validity states

| `verificationState` | Meaning |
|---------------------|---------|
| `none` | No mutations — agent completion is sufficient |
| `verification_required` | Workspace mutated; verify pending |
| `verified` | Verify passed — task may complete |
| `verification_failed` | Verify ran and failed |
| `verification_waived` | Operator waived verify — task complete |

Task `status` mirrors the gate: `verification_required`, `verification_failed`, then `completed` only after `verified` or `verification_waived`.

## Event loop

```text
patch.apply success
    → workspace.mutated (kernel)
    → task.verification_required (bridge)

agent process exits
    → if mutations: status = verification_required (not completed)

verify.run passed
    → verify.completed (kernel)
    → task.verified + status = completed (bridge)

verify.run failed
    → verify.failed (kernel)
    → status = verification_failed (bridge)
```

## Kernel events

| Event | When |
|-------|------|
| `workspace.mutated` | After successful `patch.apply` / `patch.applyBatch` |
| `verify.completed` | `verify.run` exit 0 / `passed: true` |
| `verify.failed` | `verify.run` non-zero / `passed: false` |

Pass `taskId` in RPC params to associate events with a governed task.

## Cockpit actions

| Action | Endpoint |
|--------|----------|
| Run verify | `POST /api/tasks/:id/run-verify` |
| Retry task | `POST /api/tasks/:id/retry` |
| Show failing output | Panel toggles `lastVerifyOutput` on task |
| Waive verification | `POST /api/tasks/:id/waive-verification` |
| Cancel task | `POST /api/tasks/:id/cancel` |

`run-verify` uses the request body `command` if provided, otherwise the kernel's `lastVerifiedCommand` from `workspace.status`.

## Core rule

> A task is not “done” just because the agent stopped. It is done when the workspace is either verified or explicitly waived.

This closes the control plane loop after: read anchors → drift block → approval gate → mutation → **verify gate**.
