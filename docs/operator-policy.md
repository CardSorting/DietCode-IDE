# Operator Policy (Local Control Boundaries)

Plain-text classification of DietCode RPC operations for safe local operation.

```bash
rg 'permission.*Destructive|permission.*Execute|READ_METHODS' src/ scripts/ docs/
```

---

## Policy tiers

| Tier | Risk | Server permission | Examples |
|------|------|-------------------|----------|
| **Safe read** | None — inspect only | `Read` | `rpc.ping`, `file.read`, `workspace.grep`, `diagnostics.list` |
| **Bounded mutation** | Workspace edits with validation | `Edit` | `patch.validate`, `editor.insert`, `buffers.snapshot` |
| **Destructive** | Irreversible or broad state change | `Destructive` | `patch.apply`, `git.commit`, `git.discard`, `changes.revertFile` |
| **External process** | Runs shell/tools | `Execute` | `verify.run`, `terminal.run`, `language.lint` |
| **Privileged diagnostics** | Local-only, no RPC mutation | N/A (client) | `--diagnose`, `capture_failure_bundle.py` |

---

## Agent-safe deterministic surface (Pass V)

Autonomous agents should use methods listed in `tool.capabilities.agentSafeMethods` only. Quarantined or internal surfaces are excluded:

| Class | Examples | Policy |
|-------|----------|--------|
| Agent-safe read | `workspace.grep`, `search.literal`, `search.references`, `tool.registry` | Safe read — deterministic, no ranking |
| Quarantined | `search.semantic`, `analysis.searchRanked` | Returns 4008 — use replacements |
| Internal | `analysis.*`, `language.*`, `chip.*`, `combo.*` | Not in `tool.registry` |

```bash
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
```

See [Agent Runtime Audit](agent-runtime-audit.md).

---

## Safe read operations

- All methods in client `READ_METHODS` (grep: `READ_METHODS` in `dietcode_agent_client.py`)
- Catalog permission `Read`
- No `dryRun` required; idempotent; no workspace writes

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.ping
python3 scripts/dietcode_agent_client.py --list-methods --compact
```

---

## Bounded mutation operations

- Permission `Edit` without `Destructive`
- Prefer `patch.validate` / `patch.hunks` before `patch.apply`
- Use `dryRun: true` when supported (`patch.applyBatch`, recovery prune)

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json patch.validate --params-file patch.json
```

---

## Destructive operations

Fixture anchor list: `scripts/fixtures/safety/destructive_methods.json`

| Method | Requires | Notes |
|--------|----------|-------|
| `patch.apply` | `confirm: true` for large patches | Validates before write |
| `patch.applyBatch` | `confirm` / `dryRun` | Batch limit `kMaxBatchPatchCount` |
| `git.commit` | User confirmation in UI (non-headless) | Writes git state |
| `git.discard` | Destructive tier | Reverts working tree |
| `changes.revertFile` | Destructive tier | Per-file revert |
| `workspace.openFolder` | Destructive tier | Changes workspace root |

Server may prompt for destructive confirmation unless headless/autonomy allows.

```bash
rg 'isDestructiveRequestSafe|permission_denied' src/platform/macos/control/MacControlServer.mm
```

---

## External process operations

Execute-tier methods spawn or drive external processes:

- `verify.run` — build/test commands (allowlist)
- `terminal.run` — shell commands in integrated terminal
- `language.lint` / `language.format` — LSP/tooling
- `task.runLoop` / `task.step` — multi-step agent tasks

Always pass explicit `command` / `steps`; never rely on implicit defaults.

```bash
python3 scripts/dietcode_agent_client.py --describe verify.run --compact
```

---

## Local-only diagnostics

Safe to run without mutating workspace:

```bash
python3 scripts/dietcode_agent_client.py --diagnose --json
python3 scripts/dietcode_agent_client.py --status --compact
make test-runtime-safety
```

Output is redacted per `scripts/runtime_safety.py` — no token contents, secrets masked.

---

## How to verify destructive classification

```bash
python3 -c "from scripts.runtime_safety import extract_method_permissions; import json; print(json.dumps(extract_method_permissions(), indent=2))"
make test-runtime-safety | rg destructive
```

---

## Intentionally not added

- Role-based access control beyond session token + permission tier
- Per-method interactive consent dialogs for every mutation
- Cloud policy engine or external authorization service
- Automatic method blocking based on ML/heuristics

---

## Related docs

- [Agent Runtime Audit](agent-runtime-audit.md)
- [Runtime Safety](runtime-safety.md)
- [Error Codes](error-codes.md)
- [Headless Agent Control](headless-agent-control.md)
- [Agent Tooling](agent-tooling.md)
