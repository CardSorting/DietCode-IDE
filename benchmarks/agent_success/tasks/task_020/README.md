# task_020: Verify after multi-file mutation

Batch patch two files, then run verify workflow.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
