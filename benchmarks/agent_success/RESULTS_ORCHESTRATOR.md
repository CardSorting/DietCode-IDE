# Runtime Contract Orchestrator — Results

**Generated:** 2026-06-08T11:56:46Z

> Reliable bounded autonomy emerges through adaptive runtime contract escalation, not static maximal visibility.

> Runtime contract visibility tells the agent what truth exists; execution protocols determine whether mutation remains safe under changing state.

Methodology: [WHITEPAPER.md](WHITEPAPER.md) §Phase 3–3.1

---

## Minimum Contract Set (MCS) — nightmare tier

| task | passed | MCS (observed) | protocol path | escalations | match |
|------|--------|----------------|---------------|------------:|-------|
| 051 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 052 | PASS | hidden_invariant, readme, verify_grep | single_shot_patch | 1 | True |
| 053 | PASS | readme, verify_grep | single_shot_patch | 0 | True |
| 054 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 055 | PASS | behavior_check, readme, verify_exec, verify_grep | single_shot_patch | 1 | True |
| 056 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 057 | PASS | readme, stale_read_protocol, verify_grep | single_shot_patch → lock_read_validate_apply | 1 | False |
| 058 | PASS | readme, verify_grep | single_shot_patch | 0 | False |
| 059 | FAIL | behavior_check, readme, verify_exec, verify_grep | single_shot_patch | 1 | — |
| 060 | PASS | readme, verify_grep | single_shot_patch | 0 | False |

## Executive summary

The orchestrator passed **9/10** nightmare tasks starting from `readme` + `verify_grep` + `single_shot_patch` only. Failures classify into visibility contracts *and* execution protocols; the broker retries from a clean snapshot.

**Phase 3.1:** task 057 escalates `concurrent_mutation_detected` → `stale_read_protocol` + `lock_read_validate_apply` (strip concurrent `VERSION = 3`, reconcile, re-apply).

**Key result:** task 052 MCS = `readme` + `verify_grep` + `hidden_invariant` (1 visibility escalation).

**Orchestrated pass rate:** 9/10

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

Source: `orchestrator20260608T115638Z.jsonl`
