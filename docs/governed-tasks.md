# Governed task execution

Cockpit chat submits **tasks**, not raw chat messages. Each task is a bounded Hermes run where every workspace mutation flows through the kernel.

## Architecture

```text
Human
  ↓
Cockpit (ChatPanel → POST /api/tasks)
  ↓
Bridge task registry + governed runner
  ↓
Hermes (dietcode toolset) + dietcode_ide tool
  ↓
Agent Bridge CLI → Kernel RPC
  ↓
Approval registry (supervised destructive ops)
  ↓
Workspace mutation
  ↓
SSE events → Task timeline + Approvals + Diffs
```

**Rule:** Hermes never mutates files directly. Hermes calls `dietcode_ide`, which calls the Agent Bridge, which calls kernel RPC.

## Submit a task

```http
POST /api/tasks
Content-Type: application/json

{
  "message": "Fix the failing test",
  "workspace": "/path/to/project",
  "mode": "supervised"
}
```

Response `202`:

```json
{
  "task": {
    "taskId": "task_1",
    "message": "Fix the failing test",
    "workspace": "/path/to/project",
    "mode": "supervised",
    "status": "pending"
  },
  "mode": "governed_task_accepted"
}
```

| Mode | Behavior |
|------|----------|
| `supervised` | Bridge blocks on `approvalRequired` until cockpit resolves; Hermes hooks enforced |
| `trusted` | Hermes `--yolo` for non-IDE tools; patches still go through kernel RPC |

## Task registry (bridge)

| Endpoint | Purpose |
|----------|---------|
| `GET /api/tasks` | List recent tasks |
| `GET /api/tasks/:taskId` | Task status |
| `POST /api/tasks` | Start governed Hermes run |

Runner: `scripts/cockpit_governed_task.py` (spawned by bridge).

Environment set per task:

- `DIETCODE_TASK_ID` — attached to kernel approvals and RPC params
- `DIETCODE_TASK_EVENT_LOG` — JSONL tool/approval events tailed by runner
- `DIETCODE_SUPERVISED=1` — Agent Bridge waits for approval resolution on patches

## Event surface

Canonical task events (SSE `/events`):

| Type | Source |
|------|--------|
| `task.started` | Governed runner |
| `agent.message` | Hermes stdout stream |
| `tool.call.started` | `dietcode_ide` bridge invoke |
| `tool.call.completed` | `dietcode_ide` bridge result |
| `approval.required` | Kernel + bridge tool layer |
| `approval.resolved` | Kernel |
| `file.diff` | Successful patch receipt |
| `verify.completed` | Kernel verify events |
| `task.completed` | Runner |
| `task.failed` | Runner |

Task timeline in cockpit filters to these types and optionally scopes to `activeTaskId`.

## Approval pause / resume

Supervised patch flow:

1. Agent Bridge `patch.apply` returns `approvalRequired: true`
2. `awaitApproval.ts` polls `approval.get` until cockpit resolves
3. Cockpit `ApprovalPanel` → `POST /api/approvals/:id/resolve`
4. Kernel executes on approve; bridge receives `executionResult`
5. Hermes tool call completes; task continues

## Local development

```bash
./build/dietcode-kernel --ensure-socket
cd cockpit && npm install && npm run dev
```

Open cockpit, submit a task from Chat, watch Task Timeline and Approvals.

Session state is ephemeral with bounded recovery snapshots — not a full run ledger. See [session-recovery.md](./session-recovery.md).

See also: [approval-lifecycle.md](./approval-lifecycle.md), [kernel-cockpit-architecture.md](./kernel-cockpit-architecture.md).
