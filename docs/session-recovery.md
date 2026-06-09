# Session recovery (ephemeral state)

**Not a checkpoint** — control-plane hygiene for kernel reload. See the noise bucket in [checkpoint-model.md](./checkpoint-model.md).

DietCode is a **live control surface**, not an observability warehouse. Session state is bounded on-disk snapshots for kernel recovery and harness continuity.

## What we keep vs. what we drop

| Keep (bounded) | Drop |
|----------------|------|
| Pending approvals (kernel authoritative) | Infinite event archives |
| Recent diffs (recovery store) | Per-token forensic logs |
| Active task summaries | Full tool-call history forever |
| Rolling event ring (~500 kernel events) | Splunk-for-agents sludge |

## Layout

```text
~/.dietcode/session/          # optional DIETCODE_SESSION_DIR
├─ active_tasks.json          # task registry snapshot (harness)
├─ pending_approvals.json     # kernel pending approval cache
├─ recent_events.ndjson       # rolling window
└─ recent_diffs.json          # lightweight diff previews
```

Kernel recovery store: `src/platform/macos/control/services/MacControlRecoveryStore.mm`

## Recovery behavior

### Kernel restart

On restart the kernel:

1. Reloads recovery store state
2. Retains authoritative pending approvals
3. Resumes event ring from last known sequence

Harnesses should call `make restart-agent-server-fast` and `dietcode_agent_client.py --wait-ready` before live tests.

### Agent reconnect

Agents reconnect via the same socket path and session token. Stale tokens after kernel restart require reading the new `~/.dietcode/session.token`.

## Recovery RPCs

| RPC | Purpose |
|-----|---------|
| `recovery.scan` | List recoverable artifacts |
| `recovery.list` | Enumerate recovery entries |
| `recovery.schemaInfo` | Schema version for recovery payloads |

## Related

- [approval-lifecycle.md](./approval-lifecycle.md) — pending approval semantics
- [coherence-tokens.md](./coherence-tokens.md) — coherence recovery loop
- [archive-note.md](./archive-note.md) — removed bridge session persistence
