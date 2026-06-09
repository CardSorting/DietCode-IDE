# File structure

```text
DietCode-IDE/
├── ARCHIVE.md                   # Removed vs retained index
├── build/
│   └── dietcode-kernel          # Headless kernel binary (default product)
├── src/
│   ├── kernel/                  # Kernel entry, WorkspaceSession bridge
│   ├── kernel/workspace/        # Headless file/patch/verify ops
│   ├── platform/macos/control/  # MacControlServer JSON-RPC + coherence
│   ├── filesystem/              # FileService, GitService (kernel deps)
│   └── domain/control/          # Shared control-plane types
├── scripts/
│   ├── dietcode_agent_client.py # Python RPC CLI
│   ├── dietcode_coherence.py    # Coherence helpers for harnesses
│   ├── test_coherence_tokens.py # Live coherence token tests
│   ├── coherence_recovery_smoke.py
│   ├── agent_contracts.py       # Frozen contract key sets
│   └── fixtures/
│       ├── coherence_recovery/  # Recovery smoke workspace
│       ├── recovery/            # Error recovery hint fixtures
│       └── release/             # Internal namespace fixtures
├── benchmarks/                  # Research archive (agent_success — bridge-dependent)
└── docs/                        # Coherence model + kernel reference
```

## Kernel control plane

```text
src/platform/macos/control/
├── MacControlServer.mm           # RPC dispatch, auth, autonomy
├── categories/
│   ├── MacControlServer+File.mm
│   ├── MacControlServer+Approval.mm
│   ├── MacControlServer+WorkspaceDrift.mm
│   ├── MacControlServer+Coherence.mm
│   └── MacControlServer+VerifyGate.mm
└── services/
    ├── MacControlMethodCatalog.mm
    ├── MacControlApprovalService.mm
    ├── MacControlCoherenceTokens.mm
    └── MacControlWorkspaceState.mm
```

## Key scripts

| Script | Purpose |
|--------|---------|
| `dietcode_agent_client.py` | JSON-RPC CLI — primary agent entry point |
| `dietcode_coherence.py` | Token helpers, recovery retry loop |
| `test_coherence_tokens.py` | Live kernel coherence enforcement |
| `coherence_recovery_smoke.py` | End-to-end recovery vertical |
| `test_docs_code_drift.py` | Docs ↔ code contract lock |
| `control_smoke_test.py` | Kernel control smoke |

## Generated / local state

| Path | Purpose |
|------|------|
| `~/.dietcode/control.sock` | Kernel socket |
| `~/.dietcode/session.token` | RPC auth |
| `~/.dietcode/session/` | Recovery store (or `DIETCODE_SESSION_DIR`) |

## Archived surfaces

Cockpit, legacy AppKit UI, agent-bridge, and Hermes integrations were removed from the active tree. See [archive-note.md](archive-note.md).

## Related

- [architecture.md](architecture.md)
- [testing.md](testing.md)
