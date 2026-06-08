# Deprecation Policy (Local Runtime)

Boring, grep-visible deprecation for agent-facing surfaces. No hidden compatibility shims.

```bash
rg 'STABILITY:.*deprecated|DEPRECATED:' docs/ scripts/
```

---

## Rules

1. **Mark in docs and constants** — add method/flag to `scripts/fixtures/release/surface_classification.json` under `deprecated` with removal target release.
2. **One release window** — deprecated surfaces remain functional for at least one `contractInventory` bump unless security-critical.
3. **Stable diagnostic warning** — server may include `recovery_hint: use_replacement_method` on deprecated RPC paths; no prose-only warnings in tests.
4. **Test until removal** — harness check name `deprecated.<surface>` stays until deletion.
5. **Document removal** — release notes template section + `rg` cleanup command in maintainer guide.

---

## Deprecation checklist

```markdown
- [ ] Added to surface_classification.json `deprecated` list
- [ ] Documented replacement in maintainer-guide.md
- [ ] Release notes entry (docs/templates/runtime-release-notes.md)
- [ ] Harness coverage for deprecated path (if still callable)
- [ ] Removal grep command documented
```

---

## Example: deprecating a CLI flag

1. Move flag from `stable` to `deprecated` in `surface_classification.json`.
2. Add comment in `dietcode_agent_client.py`: `# DEPRECATED: --old-flag — remove in contractInventory 1.1.0`
3. Keep behavior unchanged for one release.
4. Remove flag and update tests in following release.

---

## Example: deprecating an RPC method

1. Add method name to `surface_classification.json` `rpc_methods.deprecated`.
2. Keep `rpc.describe` entry until removal.
3. Return `method_not_found` only after documented removal release.
4. Verify with `make release-check-agent-runtime`.

---

## Current deprecations (Agent Runtime Audit Pass V–VI)

| Surface | Status | Replacement | Error when blocked |
|---------|--------|-------------|-------------------|
| `search.semantic` | Quarantined | `search.literal`, `search.tokens`, `search.references` | `semantic_disabled` (4008) |
| `analysis.searchRanked` | Quarantined | `workspace.grep`, `search.literal` | `ranked_search_disabled` (4008) |
| `--search-semantic` CLI | Deprecated | `--search-literal`, `--grep` | stderr warning (still callable) |

Quarantined methods remain callable for diagnostics but return `4008` unless `allowExperimental: true` on `search.semantic`. They are **not** listed as `agentSafe` in `tool.registry`.

Registry entries for deprecated methods include `deprecated: true`, `replacementMethod`, and `failureRecoveryHint`.

```bash
python3 scripts/dietcode_agent_client.py tool.registry --compact | rg semantic
make test-deterministic-retrieval
make test-cli-agent-failures
```

Full audit context: [Agent Runtime Audit](agent-runtime-audit.md).

---

## Intentionally not added

- Automatic deprecation telemetry
- Runtime feature flags service
- Silent aliasing to new method names

---

## Related docs

- [Agent Runtime Audit](agent-runtime-audit.md)
- [Maintainer Guide](maintainer-guide.md)
- [Error Codes](error-codes.md)
- [Surface classification fixture](../scripts/fixtures/release/surface_classification.json)
- [Release notes template](templates/runtime-release-notes.md)
