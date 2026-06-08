# DietCode Agent Bridge

Stable client-facing layer between external or local agents and the DietCode runtime.

```text
agent → DietCode Agent Bridge → DietCode Runtime RPC → C++ mutation kernel + runtime journal
```

Agents should **not** call raw DietCode RPC methods directly. The bridge absorbs runtime churn, normalizes envelopes and errors, and exposes stable workflows. The C++ runtime remains the sole mutation authority.

```bash
make agent-bridge-fast              # build TypeScript bridge only
make test-agent-bridge-fast         # offline bridge tests (mocks)
make test-agent-bridge              # rebuild/restart + offline + live + audit
make verify-agent-runtime-full      # release ladder (includes live_agent_bridge)
```

---

## Documentation map

| Doc | When to read |
|-----|--------------|
| **This page** | Quick reference, API table, CLI one-liners |
| [Agent Bridge Architecture](agent-bridge-architecture.md) | Layer model, connect lifecycle, transport design, workflows |
| [Agent Bridge Integration Guide](agent-bridge-integration-guide.md) | TypeScript recipes, error handling, migration from Python |
| [Agent Bridge Audit](agent-bridge-audit.md) | Pass I–II audit record, verification ladder, source index |

---

## Packaging

Users install **one** DietCode app. The bridge ships inside the bundle:

| Path | Role |
|------|------|
| `DietCode.app/Contents/Resources/agent-bridge/` | Compiled `@dietcode/agent-bridge` |
| `DietCode.app/Contents/Resources/bin/dietcode-agent-client` | CLI launcher → Node bridge CLI |

Repo source: `agent-bridge/`

### Hermes Agent (optional companion)

Hermes is **not** vendored into the IDE. `make app` also bundles the DietCode Hermes plugin:

| Path | Role |
|------|------|
| `integrations/hermes-dietcode-plugin/` | Maintainer sync boundary (not Hermes core) |
| `DietCode.app/Contents/Resources/integrations/hermes/dietcode/` | Plugin deployed to `~/.hermes/plugins/dietcode/` |
| `DietCode.app/Contents/Resources/bin/dietcode-enable-agent` | One-shot enable (lazy Hermes install + plugin deploy) |
| `DietCode.app/Contents/Resources/bin/dietcode-agent-chat` | Bounded Hermes chat (`dietcode_ide` guardrails) |

DietCode now ships a **bundled agent integration artifact**, not merely a benchmark bridge.

```bash
./scripts/sync-hermes-plugin.sh              # maintainers: refresh integrations/
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --dry-run
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --uninstall
```

Trust + update safety:

- Resolves `/Applications/DietCode.app`, `~/Applications/DietCode.app`, and local `build/DietCode.app`
- Backs up `config.yaml`, `.env`, and the installed plugin before any write
- Prints an exact change log (env keys, plugin version, config merge results)
- Bundle manifest: `dietcode-agent-bundle.manifest.json` (runtime, bridge, plugin, chat, min Hermes versions)

Agent Chat sidebar (native UI): [Agent Chat Sidebar](agent-chat-sidebar.md)

`safePatchFile` emits `mutation.patch.applied` telemetry (stderr marker + optional `DIETCODE_MUTATION_EVENT_LOG` JSONL outside the workspace). Agent Chat audits changed files against these events after each run.

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project \
  --prompt "inspect this project"
```

Live bounded-edit smoke (temp workspace, real Hermes patch via bridge):

```bash
make smoke-agent-chat-live
make test-agent-chat-workspace-switch
```

Workspace authority: when `--workspace` is passed, the bridge calls `workspace.openFolder` even if another folder is already open. `dietcode-agent-chat` refuses Hermes if `requestedWorkspace != workspaceRootObserved`.

---

## Public bridge API

Import from `@dietcode/agent-bridge` or use the bundled CLI.

| Method | Purpose |
|--------|---------|
| `connect()` | Socket + readiness + capabilities + workspace bootstrap |
| `getRuntimeProfile()` | Cached profile after `connect()` |
| `getDiagnostics()` | `runtime.diagnostics` (normalized) |
| `searchLiteral(query, options?)` | Deterministic literal search |
| `searchTokens(tokens, options?)` | Deterministic token search |
| `searchPaths(query, options?)` | Deterministic path search |
| `getFileStat(path)` | Workspace file metadata + `contentHash` |
| `safePatchFile(path, unifiedDiff, options?)` | Validated apply with receipts and stale recovery |
| `safePatchBatch(patches, options?)` | Atomic batch apply with batch receipts |
| `getOperationStatus(idempotencyKey)` | Timeout / replay recovery |
| `getTimeline(options?)` | `runtime.timeline` stream |
| `getRecentActivity(options?)` | `workspace.activity` (mutation-focused) |
| `verifyFast()` | Quick RPC + runtime health probe |
| `shellPwd()` | Agent session cwd (`shell.pwd`) |
| `shellCd(path)` | Workspace-scoped cwd change (`shell.cd`) |
| `shellRg(pattern, options?)` | Bounded ripgrep (`shell.rg`) |
| `shellHead(path, lines?)` | Bounded head read (`shell.head`) |
| `shellTail(path, lines?)` | Bounded tail read (`shell.tail`) |
| `shellSedRange(path, start, end)` | Read-only line range (`shell.sedRange`) |
| `shellCatSmall(path)` | Small-file read with truncation (`shell.catSmall`) |

Shell responses normalize `complete`, `partial`, `warnings`, `recoveryHint`, and `nextRecommendedCommand` like search/patch envelopes. See [Agent Shell Tooling](agent-shell-tooling.md).

Test-only export: `@dietcode/agent-bridge/testing` → `MockRpcTransport` (not for production agents).

### TypeScript quick start

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({ startApp: false });
await bridge.connect();

const profile = bridge.getRuntimeProfile();
const search = await bridge.searchLiteral('CONTRACT:', { maxResults: 5 });

await bridge.close();
```

Full recipes: [Integration Guide](agent-bridge-integration-guide.md).

---

## Runtime compatibility

On `connect()` the bridge calls `tool.capabilities` and `runtime.diagnostics`, validates contract keys, and builds a `RuntimeProfile`.

**Required** features (missing → `unsupported_runtime_capability`):

- Deterministic search (`search.literal`, `search.tokens`, `search.paths`)
- Patch receipts (`patch.apply`) and batch receipts (`patch.applyBatch`)
- Runtime timeline (`runtime.timeline`)
- BroccoliQ / runtime journal (`runtime.diagnostics` with mutation + record authority)
- `operation.status` replay
- Partial-success envelope fields

`semanticSearchDisabled: true` — the bridge does not add semantic search, fuzzy ranking, or embeddings.

---

## Safe patch workflow

`safePatchFile()`:

1. `patch.validate` → capture `beforeContentHash`
2. Generate or accept `idempotencyKey`
3. `patch.apply` with `expectBeforeHash` (never blind retry)
4. On success: `mutationReceipt`, `revisionBefore` / `revisionAfter`
5. On `nested_call_timeout`: `operation.status` with same key
6. On `stale_content`: structured stale recovery — re-validate, do not re-apply

**Pass XI — live authority:** `safePatchFile()` always sources `beforeContentHash` from `patch.validate` (`beforeHashSource: live_validate`). It never reads hashes from `runtime.timeline`, `memory.operation.*`, `memory.revision.*`, or cached `operation.status` receipts. Journal post-hashes are historical only.

`make test-agent-bridge-authority` — offline bridge authority tests.

`safePatchBatch()` mirrors for multiple files with atomic rollback verification.

Diagram: [Architecture — safe patch](agent-bridge-architecture.md#workflow-safe-patch).

---

## Partial results and errors

Bridge results include: `complete`, `partial`, `warnings`, `fallbackUsed`, `truncated`, `recoveryHint`, `nextRecommendedCommand`. Set `includeRaw: true` to include the raw RPC payload.

Errors throw `DietCodeBridgeError` with stable `code`, `recoveryHint`, `nextRecommendedCommand`, `retrySafe`, `rawError`, plus provenance:

| Field | Values | Meaning |
|-------|--------|---------|
| `recoverySource` | `runtime` \| `bridge_fallback` | Where `recoveryHint` came from |
| `nextCommandSource` | `runtime` \| `bridge_fallback` | Where `nextRecommendedCommand` came from |

**Pass XI rule:** runtime hints win when present. Bridge fallbacks apply only when the runtime omits hints. Protected codes (`stale_content`, `symlink_target`, `patch_failed`, `semantic_disabled`) never have runtime hints rewritten. The bridge does not auto-retry `patch.apply` after `stale_content`.

| Code | Typical cause |
|------|----------------|
| `stale_content` | Content drift vs validated hash |
| `semantic_disabled` | Semantic search quarantined |
| `patch_failed` | Validation or apply failure |
| `nested_call_timeout` | RPC timeout — use `getOperationStatus` |
| `runtime_unavailable` | Socket / app not ready |
| `unsupported_runtime_capability` | Runtime missing required features |

Full catalog: [Error Codes](error-codes.md).

---

## CLI usage

```bash
# Bundled (after make app)
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client search literal "RuntimeProfile"
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast --pretty

# Development
cd agent-bridge && npm run cli -- profile --no-start
```

Commands: `profile`, `diagnostics`, `search literal|tokens|paths`, `stat`, `patch safe-file`, `patch safe-batch`, `timeline recent`, `activity recent`, `verify fast`, `shell pwd|cd|rg|head|tail|sed|cat-small`.

Environment: `~/.dietcode/control.sock`, `~/.dietcode/session.token`, optional `DIETCODE_APP_PATH`.

---

## What agents should and should not call

**Do**

- Use `DietCodeBridgeClient` or `dietcode-agent-client`
- Respect stale recovery from `safePatchFile` — re-validate before retry
- Read `RuntimeProfile` before relying on timeline or batch features
- Treat `complete: false` as a first-class partial outcome

**Do not**

- Call `patch.apply`, `search.*`, or `runtime.*` RPC directly from agent code
- Re-implement mutation hashing or receipt validation
- Expect semantic or ranked search from the bridge
- Import `MockRpcTransport` in production agent code

---

## Tests and verification

| Target | Scope |
|--------|--------|
| `make test-agent-bridge-fast` | Offline mocks: capabilities, patch, stale, partial results |
| `npm test` (in `agent-bridge/`) | Offline + packaging artifact check |
| `BRIDGE_LIVE=1 npm run test:live` | Live socket + workflows A–D |
| `make test-agent-bridge` | Full: offline + packaging + live + audit |
| `make test-agent-bridge-audit` | Docs, API surface, packaging audit |
| `python3 scripts/test_agent_bridge_audit.py` | Same audit harness (NDJSON) |

---

## Production hardening (audit pass II)

| Control | Implementation |
|---------|----------------|
| RPC serialization | `callChain` — no interleaved socket frames |
| Frame matching | Wait for `requestId`; skip server notifications |
| Transport retry | `transportRetries` + reconnect |
| Token refresh | Reload token on `permission_denied` |
| Throwable errors | `DietCodeBridgeError extends Error` |
| Contract validation | `validators.ts` ↔ `agent_contracts.py` |
| Workspace bootstrap | `ensureWorkspaceRoot` on connect |
| Live workflows | Python smoke parity (A–D) |

Details: [Agent Bridge Audit — Pass II](agent-bridge-audit.md#pass-ii--production-hardening).

---

## Related

| Doc | Contents |
|-----|----------|
| [Agent Bridge Architecture](agent-bridge-architecture.md) | Layers, transport, connect lifecycle |
| [Agent Bridge Integration Guide](agent-bridge-integration-guide.md) | Recipes, CLI, migration |
| [Agent Bridge Audit](agent-bridge-audit.md) | Pass record and verification |
| [Agent Runtime Audit](agent-runtime-audit.md) | C++ runtime Passes I–VI |
| [Headless Agent Control](headless-agent-control.md) | Raw RPC reference (maintainers) |
| [Build & Test System](build-and-test-system.md) | Makefile targets |
