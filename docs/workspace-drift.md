# Workspace drift guardrails

**Checkpoint 2 · Drift** — *Did the workspace change underneath the agent?*

Canonical loop: [checkpoint-model.md](./checkpoint-model.md).

DietCode tracks workspace **state validity** so the agent cannot mutate files after the world changed underneath it.

## Kernel RPCs

| RPC | Permission | Purpose |
|-----|------------|---------|
| `workspace.status` | Read | Full drift snapshot |
| `workspace.snapshot` | Read | Point-in-time file hashes (existing) |
| `workspace.refreshAnchor` | Read | Re-anchor tracked files + git HEAD; bumps `contextRefreshId` |
| `workspace.continueAnyway` | Read | One-shot override (5 min) for supervised flows |

### `workspace.status` tracks

- `root` — active workspace path
- `gitHead` / `gitBranch` — current git state
- `anchorGitHead` / `anchorRefreshedAt` — last refresh anchor
- `dirtyFiles` — git modified/staged/untracked paths
- `fileAnchors` — mtime/hash anchors for agent-touched files
- `affectedFiles` — human-readable drift list with `reason`
- `lastVerifiedCommand` / `lastVerifiedAt` / `lastVerifyPassed`
- `contextRefreshId` — monotonic id agents must pass after refresh
- `driftDetected` / `requiresContextRefresh`

## Mutation gate

**Core rule:** If the world changed underneath the agent, DietCode blocks **Edit** and **Destructive** RPCs until context is refreshed.

Blocked responses:

```json
{
  "workspaceDriftRequired": true,
  "workspace": { "...": "workspace.status payload" },
  "blockedMethod": "patch.apply",
  "mode": "workspace_drift_pending"
}
```

Unblock paths:

1. **Refresh context** — `workspace.refreshAnchor` then retry with `contextRefreshId`
2. **Continue anyway** — `workspace.continueAnyway` or `continueAnyway: true` on the mutation
3. Cockpit drives both via bridge HTTP (see below)

Kernel emits `workspace.drift.detected` when a mutation is blocked.

**Layering:** For governed mutations (`taskId` set), the kernel checks coherence **before** drift so agents receive `coherence_mismatch` (precise) rather than `workspaceDriftRequired` (broad). Drift still applies when no task coherence envelope is in play.

## Cockpit

When drift is detected, the cockpit shows:

```text
Workspace changed outside DietCode
Affected files:
- src/foo.ts — changed since agent read it
- package.json — changed after verification

Actions: Refresh context | Cancel task | Continue anyway
```

Bridge endpoints:

| Endpoint | Action |
|----------|--------|
| `GET /api/workspace/status` | Proxy `workspace.status` |
| `POST /api/workspace/refresh-anchor` | `workspace.refreshAnchor` |
| `POST /api/workspace/re-verify` | Re-run `verify.run` with last command (checkpoint 5 — prefer task verify panel) |
| `POST /api/workspace/continue-anyway` | `workspace.continueAnyway` |

Health snapshot (`GET /api/health`) includes `workspaceStatus` and `affectedFiles`.

## Agent bridge

`patch.apply` / `patch.applyBatch` handle `workspaceDriftRequired` like approvals:

1. Poll `workspace.status` until `driftDetected` is false (cockpit refresh or external `workspace.refreshAnchor`)
2. Retry mutation with returned `contextRefreshId`

Supervised tasks: the human refreshes context in the cockpit; the agent bridge unblocks automatically.

## Anchoring

Hashes are tracked when the agent:

- Reads files (`file.read`, `file.readRange`, `file.readAround`)
- Applies patches (`patch.apply` / batch)

`workspace.refreshAnchor` re-reads all tracked paths, clears external-change flags, snapshots git HEAD, and increments `contextRefreshId`.
