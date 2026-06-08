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

End users enable Hermes without a source checkout:

```bash
./scripts/enable-hermes-agent.sh
# or from a built app:
build/DietCode.app/Contents/Resources/bin/dietcode-enable-agent
```

Hermes itself installs to `~/.hermes` on demand — it is never vendored into this repo.
