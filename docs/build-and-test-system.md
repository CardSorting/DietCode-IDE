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

| Target | Socket required? | Output |
|--------|------------------|--------|
| `make agent-self-test` | No | Compact JSON self-test report |
| `make control-smoke` | Yes | NDJSON check lines + summary |
| `make agent-integration` | Yes | NDJSON rollup via `run_agent_integration_tests.py` |
| `make test-agent-integration` | Yes | Alias for `agent-integration` |

- **`make agent-self-test`**: Runs offline parser/transport checks in `scripts/dietcode_agent_client.py --self-test`. Does **not** connect to a live server.
- **`make control-smoke`**: Runs `scripts/control_smoke_test.py`, which emits one NDJSON object per check and a final `{"type":"summary",...}` line.
- **`make test-ergonomics`**: Runs `scripts/test_ergonomics.py` for patch validation and task-runtime contracts (requires an open workspace).
- **`make agent-integration`**: Runs `scripts/run_agent_integration_tests.py` (smoke + ergonomics NDJSON rollup).
- **`make test-agent-integration`**: Alias for `agent-integration`.

Environment variables and config precedence: [Agent Environment](agent-environment.md).

### Agent verification ladder

```bash
# 1. Build
make app

# 2. Offline client checks (no socket)
make agent-self-test

# 3. Ensure socket + RPC readiness
make agent-ready
make agent-status    # expect "ok":true
make agent-ping      # expect {"pong":true,...}

# 4. Live integration (NDJSON smoke + contract suite)
make test-agent-integration

# 5. Grep/diff CLI shortcuts (literal search, no semantic layer)
python3 scripts/dietcode_agent_client.py --grep DietCode --max-results 3 --compact
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --include-lines --compact
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
