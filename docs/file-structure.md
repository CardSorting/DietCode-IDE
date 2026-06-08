# File Structure

Repository layout as of the agent-runtime audit (Passes I–VI). Grep for drift:

```bash
rg 'MacControl|agent_contracts' src/ scripts/ --files-with-matches
```

---

## Top level

```text
DietCode-IDE/
  Makefile                 # Build + all agent verification targets
  README.md                # Project overview and quick start
  LICENSE
  resources/
    Info.plist
    logo.svg
  docs/                    # Specifications and guides (see docs/README.md)
  agent-bridge/            # Bundled TypeScript agent bridge (@dietcode/agent-bridge)
  scripts/                 # Python agent client, harnesses, fixtures
  src/                     # Portable C++20 core + macOS shell
  tests/
    test_editor.cpp        # Zero-dependency C++ unit tests
  build/                   # Generated (DietCode.app, test_editor)
  .wiki/                   # Decision logs and internal memory
```

---

## `src/` — portable core

```text
src/
  editor/                  # TextBuffer, EditorDocument, undo/redo
  search/                  # FindInFile, workspace search primitives
  syntax/                  # Regex tokenizer
  filesystem/              # FileService, GitService, FileWatcher
  core/                    # LSPClient, app state, event bus
  platform/
    macos/
      main.mm
      ui/                  # AppKit shell (MacWindow, menus, editor views)
      control/             # JSON-RPC server (agent surface)
      services/            # Symbol index, diff analysis, subprocess runner
```

### `src/platform/macos/control/` — agent surface

| Path | Role |
|------|------|
| `MacControlServer.mm` | Socket listener, request dispatch, error envelopes |
| `categories/MacControlServer+*.mm` | Per-domain RPC handlers (file, editor, git, terminal, …) |
| `services/MacControlSearchService.mm` | Grep, literal/token/path search, semantic quarantine |
| `services/MacControlPatchService.mm` | patch.validate / patch.apply / applyBatch |
| `services/MacControlWorkspaceState.mm` | workspace.revision, snapshot, operation.status |
| `services/MacControlToolRegistry.mm` | tool.registry, tool.capabilities |
| `services/MacControlMethodCatalog.mm` | RPC method catalog and permissions |
| `services/MacControlRoutingPolicy.mm` | Read vs execution queue routing |
| `utils/MacControlSupport.mm` | Disk fallback reads, partial-success enrichment |
| `utils/MacControlSocketSafety.mm` | Socket path audit and hardening |
| `utils/MacControlRuntimeDiagnostics.mm` | NDJSON diagnostics, recovery hints |
| `utils/MacControlDiffParsing.mm` | Unified diff hunk parsing |

Domain limits: `src/domain/control/ControlRuntimeLimits.hpp`

---

## `agent-bridge/` — bundled TypeScript client

| Path | Role |
|------|------|
| `src/client/DietCodeBridgeClient.ts` | Stable public API (13 methods) |
| `src/client/RpcTransport.ts` | Serialized Unix-socket JSON-RPC |
| `src/workflows/` | `safePatchFile`, `safePatchBatch`, stale recovery |
| `src/contracts/` | Types, `DietCodeBridgeError`, validators, partial-result normalization |
| `src/cli/dietcode-agent-client.ts` | Bundled CLI |
| `src/testing/MockRpcTransport.ts` | Test-only transport (not public export) |
| `tests/` | Offline mocks + live socket suites |

Packaged into `DietCode.app/Contents/Resources/agent-bridge/`. Docs: [Agent Bridge](agent-bridge.md).

---

## `scripts/` — agent client and harnesses

| Path | Role |
|------|------|
| `dietcode_agent_client.py` | Python RPC client, CLI shortcuts, `--self-test` |
| `dietcode_agent_chat.py` | Bounded Hermes chat CLI (`dietcode-agent-chat`) |
| `dietcode_agent_bundle.py` | App bundle resolution, workspace authority, Hermes launch |
| `dietcode_mutation_authority.py` | Post-run mutation audit (bridge telemetry vs disk) |
| `dietcode_diff_authority.py` | Post-run unified diff audit |
| `dietcode_verification_authority.py` | Post-mutation executable verification |
| `smoke_agent_chat_live.py` | Live smoke — all four authority layers |
| `verify_agent_chat_sidebar.py` | Sidebar + bundled CLI artifact checks |
| `agent_contracts.py` | **Frozen contract key sets** (source of truth for schemas) |
| `agent_tooling.py` | Offline grep/diff mirrors for contract tests |
| `harness_support.py` | Symlink fixtures, transport mocks (Pass IV) |
| `verify_agent_runtime.py` | `make verify-agent-runtime` ladder |
| `verify_agent_runtime_full.py` | `make verify-agent-runtime-full` ladder |
| `test_agent_bridge_audit.py` | `make test-agent-bridge-audit` bridge audit harness |
| `release_check_agent_runtime.py` | `make release-check-agent-runtime` |
| `test_*.py` | Per-suite NDJSON harnesses (one check line + summary per suite) |

### `scripts/fixtures/`

| Directory | Contents |
|-----------|----------|
| `tooling/` | Grep anchors, unified diff samples, stale-content JSON |
| `retrieval/` | search.literal/tokens/registry golden responses |
| `recovery/` | `error_recovery_hints.json` |
| `release/` | `surface_classification.json`, `internal_method_namespaces.json` |
| `rpc/` | Envelope schemas, expected error codes, ping request |
| `harness/` | Symlink policy, search.files golden |
| `safety/` | Destructive method list |

---

## `docs/` — documentation map

See [Documentation Index](README.md). Key agent-runtime docs:

- [agent-runtime-audit.md](agent-runtime-audit.md) — Pass I–VI record
- [agent-tooling.md](agent-tooling.md) — grep/diff/patch/retrieval contracts
- [runtime-invariants.md](runtime-invariants.md) — frozen behavioral rules
- [headless-agent-control.md](headless-agent-control.md) — RPC reference

---

## Intentionally shallow

The tree stays broad but shallow: no vendored dependencies, no generated RPC stubs, no nested build systems. New agent surfaces add a service handler, contract keys in `agent_contracts.py`, a harness script, and a Makefile target.
