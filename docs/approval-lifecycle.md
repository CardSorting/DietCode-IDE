# Approval lifecycle

**Checkpoint 3 · Approval** — *Is this mutation allowed?*

Canonical loop: [checkpoint-model.md](./checkpoint-model.md).

DietCode kernel supervises destructive workspace mutations through a pending-approval registry. Agents never mutate the workspace without kernel authority.

## Flow

```text
agent proposes mutation (destructive RPC)
    ↓
kernel queues PendingApproval
    ↓
kernel emits approval.required (events)
    ↓
operator or harness resolves via approval.resolve RPC
    ↓
kernel executes (approve) or cancels (reject)
    ↓
kernel emits approval.resolved
```

## Autonomy levels

| Level | Behavior |
|-------|----------|
| 1 | Auto-allow destructive mutations (testing / trusted) |
| 2 | Heuristic safe-list; kernel queues unsafe destructive ops |
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
  "caller": "agent",
  "status": "pending",
  "preview": { "path": "src/foo.ts", "patch": "…" },
  "expiresAt": "…"
}
```

## Kernel RPCs

| RPC | Purpose |
|-----|---------|
| `approval.list` | List pending / resolved approvals |
| `approval.get` | Fetch one approval by id |
| `approval.resolve` | Approve or reject; executes queued mutation on approve |

### Resolve example

```bash
python3 scripts/dietcode_agent_client.py rpc approval.resolve \
  --params '{"approvalId":"appr_1","decision":"approved","resolvedBy":"operator","reason":"looks good"}'
```

Harness auto-approve: `scripts/dietcode_coherence.py` (`resolve_kernel_approval`).

## Timeouts

Pending approvals expire after **30 minutes**. Expired approvals return `approval_expired` — not an implicit approve.

## Coherence interaction

Approval runs after coherence and drift gates pass. A patch blocked by `coherence_mismatch` never reaches the approval queue.

## Related

- [kernel-rpc.md](./kernel-rpc.md)
- [agent-ergonomics.md](./agent-ergonomics.md)
- [error-codes.md](./error-codes.md)
