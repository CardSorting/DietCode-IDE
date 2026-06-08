# Integrations (optional)

The **checkpoint control loop** does not require Hermes or the legacy AppKit app.

```bash
make checkpoint-core    # proves kernel + cockpit + bridge — no Hermes
```

## Hermes Agent

Hermes is an optional companion agent runtime. DietCode ships a plugin sync boundary:

| Path | Role |
|------|------|
| `integrations/hermes-dietcode-plugin/` | Maintainer copy of Hermes `dietcode` plugin |
| `build/.../integrations/hermes/dietcode/` | Bundled into `DietCode.app` |

Enable for end users:

```bash
make app
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
```

Maintainer sync:

```bash
./scripts/sync-hermes-plugin.sh
```

Full detail: [integrations/README.md](../integrations/README.md).

## Governed Hermes tasks vs smoke tasks

| Path | Entry | Purpose |
|------|-------|---------|
| Cockpit `supervised` / `trusted` | `cockpit_governed_task.py` | Real Hermes agent in governed loop |
| Cockpit `smoke` | `cockpit_smoke_task.py` | Deterministic checkpoint proof |
| `smoke-agent-chat-live` | `smoke_agent_chat_live.py` | Hermes bounded edit + four authorities |

Only `smoke` mode is in `checkpoint-core`. Hermes smoke is a separate make target.

## Agent chat bundle

`dietcode-agent-chat` runs bounded Hermes sessions with workspace/mutation/diff/verification authorities. Uses the same kernel and bridge as governed tasks but through the legacy sidebar UI.

Not required for cockpit checkpoint validation.

## When to use what

| Goal | Command |
|------|---------|
| Freeze checkpoint baseline | `make checkpoint-core` |
| Develop cockpit UI | `cd cockpit && npm run dev` |
| Test Hermes + kernel | `make smoke-agent-chat-live` |
| Adversarial benchmarks | `make benchmark-agent-success-fast` |
