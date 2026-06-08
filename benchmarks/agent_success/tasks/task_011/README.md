# task_011: Shell rg to sedRange patch

`shell.rg` locates marker; `shell.sedRange` gathers context; patch applied.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
