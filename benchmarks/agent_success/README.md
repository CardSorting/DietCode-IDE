# Agent Success Benchmark

End-to-end benchmark harness for DietCode agent workflows. Each task exercises a
realistic agent pattern (search → inspect → patch, stale recovery, symlink safety,
large-file avoidance, batch rollback, deprecated search recovery, partial results,
verify-after-mutation) against an isolated fixture workspace.

## Layout

```text
benchmarks/agent_success/
  generate_fixtures.py   # (re)generate task fixture repos
  run_benchmark.py       # reference-agent runner (Mode A / Mode B)
  tasks/task_NNN/        # per-task README, metadata, before/, expected.patch, verify.sh
  results/               # JSONL run output (gitignored)
```

## Modes

| Mode | Flag | Stack |
|------|------|-------|
| **A** | `--mode raw_rpc` | Raw shell + `dietcode_agent_client.py` RPC |
| **B** | `--mode bridge` | Agent Bridge CLI (`dietcode-agent-client`) safe workflows |

## Quick start

```bash
# Regenerate fixture files (optional — committed fixtures ship with the repo)
python3 benchmarks/agent_success/generate_fixtures.py

# Fast iteration — assumes DietCode socket already matches HEAD
make benchmark-agent-success-fast

# Full run — rebuild app and restart agent server first
make benchmark-agent-success
```

## Metrics (JSONL)

Each task/mode run emits one line to `results/<run-id>.jsonl`:

- `taskSuccess`, `verifyPassed`, `wrongFileEdited`
- `staleRecoverySucceeded`, `rollbackSucceeded`
- `retries`, `toolCallCount`, `durationMs`
- `failureCode`, `recoveryHintsUsed`
- `commandsUsed`, `patchValidateFailures`

## Task categories (20 tasks)

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
