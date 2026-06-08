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
from render_orchestrator_findings import render_orchestrator_findings  # noqa: E402


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
    report = render_orchestrator_findings(rows, generated_at=generated_at, input_file=str(jsonl))
    out = BENCHMARK_ROOT / "RESULTS_ORCHESTRATOR.md"
    out.write_text(report, encoding="utf-8")
    print(report, end="")
    print(f"\nWrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
