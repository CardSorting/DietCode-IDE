# DietCode Agent Success Benchmark — Results Report

> **Archive note:** Frozen results (June 2026). Live reproduction requires restoring `agent-bridge/` from git history; Makefile benchmark targets were removed. See [ARCHIVE_NOTE.md](ARCHIVE_NOTE.md).

**Empirical results from live runtime evaluation — base corpus (tasks 001–030)**  
Run date: **8 June 2026**  
DietCode runtime: **1.6.5** (control socket)  
Benchmark version: **1.0** (this report) · corpus **v1.1** (40 tasks total)

Methodology: [WHITEPAPER.md](WHITEPAPER.md)

**Related reports:** [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) (051–060) · [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) (profiles)

---

## Corpus state at a glance (June 2026)

| Tier | Tasks | Reference | Agent (`grep_only`) | Report |
|------|-------|-----------|---------------------|--------|
| Normal + adversarial | 001–030 | **60/60** | **30/30** | **this document** |
| Nightmare | 051–060 | **20/20** | **6/10** | [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) |
| Nightmare + profiles | 051–060 | — | **9/10** (`contract_full`) | [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) |

Full reference solvability: **80/80** (40 tasks × `raw_rpc` + `bridge`). Zero wrong-file edits across all live runs.

---

## Executive summary

We ran the Agent Success Benchmark against a live DietCode headless runtime on macOS. Two executors were compared on the 30-task base fixture corpus (normal + adversarial):

| Executor | Mode | Pass rate | Tasks | Wrong-file edits |
|----------|------|----------:|------:|-----------------:|
| **Reference** | `raw_rpc` | **30/30 (100%)** | 30 | 0 |
| **Reference** | `bridge` | **30/30 (100%)** | 30 | 0 |
| **Agent** | `bridge` | **30/30 (100%)** | 30 | 0 |

**Reference (60/60 across both modes)** establishes mechanical solvability: the tool surface and fixtures are correct. Every normal and adversarial task completes and passes external `verify.sh` checks via both raw RPC and the Agent Bridge.

**Agent (30/30 on bridge)** establishes that bounded autonomy *can* survive all traps when constrained to `README.md`, `verify.sh`, and workspace tools only — but at **2.8× latency** and **3.5× tool-call cost** versus the reference bridge baseline, and **without exercising runtime recovery paths** (zero retries, rollbacks, or stale recoveries recorded).

> DietCode evaluates bounded agent code mutation as a transactional runtime problem, not an autocomplete problem.

These results support five concrete claims:

1. **The runtime is capable** — reference executor, 100% pass, both stacks.
2. **The agent is constrained** — no metadata, golden patch, or trap bindings in agent mode.
3. **The traps are explicit** — ten named adversarial scenarios, all verifiable post-hoc.
4. **Failures are classifiable** — metrics captured even when pass rate is 100%.
5. **Recovery is measurable** — reference runs recorded 6 stale recoveries and 4 rollback successes; agent runs recorded none.

**Subsequent tiers:** nightmare tasks (051–060) break the agent's 100% pass rate (6/10 at `grep_only`). The [Runtime Contract Evaluation Ladder](RESULTS_CONTRACT_LADDER.md) shows which contract visibility unlocks each trap — e.g. task 052 requires `invariant_aware`, tasks 055/059 require `verify_exec`.

---

## 1. Run configuration

| Parameter | Value |
|-----------|-------|
| Host OS | macOS (darwin 25.2.0) |
| DietCode server | `DietCodeControlServer` v1.6.5 |
| Socket | `~/.dietcode/control.sock` |
| Tasks | 30 (`task_001` – `task_030`) |
| Normal tasks | 20 |
| Adversarial tasks | 10 |
| Bridge build | `agent-bridge/` (restore from git history) |

### Source artifacts

| Run | Executor | Mode | JSONL |
|-----|----------|------|-------|
| R1 | `reference` | `raw_rpc` + `bridge` | `results/20260608T110053Z.jsonl` |
| R2 | `agent` | `bridge` | `results/paper_agent_bridge_20260608.jsonl` |

Combined reference run: **60 result rows** (30 tasks × 2 modes).  
Agent run: **30 result rows** (30 tasks × 1 mode).

---

## 2. Reference executor results

The reference executor uses workflow bindings and golden `expected.patch` files. It is the **solvability control**.

### 2.1 Aggregate

| Mode | Passed | Pass rate | Avg duration | Avg tool calls | Retries | Rollback | Stale recovery |
|------|-------:|----------:|-------------:|---------------:|--------:|---------:|---------------:|
| `bridge` | 30/30 | 100% | **232 ms** | **2.8** | 4 | 2 | 3 |
| `raw_rpc` | 30/30 | 100% | **141 ms** | **4.9** | 4 | 2 | 3 |

`raw_rpc` is **39% faster** per task but uses **75% more tool calls** than bridge — the bridge collapses multi-step validate/apply flows into safe workflows.

### 2.2 Normal vs adversarial (reference, bridge mode)

| Split | Passed | Pass rate |
|-------|-------:|----------:|
| Normal (001–020) | 20/20 | 100% |
| Adversarial (021–030) | 10/10 | 100% |

Wrong-file edits: **0** across all 60 reference rows.

### 2.3 Recovery and rollback events (reference only)

These tasks intentionally exercise transactional recovery. The reference executor recorded:

| Task | Trap / category | Mode(s) | Retries | Stale recovery | Rollback | Recovery hint |
|------|-----------------|---------|--------:|----------------|----------|---------------|
| 005 | stale_content_recovery | both | 1 | ✓ | — | `revalidate_patch_with_patch.validate` |
| 006 | stale_content_recovery | both | 1 | ✓ | — | `revalidate_patch_with_patch.validate` |
| 014 | batch_rollback | both | 0 | — | ✓ | `revalidate_patch_with_patch.validate` (rpc) |
| 024 | recover_from_failed_patch | both | 1 | — | — | — |
| 026 | stale_read_recovery | both | 1 | ✓ | — | `revalidate_patch_with_patch.validate` |
| 027 | rollback_after_corruption | both | 0 | — | ✓ | — |

**Total across 60 reference rows:** 4 retries, 6 stale-recovery successes, 4 rollback successes, 0 patch-validate failures.

### 2.4 Recovery hints consumed (reference, `raw_rpc`)

| Hint | Count |
|------|------:|
| `revalidate_patch_with_patch.validate` | 5 |
| `use_search_literal_or_search_tokens` | 2 |
| `use_non_symlink_target_path` | 1 |
| `use_workspace_relative_path` | 1 |
| `use_shell_head_tail_or_sedRange` | 1 |
| `paginate_with_resultOffset` | 1 |
| `narrow_include_glob` | 1 |

Hints appear on expected recovery paths — the runtime is emitting structured guidance, not silent failure.

---

## 3. Agent executor results

The agent executor (`agent_driver.py`) reads only `README.md` and `verify.sh`, then uses bridge tools. No `metadata.json`, no `expected.patch`, no `trapType`.

### 3.1 Aggregate (bridge mode)

| Metric | Value |
|--------|------:|
| Passed | **30/30 (100%)** |
| Normal | 20/20 |
| Adversarial | 10/10 |
| Avg duration | **649 ms** |
| Avg tool calls | **9.7** |
| Retries | 0 |
| Rollback succeeded | 0 |
| Stale recovery succeeded | 0 |
| Wrong-file edits | 0 |
| Patch validate failures | 0 |
| Recovery hints used | 0 |

### 3.2 Interpretation

The built-in agent passes all tasks because it **parses acceptance criteria from `verify.sh`** and applies goal-directed patches. This is honest bounded autonomy: the agent must still discover targets via search and read tools, but it does not need to infer goals from an incomplete README alone.

Important distinction for readers:

| Property | Reference | Agent (built-in) |
|----------|-----------|------------------|
| Reads `verify.sh` | No (uses golden patch) | **Yes** |
| Reads `metadata.json` | Yes | **No** |
| Exercises stale/rollback stress paths | **Yes** (by workflow design) | **No** (single-shot goal patch) |
| Pass rate this run | 100% | 100% |
| Cost | Lower | **~3.5× tool calls, ~2.8× time** |

An external LLM agent that **does not** read `verify.sh` is expected to score lower on adversarial tasks 022 (verify-only), 028 (noop trap), and 021/030 (decoy/ambiguous symbol) — that is the intended stress surface.

---

## 4. Head-to-head comparison (bridge mode, 30 tasks)

| Task | Category | Ref tools | Agent tools | Ref ms | Agent ms | Ref retries | Agent retries |
|------|----------|----------:|------------:|-------:|---------:|------------:|--------------:|
| 001 | literal_search_patch | 2 | 9 | 214 | 716 | 0 | 0 |
| 002 | literal_search_patch | 2 | 9 | 216 | 600 | 0 | 0 |
| 003 | multi_file_patch | 2 | 12 | 310 | 874 | 0 | 0 |
| 004 | multi_file_patch | 1 | 15 | 352 | 1180 | 0 | 0 |
| 005 | stale_content_recovery | 5 | 9 | 158 | 591 | 1 | 0 |
| 006 | stale_content_recovery | 5 | 9 | 166 | 587 | 1 | 0 |
| 007 | symlink_rejection | 2 | 9 | 134 | 556 | 0 | 0 |
| 008 | symlink_rejection | 2 | 9 | 135 | 503 | 0 | 0 |
| 009 | large_file_avoidance | 3 | 9 | 243 | 571 | 0 | 0 |
| 010 | large_file_avoidance | 3 | 9 | 197 | 542 | 0 | 0 |
| 011 | shell_rg_sed | 3 | 9 | 276 | 586 | 0 | 0 |
| 012 | shell_rg_sed | 3 | 9 | 280 | 588 | 0 | 0 |
| 013 | batch_rollback | 2 | 12 | 363 | 843 | 0 | 0 |
| 014 | batch_rollback | 2 | 12 | 369 | 842 | 0 | 0 |
| 015 | semantic_recovery | 2 | 9 | 284 | 585 | 0 | 0 |
| 016 | semantic_recovery | 3 | 9 | 337 | 586 | 0 | 0 |
| 017 | partial_truncated | 2 | 9 | 223 | 586 | 0 | 0 |
| 018 | partial_truncated | 2 | 9 | 223 | 589 | 0 | 0 |
| 019 | verify_after_mutation | 2 | 9 | 220 | 587 | 0 | 0 |
| 020 | verify_after_mutation | 2 | 12 | 314 | 891 | 0 | 0 |
| 021 | wrong_file_decoy | 3 | 9 | 274 | 587 | 0 | 0 |
| 022 | verify_only_requirement | 2 | 9 | 215 | 579 | 0 | 0 |
| 023 | preserve_partial_fix | 2 | 9 | 215 | 590 | 0 | 0 |
| 024 | recover_from_failed_patch | 4 | 9 | 114 | 581 | 1 | 0 |
| 025 | multi_file_coordination | 5 | 11 | 215 | 750 | 0 | 0 |
| 026 | stale_read_recovery | 5 | 9 | 158 | 588 | 1 | 0 |
| 027 | rollback_after_corruption | 5 | 9 | 201 | 589 | 0 | 0 |
| 028 | noop_success_trap | 4 | 9 | 114 | 616 | 0 | 0 |
| 029 | path_containment_decoy | 2 | 9 | 221 | 594 | 0 | 0 |
| 030 | ambiguous_symbol_choice | 2 | 9 | 219 | 589 | 0 | 0 |

**Efficiency summary (bridge):**

| Metric | Reference | Agent | Ratio (agent ÷ ref) |
|--------|----------:|------:|--------------------:|
| Mean tool calls | 2.8 | 9.7 | **3.5×** |
| Mean duration | 232 ms | 649 ms | **2.8×** |
| Max duration | 369 ms | 1180 ms | 3.2× (task 004) |

The agent driver uses a consistent search → stat → read → patch loop (~9 tool calls/task). The reference executor uses workflow-shortcut paths (1–5 calls) and is the efficiency ceiling.

---

## 5. Adversarial trap matrix (reference, both modes combined)

| trapType | passRate | wrongFileEdited | rollbackSucceeded | recoverySucceeded | avgRetries |
|----------|----------:|----------------:|------------------:|------------------:|-----------:|
| ambiguous_symbol_choice | 100% | 0 | 0 | 0 | 0 |
| multi_file_coordination | 100% | 0 | 0 | 0 | 0 |
| noop_success_trap | 100% | 0 | 0 | 0 | 0 |
| path_containment_decoy | 100% | 0 | 0 | 0 | 0 |
| preserve_partial_fix | 100% | 0 | 0 | 0 | 0 |
| recover_from_failed_patch | 100% | 0 | 0 | 0 | **1.0** |
| rollback_after_corruption | 100% | 0 | **2** | 0 | 0 |
| stale_read_recovery | 100% | 0 | 0 | **2** | **1.0** |
| verify_only_requirement | 100% | 0 | 0 | 0 | 0 |
| wrong_file_decoy | 100% | 0 | 0 | 0 | 0 |

Reference passes all traps while recording recovery/rollback on the tasks designed to produce them. The matrix is **non-zero on stress dimensions** even at 100% pass rate — demonstrating that the instrumentation works.

### Adversarial trap matrix (agent, bridge)

| trapType | passRate | wrongFileEdited | rollbackSucceeded | recoverySucceeded | avgRetries |
|----------|----------:|----------------:|------------------:|------------------:|-----------:|
| *(all 10 traps)* | 100% | 0 | 0 | 0 | 0 |

Agent passes all traps in this run but **does not surface recovery/rollback metrics** — a gap that external agents with organic stale failures would populate.

---

## 6. Money table (this evaluation)

| executor | mode | normal pass | adversarial pass | wrong file | rollback | recovery |
|----------|------|------------:|-----------------:|-----------:|---------:|---------:|
| reference | bridge | 100% | 100% | 0 | 2 | 3 |
| reference | raw_rpc | 100% | 100% | 0 | 2 | 3 |
| agent | bridge | 100% | 100% | 0 | 0 | 0 |

---

## 7. Evaluation claim (this run)

Executor coverage in this report: reference **present** | agent **present** (bridge only).

The reference executor passed **60/60** tasks, demonstrating that the tool surface and fixtures are mechanically solvable across both `raw_rpc` and `bridge` modes.

The agent executor passed **30/30** tasks on `bridge`, using only `README.md`, `verify.sh`, and workspace inspection. It was denied `metadata.json`, `expected.patch`, `trapType`, and workflow bindings.

Adversarial tasks were all verified post-mutation. Reference runs recorded bounded recovery (6 stale recoveries, 4 rollbacks) on stress-path tasks. Agent runs completed without wrong-file edits but also without exercising those recovery paths in this run.

> DietCode evaluates bounded agent code mutation as a transactional runtime problem, not an autocomplete problem.

---

## 8. What these results prove

### Proven

- **End-to-end solvability** — search, inspect, patch, verify, recover, and rollback workflows complete on all 30 fixtures.
- **Bridge parity** — Agent Bridge safe workflows match raw RPC pass rate (100%).
- **Adversarial verifiability** — all ten trap types pass external verification when solved correctly.
- **Instrumentation** — recovery hints, retries, rollbacks, and wrong-file flags are emitted and aggregatable.
- **Agent honesty constraint is enforceable** — agent driver operates without golden patches or trap metadata.

### Not proven by this run

- **LLM agent performance** — built-in agent is verify-driven, not a language model.
- **Agent failure under traps** — 100% agent pass means decoy/symbol/noop traps did not fool this driver; external agents are the next evaluation target.
- **Production-scale latency** — mean task duration is sub-second on tiny fixtures.
- **Cross-platform reproducibility** — single host, single runtime version.

---

## 9. Recommended next runs (archived)

To re-run live evaluation, restore `agent-bridge/` from git history first (see [ARCHIVE_NOTE.md](ARCHIVE_NOTE.md)). Example:

```bash
# External LLM agent (does not read verify.sh by default)
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/llm_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge --assume-server-ready

# Combined report (requires restored Makefile targets)
# make benchmark-agent-success-report
```

Compare money-table adversarial pass rates and `wrongFileEditedByTrapType` counts. The expected outcome for naive agents:

> Lower adversarial pass rate, non-zero wrong-file edits on decoy/ambiguous traps, with failures that are observable, categorized, and bounded.

---

## 10. Reproducing these results (archived)

Restore `agent-bridge/` and Makefile benchmark targets from git history before running.

```bash
# Reference baseline (60 rows) — target removed from coherence-core Makefile
# make benchmark-agent-success-fast

# Agent bridge run
python3 benchmarks/agent_success/run_benchmark.py \
  --executor agent --mode bridge --assume-server-ready \
  --run-id paper_agent_bridge_$(date -u +%Y%m%d)

# Report
python3 benchmarks/agent_success/report_results.py \
  --input benchmarks/agent_success/results/20260608T110053Z.jsonl
```

---

## Appendix: per-category pass rates (reference, bridge)

| Category | Passed |
|----------|-------:|
| literal_search_patch | 2/2 |
| multi_file_patch | 2/2 |
| stale_content_recovery | 2/2 |
| symlink_rejection | 2/2 |
| large_file_avoidance | 2/2 |
| shell_rg_sed | 2/2 |
| batch_rollback | 2/2 |
| semantic_recovery | 2/2 |
| partial_truncated | 2/2 |
| verify_after_mutation | 2/2 |
| wrong_file_decoy | 1/1 |
| verify_only_requirement | 1/1 |
| preserve_partial_fix | 1/1 |
| recover_from_failed_patch | 1/1 |
| multi_file_coordination | 1/1 |
| stale_read_recovery | 1/1 |
| rollback_after_corruption | 1/1 |
| noop_success_trap | 1/1 |
| path_containment_decoy | 1/1 |
| ambiguous_symbol_choice | 1/1 |

---

*Generated from live JSONL artifacts. See `results/20260608T110053Z.jsonl` and `results/paper_agent_bridge_20260608.jsonl`. Nightmare and ladder results: [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md), [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md).*
