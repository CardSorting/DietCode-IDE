# task_009: Large file catSmall avoidance

`shell.catSmall` returns partial; use `shell.sedRange` to read target line and patch.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
