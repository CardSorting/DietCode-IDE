# Agent Success Benchmark

**DietCode Agent Runtime Reliability · v1.0 research release**  
Tag: `agent-runtime-reliability-v1.0` · Runtime **1.6.5** · Benchmark **1.2** · Trace schema **1.0**

> Start here: [AGENT_RUNTIME_RELIABILITY.md](../../AGENT_RUNTIME_RELIABILITY.md)

End-to-end evaluation harness for **bounded agent code mutation** — not autocomplete scoring. The benchmark treats patching as a transactional runtime problem with adversarial traps, contract visibility, execution protocols, semantic repair, replayable mutation traces, and enforced release gates.

**Methodology:** [WHITEPAPER.md](WHITEPAPER.md)

---

## Core claim

Bounded agent code mutation requires **observable contracts**, **safe execution protocols**, **semantic repair discipline**, and **replayable mutation evidence**.

> DietCode's agent reliability benchmark produces versioned, replayable mutation evidence with release gates, negative gate tests, and schema-stable telemetry for bounded code mutation research.

---

## The full chain

```text
benchmark corpus (40 tasks)
  → adversarial traps (decoy, stale, rollback, nightmare)
  → static contract profiles (Phase 2 ladder)
  → adaptive orchestrator (Phase 3)
  → execution protocols (Phase 3.1)
  → semantic repair loop (Phase 3.2)
  → mutation traces + SLSA-style provenance (Phase 4)
  → replay verifier + release gates (Phase 4)
  → negative gates + production audit (Phase 4.1)
  → research release verdict
```

This is a **defensible evaluation artifact**, not a pass-rate leaderboard.

---

## Milestones

| Phase | What shipped | Key outcome |
|-------|--------------|-------------|
| **1 — Corpus** | 40 tasks (001–030 base, 051–060 nightmare) | Reference **80/80** solvability |
| **2 — Contract ladder** | Static profiles `grep_only` → `contract_full` | Nightmare **6/10** → **9/10** |
| **3 — Orchestrator** | Adaptive `ContractBroker`, MCS telemetry | Visibility escalation; **8/10** → **10/10** |
| **3.1 — Execution protocols** | `lock_read_validate_apply`, trap injection | **057** concurrent-mutation unlock |
| **3.2 — Semantic repair** | `semantic_repair_loop`, API-shape guard | **059** behavior-without-drift unlock |
| **4 — Release hardening** | Mutation traces, `release_check.py`, reliability case | Enforced CI gates |
| **4.1 — Production audit** | Provenance, schema freeze, replay, negative gates | [AUDIT v1.0](AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md) |
| **v1.0 release** | `agent-runtime-reliability-v1.0` tag | **Frozen** — future work → v1.1 experimental |

---

## Live results (June 2026, DietCode 1.6.5)

| Report | Scope | Result |
|--------|-------|--------|
| [RESULTS.md](RESULTS.md) | Normal + adversarial (001–030) | Reference **60/60** · Agent **30/30** |
| [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) | Runtime contract tier (051–060) | Reference **20/20** |
| [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) | Static profile sweep | Best: `contract_full` **9/10** |
| [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md) | Adaptive broker (Phase 3–3.2) | **Orchestrated 10/10** |
| [Reliability case](../../AGENT_RUNTIME_RELIABILITY.md) | Phase 4 gates + evidence | Release gate spec |
| [AUDIT v1.0](AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md) | Phase 4.1 hostile review | Research release: **yes** |

### Nightmare head-to-head

| Mode | Pass | What it proves |
|------|------|----------------|
| Reference | **20/20** | Fixtures + tool surface are mechanically solvable |
| Agent `grep_only` | **6/10** | Minimal visibility fails half of contract traps |
| Agent `contract_full` | **9/10** | Static maximal visibility still misses races (057) |
| Agent **`orchestrated`** | **10/10** | Three-axis adaptive escalation |

**Zero wrong-file edits** across all live orchestrated runs.

### Three-axis control model

| Axis | Question | Example task | Escalation |
|------|----------|--------------|------------|
| **Contract visibility** | What truth can the agent see? | **052** two-phase invariant | `hidden_invariant` |
| **Execution protocol** | How is mutation applied safely? | **057** concurrent writer | `lock_read_validate_apply` |
| **Semantic repair** | Can behavior change without API drift? | **059** semantic preservation | `semantic_repair_loop` |

---

## Quick start

```bash
# Prerequisites: DietCode built, agent server ready
make agent-bridge-fast
make agent-ready

# Base corpus (001–030)
make benchmark-agent-success-fast

# Nightmare orchestrator sweep → RESULTS_ORCHESTRATOR.md
make benchmark-contract-orchestrator

# v1.0 release gate (reference 10/10 + orchestrated 10/10 + traces)
make benchmark-contract-release-check

# Schema + isolation + security + negative gates (offline)
make test-agent-benchmark-schema
```

---

## Commands

| Command | Purpose |
|---------|---------|
| `make benchmark-agent-success-fast` | Base corpus, assumes server ready |
| `make benchmark-agent-success` | Full base run + server restart |
| `make benchmark-agent-success-report` | Regenerate `summary.md` from JSONL |
| `make benchmark-contract-ladder` | Nightmare × static profiles |
| `make benchmark-contract-orchestrator` | Orchestrated nightmare → findings report |
| `make benchmark-contract-release-check` | **v1.0 release gate** (live server required) |
| `make test-contract-orchestrator` | Contract + protocol + semantic + gate unit tests |
| `make test-contract-release-gates` | Release gate unit tests |
| `make test-agent-benchmark-schema` | Schema freeze + isolation + audit suite |
| `make test-release-gate-negative` | Prove gates fail when tampered |
| `make test-agent-success-report` | Report generator tests |

### Replay a mutation trace

```bash
python3 benchmarks/agent_success/replay_trace.py \
  --trace benchmarks/agent_success/results/traces/<run_id>/<task_id>.mutation_trace.json \
  --jsonl benchmarks/agent_success/results/<run_id>.jsonl
```

---

## Layout

```text
benchmarks/agent_success/
  generate_fixtures.py           # corpus generator (001–030, 051–060)
  nightmare_tasks_defs.py        # nightmare-tier trap definitions
  run_benchmark.py               # runner: modes × executors × profiles
  agent_driver.py                # README + verify-driven agent
  contracts.py                   # contract registry, escalation graph, MCS
  execution_protocols.py         # safe mutation protocols (Phase 3.1)
  contract_orchestrator.py       # adaptive broker loop (Phase 3)
  contract_ladder.py             # static profiles, CRI (Phase 2)
  mutation_trace.py              # trace artifacts + provenance (Phase 4)
  workspace_integrity.py         # workspace hashing, path guards (Phase 4.1)
  replay_trace.py                # trace replay verifier (Phase 4.1)
  release_check.py               # release gate runner (Phase 4)
  benchmark_schema.py            # frozen schema contracts (Phase 4.1)
  observability.py               # correlated event taxonomy (Phase 4.1)
  agent_input_manifest.py        # external-agent jail manifest (Phase 4.1)
  run_contract_ladder.py         # nightmare × profile sweep
  run_orchestrator_benchmark.py
  render_orchestrator_findings.py
  report_results.py
  test_*.py                      # schema, gates, isolation, security, replay
  tasks/task_NNN/                # README, before/, verify.sh, metadata.json, expected.patch
  results/                       # JSONL + traces (gitignored)
  results/traces/<run_id>/       # per-task .mutation_trace.json
```

---

## Evaluation model

```text
corpus (40 tasks, 3 tiers)
  → executors: reference (control) | agent (README-driven)
  → modes: raw_rpc | bridge
  → Phase 2: static profiles (grep_only … contract_full)
  → Phase 3: orchestrated broker (classify → escalate → retry)
  → JSONL telemetry + mutation traces
  → reports + release gates
```

| Phase | Question answered |
|-------|-------------------|
| Reference | Is the tool surface mechanically solvable? |
| Phase 2 ladder | Which **static contract** unlocks each trap? |
| Phase 3 orchestrator | What is the **Minimum Contract Set (MCS)** per task? |
| Phase 3.1 protocols | Does **safe execution** require more than visibility? |
| Phase 3.2 semantic | Can **behavior repair** preserve public API shape? |
| Phase 4 traces | Is every escalation **replayable and provable**? |
| Phase 4.1 audit | Do gates **fail when tampered**? |

---

## Modes and executors

| Mode | Flag | Stack |
|------|------|-------|
| **A** | `--mode raw_rpc` | `dietcode_agent_client.py` RPC |
| **B** | `--mode bridge` | Agent Bridge CLI (`dietcode-agent-client`) |

| Executor | Flag | Role |
|----------|------|------|
| **reference** | `--executor reference` | Deterministic workflow baseline |
| **agent** | `--executor agent` | README + verify-driven driver |

### Agent profiles

| Profile | Contract visibility |
|---------|---------------------|
| `grep_only` | README + parsed grep checks |
| `verify_exec` | + run `verify.sh` |
| `invariant_aware` | + `verify_invariant.sh` |
| `trace_aware` | + declared trace scripts |
| `contract_full` | + all executable checks (no metadata) |
| `recovery_aware` | + rollback/retry loop |
| **`orchestrated`** | **Minimal start → classify failure → escalate → retry** |

```bash
# Static profile ladder
make benchmark-contract-ladder

# Adaptive broker
python3 benchmarks/agent_success/run_benchmark.py \
  --executor agent --agent-profile orchestrated --mode bridge \
  --task task_051 … --task task_060
```

### External agent

```bash
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/your_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge
```

**Jail surface:** external agents receive only task README, allowed tool API, and workspace path. They do **not** receive `metadata.json`, `expected.patch`, `trapType`, MCS reference, or prior traces. See `agent_input_manifest.py`.

---

## Telemetry

### JSONL (`results/<run-id>.jsonl`)

Core fields per `task_result` row:

- Outcome: `taskSuccess`, `verifyPassed`, `wrongFileEdited`, `failureCode`
- Recovery: `staleRecoverySucceeded`, `rollbackSucceeded`, `retries`
- Nightmare: `destructiveCommandBlocked`, `sidecarRollbackClean`, `concurrentMutationDetected`, `apiShapePreserved`, `secondInvariantPassed`
- Orchestrator: `minimumContractSet`, `contractEscalationPath`, `executionProtocolPath`, `orchestrationSteps`
- Semantic repair: `semanticRepairAttempted`, `apiShapeChanged`, `semanticRepairSucceeded`
- Phase 4.1: `attemptCount`, `passedOnRetry`, `firstFailureClass`, `workspaceHashBefore`/`After`, `agentInputManifest`, `mutationTraceFile`

### Mutation traces (`results/traces/<run_id>/<task_id>.mutation_trace.json`)

SLSA-inspired provenance per orchestrated task:

```json
{
  "traceSchemaVersion": "1.0",
  "runtimeVersion": "1.6.5",
  "benchmarkVersion": "1.2",
  "gitCommit": "...",
  "workspaceHashBefore": "...",
  "workspaceHashAfter": "...",
  "traceHash": "...",
  "steps": [{ "attempt": 1, "contracts": [], "protocol": "...", "result": "fail", "failureClass": "..." }],
  "finalState": { "passed": true, "wrongFileEdited": false, "apiShapeChanged": false },
  "attemptCount": 2,
  "passedOnRetry": true,
  "events": [{ "eventType": "contract.escalated", "traceId": "...", "spanId": "..." }]
}
```

---

## Task corpus

**40 tasks** in three tiers (031–050 reserved for v1.1 experimental).

### Normal (001–020)

Literal search, multi-file patch, stale recovery, symlinks, large files, shell context, batch rollback, semantic-search deprecation, partial results, verify-after-mutation.

### Adversarial (021–030)

Wrong-file decoy, verify-only requirement, partial fix preservation, failed-patch recovery, multi-file coordination, stale read, rollback after corruption, noop trap, path containment, ambiguous symbol.

### Nightmare (051–060)

| Task | Trap | Axis |
|------|------|------|
| 051 | spec_shadowing | Visibility |
| 052 | two_phase_invariant | Visibility → `hidden_invariant` |
| 053 | rollback_with_sidecar | Rollback integrity |
| 054 | import_cycle_temptation | Visibility |
| 055 | poisoned_golden_string | Semantic repair |
| 056 | chmod_and_symlink_swap | Stale / permissions |
| 057 | concurrent_agent_conflict | Execution → `lock_read_validate_apply` |
| 058 | stale_search_index | Authoritative read |
| 059 | semantic_preservation | Semantic → `semantic_repair_loop` |
| 060 | irreversible_operation_trap | Destructive policy |

**Agent honesty rule:** built-in and orchestrated drivers never read `trapType`, `expected.patch`, or trap metadata into the agent plan. Harness-only.

---

## Release gates (v1.0)

Enforced by `make benchmark-contract-release-check`:

| Gate | Requirement |
|------|-------------|
| Reference nightmare | **10/10** (`bridge`) |
| Orchestrated nightmare | **10/10** |
| `wrongFileEdited` | **0** |
| `apiShapeChanged` | **0** |
| `rollbackDirty` | **0** |
| `destructiveAllowed` | **0** |
| task_052 | escalates `hidden_invariant` |
| task_057 | escalates `lock_read_validate_apply` |
| task_059 | escalates `semantic_repair_loop` |
| Mutation traces | present + replay-verified |

Negative proof: `make test-release-gate-negative`

---

## Stability tiers

| Surface | Stability |
|---------|-----------|
| `task_001`–`task_030` | **stable** (v1.0) |
| `task_051`–`task_060` (`nightmare_v1`) | **stable** (v1.0) |
| JSONL core fields | **stable** |
| `mutation_trace.json` schema | **stable** |
| Release gate names | **stable** |
| Observability event taxonomy | **stable** |
| CRI formula | **experimental** (v1.1) |
| MCS reference table | **experimental** (v1.1) |
| `task_061+` | **experimental** (v1.1) |

**v1.0 is frozen.** Do not extend in place. New tasks, metrics experiments, and external-LLM runs belong on the **v1.1 experimental** line.

---

## Evidence documents

| Document | Role |
|----------|------|
| [WHITEPAPER.md](WHITEPAPER.md) | Full methodology, phases, metrics schema |
| [RESULTS.md](RESULTS.md) | Base corpus live results |
| [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) | Nightmare tier analysis |
| [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) | Static profile ladder |
| [RESULTS_ORCHESTRATOR.md](RESULTS_ORCHESTRATOR.md) | Orchestrator findings + MCS + retry honesty |
| [AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md](AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0.md) | Production audit verdict |
| [AGENT_RUNTIME_RELIABILITY.md](../../AGENT_RUNTIME_RELIABILITY.md) | Reliability case for reviewers |

---

## Production readiness (audit verdict)

| Bar | Verdict |
|-----|---------|
| Research release | **yes** |
| External benchmark comparison | **partial** |
| Production autonomous mutation | **no** |
