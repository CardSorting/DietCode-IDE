# Approval lifecycle

**Checkpoint 3 · Approval** — *Is this mutation allowed?*

Canonical loop: [checkpoint-model.md](./checkpoint-model.md).

DietCode kernel supervises destructive workspace mutations through a pending-approval registry. The cockpit is the human control plane; agents never mutate the workspace without kernel authority.

## Flow

```text
agent proposes mutation (destructive RPC)
    ↓
kernel queues PendingApproval
    ↓
kernel emits approval.required (SSE / events.recent)
    ↓
cockpit ApprovalPanel renders card + diff preview
    ↓
user approves or rejects
    ↓
bridge POST /api/approvals/:id/resolve → approval.resolve RPC
    ↓
kernel executes (approve) or cancels (reject)
    ↓
kernel emits approval.resolved
```

## Autonomy levels

| Level | Behavior |
|-------|----------|
| 1 | Auto-allow destructive mutations (testing / trusted) |
| 2 | Heuristic safe-list in legacy UI; kernel/headless queues unsafe destructive ops |
| 3 | Supervised — destructive mutations require explicit approval (kernel default) |

`dietcode-kernel` starts with autonomy **3**.

## PendingApproval shape

```json
{
  "approvalId": "appr_1",
  "taskId": "task_…",
  "actionType": "patch",
  "method": "patch.apply",
  "reason": "Destructive mutation requires explicit approval.",
  "caller": "hermes",
  "status": "pending",
  "preview": { "path": "src/foo.ts", "patch": "…" },
  "createdAt": "2026-06-08T12:00:00Z"
}
```

Status values: `pending`, `approved`, `rejected`, `expired`, `failed`.

Pending approvals expire after 30 minutes.

## RPC methods

### `approval.list`

```json
{ "status": "pending", "limit": 50 }
```

Returns `{ "approvals": […], "count": N, "mode": "approval_list" }`.

### `approval.get`

```json
{ "approvalId": "appr_1" }
```

### `approval.resolve`

```json
{
  "approvalId": "appr_1",
  "decision": "approved",
  "reason": "User approved from cockpit",
  "resolvedBy": "cockpit"
}
```

On approve, the kernel executes the queued RPC and includes `executionResult` in the resolution payload. On reject, the mutation is discarded.

### Agent retry with `approvalId`

After cockpit approval, an agent may re-issue the original RPC with the same params plus `"approvalId": "appr_1"`. The kernel validates the approval hash before executing.

If the cockpit already executed the mutation via `approval.resolve`, retry returns `approval_invalid` (already executed).

## Queued destructive response

When a destructive RPC is queued:

```json
{
  "approvalRequired": true,
  "approval": { "approvalId": "appr_1", "status": "pending", … },
  "mode": "approval_pending"
}
```

## Bridge HTTP API

| Method | Path | Maps to |
|--------|------|---------|
| GET | `/api/approvals?status=pending` | `approval.list` |
| GET | `/api/approvals/:id` | `approval.get` |
| POST | `/api/approvals/:id/resolve` | `approval.resolve` |

Body for resolve:

```json
{
  "decision": "approved",
  "reason": "User approved from cockpit",
  "resolvedBy": "cockpit"
}
```

## Events

| Type | When |
|------|------|
| `approval.required` | Pending approval created |
| `approval.resolved` | User decision recorded (includes resolution + approval snapshot) |

Subscribe via cockpit SSE (`/events`) or kernel `events.recent` / `event.subscribe`.

## Cockpit

`ApprovalPanel` polls `/api/approvals` and refreshes on `approval.required` / `approval.resolved` SSE events. It shows pending cards with diff/command preview, approve/reject actions, and resolved history.
