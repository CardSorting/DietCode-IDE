# Runtime Contract Orchestrator — Results

**Generated:** 2026-06-08T12:07:04Z

> Reliable bounded autonomy emerges through adaptive runtime contract escalation, not static maximal visibility.

> Runtime contract visibility tells the agent what truth exists; execution protocols determine whether mutation remains safe under changing state.

> Bounded mutation reliability requires three separable controls: contract visibility, safe execution protocol, and semantic repair discipline.

Methodology: [WHITEPAPER.md](WHITEPAPER.md) §Phase 3–3.2

---

## Minimum Contract Set (MCS) — nightmare tier

| task | passed | MCS (observed) | protocol path | escalations | match |
|------|--------|----------------|---------------|------------:|-------|
| 051 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 052 | PASS | hidden_invariant, readme, verify_grep | single_shot_patch | 1 | True |
| 053 | PASS | readme, verify_grep | single_shot_patch | 0 | True |
| 054 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 055 | PASS | api_shape_contract, behavior_check, readme, verify_exec, verify_grep | single_shot_patch → semantic_repair_loop | 1 | False |
| 056 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 057 | PASS | readme, stale_read_protocol, verify_grep | single_shot_patch → lock_read_validate_apply | 1 | False |
| 058 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 059 | PASS | api_shape_contract, behavior_check, readme, verify_exec, verify_grep | single_shot_patch → semantic_repair_loop | 1 | True |
| 060 | PASS | readme, verify_grep | single_shot_patch | 0 | False |

## Executive summary

The orchestrator passed **10/10** nightmare tasks starting from `readme` + `verify_grep` + `single_shot_patch` only. Failures classify into visibility contracts *and* execution protocols; the broker retries from a clean snapshot.

**Phase 3.1:** task 057 → `lock_read_validate_apply`. **Phase 3.2:** task 059 → `semantic_repair_loop` (behavior-preserving API-shape repair).

**Orchestrated pass rate:** 10/10

## Semantic Repair Matrix

| task | behaviorFailureCaptured | apiShapeChanged | semanticRepairSucceeded | rollbackTriggered | finalVerifyPassed |
|------|----------------------:|----------------:|------------------------:|------------------:|------------------:|
| 055 | ✓ | — | ✓ | — | ✓ |
| 059 | ✓ | — | ✓ | — | ✓ |

## Example escalations

Task 052 (visibility):

```json
{
  "failureClass": "hidden_invariant_missing",
  "grantedContract": "hidden_invariant",
  "grantedProtocol": null,
  "protocolAfter": "single_shot_patch"
}
```

Task 057 (visibility + execution):

```json
{
  "failureClass": "concurrent_mutation_detected",
  "grantedContract": "stale_read_protocol",
  "grantedProtocol": "lock_read_validate_apply",
  "executionProtocolPath": [
    "single_shot_patch",
    "lock_read_validate_apply"
  ],
  "protocolEscalationSucceeded": true
}
```

Task 059 (semantic repair):

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

Source: `orchestrator20260608T120655Z.jsonl`
