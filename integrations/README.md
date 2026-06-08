# Integrations

Optional companion integrations shipped with DietCode. **Not part of the IDE core.**

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

DietCode now ships a **bundled agent integration artifact**, not merely a benchmark bridge.

End users enable Hermes without a source checkout:

```bash
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --doctor
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --dry-run
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent --uninstall
build/DietCode.app/Contents/Resources/bin/dietcode-agent-chat \
  --workspace /path/to/project --prompt "inspect this project"
```

Agent Chat sidebar in the IDE uses `dietcode-agent-chat` for real Hermes sessions.

Trust guarantees:

- Works from `/Applications/DietCode.app`, `~/Applications/DietCode.app`, and `build/DietCode.app`
- Backs up `~/.hermes/config.yaml`, `.env`, and the plugin before writes
- Prints an exact JSON change log of env/config/plugin updates
- Version manifest: `dietcode-agent-bundle.manifest.json`

Hermes itself installs to `~/.hermes` on demand — it is never vendored into this repo.
