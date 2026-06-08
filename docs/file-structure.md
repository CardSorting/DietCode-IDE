# File structure

```text
DietCode-IDE/
├── build/
│   ├── dietcode-kernel          # Headless kernel binary (default product)
│   ├── cockpit-smoke-ws/        # Vertical-slice fixture workspace (generated)
│   └── DietCode.app/            # Optional legacy bundle (make app)
├── cockpit/
│   ├── src/                     # React UI (CheckpointRail, panels, chat)
│   └── server/                  # Bridge (bridge.ts, checkpoints.ts, verifyGate.ts)
├── agent-bridge/                # @dietcode/agent-bridge TypeScript package
├── src/
│   ├── kernel/                  # Kernel entry, WorkspaceSession bridge
│   ├── kernel/workspace/        # Headless file/patch/verify ops
│   └── platform/macos/control/  # MacControlServer JSON-RPC
├── scripts/
│   ├── dietcode_agent_client.py # Python RPC CLI
│   ├── cockpit_vertical_slice.py
│   ├── cockpit_smoke_task.py
│   ├── cockpit_governed_task.py
│   ├── agent_contracts.py       # Frozen contract key sets
│   └── fixtures/
│       └── cockpit_smoke/       # npm-test, make-test, verify-sh
├── legacy_ui/                   # Optional AppKit editor (not cockpit)
├── integrations/                # Hermes plugin sync boundary
└── docs/                        # This documentation set
```

## Kernel control plane

```text
src/platform/macos/control/
├── MacControlServer.mm           # RPC dispatch, auth, autonomy
├── categories/
│   ├── MacControlServer+File.mm
│   ├── MacControlServer+Approval.mm
│   ├── MacControlServer+WorkspaceDrift.mm
│   └── MacControlServer+VerifyGate.mm
└── services/
    ├── MacControlMethodCatalog.mm
    ├── MacControlApprovalService.mm
    └── MacControlWorkspaceState.mm
```

## Cockpit server modules

| File | Role |
|------|------|
| `bridge.ts` | HTTP API + kernel RPC client |
| `taskRunner.ts` | Governed/smoke task processes |
| `checkpoints.ts` | Six-gate snapshot builder |
| `verifyGate.ts` | Verify-before-complete semantics |
| `sessionStore.ts` | Session persistence |
| `verifyCommandResolver.ts` | npm / make / verify.sh |

## Key scripts

| Script | Purpose |
|--------|---------|
| `test_checkpoint_resolver.py` | Verify resolver unit test |
| `test_docs_code_drift.py` | Docs ↔ code contract lock |
| `control_smoke_test.py` | Kernel control smoke |

## Generated / local state

| Path | Purpose |
|------|---------|
| `~/.dietcode/control.sock` | Kernel socket |
| `~/.dietcode/session.token` | RPC auth |
| `~/.dietcode/session/` | Bridge session (or `DIETCODE_SESSION_DIR`) |

## Related

- [architecture.md](architecture.md)
- [testing.md](testing.md)
