# DietCode Agent Success Benchmark

**A whitepaper on evaluating bounded agent code mutation as a transactional runtime problem**

Version 1.2 · June 2026  
Location: `benchmarks/agent_success/`

**Live results:** [RESULTS.md](RESULTS.md) (001–030) · [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) (051–060) · [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) (profiles)

---

## Abstract

Most “agent IDE” evaluations conflate four distinct questions:

1. Can the **tool surface** perform safe code mutation end-to-end?
2. Can an **autonomous agent** use that surface under realistic constraints?
3. When autonomy fails, are failures **observable, categorized, and bounded**?
4. **Which runtime contract** must be visible before bounded mutation becomes reliable?

The DietCode Agent Success Benchmark answers these separately. It provides **40 deterministic fixture tasks** in three tiers (normal, adversarial, nightmare), two runtime modes (`raw_rpc` and `bridge`), two executors (`reference` and `agent`), six **agent contract profiles** (Runtime Contract Evaluation Ladder), and claim-ready reporting with mutation telemetry comparable to observability maturity models.

> **Thesis:** DietCode evaluates bounded agent code mutation as a transactional runtime problem, not an autocomplete problem.

**Live state (June 2026, DietCode 1.6.5):** reference **80/80** (40 tasks × 2 modes); agent **30/30** on base corpus; nightmare **6/10** at `grep_only`, **9/10** at `contract_full`. See result papers linked above.

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
| Nightmare tier | Does mutation stay bounded under adversarial runtime state? |
| Contract ladder | Which contract visibility unlocks each trap? |
| Report | Are outcomes classified, attributable, and comparable? |

The pipeline mirrors industry eval / safety / observability patterns:

```text
benchmark corpus (40 tasks)
  → profiles (contract visibility ladder)
  → metrics (pass, wrong-file, recovery, rollback, invariants, CRI)
  → telemetry (JSONL event stream)
  → reports (summary, trap matrix, failure attribution)
  → CI gate (reference solvability + contract metric regression)
  → versioned claims (benchmark v1.1, runtime 1.6.5, run IDs)
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
├── generate_fixtures.py       # Corpus generator (001–030, 051–060)
├── nightmare_tasks_defs.py    # Nightmare-tier definitions
├── run_benchmark.py           # Runner: modes × executors × profiles
├── agent_driver.py            # Agent executor (6 contract profiles)
├── contract_ladder.py         # Profile caps, CRI, required-contract map
├── run_contract_ladder.py     # Nightmare × profile orchestrator
├── render_contract_ladder.py  # Ladder report generator
├── report_results.py          # Claim-ready aggregation
├── test_report_results.py     # Report smoke tests
├── test_contract_ladder.py    # Ladder smoke tests
├── tasks/task_NNN/            # Per-task fixtures
│   ├── README.md
│   ├── before/
│   ├── expected.patch         # Reference executor only
│   ├── verify.sh              # (+ verify_invariant.sh on nightmare)
│   └── metadata.json
├── RESULTS.md                 # Base corpus live results
├── NIGHTMARE_RESULTS.md       # Nightmare tier live results
├── RESULTS_CONTRACT_LADDER.md # Profile sweep live results
└── results/                   # JSONL + summary (gitignored)
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

The agent executor (`agent_driver.py`) simulates bounded autonomy with **Runtime Contract Evaluation profiles**:

| Profile | Contract visibility |
|---------|---------------------|
| `grep_only` (default) | README + parsed grep checks |
| `verify_exec` | + run `verify.sh`, inspect failure output |
| `invariant_aware` | + `verify_invariant.sh` |
| `trace_aware` | + declared trace scripts |
| `contract_full` | + all executable checks (no metadata/golden patch) |
| `recovery_aware` | + validate → apply → verify → rollback/retry loop |

Each run emits `contractCoverage` and `contractReliabilityIndex` (CRI) in JSONL.

External agents can replace the built-in driver:

```bash
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/your_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge --agent-profile contract_full
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

### 6.5 Phase 3 — Runtime Contract Orchestrator

Phase 2 proved **static** contract visibility improves reliability. Phase 3 asks: *how should the runtime decide what truth to reveal during failure recovery?*

The orchestrator (`contracts.py`, `contract_orchestrator.py`) implements an **adaptive contract broker**:

```text
agent starts minimally bounded (readme + verify_grep)
  → mutation attempt
  → verify failure classified (orchestrator-side)
  → runtime grants next contract layer
  → workspace restored from fixture
  → retry
```

**Failure classification** (no trap metadata exposed to agent):

| Failure class | Contract granted |
|---------------|------------------|
| `hidden_invariant_missing` | `hidden_invariant` |
| `runtime_behavior_mismatch` | `verify_exec` |
| `execution_trace_required` | `execution_trace` |
| `stale_read_detected` | `authoritative_read` |
| `concurrent_mutation` | `stale_read_protocol` |

**Minimum Contract Set (MCS)** — per task, the smallest contract set observed at first successful pass:

```json
{
  "minimumContractSet": ["readme", "verify_grep", "hidden_invariant"],
  "contractEscalationPath": [
    {"failureClass": "hidden_invariant_missing", "grantedContract": "hidden_invariant"}
  ],
  "escalationSucceeded": true
}
```

```bash
python3 benchmarks/agent_success/run_benchmark.py --executor agent --agent-profile orchestrated --mode bridge
make benchmark-contract-orchestrator   # nightmare tier → RESULTS_ORCHESTRATOR.md
```

**Claim (Phase 3):** Reliable bounded autonomy emerges through **adaptive runtime contract escalation**, not static maximal visibility.

Results: [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md)

### 6.6 Phase 3.1 — Execution-Side Recovery Protocol

Phase 3 escalated **visibility contracts** only. Phase 3.1 adds a second axis — **execution protocols** — because revealing more truth is not enough when workspace state changes mid-mutation.

```text
failure → classify → grantContract + grantProtocol → retry with new mutation strategy
```

| Protocol | Behavior |
|----------|----------|
| `single_shot_patch` | Read, validate, apply (default) |
| `stale_safe_patch` | Re-read and reconcile on `stale_content` |
| `lock_read_validate_apply` | Authoritative read; strip concurrent writer lines; reconcile |
| `transactional_batch_patch` | Snapshot rollback between batch attempts |
| `rollback_cleanup` | Restore fixture and remove sidecar residue |

**Dual-axis escalation example (task 057):**

```json
{
  "failureClass": "concurrent_mutation_detected",
  "grantedContract": "stale_read_protocol",
  "grantedProtocol": "lock_read_validate_apply",
  "executionProtocolPath": ["single_shot_patch", "lock_read_validate_apply"],
  "protocolEscalationSucceeded": true
}
```

**Claim (Phase 3.1):** Runtime contract visibility tells the agent what truth exists; **execution protocols** determine whether mutation remains safe under changing state.

Implementation: `execution_protocols.py`, extended `ESCALATION_GRAPH` in `contracts.py`.

### 6.7 Phase 3.2 — Semantic Repair Protocol

The third control axis: **behavior-preserving repair** when visibility and execution protocol are insufficient (task 059).

```text
snapshot → capture API shape → run behavior check → derive implementation target
  → patch implementation only → re-check behavior + API shape → verify
  → rollback if shape changed or behavior still fails
```

**Protocol:** `semantic_repair_loop` (requires `verify_exec`, `behavior_check`, `api_shape_contract`)

**Escalation:**

| Failure class | Contract | Protocol |
|---------------|----------|----------|
| `behavior_check_failed` | `behavior_check` | `semantic_repair_loop` |
| `api_shape_mismatch` | `api_shape_contract` | `semantic_repair_loop` |
| `semantic_preservation_failed` | `api_shape_contract` | `semantic_repair_loop` |

**Telemetry:** `semanticRepairAttempted`, `behaviorFailureCaptured`, `apiShapeBefore`/`apiShapeAfter`, `apiShapeChanged`, `semanticRepairSucceeded`, `semanticRollbackTriggered`

**Claim (Phase 3.2):** Bounded mutation reliability requires three separable controls: **contract visibility**, **safe execution protocol**, and **semantic repair discipline**.

### 6.8 Phase 4 — Reliability Case & Release Gates

Phase 4 hardens the architecture against regression:

- **Mutation traces** — `results/traces/<run_id>/<task_id>.mutation_trace.json` per orchestrated task
- **Release gates** — `make benchmark-contract-release-check` enforces reference 10/10, orchestrated 10/10, integrity counters, and escalation proofs (052/057/059)
- **Reliability case** — [AGENT_RUNTIME_RELIABILITY.md](../../AGENT_RUNTIME_RELIABILITY.md)

**Claim (Phase 4):** DietCode emits replayable mutation traces and enforces release gates for bounded agent code mutation across visibility, execution, and semantic-repair controls.

**Stability tiers:** tasks 001–030 and 051–060 are **stable**; CRI and MCS reference are **experimental**.

### 6.9 Phase 4.1 — Production Hardening Audit

Phase 4.1 audits the reliability stack for hostile review:

- **Trace provenance** — `traceSchemaVersion`, `traceHash`, workspace hashes, `gitCommit`
- **Schema freeze** — `make test-agent-benchmark-schema`
- **Replay verifier** — `replay_trace.py`
- **Negative gates** — `make test-release-gate-negative`
- **Audit report** — [AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md](AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md)

**Claim (Phase 4.1):** DietCode's agent reliability benchmark produces versioned, replayable mutation evidence with release gates, negative gate tests, and schema-stable telemetry for bounded code mutation research.

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
| `minimumContractSet` | MCS at first successful pass (`orchestrated` profile) |
| `contractEscalationPath` | Failure class → granted contract per step |
| `escalationSucceeded` | Task passed after at least one contract escalation |
| `orchestrationSteps` | Broker iterations consumed |
| `executionProtocolPath` | Protocols active across orchestration (`orchestrated` profile) |
| `protocolEscalationSucceeded` | Task passed after execution-protocol escalation |
| `semanticRepairAttempted` | `semantic_repair_loop` protocol ran |
| `behaviorFailureCaptured` | Pre-repair behavior check failure recorded |
| `apiShapeChanged` | Public `def` signatures differ after mutation |
| `semanticRepairSucceeded` | Behavior + API shape + verify passed after repair |
| `semanticRollbackTriggered` | Repair rolled back due to shape/behavior violation |
| `mutationTraceFile` | Path to replayable per-task mutation trace (Phase 4) |
| `mcsReferenceMatch` | Observed MCS vs diagnostic reference |
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

**Orchestrator findings (Phase 3–3.2):** [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md) documents the three-axis control model (visibility · execution protocol · semantic repair), static-vs-adaptive pass rates, failure attribution matrix, MCS interpretation, and representative case studies for tasks 052, 057, and 059.

### 8.3 Executor coverage

Reports state whether each executor is present or absent:

```text
Executor coverage: reference **present** | agent **absent**
```

Reference-only runs include:

> Agent executor results are not present in this summary.

### 8.4 Money table

| executor | mode | normal pass | adversarial pass | nightmare pass | wrong file | rollback | recovery |
|----------|------|------------:|-----------------:|---------------:|-----------:|---------:|---------:|

This is the primary comparison surface for stakeholders.

### 8.5 Trap matrices

**Adversarial (021–030):**

| trapType | passRate | wrongFileEdited | rollbackSucceeded | recoverySucceeded | avgRetries |
|----------|----------|----------------:|------------------:|------------------:|-----------:|

**Nightmare (051–060) — Runtime Contract Matrix:**

| trapType | passRate | destructiveBlocked | sidecarClean | concurrentDetected | searchMismatch | apiPreserved | inv₂ |
|----------|----------|-------------------:|-------------:|-------------------:|---------------:|-------------:|-----:|

### 8.6 Runtime Contract Evaluation Ladder

From `RESULTS_CONTRACT_LADDER.md`:

| profile | allowed visibility | pass | contractSignals | avgCRI |
|---------|-------------------|-----:|----------------:|-------:|

**Failure Attribution Matrix** — task × profile → PASS/FAIL with `requiredContract` (e.g. task 052 requires `hidden_invariant`; `grep_only` fails, `invariant_aware` passes).

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

# Smoke tests
make test-agent-success-report
make test-contract-ladder

# Runtime Contract Evaluation Ladder (nightmare × all profiles)
make benchmark-contract-ladder
```

### 9.1 Selective runs

```bash
# Reference baseline, both modes (base corpus)
python3 benchmarks/agent_success/run_benchmark.py --executor reference --mode both --assume-server-ready

# Agent with contract profile
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge \
  --agent-profile invariant_aware --assume-server-ready

# Nightmare tier only
python3 benchmarks/agent_success/run_benchmark.py --executor reference \
  --task task_051 … --task task_060 --assume-server-ready

# Single task
python3 benchmarks/agent_success/run_benchmark.py --task task_052 --executor agent \
  --agent-profile invariant_aware --mode bridge --assume-server-ready
```

---

## 10. Interpreting results

### 10.1 What a healthy reference run looks like

As of benchmark v1.1 (June 2026, DietCode 1.6.5), the reference executor passes **100%** on the full corpus:

| Tier | Tasks | Reference pass | Wrong-file edits |
|------|-------|---------------:|-----------------:|
| Normal + adversarial | 001–030 | **60/60** (×2 modes) | 0 |
| Nightmare | 051–060 | **20/20** (×2 modes) | 0 |
| **Total** | **40** | **80/80** | 0 |

Recovery/rollback/contract-metric events are non-zero on stress-path tasks (expected). This is the **solvability certificate** for the tool surface.

### 10.2 What agent runs reveal

| Tier | Agent (`grep_only`, bridge) | Notes |
|------|----------------------------:|-------|
| Base (001–030) | **30/30** | Verify-driven; no recovery paths exercised |
| Nightmare (051–060) | **6/10** | First meaningful separation from reference |
| Nightmare (`contract_full`) | **9/10** | CRI avg 95; task 057 still fails all profiles |

Lower pass rate with **zero wrong-file edits** and a **failure attribution matrix** is informative — it shows which contract visibility unlocks each trap (e.g. 052 needs `invariant_aware`, 055/059 need `verify_exec`, 057 needs organic stale recovery).

The desired property:

> Failures are attributable to missing contract visibility — not silent corruption.

### 10.3 What this benchmark does not claim

- It does not measure LLM reasoning quality directly (plug in `AGENT_BENCHMARK_AGENT_SCRIPT` for that).
- It does not replace production workload profiling.
- It does not test UI ergonomics or latency at scale.
- It is not a leaderboard — it is an instrument for runtime and agent integration hardening.

---

## 11. Relationship to DietCode runtime

The benchmark exercises the DietCode control plane documented in:

- [Agent Bridge](../../docs/agent-bridge.md)
- [Testing & release gates](../../docs/testing.md)
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

1. **The runtime is capable** — reference **80/80** across 40 tasks and 2 modes.
2. **The agent is constrained** — no metadata cheats; contract visibility is profile-controlled.
3. **The traps are explicit** — adversarial + nightmare tiers with typed failure modes.
4. **Failures are attributable** — contract ladder + failure attribution matrix.
5. **Safety is scored** — CRI weights wrong-file, invariant, rollback, and containment over raw pass rate.
6. **Recovery is measurable** — per-trap matrix, contract signals, mutation telemetry.

DietCode does not only measure whether an agent can patch code. It measures **which runtime contracts must be visible** for bounded mutation to remain reliable — searchable, patchable, verifiable, recoverable, and reportable.

---

## Appendix A: File reference

| File | Purpose |
|------|---------|
| `generate_fixtures.py` | Task corpus generator |
| `nightmare_tasks_defs.py` | Nightmare-tier task definitions |
| `run_benchmark.py` | Benchmark runner (`--agent-profile`) |
| `agent_driver.py` | Built-in agent executor (6 profiles) |
| `contract_ladder.py` | Profile caps, CRI, required-contract map |
| `run_contract_ladder.py` | Nightmare × profile orchestrator |
| `render_contract_ladder.py` | Ladder report generator |
| `report_results.py` | Report aggregator |
| `RESULTS.md` | Base corpus live results |
| `NIGHTMARE_RESULTS.md` | Nightmare tier live results |
| `RESULTS_CONTRACT_LADDER.md` | Profile sweep live results |
| `tasks/task_NNN/` | Fixture repos |
| `results/*.jsonl` | Raw run output |
| `results/summary.md` | Claim-ready report |

## Appendix B: Makefile targets

| Target | Action |
|--------|--------|
| `benchmark-agent-success` | Rebuild, restart, full base-corpus run |
| `benchmark-agent-success-fast` | Fast base-corpus run + report |
| `benchmark-agent-success-report` | Report from latest JSONL |
| `benchmark-contract-ladder` | Nightmare × all profiles → ladder report |
| `test-agent-success-report` | Report format smoke test |
| `test-contract-ladder` | Ladder smoke test |

## Appendix C: Version history

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | June 2026 | 30 tasks: dual modes, dual executors, adversarial traps, claim-ready reporting |
| 1.1 | June 2026 | +10 nightmare tasks (051–060), contract metrics, Runtime Contract Evaluation Ladder (6 profiles), CRI, failure attribution, three result papers |
| 1.2 | June 2026 | Phase 3: Runtime Contract Orchestrator, adaptive escalation, MCS metric, `orchestrated` agent profile |
| 1.3 | June 2026 | Phase 3.1: execution protocols (`lock_read_validate_apply`, etc.), dual-axis escalation, `executionProtocolPath` metric |
| 1.4 | June 2026 | Phase 3.2: `semantic_repair_loop`, `api_shape_contract`, semantic repair telemetry, CRI semantic penalties |
| 1.5 | June 2026 | Phase 4: mutation traces, `release_check.py`, reliability case doc, release gates |
