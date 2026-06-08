# Agent Bridge Audit (Passes I–II)

Canonical record of the DietCode Agent Bridge — the stable TypeScript client layer between external agents and the DietCode runtime RPC surface.

```bash
rg 'agent-bridge|Agent Bridge' docs/ agent-bridge/
make test-agent-bridge
make test-agent-bridge-audit
```

**Scope:** bundled bridge package, public API boundary, safe patch workflows, capability detection, production transport hardening, live workflow parity, packaging, and audit harness.

**Explicitly excluded:** semantic search, embeddings, fuzzy ranking, duplicate mutation authority in the bridge, raw RPC leakage in the public agent API.

---

## Pass summary

| Pass | Focus | Key deliverables | Verify |
|------|-------|------------------|--------|
| **I** | Bridge package + packaging | `agent-bridge/` package, `DietCodeBridgeClient`, CLI, Makefile `make app` bundling | `make test-agent-bridge-fast` |
| **II** | Production hardening | Serialized transport, `DietCodeBridgeError`, contract validators, live workflows A–D, audit harness | `make test-agent-bridge`, `test_agent_bridge_audit.py` |

---

## Pass I — Bridge package and packaging

### Problem

Agents integrated via raw RPC method names (`patch.apply`, `search.literal`, …) coupled agent code to runtime churn. Python `dietcode_agent_client.py` helped but was not a stable workflow-oriented boundary and was not bundled inside the app.

### Architecture decision

```text
agent → DietCode Agent Bridge → DietCode Runtime RPC → C++ mutation kernel + runtime journal
```

The bridge **adapts, validates, retries safely, and presents stable workflows**. It does not own mutation authority.

### Changes

| Area | Implementation |
|------|----------------|
| Package | `agent-bridge/` TypeScript module (`@dietcode/agent-bridge`) |
| Public API | `DietCodeBridgeClient` — 13 stable methods (no raw RPC names) |
| Adapters | `searchAdapter`, `patchAdapter`, `runtimeAdapter`, `diagnosticsAdapter` |
| Workflows | `safePatchFile`, `safePatchBatch`, `stalePatchRecovery`, `verifyAfterMutation` |
| Capabilities | `detectRuntimeCapabilities` on `connect()` — fails loudly if required features missing |
| CLI | `dietcode-agent-client` — compact JSON by default |
| Bundling | `DietCode.app/Contents/Resources/agent-bridge/` + `bin/dietcode-agent-client` launcher |
| Offline tests | Mock transport: capabilities, safe patch, stale recovery, partial results |
| Docs | `docs/agent-bridge.md` |

### Public API (frozen surface)

| Method | Internal RPC (not public) |
|--------|---------------------------|
| `connect()` | `tool.capabilities`, `runtime.diagnostics`, `rpc.ping` |
| `searchLiteral()` | `search.literal` |
| `searchTokens()` | `search.tokens` |
| `searchPaths()` | `search.paths` |
| `getFileStat()` | `file.stat` |
| `safePatchFile()` | `patch.validate` → `patch.apply` |
| `safePatchBatch()` | `patch.validate` × N → `patch.applyBatch` |
| `getOperationStatus()` | `operation.status` |
| `getTimeline()` | `runtime.timeline` |
| `getRecentActivity()` | `workspace.activity` |
| `getDiagnostics()` | `runtime.diagnostics` |
| `verifyFast()` | `rpc.ping` + `runtime.diagnostics` |

### Invariants

- No raw RPC names in the public bridge API
- No duplicate mutation authority — `expectBeforeHash`, receipts, stale guards stay in C++
- No semantic search, fuzzy matching, ranking, or hidden heuristics in the bridge
- Partial-success envelopes normalized at the bridge boundary

---

## Pass II — Production hardening

### Problem

Initial bridge transport lacked serialization parity with Python `dietcode_agent_client.py`, errors were plain objects, contract validation was minimal, live workflow coverage was thin, and `MockRpcTransport` leaked into the public package export.

### Changes

| Area | Implementation |
|------|----------------|
| RPC serialization | `RpcTransport.callChain` — one in-flight request per socket |
| Frame matching | Read loop until `requestId` matches; skip server push notifications |
| Transport retry | `transportRetries` + reconnect on transport failures (read methods get ≥1 retry) |
| Token refresh | Reload session token once on `permission_denied` |
| Throwable errors | `DietCodeBridgeError extends Error` with `toJSON()` recovery metadata |
| Contract validation | `validators.ts` mirrors `agent_contracts.py` key sets |
| Workspace bootstrap | `ensureWorkspaceRoot` on `connect()` |
| App path resolution | Bundled binary, `DIETCODE_APP_PATH`, repo `build/` fallback (`config.ts`) |
| Readiness | `waitForReady()` — `rpc.ping` loop before capability detection |
| Test boundary | `MockRpcTransport` → `@dietcode/agent-bridge/testing` only |
| Live integration | `bridge.live.test.ts` — profile, search, timeline, verify |
| Live workflows | `bridge.live.workflows.test.ts` — workflows A–D (Python smoke parity) |
| Audit harness | `scripts/test_agent_bridge_audit.py` |
| Makefile fix | `BRIDGE_LIVE=1` passed to npm for live suite; `--test-concurrency=1` |

### Bugs fixed in Pass II

| Bug | Symptom | Fix |
|-----|---------|-----|
| `waitForReady` clock mismatch | Connect always failed (`performance.now` vs `Date.now`) | Unified on `Date.now()` |
| `BridgeError` recursion | Stack overflow on any thrown error | Recovery defaults inlined in `DietCodeBridgeError` |
| Read timeout as socket close | False `transport_error` on slow responses | Empty reads retry until deadline |
| Parallel live tests | Flaky capability detection | Serial live test concurrency |
| `BRIDGE_LIVE` Makefile placement | Live tests always skipped | Env var scoped to `npm run test:live` |

### Live workflow parity (vs `test_agent_workflow_smoke.py`)

| Workflow | Bridge live test | Behavior |
|----------|------------------|----------|
| **A** — Find and patch | `workflow A — stat, safe patch, revision bump` | `getFileStat` → `safePatchFile` → revision bump + receipt |
| **B** — Stale recovery | `workflow B — stale apply surfaces structured recovery` | validate → external mutate → `stale_content` on apply |
| **C** — Batch rollback | `workflow C — batch apply rolls back on stale member` | batch stale → atomic failure, files unchanged |
| **D** — Semantic disabled | `workflow D — semantic disabled maps to stable bridge error` | `search.semantic` → `semantic_disabled` via `mapRpcError` |

---

## Verification ladder

### Daily development

```bash
make agent-bridge-fast           # compile TypeScript only
make test-agent-bridge-fast      # offline mocks (no socket)
make restart-agent-server        # after C++ changes
BRIDGE_LIVE=1 cd agent-bridge && npm run test:live   # live socket (optional)
```

### Release / full closure

```bash
make test-agent-bridge           # offline + packaging + live + audit
make verify-agent-runtime-full   # includes live_agent_bridge step
python3 scripts/test_agent_bridge_audit.py --compact
```

### Audit harness checks (`test_agent_bridge_audit.py`)

| Check | Validates |
|-------|-----------|
| `audit.docs_public_api` | All 13 public methods documented in `agent-bridge.md` |
| `audit.docs_forbid_raw_rpc` | Docs warn against direct RPC |
| `audit.no_mock_in_public_index` | `MockRpcTransport` not in public `index.ts` |
| `audit.testing_subpath` | `@dietcode/agent-bridge/testing` export exists |
| `audit.makefile_targets` | `test-agent-bridge`, `test-agent-bridge-fast`, `agent-bridge-fast` |
| `audit.throwable_error_class` | `DietCodeBridgeError extends Error` |
| `audit.rpc_transport_serialization` | `callChain` + `readJsonFrame` in transport |
| `audit.offline_tests` | `make test-agent-bridge-fast` passes |
| `audit.packaged_artifact` | Bundled `agent-bridge/dist/index.js` + launcher exist |

---

## Source file index

| Area | Primary files |
|------|---------------|
| Public client | `agent-bridge/src/client/DietCodeBridgeClient.ts` |
| Transport | `agent-bridge/src/client/RpcTransport.ts`, `connection.ts`, `config.ts` |
| Capabilities | `agent-bridge/src/capabilities/detectRuntimeCapabilities.ts` |
| Workflows | `agent-bridge/src/workflows/safePatchFile.ts`, `safePatchBatch.ts` |
| Contracts | `agent-bridge/src/contracts/types.ts`, `errors.ts`, `BridgeError.ts`, `validators.ts` |
| CLI | `agent-bridge/src/cli/dietcode-agent-client.ts` |
| Test doubles | `agent-bridge/src/testing/MockRpcTransport.ts` |
| Python contracts | `scripts/agent_contracts.py` (parity source) |
| Audit harness | `scripts/test_agent_bridge_audit.py` |
| Launcher | `resources/bin/dietcode-agent-client` |

---

## Intentionally not added

- Semantic graphs, embeddings, vector search, fuzzy matching
- Probabilistic ranking or opaque relevance scores
- Raw RPC methods on `DietCodeBridgeClient`
- Mutation authority or stale decisions in TypeScript (C++ kernel only)
- `MockRpcTransport` in the production public export

---

## Related docs

| Doc | Contents |
|-----|----------|
| [Agent Bridge](agent-bridge.md) | Overview and quick reference |
| [Agent Bridge Architecture](agent-bridge-architecture.md) | Layer diagram, module boundaries, connect lifecycle |
| [Agent Bridge Integration Guide](agent-bridge-integration-guide.md) | TypeScript recipes, error handling, CLI patterns |
| [Agent Runtime Audit](agent-runtime-audit.md) | C++ runtime Passes I–VI |
| [Headless Agent Control](headless-agent-control.md) | Raw RPC reference (maintainers / legacy Python) |
| [Build & Test System](build-and-test-system.md) | Makefile targets |
