# task_015: Semantic search recovery to literal

`search.semantic` returns `semantic_disabled`; recover via `search.literal`.

## Fixture layout

- `before/` — workspace state before the agent acts
- `expected.patch` — golden unified diff the reference workflow applies
- `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
- `metadata.json` — runner workflow binding and expectations
