# Runtime Contract Orchestrator — Findings

**Generated:** 2026-06-08T12:07:04Z · DietCode **1.6.5** · Benchmark **v1.4**

> Reliable bounded autonomy emerges through adaptive runtime contract escalation, not static maximal visibility.

> Runtime contract visibility tells the agent what truth exists; execution protocols determine whether mutation remains safe under changing state.

> Bounded mutation reliability requires three separable controls: contract visibility, safe execution protocol, and semantic repair discipline.

Methodology: [WHITEPAPER.md](WHITEPAPER.md) §6.5–6.7 · Prior work: [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) · Nightmare corpus: [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md)

---

## 1. What we measured

The nightmare tier (tasks 051–060) tests **bounded mutation under adversarial runtime state** — not model intelligence. Each task encodes a trap where the agent must discover the right *kind* of runtime support before a patch can succeed safely.

We compared two evaluation modes:

| Mode | How contracts are granted | Nightmare pass rate (live) |
|------|---------------------------|----------------------------|
| **Static profiles** (Phase 2) | Agent starts with a fixed visibility bundle (`grep_only` → `contract_full`) | **6/10** (`grep_only`) → **9/10** (`contract_full`) |
| **Orchestrated broker** (Phase 3–3.2) | Agent starts minimal; runtime classifies failure and escalates contracts *and* protocols | **10/10** |

The orchestrator begins every task with only:

- **Visibility:** `readme` + `verify_grep`
- **Protocol:** `single_shot_patch`

No metadata, no golden patch, no trap labels. Failures trigger classified escalation; the broker restores a clean fixture snapshot and retries.

**Headline:** The adaptive broker matches or exceeds static maximal visibility while exposing *what was minimally necessary* per task (MCS + protocol path telemetry).

---

## 2. The three-axis control model

Industry systems separate **what you can observe**, **how you act safely**, and **how you recover when behavior must change**. This benchmark makes that separation explicit:

| Axis | Question the runtime answers | Failure when missing | Representative task |
|------|------------------------------|----------------------|---------------------|
| **Contract visibility** | What truth is the agent allowed to see? | Agent plans from incomplete or misleading surface | **052** — hidden invariant |
| **Execution protocol** | How is mutation applied under changing state? | Stale reads, concurrent writers, partial applies | **057** — concurrent conflict |
| **Semantic repair** | Can behavior be fixed while preserving public contracts? | Correct grep, wrong semantics; API shape drift | **059** — semantic preservation |

These axes are **orthogonal**. Task 057 demonstrated that escalating visibility alone (`stale_read_protocol`, `authoritative_read`) is insufficient without a concurrent-safe mutation protocol. Task 059 demonstrated that safe patching alone is insufficient without a behavior-preserving repair loop that guards API shape.

Analogies (informative, not identity):

- **Playwright-style automation:** isolated workspace snapshots, mutation traces, retries, and contract assertions — applied to agent patching instead of browser clicks.
- **OpenTelemetry-style observability:** every escalation emits structured telemetry (contracts granted, protocols switched, stale recovery, semantic rollback).
- **SLSA-style integrity:** who changed what, under which protocol, with what verification and rollback evidence — measured, not assumed.

---

## 3. Research progression

```text
Phase 2   Static profiles        →  Which contract bundle is enough?     →  contract_full 9/10
Phase 3   Adaptive visibility    →  Can the runtime reveal truth on failure? →  8/10 (+ MCS)
Phase 3.1 Execution protocols    →  Can mutation stay safe under races?    →  9/10 (057 unlocked)
Phase 3.2 Semantic repair        →  Can behavior change without API drift?   →  10/10 (059 unlocked)
```

**Phase 2 insight:** Contract visibility is necessary but static maximal bundles are wasteful and still miss execution-side races (057 failed all static profiles).

**Phase 3 insight:** Failure classification + incremental contract grants let most tasks pass with *less* upfront visibility than `contract_full`.

**Phase 3.1 insight:** The broker must escalate **mutation strategy**, not only **truth surface**. `lock_read_validate_apply` strips concurrent writer residue and reconciles before re-apply.

**Phase 3.2 insight:** Some failures are neither visibility nor staleness — they require **implementation repair under API-shape constraints**. `semantic_repair_loop` captures behavior failure, patches implementation only, and rolls back if public `def` signatures change.

---

## 4. Failure attribution matrix

| Task | Trap | Dominant axis | Failure class (observed) | Escalation granted | Protocol path |
|------|------|---------------|--------------------------|-------------------|---------------|
| 051 | spec_shadowing | Visibility | *(none — passes at minimal)* | — | `single_shot_patch` |
| 052 | two_phase_invariant | Visibility | `hidden_invariant_missing` | `hidden_invariant` | `single_shot_patch` |
| 053 | rollback_with_sidecar | Visibility | *(none)* | — | `single_shot_patch` |
| 054 | import_cycle_temptation | Visibility | *(none)* | — | `single_shot_patch` |
| 055 | poisoned_golden_string | Semantic | `behavior_check_failed` | `behavior_check` + `api_shape_contract` | → `semantic_repair_loop` |
| 056 | chmod_and_symlink_swap | Visibility | *(none)* | — | `single_shot_patch` |
| 057 | concurrent_agent_conflict | **Execution** | `concurrent_mutation_detected` | `stale_read_protocol` | → `lock_read_validate_apply` |
| 058 | stale_search_index | Visibility | *(none)* | — | `single_shot_patch` |
| 059 | semantic_preservation | **Semantic** | `behavior_check_failed` | `behavior_check` + `api_shape_contract` | → `semantic_repair_loop` |
| 060 | irreversible_operation_trap | Visibility | *(none)* | — | `single_shot_patch` |

**Zero wrong-file edits** across all orchestrated runs. Pass rate alone is insufficient; the attribution matrix is the diagnostic product.

---

## 5. Representative case studies

### 5.1 Task 052 — visibility unlocks hidden invariants

Primary `verify.sh` passes after a naive patch; `verify_invariant.sh` catches a second regression. At `grep_only`, the agent cannot see the invariant script. The broker classifies `hidden_invariant_missing` and grants `hidden_invariant` — one escalation, no protocol change.

**MCS observed:** `readme` + `verify_grep` + `hidden_invariant` (matches reference).

### 5.2 Task 057 — execution protocol, not more context

A simulated second writer appends `VERSION = 3` between validate and apply. `single_shot_patch` fails with stale content. Visibility escalation alone cannot help: the agent already knows the target file. The broker grants `lock_read_validate_apply`, which strips the concurrent line, reconciles to `VERSION = 2`, and re-applies against live content.

**MCS observed:** `readme` + `verify_grep` + `stale_read_protocol` (reference also lists `authoritative_read` — observed MCS is a subset that still suffices).

### 5.3 Task 059 — semantic repair, not smarter grep

`verify.sh` includes grep clauses on `def format_result` and `def compute`. These are **API-shape constraints**, not patch targets. At minimal visibility, treating them as positive grep goals corrupts the module. The broker classifies `behavior_check_failed`, grants `semantic_repair_loop`, and:

1. Captures API shape (`def` signatures) before mutation
2. Runs `test_api.py` and records the assertion failure
3. Derives an implementation-only target (`return format_result(1)`)
4. Patches, re-runs behavior check, compares API shape
5. Rolls back if shape changed or behavior still fails

**MCS observed:** `readme` + `verify_grep` + `verify_exec` + `behavior_check` + `api_shape_contract` (matches reference).

---

## 6. Minimum Contract Set (MCS) — live results

| task | passed | MCS (observed) | protocol path | escalations | ref match |
|------|--------|----------------|---------------|------------:|-----------|
| 051 | PASS | readme, verify_grep | single_shot_patch | 0 | — |
| 052 | PASS | hidden_invariant, readme, verify_grep | single_shot_patch | 1 | ✓ |
| 053 | PASS | readme, verify_grep | single_shot_patch | 0 | ✓ |
| 054 | PASS | readme, verify_grep | single_shot_patch | 0 | — |
| 055 | PASS | api_shape_contract, behavior_check, readme, verify_exec, verify_grep | single_shot_patch → semantic_repair_loop | 1 | — |
| 056 | PASS | readme, verify_grep | single_shot_patch | 0 | — |
| 057 | PASS | readme, stale_read_protocol, verify_grep | single_shot_patch → lock_read_validate_apply | 1 | — |
| 058 | PASS | readme, verify_grep | single_shot_patch | 0 | — |
| 059 | PASS | api_shape_contract, behavior_check, readme, verify_exec, verify_grep | single_shot_patch → semantic_repair_loop | 1 | ✓ |
| 060 | PASS | readme, verify_grep | single_shot_patch | 0 | — |

**Orchestrated pass rate: 10/10**

### How to read MCS `ref match`

Reference MCS is a **diagnostic baseline** derived from trap analysis, not ground truth. `match: false` is informative:

- **Observed ⊂ reference** (e.g. 057): task passed with *fewer* contracts than conservatively estimated — the broker found a slimmer sufficient set.
- **Observed ⊃ reference** (e.g. 055): semantic repair auto-grants bundled contracts (`verify_exec`, `api_shape_contract`) in one escalation step.
- **Pass at minimal** (051, 054, 056, 058, 060): trap is solvable without escalation — the task does not require exposing the named reference contract layer upfront.

The product is not “match the table.” The product is **measured minimal sufficiency** per task.

---

## 7. Retry / Escalation Honesty

Retries are explicit — not hidden behind a single pass bit.

| task | firstAttemptPassed | attemptCount | passedOnRetry | firstFailureClass | finalProtocol |
|------|-------------------:|-------------:|:-------------:|-------------------|---------------|
| 051 | ✓ | 1 | — | — | `single_shot_patch` |
| 052 | — | 2 | ✓ | `hidden_invariant_missing` | `single_shot_patch` |
| 053 | ✓ | 1 | — | — | `single_shot_patch` |
| 054 | ✓ | 1 | — | — | `single_shot_patch` |
| 055 | — | 2 | ✓ | `behavior_check_failed` | `semantic_repair_loop` |
| 056 | ✓ | 1 | — | — | `single_shot_patch` |
| 057 | — | 2 | ✓ | `concurrent_mutation_detected` | `lock_read_validate_apply` |
| 058 | ✓ | 1 | — | — | `single_shot_patch` |
| 059 | — | 2 | ✓ | `behavior_check_failed` | `semantic_repair_loop` |
| 060 | ✓ | 1 | — | — | `single_shot_patch` |

---

## 8. Semantic repair matrix

| task | behaviorFailureCaptured | apiShapeChanged | semanticRepairSucceeded | rollbackTriggered | finalVerifyPassed |
|------|------------------------:|----------------:|------------------------:|------------------:|------------------:|
| 055 | ✓ | — | ✓ | — | ✓ |
| 059 | ✓ | — | ✓ | — | ✓ |

Tasks 055 and 059 route through `semantic_repair_loop` after `behavior_check_failed`. Both capture pre-repair assertion output, preserve API shape (`apiShapeChanged: false`), and pass final verify without rollback.

---

## 9. Telemetry emitted per run

Each orchestrated row in JSONL includes:

| Field | Meaning |
|-------|---------|
| `minimumContractSet` | Contracts visible at first successful pass |
| `contractEscalationPath` | Failure class → granted contract/protocol per step |
| `executionProtocolPath` | Protocols active across the run |
| `protocolEscalationSucceeded` | Passed after switching away from `single_shot_patch` |
| `semanticRepairAttempted` | `semantic_repair_loop` executed |
| `behaviorFailureCaptured` | Pre-repair behavior check failure recorded |
| `apiShapeBefore` / `apiShapeAfter` | Public `def` signature snapshot |
| `apiShapeChanged` | API shape violated during repair |
| `semanticRepairSucceeded` | Repair passed behavior + shape + verify |
| `semanticRollbackTriggered` | Repair rolled back on violation |

**CRI penalties (v1.4):** `-15` API shape changed · `-10` behavior failure uncaptured (see [WHITEPAPER.md](WHITEPAPER.md) §7).

---

## 10. What this does not claim

- **Not** a measure of raw model intelligence or context-window size.
- **Not** proof that minimal visibility always beats maximal — only that **adaptive escalation** can reach the same reliability with measured, task-specific sufficiency.
- **Not** production agent policy — this is a **runtime broker design probe** with deterministic fixtures and a reference executor ground truth.

---

## 11. Example escalation traces

**Task 052 (visibility axis):**

```json
{
  "failureClass": "hidden_invariant_missing",
  "grantedContract": "hidden_invariant",
  "grantedProtocol": null,
  "protocolAfter": "single_shot_patch"
}
```

**Task 057 (execution axis):**

```json
{
  "failureClass": "concurrent_mutation_detected",
  "grantedContract": "stale_read_protocol",
  "grantedProtocol": "lock_read_validate_apply",
  "executionProtocolPath": ["single_shot_patch", "lock_read_validate_apply"],
  "protocolEscalationSucceeded": true
}
```

**Task 059 (semantic axis):**

```json
{
  "failureClass": "behavior_check_failed",
  "grantedContract": "behavior_check",
  "grantedProtocol": "semantic_repair_loop",
  "semanticRepairAttempted": true,
  "behaviorFailureCaptured": true,
  "apiShapeChanged": false,
  "semanticRepairSucceeded": true
}
```

---

**Source:** `orchestrator20260608T120655Z.jsonl` · Regenerate: `make benchmark-contract-orchestrator`

**Release gates (Phase 4):** `make benchmark-contract-release-check` · Reliability case: [docs/agent-runtime-reliability-case.md](../../docs/agent-runtime-reliability-case.md)
