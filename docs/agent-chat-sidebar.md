# Agent Chat Sidebar

Native right-side Agent Chat in DietCode (AppKit). Real end-to-end path:

```text
Sidebar → dietcode-agent-chat → Hermes → dietcode_ide → agent bridge → DietCode runtime
```

DietCode ships a **bundled agent integration artifact**, not merely a benchmark bridge.

Agent Chat is **auditable** — not just a chat shell. Each run emits four authority layers that together answer: *did the agent edit the right workspace, through the approved path, with an inspectable diff, and pass executable verification afterward?*

## Trust loop (four authorities)

| Layer | When | Invariant |
|-------|------|-----------|
| **Workspace authority** | Before Hermes | `requestedWorkspace == workspaceRootObserved` |
| **Mutation authority** | After Hermes | Changed files explained by bridge patch telemetry |
| **Diff authority** | After mutation audit | Visible diff changed set == mutation reported files |
| **Verification authority** | After diff audit | Executable verify runs and passes after final mutation |

```text
open folder
  → workspace authority (fail fast on mismatch)
  → Hermes + dietcode_ide.patch
  → mutation authority (bridge telemetry vs disk)
  → diff authority (unified diff vs mutation set)
  → verification authority (verify.sh after mutation)
  → sidebar status + persisted run artifacts
```

Run artifacts (never written inside the workspace):

```text
~/.dietcode/agent-chat/runs/<run_id>/
  diff.patch
  verify.stdout.log
  verify.stderr.log
  verification.json
```

Bridge patch telemetry (ephemeral per run, outside workspace):

```text
~/.dietcode/agent-chat/events/<run_id>.jsonl
```

The difference between “agent chat exists” and “agent chat is auditable” is this loop.

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
dietcode-agent-chat --doctor --workspace /path --format json
dietcode-agent-chat --version

# Authority enforcement (smoke / CI)
dietcode-agent-chat --workspace /path --prompt "..." \
  --enforce-mutation-authority \
  --enforce-verification-authority \
  --verify-command "./verify.sh" \
  --format json
```

| Flag | Role |
|------|------|
| `--workspace` | Required for chat; drives workspace authority |
| `--prompt` | User request passed to Hermes |
| `--format text\|json` | Text transcript or full authority payload |
| `--doctor` | Readiness only (no Hermes) |
| `--enforce-mutation-authority` | Exit 11 if mutation authority is `unknown` or `violated` |
| `--enforce-verification-authority` | Exit 12 if verification fails or does not run |
| `--verify-command` | Override verify command (default: `./verify.sh` if present) |
| `--max-turns` | Hermes turn budget (default 25) |
| `--app-bundle` | Explicit `DietCode.app` path |

After a successful chat, `--format json` includes all four authorities plus `runId`:

```json
{
  "ok": true,
  "action": "chat",
  "runId": "abc123",
  "workspaceAuthority": { "workspaceMatch": true },
  "mutationAuthority": { "mode": "bridge_only", "mutatedFiles": ["src/foo.py"] },
  "diffAuthority": { "matchesMutationAuthority": true, "changedFiles": ["src/foo.py"] },
  "verificationAuthority": { "executed": true, "passed": true, "exitCode": 0 }
}
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

**Invariant:** a successful agent edit is not trusted unless changed files are explained by bridge patch telemetry.

## Diff authority

After each chat run, a unified diff is collected and stored outside the workspace:

```text
~/.dietcode/agent-chat/runs/<run_id>/diff.patch
```

Chat JSON includes:

```json
{
  "diffAuthority": {
    "diffFile": "/Users/you/.dietcode/agent-chat/runs/abc123/diff.patch",
    "changedFiles": ["smoke_probe.py"],
    "matchesMutationAuthority": true
  }
}
```

`matchesMutationAuthority` is true when `diffAuthority.changedFiles` equals `mutationAuthority.mutatedFiles`.

The sidebar exposes **View Diff** (opens the stored patch) and reports diff authority in status/transcript.

## Verification authority

After mutation and diff authority complete, executable verification runs for the workspace.

Verification order:

1. `./verify.sh` if present in the workspace
2. fallback from `DIETCODE_AGENT_CHAT_FALLBACK_VERIFY` (optional)
3. explicit `--verify-command` override

Artifacts per run (outside workspace):

```text
~/.dietcode/agent-chat/runs/<run_id>/
  diff.patch
  verify.stdout.log
  verify.stderr.log
  verification.json
```

```json
{
  "verificationAuthority": {
    "verifyCommand": "./verify.sh",
    "executed": true,
    "exitCode": 0,
    "passed": true,
    "stdoutFile": "/Users/you/.dietcode/agent-chat/runs/abc123/verify.stdout.log",
    "stderrFile": "/Users/you/.dietcode/agent-chat/runs/abc123/verify.stderr.log",
    "checkedAfterMutation": true,
    "durationMs": 12
  }
}
```

Enforcement (smoke / CI):

```bash
dietcode-agent-chat --workspace /path --prompt "..." --enforce-verification-authority
```

Verification runs **after** mutation and diff authority complete — never before.

**Invariant:** a trusted agent mutation is incomplete unless executable verification runs successfully after the final mutation step.

Optional fallback when `verify.sh` is absent: set `DIETCODE_AGENT_CHAT_FALLBACK_VERIFY` to a shell command.

## Sidebar UX (v1)

- Status: runtime · bridge · Hermes · workspace requested/active · mutation path · verification · last exit
- Transcript: `You:` / `Hermes:` plain text
- Send runs `dietcode-agent-chat` off the main thread
- Stop cancels the active subprocess
- No workspace → “Open a folder first.”
- Workspace mismatch → “Workspace mismatch — agent disabled” (Send disabled)
- Mutation path: Bridge verified / No mutation / Unknown — review run / Violation — agent disabled
- Mutation violation → Send disabled until workspace changes or status refresh clears state; changed files and evidence appear in transcript
- **View Diff** opens the last run’s `diff.patch` from `~/.dietcode/agent-chat/runs/<run_id>/`
- **View Verify Log** opens persisted `verify.stdout.log` / `verify.stderr.log`
- Verification failed → Send stays enabled (retry allowed); status marks workspace unverified

Not in v1: streaming UI, markdown, model picker, persisted history, in-app diff viewer.

## Limitations (all four layers)

- **Workspace:** relies on runtime `workspace.openFolder`; not a sandbox boundary
- **Mutation:** raw-write detection is best-effort; bridge telemetry is authoritative only for DietCode-mediated patches
- **Diff:** text-file snapshot scope matches mutation manifest (binary/large files may differ)
- **Verification:** quality depends on workspace `verify.sh` or override; not formal correctness proof

## Tests and release ladder

Unit / contract tests:

```bash
make test-dietcode-agent-chat
make test-agent-chat-workspace-switch
make test-mutation-authority
make test-diff-authority
make test-verification-authority
make verify-agent-chat-sidebar
```

Hermes + bridge integration ladder (`make verify-hermes-bridge`):

```bash
make verify-hermes-bridge   # includes all authority unit tests + sidebar verify
```

Full agent runtime ladder (`make verify-agent-runtime-full`):

```bash
make verify-agent-runtime-full   # includes test-verification-authority + smoke-agent-chat-live
```

`verify-hermes-bridge` and `verify-agent-runtime-full` enforce all four authorities before release.

## Live smoke (bounded edit proof)

Proof command for **sidebar/chat → Hermes → dietcode_ide → bridge → runtime → real file mutation**:

```bash
make smoke-agent-chat-live
```

Proves the installed app path can perform a real Hermes edit through `dietcode_ide` + bridge:

The smoke harness:

1. Creates a temp workspace with `smoke_probe.py` (`VALUE = 1`) and executable `verify.sh`
2. Asserts workspace authority (`workspaceMatch == true`)
3. Runs Hermes via `dietcode-agent-chat` prompt to fix `VALUE` to `2`
4. Asserts mutation authority (`mode == bridge_only`, `bridgePatchCount >= 1`, `smoke_probe.py` in `mutatedFiles`)
5. Asserts diff authority (`matchesMutationAuthority == true`, `smoke_probe.py` in `diff.patch`)
6. Asserts verification authority (`executed`, `passed`, `checkedAfterMutation`; logs exist)
7. Verifies disk + bridge read show `VALUE = 2` and runtime timeline mentions patch activity
8. Prints a compact transcript and cleans up

Skip live Hermes (CI / offline): `AGENT_CHAT_LIVE=0 make smoke-agent-chat-live` or `--skip-live`.

The smoke harness forces `workspace.openFolder` on the temp directory (bridge switches away from any already-open repo). Progress events emit every 15s while Hermes runs; default timeout is 180s (`AGENT_CHAT_SMOKE_TIMEOUT`).

## Files

| Path | Role |
|------|------|
| `src/platform/macos/MacAgentSidebar.mm` | Sidebar UI |
| `scripts/dietcode_agent_chat.py` | Chat CLI |
| `scripts/dietcode_agent_bundle.py` | Shared bundle resolution |
| `scripts/dietcode_mutation_authority.py` | Post-run mutation audit |
| `scripts/dietcode_diff_authority.py` | Post-run unified diff audit |
| `scripts/dietcode_verification_authority.py` | Post-mutation executable verification |
| `agent-bridge/src/telemetry/mutationTelemetry.ts` | Bridge patch event log |
| `resources/bin/dietcode-agent-chat` | App launcher |
