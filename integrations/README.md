# Integrations

> **Optional.** The Cockpit checkpoint loop does not require Hermes or the legacy app.

[← Doc index](../docs/README.md) · [integrations.md](../docs/integrations.md) · [← README](../README.md#optional-integrations)

## I want to…

| I want to… | Start here |
|------------|------------|
| **Use Hermes with DietCode** | [Enable agent](#enable-hermes) below |
| **Run a one-shot agent chat** | `dietcode-agent-chat` — [CLI](#cli-reference) |
| **Prove live edit authority** | `make smoke-agent-chat-live` |
| **Stay on Cockpit only** | [getting-started.md](../docs/getting-started.md) — skip this folder |

---

## What ships here

| Path | Role |
|------|------|
| `hermes-dietcode-plugin/` | Hermes Agent plugin (`dietcode_ide`, auto-connect, write routing) |

Maintainers sync from the Hermes plugin checkout:

```bash
./scripts/sync-hermes-plugin.sh
```

`make app` copies `hermes-dietcode-plugin/` into:

```text
DietCode.app/Contents/Resources/integrations/hermes/dietcode/
```

DietCode ships a **bundled agent integration artifact**, not merely a benchmark bridge.

---

## Enable Hermes

End users enable Hermes without a source checkout:

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --dry-run
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --uninstall
```

The Agent Chat sidebar in the legacy IDE uses `dietcode-agent-chat` for Hermes sessions. This path is **not** part of `checkpoint-core`.

---

## CLI reference

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project --prompt "inspect this project"
```

---

## Live proof (four authority layers)

```bash
make smoke-agent-chat-live
make test-mutation-authority
make test-diff-authority
make test-verification-authority
```

Separate from `make cockpit-smoke` / `make checkpoint-core`. Research context: [AGENT_RUNTIME_RELIABILITY.md](../AGENT_RUNTIME_RELIABILITY.md).

---

## Trust guarantees

- Works from `/Applications/DietCode.app`, `~/Applications/DietCode.app`, and `build/DietCode.app`
- Backs up `~/.hermes/config.yaml`, `.env`, and the plugin before writes
- Prints an exact JSON change log of env/config/plugin updates
- Version manifest: `dietcode-agent-bundle.manifest.json`
- Agent Chat: workspace match before Hermes; bridge-only mutation telemetry; persisted diff + verify logs outside workspace

Hermes itself installs to `~/.hermes` on demand — it is never vendored into this repo.
