# Archive note

DietCode began as a governed mutation experiment with multiple product surfaces. The retained repository is the **kernel/coherence-core** archive — not a shipping IDE or web app.

## Removed experimental surfaces

These directories were used to prove the coherence and checkpoint model in realistic operator workflows. They are no longer part of the active repo:

| Surface | Former role |
|---------|-------------|
| `cockpit/` | React UI + HTTP bridge for governed tasks, approvals, and checkpoint visibility |
| `legacy_ui/` | Optional AppKit editor shell |
| `agent-bridge/` | TypeScript client workflows (`safePatchFile`, session recovery) |
| `integrations/` | Hermes plugin wiring into the bridge and kernel |

They demonstrated that operational coherence, drift layering, approval gates, and verify-before-complete semantics work end-to-end when a human or agent can see checkpoint state. That proof informed the frozen **coherence-core-v0.1** baseline.

## What remains

| Artifact | Purpose |
|----------|---------|
| `dietcode-kernel` | Headless mutation authority |
| `src/platform/macos/control/` | JSON-RPC, coherence token registry, drift/approval/verify enforcement |
| `scripts/dietcode_agent_client.py` | Python RPC CLI for agents and harnesses |
| `scripts/dietcode_coherence.py` | Shared coherence helpers for smoke and agent loops |
| Coherence tests + fixtures | `test_coherence_tokens.py`, `coherence_recovery_smoke.py`, `fixtures/coherence_recovery/` |
| Coherence docs | [coherence-tokens.md](coherence-tokens.md), [workspace-drift.md](workspace-drift.md), [kernel-rpc.md](kernel-rpc.md) |

## Validation baseline

```bash
make coherence-core-v0.1
```

Tag when green: **coherence-core-v0.1**.

## Related

- [README.md](../README.md)
- [testing.md](testing.md)
- [checkpoint-model.md](checkpoint-model.md)
