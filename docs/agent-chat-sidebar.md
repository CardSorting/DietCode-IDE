# Agent Chat Sidebar

Native right-side Agent Chat in DietCode (AppKit). Real end-to-end path:

```text
Sidebar → dietcode-agent-chat → Hermes → dietcode_ide → agent bridge → DietCode runtime
```

DietCode ships a **bundled agent integration artifact**, not merely a benchmark bridge.

## Open the sidebar

- **View → Toggle Agent Sidebar**
- **⌘⇧A**

## User flow (installed app)

```bash
/Applications/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
/Applications/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project \
  --prompt "inspect this project"
```

## Bundled CLIs

| CLI | Role |
|-----|------|
| `dietcode-enable-agent` | Install plugin, backup config, doctor |
| `dietcode-agent-chat` | Bounded Hermes chat with `dietcode_ide` guardrails |

Both live in `DietCode.app/Contents/Resources/bin/`.

## `dietcode-agent-chat` contract

```bash
dietcode-agent-chat --workspace /path --prompt "request" --format text
dietcode-agent-chat --doctor --format json
dietcode-agent-chat --version
```

Readiness checks (fail early):

1. `dietcode-enable-agent --doctor`
2. Hermes + plugin present
3. Bridge CLI in app bundle
4. DietCode runtime socket (`--ensure-socket`)
5. `dietcode_ide verify` via bridge CLI

Hermes receives a strict instruction to use `dietcode_ide` only — no raw writes, no benchmark fixture reads.

## Workspace authority

Requested workspace, runtime workspace, Hermes env, and bridge `--workspace` must agree before chat starts.

`dietcode-agent-chat --doctor --workspace /path --format json` includes:

```json
{
  "workspaceAuthority": {
    "requestedWorkspace": "/tmp/dietcode-smoke-...",
    "runtimeWorkspaceBefore": "/Users/.../DietCode-IDE",
    "runtimeWorkspaceAfter": "/tmp/dietcode-smoke-...",
    "workspaceRootObserved": "/tmp/dietcode-smoke-...",
    "workspaceSwitchSucceeded": true,
    "workspaceMatch": true
  }
}
```

If `requestedWorkspace != workspaceRootObserved` after switch, chat exits before Hermes:

```text
Workspace mismatch:
requested: <path>
runtime:   <path>
Refusing to start agent chat against the wrong workspace.
```

## Mutation authority

Approved mutation path:

```text
DietCode sidebar → dietcode-agent-chat → Hermes → dietcode_ide.patch → agent bridge → DietCode runtime safe patch/apply
```

After each chat run, `dietcode-agent-chat` audits workspace file hashes against bridge patch telemetry (`mutation.patch.applied` events). Telemetry is written outside the workspace (`~/.dietcode/agent-chat/events/<run-id>.jsonl`).

```json
{
  "mutationAuthority": {
    "mode": "bridge_only",
    "bridgePatchCount": 1,
    "rawWriteSuspected": false,
    "mutatedFiles": ["smoke_probe.py"],
    "evidence": []
  }
}
```

Modes:

| `mode` | Meaning |
|--------|---------|
| `bridge_only` | Every changed file is explained by bridge patch telemetry |
| `no_mutation` | No file changes observed |
| `unknown` | Files changed but bridge telemetry is incomplete |
| `violated` | Changes outside the approved bridge path |

Enforcement (smoke / CI):

```bash
dietcode-agent-chat --workspace /path --prompt "..." --enforce-mutation-authority
```

Exits nonzero when `mode` is `unknown` or `violated`.

**Trust guarantees**

- Workspace authority enforced before chat
- Mutation authority audited after chat
- Live smoke proves real bridge-mediated mutation

**Limitations**

- Not full OS-level sandboxing
- Raw-write detection is best-effort unless Hermes tool permissions are locked down
- Bridge telemetry is authoritative only for DietCode-mediated patches

**Invariant:** a successful agent edit is not trusted unless changed files are explained by bridge patch telemetry.

## Sidebar UX (v1)

- Status: runtime · bridge · Hermes · workspace requested/active · mutation path · last exit
- Transcript: `You:` / `Hermes:` plain text
- Send runs `dietcode-agent-chat` off the main thread
- Stop cancels the active subprocess
- No workspace → “Open a folder first.”
- Workspace mismatch → “Workspace mismatch — agent disabled” (Send disabled)
- Mutation path: Bridge verified / No mutation / Unknown — review run / Violation — agent disabled
- Mutation violation → Send disabled until workspace changes or status refresh clears state; changed files and evidence appear in transcript

Not in v1: streaming UI, markdown, model picker, persisted history, diff viewer.

## Tests

```bash
make test-dietcode-agent-chat
make test-agent-chat-workspace-switch
make test-mutation-authority
make verify-agent-chat-sidebar
make verify-hermes-bridge
```

## Live smoke (bounded edit proof)

Proof command for **sidebar/chat → Hermes → dietcode_ide → bridge → runtime → real file mutation**:

```bash
make smoke-agent-chat-live
```

Proves the installed app path can perform a real Hermes edit through `dietcode_ide` + bridge:

The smoke harness:

1. Creates a temp workspace with `smoke_probe.py` (`VALUE = 1`)
2. Runs `dietcode-agent-chat --prompt "fix VALUE to 2"`
3. Verifies disk + bridge read show `VALUE = 2`
4. Checks runtime timeline for patch activity
5. Asserts `mutationAuthority.mode == bridge_only`, `bridgePatchCount >= 1`, `smoke_probe.py` in `mutatedFiles`, `rawWriteSuspected == false`
6. Prints a compact transcript and cleans up

Skip live Hermes (CI / offline): `AGENT_CHAT_LIVE=0 make smoke-agent-chat-live` or `--skip-live`.

The smoke harness forces `workspace.openFolder` on the temp directory (bridge switches away from any already-open repo). Progress events emit every 15s while Hermes runs; default timeout is 180s (`AGENT_CHAT_SMOKE_TIMEOUT`).

## Files

| Path | Role |
|------|------|
| `src/platform/macos/MacAgentSidebar.mm` | Sidebar UI |
| `scripts/dietcode_agent_chat.py` | Chat CLI |
| `scripts/dietcode_agent_bundle.py` | Shared bundle resolution |
| `scripts/dietcode_mutation_authority.py` | Post-run mutation audit |
| `agent-bridge/src/telemetry/mutationTelemetry.ts` | Bridge patch event log |
| `resources/bin/dietcode-agent-chat` | App launcher |
