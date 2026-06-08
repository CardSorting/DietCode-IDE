#!/usr/bin/env python3
"""Run Runtime Contract Evaluation Ladder across agent profiles on nightmare tasks."""

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

from contract_ladder import AGENT_PROFILES, NIGHTMARE_TASKS  # noqa: E402


def run_profile(profile: str, *, run_id: str, assume_ready: bool) -> Path:
    cmd = [
        sys.executable,
        str(BENCHMARK_ROOT / "run_benchmark.py"),
        "--executor",
        "agent",
        "--mode",
        "bridge",
        "--agent-profile",
        profile,
        "--run-id",
        f"{run_id}_{profile}",
    ]
    for task_id in NIGHTMARE_TASKS:
        cmd.extend(["--task", task_id])
    if assume_ready:
        cmd.append("--assume-server-ready")
    subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)
    return RESULTS_DIR / f"{run_id}_{profile}.jsonl"


def combine_jsonl(paths: list[Path], out: Path) -> None:
    with open(out, "w", encoding="utf-8") as handle:
        for path in paths:
            if not path.is_file():
                continue
            handle.write(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Run contract evaluation ladder on nightmare tasks.")
    parser.add_argument("--assume-server-ready", action="store_true")
    parser.add_argument("--run-id", default=None)
    parser.add_argument(
        "--profiles",
        nargs="*",
        choices=list(AGENT_PROFILES),
        default=list(AGENT_PROFILES),
    )
    parser.add_argument("--write-report", action="store_true", default=True)
    parser.add_argument("--no-write-report", action="store_false", dest="write_report")
    args = parser.parse_args()

    run_id = args.run_id or datetime.now(timezone.utc).strftime("ladder%Y%m%dT%H%M%SZ")

    if not args.assume_server_ready:
        subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py"), "--wait-ready", "--quiet"],
            cwd=str(REPO_ROOT),
            check=False,
        )

    jsonl_paths: list[Path] = []
    for profile in args.profiles:
        print(f"running profile: {profile}", file=sys.stderr)
        path = run_profile(profile, run_id=run_id, assume_ready=True)
        jsonl_paths.append(path)

    combined = RESULTS_DIR / f"{run_id}_combined.jsonl"
    combine_jsonl(jsonl_paths, combined)
    print(json.dumps({"type": "ladder_complete", "combined": str(combined), "profiles": args.profiles}))

    if args.write_report:
        from render_contract_ladder import write_contract_ladder_report

        write_contract_ladder_report(combined, BENCHMARK_ROOT / "RESULTS_CONTRACT_LADDER.md")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
