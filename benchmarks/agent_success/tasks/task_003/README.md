# task_003: Multi-file sequential patch

Patch `pkg/a.py` and `pkg/b.py` sequentially after path search.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
