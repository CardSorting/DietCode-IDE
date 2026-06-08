# Runtime Contract Orchestrator — Results

**Generated:** 2026-06-08T11:47:47Z

> Reliable bounded autonomy emerges through adaptive runtime contract escalation, not static maximal visibility.

Methodology: [WHITEPAPER.md](WHITEPAPER.md) §Phase 3

---

## Minimum Contract Set (MCS) — nightmare tier

| task | passed | MCS (observed) | MCS (reference) | escalations | match |
|------|--------|----------------|-----------------|------------:|-------|
| 051 | PASS | readme, verify_grep | readme, verify_grep, execution_trace | 0 | False |
| 052 | PASS | hidden_invariant, readme, verify_grep | readme, verify_grep, hidden_invariant | 1 | True |
| 053 | PASS | readme, verify_grep | readme, verify_grep | 0 | True |
| 054 | PASS | readme, verify_grep | readme, verify_grep, verify_exec | 0 | False |
| 055 | PASS | behavior_check, readme, verify_exec, verify_grep | readme, verify_grep, verify_exec, behavior_check | 1 | True |
| 056 | PASS | readme, verify_grep | readme, verify_grep, stale_read_protocol | 0 | False |
| 057 | FAIL | behavior_check, execution_trace, hidden_invariant, readme, verify_exec, verify_grep | readme, verify_grep, stale_read_protocol, authoritative_read | 3 | — |
| 058 | PASS | readme, verify_grep | readme, verify_grep, authoritative_read | 0 | False |
| 059 | FAIL | behavior_check, readme, verify_exec, verify_grep | readme, verify_grep, verify_exec, behavior_check | 1 | — |
| 060 | PASS | readme, verify_grep | readme, verify_grep, destructive_policy | 0 | False |

## Executive summary

The orchestrator passed **8/10** nightmare tasks starting from `readme` + `verify_grep` only. Failures trigger classified escalation; the broker grants the next contract layer and retries from a clean fixture snapshot.

**Key result:** task 052 MCS = `readme` + `verify_grep` + `hidden_invariant` (1 escalation after `hidden_invariant_missing`) — matches reference MCS.

**Gap:** task 057 exhausts escalation without organic stale recovery; task 059 grants `verify_exec` + `behavior_check` but still fails execution (visibility ≠ patch correctness).

**Orchestrated pass rate:** 8/10

## Example escalation (task 052)

```json
{
  "failureClass": "hidden_invariant_missing",
  "grantedContract": "hidden_invariant",
  "visibleAfter": [
    "readme",
    "verify_grep",
    "hidden_invariant"
  ]
}
```

Source: `orchestrator_smoke_20260608.jsonl`
