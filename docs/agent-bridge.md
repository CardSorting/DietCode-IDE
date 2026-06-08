# DietCode Agent Bridge

Stable client-facing layer between external or local agents and the DietCode runtime. Agents should **not** call raw DietCode RPC methods directly.

```text
agent → DietCode Agent Bridge → DietCode Runtime RPC → C++ mutation kernel + runtime journal
```

The bridge absorbs runtime churn, normalizes envelopes and errors, and exposes stable workflows. The C++ runtime remains the sole mutation authority.

```bash
make agent-bridge-fast              # build TypeScript bridge only
make test-agent-bridge-fast         # offline bridge tests (mocks)
make test-agent-bridge              # rebuild/restart + offline + live (BRIDGE_LIVE=1)
make verify-agent-runtime-full      # release ladder (includes live_agent_bridge)
```

---

## Package layout

| Path | Role |
|------|------|
| `agent-bridge/src/client/` | `DietCodeBridgeClient`, `RpcTransport`, `RuntimeProfile` |
| `agent-bridge/src/capabilities/` | Runtime capability detection on `connect()` |
| `agent-bridge/src/adapters/` | Thin RPC adapters (search, patch, runtime, diagnostics) |
| `agent-bridge/src/workflows/` | Safe patch, batch patch, stale recovery, post-mutation verify |
| `agent-bridge/src/contracts/` | Types, error mapping, partial-result normalization |
| `agent-bridge/src/cli/` | `dietcode-agent-client` JSON CLI |
| `agent-bridge/tests/` | Offline mocks + optional live socket tests |

Built output is copied into the app bundle:

- `DietCode.app/Contents/Resources/agent-bridge/`
- `DietCode.app/Contents/Resources/bin/dietcode-agent-client` (launcher → bundled Node CLI)

Users install **one** DietCode app; the bridge is an internal module boundary, not a separate package to install.

---

## Public bridge API

Import from `@dietcode/agent-bridge` (repo path `agent-bridge/`) or use the CLI.

| Method | Purpose |
|--------|---------|
| `connect()` | Open control socket, detect capabilities, build `RuntimeProfile` |
| `getRuntimeProfile()` | Cached profile after `connect()` |
| `getDiagnostics()` | Unified `runtime.diagnostics` envelope (normalized) |
| `searchLiteral(query, options?)` | Deterministic literal search |
| `searchTokens(tokens, options?)` | Deterministic token search |
| `searchPaths(query, options?)` | Deterministic path search |
| `getFileStat(path)` | Workspace file metadata |
| `safePatchFile(path, unifiedDiff, options?)` | Validated apply with receipts and stale recovery |
| `safePatchBatch(patches, options?)` | Atomic batch apply with batch receipts |
| `getOperationStatus(idempotencyKey)` | Timeout / replay recovery |
| `getTimeline(options?)` | `runtime.timeline` stream |
| `getRecentActivity(options?)` | `workspace.activity` (mutation-focused timeline) |
| `verifyFast()` | Quick RPC + runtime health probe |

Raw RPC names are **not** part of the public agent API. Adapters may call RPC internally; agent code should stay on the methods above.

---

## Runtime compatibility model

On `connect()` the bridge:

1. Calls `tool.capabilities`
2. Calls `runtime.diagnostics`
3. Builds a `RuntimeProfile` with detected features

**Required** runtime features (missing → `unsupported_runtime_capability`):

- Deterministic search (`search.literal`, `search.tokens`, `search.paths`)
- Patch receipts (`patch.apply`)
- Batch receipts (`patch.applyBatch`)
- Runtime timeline (`runtime.timeline`)
- BroccoliQ / runtime journal signals in diagnostics
- `operation.status` replay
- Partial-success envelope fields (`complete`, `partial`, warnings, recovery hints)

The profile also records `semanticSearchDisabled: true` — the bridge does not add semantic search, fuzzy ranking, or embeddings.

---

## Safe patch workflow (`safePatchFile`)

1. `patch.validate` for the target path and unified diff
2. Capture `beforeContentHash` and workspace revision
3. Generate or accept an `idempotencyKey`
4. `patch.apply` with `expectBeforeHash` from validation (never blind retry)
5. On success: `mutationReceipt`, `revisionBefore` / `revisionAfter`, `nextRecommendedCommand`
6. On `nested_call_timeout`: `operation.status` with the same idempotency key
7. On `stale_content`: structured stale recovery (current hash, hints) — **no** silent re-apply

`safePatchBatch` mirrors this for multiple files: per-file validation, one batch idempotency key, `patch.applyBatch`, batch receipt required, partial stale failures verified without silent mutation.

---

## Partial results and errors

Bridge results extend a common partial-success shape:

- `complete`, `partial`, `warnings`, `fallbackUsed`, `truncated`
- `recoveryHint`, `nextRecommendedCommand`
- `raw` only when `includeRaw: true`

Stable bridge error codes include:

| Code | Typical cause |
|------|----------------|
| `stale_content` | Content drift vs validated hash |
| `semantic_disabled` | Semantic search not available (by design) |
| `ranked_search_disabled` | Ranking not available |
| `symlink_target` | Symlink policy violation |
| `patch_failed` | Validation or apply failure |
| `nested_call_timeout` | RPC timeout (retry via `operation.status` when safe) |
| `runtime_unavailable` | Socket / app not ready |
| `unsupported_runtime_capability` | Runtime missing required features |

Each error includes `message`, `recoveryHint`, `nextRecommendedCommand`, `retrySafe`, and optional `rawError`.

---

## CLI usage

Bundled launcher (after `make app`):

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client diagnostics --pretty
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client search literal "RuntimeProfile"
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client stat agent-bridge/package.json
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast
```

During development:

```bash
cd agent-bridge && npm run cli -- profile --no-start
```

Commands: `profile`, `diagnostics`, `search literal|tokens|paths`, `stat`, `patch safe-file`, `patch safe-batch`, `timeline recent`, `activity recent`, `verify fast`.

Default output is compact JSON; pass `--pretty` for indentation. Use `--no-start` when the control socket is already up (`make restart-agent-server`).

Environment:

- Control socket: `~/.dietcode/control.sock`
- Session token: `~/.dietcode/session.token`
- Optional `DIETCODE_APP_PATH` for auto `--ensure-socket` when using `startApp: true`

---

## What agents should and should not call

**Do**

- Use `DietCodeBridgeClient` or `dietcode-agent-client` for all runtime interaction
- Respect `expectBeforeHash` / stale recovery flows from `safePatchFile`
- Read `RuntimeProfile` before relying on timeline or batch features
- Treat partial envelopes as first-class (`complete: false`, `warnings`)

**Do not**

- Call `patch.apply`, `search.*`, or `runtime.*` RPC directly from agent code
- Re-implement mutation, hashing, or receipt validation in the agent
- Expect semantic or ranked search from the bridge
- Retry failed patches without revalidation or `operation.status`

---

## Tests

| Target | Scope |
|--------|--------|
| `make test-agent-bridge-fast` | Mock transport: capabilities, safe patch, stale recovery, partial results |
| `npm test` (in `agent-bridge`) | Fast tests + packaging artifact check (requires `make app`) |
| `BRIDGE_LIVE=1 npm run test:live` | Live socket integration (`bridge.live.test.ts`) |
| `make test-agent-bridge` | `restart-agent-server`, full `npm test`, then live suite |

Live tests are skipped unless `BRIDGE_LIVE=1` is set (the Makefile sets this for the full target).

---

## Production hardening (audit pass II)

| Control | Implementation |
|---------|----------------|
| RPC serialization | `RpcTransport` serializes calls via `callChain`; no interleaved frames |
| Frame matching | Reads until matching `requestId`; skips server push notifications |
| Transport retry | Configurable `transportRetries` with reconnect on transport failures |
| Token refresh | Reloads session token once on `permission_denied` |
| Throwable errors | `DietCodeBridgeError extends Error` with `toJSON()` recovery metadata |
| Contract validation | `validators.ts` mirrors frozen Python `agent_contracts.py` keys |
| Workspace bootstrap | `ensureWorkspaceRoot` on `connect()` when no folder is open |
| App path resolution | Bundled binary discovery, `DIETCODE_APP_PATH`, repo `build/` fallback |
| Test boundary | `MockRpcTransport` exported only from `@dietcode/agent-bridge/testing` |
| Live workflows | `bridge.live.workflows.test.ts` mirrors Python workflow smoke A–D |
| Audit harness | `scripts/test_agent_bridge_audit.py` + `make test-agent-bridge` |

```bash
make test-agent-bridge-fast     # offline contract + workflow mocks
make test-agent-bridge          # live socket + packaging + audit harness
python3 scripts/test_agent_bridge_audit.py --compact
```

---

## Related

- [Runtime Native Integration](runtime-native-integration.md) — timeline, identity, diagnostics parity
- [BroccoliQ Runtime Memory](broccoliq-runtime-memory.md) — journal semantics
- [Agent Runtime Audit](agent-runtime-audit.md) — broader runtime verification map
