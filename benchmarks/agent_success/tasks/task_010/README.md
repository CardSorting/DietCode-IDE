# task_010: Large file read avoidance

Avoid full `file.read` on oversize file; use `file.readRange` or `shell.head`.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
