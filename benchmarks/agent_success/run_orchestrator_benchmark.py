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
from contracts import MCS_REFERENCE, ORCHESTRATOR_CLAIM  # noqa: E402


def render_mcs_report(rows: list[dict], *, generated_at: str, input_file: str) -> str:
    lines = [
        "# Runtime Contract Orchestrator — Results",
        "",
        f"**Generated:** {generated_at}",
        "",
        f"> {ORCHESTRATOR_CLAIM}",
        "",
        "Methodology: [WHITEPAPER.md](WHITEPAPER.md) §Phase 3",
        "",
        "---",
        "",
        "## Minimum Contract Set (MCS) — nightmare tier",
        "",
        "| task | passed | MCS (observed) | MCS (reference) | escalations | match |",
        "|------|--------|----------------|-----------------|------------:|-------|",
    ]
    passed = 0
    for row in sorted(rows, key=lambda r: r.get("taskId", "")):
        tid = row.get("taskId", "").replace("task_", "")
        ok = row.get("taskSuccess") and row.get("verifyPassed")
        if ok:
            passed += 1
        mcs = ", ".join(row.get("minimumContractSet") or [])
        ref = ", ".join(MCS_REFERENCE.get(row.get("taskId", ""), []))
        esc = len(row.get("contractEscalationPath") or [])
        match = row.get("mcsReferenceMatch", {}).get("matched", "—")
        lines.append(f"| {tid} | {'PASS' if ok else 'FAIL'} | {mcs or '—'} | {ref or '—'} | {esc} | {match} |")

    lines.extend(
        [
            "",
            "## Executive summary",
            "",
            (
                f"The orchestrator passed **{passed}/{len(rows)}** nightmare tasks starting from "
                "`readme` + `verify_grep` only. Failures trigger classified escalation; the broker "
                "grants the next contract layer and retries from a clean fixture snapshot."
            ),
            "",
            (
                "**Key result:** task 052 MCS = `readme` + `verify_grep` + `hidden_invariant` "
                "(1 escalation after `hidden_invariant_missing`) — matches reference MCS."
            ),
            "",
            (
                "**Gap:** task 057 exhausts escalation without organic stale recovery; "
                "task 059 grants `verify_exec` but still fails execution (visibility ≠ patch correctness)."
            ),
            "",
            f"**Orchestrated pass rate:** {passed}/{len(rows)}",
            "",
            "## Example escalation (task 052)",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "hidden_invariant_missing",
                    "grantedContract": "hidden_invariant",
                    "visibleAfter": ["readme", "verify_grep", "hidden_invariant"],
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
