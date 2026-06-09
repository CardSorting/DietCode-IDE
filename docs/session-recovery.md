# Session recovery

**Not a checkpoint** — control-plane hygiene for kernel reload. See noise bucket in [checkpoint-model.md](checkpoint-model.md).

DietCode is a **live control surface**, not an observability warehouse. Session state is bounded on-disk snapshots for kernel recovery and harness continuity.

---

## Keep vs drop

| Keep (bounded) | Drop |
|----------------|------|
| Pending approvals (kernel authoritative) | Infinite event archives |
| Recent diffs (recovery store) | Per-token forensic logs |
| Active task summaries (harness) | Full tool-call history forever |
| Rolling event ring (~500 events) | Long-term agent chat logs |

---

## Layout

```text
~/.dietcode/session/          # optional DIETCODE_SESSION_DIR
├─ active_tasks.json          # harness task registry snapshot
├─ pending_approvals.json     # kernel pending approval cache
├─ recent_events.ndjson       # rolling window
└─ recent_diffs.json          # lightweight diff previews
```

Kernel recovery store: `src/platform/macos/control/services/MacControlRecoveryStore.mm`

---

## Kernel restart

On restart the kernel:

1. Reloads recovery store state
2. Retains authoritative pending approvals
3. Resumes event ring from last known sequence

Harnesses should run before live tests:

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
```

---

## Agent reconnect

Agents reconnect via the same socket path and session token. After kernel restart, read fresh `~/.dietcode/session.token` if auth fails.

---

## Recovery RPCs

| RPC | Purpose |
|-----|---------|
| `recovery.scan` | List recoverable artifacts |
| `recovery.list` | Enumerate recovery entries |
| `recovery.schemaInfo` | Schema version for payloads |

Internal namespace `recovery.*` — not agent-safe; harness use only.

---

## Related

- [approval-lifecycle.md](approval-lifecycle.md)
- [coherence-tokens.md](coherence-tokens.md)
- [archive-note.md](archive-note.md)
