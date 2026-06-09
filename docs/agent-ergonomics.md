# Agent ergonomics (checkpoint-aware)

> **DietCode gives agents bounded autonomy through visible checkpoints enforced by the kernel.**

Agents should treat the kernel as a **state machine with six gates**, not a fire-and-forget file API. This doc is the agent-facing contract; the full map is [checkpoint-model.md](./checkpoint-model.md).

## Kernel RPC checkpoint queries

Poll kernel state directly via RPC:

| RPC | Returns |
|-----|---------|
| `workspace.status` | Drift snapshot, anchors, verify state |
| `workspace.revision` | Revision IDs for coherence |
| `verify.status` / `verify.last` | Verification gate state |
| `approval.list` | Pending approvals |

Use `taskId` on reads to receive coherence tokens. See [coherence-tokens.md](./coherence-tokens.md).

## Blocking responses

| Kernel result | Agent action | Checkpoint |
|---------------|--------------|------------|
| `approvalRequired: true` | Poll `approval.get` / resolve via `approval.resolve` | 3 |
| `workspaceDriftRequired: true` | `workspace.refreshAnchor` then retry with `contextRefreshId` | 2 |
| `coherence_mismatch` | Re-read `changedPaths` with `taskId`, regenerate patch, retry once | — |
| `patch.apply` + receipt | Continue | 4 |
| `verify.run` failure | Re-run verify or escalate | 5 |

### Error codes (recovery hints)

| Code | `nextRecommendedCommand` | Meaning |
|------|--------------------------|---------|
| `workspace_drift` | `workspace.status` | Refresh context before retry |
| `stale_content` | `patch.validate` | Re-read before patch |
| `coherence_mismatch` | `file.read` | Task-scoped stale write — re-read `changedPaths`, regenerate patch, retry once |
| `approval_required` | `approval.get` | Wait for operator |
| `approval_rejected` | `workspace.revision` | Revise plan |

## Verify command resolution

Harnesses resolve verify commands via `dietcode_verification_authority.py`:

1. Explicit `command` in `verify.run`
2. `./verify.sh` in workspace root
3. `make test` if Makefile has `test` target
4. `npm test` / `npm run verify` from `package.json`

Agents should prefer workspace-native `verify.sh`.

## Recommended agent loop

```text
1. file.read / patch.validate (taskId)  → anchor context + coherence token (checkpoint 1)
2. workspace.status                     → check drift (checkpoint 2)
3. patch.apply (coherenceTokenId)       → mutation (checkpoint 4)
4. verify.run                           → verification (checkpoint 5)
5. Do not claim "done" until verify passes or is waived (checkpoint 6)
```

## Coherence tokens (governed tasks)

When `taskId` is set on reads (`file.read`, `file.readBatch`, `workspace.status`, …), the kernel issues a **coherence token** — proof of what the agent observed. Mutations must carry `coherenceTokenId` + `expectedWorkspaceRevision` or the kernel returns `coherence_mismatch` (before drift).

**Recovery loop** (`scripts/dietcode_coherence.py`):

```text
patch.apply → coherence_mismatch
  → emit context.stale
  → file.read changedPaths with taskId
  → emit context.refreshed
  → regenerate patch from live content
  → emit coherence.retry (one attempt)
  → success OR coherence.operator_required
```

| Event | Meaning |
|-------|---------|
| `context.stale` | Observed anchors no longer match disk |
| `context.refreshed` | Re-read issued new coherence token |
| `coherence.retry` | Automatic retry with fresh token |
| `coherence.operator_required` | Second mismatch — stop and escalate |

See [coherence-tokens.md](./coherence-tokens.md) for kernel caps and anchor format.

## NDJSON task events

Harnesses may emit NDJSON to `DIETCODE_TASK_EVENT_LOG`:

| Event | Checkpoint |
|-------|------------|
| `workspace.drift.detected` | 2 |
| `context.stale` | — (coherence) |
| `context.refreshed` | — (coherence) |
| `coherence.retry` | — (coherence) |
| `coherence.operator_required` | — (coherence) |
| `approval.required` | 3 |
| `mutation.applied` | 4 |
| `verify.completed` | 5 |

## What agents should not do

- Claim task completion when verify has not passed
- Bypass drift with blind mutation retries (use `workspace.refreshAnchor`)
- Skip coherence tokens when `taskId` is set on governed paths
- Treat log streams as gates — they are audit trails only
