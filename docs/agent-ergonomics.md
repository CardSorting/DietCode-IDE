# Agent ergonomics (checkpoint-aware)

> **DietCode gives agents bounded autonomy through visible checkpoints.**

Agents should treat the kernel as a **state machine with six gates**, not a fire-and-forget file API. This doc is the agent-facing contract; the full map is [checkpoint-model.md](./checkpoint-model.md).

## Checkpoint query API (cockpit bridge)

Humans use the cockpit; agents and tooling can poll structured checkpoint state:

| Endpoint | Returns |
|----------|---------|
| `GET /api/checkpoints` | Active task checkpoint snapshot |
| `GET /api/tasks/:id/checkpoints` | Per-task checkpoint snapshot |

Response shape:

```json
{
  "snapshot": {
    "taskId": "task_3",
    "taskStatus": "verification_required",
    "verificationState": "verification_required",
    "canComplete": false,
    "blockingCheckpoint": 5,
    "suggestedVerifyCommand": "make test",
    "checkpoints": [
      { "id": 1, "key": "context", "name": "Context", "status": "passed", "question": "..." },
      { "id": 2, "key": "drift", "name": "Drift", "status": "passed" },
      { "id": 5, "key": "verification", "name": "Verification", "status": "active", "blocking": true }
    ]
  }
}
```

**Status values:** `pending`, `active`, `passed`, `failed`, `blocked`, `waived`, `skipped`.

Industry mirror: CI pipeline stages (GitHub Actions, Buildkite) — one stage, one question, explicit pass/fail.

## Agent bridge behavior

### Automatic `taskId`

When `DIETCODE_TASK_ID` is set (governed tasks), the bridge injects `taskId` into every kernel RPC so events bind to the correct task.

### Blocking responses

| Kernel result | Bridge action | Checkpoint |
|---------------|---------------|------------|
| `approvalRequired: true` | Poll `approval.get` until resolved | 3 |
| `workspaceDriftRequired: true` | Poll `workspace.status` until drift clears | 2 |
| `patch.apply` + receipt | Continue | 4 |
| `verify.run` failure | Surface `verification_failed` to cockpit | 5 |

### Error codes (recovery hints)

| Code | `nextRecommendedCommand` | Meaning |
|------|--------------------------|---------|
| `workspace_drift` | `workspace.status` | Refresh context before retry |
| `stale_content` | `patch.validate` | Re-read before patch |
| `coherence_mismatch` | `file.read` | Task-scoped stale write — re-read `changedPaths`, regenerate patch, retry once |
| `approval_required` | `approval.get` | Wait for human |
| `approval_rejected` | `workspace.revision` | Revise plan |

## Verify command resolution

The bridge resolves verify commands in order (mirrors `dietcode_verification_authority.py`):

1. Explicit `command` in `POST /api/tasks/:id/run-verify`
2. Task `lastVerifyCommand`
3. Kernel `workspace.status.lastVerifiedCommand`
4. `./verify.sh` in workspace root
5. `make test` if Makefile has `test` target
6. `npm test` / `npm run verify` from `package.json`
7. `DIETCODE_AGENT_CHAT_FALLBACK_VERIFY` env

Agents should prefer workspace-native `verify.sh` — same convention as agent chat sidebar.

## Recommended agent loop

```text
1. file.read / patch.validate     → anchor context (checkpoint 1)
2. workspace.status               → check drift (checkpoint 2)
3. patch.apply                    → mutation (checkpoint 4)
4. Poll GET /api/tasks/:id/checkpoints until blockingCheckpoint is null or 5 active
5. Do not claim "done" until snapshot.canComplete === true
```

## Coherence tokens (governed tasks)

When `taskId` is set on reads (`file.read`, `file.readBatch`, `workspace.status`, …), the kernel issues a **coherence token** — proof of what the agent observed. Mutations must carry `coherenceTokenId` + `expectedWorkspaceRevision` or the kernel returns `coherence_mismatch` (before drift).

**Recovery loop** (bridge + Python harness):

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

## Hermes `dietcode_ide` events

Governed tasks emit NDJSON to `DIETCODE_TASK_EVENT_LOG`:

| Event | Checkpoint |
|-------|------------|
| `workspace.drift.detected` | 2 |
| `context.stale` | — (coherence) |
| `context.refreshed` | — (coherence) |
| `coherence.retry` | — (coherence) |
| `coherence.operator_required` | — (coherence) |
| `approval.required` | 3 |
| `file.diff` | 4 |
| `tool.call.completed` | — (observability) |

## What agents should not do

- Claim task completion when `verificationState` is `verification_required`
- Bypass drift with mutation retries (use `workspace.refreshAnchor` or cockpit **Continue anyway**)
- Treat log stream or timeline as gates — they are audit trails only
