# Agent Success Benchmark

End-to-end benchmark harness for DietCode agent workflows.

**Whitepaper:** [WHITEPAPER.md](WHITEPAPER.md) · **Results:** [RESULTS.md](RESULTS.md) · **Nightmare:** [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md) · **Contract ladder:** [RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md)

Each task exercises a
realistic agent pattern (search → inspect → patch, stale recovery, symlink safety,
large-file avoidance, batch rollback, deprecated search recovery, partial results,
verify-after-mutation) against an isolated fixture workspace.

## Layout

```text
benchmarks/agent_success/
  generate_fixtures.py   # (re)generate task fixture repos
  run_benchmark.py       # benchmark runner (Mode A / Mode B, reference or agent executor)
  report_results.py      # comparison report from JSONL results
  agent_driver.py        # optional README-driven agent executor
  tasks/task_NNN/        # per-task README, metadata, before/, expected.patch, verify.sh
  results/               # JSONL run output (gitignored)
```

## Modes

| Mode | Flag | Stack |
|------|------|-------|
| **A** | `--mode raw_rpc` | Raw shell + `dietcode_agent_client.py` RPC |
| **B** | `--mode bridge` | Agent Bridge CLI (`dietcode-agent-client`) safe workflows |

## Executors

| Executor | Flag | Description |
|----------|------|-------------|
| **reference** (default) | `--executor reference` | Deterministic workflow baseline (control) |
| **agent** | `--executor agent` | README + verify-driven driver (`agent_driver.py`) |

### Runtime Contract Evaluation Ladder (agent profiles)

| Profile | Allowed contract visibility |
|---------|----------------------------|
| `grep_only` (default) | README + parsed grep checks |
| `verify_exec` | + run `verify.sh` / shell checks |
| `invariant_aware` | + `verify_invariant.sh` |
| `trace_aware` | + declared trace scripts |
| `contract_full` | + all executable checks (no metadata) |
| `recovery_aware` | + rollback/retry transactional loop |

```bash
python3 benchmarks/agent_success/run_benchmark.py --executor agent --agent-profile invariant_aware --mode bridge
make benchmark-contract-ladder   # nightmare tasks × all profiles → RESULTS_CONTRACT_LADDER.md
```

Override the built-in agent with an external script:

```bash
export AGENT_BENCHMARK_AGENT_SCRIPT=/path/to/your_agent.py
python3 benchmarks/agent_success/run_benchmark.py --executor agent --mode bridge
```

## Quick start

```bash
# Regenerate fixture files (optional — committed fixtures ship with the repo)
python3 benchmarks/agent_success/generate_fixtures.py

# Fast iteration — assumes DietCode socket already matches HEAD
make benchmark-agent-success-fast

# Full run — rebuild app and restart agent server first
make benchmark-agent-success

# Report only (latest JSONL in results/)
make benchmark-agent-success-report
```

## Metrics (JSONL)

Each task/mode run emits one line to `results/<run-id>.jsonl`:

- `taskSuccess`, `verifyPassed`, `wrongFileEdited`
- `staleRecoverySucceeded`, `rollbackSucceeded`
- `retries`, `toolCallCount`, `durationMs`
- `failureCode`, `recoveryHintsUsed`
- `commandsUsed`, `patchValidateFailures`
- Nightmare contract: `destructiveCommandBlocked`, `sidecarRollbackClean`,
  `concurrentMutationDetected`, `searchReadMismatchDetected`, `apiShapePreserved`,
  `secondInvariantPassed`, `finalVerifyPassed`
- Contract ladder: `contractCoverage`, `contractReliabilityIndex`, `agentProfile`

## Task categories (40 tasks)

### Normal (001–020)

| Category | Tasks |
|----------|-------|
| Literal search → inspect → patch | 001–002 |
| Multi-file patch | 003–004 |
| Stale content recovery | 005–006 |
| Symlink rejection | 007–008 |
| Large file avoidance | 009–010 |
| Shell rg → sedRange context | 011–012 |
| Batch patch rollback | 013–014 |
| Deprecated semantic search recovery | 015–016 |
| Partial / truncated results | 017–018 |
| Verify-after-mutation | 019–020 |

### Adversarial (021–030)

| Task | Trap | What it tests |
|------|------|---------------|
| 021 | wrong_file_decoy | Similar filenames — edit the correct one |
| 022 | verify_only_requirement | Incomplete README — verify reveals requirement |
| 023 | preserve_partial_fix | Do not overwrite already-correct code |
| 024 | recover_from_failed_patch | First patch fails — retry required |
| 025 | multi_file_coordination | Implementation + export + test stay consistent |
| 026 | stale_read_recovery | File changes after read — stale recovery |
| 027 | rollback_after_corruption | Bad patch breaks verify — rollback then fix |
| 028 | noop_success_trap | Grep decoy passes — behavior must actually change |
| 029 | path_containment_decoy | Tempting out-of-workspace target ignored |
| 030 | ambiguous_symbol_choice | Same symbol in two modules — patch the live one |

Adversarial tasks set `metadata.json` fields: `adversarial`, `trapType`,
`expectedFailureModes`, `requiresRecovery`, `requiresRollback`, `mustInspectVerify`.

**Agent honesty rule:** in `--executor agent` mode, the driver sees only
`README.md`, `verify.sh`, and workspace files via tools — never `trapType`,
`expected.patch`, or workflow metadata.

## Reports

`report_results.py` writes `results/summary.md` and `results/summary.json` with:

- **Evaluation Claim** — reference vs agent framing (claim-ready prose)
- **Money table** — normal vs adversarial pass rates by executor/mode
- **Adversarial Trap Matrix** — per-`trapType` pass rate, wrong-file, rollback, recovery, retries

```bash
make benchmark-agent-success-report
make test-agent-success-report    # smoke test — claim format must not regress
```

`summary.md` states executor coverage (`reference` / `agent` present or absent).
Reference-only runs include a warning when agent results are missing.

### Nightmare (051–060)

| Task | Trap | What it tests |
|------|------|---------------|
| 051 | spec_shadowing | README/decoys imply wrong target; execution trace reveals live path |
| 052 | two_phase_invariant | First verify passes; second invariant catches hidden regression |
| 053 | rollback_with_sidecar | Bad patch leaves sidecars; rollback must restore full workspace |
| 054 | import_cycle_temptation | Obvious fix creates circular import; correct fix is lower-level |
| 055 | poisoned_golden_string | Decoy contains golden string; behavior validated by execution |
| 056 | chmod_and_symlink_swap | Permissions/symlink change between inspect and apply |
| 057 | concurrent_agent_conflict | Simulated second writer mutates file mid-run |
| 058 | stale_search_index | Search shows stale copy; direct read is source of truth |
| 059 | semantic_preservation | Fix bug while preserving public API and output shape |
| 060 | irreversible_operation_trap | README tempts destructive cache wipe; runtime must contain it |

Nightmare tasks set `metadata.json` fields: `nightmare`, `tier: "nightmare"`, plus
adversarial trap metadata. Tasks 052+ may ship `verify_invariant.sh` for a second-phase check.

The reference executor proves the tools can solve it. The agent executor reveals
whether autonomy survives the traps — including the nightmare runtime contract layer.
