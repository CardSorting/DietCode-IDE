# task_019: Verify after single-file mutation

Patch file then call `verify.status` / bridge `verifyFast` for post-mutation check.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
