# Agent Tooling (Deterministic Grep / Diff / Patch)

Plain-text contracts for local-first agent workflows. No semantic search, embeddings, or fuzzy matching.

```bash
rg 'TOOLING:|GREP_RESPONSE_KEYS|PATCH_VALIDATION_KEYS' scripts/ docs/
```

---

## Audit summary (grep/diff/patch pass)

| Issue | Root cause | Fix |
|-------|------------|-----|
| `workspace.grep` returned 0 matches in headless mode | Search read open-editor buffers only | Disk fallback via `TextForSearchAtPath` |
| Empty grep looked like success | No scan/read diagnostics | `filesRead`, `filesSkippedUnreadable`, `filesSkippedBinary` |
| Agents misread RPC envelopes | `client.call()` unwraps `result` | CLI normalizes + stderr hints on zero matches |
| Large diff payloads | Full hunk lines by default | `--diff-summary` compact JSON |
| Patch validation noise | Nested `validation` object | `--patch-summary` compact JSON |

---

## Grep contracts

### `workspace.grep` mode

Always `literal_substring`. Case folding unless `caseSensitive: true`.

### Required response keys

See `GREP_RESPONSE_KEYS` in `scripts/agent_contracts.py`.

Diagnostic counters (deterministic, not ranked):

| Key | Meaning |
|-----|---------|
| `scannedFiles` | Paths visited during scan |
| `filesRead` | Files with readable text (editor or disk) |
| `filesReadFromDisk` | Files read from filesystem |
| `filesReadFromEditor` | Files read from open buffer |
| `filesSkippedUnreadable` | Missing or unreadable paths |
| `filesSkippedBinary` | NUL-byte / binary content rejected |

### CLI

```bash
# JSON envelope (default)
python3 scripts/dietcode_agent_client.py --grep "CONTRACT:" --include 'scripts/*.py' --max-results 5 --compact

# ripgrep-style lines (exit 1 when no matches)
python3 scripts/dietcode_agent_client.py --grep "CONTRACT:" --grep-format rg --include scripts/agent_contracts.py

# stderr hint on zero matches (non --quiet)
python3 scripts/dietcode_agent_client.py --grep NOT_PRESENT --max-results 1 --compact
```

### Offline mirror

`scripts/agent_tooling.py`:

- `literal_match_spans()` — exact C++ `LiteralMatchSpans` parity
- `read_text_file_literal()` — disk read with binary rejection
- `grep_empty_result_hint()` — deterministic zero-match guidance

---

## Diff contracts

### `diff.hunks` mode

Always `literal_unified_diff_hunks`. Pagination via `hunkOffset` / `nextHunkOffset`.

```bash
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --include-lines --compact
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --diff-summary --compact
```

Offline parser: `parse_unified_diff_hunks()` mirrors `MacControlDiffParsing.mm`.

Fixture: `scripts/fixtures/tooling/sample_unified_diff.txt`

---

## Patch contracts

### Validate before mutate

Always call `patch.validate` (or `patch.preview`) before `patch.apply`.

```bash
python3 scripts/dietcode_agent_client.py --patch-file fix.diff --path src/foo.py --patch-summary --compact
git diff -- path | python3 scripts/dietcode_agent_client.py --patch-stdin --path path --patch-summary --compact
```

Required validation keys: `PATCH_VALIDATION_KEYS` in `scripts/agent_contracts.py`.

| Field | Agent use |
|-------|-----------|
| `ok` | Safe to proceed when true (with `ignoreSyntax` policy) |
| `patchAppliesCleanly` | Unified diff applies to current file text |
| `syntaxDanger` | True when relaxed mode allows risky syntax |
| `requiresConfirmation` | Large patch — needs `confirm: true` on apply |
| `rejectedReason` | Human-readable block reason when `ok: false` |

Disk read: patch validation already falls back to disk when file is not open (`MacControlPatchService`).

---

## Verification ladder

```bash
make test-agent-offline
make test-grep-diff-tooling
make test-deterministic-retrieval
make control-smoke
make verify-agent-runtime
```

Grep anchor fixture: `scripts/fixtures/tooling/grep_anchor.json`

---

## Deterministic retrieval (pass 5)

Agent-safe search surfaces (no semantic/fuzzy/ranking):

| Method | Mode | Agent-safe |
|--------|------|------------|
| `search.literal` | `literal_substring` | yes |
| `search.tokens` | `literal_token_conjunctive` | yes |
| `search.paths` | alias of `search.files` (`deterministic_path_match`) | yes |
| `search.references` | `symbol_exact`, `sortOrder: path_line_column` | yes |
| `tool.registry` | per-method `agentSafe` / `deprecated` / `replacementMethod` | yes |
| `tool.capabilities` | `agentSafeMethods`, `semanticSearchDisabled: true` | yes |

Quarantined (returns `4008` unless `allowExperimental: true`):

| Method | Replacement |
|--------|-------------|
| `search.semantic` | `search.literal`, `search.tokens`, `search.references` |
| `analysis.searchRanked` | `workspace.grep`, `search.literal` |

```bash
make test-deterministic-retrieval
python3 scripts/dietcode_agent_client.py tool.capabilities --compact
python3 scripts/dietcode_agent_client.py search.literal '{"query":"CONTRACT:","include":["scripts/*.py"],"maxResults":5}' --compact
```

Golden fixtures: `scripts/fixtures/retrieval/`

---

## Intentionally not added

- Semantic graphs, embeddings, vector search, fuzzy matching
- Probabilistic ranking or opaque relevance scores
- Hidden agent memory or retrieval caches
- ML-based patch suggestion or error recovery

Regressions surface via **grep misses**, **schema validation**, **anchor fixture drift**, or **nonzero harness exit**.

---

## Harness realism (pass 4)

```bash
make test-harness-realism
```

Covers deterministic `search.files`, live symlink escape fixture, transport idempotency recovery, and concurrent stale-write fuzz.

---

## Transaction kernel (pass 3)

```bash
make test-transaction-kernel
python3 scripts/dietcode_agent_client.py workspace.revision
python3 scripts/dietcode_agent_client.py operation.status '{"idempotencyKey":"..."}'
```

See [Runtime Invariants](runtime-invariants.md) for revision surfaces, batch receipts, and symlink policy.

---

## Runtime invariants (pass 2)

See [Runtime Invariants](runtime-invariants.md) for state-hash guards, grep sort order, and mutation receipts.

```bash
make test-runtime-determinism
python3 scripts/dietcode_agent_client.py --expect-before-hash <hash> --patch-file fix.diff --path src/foo.py
```

---

## Related docs

- [Runtime Invariants](runtime-invariants.md)
- [Headless Agent Control](headless-agent-control.md)
- [Runtime Contracts](runtime-contracts.md)
- [Operator Policy](operator-policy.md)
