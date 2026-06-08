# task_008: Symlink escape read rejection

Detect symlink escape on `file.stat`; read/patch only in-workspace real file.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
