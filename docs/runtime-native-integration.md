# Pass VIII — Native Runtime Integration

Makes the BroccoliQ-backed journal feel like a **native runtime primitive**, not an attached memory plugin.

```bash
make test-runtime-native-integration-fast   # iteration
make test-runtime-native-integration        # full rebuild/restart
make verify-agent-runtime-full              # release ladder
```

---

## Audit findings

| Area | Before (Pass VII) | After (Pass VIII) | Risk |
|------|-------------------|-------------------|------|
| Response envelopes | `memory_*` modes, no `complete`/`partial` | `runtime_*` modes + partial-success parity | Low |
| Operation identity | Scattered across tables | Unified `correlation` block on all records | Low |
| History surface | `memory.operation.recent` only | `runtime.timeline`, `workspace.activity` | Low |
| Restart continuity | Implicit replay restore | Explicit `startup` diagnostics on `runtime.diagnostics` | Low |
| Diagnostics | `memoryAuthority: broccoliq_record_only` | `recordAuthority: runtime_journal` | Low |
| Terminology | "memory subsystem" | "runtime journal" (one machine vocabulary) | Low |
| Mutation authority | C++ kernel | **Unchanged** | None |

---

## Unified operation identity

Every major runtime action correlates through:

| Field | Role |
|-------|------|
| `operationId` | Primary operation receipt |
| `revisionId` / `revisionBefore` / `revisionAfter` | Workspace revision chain |
| `idempotencyKey` | Safe retry / replay lookup |
| `workflowId` | Multi-step workflow correlation |
| `receiptHash` | Mutation receipt fingerprint |

Exposed as `correlation` on operations, timeline events, and `runtime.correlate`.

---

## Native runtime surfaces

| RPC | Purpose |
|-----|---------|
| `runtime.diagnostics` | Unified status + startup continuity (replaces addon-style `memory.status` semantics) |
| `runtime.timeline` | Chronological deterministic event stream |
| `runtime.history` | Alias of `runtime.timeline` |
| `workspace.activity` | Timeline filtered to mutations/revisions/replay |
| `runtime.operation.recent` | Recent ops; `compact: true` for summaries |
| `runtime.warnings.recent` | Recent errors/warnings |
| `runtime.correlate` | Join operation + revision + replay + timeline by IDs |

### Timeline filters

- `limit`, `offset` — pagination
- `sinceRevision`, `untilRevision` — revision range
- `errorsOnly` — error events only
- `compact` — omit payloads
- `operationId`, `workflowId` — correlation filters

---

## Restart continuity guarantees

On journal open (`runtime.diagnostics` → `startup`):

| Field | Meaning |
|-------|---------|
| `lastKnownRevision` | Highest persisted revision |
| `replayCacheRestoredCount` | Retained replay entries after restart |
| `replayCacheEvictedCount` | Expired entries removed at startup |
| `runtimeRecoveredFromShutdown` | `true` if prior shutdown was unclean |
| `cleanShutdown` / `recoveredShutdown` | Explicit shutdown classification |

Clean shutdown recorded on journal close; WAL checkpoint on shutdown.

---

## Diagnostics consistency

All runtime surfaces share partial-success fields:

- `complete`, `partial`, `warnings`
- `recoveryHint`, `nextRecommendedCommand`
- `sortOrder: timestamp_desc` on lists

Progress lines in verify ladders use `{"type":"progress","step":"..."}` — same shape as runtime diagnostics events.

---

## `memory.*` vs `runtime.*`

| Namespace | Role |
|-----------|------|
| `runtime.*` | Native agent-facing history, diagnostics, timeline |
| `memory.*` | Durable store queries (backward compatible; enriched to runtime envelope) |

Both read the same journal. Mutation kernel remains authoritative.

---

## Remaining gaps

1. Automatic `verify.run` → timeline event hook (manual `memory.verify.record` today)
2. Cross-process shard coordination (single-process embedded journal)
3. `runtime.timeline` export to NDJSON file (RPC-only today)
4. Configurable replay TTL via RPC

---

## Related

- [BroccoliQ Runtime Memory (Pass VII)](broccoliq-runtime-memory.md)
- [Agent Runtime Audit](agent-runtime-audit.md)
- [Runtime Invariants](runtime-invariants.md)
