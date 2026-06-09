# Kernel RPC reference

Headless control surface for workspace mutation. Agents and harnesses speak this protocol via `scripts/dietcode_agent_client.py`.

| | |
|--|--|
| Socket | `~/.dietcode/control.sock` |
| Token | `~/.dietcode/session.token` |
| Wire | Single-line JSON per request/response |
| Schema | `1.6.2` |

```bash
make restart-agent-server-fast
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py rpc rpc.ping
python3 scripts/dietcode_agent_client.py --list-methods
```

See [agent-environment.md](agent-environment.md) for paths and env vars.

## Request envelope

```json
{
  "id": "unique-id",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": { "path": "src/foo.ts", "patch": "...", "confirm": true },
  "token": "<contents of session.token>"
}
```

## Checkpoint-relevant methods

### Context (checkpoint 1)

| Method | Permission | Notes |
|--------|------------|-------|
| `file.read` / `file.readRange` / `file.readAround` / `file.readBatch` | Read | Sets hash anchors; returns `coherence` when `taskId` set |
| `file.stat` | Read | Metadata + content hash; optional `coherence` with `taskId` |
| `workspace.status` | Read | Drift snapshot; optional `coherence` with `taskId` |
| `workspace.snapshot` | Read | Point-in-time hashes |
| `workspace.revision` | Read | Monotonic revision + receipts |
| `patch.validate` | Read | `beforeContentHash` for optimistic apply |

### Drift (checkpoint 2)

| Method | Permission | Notes |
|--------|------------|-------|
| `workspace.status` | Read | `driftDetected`, `affectedFiles` |
| `workspace.refreshAnchor` | Read | Re-anchor after external change |
| `workspace.continueAnyway` | Read | Operator override with `contextRefreshId` |

Edit/Destructive RPCs return `workspaceDriftRequired` when drift blocks.

When `taskId` is set, mutating RPCs also require a valid **coherence token** from the latest read. Stale tokens return `coherence_mismatch` (before drift). See [coherence-tokens.md](./coherence-tokens.md).

### Approval (checkpoint 3)

| Method | Permission | Notes |
|--------|------------|-------|
| `approval.list` | Read | Filter by `status` |
| `approval.get` | Read | Single pending approval |
| `approval.resolve` | Execute | Approve executes queued mutation |

Destructive methods return `approvalRequired: true` when autonomy is 3 (default).

### Mutation (checkpoint 4)

| Method | Permission | Notes |
|--------|------------|-------|
| `patch.validate` | Read | Pre-flight |
| `patch.apply` | Destructive* | `confirm: true`, `expectBeforeHash`, `taskId`, `coherenceTokenId`, `expectedWorkspaceRevision` |
| `patch.applyBatch` | Destructive* | Same coherence fields as single apply |

\* Queued for approval at autonomy 3. Emits `workspace.mutated` on success.

### Verification (checkpoint 5)

| Method | Permission | Notes |
|--------|------------|-------|
| `verify.run` | Execute | `command`, optional `cwd`, `taskId` |
| `verify.status` | Read | Running verify state |

Allowed command prefixes (default): `make test`, `make kernel`, `git diff --check`, `npm test`, `./verify.sh`.

Emits `verify.completed` or `verify.failed`.

## Agent-safe read/search

| Method | Notes |
|--------|-------|
| `search.literal` | Deterministic substring search |
| `search.tokens` | Conjunctive token match |
| `workspace.grep` | Literal scan with accounting |
| `tool.registry` / `tool.capabilities` | Agent-safe catalog |

Quarantined: `search.semantic` → `semantic_disabled`. Use `search.literal`.

Tool contracts: [agent-tooling.md](agent-tooling.md). Shell tools: [agent-shell-tooling.md](agent-shell-tooling.md).

## Workspace

| Method | Permission |
|--------|------------|
| `workspace.getRoot` | Read |
| `workspace.openFolder` | Destructive |
| `workspace.findFiles` | Read |
| `workspace.listFiles` | Read |

## Events

| Method | Notes |
|--------|-------|
| `events.recent` | Poll kernel events (bridge uses this) |
| `event.subscribe` | Stream subscription |

## Python CLI

```bash
python3 scripts/dietcode_agent_client.py rpc <method> --params '{}'
python3 scripts/dietcode_agent_client.py --capabilities
python3 scripts/dietcode_agent_client.py --self-test
```

## Errors

Every failure includes `string_code`, `message`, and usually `recovery_hint` + `nextRecommendedCommand`.

Catalog: [error-codes.md](error-codes.md). Invariants: [runtime-invariants.md](runtime-invariants.md).

## Related

- [architecture.md](architecture.md)
- [coherence-tokens.md](coherence-tokens.md) — coherence token model
- [checkpoint-model.md](checkpoint-model.md)
