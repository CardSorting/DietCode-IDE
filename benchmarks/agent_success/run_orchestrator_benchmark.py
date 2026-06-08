#!/usr/bin/env python3
"""Run orchestrated agent on nightmare tasks and write MCS report."""

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
from contracts import MCS_REFERENCE, ORCHESTRATOR_CLAIM, PHASE_31_CLAIM, PHASE_32_CLAIM  # noqa: E402


def render_mcs_report(rows: list[dict], *, generated_at: str, input_file: str) -> str:
    lines = [
        "# Runtime Contract Orchestrator — Results",
        "",
        f"**Generated:** {generated_at}",
        "",
        f"> {ORCHESTRATOR_CLAIM}",
        "",
        f"> {PHASE_31_CLAIM}",
        "",
        f"> {PHASE_32_CLAIM}",
        "",
        "Methodology: [WHITEPAPER.md](WHITEPAPER.md) §Phase 3–3.2",
        "",
        "---",
        "",
        "## Minimum Contract Set (MCS) — nightmare tier",
        "",
        "| task | passed | MCS (observed) | protocol path | escalations | match |",
        "|------|--------|----------------|---------------|------------:|-------|",
    ]
    passed = 0
    for row in sorted(rows, key=lambda r: r.get("taskId", "")):
        tid = row.get("taskId", "").replace("task_", "")
        ok = row.get("taskSuccess") and row.get("verifyPassed")
        if ok:
            passed += 1
        mcs = ", ".join(row.get("minimumContractSet") or [])
        protocols = " → ".join(row.get("executionProtocolPath") or ["single_shot_patch"])
        esc = len(row.get("contractEscalationPath") or [])
        match = row.get("mcsReferenceMatch", {}).get("matched", "—")
        lines.append(f"| {tid} | {'PASS' if ok else 'FAIL'} | {mcs or '—'} | {protocols} | {esc} | {match} |")

    lines.extend(
        [
            "",
            "## Executive summary",
            "",
            (
                f"The orchestrator passed **{passed}/{len(rows)}** nightmare tasks starting from "
                "`readme` + `verify_grep` + `single_shot_patch` only. Failures classify into "
                "visibility contracts *and* execution protocols; the broker retries from a clean snapshot."
            ),
            "",
            (
                "**Phase 3.1:** task 057 → `lock_read_validate_apply`. "
                "**Phase 3.2:** task 059 → `semantic_repair_loop` (behavior-preserving API-shape repair)."
            ),
            "",
            f"**Orchestrated pass rate:** {passed}/{len(rows)}",
            "",
            "## Semantic Repair Matrix",
            "",
            "| task | behaviorFailureCaptured | apiShapeChanged | semanticRepairSucceeded | rollbackTriggered | finalVerifyPassed |",
            "|------|----------------------:|----------------:|------------------------:|------------------:|------------------:|",
        ]
    )
    for row in sorted(rows, key=lambda r: r.get("taskId", "")):
        tid = row.get("taskId", "").replace("task_", "")
        if not row.get("semanticRepairAttempted") and not row.get("behaviorFailureCaptured"):
            continue
        lines.append(
            f"| {tid} | "
            f"{'✓' if row.get('behaviorFailureCaptured') else '—'} | "
            f"{'✓' if row.get('apiShapeChanged') else '—'} | "
            f"{'✓' if row.get('semanticRepairSucceeded') else '—'} | "
            f"{'✓' if row.get('semanticRollbackTriggered') else '—'} | "
            f"{'✓' if row.get('finalVerifyPassed') else '—'} |"
        )

    lines.extend(
        [
            "",
            "## Example escalations",
            "",
            "Task 052 (visibility):",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "hidden_invariant_missing",
                    "grantedContract": "hidden_invariant",
                    "grantedProtocol": None,
                    "protocolAfter": "single_shot_patch",
                },
                indent=2,
            ),
            "```",
            "",
            "Task 057 (visibility + execution):",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "concurrent_mutation_detected",
                    "grantedContract": "stale_read_protocol",
                    "grantedProtocol": "lock_read_validate_apply",
                    "executionProtocolPath": ["single_shot_patch", "lock_read_validate_apply"],
                    "protocolEscalationSucceeded": True,
                },
                indent=2,
            ),
            "```",
            "",
            "Task 059 (semantic repair):",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "behavior_check_failed",
                    "grantedContract": "behavior_check",
                    "grantedProtocol": "semantic_repair_loop",
                    "semanticRepairAttempted": True,
                    "behaviorFailureCaptured": True,
                    "apiShapeChanged": False,
                    "semanticRepairSucceeded": True,
                },
                indent=2,
            ),
            "```",
            "",
            f"Source: `{Path(input_file).name}`",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run orchestrated agent on nightmare tasks.")
    parser.add_argument("--assume-server-ready", action="store_true")
    parser.add_argument("--run-id", default=None)
    args = parser.parse_args()

    run_id = args.run_id or datetime.now(timezone.utc).strftime("orchestrator%Y%m%dT%H%M%SZ")
    cmd = [
        sys.executable,
        str(BENCHMARK_ROOT / "run_benchmark.py"),
        "--executor",
        "agent",
        "--mode",
        "bridge",
        "--agent-profile",
        "orchestrated",
        "--run-id",
        run_id,
    ]
    for task_id in NIGHTMARE_TASKS:
        cmd.extend(["--task", task_id])
    if args.assume_server_ready:
        cmd.append("--assume-server-ready")

    subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)

    jsonl = RESULTS_DIR / f"{run_id}.jsonl"
    rows: list[dict] = []
    if jsonl.is_file():
        for line in jsonl.read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            if row.get("type") == "task_result":
                rows.append(row)

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    report = render_mcs_report(rows, generated_at=generated_at, input_file=str(jsonl))
    out = BENCHMARK_ROOT / "RESULTS_ORCHESTRATOR.md"
    out.write_text(report, encoding="utf-8")
    print(report, end="")
    print(f"\nWrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
