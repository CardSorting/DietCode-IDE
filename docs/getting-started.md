# Getting started

## Prerequisites

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`clang++`, `make`)
- Node.js 20+ (cockpit + agent-bridge)
- Python 3.11+ (harnesses, `dietcode_agent_client.py`)

## Build the kernel

```bash
make kernel
./build/dietcode-kernel --ensure-socket
```

Kernel control surface:

| Path | Role |
|------|------|
| `~/.dietcode/control.sock` | Unix socket |
| `~/.dietcode/session.token` | Session auth token |

Verify:

```bash
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
```

## Open a workspace

```bash
python3 scripts/dietcode_agent_client.py rpc workspace.openFolder \
  --params '{"path":"/path/to/your/project"}'
```

Destructive workspace ops (including `workspace.openFolder` at autonomy 3) queue for approval. Resolve via cockpit Approvals panel or `approval.resolve` RPC.

## Run the cockpit

```bash
cd cockpit && npm install && npm run dev
```

This starts:

- Vite dev server (UI)
- Bridge API at `http://127.0.0.1:9477`

Production build:

```bash
make cockpit
cd cockpit && npm run bridge    # bridge only, after build
```

## Submit a governed task

In cockpit chat, or via API:

```bash
curl -s -X POST http://127.0.0.1:9477/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"message":"Fix probe VALUE","workspace":"/path/to/project","mode":"supervised"}'
```

Watch checkpoints: `GET /api/tasks/:id/checkpoints`.  
See [governed-tasks.md](governed-tasks.md).

## Prove the loop (release gate)

```bash
make checkpoint-core
```

Runs kernel + bridge + cockpit builds, the 53-check `cockpit-smoke` vertical slice, checkpoint unit tests, and `make test-docs-code-drift`.  
Tag: `checkpoint-core-v0.1`.

## Restart kernel after C++ changes

```bash
make restart-agent-server-fast    # fast — no rebuild
make restart-agent-server         # rebuild kernel + restart
```

Stale kernel binaries cause missing RPC methods (e.g. `workspace.status`). Always restart after pulling C++ changes.

## Optional: legacy app + Hermes

```bash
make app
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
```

Not required for cockpit checkpoint work. See [integrations.md](integrations.md).

## Next

- [architecture.md](architecture.md) — how components connect
- [testing.md](testing.md) — all make targets
- [troubleshooting.md](troubleshooting.md) — socket and drift issues
