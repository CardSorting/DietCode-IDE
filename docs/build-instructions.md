# Build Instructions

How to compile, run, and verify DietCode from source. Agent-runtime verification: [Build & Test System](build-and-test-system.md). Audit context: [Agent Runtime Audit](agent-runtime-audit.md).

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| macOS 12+ | Primary platform target |
| Xcode Command Line Tools | `xcode-select --install` |
| `clang++` | C++20, provided by Xcode CLT |
| `make` | Single Makefile orchestrates build and tests |
| Python 3 | Agent client and integration harnesses only |

No npm, Cargo, CMake, or third-party package manager is required for the MVP.

---

## Core build targets

```bash
make test          # C++ editor unit tests + offline agent self-test
make app           # build/DietCode.app
make run           # launch interactive IDE
make clean         # remove build/
```

Expected test output includes `All DietCode editor tests passed.` from the C++ runner.

---

## Headless and agent server

```bash
make headless              # run without window; starts control server
make ensure-socket         # ensure socket is listening (no UI)
make restart-agent-server  # rebuild + kill stale process + ensure socket
make agent-ready           # wait for socket + RPC readiness
make agent-status          # readiness JSON on stdout
make agent-ping            # rpc.ping smoke
```

**After any C++ change under `src/platform/macos/control/`**, run `make restart-agent-server` before live harnesses. A stale server binary causes false test failures.

Socket path: `~/.dietcode/control.sock`  
Token file: `~/.dietcode/session.token`

---

## Agent verification (quick)

```bash
# Offline — no socket required
make test-agent-offline
make test-docs-code-drift

# Daily ladder (14 checks)
make verify-agent-runtime

# Release ladder (workflow smoke + partial-success closure + release readiness)
make verify-agent-runtime-full
make release-check-agent-runtime
```

Per-pass suites (require live server):

```bash
make test-grep-diff-tooling        # Pass I
make test-runtime-determinism      # Pass II
make test-transaction-kernel       # Pass III
make test-harness-realism          # Pass IV
make test-deterministic-retrieval  # Pass V
make test-agent-workflow-smoke     # Pass VI
make test-cli-agent-failures
make test-partial-success-closure
```

Override harness workspace:

```bash
export DIETCODE_TEST_WORKSPACE=/path/to/workspace
make test-agent-integration
```

---

## CLI smoke (after `make agent-ready`)

```bash
python3 scripts/dietcode_agent_client.py --grep CONTRACT --max-results 3 --compact
python3 scripts/dietcode_agent_client.py --search-literal CONTRACT --max-results 3 --compact
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
python3 scripts/dietcode_agent_client.py --emit-config --json
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Cocoa/Cocoa.h not found` | `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` |
| `connection_refused` on agent calls | `make restart-agent-server` then `make agent-ready` |
| Harness passes before C++ edit, fails after | Stale server — `make restart-agent-server` |
| `permission_denied` on socket | Run from an environment with access to `~/.dietcode/` |

More: [FAQ & Troubleshooting](faq-and-troubleshooting.md).

---

## Build philosophy

- Platform-native tools only (`clang++`, `make`, AppKit).
- Keep the Makefile readable — one file, no code generation.
- Zero-dependency C++ tests (no GTest/Catch2).
- Add CMake only when multi-platform complexity requires it.
