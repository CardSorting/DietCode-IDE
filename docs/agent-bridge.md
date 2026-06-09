# Agent Bridge

Stable TypeScript layer between external agents and the DietCode kernel.

```text
agent → @dietcode/agent-bridge → kernel RPC → workspace
```

Agents should prefer bridge **workflows** (`safePatchFile`, `awaitApproval`, `awaitWorkspaceDrift`) over raw RPC. The kernel remains the sole mutation authority.

```bash
make agent-bridge-fast
make test-agent-bridge-fast
```

## Layout

| Path | Role |
|------|------|
| `agent-bridge/src/` | Workflows, adapters, transport |
| `agent-bridge/dist/` | Compiled output |
| `build/resources/agent-bridge/` | Packaged into app bundle |

CLI launcher: `build/resources/bin/dietcode-agent-client` (when `make app`).

## Core workflows

| Workflow | Checkpoint |
|----------|------------|
| `connect` / `ping` | Transport |
| `safePatchFile` | 3 Approval → 4 Mutation |
| `awaitWorkspaceDrift` | 2 Drift |
| `awaitApproval` | 3 Approval |

When `DIETCODE_TASK_ID` is set, the bridge injects `taskId` into destructive RPC params and
enables one automatic coherence recovery retry on `safePatchFile` (re-read → regenerate patch).

Hermes `dietcode_ide(action='patch')` routes through `run_safe_file_patch` with the same behavior.
Headless harnesses may set `DIETCODE_HEADLESS_AUTO_APPROVE=1` for governed approval gates.

## Public API (summary)

| Export | Purpose |
|--------|---------|
| `DietCodeBridge` | Connection + `call(method, params)` |
| `safePatchFile` | validate → apply with approval/drift/coherence recovery |
| `shellPwd` / `shellRg` / `shellSedRange` / `shellCatSmall` | Bounded shell (see [agent-shell-tooling.md](agent-shell-tooling.md)) |

Bridge errors include `recoveryHint` aligned with [error-codes.md](error-codes.md).

## Hermes plugin

Hermes calls `dietcode_ide` tools → bridge CLI → kernel. Plugin source: `integrations/hermes-dietcode-plugin/`.

Not required for `make checkpoint-core`. See [integrations.md](integrations.md).

## Packaging with app bundle

```bash
make app
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
```

Manifest: `resources/dietcode-agent-bundle.manifest.json`.

## Testing

```bash
make test-agent-bridge-fast       # dist/tests/*.test.js
make test-agent-bridge-authority  # authority boundary tests
```

## Python alternative

`scripts/dietcode_agent_client.py` — direct RPC for harnesses and debugging. Use bridge for agent product code.

## Related

- [kernel-rpc.md](kernel-rpc.md)
- [agent-ergonomics.md](agent-ergonomics.md)
- [governed-tasks.md](governed-tasks.md)
