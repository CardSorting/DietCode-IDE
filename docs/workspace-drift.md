# Workspace drift guardrails

**Checkpoint 2 · Drift** — *Did the workspace change underneath the agent?*

Canonical loop: [checkpoint-model.md](./checkpoint-model.md).

DietCode tracks workspace **state validity** so the agent cannot mutate files after the world changed underneath it.

## Kernel RPCs

| RPC | Permission | Purpose |
|-----|------------|---------|
| `workspace.status` | Read | Full drift snapshot |
| `workspace.snapshot` | Read | Point-in-time file hashes |
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

Kernel emits `workspace.drift.detected` when a mutation is blocked.

**Layering:** For governed mutations (`taskId` set), the kernel checks coherence **before** drift so agents receive `coherence_mismatch` (precise) rather than `workspaceDriftRequired` (broad). Drift still applies when no task coherence envelope is in play. See [coherence-tokens.md](./coherence-tokens.md).

## Agent loop

`patch.apply` / `patch.applyBatch` handle `workspaceDriftRequired` in harnesses:

1. Call `workspace.refreshAnchor`
2. Poll `workspace.status` until `driftDetected` is false
3. Retry mutation with returned `contextRefreshId`

Python helper: `scripts/dietcode_coherence.py` (`_complete_after_workspace_drift`).

## Anchoring

Hashes are tracked when the agent:

- Reads files (`file.read`, `file.readRange`, `file.readAround`, `file.readBatch`)
- Applies patches (`patch.apply` / batch)

`workspace.refreshAnchor` re-reads all tracked paths, clears external-change flags, snapshots git HEAD, and increments `contextRefreshId`.
