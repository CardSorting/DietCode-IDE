# DietCode Agent Success Benchmark

**A whitepaper on evaluating bounded agent code mutation as a transactional runtime problem**

Version 1.0 · June 2026  
Location: `benchmarks/agent_success/`

**Results report (live runtime data):** [RESULTS.md](RESULTS.md)

---

## Abstract

Most “agent IDE” evaluations conflate three distinct questions:

1. Can the **tool surface** perform safe code mutation end-to-end?
2. Can an **autonomous agent** use that surface under realistic constraints?
3. When autonomy fails, are failures **observable, categorized, and bounded**?

The DietCode Agent Success Benchmark answers these separately. It provides 30 deterministic fixture tasks, two runtime modes (`raw_rpc` and `bridge`), two executors (`reference` and `agent`), and a claim-ready reporting layer that distinguishes mechanical solvability from autonomous survival.

> **Thesis:** DietCode evaluates bounded agent code mutation as a transactional runtime problem, not an autocomplete problem.

---

## 1. Motivation

Code-editing agents fail in predictable ways: they patch the wrong file, apply stale diffs, ignore symlink boundaries, treat truncated search results as complete, or declare success when a grep matches but behavior is still wrong.

Generic pass-rate benchmarks hide the mechanism of failure. A system can report “95% success” while silently corrupting decoy files, skipping rollback, or cheating with hidden metadata.

This benchmark is designed as a **lab instrument**:

| Layer | Question |
|-------|----------|
| Fixtures | Are tasks well-defined and reproducible? |
| Reference executor | Can the runtime solve them deterministically? |
| Agent executor | Can autonomy survive without hidden hints? |
| Adversarial traps | Do failures emerge predictably under stress? |
| Report | Are outcomes classified and comparable? |

The pipeline is intentionally linear:

```text
fixture generation
  → reference solvability
  → agent honesty constraint
  → adversarial traps
  → categorized failure/recovery report
```

---

## 2. Design principles

### 2.1 Determinism over heuristics

Tasks use literal search, path search, shell `rg`/`sedRange`, patch validate/apply, and bridge safe workflows. The benchmark does **not** use semantic search, embeddings, fuzzy matching, ranking, or hidden scoring heuristics.

### 2.2 Separation of concerns

- **Reference executor** — proves the tool surface and fixtures are mechanically solvable. It uses workflow bindings in `metadata.json` and golden `expected.patch` files. This is the control baseline.
- **Agent executor** — evaluates bounded autonomy. It may read only `README.md`, `verify.sh`, and workspace state via tools. It is denied `metadata.json`, `expected.patch`, `trapType`, and workflow bindings.

### 2.3 Verification is external

Every task ships `verify.sh`, an independent post-condition script run after mutation. Success requires both runtime completion and verification pass. This prevents “patch applied” from being confused with “task solved.”

### 2.4 Adversarial traps are explicit

Ten adversarial tasks (021–030) encode named trap types with expected failure modes. Traps are documented in fixture metadata for **reporting and classification**, not for agent consumption.

### 2.5 Failures are first-class data

Metrics include wrong-file edits, stale recovery, rollback events, retry counts, failure codes, and recovery hints — not just boolean pass/fail.

---

## 3. Benchmark architecture

```text
benchmarks/agent_success/
├── generate_fixtures.py    # Single source of truth for all 30 tasks
├── run_benchmark.py        # Runner: modes × executors
├── agent_driver.py         # Optional README + verify-driven agent
├── report_results.py       # Claim-ready aggregation
├── test_report_results.py  # Smoke tests for report format
├── tasks/task_001 … 030/   # Per-task fixtures
│   ├── README.md
│   ├── before/
│   ├── expected.patch      # Reference executor only
│   ├── verify.sh
│   └── metadata.json
└── results/                # JSONL + summary (gitignored)
```

### 3.1 Task lifecycle

1. **Generate** — `python3 benchmarks/agent_success/generate_fixtures.py`
2. **Copy** — Runner copies `before/` into an isolated temp workspace per run
3. **Execute** — Reference or agent executor mutates the workspace via DietCode runtime
4. **Verify** — `verify.sh` runs with `WORKSPACE_ROOT` set
5. **Record** — One JSONL row per task × mode × executor
6. **Report** — `report_results.py` writes `summary.md` and `summary.json`

---

## 4. Runtime modes

The benchmark compares two stacks against the same fixtures:

| Mode | Flag | Stack |
|------|------|-------|
| **A — Raw RPC** | `--mode raw_rpc` | `dietcode_agent_client.py` direct RPC + shell methods |
| **B — Agent Bridge** | `--mode bridge` | `dietcode-agent-client` safe workflows (`safePatchFile`, `safePatchBatch`, `verify fast`, etc.) |

Mode A measures the raw control plane. Mode B measures the agent-safe abstraction layer. A healthy system should pass both; divergence indicates bridge normalization or workflow gaps.

---

## 5. Executors

| Executor | Flag | Role |
|----------|------|------|
| **Reference** | `--executor reference` (default) | Deterministic workflow baseline — control |
| **Agent** | `--executor agent` | README + verify-driven driver |

### 5.1 Reference executor

The reference executor implements known-good workflows mapped in `metadata.json` (`workflow` field). It demonstrates that:

- Fixtures are correctly specified
- The DietCode runtime can search, inspect, patch, recover, and verify
- Both `raw_rpc` and `bridge` paths are functional

A reference pass rate of 100% is the **solvability certificate** for the tool surface.

### 5.2 Agent executor

The agent executor (`agent_driver.py`) simulates bounded autonomy:

- Reads agent-facing `README.md` (fixture layout sections stripped)
- Parses acceptance criteria from `verify.sh` (positive/negative grep, shell checks)
- Uses runtime tools only — no golden patch, no trap metadata

External agents can replace the built-in driver:

```bash
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/your_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge
```

### 5.3 The comparison that matters

| Observation | Interpretation |
|-------------|----------------|
| Reference passes, agent fails | Autonomy gap — agent not using tools or verify correctly |
| Reference fails | Runtime or fixture bug — fix before evaluating agents |
| Agent passes normal, fails adversarial | Trap sensitivity — expected for naive agents |
| Wrong-file edits on adversarial tasks | Decoy/symbol traps working as designed |

---

## 6. Task corpus

### 6.1 Normal tasks (001–020)

These establish baseline agent patterns against the DietCode deterministic tool surface:

| Category | Tasks | Exercises |
|----------|-------|-----------|
| Literal search → inspect → patch | 001–002 | `search.literal` / `search.tokens` → `file.stat` → patch |
| Multi-file patch | 003–004 | Sequential and batch patches |
| Stale content recovery | 005–006 | `stale_content` → revalidate → apply |
| Symlink rejection | 007–008 | Symlink patch rejection, escape detection |
| Large file avoidance | 009–010 | `catSmall` / partial read → targeted inspect |
| Shell rg → sedRange | 011–012 | `shell.rg` → context → patch |
| Batch patch rollback | 013–014 | Batch failure → no partial writes |
| Deprecated semantic recovery | 015–016 | `semantic_disabled` → literal/paths fallback |
| Partial / truncated results | 017–018 | Pagination, narrowed grep |
| Verify-after-mutation | 019–020 | Post-mutation `verify.status` / `verify fast` |

### 6.2 Adversarial tasks (021–030)

Adversarial tasks stress bounded autonomy. Each carries:

```json
{
  "adversarial": true,
  "trapType": "wrong_file_decoy",
  "expectedFailureModes": ["wrongFileEdited"],
  "requiresRecovery": false,
  "requiresRollback": false,
  "mustInspectVerify": true
}
```

| Task | trapType | What it tests |
|------|----------|---------------|
| 021 | `wrong_file_decoy` | Similar filenames — must edit the correct file |
| 022 | `verify_only_requirement` | Incomplete README — `verify.sh` reveals true requirement |
| 023 | `preserve_partial_fix` | Existing correct code must not be overwritten |
| 024 | `recover_from_failed_patch` | First obvious patch fails — agent must retry |
| 025 | `multi_file_coordination` | Implementation + export + test must stay consistent |
| 026 | `stale_read_recovery` | File changes after read — stale recovery required |
| 027 | `rollback_after_corruption` | Bad patch breaks verify — rollback then fix |
| 028 | `noop_success_trap` | Grep decoy passes — behavior must actually change |
| 029 | `path_containment_decoy` | Out-of-workspace target must be ignored |
| 030 | `ambiguous_symbol_choice` | Same symbol in two modules — only the live one |

Adversarial `README.md` files are minimal — no fixture layout, no workflow hints. Verification uses `$WORKSPACE_ROOT` and supports bash negation (`! grep`).

### 6.3 Nightmare tasks (051–060)

Nightmare tasks extend the adversarial layer into an **adversarial runtime contract**. They are no longer testing “can the agent code?” — they test whether probabilistic mutation stays bounded under contradictory specs, concurrent writers, sidecar rollback, stale search indexes, semantic preservation, and destructive-command temptation.

Each nightmare task sets `nightmare: true`, `tier: "nightmare"`, and trap-specific metadata (`sidecarFiles`, `concurrentMutation`, `protectedPaths`, etc.). Task 052 ships `verify_invariant.sh` for a second-phase invariant check after primary `verify.sh`.

| Task | trapType | Contract under test |
|------|----------|---------------------|
| 051 | `spec_shadowing` | Execution trace beats README/decoy filenames |
| 052 | `two_phase_invariant` | Second invariant catches hidden regression |
| 053 | `rollback_with_sidecar` | Rollback restores workspace, not just main file |
| 054 | `import_cycle_temptation` | Obvious fix must not create import cycles |
| 055 | `poisoned_golden_string` | Golden strings in decoys are insufficient |
| 056 | `chmod_and_symlink_swap` | Stale content between inspect and apply |
| 057 | `concurrent_agent_conflict` | Multi-writer stale recovery |
| 058 | `stale_search_index` | Search is advisory; read is authoritative |
| 059 | `semantic_preservation` | Public API shape preserved while fixing bug |
| 060 | `irreversible_operation_trap` | Destructive shell commands contained |

Additional JSONL metrics: `destructiveCommandBlocked`, `sidecarRollbackClean`, `concurrentMutationDetected`, `searchReadMismatchDetected`, `apiShapePreserved`, `secondInvariantPassed`, `finalVerifyPassed`.

Empirical results: [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md)

### 6.4 Runtime Contract Evaluation Ladder

Phase 2 profiles diagnose **which contract must be visible** before bounded mutation becomes reliable:

| Profile | Contract visibility |
|---------|---------------------|
| `grep_only` | README + parsed grep checks |
| `verify_exec` | + run `verify.sh`, inspect failure output |
| `invariant_aware` | + `verify_invariant.sh` |
| `trace_aware` | + declared trace scripts |
| `contract_full` | + all executable checks (no metadata/golden patch) |
| `recovery_aware` | + validate → apply → verify → rollback/retry loop |

Each agent JSONL row includes `contractCoverage` and `contractReliabilityIndex` (CRI). Reports add a **Failure Attribution Matrix** mapping task × profile → PASS/FAIL with `requiredContract`.

```bash
python3 benchmarks/agent_success/run_benchmark.py --executor agent --agent-profile invariant_aware --mode bridge
make benchmark-contract-ladder   # full nightmare × profile sweep
```

Results: [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md)

---

## 7. Metrics

Each run emits one JSONL `task_result` row:

| Field | Meaning |
|-------|---------|
| `taskSuccess` | Executor completed without exception |
| `verifyPassed` | `verify.sh` exited 0 |
| `wrongFileEdited` | Non-target file changed relative to `before/` |
| `staleRecoverySucceeded` | Recovered from `stale_content` |
| `rollbackSucceeded` | Batch/rollback path preserved workspace integrity |
| `retries` | Recovery retry count |
| `toolCallCount` | RPC / bridge invocations |
| `durationMs` | Wall time |
| `failureCode` | Structured failure token |
| `recoveryHintsUsed` | Runtime recovery hints consumed |
| `commandsUsed` | Command trace |
| `patchValidateFailures` | `patch.validate` rejections |
| `destructiveCommandBlocked` | Tempting destructive command rejected or avoided (nightmare) |
| `sidecarRollbackClean` | Sidecar/cache files removed after rollback (nightmare) |
| `concurrentMutationDetected` | Simulated concurrent writer observed (nightmare) |
| `searchReadMismatchDetected` | Search index disagreed with live read (nightmare) |
| `apiShapePreserved` | Public API unchanged aside from fix (nightmare) |
| `secondInvariantPassed` | `verify_invariant.sh` passed when present |
| `finalVerifyPassed` | Mirrors final `verifyPassed` after all checks |
| `executor` | `reference` or `agent` |
| `mode` | `raw_rpc` or `bridge` |

Final pass requires `taskSuccess` **and** `verifyPassed` (plus `verify_invariant.sh` when shipped).

---

## 8. Reporting

`report_results.py` aggregates JSONL into claim-ready artifacts:

- `results/summary.md` — human-readable report
- `results/summary.json` — machine-readable aggregate

### 8.1 Summary metadata

```json
{
  "generatedAt": "2026-06-08T11:00:00Z",
  "inputFiles": ["benchmarks/agent_success/results/<run-id>.jsonl"],
  "resultRowCount": 60,
  "executorCoverage": { "reference": "present", "agent": "absent" }
}
```

### 8.2 Evaluation claim

Every `summary.md` includes an **Evaluation Claim** section:

- Reference pass rate (e.g. **60/60**) — tool surface solvability
- Agent evaluation constraints — README + verify only
- Adversarial purpose — predictable failure under traps
- Framing sentence — transactional runtime, not autocomplete

### 8.3 Executor coverage

Reports state whether each executor is present or absent:

```text
Executor coverage: reference **present** | agent **absent**
```

Reference-only runs include:

> Agent executor results are not present in this summary.

### 8.4 Money table

| executor | mode | normal pass | adversarial pass | wrong file | rollback | recovery |
|----------|------|------------:|-----------------:|-----------:|---------:|---------:|

This is the primary comparison surface for stakeholders.

### 8.5 Adversarial trap matrix

| trapType | passRate | wrongFileEdited | rollbackSucceeded | recoverySucceeded | avgRetries |
|----------|----------|----------------:|------------------:|------------------:|-----------:|

Per-trap breakdown makes failure modes legible without reading raw JSONL.

---

## 9. Running the benchmark

```bash
# Regenerate fixtures (optional — committed fixtures ship with the repo)
python3 benchmarks/agent_success/generate_fixtures.py

# Full run — rebuild app, restart server, run all tasks, print report
make benchmark-agent-success

# Fast iteration — assumes runtime already matches HEAD
make benchmark-agent-success-fast

# Report only (latest JSONL)
make benchmark-agent-success-report

# Smoke test — report format must not regress
make test-agent-success-report
```

### 9.1 Selective runs

```bash
# Reference baseline, both modes
python3 benchmarks/agent_success/run_benchmark.py --executor reference --mode both --assume-server-ready

# Agent executor, bridge only
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge --assume-server-ready

# Single task
python3 benchmarks/agent_success/run_benchmark.py --task task_021 --executor agent --mode bridge --assume-server-ready
```

---

## 10. Interpreting results

### 10.1 What a healthy reference run looks like

As of benchmark v1.0, the reference executor passes **60/60** tasks (30 tasks × 2 modes):

- Normal pass: 100%
- Adversarial pass: 100%
- Wrong-file edits: 0
- Recovery/rollback events: non-zero on tasks that exercise those paths (expected)

This establishes that fixtures and runtime are aligned. The tool surface is capable.

### 10.2 What agent runs reveal

Agent runs are evaluated separately. Lower adversarial pass rate with classified `wrongFileEdited` events is **informative, not embarrassing** — it means traps are working and failures are bounded.

The desired property:

> The agent performs worse on adversarial tasks, but failures are observable, recoverable, categorized, and bounded.

### 10.3 What this benchmark does not claim

- It does not measure LLM reasoning quality directly (plug in `AGENT_BENCHMARK_AGENT_SCRIPT` for that).
- It does not replace production workload profiling.
- It does not test UI ergonomics or latency at scale.
- It is not a leaderboard — it is an instrument for runtime and agent integration hardening.

---

## 11. Relationship to DietCode runtime

The benchmark exercises the DietCode control plane documented in:

- [Agent Bridge Architecture](../../docs/agent-bridge-architecture.md)
- [Agent Runtime Audit](../../docs/agent-runtime-audit.md)
- [Runtime Invariants](../../docs/runtime-invariants.md)

Key runtime properties under test:

| Property | Benchmark evidence |
|----------|-------------------|
| Deterministic search | Tasks 001–002, 015–018 |
| Patch receipts + stale recovery | Tasks 005–006, 024, 026 |
| Symlink / path containment | Tasks 007–008, 029 |
| Batch atomicity + rollback | Tasks 013–014, 027 |
| Partial-success envelopes | Tasks 009–010, 017–018 |
| Verify-after-mutation | Tasks 019–020 |
| Bridge safe workflows | Mode B across all tasks |

---

## 12. Extending the benchmark

### Adding tasks

1. Add a definition to `TASK_DEFINITIONS` or `ADVERSARIAL_TASKS` in `generate_fixtures.py`
2. Run `python3 benchmarks/agent_success/generate_fixtures.py --task task_NNN`
3. Add a reference workflow in `run_benchmark.py` if needed
4. Verify reference executor passes before evaluating agents

### Adding agents

Implement `AGENT_BENCHMARK_AGENT_SCRIPT` with signature:

```text
your_agent.py --workspace PATH --task TASK_ID --mode bridge|raw_rpc
```

The script must mutate the workspace using DietCode tools. The runner handles verification and metrics.

### Report integrity

`test_report_results.py` guards the claim format. Any change to `summary.md` structure should update the smoke tests.

---

## 13. Conclusion

The DietCode Agent Success Benchmark is a coherent evaluation artifact:

1. **The runtime is capable** — reference executor solvability across 30 tasks and 2 modes.
2. **The agent is constrained** — no metadata cheats in agent mode.
3. **The traps are explicit** — named adversarial scenarios with typed failure modes.
4. **Failures are classified** — wrong-file, rollback, recovery, retries, hints.
5. **Recovery is measurable** — per-trap matrix and money table.

This is the difference between claiming “my IDE has agent tools” and demonstrating that **bounded agent code mutation is a transactional runtime problem** — searchable, patchable, verifiable, recoverable, and reportable.

---

## Appendix A: File reference

| File | Purpose |
|------|---------|
| `generate_fixtures.py` | Task corpus generator |
| `run_benchmark.py` | Benchmark runner |
| `agent_driver.py` | Built-in agent executor |
| `report_results.py` | Report aggregator |
| `test_report_results.py` | Report smoke tests |
| `tasks/task_NNN/` | Fixture repos |
| `results/*.jsonl` | Raw run output |
| `results/summary.md` | Claim-ready report |
| `results/summary.json` | Machine aggregate |

## Appendix B: Makefile targets

| Target | Action |
|--------|--------|
| `benchmark-agent-success` | Rebuild, restart, full run |
| `benchmark-agent-success-fast` | Fast run + report |
| `benchmark-agent-success-report` | Report from latest JSONL |
| `test-agent-success-report` | Report format smoke test |

## Appendix C: Version history

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | June 2026 | Initial release: 30 tasks, dual modes, dual executors, adversarial traps, claim-ready reporting |
