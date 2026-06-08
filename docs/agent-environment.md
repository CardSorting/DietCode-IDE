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

## Agent CLI shortcuts (Pass I–VI)

| Flag | RPC / behavior |
|------|----------------|
| `--grep QUERY` | `workspace.grep` literal scan |
| `--grep-format rg` | ripgrep-style lines; exit 1 when no matches |
| `--search-literal QUERY` | `search.literal` (agent-safe) |
| `--search-semantic QUERY` | **Deprecated** — stderr warning |
| `--expect-before-hash HASH` | `expectBeforeHash` on `patch.apply` |
| `--diff-hunks` + `--diff-source` | `diff.hunks` structured output |
| `--patch-summary` | Compact `patch.validate` summary |
| `--raw-response` | Full envelope; exit 1 when `ok:false` |
| `--error-json` | JSON error envelopes on stderr |
| `--diagnose` | Socket/RPC diagnostic snapshot |

Full flag table: [Headless Agent Control](headless-agent-control.md#cli-flag-reference).

---

## Integration harness output

All harnesses emit **NDJSON** (one JSON object per line). Registry: `INTEGRATION_SUITES` in `scripts/agent_contracts.py`.

| Script | Suite name | Pass |
|--------|------------|------|
| `control_smoke_test.py` | `control_smoke` | — |
| `test_task_server_health.py` | `task_server_health` | — |
| `test_rpc_transaction_health.py` | `rpc_transaction` | — |
| `test_ergonomics.py` | `ergonomics` | — |
| `test_operator_diagnostics.py` | `operator_diagnostics` | — |
| `test_runtime_safety.py` | `runtime_safety` | — |
| `test_grep_diff_tooling.py` | `grep_diff_tooling` | I |
| `test_runtime_determinism.py` | `runtime_determinism` | II |
| `test_transaction_kernel.py` | `transaction_kernel` | III |
| `test_harness_realism.py` | `harness_realism` | IV |
| `test_deterministic_retrieval.py` | `deterministic_retrieval` | V |
| `test_agent_workflow_smoke.py` | `agent_workflow_smoke` | VI |
| `test_cli_agent_failures.py` | `cli_agent_failures` | VI |
| `test_docs_code_drift.py` | `docs_code_drift` | VI (offline) |
| `test_partial_success_closure.py` | `partial_success_closure` | VI closure |

Rollup scripts:

```bash
make agent-integration                              # smoke + ergonomics NDJSON
make verify-agent-runtime                           # 14-check ladder
make verify-agent-runtime-full                      # release ladder
python3 scripts/run_agent_integration_tests.py --compact | rg '"type":"summary"'
```

---

## Server restart after rebuild

`make app` replaces the binary but does not restart a running control server:

```bash
make restart-agent-server
make agent-ready
```

Equivalent manual steps:

```bash
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
build/DietCode.app/Contents/MacOS/DietCode --ensure-socket --ensure-timeout 15
```

Task failure recovery: [Task Server Recovery](task-server-recovery.md). Queue contract: [Queue Contract](queue-contract.md). Frozen contracts: [Runtime Contracts](runtime-contracts.md). Audit record: [Agent Runtime Audit](agent-runtime-audit.md).

See [Build & Test System](build-and-test-system.md) and [Error Codes](error-codes.md).
