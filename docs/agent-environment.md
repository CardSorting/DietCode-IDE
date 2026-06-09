# Agent environment

Paths, environment variables, and CLI precedence for kernel RPC clients.

```bash
python3 scripts/dietcode_agent_client.py --emit-config --json
python3 scripts/dietcode_agent_client.py --status --compact
```

## Precedence (highest wins)

1. CLI flags (`--socket`, `--token-file`, …)
2. Config file (`--config` / `DIETCODE_AGENT_CONFIG`)
3. Environment variables
4. Built-in defaults

## Paths

| Variable | Default |
|----------|---------|
| `DIETCODE_SOCKET_PATH` | `~/.dietcode/control.sock` |
| `DIETCODE_TOKEN_PATH` | `~/.dietcode/session.token` |
| `DIETCODE_APP_PATH` | `build/dietcode-kernel` |
| `DIETCODE_REPO_ROOT` | Repo root (Makefile sets for harnesses) |
| `DIETCODE_SESSION_DIR` | `~/.dietcode/session` |

## Governed tasks / coherence

| Variable | Purpose |
|----------|---------|
| `DIETCODE_TASK_ID` | Attach RPCs and events to a task; issues coherence tokens on reads |
| `DIETCODE_COHERENCE_EVENT_SOURCE` | NDJSON event source label in harnesses |

## Harness workspace

| Variable | Default |
|----------|---------|
| `DIETCODE_TEST_WORKSPACE` | Repository root |

## Restart after C++ changes

```bash
make restart-agent-server-fast
```

Without restart, harnesses may hit a stale kernel missing new RPC methods.

## Minimal config file

```json
{
  "socket": "~/.dietcode/control.sock",
  "tokenFile": "~/.dietcode/session.token",
  "timeout": 30
}
```

```bash
python3 scripts/dietcode_agent_client.py --config /path/to/config.json rpc rpc.ping
```

## Related

- [kernel-rpc.md](kernel-rpc.md)
- [coherence-tokens.md](coherence-tokens.md)
- [getting-started.md](getting-started.md)
