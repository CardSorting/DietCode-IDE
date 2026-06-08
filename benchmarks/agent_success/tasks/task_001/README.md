# task_001: Literal search to single-file patch

Find `TASK_001_MARKER` via `search.literal`, inspect with `file.stat`, validate and apply patch.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
