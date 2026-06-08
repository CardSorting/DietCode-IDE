# Governed tasks

**Checkpoint 6 · Completion** orchestrates checkpoints 1–5. See [checkpoint-model.md](checkpoint-model.md).

Cockpit chat submits **tasks**, not unbounded chat. Each task is a bounded agent run where every workspace mutation flows through the kernel approval and verify gates.

## Flow

```text
Human → Cockpit ChatPanel
    → POST /api/tasks (bridge)
    → task runner spawns Python script
    → agent reads files (checkpoint 1)
    → patch.apply → approval if supervised (checkpoints 2–3)
    → workspace.mutated (checkpoint 4)
    → verification_required (checkpoint 5)
    → run-verify → completed + verified (checkpoint 6)
```

**Rule:** Agents never write files outside kernel RPC. Hermes uses `dietcode_ide` → Agent Bridge → kernel.

## Submit a task

```http
POST /api/tasks
Content-Type: application/json

{
  "message": "Change probe.py VALUE from 1 to 2",
  "workspace": "/path/to/project",
  "mode": "supervised"
}
```

Response `202`:

```json
{
  "task": {
    "taskId": "task_1",
    "message": "...",
    "workspace": "/path/to/project",
    "mode": "supervised",
    "status": "queued",
    "verificationState": "none"
  },
  "mode": "governed_task_accepted"
}
```

### Modes

| Mode | Runner | Behavior |
|------|--------|----------|
| `supervised` | `cockpit_governed_task.py` | Hermes + bridge approval wait on patches |
| `trusted` | `cockpit_governed_task.py` | Hermes with relaxed tool policy; patches still kernel-gated |
| `smoke` | `cockpit_smoke_task.py` | Deterministic RPC loop — no Hermes (`make cockpit-smoke`) |

## Task statuses

| Status | Checkpoint |
|--------|------------|
| `queued` / `running` | 1 Context |
| `awaiting_approval` | 3 Approval |
| `verification_required` | 5 Verification |
| `verification_failed` | 5 Verification (failed) |
| `completed` | 6 — only with `verificationState: verified` or `waived` |
| `failed` / `cancelled` | Terminal |

`verificationState`: `none` · `verification_required` · `verified` · `verification_failed` · `verification_waived`.

## Bridge HTTP API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/tasks` | List tasks |
| `GET /api/tasks/:id` | Task detail |
| `POST /api/tasks` | Start governed run |
| `GET /api/tasks/:id/checkpoints` | Six-gate snapshot |
| `POST /api/tasks/:id/run-verify` | Run verify command |
| `POST /api/tasks/:id/waive-verification` | Operator waive (checkpoint 5) |
| `GET /api/checkpoints` | Active task checkpoints |
| `GET /api/session` | Restored session snapshot |
| `GET /api/health` | Kernel + workspace health |
| `GET /events` | SSE event stream |

Checkpoint query shape: [agent-ergonomics.md](agent-ergonomics.md).

## Verify gate

After mutation, the bridge sets `verification_required`. Cockpit **VerifyGatePanel** runs `verify.run` via `POST /api/tasks/:id/run-verify`.

Command resolution order: request body → task `lastVerifyCommand` → workspace `verify.sh` / `Makefile` `test` / `package.json` `test`.  
See [verify-gate.md](verify-gate.md).

## Events (SSE)

Canonical types for timeline and panels:

- `task.started` · `task.completed` · `task.verification_required` · `task.verified` · `task.verification_failed`
- `approval.required` · `approval.resolved`
- `workspace.mutated` · `file.diff`
- `verify.completed` · `verify.failed`

## Environment (Hermes runs)

| Variable | Role |
|----------|------|
| `DIETCODE_TASK_ID` | Bound to approvals and kernel events |
| `DIETCODE_TASK_EVENT_LOG` | JSONL tool events |
| `DIETCODE_SUPERVISED=1` | Bridge waits for approval on patches |
| `DIETCODE_SESSION_DIR` | Bridge session persistence path |

## Smoke validation

```bash
make cockpit-smoke
```

Uses `mode: smoke` and fixture workspace under `build/cockpit-smoke-ws/`. Proves the full pipeline without Hermes.

## Related

- [approval-lifecycle.md](approval-lifecycle.md) — checkpoint 3
- [verify-gate.md](verify-gate.md) — checkpoints 5–6
- [session-recovery.md](session-recovery.md) — bridge reload
