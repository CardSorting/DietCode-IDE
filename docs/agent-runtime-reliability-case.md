# Agent Runtime Reliability Case

**DietCode Agent Success Benchmark · Phase 4**  
**Version:** 1.4 · June 2026

---

## Claim

Bounded mutation reliability requires **three separable controls**:

1. **Contract visibility** — what runtime truth the agent may observe  
2. **Execution protocol escalation** — how mutation stays safe under changing workspace state  
3. **Semantic repair discipline** — how behavior changes without public API drift  

> DietCode emits replayable mutation traces and enforces release gates for bounded agent code mutation across visibility, execution, and semantic-repair controls.

---

## Evidence

| Evidence | Result | Source |
|----------|--------|--------|
| Nightmare reference (051–060) | **10/10** tasks | `release_check.py` · `bridge` mode |
| Orchestrated broker (051–060) | **10/10** tasks | [RESULTS_ORCHESTRATOR.md](../benchmarks/agent_success/RESULTS_ORCHESTRATOR.md) |
| Wrong-file edits | **0** | JSONL `wrongFileEdited` |
| API shape violations | **0** | JSONL `apiShapeChanged` |
| Rollback integrity | **0 dirty** | `sidecarRollbackClean` · semantic rollback telemetry |

### Representative proofs

| Task | Trap | Control axis | Escalation observed |
|------|------|--------------|---------------------|
| **052** | two_phase_invariant | Visibility | `hidden_invariant` granted after `hidden_invariant_missing` |
| **057** | concurrent_agent_conflict | Execution | `lock_read_validate_apply` after `concurrent_mutation_detected` |
| **059** | semantic_preservation | Semantic repair | `semantic_repair_loop` after `behavior_check_failed` |

### Mutation trace artifacts

Every orchestrated run writes per-task traces:

```text
benchmarks/agent_success/results/traces/<run_id>/<task_id>.mutation_trace.json
```

Each trace records:

- `initialContracts` / `initialProtocol` (minimal start state)
- `steps[]` — attempt, contracts, protocol, result, `failureClass`
- `finalState` — `passed`, `wrongFileEdited`, `apiShapeChanged`, `rollbackDirty`, `destructiveAllowed`
- `telemetry` — MCS, protocol path, escalation path

Traces are **replayable failure narratives** for escalation debugging (Playwright-style isolation + retry traces; OpenTelemetry-style correlated signals).

---

## Limits

This reliability case does **not** yet cover:

- **Tiny fixtures** — 40 tasks, not production repos  
- **Single host/runtime** — one DietCode server profile per run  
- **Built-in agent** — README + verify-driven driver, not external LLM agents  
- **No long-running workload** — no multi-hour repo-scale mutation campaigns  
- **Experimental metrics** — CRI formula and MCS reference tables may change (see stability tiers)

---

## Release Gates

Enforced by:

```bash
make benchmark-contract-release-check
```

| Gate | Requirement |
|------|-------------|
| Reference nightmare | **10/10** tasks pass (`executor=reference`, `bridge`) |
| Orchestrated nightmare | **10/10** tasks pass (`agent-profile=orchestrated`) |
| `wrongFileEdited` | **0** across orchestrated nightmare rows |
| `apiShapeChanged` | **0** |
| `rollbackDirty` | **0** (sidecar / semantic rollback violations) |
| `destructiveAllowed` | **0** (task 060 must block destructive command) |
| Task **052** | Escalates `hidden_invariant` |
| Task **057** | Protocol path includes `lock_read_validate_apply` |
| Task **059** | Protocol path includes `semantic_repair_loop` |
| Mutation traces | One non-empty trace per nightmare task under `results/traces/<run_id>/` |

Validate an existing run without re-executing benchmarks:

```bash
python3 benchmarks/agent_success/release_check.py \
  --validate-only \
  --run-id <orchestrated_run_id> \
  --reference-jsonl benchmarks/agent_success/results/<run_id>_ref.jsonl
```

---

## Stability tiers

| Surface | Stability |
|---------|-----------|
| `task_001`–`task_030` (base + adversarial) | **stable** |
| `task_051`–`task_060` (`nightmare_v1`) | **stable** |
| JSONL telemetry core fields (`taskSuccess`, `verifyPassed`, `wrongFileEdited`, escalation paths) | **stable** |
| Mutation trace schema (`steps`, `finalState`, `initialContracts`) | **stable** |
| Release gate predicates | **stable** |
| CRI formula | **experimental** |
| MCS reference table | **experimental** |
| Future tasks `task_061+` | **experimental** |

---

## Industry alignment (informative)

| Practice | Industry pattern | DietCode implementation |
|----------|------------------|-------------------------|
| Isolation + retry traces | [Playwright browser contexts](https://playwright.dev/docs/browser-contexts) | Workspace snapshot restore + per-attempt mutation traces |
| Correlated observability | [OpenTelemetry](https://opentelemetry.io/) traces/metrics/logs | Contract grants, protocol paths, rollback and semantic-repair events in JSONL + traces |
| Provenance / integrity | [SLSA](https://slsa.dev/) supply-chain levels | Mutation provenance per attempt; post-mutation workspace integrity checks |

---

## Related documents

- [WHITEPAPER.md](../benchmarks/agent_success/WHITEPAPER.md) — methodology  
- [RESULTS_ORCHESTRATOR.md](../benchmarks/agent_success/RESULTS_ORCHESTRATOR.md) — three-axis findings  
- [RESULTS_CONTRACT_LADDER.md](../benchmarks/agent_success/RESULTS_CONTRACT_LADDER.md) — static profile ladder  
- [NIGHTMARE_RESULTS.md](../benchmarks/agent_success/NIGHTMARE_RESULTS.md) — nightmare tier baseline  
