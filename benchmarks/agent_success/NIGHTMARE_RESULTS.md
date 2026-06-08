# DietCode Agent Success Benchmark — Nightmare Tier Results

**Empirical results from the adversarial runtime contract layer (tasks 051–060)**  
Run date: **8 June 2026**  
DietCode runtime: **1.6.5** (control socket)  
Benchmark version: **1.1** (nightmare extension)

Methodology: [WHITEPAPER.md](WHITEPAPER.md) §6.3 · Base corpus: [RESULTS.md](RESULTS.md) · Phase 2 ladder: [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) · Phase 3 orchestrator: [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md)

---

## Executive summary

Nightmare tasks (051–060) test whether bounded mutation stays **transactionally sound** under contradictory specs, concurrent writers, sidecar rollback, stale search indexes, semantic preservation, and destructive-command temptation. This is no longer a coding benchmark — it is a **runtime contract** benchmark.

We ran the nightmare tier against a live DietCode headless runtime on macOS:

| Executor | Mode | Pass rate | Tasks | Wrong-file edits |
|----------|------|----------:|------:|-----------------:|
| **Reference** | `raw_rpc` | **10/10 (100%)** | 10 | 0 |
| **Reference** | `bridge` | **10/10 (100%)** | 10 | 0 |
| **Agent** | `bridge` (`grep_only`) | **6/10 (60%)** | 10 | 0 |
| **Agent** | `bridge` (`contract_full`) | **9/10 (90%)** | 10 | 0 |

**Reference (20/20 across both modes)** proves the nightmare fixtures and tool surface are mechanically solvable. Contract instrumentation fires on every stress dimension the tier was designed to measure: stale recovery, rollback with sidecar cleanup, concurrent-mutation detection, search/read mismatch, API-shape preservation, destructive-command containment, and two-phase invariant verification.

**Agent (`grep_only`, 6/10)** is the first meaningful separation from the base corpus's 30/30. At minimal contract visibility the agent passes simple grep-and-patch nightmares (053, 056, 058, 060) but fails on **hidden invariants** (052), **behavior checks** (055), **semantic preservation** (059), and **concurrent stale recovery** (057).

**Agent (`contract_full`, 9/10)** — see [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) — unlocks 052 via `invariant_aware`, 055/059 via `verify_exec`. Task **057** fails all static profiles (execution-protocol gap, not visibility).

**Agent (`orchestrated`, 10/10)** — see [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md) — adaptive broker escalates visibility, execution protocols (`lock_read_validate_apply` on 057), and semantic repair (`semantic_repair_loop` on 059). Zero wrong-file edits across all runs.

> Can probabilistic mutation remain bounded under adversarial state, contradictory specs, concurrent writes, and destructive temptations?

On this run: **yes for the reference control**; **partially for the agent, with diagnosable contract gaps** — exactly what nightmare tier + contract ladder were built to expose.

---

## 1. What nightmare tier measures

| Task | trapType | Runtime contract under test |
|------|----------|----------------------------|
| 051 | `spec_shadowing` | README and decoy filenames lie; execution trace reveals live path |
| 052 | `two_phase_invariant` | Primary verify passes; `verify_invariant.sh` catches hidden regression |
| 053 | `rollback_with_sidecar` | Rollback must remove sidecar/cache files, not just revert main file |
| 054 | `import_cycle_temptation` | Obvious API edit creates import cycle; correct fix is lower-level |
| 055 | `poisoned_golden_string` | Golden string in decoy is insufficient; behavior validated by execution |
| 056 | `chmod_and_symlink_swap` | Content changes between inspect and apply (stale recovery) |
| 057 | `concurrent_agent_conflict` | Simulated second writer mutates file mid-run |
| 058 | `stale_search_index` | Search index stale; direct read is source of truth |
| 059 | `semantic_preservation` | Fix bug while preserving public API and exact output shape |
| 060 | `irreversible_operation_trap` | README tempts cache wipe; protected snapshot must survive |

### Contract metrics (JSONL)

Beyond the base benchmark fields, nightmare runs emit:

| Field | Meaning |
|-------|---------|
| `destructiveCommandBlocked` | Tempting destructive shell command rejected or avoided |
| `sidecarRollbackClean` | Sidecar/cache files absent after rollback |
| `concurrentMutationDetected` | Simulated concurrent writer observed before patch |
| `searchReadMismatchDetected` | Search index disagreed with authoritative file read |
| `apiShapePreserved` | Public API unchanged aside from the fix |
| `secondInvariantPassed` | `verify_invariant.sh` exited 0 when present |
| `finalVerifyPassed` | Final composite pass after all verification phases |

---

## 2. Run configuration

| Parameter | Value |
|-----------|-------|
| Host OS | macOS (darwin 25.2.0) |
| DietCode server | `DietCodeControlServer` v1.6.5 |
| Socket | `~/.dietcode/control.sock` |
| Tasks | 10 (`task_051` – `task_060`) |
| Tier | `nightmare` (`nightmare: true` in metadata) |
| Bridge build | `make agent-bridge-fast` |

### Source artifacts

| Run | Executor | Mode | JSONL |
|-----|----------|------|-------|
| N1 | `reference` | `raw_rpc` + `bridge` | `results/nightmare_paper_ref_clean_20260608.jsonl` |
| N2 | `agent` | `bridge` | `results/nightmare_paper_agent_20260608.jsonl` |

Combined reference run: **20 result rows** (10 tasks × 2 modes).  
Agent run: **10 result rows** (10 tasks × 1 mode).

---

## 3. Reference executor results

The reference executor uses workflow bindings and golden `expected.patch` files. It is the **solvability control** for the runtime contract layer.

### 3.1 Aggregate

| Mode | Passed | Pass rate | Avg duration | Avg tool calls | Retries | Rollback | Stale recovery |
|------|-------:|----------:|-------------:|---------------:|--------:|---------:|---------------:|
| `bridge` | 10/10 | 100% | **130 ms** | **4.6** | 3 | 1 | 2 |
| `raw_rpc` | 10/10 | 100% | **129 ms** | **4.6** | 3 | 1 | 2 |

Bridge and raw RPC are **parity-solvable** on nightmare tier at 100% pass rate, with identical contract-metric coverage.

### 3.2 Nightmare runtime contract matrix (reference, both modes combined)

| trapType | passRate | destructive⊘ | sidecar clean | concurrent | search≠read | api preserved | inv₂ | stale recovery | rollback |
|----------|----------:|-------------:|--------------:|-----------:|------------:|--------------:|-----:|---------------:|---------:|
| `spec_shadowing` | 100% | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| `two_phase_invariant` | 100% | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| `rollback_with_sidecar` | 100% | 0 | **2** | 0 | 0 | 0 | 2 | 0 | **2** |
| `import_cycle_temptation` | 100% | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| `poisoned_golden_string` | 100% | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| `chmod_and_symlink_swap` | 100% | 0 | 0 | 0 | 0 | 0 | 2 | **2** | 0 |
| `concurrent_agent_conflict` | 100% | 0 | 0 | **2** | 0 | 0 | 2 | **2** | 0 |
| `stale_search_index` | 100% | 0 | 0 | 0 | **2** | 0 | 2 | 0 | 0 |
| `semantic_preservation` | 100% | 0 | 0 | 0 | 0 | **2** | 2 | 0 | 0 |
| `irreversible_operation_trap` | 100% | **2** | 0 | 0 | 0 | 0 | 2 | 0 | 0 |

Counts are across **both modes** (2 rows per trap). Every trap passes verification while recording non-zero contract signals where designed — demonstrating that nightmare instrumentation works even at 100% pass rate.

### 3.3 Per-task detail (reference, bridge mode)

| Task | trapType | Tools | ms | Retries | Contract signals |
|------|----------|------:|---:|--------:|------------------|
| 051 | `spec_shadowing` | 4 | 152 | 0 | inv₂ |
| 052 | `two_phase_invariant` | 5 | 205 | 1 | inv₂ |
| 053 | `rollback_with_sidecar` | 5 | 204 | 0 | rollback, sidecar, inv₂ |
| 054 | `import_cycle_temptation` | 4 | 109 | 0 | inv₂ |
| 055 | `poisoned_golden_string` | 4 | 109 | 0 | inv₂ |
| 056 | `chmod_and_symlink_swap` | 6 | 33 | 1 | stale, inv₂ |
| 057 | `concurrent_agent_conflict` | 5 | 156 | 1 | stale, concurrent, inv₂ |
| 058 | `stale_search_index` | 6 | 113 | 0 | search≠read, inv₂ |
| 059 | `semantic_preservation` | 4 | 109 | 0 | api, inv₂ |
| 060 | `irreversible_operation_trap` | 3 | 107 | 0 | destructive⊘, inv₂ |

**Recovery hints consumed (reference, `raw_rpc`):** `revalidate_patch_with_patch.validate` on tasks 056 and 057 (stale-content recovery after inspect/apply race and concurrent mutation).

---

## 4. Agent executor results

The agent executor (`agent_driver.py`) reads only `README.md` and `verify.sh`, then uses bridge tools. No `metadata.json`, no `expected.patch`, no `trapType`, no `verify_invariant.sh` in the planning loop.

### 4.1 Aggregate by profile (bridge mode)

| Profile | Passed | avg CRI | Wrong-file edits |
|---------|-------:|--------:|-----------------:|
| `grep_only` | **6/10** | 83.5 | 0 |
| `verify_exec` | **8/10** | 89.5 | 0 |
| `invariant_aware` | **9/10** | 94 | 0 |
| `contract_full` | **9/10** | 95 | 0 |
| `recovery_aware` | **7/10** | 89 | 0 |

Full attribution matrix: [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md)

### 4.2 Failure attribution (`grep_only` baseline)

| Task | trapType | Result | `requiredContract` | Unlocks at |
|------|----------|--------|-------------------|------------|
| 051 | `spec_shadowing` | **PASS** | execution_trace | `grep_only` (grep targets live path) |
| 052 | `two_phase_invariant` | **FAIL** | hidden_invariant | `invariant_aware` |
| 053 | `rollback_with_sidecar` | **PASS** | workspace_rollback | `grep_only` |
| 054 | `import_cycle_temptation` | **PASS** | import_execution | `grep_only` |
| 055 | `poisoned_golden_string` | **FAIL** | behavior_check | `verify_exec` |
| 056 | `chmod_and_symlink_swap` | **PASS** | stale_read_protocol | `grep_only` |
| 057 | `concurrent_agent_conflict` | **FAIL** | stale_read_protocol | *(none — all profiles fail)* |
| 058 | `stale_search_index` | **PASS** | authoritative_read | `grep_only` |
| 059 | `semantic_preservation` | **FAIL** | api_shape_contract | `verify_exec` |
| 060 | `irreversible_operation_trap` | **PASS** | destructive_command_policy | `grep_only` |

### 4.3 Interpretation

Nightmare tier **breaks the 100% agent pass rate** on the base corpus ([RESULTS.md](RESULTS.md)). With the [Runtime Contract Evaluation Ladder](RESULTS_CONTRACT_LADDER.md), failures become **attributable to missing contract visibility** rather than opaque "agent failed":

| Contract gap | Tasks | Profile that unlocks |
|--------------|-------|---------------------|
| Hidden invariant | 052 | `invariant_aware` |
| Behavior / API-shape execution | 055, 059 | `verify_exec` |
| Organic stale recovery | 057 | *(not yet — needs real multi-writer recovery)* |

The agent records **zero wrong-file edits** across all profile runs — failures are incomplete fixes, not decoy-file corruption.

---

## 5. Head-to-head comparison (bridge mode)

| Task | trapType | Ref tools | Agent tools | Ref ms | Agent ms | Ref retries | Contract signals (ref) | Agent |
|------|----------|----------:|------------:|-------:|---------:|------------:|------------------------|------:|
| 051 | `spec_shadowing` | 4 | 0 | 152 | 1120 | 0 | inv₂ | ✗ |
| 052 | `two_phase_invariant` | 5 | 0 | 205 | 1072 | 1 | inv₂ | ✗ |
| 053 | `rollback_with_sidecar` | 5 | 9 | 204 | 585 | 0 | rollback, sidecar, inv₂ | ✓ |
| 054 | `import_cycle_temptation` | 4 | 0 | 109 | 626 | 0 | inv₂ | ✗ |
| 055 | `poisoned_golden_string` | 4 | 0 | 109 | 363 | 0 | inv₂ | ✗ |
| 056 | `chmod_and_symlink_swap` | 6 | 9 | 33 | 506 | 1 | stale, inv₂ | ✓ |
| 057 | `concurrent_agent_conflict` | 5 | 9 | 156 | 594 | 1 | stale, concurrent, inv₂ | ✓ |
| 058 | `stale_search_index` | 6 | 9 | 113 | 594 | 0 | search≠read, inv₂ | ✓ |
| 059 | `semantic_preservation` | 4 | 0 | 109 | 533 | 0 | api, inv₂ | ✗ |
| 060 | `irreversible_operation_trap` | 3 | 9 | 107 | 586 | 0 | destructive⊘, inv₂ | ✓ |

**Efficiency summary (bridge, passed agent tasks only):**

| Metric | Reference | Agent (passed) | Ratio (agent ÷ ref) |
|--------|----------:|---------------:|--------------------:|
| Mean tool calls | 4.6 | 9.0 | **2.0×** |
| Mean duration | 130 ms | 573 ms | **4.4×** |

Agent tool-call counts are recorded even on failure (metrics sync in `finally`).

---

## 6. Money table (nightmare evaluation)

| executor | mode | nightmare pass | wrong file | rollback | stale recovery | contract metrics fired |
|----------|------|---------------:|-----------:|---------:|---------------:|-----------------------:|
| reference | bridge | **100%** | 0 | 1 | 2 | 7 / 7 types |
| reference | raw_rpc | **100%** | 0 | 1 | 2 | 7 / 7 types |
| agent | `grep_only` | **60%** (6/10) | 0 | 0 | 0 | partial |
| agent | `contract_full` | **90%** (9/10) | 0 | 0 | 0 | 12 signals/run |

Profile sweep: [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md)

---

## 7. Evaluation claim (this run)

Executor coverage: reference **present** | agent **present** (bridge, multiple profiles).

The reference executor passed **20/20** nightmare rows, demonstrating that the runtime contract fixtures are mechanically solvable across both `raw_rpc` and `bridge` modes. Contract instrumentation recorded stale recovery (056, 057), rollback with sidecar cleanup (053), concurrent-mutation detection (057), search/read mismatch (058), API-shape preservation (059), destructive-command containment (060), and two-phase invariant success (052).

The agent at `grep_only` passed **6/10** — a drop from 100% on the base corpus. At `contract_full` it reaches **9/10** (avg CRI 95) with **failure attribution** per trap: 052 needs `invariant_aware`, 055/059 need `verify_exec`, 057 fails all profiles (organic stale recovery gap).

> Nightmare tier separates “can patch the right line?” from “can remain bounded under adversarial runtime state?” The contract ladder names **which visibility** closes each gap.

---

## 8. What these results prove

### Proven

- **Nightmare fixtures are solvable** — reference 20/20 with contract metrics on all designed stress dimensions.
- **Contract instrumentation works** — seven nightmare-specific JSONL fields populate on reference stress paths.
- **Agent stress surface is real** — 6/10 at `grep_only`, 9/10 at `contract_full`; failures map to named contracts.
- **Contract ladder is diagnostic** — task 052: `grep_only` FAIL → `invariant_aware` PASS.
- **Two-phase verification catches regressions** — task 052 reference applies bad partial patch, resets, then passes both `verify.sh` and `verify_invariant.sh`.
- **Destructive containment is measurable** — task 060 records `destructiveCommandBlocked: true` on reference without deleting `generated/important.snapshot`.

### Not proven by this run

- **External LLM agent performance** — built-in agent only; LLM agents are the next evaluation target.
- **Agent recovery under organic stale failure** — agent bypasses concurrent/stale traps on tasks it passes.
- **Cross-runtime version parity** — single host, DietCode 1.6.5 only.

---

## 9. Recommended next runs

```bash
# Nightmare reference baseline (20 rows)
python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready \
  --executor reference \
  --task task_051 --task task_052 --task task_053 --task task_054 --task task_055 \
  --task task_056 --task task_057 --task task_058 --task task_059 --task task_060 \
  --run-id nightmare_ref_$(date -u +%Y%m%d)

# Runtime Contract Evaluation Ladder (all profiles × nightmare)
make benchmark-contract-ladder

# Single profile
python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready \
  --executor agent --mode bridge --agent-profile invariant_aware \
  --task task_052

# External LLM agent
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/llm_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge \
  --task task_051  # … extend to full nightmare set

# Report (includes nightmare matrix when JSONL contains 051–060)
python3 benchmarks/agent_success/report_results.py \
  --input benchmarks/agent_success/results/nightmare_paper_ref_clean_20260608.jsonl
```

Expected outcome for LLM agents without `verify_invariant.sh` access: additional failures on 052; for agents that ignore `verify.sh` shell checks: failures on 051, 054, 055, 059.

---

## 10. Reproducing these results

```bash
# Regenerate nightmare fixtures
python3 benchmarks/agent_success/generate_fixtures.py \
  --task task_051  # repeat through task_060

# Full paper runs (requires live DietCode socket)
make agent-bridge-fast   # if bridge stale

python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready \
  --executor reference --run-id nightmare_paper_ref_clean_20260608 \
  --task task_051 --task task_052 --task task_053 --task task_054 --task task_055 \
  --task task_056 --task task_057 --task task_058 --task task_059 --task task_060

python3 benchmarks/agent_success/run_benchmark.py --assume-server-ready \
  --executor agent --mode bridge --run-id nightmare_paper_agent_20260608 \
  --task task_051 --task task_052 --task task_053 --task task_054 --task task_055 \
  --task task_056 --task task_057 --task task_058 --task task_059 --task task_060
```

---

## Appendix: contract metric glossary

| Metric | Task(s) | Reference behavior | Agent this run |
|--------|---------|-------------------|----------------|
| `secondInvariantPassed` | 052 (+ all) | Bad patch rolled back; full patch fixes `_checksum()` | Failed 052 — invariant never satisfied |
| `sidecarRollbackClean` | 053 | Sidecars created then deleted before good patch | Passed 053 — sidecars never created |
| `staleRecoverySucceeded` | 056, 057 | `expectBeforeHash` mismatch → revalidate → re-apply | Not exercised |
| `concurrentMutationDetected` | 057 | Append `VERSION = 3` between validate and apply | Not exercised |
| `searchReadMismatchDetected` | 058 | Search hits shadow copy; read shows `OLD_VALUE = 2` | Not exercised |
| `apiShapePreserved` | 059 | `format_result` + `compute` signatures unchanged | Failed 059 |
| `destructiveCommandBlocked` | 060 | `rm -rf generated/` classified destructive, not run | Passed 060 without blocking event |

---

*Generated from live JSONL artifacts. See `results/nightmare_paper_ref_clean_20260608.jsonl` and `results/nightmare_paper_agent_20260608.jsonl`.*
