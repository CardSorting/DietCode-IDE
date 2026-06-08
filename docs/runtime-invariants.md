# Runtime Invariants (Deterministic Agent Kernel)

Frozen invariants for local-first agent execution. Grep inventory:

```bash
rg 'INVARIANT:|stale_content|beforeContentHash|sortOrder' src/ scripts/ docs/
```

---

## State synchronization

| Surface | Invariant | Verify |
|---------|-----------|--------|
| File text read | Editor buffer preferred; disk fallback via `TextForSearchAtPath` | `readSource` on `file.stat` / `patch.validate` |
| Content identity | `StableHashForString` (16 hex, FNV-1a) | `contentHash`, `beforeContentHash` |
| Stale writes | `expectBeforeHash` on `patch.apply` rejects drift | `stale_content` error |
| Mutation proof | `mutationReceipt` on successful `patch.apply` | `validate_mutation_receipt()` |

Agents must treat `beforeContentHash` from `patch.validate` as the precondition for `patch.apply`.

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json patch.validate --params-file patch.json
# apply with expectBeforeHash from validation.beforeContentHash
```

---

## Grep determinism

| Invariant | Value |
|-----------|-------|
| Match mode | `literal_substring` only |
| Traversal order | Sorted absolute paths before scan |
| Result order | `sortOrder: path_line_column` |
| Skip accounting | `filesSkippedOversize`, `filesSkippedExcluded`, `filesSkippedUnreadable`, `filesSkippedBinary` |
| Timing | `scanDurationMs` (server-measured) |

Two identical queries with identical workspace state must return identical `(path, line, column)` tuples.

```bash
make test-runtime-determinism
```

---

## Patch mutation safety

| Stage | Contract |
|-------|----------|
| `patch.validate` | Returns `beforeContentHash`, `patchFingerprint`, `readSource` |
| `patch.apply` | Checks `expectBeforeHash` **before** re-validation; emits `mutationReceipt` on success |
| Rollback | `restorePatchRecords` verifies `beforeHash` / `postHash` |

Error `stale_content` (4004): content changed between validate and apply. Recovery: re-run `patch.validate`.

---

## RPC envelope rules

- Exactly one terminal envelope per request (`id`, `ok`, `result` | `error`)
- Errors include `string_code`, `request_id`, `category`, `retryable`, `recovery_hint`
- Success payloads validated by frozen key sets in `scripts/agent_contracts.py`

---

## Verification ladder

```bash
make test-runtime-determinism
make test-grep-diff-tooling
make verify-agent-runtime
```

---

## Workspace revision (pass 3)

| RPC | Purpose |
|-----|---------|
| `workspace.revision` | Monotonic `revisionId`, `changedFiles`, `lastMutationReceipt`, `externalChangeDetected` |
| `workspace.snapshot` | Point-in-time `fileHashes`; compare with `sinceRevision` for drift |
| `operation.status` | Lookup completed mutation by `idempotencyKey` (safe retry after timeout) |

Mutating commands return `revisionBefore` / `revisionAfter`. Batch apply returns `batchMutationReceipt` with per-file receipts and `rollbackProof`.

```bash
make test-transaction-kernel
```

---

## Symlink policy (frozen)

| Policy | Value |
|--------|-------|
| Traversal | `skip_never_follow` — symlinks are counted in `filesSkippedSymlink`, never followed |
| Patch targets | `PathIsInsideWorkspace` rejects symlinks escaping workspace root |
| Accounting | `symlinkPolicy: skip_never_follow` on all search surfaces |

---

## Search parity

`search.text` and `search.todo` share the same accounting model as `workspace.grep` (`SEARCH_ACCOUNTING_KEYS` in `agent_contracts.py`).

---

## Intentionally not added

- Workspace-wide CRDT sync
- Semantic merge or fuzzy patch anchoring
- Probabilistic conflict resolution
- Hidden buffer coalescing

State divergence must be **visible** via hashes, receipts, and stable error codes.

---

## Related docs

- [Agent Tooling](agent-tooling.md)
- [Runtime Contracts](runtime-contracts.md)
- [Error Codes](error-codes.md)
