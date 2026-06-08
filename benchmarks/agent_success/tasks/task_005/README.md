# task_005: Stale content recovery (raw RPC)

Validate patch, mutate file externally, recover from `stale_content`, revalidate and apply.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
