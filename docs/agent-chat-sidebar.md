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

## Sidebar UX (v1)

- Status: runtime · bridge · Hermes · workspace · last exit
- Transcript: `You:` / `Hermes:` plain text
- Send runs `dietcode-agent-chat` off the main thread
- Stop cancels the active subprocess
- No workspace → “Open a folder first.”

Not in v1: streaming UI, markdown, model picker, persisted history, diff viewer.

## Tests

```bash
make test-dietcode-agent-chat
make verify-agent-chat-sidebar
make verify-hermes-bridge
```

## Live smoke (bounded edit proof)

Proves the installed app path can perform a real Hermes edit through `dietcode_ide` + bridge:

```bash
make smoke-agent-chat-live
```

The smoke harness:

1. Creates a temp workspace with `smoke_probe.py` (`VALUE = 1`)
2. Runs `dietcode-agent-chat --prompt "fix VALUE to 2"`
3. Verifies disk + bridge read show `VALUE = 2`
4. Checks runtime timeline for patch activity
5. Prints a compact transcript and cleans up

Skip live Hermes (CI / offline): `AGENT_CHAT_LIVE=0 make smoke-agent-chat-live` or `--skip-live`.

The smoke harness forces `workspace.openFolder` on the temp directory (bridge switches away from any already-open repo). Progress events emit every 15s while Hermes runs; default timeout is 180s (`AGENT_CHAT_SMOKE_TIMEOUT`).

## Files

| Path | Role |
|------|------|
| `src/platform/macos/MacAgentSidebar.mm` | Sidebar UI |
| `scripts/dietcode_agent_chat.py` | Chat CLI |
| `scripts/dietcode_agent_bundle.py` | Shared bundle resolution |
| `resources/bin/dietcode-agent-chat` | App launcher |
