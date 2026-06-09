# Architecture

> DietCode is a **headless governed mutation kernel**. The control plane is JSON-RPC; the kernel is the sole mutation authority.

Canonical checkpoint map: [checkpoint-model.md](checkpoint-model.md) · Coherence: [coherence-tokens.md](coherence-tokens.md)

## Components

```text
┌─────────────────────────────────────────────────────────┐
│  Agents / harnesses (Python CLI, scripts, CI)           │
│  scripts/dietcode_agent_client.py                       │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON lines + token
┌───────────────────────▼─────────────────────────────────┐
│  dietcode-kernel (C++ / ObjC++)                          │
│  MacControlServer · coherence tokens · approvals        │
│  drift · verify · WorkspaceSession                       │
└───────────────────────┬─────────────────────────────────┘
                        │
                   Workspace on disk
```

## Kernel

| Artifact | Path |
|----------|------|
| Binary | `build/dietcode-kernel` |
| Entry | `src/kernel/main.mm`, `KernelRuntime.mm` |
| RPC server | `src/platform/macos/control/MacControlServer.mm` |
| Coherence | `MacControlCoherenceTokens.mm` |
| Workspace | `src/kernel/workspace/` |
| Socket | `~/.dietcode/control.sock` |

Headless build uses `DietCodeControlWindowBridge` — no AppKit editor required. `safeWorkspacePath` reads from `WorkspaceSession`.

```bash
make kernel
DIETCODE_REPO_ROOT=$(pwd) ./build/dietcode-kernel --ensure-socket
```

## RPC wire format

Requests are single-line JSON:

```json
{
  "id": "uuid",
  "schemaVersion": "1.6.2",
  "method": "patch.apply",
  "params": { },
  "token": "<session.token>"
}
```

Responses: `{ "id", "ok", "result" }` or `{ "id", "ok": false, "error": { "string_code", "message", ... } }`.

## Session and recovery

Kernel recovery store and optional session dir (`DIETCODE_SESSION_DIR`, default `~/.dietcode/session/`):

- Pending approvals (kernel authoritative)
- Bounded event ring buffer
- Recovery RPCs (`recovery.*`)

See [session-recovery.md](session-recovery.md).

## Autonomy and permissions

Default autonomy level: **3 (supervised)**. Destructive RPCs (`patch.apply` with `confirm`, `workspace.openFolder`, etc.) queue `approvalRequired` until resolved via `approval.resolve`.

Permission tiers: Read · Edit · Execute · Destructive. Method catalog: `src/platform/macos/control/services/MacControlMethodCatalog.mm`.

## Coherence layer

When `taskId` is set on reads, the kernel issues coherence tokens. Mutations must include `coherenceTokenId` + `expectedWorkspaceRevision` or receive `coherence_mismatch` before drift checks run.

Harness: `scripts/dietcode_coherence.py` · Tests: `scripts/test_coherence_tokens.py`, `scripts/coherence_recovery_smoke.py`

## Archived surfaces

Cockpit UI, HTTP bridge, TypeScript agent-bridge, and Hermes integrations were experimental product surfaces used to prove the model. They are no longer in the active tree. See [archive-note.md](archive-note.md).

## What is not in this stack

| Item | Role |
|------|------|
| Benchmark harness | Parallel reliability track — not coherence-core |
| BroccoliQ journal | Offline evaluation — noise bucket |
| Cloud / remote kernel | Not supported |

## Related

- [kernel-rpc.md](kernel-rpc.md) — method reference
- [agent-ergonomics.md](agent-ergonomics.md) — agent loop
- [testing.md](testing.md) — release gates
