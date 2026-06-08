# Build & Test System

DietCode is designed to be built and verified using only platform-native tools, avoiding the overhead of external package managers or heavy build frameworks.

## 🛠️ The Build System (`Makefile`)

The build process is orchestrated by a single, transparent `Makefile`.

### Primary Targets
- **`make app`**: Compiles the portable C++20 core and the Objective-C++ macOS shell, then bundles them into `build/DietCode.app`.
- **`make test`**: Compiles and executes the unit test suite and agent self-tests.
- **`make clean`**: Wipes the `build/` directory for a fresh start.

### Platform Flags
- **`CXXFLAGS`**: Enables C++20 and strict warning levels (`-Wall -Wextra -Wpedantic`).
- **`OBJCXXFLAGS`**: Enables Automatic Reference Counting (`-fobjc-arc`) for the macOS shell integration.

---

## 🧪 Testing Strategy

DietCode employs a **Zero-Dependency Testing** approach. Tests are designed to be fast, readable, and executable on any machine with a C++ compiler.

### Unit Tests (`tests/test_editor.cpp`)
- **Direct Logic Verification**: Tests the `TextBuffer`, `EditorDocument`, and search algorithms directly in C++.
- **Self-Contained**: Implements its own minimal `expect()` assertion logic to avoid linking against heavy test frameworks like GTest or Catch2.
- **Speed**: The entire suite runs in milliseconds, encouraging frequent execution during the development cycle.

### Integration & Agent Tests

Full audit context: [Agent Runtime Audit](agent-runtime-audit.md) (Passes I–VI).

#### Socket readiness

| Target | Socket? | Purpose |
|--------|---------|---------|
| `make restart-agent-server` | Starts server | Rebuild + kill stale process + `--ensure-socket` (required after C++ changes) |
| `make agent-ready` | Yes | `--wait-ready` preflight |
| `make agent-status` | Yes | Socket + RPC readiness JSON |
| `make agent-ping` | Yes | `rpc.ping` smoke |
| `make agent-methods` | Yes | List RPC method names |
| `make agent-capabilities` | Yes | `tool.capabilities` summary |

#### Offline (no socket)

| Target | Script | Pass |
|--------|--------|------|
| `make agent-self-test` | `dietcode_agent_client.py --self-test` | — |
| `make test-agent-offline` | + `test_contract_lockdown.py` | — |
| `make test-docs-code-drift` | `test_docs_code_drift.py` | VI |

#### Live contract suites (socket required)

| Target | Script | Pass |
|--------|--------|------|
| `make control-smoke` | `control_smoke_test.py` | — |
| `make test-task-health` | `test_task_server_health.py` | — |
| `make test-rpc-transaction` | `test_rpc_transaction_health.py` | — |
| `make test-operator-diagnostics` | `test_operator_diagnostics.py` | — |
| `make test-runtime-safety` | `test_runtime_safety.py` | — |
| `make test-grep-diff-tooling` | `test_grep_diff_tooling.py` | I |
| `make test-runtime-determinism` | `test_runtime_determinism.py` | II |
| `make test-transaction-kernel` | `test_transaction_kernel.py` | III |
| `make test-harness-realism` | `test_harness_realism.py` | IV |
| `make test-deterministic-retrieval` | `test_deterministic_retrieval.py` | V |
| `make test-agent-workflow-smoke` | `test_agent_workflow_smoke.py` | VI |
| `make test-cli-agent-failures` | `test_cli_agent_failures.py` | VI |
| `make test-partial-success-closure` | `test_partial_success_closure.py` | VI closure |
| `make test-ergonomics` | `test_ergonomics.py` | — |
| `make agent-integration` | `run_agent_integration_tests.py` | — |
| `make test-agent-integration` | Alias for `agent-integration` | — |

#### Verification ladders

| Target | Contents |
|--------|----------|
| `make verify-agent-runtime-fast` | Same as `verify-agent-runtime` but **no rebuild/restart** (assumes fresh server/binary) |
| `make verify-agent-runtime` | 14 checks: offline + smoke + task + RPC + ergonomics + operator + safety + passes I–V; rebuilds + restarts once |
| `make verify-agent-runtime-full-fast` | Same as `verify-agent-runtime-full` but **no rebuild/restart** |
| `make verify-agent-runtime-full` | 9 checks: offline drift + full ladder + workflow + CLI + partial-success + BroccoliQ memory + release readiness; rebuilds + restarts once |
| `make test-broccoliq-runtime-memory-fast` | BroccoliQ memory tests only, no rebuild/restart |
| `make test-broccoliq-runtime-memory` | BroccoliQ memory tests with rebuild + restart |
| `make release-check-agent-runtime` | Release-grade gate (`release_check_agent_runtime.py`) |

**Fast vs full:** `*-fast` targets skip `make app` / `make restart-agent-server` and are for day-to-day iteration after you have already built and restarted. Full targets rebuild and restart once at the start (the app link step takes ~60s with no output — progress lines now emit before each ladder step).

**After C++ changes:** run `make app && make restart-agent-server` once, then use `*-fast` targets while iterating; use full targets before merge/release.

Environment variables and config precedence: [Agent Environment](agent-environment.md).

Frozen runtime contracts: [Runtime Contracts](runtime-contracts.md). Operator workflows: [Operator Diagnostics](operator-diagnostics.md).

```bash
make test-agent-offline
make verify-agent-runtime
make verify-agent-runtime-full
rg 'CONTRACT:' docs/runtime-contracts.md
```

### Agent verification ladder

```bash
# 1. Build + fresh server (after C++ edits)
make app
make restart-agent-server

# 2. Offline client checks (no socket)
make agent-self-test
make test-docs-code-drift

# 3. Ensure socket + RPC readiness
make agent-ready
make agent-status    # expect "ok":true
make agent-ping      # expect {"pong":true,...}

# 4. Per-pass suites
make test-grep-diff-tooling        # Pass I
make test-runtime-determinism      # Pass II
make test-transaction-kernel       # Pass III
make test-harness-realism          # Pass IV
make test-deterministic-retrieval  # Pass V
make test-agent-workflow-smoke     # Pass VI
make test-cli-agent-failures
make test-partial-success-closure  # Pass VI closure

# 5. Full ladders
make verify-agent-runtime
make verify-agent-runtime-full
make release-check-agent-runtime

# 6. Grep/diff CLI shortcuts (literal search, no semantic layer)
python3 scripts/dietcode_agent_client.py --grep DietCode --max-results 3 --compact
python3 scripts/dietcode_agent_client.py --grep DietCode --grep-format rg
python3 scripts/dietcode_agent_client.py --search-literal CONTRACT --max-results 3 --compact
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --diff-summary --compact
```

Override the workspace used by integration scripts:

```bash
export DIETCODE_TEST_WORKSPACE=/path/to/workspace
make test-agent-integration
```

See [Error Codes](error-codes.md) for stable `string_code` values and grep anchors.

---

## 🤖 Headless CI Support

DietCode's build system is fully CI-compatible:
- **Exit Codes**: The test runner and agent client use standard Unix exit codes (0 for success, non-zero for failure).
- **Headless Mode**: The `--headless` flag allows DietCode to run without a window, enabling automated testing of the RPC surface in virtualized environments.
