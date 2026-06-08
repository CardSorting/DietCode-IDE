# task_006: Stale content recovery (bridge safe patch)

Same stale recovery pattern; Mode B uses `safePatchFile` stale envelope.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
