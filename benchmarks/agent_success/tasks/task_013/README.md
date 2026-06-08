# task_013: Batch patch rollback on stale file

Batch apply fails when one file is mutated; verify no partial writes.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
