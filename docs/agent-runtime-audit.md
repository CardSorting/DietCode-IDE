# Agent Runtime Audit (Passes I–VI)

Canonical record of the six audit passes that hardened DietCode's headless agent control surface into a **deterministic, inspectable local transaction kernel**.

```bash
rg 'Pass [IV]+|agent-runtime-audit' docs/
make verify-agent-runtime-full
```

**Scope:** grep/patch/search reliability, runtime determinism, transaction kernel, harness realism, semantic surface removal, agent failure traps, and partial-success closure.

**Explicitly excluded (all passes):** semantic search, embeddings, fuzzy matching, probabilistic ranking, node graphs, hidden relevance systems, governance abstractions, operating modes.

---

## Pass summary

| Pass | Focus | Key deliverables | Verify |
|------|-------|------------------|--------|
| **I** | Grep reliability | Disk fallback (`TextForSearchAtPath`), scan accounting, `agent_tooling.py`, `agent_contracts.py` | `make test-grep-diff-tooling` |
| **II** | Runtime determinism | `expectBeforeHash`, `stale_content`, `mutationReceipt`, sorted grep traversal | `make test-runtime-determinism` |
| **III** | Transaction kernel | `workspace.revision`, `workspace.snapshot`, `operation.status`, batch atomicity, idempotency | `make test-transaction-kernel` |
| **IV** | Harness realism | Deterministic `search.files`, symlink policy, transport retry, concurrent stale-write | `make test-harness-realism` |
| **V** | Semantic surface removal | Quarantine `search.semantic`, deterministic retrieval, `tool.registry` | `make test-deterministic-retrieval` |
| **VI** | Agent failure traps | Partial-success signals, workflow smoke tests, CLI ergonomics, docs drift | `make verify-agent-runtime-full` |
| **VI closure** | Parity gaps | `patch.applyBatch`, `workspace.snapshot`, `diff.hunks` enrichment | `make test-partial-success-closure` |

---

## Pass I — Grep reliability

### Problem

`workspace.grep` returned zero matches in headless mode because search only read open editor buffers.

### Changes

| Area | Implementation |
|------|----------------|
| Disk fallback | `TextForSearchAtPath` in `MacControlSupport.mm` — editor buffer preferred, disk when headless |
| Scan accounting | `scannedFiles`, `filesRead`, `filesReadFromDisk`, `filesSkippedUnreadable`, `filesSkippedBinary`, … |
| Contracts | `GREP_RESPONSE_KEYS` frozen in `scripts/agent_contracts.py` |
| Offline mirror | `scripts/agent_tooling.py` — `literal_match_spans()`, `grep_empty_result_hint()` |
| CLI | `--grep`, `--grep-format rg`, stderr hints on zero matches |
| Docs | `docs/agent-tooling.md` |
| Tests | `scripts/test_grep_diff_tooling.py` |

### Invariants

- Mode: `literal_substring` only
- Sort: `sortOrder: path_line_column`
- No scores, no fuzzy expansion

---

## Pass II — Runtime determinism

### Problem

Agents could not detect stale writes, grep order was unstable, and mutation proof was missing.

### Changes

| Area | Implementation |
|------|----------------|
| Stale writes | `expectBeforeHash` on `patch.apply` → `stale_content` (4004) if content drifted |
| Mutation proof | `mutationReceipt` with `beforeContentHash`, `postContentHash`, `patchFingerprint` |
| Disk patch | `ApplyUnifiedPatchToDisk` for headless `patch.apply` |
| Grep order | Sorted path traversal before scan |
| Contracts | `MUTATION_RECEIPT_KEYS`, `PATCH_VALIDATION_KEYS` |
| Tests | `scripts/test_runtime_determinism.py` |
| Docs | `docs/runtime-invariants.md` |

### Invariants

- `patch.validate` must precede `patch.apply`
- Stale check runs **before** re-validation on apply
- Identical grep queries → identical `(path, line, column)` tuples

---

## Pass III — Transaction kernel

### Problem

No monotonic workspace revision, no idempotency replay, no batch rollback proof.

### Changes

| RPC | Purpose |
|-----|---------|
| `workspace.revision` | Monotonic `revisionId`, `changedFiles`, `lastMutationReceipt` |
| `workspace.snapshot` | Point-in-time `fileHashes`; `sinceRevision` delta |
| `operation.status` | Lookup completed mutation by `idempotencyKey` |
| `patch.applyBatch` | Atomic multi-file apply with `batchMutationReceipt`, rollback on failure |

| Area | Implementation |
|------|----------------|
| State service | `MacControlWorkspaceState.mm` |
| Batch rollback | Per-file `expectBeforeHash`; restore on any failure |
| Search parity | `search.text` / `search.todo` share `SEARCH_ACCOUNTING_KEYS` with grep |
| Symlink policy | `skip_never_follow`; `filesSkippedSymlink` accounting |
| Tests | `scripts/test_transaction_kernel.py` (13 checks) |

---

## Pass IV — Harness realism

### Problem

`search.files` used probabilistic `score`; live harness lacked symlink escape, transport, and concurrency coverage.

### Changes

| Area | Implementation |
|------|----------------|
| `search.files` | `deterministic_path_match`, `matchReason`, `sortOrder: match_reason_path` — **no score** |
| `file.stat` | `isSymlink`, `symlinkTarget`, `pathEscapesWorkspace` |
| `patch.apply` | Rejects symlink targets → `symlink_target` (4004) |
| `workspace.snapshot` | `snapshotMode`, `complete`, `truncated`, `filesHashed`, `hashAlgorithm` |
| Harness | `scripts/harness_support.py` — symlink fixture, transport mocks |
| Tests | `scripts/test_harness_realism.py` (11 checks) |
| Verify | `make verify-agent-runtime` ladder |

---

## Pass V — Semantic surface removal

### Problem

Non-deterministic retrieval (`search.semantic`, `analysis.searchRanked`) and no agent-safe method registry.

### Quarantined surfaces

| Method | Error | Replacement |
|--------|-------|-------------|
| `search.semantic` | `semantic_disabled` (4008) | `search.literal`, `search.tokens`, `search.references` |
| `analysis.searchRanked` | `ranked_search_disabled` (4008) | `workspace.grep`, `search.literal` |

`allowExperimental: true` on `search.semantic` returns deterministic symbol refs with warning — **not agent-safe**.

### Deterministic replacements

| Method | Mode |
|--------|------|
| `search.literal` | `literal_substring`, `rankingPolicy: none`, `agentSafe: true` |
| `search.tokens` | `literal_token_conjunctive`, `matchReason: all_tokens_literal` |
| `search.paths` | Alias of `search.files` (`deterministic_path_match`) |
| `search.references` | `symbol_exact`, sorted `path_line_column` |
| `tool.registry` | Per-method `agentSafe`, `deterministic`, `deprecated`, `replacementMethod` |
| `tool.capabilities` | `agentSafeMethods`, `deprecatedMethods`, `semanticSearchDisabled: true` |

### Changes

| Area | Implementation |
|------|----------------|
| Server | `MacControlSearchService.mm` quarantine; `MacControlToolRegistry.mm` |
| CLI | `--search-semantic` deprecated; `--search-literal` added |
| Contracts | `SEARCH_LITERAL_*`, `TOOL_REGISTRY_*` in `agent_contracts.py` |
| Fixtures | `scripts/fixtures/retrieval/` |
| Surface | `surface_classification.json` v1.1.0 |
| Tests | `scripts/test_deterministic_retrieval.py` (15 checks) |

---

## Pass VI — Agent failure traps

### Problem

Agents could misread `ok: true` as full success when results were truncated, validation required confirmation, or deprecated methods were called.

### Partial-success model

Success payloads expose:

| Field | Meaning |
|-------|---------|
| `complete` | `false` when truncated, paginated, or scan-limited |
| `partial` | `true` when warnings, skips, or fallback reads occurred |
| `warnings` | Stable tokens (`results_truncated`, `requires_confirmation`, …) |
| `fallbackUsed` | Disk read fallback was used |
| `recoveryHint` | Next safe action token when incomplete |
| `nextRecommendedCommand` | RPC method to call next |

Errors expose `recovery_hint` + `nextRecommendedCommand`.

### Enriched surfaces (C++)

`MacControlSupport.mm`:

- `MacControlEnrichReadSearchResult` — grep, search.text/literal/tokens/files/todo
- `MacControlEnrichPatchValidateResult` — patch.validate
- `MacControlEnrichPatchApplyResult` — patch.apply
- `MacControlEnrichPatchApplyBatchResult` — patch.applyBatch (Pass VI closure)
- `MacControlEnrichSnapshotResult` — workspace.snapshot (closure)
- `MacControlEnrichDiffHunksResult` — diff.hunks, patch.hunks (closure)

### Tool registry

Each `tool.registry` entry includes:

- `agentSafe`, `deterministic`, `mutatesWorkspace`, `requiresConfirmation`
- `failureRecoveryHint`, `nextRecommendedCommand`, `replacementMethod`, `deprecated`

### Internal namespaces (not in registry)

`tool.capabilities.internalNamespaces`:

- `analysis.`, `language.`, `chip.`, `combo.`, `recovery.`, `terminal.run`, `verify.run`

Fixture: `scripts/fixtures/release/internal_method_namespaces.json`

### Error recovery (frozen)

| `string_code` | `recovery_hint` | `nextRecommendedCommand` |
|---------------|-----------------|--------------------------|
| `stale_content` | `revalidate_patch_with_patch.validate` | `patch.validate` |
| `symlink_target` | `use_non_symlink_target_path` | `file.stat` |
| `semantic_disabled` | `use_search_literal_or_search_tokens` | `search.literal` |
| `ranked_search_disabled` | `use_workspace_grep_or_search_literal` | `workspace.grep` |
| `patch_failed` | `run_patch_preview_or_patch_validate` | `patch.validate` |
| `nested_call_timeout` | `reduce_concurrency_or_retry_later` | `operation.status` |

Fixture: `scripts/fixtures/recovery/error_recovery_hints.json`

### CLI improvements

- `--search-literal` agent-safe alias
- Argparse examples epilog
- Clear `params JSON is invalid` messages
- stderr `hint:` lines for partial/truncated results
- `--search-semantic` deprecation warning

### Workflow smoke tests

`scripts/test_agent_workflow_smoke.py`:

| Workflow | Steps |
|----------|-------|
| A — Find and patch | search.literal → file.stat → patch.validate → patch.apply → revision bump |
| B — Stale recovery | validate → external mutate → stale_content → re-validate corrected patch → apply |
| C — Batch rollback | validate batch → stale one file → atomic failure, no files changed |
| D — Deprecated recovery | search.semantic → semantic_disabled → search.literal |

### Tests added (Pass VI)

| Suite | Checks |
|-------|--------|
| `test_agent_workflow_smoke.py` | 6 |
| `test_cli_agent_failures.py` | 6 |
| `test_docs_code_drift.py` | 9 |
| `test_partial_success_closure.py` | 6 |

---

## Verification ladder

### Daily development

```bash
make app
make restart-agent-server          # after C++ changes
make test-agent-offline
make verify-agent-runtime          # 14 live + offline checks
```

### Release / full closure

```bash
make verify-agent-runtime-full     # 9 checks incl. workflow + drift + closure
make release-check-agent-runtime
```

### Per-pass targets

```bash
make test-grep-diff-tooling        # Pass I
make test-runtime-determinism      # Pass II
make test-transaction-kernel       # Pass III
make test-harness-realism          # Pass IV
make test-deterministic-retrieval  # Pass V
make test-agent-workflow-smoke     # Pass VI
make test-cli-agent-failures       # Pass VI
make test-docs-code-drift          # Pass VI
make test-partial-success-closure  # Pass VI closure
```

---

## Source file index

| Area | Primary files |
|------|---------------|
| Disk fallback + enrichment | `src/platform/macos/control/utils/MacControlSupport.mm` |
| Grep / search | `src/platform/macos/control/services/MacControlSearchService.mm` |
| Patch / batch | `src/platform/macos/control/services/MacControlPatchService.mm` |
| Revision / snapshot | `src/platform/macos/control/services/MacControlWorkspaceState.mm` |
| Tool registry | `src/platform/macos/control/services/MacControlToolRegistry.mm` |
| Error recovery hints | `src/platform/macos/control/utils/MacControlRuntimeDiagnostics.mm` |
| Socket safety | `src/platform/macos/control/utils/MacControlSocketSafety.mm` |
| Runtime limits | `src/domain/control/ControlRuntimeLimits.hpp` |
| Contract constants | `scripts/agent_contracts.py` |
| Offline mirrors | `scripts/agent_tooling.py`, `scripts/harness_support.py` |
| Python client | `scripts/dietcode_agent_client.py` |

---

## Fixture index

| Fixture | Validates |
|---------|-----------|
| `scripts/fixtures/tooling/grep_anchor.json` | Grep match shape and accounting |
| `scripts/fixtures/tooling/sample_unified_diff.txt` | Offline diff hunk parser parity |
| `scripts/fixtures/tooling/stale_content.json` | Stale-write scenario metadata |
| `scripts/fixtures/retrieval/search_literal_golden.json` | search.literal response |
| `scripts/fixtures/retrieval/search_tokens_golden.json` | search.tokens response |
| `scripts/fixtures/retrieval/tool_registry_golden.json` | tool.registry entry shape |
| `scripts/fixtures/retrieval/semantic_disabled_golden.json` | semantic_disabled envelope |
| `scripts/fixtures/recovery/error_recovery_hints.json` | ERROR_RECOVERY_HINTS parity |
| `scripts/fixtures/release/surface_classification.json` | STABILITY classification |
| `scripts/fixtures/release/internal_method_namespaces.json` | INTERNAL_METHOD_NAMESPACES |
| `scripts/fixtures/harness/symlink_policy.json` | Symlink traversal policy |
| `scripts/fixtures/harness/search_files_golden.json` | search.files deterministic match |
| `scripts/fixtures/safety/destructive_methods.json` | Destructive RPC tier list |
| `scripts/fixtures/rpc/expected_error_codes.json` | Golden string_code set |

---

## Contract inventory (frozen keys)

Source of truth: `scripts/agent_contracts.py` (grep `CONTRACT:`).

| Constant | Surface |
|----------|---------|
| `GREP_RESPONSE_KEYS` | workspace.grep |
| `SEARCH_LITERAL_RESPONSE_KEYS` | search.literal |
| `SEARCH_TOKENS_RESPONSE_KEYS` | search.tokens |
| `SEARCH_FILES_RESPONSE_KEYS` | search.files |
| `PATCH_VALIDATION_KEYS` | patch.validate |
| `MUTATION_RECEIPT_KEYS` | patch.apply |
| `PATCH_APPLY_BATCH_SUCCESS_KEYS` | patch.applyBatch success |
| `WORKSPACE_SNAPSHOT_KEYS` | workspace.snapshot |
| `DIFF_HUNKS_RESPONSE_KEYS` | diff.hunks / patch.hunks |
| `TOOL_REGISTRY_*` | tool.registry / tool.capabilities |
| `PARTIAL_SUCCESS_OPTIONAL_KEYS` | Shared enrichment fields |
| `ERROR_RECOVERY_HINTS` | Error envelope recovery |
| `INTERNAL_METHOD_NAMESPACES` | Non-agent-safe RPC prefixes |

---

## Deprecated surfaces

| Surface | Status | Replacement |
|---------|--------|-------------|
| `search.semantic` | Quarantined (4008) | `search.literal`, `search.tokens` |
| `analysis.searchRanked` | Quarantined (4008) | `workspace.grep`, `search.literal` |
| `--search-semantic` CLI | Deprecated | `--search-literal`, `--grep` |

See [Deprecation Policy](deprecation-policy.md).

---

## Intentionally not added

- Semantic graphs, embeddings, vector search, fuzzy matching
- Probabilistic ranking or opaque relevance scores
- Hidden agent memory or retrieval caches
- Governance layers, operating modes, policy engines
- `search.contracts` as separate RPC (use `search.references` + `symbols.references`)
- Empty `warnings: []` on all complete read-search responses (grep omits when none; snapshot/diff/batch always include key)

---

## Related docs

| Doc | Contents |
|-----|----------|
| [Agent Tooling](agent-tooling.md) | Grep/diff/patch/retrieval contracts |
| [Runtime Invariants](runtime-invariants.md) | Frozen behavioral rules |
| [Runtime Contracts](runtime-contracts.md) | Contract IDs and versions |
| [Error Codes](error-codes.md) | `string_code` catalog + recovery |
| [Headless Agent Control](headless-agent-control.md) | RPC reference + CLI |
| [Build & Test System](build-and-test-system.md) | Makefile targets |
| [Testing Checklist](testing-checklist.md) | Pre-merge checklist |
| [Maintainer Guide](maintainer-guide.md) | How to extend safely |
| [Deprecation Policy](deprecation-policy.md) | Deprecation workflow |
