# Audit Result — Agent Runtime Reliability Benchmark

**Audit ID:** `AUDIT_AGENT_RUNTIME_RELIABILITY_v1.0`  
**Benchmark version:** 1.2 · **Trace schema:** 1.0 · **Runtime:** DietCode 1.6.5  
**Date:** June 2026 · **Phase:** 4.1 Production Hardening Audit

---

## Scope

This audit covers the **agent success benchmark** reliability stack:

- Mutation trace provenance (`results/traces/<run_id>/<task_id>.mutation_trace.json`)
- Release gates (`make benchmark-contract-release-check`)
- Schema-frozen JSONL + trace contracts (`make test-agent-benchmark-schema`)
- Replay verifier (`replay_trace.py`)
- Workspace isolation, security boundaries, external-agent jail
- Negative release gate tests (`make test-release-gate-negative`)

**Out of scope:** external LLM agents, multi-host distribution, production repo-scale workloads.

---

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Tampered mutation evidence | `traceHash`, `gitCommit`, workspace hashes, replay verifier |
| Cross-task workspace leakage | Per-task `.workspaces/` copies; sidecar isolation tests |
| Harness secret leakage to agents | `agentInputManifest`; external argv jail; no `metadata.json` / `expected.patch` in agent surface |
| Decorative release gates | Negative gate tests mutate traces/JSONL and assert failure |
| Schema drift breaking tooling | Frozen field sets + contract/protocol/failureClass enums |
| Path traversal via trace paths | `validate_run_id` / `validate_task_id`; traces outside workspace |
| Hidden retry instability | `attemptCount`, `passedOnRetry`, `firstFailureClass` in trace + JSONL |

---

## Release Gates

Enforced by `release_check.py` (10 named gates):

| Gate | Requirement |
|------|-------------|
| `reference_nightmare_10_10` | Reference executor passes 051–060 |
| `orchestrated_nightmare_10_10` | Orchestrated broker passes 051–060 |
| `wrong_file_edited_zero` | No wrong-file edits |
| `api_shape_changed_zero` | No API shape violations |
| `rollback_dirty_zero` | No dirty rollback / sidecar residue |
| `destructive_allowed_zero` | task_060 destructive commands blocked |
| `task_052_hidden_invariant_escalation` | Visibility escalation proof |
| `task_057_lock_read_validate_apply_escalation` | Execution protocol proof |
| `task_059_semantic_repair_loop_escalation` | Semantic repair proof |
| `mutation_traces_present` | Non-empty replayable traces + integrity checks |

---

## Trace Integrity

Each orchestrated trace includes SLSA-inspired provenance:

```json
{
  "traceSchemaVersion": "1.0",
  "runtimeVersion": "1.6.5",
  "benchmarkVersion": "1.2",
  "gitCommit": "<repo HEAD>",
  "workspaceHashBefore": "<sha256>",
  "workspaceHashAfter": "<sha256>",
  "traceHash": "<sha256 of canonical trace body>",
  "parentRunId": "<optional>"
}
```

Verify with:

```bash
python3 benchmarks/agent_success/replay_trace.py \
  --trace benchmarks/agent_success/results/traces/<run>/<task>.mutation_trace.json \
  --jsonl benchmarks/agent_success/results/<run>.jsonl
```

Correlated observability events (`contract.escalated`, `protocol.escalated`, etc.) follow OpenTelemetry-style `traceId` / `spanId` structure in local JSON.

---

## Isolation Guarantees

- Each task receives a fresh workspace under `benchmarks/agent_success/.workspaces/`
- Sidecars from task N do not appear in task N+1 (tested: 053 → 054)
- `__pycache__` and `.agent_patches` excluded from integrity hashes
- Mutation traces written to `results/traces/` — never inside task workspace copies
- Run-scoped trace directories prevent cross-run artifact leakage

---

## Schema Stability

| Surface | Stability |
|---------|-----------|
| task_001–030 | **stable** |
| task_051–060 nightmare_v1 | **stable** |
| JSONL core fields | **stable** |
| `mutation_trace.json` provenance + steps | **stable** |
| Release gate names | **stable** |
| Observability event taxonomy | **stable** |
| CRI formula | **experimental** |
| MCS reference | **experimental** |
| task_061+ | **experimental** |

Freeze tests: `make test-agent-benchmark-schema`

---

## Negative Gate Tests

`test_release_gate_negative.py` proves gates fail when:

- task_052 trace/JSONL removes `hidden_invariant` escalation
- task_057 removes `lock_read_validate_apply`
- task_059 sets `apiShapeChanged=true`
- A trace file is deleted
- `wrongFileEdited=1` is injected

---

## Known Limitations

- Tiny fixtures (40 tasks); not representative of production repos
- Single-host DietCode runtime per run
- Built-in README/verify agent driver; external LLM evaluation partial
- No OpenTelemetry export — local JSON events only
- `traceHash` covers trace body, not workspace file contents post-hoc on other hosts
- Symlink targets outside workspace are hashed as link nodes, not followed trees

---

## Production Readiness Verdict

| Bar | Verdict |
|-----|---------|
| **Ready for research release** | **yes** |
| **Ready for external benchmark comparison** | **partial** (jail + schema stable; external LLM not certified) |
| **Ready for production autonomous mutation** | **no** |

### Claim (Phase 4.1)

> DietCode's agent reliability benchmark now produces versioned, replayable mutation evidence with release gates, negative gate tests, and schema-stable telemetry for bounded code mutation research.

---

## Commands

```bash
make test-agent-benchmark-schema    # schema + isolation + security + jail + negative gates
make test-release-gate-negative       # negative gate tests only
make benchmark-contract-release-check # full live gate run (requires DietCode server)
```
