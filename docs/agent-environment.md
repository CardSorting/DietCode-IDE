# Agent Environment & Config

Plain-text reference for environment variables, config file keys, and CLI flag precedence. Grep this file when wiring automation.

```bash
rg 'DIETCODE_' docs/agent-environment.md scripts/dietcode_agent_client.py
python3 scripts/dietcode_agent_client.py --emit-config --json
```

---

## Config precedence (highest wins)

1. **CLI flag** (`--app`, `--socket`, `--token-file`, `--timeout`, …)
2. **Config file** (`--config` or `DIETCODE_AGENT_CONFIG`)
3. **Environment variable**
4. **Built-in default** (repo-relative app path, `~/.dietcode/…`)

---

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DIETCODE_AGENT_CONFIG` | *(none)* | Path to JSON config file |
| `DIETCODE_APP_PATH` | `build/DietCode.app/Contents/MacOS/DietCode` | DietCode binary for socket startup |
| `DIETCODE_SOCKET_PATH` | `~/.dietcode/control.sock` | Unix control socket |
| `DIETCODE_TOKEN_PATH` | `~/.dietcode/session.token` | Session token file |
| `DIETCODE_TEST_WORKSPACE` | repo root | Workspace opened by integration harnesses |

---

## Config file keys

Example: `docs/headless-agent-config.example.json`

| Key | Type | Maps to CLI |
|-----|------|-------------|
| `app` | string | `--app` |
| `socket` | string | `--socket` |
| `tokenFile` | string | `--token-file` |
| `timeout` | number | `--timeout` |
| `requestTimeout` | number | `--request-timeout` |
| `retries` | number | `--retries` |

---

## CLI output flags

| Flag | stdout | stderr on failure |
|------|--------|-----------------|
| `--compact` / `--json` | Single-line sorted JSON | plain text (unless `--error-json`) |
| `--error-json` | unchanged | JSON-RPC error envelope |
| `--quiet` | unchanged | suppress diagnostics |
| `--verbose` | unchanged | force diagnostics (overrides `--quiet`) |
| `--raw-response` | full RPC envelope; exit 1 when `ok:false` | via `--error-json` rules |

---

## Grep / diff workflows

```bash
# Locate RPC method implementations
rg 'executeMethod|outErrCode = @"' src/platform/macos/control

# Locate client read-method retry set
rg 'READ_METHODS' scripts/dietcode_agent_client.py

# Diff local agent client changes
git diff scripts/dietcode_agent_client.py

# Verify resolved config without connecting
python3 scripts/dietcode_agent_client.py --emit-config --json | python3 -m json.tool
```

---

## Integration harness output

All harnesses emit **NDJSON** (one JSON object per line):

| Script | Suite name | When to run |
|--------|------------|-------------|
| `scripts/control_smoke_test.py` | `control_smoke` | After `make agent-ready` |
| `scripts/test_ergonomics.py` | `ergonomics` | Patch/task contract verification |
| `scripts/run_agent_integration_tests.py` | `agent_integration` | Rolls up smoke + ergonomics |

```bash
make agent-integration
python3 scripts/run_agent_integration_tests.py --compact --verbose
python3 scripts/run_agent_integration_tests.py --compact | rg '"type":"summary"'
```

## Server restart after rebuild

`make app` replaces the binary but does not restart a running control server. After rebuilding, restart the server so RPC behavior matches the new binary:

```bash
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
build/DietCode.app/Contents/MacOS/DietCode --ensure-socket --ensure-timeout 15
make agent-integration
```

See [Build & Test System](build-and-test-system.md) and [Error Codes](error-codes.md).
