# Architecture

> DietCode is a **governed local mutation runtime**. The cockpit is the control surface; the kernel is the authority.

Canonical checkpoint map: [checkpoint-model.md](checkpoint-model.md).

## Components

```text
┌─────────────────────────────────────────────────────────┐
│  Cockpit (Vite + React)                                 │
│  Chat · CheckpointRail · Drift · Approval · Verify      │
│  Timeline · Diffs · Logs                                │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTP + SSE (:9477)
┌───────────────────────▼─────────────────────────────────┐
│  Cockpit bridge (cockpit/server/bridge.ts)              │
│  Task registry · session store · checkpoint resolver    │
│  Approval proxy · verify gate · event polling           │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON lines + token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel (C++ / ObjC++)                           │
│  MacControlServer · approvals · drift · verify            │
│  WorkspaceSession — sole mutation authority               │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

**Agent Bridge** (`agent-bridge/`) sits beside this stack: agents call bridge workflows → kernel RPC. Hermes uses the bundled plugin → bridge CLI → kernel.

## Kernel

| Artifact | Path |
|----------|------|
| Binary | `build/dietcode-kernel` |
| Entry | `src/kernel/main.mm`, `KernelRuntime.mm` |
| RPC server | `src/platform/macos/control/MacControlServer.mm` |
| Workspace | `src/kernel/workspace/` |
| Socket | `~/.dietcode/control.sock` |

Headless build excludes `legacy_ui/` editor sources. `safeWorkspacePath` reads from `WorkspaceSession`, not AppKit windows.

```bash
make kernel
DIETCODE_REPO_ROOT=$(pwd) ./build/dietcode-kernel --ensure-socket
```

## Cockpit bridge

| Module | Role |
|--------|------|
| `bridge.ts` | HTTP API, RPC client, SSE |
| `taskRunner.ts` | Spawns governed/smoke task scripts |
| `taskRegistry.ts` | In-memory tasks + persistence hook |
| `sessionStore.ts` | Event ring, diffs, active tasks JSON |
| `checkpoints.ts` | Six-gate snapshot builder |
| `verifyGate.ts` | Mutation → verification_required → completed |
| `workspaceDrift.ts` | Drift status cache |
| `verifyCommandResolver.ts` | `verify.sh` → `make test` → `npm test` |

### Governed task runners

| Mode | Script |
|------|--------|
| `supervised` / `trusted` | `scripts/cockpit_governed_task.py` (Hermes) |
| `smoke` | `scripts/cockpit_smoke_task.py` (deterministic, no Hermes) |

Vertical slice orchestrator: `scripts/cockpit_vertical_slice.py` (`make cockpit-smoke`).

## RPC wire format

Requests are single-line JSON:

```json
{
  "id": "uuid",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": { },
  "token": "<session.token>"
}
```

Responses: `{ "id", "ok", "result" }` or `{ "id", "ok": false, "error": { "string_code", "message", ... } }`.

## Session and recovery

Bridge persists under `DIETCODE_SESSION_DIR` (default `~/.dietcode/session/`):

- `active_tasks.json`
- `recent_events.ndjson`
- `recent_diffs.json`
- `pending_approvals.json`

On bridge restart, `bootstrapSessionRecovery` reloads tasks and syncs kernel approvals. See [session-recovery.md](session-recovery.md).

## Autonomy and permissions

Default autonomy level: **3 (supervised)**. Destructive RPCs (`patch.apply` with `confirm`, `workspace.openFolder`, etc.) queue `approvalRequired` until cockpit resolves.

Permission tiers: Read · Edit · Execute · Destructive. Method catalog: `src/platform/macos/control/services/MacControlMethodCatalog.mm`.

## What is not in this stack

| Item | Role |
|------|------|
| Benchmark harness | Parallel reliability track — not a checkpoint |
| BroccoliQ journal | Offline evaluation — noise bucket |
| Legacy AppKit editor | Optional; not cockpit |
| Cloud / remote kernel | Not supported |

## Related

- [kernel-rpc.md](kernel-rpc.md) — method reference
- [governed-tasks.md](governed-tasks.md) — HTTP task API
- [agent-bridge.md](agent-bridge.md) — agent client layer
