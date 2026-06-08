# DietCode Cockpit

Web control surface for the DietCode kernel. The cockpit **never edits files directly** — all workspace mutation flows through `dietcode-kernel`.

```text
agent / user
    ↓
cockpit UI (this package)
    ↓
cockpit bridge (HTTP → Unix socket)
    ↓
dietcode-kernel
    ↓
workspace
```

## Quick start

```bash
# Terminal 1 — kernel
make kernel
./build/dietcode-kernel --workspace /path/to/project

# Terminal 2 — cockpit
make cockpit-dev
```

Open http://localhost:5173

## Panels

| Panel | Data source |
|-------|-------------|
| Chat | Agent dispatch layer (v0.1 placeholder) |
| Task timeline | `events.recent` SSE + `runtime.timeline` |
| Diffs | `runtime.operation.recent` |
| Approvals | `event.emitted` (approval/destructive types) |
| Logs | `event.emitted` (terminal/shell/verify types) |

## Bridge API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/status` | Kernel connectivity + workspace root |
| `POST /api/rpc` | Proxy JSON-RPC to `~/.dietcode/control.sock` |
| `GET /events` | SSE stream of structured kernel events |
