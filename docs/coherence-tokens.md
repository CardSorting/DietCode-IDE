# Coherence tokens (v0.1)

**Low-level enforcement primitive** beneath checkpoint 2 (Drift). Drift is broad — *something changed*. Coherence mismatch is precise — *this task is mutating from stale observed state*.

> DietCode uses coherence tokens so agents can only mutate the workspace they actually observed.

## What it answers

1. Did the workspace change since this task read?
2. Did any file this task depends on change?
3. Is verification older than the latest mutation context? (`verifyRevision` on token must match kernel)

No graph. No ledger. Caps: **40 tasks**, **100 anchors/task**, **30 min TTL**. Hash only files actually read.

## Counters

| Counter | When it increments |
|---------|-------------------|
| `workspaceRevision` | Kernel mutation; patch apply/batch |
| `verifyRevision` | Successful `verify.run` |

## Read response

Issued on `file.read`, `file.readBatch`, `file.readRange`, `file.readAround`, `file.stat`, and `workspace.status` when `taskId` is set:

Batch reads return one task-scoped token at the top level:

```json
{
  "results": {
    "src/a.ts": { "ok": true, "text": "..." },
    "src/b.ts": { "ok": true, "text": "..." }
  },
  "coherence": {
    "tokenId": "coh_123",
    "workspaceRevision": 41,
    "verifyRevision": 7,
    "anchors": {
      "src/a.ts": "fnv1a:...",
      "src/b.ts": "fnv1a:..."
    }
  }
}
```

Single-file reads embed `coherence` beside `text`:

```json
{
  "text": "...",
  "coherence": {
    "tokenId": "coh_123",
    "workspaceRevision": 41,
    "verifyRevision": 7,
    "anchors": {
      "src/foo.ts": "fnv1a:abc123deadbeef00"
    }
  }
}
```

Anchors use the kernel content hash (`fnv1a:<hex>`).

## Mutation params

Required when `taskId` is set on `patch.apply` / `patch.applyBatch`:

```json
{
  "taskId": "task_12",
  "coherenceTokenId": "coh_123",
  "expectedWorkspaceRevision": 41
}
```

## Stale response

```json
{
  "error": {
    "string_code": "coherence_mismatch",
    "reason": "anchored_file_changed",
    "changedPaths": ["src/foo.ts"],
    "currentWorkspaceRevision": 42,
    "requiredAction": "refresh_context"
  }
}
```

**Recovery:** re-read affected paths with the same `taskId`, then retry the mutation with the new token.

## Agent recovery (bridge)

When `safePatchFile` is called with `taskId` and `buildPatchFromContent`, a single automatic retry runs on `coherence_mismatch`:

```text
coherence_mismatch
  → emit context.stale
  → re-read changedPaths (context.refreshed)
  → buildPatchFromContent(current text)
  → emit coherence.retry
  → retry patch.apply once with fresh token
  → still stale? emit coherence.operator_required and stop
```

Without `buildPatchFromContent`, the bridge returns `CoherenceStaleRecovery` for the caller to handle.

```typescript
await safePatchFile(transport, path, diff, {
  taskId: 'task_12',
  buildPatchFromContent: ({ content }) => rebuildUnifiedDiff(path, content, target),
  onCoherenceEvent: (event) => logNdjson(event),
});
```

Smoke: `make coherence-recovery-smoke`

## Release gate

Tag when green:

```bash
make coherence-core-v0.1
```

| Step | Proves |
|------|--------|
| `test-coherence-tokens` | Kernel issuance + enforcement (incl. `file.readBatch`) |
| `coherence-recovery-smoke-fast` | Python recovery vertical |

Tag: **coherence-core-v0.1**

## Agent loop

```text
read file (taskId) → coherence token
prepare patch → include token + expectedWorkspaceRevision
patch.apply → kernel validates
mismatch → refresh context and retry
valid → approval → mutation → verify
```

## Related

- [workspace-drift.md](./workspace-drift.md) — user-facing drift checkpoint
- [kernel-rpc.md](./kernel-rpc.md) — RPC reference
- [error-codes.md](./error-codes.md) — `coherence_mismatch`
