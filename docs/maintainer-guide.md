# Maintainer Guide (Agent Runtime)

How to evolve the control runtime without breaking grep/diff-first contracts.

```bash
rg 'MAINTAINER:|RELEASE:|CONTRACT:' docs/ scripts/
```

---

## How to add a new RPC method safely

1. Add catalog entry in `src/platform/macos/control/services/MacControlMethodCatalog.mm` with `permission` tier.
2. If read-queue method, add to `MacControlRoutingPolicy.mm` / `READ_METHODS` in `dietcode_agent_client.py`.
3. Implement handler in appropriate `MacControlServer+*.mm` category.
4. Classify stability in `scripts/fixtures/release/surface_classification.json` (`stable` or `experimental`).
5. Add smoke or integration check with dotted name (`rpc.new_method_shape`).
6. Run `make release-check-agent-runtime`.

```bash
rg 'MacControlMethodCatalog|executeFileMethod' src/platform/macos/control
python3 scripts/dietcode_agent_client.py --describe your.method --compact
```

---

## How to add a new error code

1. Map `string_code` → numeric in `MacControlServer.mm` `sendError`.
2. Document in `docs/error-codes.md`.
3. Add metadata in `MacControlRuntimeDiagnostics.mm` `MacControlRpcErrorDiagnosticMetadata` if needed.
4. Add golden fixture entry in `scripts/fixtures/rpc/expected_error_codes.json` if harness-tested.
5. Bump `errorTaxonomy` in `ControlReleaseVersions.hpp` + `scripts/release_versions.py` if taxonomy shape changes.

```bash
rg 'stringCode isEqualToString' src/platform/macos/control/MacControlServer.mm
make test-rpc-transaction
```

---

## How to add a new safety limit

1. Add `constexpr` to `src/domain/control/ControlRuntimeLimits.hpp` with `SAFETY:` or `RELEASE:` comment.
2. Wire through `MacControlSupport.mm` if used server-side.
3. Mirror in `scripts/runtime_safety.py` `RUNTIME_LIMITS`.
4. Enforce in `MacControlServer.mm` or relevant service.
5. Document in `docs/runtime-safety.md`.
6. Bump `safetyLimits` version if schema of limits dict changes.
7. Run `make test-runtime-safety`.

```bash
rg 'kMax' src/domain/control/ControlRuntimeLimits.hpp scripts/runtime_safety.py
```

---

## How to add a new diagnostic field

1. Add to server log in `logRuntimeDiagnostic` or error envelope in `sendError`.
2. Update `RUNTIME_DIAGNOSTIC_LINE_KEYS` or `RPC_ERROR_DIAGNOSTIC_OPTIONAL_KEYS` in `scripts/agent_contracts.py`.
3. Classify `stable` vs `experimental` in `surface_classification.json`.
4. Document in `docs/operator-diagnostics.md`.
5. Bump `diagnostics` version in release versions if required keys change.
6. Run `make test-operator-diagnostics`.

---

## How to add a new regression suite

1. Create `scripts/test_<name>.py` using `CheckRecorder` + `finish_test_run`.
2. Register in `INTEGRATION_SUITES` or `OFFLINE_SUITES` in `scripts/agent_contracts.py`.
3. Add Makefile target `test-<name>`.
4. Add to `release_check_agent_runtime.py` LADDER if release-grade.
5. Classify Makefile target stability in `surface_classification.json`.

```bash
rg 'CheckRecorder|finish_test_run' scripts/test_*.py
```

---

## How to add an agent-safe search or read surface

1. Implement in `MacControlSearchService.mm` (or read path in `MacControlSupport.mm`).
2. Set explicit `searchMode` / `sortOrder` — no `score`, `relevance`, or fuzzy expansion.
3. Call `MacControlEnrichReadSearchResult` (or sibling enrich helper) for partial-success fields.
4. Add frozen keys to `scripts/agent_contracts.py` and a golden fixture under `scripts/fixtures/retrieval/` or `scripts/fixtures/tooling/`.
5. Register in `MacControlToolRegistry.mm` with `agentSafe: true`, `deterministic: true`.
6. Add harness check in `test_deterministic_retrieval.py` or `test_grep_diff_tooling.py`.
7. Document in `docs/agent-tooling.md` and bump [Agent Runtime Audit](agent-runtime-audit.md) if pass-level.

**Do not** add semantic embeddings, probabilistic ranking, or hidden relevance — see [Anti-Scope Checklist](anti-scope-checklist.md).

---

## How to add partial-success enrichment to a surface

1. Add or extend an enrich helper in `MacControlSupport.mm` (`MacControlEnrich*`).
2. Set `complete`, `partial`, `warnings` (always include `warnings` key — empty array when none).
3. Set `nextRecommendedCommand` and `recoveryHint` when `complete: false` or validation requires follow-up.
4. Add keys to `PARTIAL_SUCCESS_OPTIONAL_KEYS` in `agent_contracts.py`.
5. Add recovery row to `scripts/fixtures/recovery/error_recovery_hints.json` if new error path.
6. Add check in `test_partial_success_closure.py` or `test_agent_workflow_smoke.py`.
7. Run `make test-docs-code-drift` — docs must match fixture recovery table.

```bash
rg 'MacControlEnrich' src/platform/macos/control/utils/MacControlSupport.mm
make test-partial-success-closure
```

---

## How to register a method in tool.registry

1. Add entry in `MacControlToolRegistry.mm` with `agentSafe`, `deterministic`, `mutatesWorkspace`, `requiresConfirmation`.
2. For deprecated methods, set `deprecated: true` and `replacementMethod`.
3. For internal-only surfaces (`analysis.*`, `language.*`, …), add prefix to `internalNamespaces` — **do not** add to registry list.
4. Update `scripts/fixtures/release/surface_classification.json` and `internal_method_namespaces.json`.
5. Run `make test-deterministic-retrieval`.

```bash
python3 scripts/dietcode_agent_client.py tool.registry --compact
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
```

---

## Agent runtime audit passes (I–VI)

Canonical record: [Agent Runtime Audit](agent-runtime-audit.md).

| Pass | Maintainer touchpoints |
|------|------------------------|
| I — Grep | `TextForSearchAtPath`, `agent_tooling.py`, `GREP_RESPONSE_KEYS` |
| II — Determinism | `expectBeforeHash`, `mutationReceipt`, `test_runtime_determinism.py` |
| III — Transaction | `MacControlWorkspaceState.mm`, `patch.applyBatch`, revision/snapshot |
| IV — Harness | `search.files` deterministic mode, `harness_support.py`, symlink fixture |
| V — Retrieval | `MacControlToolRegistry.mm`, semantic quarantine, `search.literal` |
| VI — Failure traps | `MacControlEnrich*`, workflow smoke, `test_docs_code_drift.py` |

After any C++ change to control services: `make restart-agent-server` before live harnesses.

---

## How to update contract inventory

1. Edit `docs/runtime-contracts.md` — add row to contract index with ID `C-*`.
2. Add `CONTRACT:` / `INVARIANT:` comments in source.
3. Bump `contractInventory` in `ControlReleaseVersions.hpp` and `scripts/release_versions.py`.
4. Fill `docs/templates/runtime-release-notes.md` for the release.
5. Run `make test-agent-offline` and `make release-check-agent-runtime`.

---

## How to keep documentation aligned

When changing agent-runtime behavior, update docs in the same PR:

| Change type | Update |
|-------------|--------|
| New frozen key set | `scripts/agent_contracts.py` + `docs/agent-tooling.md` constant table |
| New error + recovery | `MacControlRuntimeDiagnostics.mm` + `error-codes.md` + `fixtures/recovery/` |
| New Makefile target | `Makefile` + `docs/build-and-test-system.md` + `docs/build-instructions.md` |
| New RPC method | `headless-agent-control.md` + `tool.registry` if agent-safe |
| Pass-level feature | `docs/agent-runtime-audit.md` |
| Internal namespace | `internal_method_namespaces.json` + `agent-tooling.md` |

```bash
make test-docs-code-drift
rg 'agent-runtime-audit|verify-agent-runtime-full' docs/ README.md
```

Drift test enforces: recovery hints in `error-codes.md`, internal namespaces in `agent-tooling.md`, Makefile targets, and contract key presence in `runtime-invariants.md`.

---

## How to review changes with rg/git diff

```bash
# Version and stability drift
rg 'RELEASE:|STABILITY:|deprecated|experimental' src/ scripts/ docs/

# Contract comments
rg 'CONTRACT:|INVARIANT:|SAFETY:' src/ scripts/ docs/

# Release diff review
git diff src/domain/control/ src/platform/macos/control/ scripts/ docs/ Makefile

# Verify before merge
make release-check-agent-runtime
```

---

## Version surfaces (single source of truth)

| Surface | C++ | Python |
|---------|-----|--------|
| Protocol | `ControlReleaseVersions.hpp` | `scripts/release_versions.py` |
| Client schema | — | `CLIENT_SCHEMA_VERSION` |
| Sync test | — | `test_release_readiness.py` → `release.versions_synced` |

Expose via:

```bash
python3 scripts/dietcode_agent_client.py --emit-config --json | rg contractVersions
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.version
```

---

## Intentionally not added

- Semantic versioning automation or changelog generators
- Telemetry-backed release analytics
- Feature flag service or remote kill switches
- Abstraction-heavy release framework (no staged rollout platform)
- Hidden compatibility adapters between protocol versions
- Fuzzy or ML-based breaking-change detection

Ship with: **version bump → release notes template → `make release-check-agent-runtime` → `git diff` review**.

---

## Related docs

- [Agent Runtime Audit](agent-runtime-audit.md)
- [Agent Tooling](agent-tooling.md)
- [Runtime Contracts](runtime-contracts.md)
- [Runtime Invariants](runtime-invariants.md)
- [Release Upgrade & Rollback](release-upgrade-rollback.md)
- [Deprecation Policy](deprecation-policy.md)
- [Runtime Safety](runtime-safety.md)
