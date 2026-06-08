# Agent Bridge Integration Guide

Practical patterns for building agents on top of the DietCode Agent Bridge — TypeScript API, CLI, error handling, and workflows.

**Prerequisites:** `make app`, `make restart-agent-server`, working socket (`make agent-ready`).

See also: [Agent Bridge](agent-bridge.md), [Agent Bridge Architecture](agent-bridge-architecture.md).

---

## Quick start (TypeScript)

From the repo during development:

```bash
make agent-bridge-fast
make restart-agent-server
```

```typescript
import { DietCodeBridgeClient } from '@dietcode/agent-bridge';

const bridge = new DietCodeBridgeClient({
  startApp: false,  // socket already up
});

await bridge.connect();
const profile = bridge.getRuntimeProfile();

console.log(profile.capabilities.deterministicSearch); // true
console.log(bridge.getWorkspacePath());

await bridge.close();
// or: await bridge[Symbol.asyncDispose]() with `await using`
```

From the bundled app (after `make app`):

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client profile
build/DietCode.app/Contents/Resources/bin/dietcode-agent-client verify fast
```

---

## Connect options

| Option | Default | Purpose |
|--------|---------|---------|
| `startApp` | `true` | Run `--ensure-socket` if socket missing |
| `appPath` | auto | DietCode binary for `--ensure-socket` |
| `socketPath` | `~/.dietcode/control.sock` | Control socket |
| `tokenPath` | `~/.dietcode/session.token` | Session token |
| `connectTimeoutMs` | `10000` | Socket connect timeout |
| `requestTimeoutMs` | `30000` | Per-RPC timeout |
| `transportRetries` | `1` | Reconnect attempts on transport errors |
| `workspaceRoot` | `cwd` | Open this folder if no workspace active |
| `ensureWorkspace` | `true` | Call `workspace.openFolder` when needed |
| `agentId` | — | Passed on RPC requests |
| `rationale` | — | Human-readable RPC rationale |

```typescript
const bridge = new DietCodeBridgeClient({
  startApp: true,
  appPath: '/path/to/DietCode.app/Contents/MacOS/DietCode',
  workspaceRoot: '/path/to/project',
  agentId: 'my-agent-v1',
  transportRetries: 2,
});
```

---

## Recipe 1: Deterministic code search

```typescript
const result = await bridge.searchLiteral('expectBeforeHash', {
  maxResults: 20,
  include: ['scripts/**/*.py'],
});

if (!result.complete) {
  console.warn('partial:', result.warnings, result.recoveryHint);
}

const matches = result.result.results as Array<{ path: string; line: number }>;
```

Token conjunctive search:

```typescript
await bridge.searchTokens(['safePatch', 'idempotencyKey'], { maxResults: 10 });
```

Path match:

```typescript
await bridge.searchPaths('agent-bridge', { maxResults: 10 });
```

**Do not** call `search.semantic` — it returns `semantic_disabled` by design.

---

## Recipe 2: Safe single-file patch

```typescript
import { readFile } from 'node:fs/promises';

const relPath = 'src/example.ts';
const diff = await readFile('fixes/example.patch', 'utf8');

const outcome = await bridge.safePatchFile(relPath, diff, {
  idempotencyKey: `my-agent:patch:${relPath}:v1`,
});

if (outcome.applied) {
  console.log('receipt:', outcome.mutationReceipt);
  console.log('revision:', outcome.revisionBefore, '→', outcome.revisionAfter);
} else if (outcome.stale) {
  console.log('stale — revalidate before retry');
  console.log('expected hash:', outcome.expectedBeforeHash);
  console.log('current hash:', outcome.currentContentHash);
  console.log('hint:', outcome.recoveryHint);
}
```

The bridge never retries `patch.apply` blindly after `stale_content`.

---

## Recipe 3: Safe batch patch

```typescript
const outcome = await bridge.safePatchBatch(
  [
    { path: 'a.ts', unifiedDiff: diffA },
    { path: 'b.ts', unifiedDiff: diffB },
  ],
  { idempotencyKey: `my-agent:batch:${Date.now()}` },
);

if (outcome.applied) {
  console.log('batch receipt:', outcome.batchMutationReceipt);
} else {
  console.log('rolled back:', outcome.rolledBack);
  console.log('files unchanged:', outcome.filesVerifiedUnchanged);
  console.log('failed:', outcome.failedPath);
}
```

---

## Recipe 4: Timeout recovery

If `safePatchFile` throws `nested_call_timeout` (or you suspect a slow apply):

```typescript
import { DietCodeBridgeError, isBridgeError } from '@dietcode/agent-bridge';

const key = 'my-agent:patch:src/foo.ts:v1';

try {
  await bridge.safePatchFile('src/foo.ts', diff, { idempotencyKey: key });
} catch (error) {
  if (isBridgeError(error) && error.code === 'nested_call_timeout' && error.retrySafe) {
    const status = await bridge.getOperationStatus(key);
    if (status.status === 'completed') {
      console.log('apply completed despite timeout:', status.mutationReceipt);
    }
  } else {
    throw error;
  }
}
```

`safePatchFile` already attempts `operation.status` internally on timeout — this pattern is for explicit agent-level handling.

---

## Recipe 5: Runtime observability

```typescript
// Quick health check
const health = await bridge.verifyFast();
// { ok, rpcReady, runtimeAvailable, latencyMs }

// Full diagnostics envelope
const diag = await bridge.getDiagnostics();
// diag.result.available, mutationAuthority, recordAuthority

// Mutation-focused activity
const activity = await bridge.getRecentActivity({ limit: 20 });

// Full timeline
const timeline = await bridge.getTimeline({ limit: 50, sinceRevision: 10 });
```

Treat `complete: false` on timeline/search as normal when results are truncated.

---

## Error handling

```typescript
import { DietCodeBridgeError, isBridgeError } from '@dietcode/agent-bridge';

try {
  await bridge.connect();
} catch (error) {
  if (isBridgeError(error)) {
    console.error(error.code, error.message);
    console.error('recovery:', error.recoveryHint);
    console.error('next:', error.nextRecommendedCommand);
    console.error('retrySafe:', error.retrySafe);
    // CLI / logging: error.toJSON()
  }
}
```

| Code | Agent action |
|------|----------------|
| `stale_content` | Re-validate patch; do not re-apply same diff |
| `patch_failed` | Run validation; fix diff |
| `nested_call_timeout` | `getOperationStatus(idempotencyKey)` |
| `runtime_unavailable` | Ensure app running; `make restart-agent-server` |
| `unsupported_runtime_capability` | Upgrade DietCode app |
| `semantic_disabled` | Use `searchLiteral` / `searchTokens` |

Full catalog: [Error Codes](error-codes.md).

---

## CLI reference

```bash
# Readiness (socket must be up, or omit --no-start)
dietcode-agent-client --wait-ready

# Profile + diagnostics
dietcode-agent-client profile
dietcode-agent-client diagnostics --pretty

# Search
dietcode-agent-client search literal "RuntimeProfile"
dietcode-agent-client search tokens safe Patch File
dietcode-agent-client search paths agent-bridge

# File metadata
dietcode-agent-client stat agent-bridge/package.json

# Patch workflows
dietcode-agent-client patch safe-file src/foo.ts /tmp/foo.patch
dietcode-agent-client patch safe-batch '[{"path":"a.ts","unifiedDiff":"..."}]'

# Runtime journal surfaces
dietcode-agent-client timeline recent
dietcode-agent-client activity recent

# Health
dietcode-agent-client verify fast
```

Flags:

| Flag | Purpose |
|------|---------|
| `--pretty` | Indented JSON |
| `--compact` / `--json` | Single-line JSON (default) |
| `--error-json` | Errors as JSON on stderr |
| `--no-start` | Do not auto-start socket |
| `--wait-ready` | Wait for RPC readiness |
| `--app PATH` | DietCode binary |
| `--workspace PATH` | Workspace to open |

---

## Migrating from Python RPC client

| Python pattern | Bridge equivalent |
|----------------|-------------------|
| `DietCodeAgentClient().call("search.literal", …)` | `bridge.searchLiteral(…)` |
| `patch.validate` + `patch.apply` + `expectBeforeHash` | `bridge.safePatchFile(…)` |
| `patch.applyBatch` | `bridge.safePatchBatch(…)` |
| `operation.status` | `bridge.getOperationStatus(…)` |
| `runtime.timeline` | `bridge.getTimeline(…)` |
| `tool.capabilities` on connect | `bridge.getRuntimeProfile()` after `connect()` |

Keep `dietcode_agent_client.py` for maintainer harnesses, `--grep` shortcuts, and contract tests. New agent products should use the bridge.

---

## Testing your integration

```bash
# Offline (no socket) — fast CI loop
make test-agent-bridge-fast

# Full — rebuild, live workflows, packaging, audit
make test-agent-bridge

# Audit only (after make app)
make test-agent-bridge-audit
```

---

## Related

- [Agent Integration Cookbook](agent-integration-cookbook.md) — Python RPC recipes (legacy path)
- [Agent Environment](agent-environment.md) — env vars and config
- [Testing Checklist](testing-checklist.md) — pre-merge verification
