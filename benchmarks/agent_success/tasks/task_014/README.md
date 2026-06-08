# task_014: Batch validation failure rollback

One patch in batch fails validation; entire batch rejected, files unchanged.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
