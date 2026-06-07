# Runtime Release Notes — Template

Copy this file per release (e.g. `docs/releases/agent-runtime-1.0.0.md`).

```markdown
# Agent Runtime Release YYYY-MM-DD

## Contract inventory version

- **contractInventory:** X.Y.Z (was: A.B.C)

## Changed contracts

- C-RPC-XX: ...
- C-SAFETY-XX: ...

## Error codes

### Added

- `new_code` — numeric N — meaning

### Removed (breaking)

- `old_code` — migration: ...

## Limits

| Constant | Old | New |
|----------|-----|-----|
| kMaxActiveConnections | 8 | 8 |

## Diagnostics fields

### Added (stable / experimental)

- `error.new_field` — STABILITY: experimental

### Removed

- ...

## Makefile targets

### Added

- `make new-target`

### Deprecated

- `make old-target` — use `make new-target`

## Migration notes

1. ...
2. ...

## Verification commands run

\`\`\`bash
make release-check-agent-runtime
make verify-agent-runtime
python3 scripts/dietcode_agent_client.py --emit-config --json
python3 scripts/dietcode_agent_client.py --diagnose --json
rg 'RELEASE:|STABILITY:' src/ scripts/ docs/
git diff src/ scripts/ docs/ Makefile
\`\`\`

## Rollback

See [Release Upgrade & Rollback](release-upgrade-rollback.md).
```
