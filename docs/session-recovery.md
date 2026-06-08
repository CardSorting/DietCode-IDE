# Session recovery (ephemeral state)

DietCode is a **live control surface**, not an observability warehouse. Session state is in-memory first, with bounded on-disk snapshots for cockpit reload and bridge restart recovery.

## What we keep vs. what we drop

| Keep (bounded) | Drop |
|----------------|------|
| Live steering | Infinite event archives |
| Pending approvals | Per-token forensic logs |
| Recent diffs (last ~20) | Full tool-call history forever |
| Active task summaries | Splunk-for-agents sludge |
| Rolling timeline (~300 events) | |

## Layout

```text
~/.dietcode/session/
├─ active_tasks.json      # task registry snapshot (max ~40)
├─ pending_approvals.json # kernel pending approval cache
├─ recent_events.ndjson   # rolling window only (max ~300 lines)
└─ recent_diffs.json      # lightweight diff previews (max ~20)
```

Optional explicit export (user-initiated only):

```text
~/.dietcode/exports/session_export_<timestamp>.json
```

## Recovery behavior

### Cockpit reload

`GET /api/session` restores:

- recent timeline events
- active / disconnected tasks
- pending approval snapshot
- recent diff previews
- suggested `activeTaskId`

Cockpit hydrates Task Timeline and Diffs from this endpoint, then continues on live SSE.

### Bridge restart

On startup the bridge:

1. Loads `~/.dietcode/session/*`
2. Restores task registry
3. Marks previously `running` tasks as `disconnected` (subprocess cannot reconnect)
4. Syncs `pending_approvals.json` from kernel `approval.list`
5. Resumes kernel event polling from last known sequence

Kernel retains authoritative state for approvals and its own 500-event ring buffer.

## API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/session` | Ephemeral session snapshot for UI recovery |
| `POST /api/session/export` | Optional explicit export to `~/.dietcode/exports/` |

## Environment tuning

| Variable | Default | Meaning |
|----------|---------|---------|
| `DIETCODE_SESSION_DIR` | `~/.dietcode/session` | Snapshot directory |
| `DIETCODE_SESSION_MAX_EVENTS` | `300` | Rolling event cap |
| `DIETCODE_SESSION_MAX_DIFFS` | `20` | Recent diff cap |
| `DIETCODE_SESSION_MAX_TASKS` | `40` | Task registry cap |

## Philosophy

```text
live steering + bounded mutation + approvals + recent context + recoverability
```

Not a permanent black-box recorder. When you need a durable artifact, export explicitly or rely on kernel patch receipts in the workspace journal — not cockpit session sludge.

## Failure semantics

DietCode never pretends an agent is still safely operating when the control loop is broken.

### Task statuses

| Status | Meaning |
|--------|---------|
| `queued` | Accepted, not yet spawned |
| `running` | Hermes subprocess active |
| `awaiting_approval` | Blocked on cockpit/kernel approval |
| `disconnected` | Bridge restarted or control loop lost mid-run |
| `failed` | Agent process died or exited with error |
| `completed` | Finished successfully |
| `cancelled` | User cancelled from cockpit |

### Cockpit banners

| Banner | Trigger |
|--------|---------|
| Kernel offline | Control socket unreachable |
| Bridge reconnected | Session restored after bridge restart |
| Task disconnected | Orphaned task after mid-run interruption |
| Approval expired | Kernel approvals past TTL |
| Workspace changed externally | `workspace.revision.externalChangeDetected` or path drift |
| Live stream stale | SSE silent >20s while kernel online |

### Recovery actions

| Action | Endpoint |
|--------|----------|
| Reconnect | `POST /api/reconnect` |
| Retry task | `POST /api/tasks/:id/retry` |
| Cancel task | `POST /api/tasks/:id/cancel` |
| Refresh approvals | `POST /api/approvals/refresh` |
| Export snapshot | `POST /api/session/export` |
| Clear session | `POST /api/session/clear` |

Health probe: `GET /api/health`

See also: [governed-tasks.md](./governed-tasks.md), [approval-lifecycle.md](./approval-lifecycle.md).
