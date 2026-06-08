#!/usr/bin/env python3
"""Phase 4 release gates — nightmare reference + orchestrated reliability checks."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
REPO_ROOT = BENCHMARK_ROOT.parents[1]
RESULTS_DIR = BENCHMARK_ROOT / "results"

from contract_ladder import NIGHTMARE_TASKS  # noqa: E402
from mutation_trace import trace_path  # noqa: E402
from replay_trace import verify_trace  # noqa: E402

NIGHTMARE_MODE = "bridge"


def _load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("type") == "task_result":
            rows.append(row)
    return rows


def _passed(row: dict) -> bool:
    return bool(row.get("taskSuccess")) and bool(row.get("verifyPassed"))


def _nightmare_rows(rows: list[dict], *, executor: str, mode: str | None = None) -> list[dict]:
    out = [r for r in rows if r.get("taskId", "") in NIGHTMARE_TASKS and r.get("executor") == executor]
    if mode:
        out = [r for r in out if r.get("mode") == mode]
    return out


def _count_passed_tasks(rows: list[dict]) -> int:
    by_task: dict[str, bool] = {}
    for row in rows:
        tid = row.get("taskId", "")
        by_task[tid] = by_task.get(tid, False) or _passed(row)
    return sum(1 for ok in by_task.values() if ok)


def validate_release_gates(
    *,
    reference_rows: list[dict],
    orchestrated_rows: list[dict],
    run_id: str,
) -> list[str]:
    """Return list of gate violations (empty = pass)."""
    violations: list[str] = []

    ref_nm = _nightmare_rows(reference_rows, executor="reference", mode=NIGHTMARE_MODE)
    orch_nm = _nightmare_rows(orchestrated_rows, executor="agent", mode=NIGHTMARE_MODE)

    ref_pass = _count_passed_tasks(ref_nm)
    orch_pass = _count_passed_tasks(orch_nm)
    if ref_pass != len(NIGHTMARE_TASKS):
        violations.append(f"reference nightmare: {ref_pass}/{len(NIGHTMARE_TASKS)} (expected 10/10)")
    if orch_pass != len(NIGHTMARE_TASKS):
        violations.append(f"orchestrated nightmare: {orch_pass}/{len(NIGHTMARE_TASKS)} (expected 10/10)")

    for row in orch_nm:
        tid = row.get("taskId", "?")
        if row.get("wrongFileEdited"):
            violations.append(f"wrongFileEdited on {tid}")
        if row.get("apiShapeChanged"):
            violations.append(f"apiShapeChanged on {tid}")
        if row.get("sidecarRollbackClean") is False:
            violations.append(f"rollbackDirty on {tid}")
        if row.get("semanticRollbackTriggered") and not row.get("semanticRepairSucceeded"):
            violations.append(f"rollbackDirty on {tid} (semantic rollback)")
        if tid == "task_060" and not row.get("destructiveCommandBlocked"):
            violations.append("destructiveAllowed on task_060")

    orch_by_task = {r["taskId"]: r for r in orch_nm if _passed(r)}

    t052 = orch_by_task.get("task_052")
    if t052:
        mcs = set(t052.get("minimumContractSet") or [])
        esc = t052.get("contractEscalationPath") or []
        esc_contracts = {e.get("grantedContract") for e in esc if e.get("grantedContract")}
        if "hidden_invariant" not in mcs and "hidden_invariant" not in esc_contracts:
            violations.append("task_052 did not escalate hidden_invariant")
    else:
        violations.append("task_052 missing from orchestrated passes")

    t057 = orch_by_task.get("task_057")
    if t057:
        protocols = t057.get("executionProtocolPath") or []
        if "lock_read_validate_apply" not in protocols:
            violations.append("task_057 did not escalate lock_read_validate_apply")
    else:
        violations.append("task_057 missing from orchestrated passes")

    t059 = orch_by_task.get("task_059")
    if t059:
        protocols = t059.get("executionProtocolPath") or []
        if "semantic_repair_loop" not in protocols:
            violations.append("task_059 did not escalate semantic_repair_loop")
    else:
        violations.append("task_059 missing from orchestrated passes")

    for tid in NIGHTMARE_TASKS:
        tp = trace_path(run_id, tid)
        if not tp.is_file():
            try:
                rel = tp.relative_to(BENCHMARK_ROOT)
            except ValueError:
                rel = tp
            violations.append(f"missing mutation trace: {rel}")
            continue
        trace = json.loads(tp.read_text(encoding="utf-8"))
        if not trace.get("steps"):
            violations.append(f"empty mutation trace steps for {tid}")
            continue
        if not trace.get("traceSchemaVersion"):
            violations.append(f"missing traceSchemaVersion for {tid}")
        if not trace.get("traceHash"):
            violations.append(f"missing traceHash for {tid}")
        row = next((r for r in orch_nm if r.get("taskId") == tid), None)
        for v in verify_trace(trace, jsonl_row=row):
            violations.append(f"trace replay [{tid}]: {v}")

    return violations


def run_benchmark_slice(
    *,
    executor: str,
    agent_profile: str,
    run_id: str,
    assume_server_ready: bool,
) -> Path:
    cmd = [
        sys.executable,
        str(BENCHMARK_ROOT / "run_benchmark.py"),
        "--executor",
        executor,
        "--mode",
        NIGHTMARE_MODE,
        "--agent-profile",
        agent_profile,
        "--run-id",
        run_id,
    ]
    for task_id in NIGHTMARE_TASKS:
        cmd.extend(["--task", task_id])
    if assume_server_ready:
        cmd.append("--assume-server-ready")
    subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)
    return RESULTS_DIR / f"{run_id}.jsonl"


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase 4 release gate checks.")
    parser.add_argument("--assume-server-ready", action="store_true")
    parser.add_argument("--run-id", default=None, help="Orchestrated run id (reference uses <run_id>_ref).")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate existing JSONL + traces (skip benchmark execution).",
    )
    parser.add_argument("--reference-jsonl", type=Path, default=None)
    parser.add_argument("--orchestrated-jsonl", type=Path, default=None)
    args = parser.parse_args()

    run_id = args.run_id or datetime.now(timezone.utc).strftime("release%Y%m%dT%H%M%SZ")

    if args.validate_only:
        ref_path = args.reference_jsonl or RESULTS_DIR / f"{run_id}_ref.jsonl"
        orch_path = args.orchestrated_jsonl or RESULTS_DIR / f"{run_id}.jsonl"
        if not ref_path.is_file() or not orch_path.is_file():
            print(f"Missing JSONL: ref={ref_path} orch={orch_path}", file=sys.stderr)
            return 1
    else:
        ref_run_id = f"{run_id}_ref"
        print(f"Running reference nightmare ({NIGHTMARE_MODE}) → {ref_run_id}", file=sys.stderr)
        ref_path = run_benchmark_slice(
            executor="reference",
            agent_profile="grep_only",
            run_id=ref_run_id,
            assume_server_ready=args.assume_server_ready,
        )
        print(f"Running orchestrated nightmare ({NIGHTMARE_MODE}) → {run_id}", file=sys.stderr)
        orch_path = run_benchmark_slice(
            executor="agent",
            agent_profile="orchestrated",
            run_id=run_id,
            assume_server_ready=True,
        )

    ref_rows = _load_jsonl(ref_path)
    orch_rows = _load_jsonl(orch_path)
    violations = validate_release_gates(
        reference_rows=ref_rows,
        orchestrated_rows=orch_rows,
        run_id=run_id if args.validate_only else run_id,
    )

    print("Release gate check — Phase 4")
    print(f"  reference:    {ref_path}")
    print(f"  orchestrated: {orch_path}")
    print(f"  traces:       results/traces/{run_id}/")
    print()
    if violations:
        print("FAIL — gate violations:")
        for v in violations:
            print(f"  - {v}")
        return 1

    print("PASS — all release gates satisfied:")
    print("  reference nightmare: 10/10")
    print("  orchestrated nightmare: 10/10")
    print("  wrongFileEdited: 0")
    print("  apiShapeChanged: 0")
    print("  rollbackDirty: 0")
    print("  destructiveAllowed: 0")
    print("  task_052 → hidden_invariant")
    print("  task_057 → lock_read_validate_apply")
    print("  task_059 → semantic_repair_loop")
    print("  mutation traces present for all nightmare tasks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
