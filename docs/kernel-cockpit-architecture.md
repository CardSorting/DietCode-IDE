# DietCode Kernel + Cockpit Architecture

DietCode is a **local agent-control runtime for deterministic workspace mutation**.

It is not an IDE, not a Cursor competitor, and not a VS Code replacement. It is the local control plane for agentic software work.

## Components

```text
DietCode Kernel
= C++ local runtime
= workspace control
= safe file mutation
= diff/patch engine
= verification runner
= event stream
= permission boundary

DietCode Cockpit
= Vite + React + TypeScript
= chat layer
= task timeline
= streamed agent activity
= diffs
= approvals
= logs
= recovery history
```

## Control flow

```text
agent / user
    ↓
cockpit UI
    ↓
local bridge API (HTTP → Unix socket)
    ↓
dietcode-kernel
    ↓
workspace
```

**Hard rule:** The cockpit never edits files directly. The kernel is the only thing allowed to mutate the workspace.

## Kernel

| Path | Role |
|------|------|
| `build/dietcode-kernel` | Headless binary (default build target) |
| `src/kernel/` | Kernel entry, `KernelRuntime`, minimal AppKit delegate |
| `src/kernel/workspace/` | Headless workspace adapter (sole mutation authority) |
| `src/platform/macos/control/` | JSON-RPC server dispatch |
| `~/.dietcode/control.sock` | Unix socket control surface |
| `~/.dietcode/session.token` | Session authentication |

### Workspace adapter

```text
src/kernel/workspace/
├─ WorkspaceSession.hpp/.cpp      # orchestrator
├─ WorkspaceFileOps.hpp/.cpp      # read/write/list + path security
├─ WorkspaceIndex.hpp/.cpp        # find/grep
├─ WorkspacePatchOps.hpp/.cpp     # unified diff apply (disk)
└─ WorkspaceVerifyOps.hpp/.cpp    # post-mutation verification
```

**Rule:** MacWindow may call the workspace adapter. The workspace adapter never calls MacWindow.

- Kernel RPC handlers talk to `DietCodeWorkspaceSession` via `MacControlWindowBridge` (session-only).
- Legacy UI uses `DietCodeLegacyWindowBridge` (session + optional editor overlay for open tabs).
- `dietcode-kernel` builds **without** `legacy_ui/` editor sources — zero `NSWindow` / `NSTextView` objects alive.

```bash
make kernel
./build/dietcode-kernel --workspace /path/to/project
./build/dietcode-kernel --ensure-socket
```

## Event stream

Structured events flow over the existing socket subscription model:

| RPC | Purpose |
|-----|---------|
| `event.subscribe` | Push `event.emitted` frames to client |
| `events.recent` | Poll ring buffer (500 events) for cockpit bridge |

Event shape:

```json
{
  "id": "evt-42",
  "sequence": 42,
  "timestamp": "2026-06-08T12:00:00.000+0000",
  "type": "terminal.output",
  "source": "kernel",
  "detail": "...",
  "payload": {}
}
```

## Cockpit

| Path | Role |
|------|------|
| `cockpit/` | Vite + React web UI |
| `cockpit/server/bridge.ts` | HTTP proxy + SSE event fan-out |

```bash
make cockpit-dev    # Vite on :5173, bridge on :9477
```

Bridge endpoints:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/status` | Kernel health + workspace |
| `POST /api/rpc` | JSON-RPC proxy |
| `GET /events` | SSE structured event stream |
| `GET /api/approvals` | List pending/resolved approvals |
| `GET /api/approvals/:id` | Fetch one approval |
| `POST /api/approvals/:id/resolve` | Approve or reject a queued mutation |

Kernel RPCs: `approval.list`, `approval.get`, `approval.resolve`. Destructive mutations in supervised mode (autonomy 3, kernel default) emit `approval.required` and return `approvalRequired: true` until resolved.

See [approval-lifecycle.md](./approval-lifecycle.md) for the full safety loop.

## Governed tasks

Cockpit chat submits Hermes **tasks** (not raw chat):

| Endpoint | Purpose |
|----------|---------|
| `POST /api/tasks` | Start governed Hermes run (`message`, `workspace`, `mode`) |
| `GET /api/tasks` | List tasks |
| `GET /api/tasks/:id` | Task status |

Events (`task.started`, `agent.message`, `tool.call.*`, `approval.*`, `file.diff`, `task.completed`) stream over SSE. See [governed-tasks.md](./governed-tasks.md).

## Session recovery (ephemeral)

Cockpit session state is **in-memory first** with bounded snapshots in `~/.dietcode/session/` for reload recovery — not a permanent audit trail.

| Endpoint | Purpose |
|----------|---------|
| `GET /api/session` | Restore timeline, tasks, approvals cache, recent diffs |
| `POST /api/session/export` | Optional explicit export |

See [session-recovery.md](./session-recovery.md).

## Legacy native UI

The original AppKit editor shell is preserved in `legacy_ui/` for optional editor integration:

```bash
make legacy-app     # builds DietCode.app
make run            # opens legacy app
```

## Agent integration

Agents continue to use the bundled Agent Bridge — not raw RPC, not the cockpit:

```bash
build/resources/bin/dietcode-agent-client profile
```

The bridge resolves `build/dietcode-kernel` before the legacy app bundle.
