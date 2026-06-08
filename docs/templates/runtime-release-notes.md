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

## Agent runtime pass impact (if applicable)

| Pass | Harness | Doc to update |
|------|---------|---------------|
| I — Grep | `make test-grep-diff-tooling` | `agent-tooling.md` |
| II — Determinism | `make test-runtime-determinism` | `runtime-invariants.md` |
| III — Transaction | `make test-transaction-kernel` | `agent-runtime-audit.md` |
| IV — Harness | `make test-harness-realism` | `runtime-invariants.md` |
| V — Retrieval | `make test-deterministic-retrieval` | `deprecation-policy.md` |
| VI — Failure traps | `make test-agent-workflow-smoke` | `error-codes.md`, `headless-agent-control.md` |

## Verification commands run

\`\`\`bash
make verify-agent-runtime-full
make release-check-agent-runtime
make test-docs-code-drift
python3 scripts/dietcode_agent_client.py --emit-config --json
python3 scripts/dietcode_agent_client.py --diagnose --json
rg 'RELEASE:|STABILITY:|CONTRACT:' src/ scripts/ docs/
git diff src/ scripts/ docs/ Makefile
\`\`\`

## Rollback

See [Release Upgrade & Rollback](release-upgrade-rollback.md).
```
