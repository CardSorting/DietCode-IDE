# task_018: Truncated workspace grep handling

Handle `truncated: true` on `workspace.grep`; narrow include glob and retry.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
