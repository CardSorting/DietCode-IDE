#!/usr/bin/env python3
"""Run live-server agent integration harnesses and emit one NDJSON summary."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from agent_test_support import add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, emit_test_line, finish_test_run


SUITES: list[tuple[str, list[str]]] = [
    ("control_smoke", [sys.executable, "scripts/control_smoke_test.py", "--compact"]),
    ("task_server_health", [sys.executable, "scripts/test_task_server_health.py", "--compact"]),
    ("rpc_transaction", [sys.executable, "scripts/test_rpc_transaction_health.py", "--compact"]),
    ("ergonomics", [sys.executable, "scripts/test_ergonomics.py", "--compact"]),
    ("operator_diagnostics", [sys.executable, "scripts/test_operator_diagnostics.py", "--compact"]),
    ("runtime_safety", [sys.executable, "scripts/test_runtime_safety.py", "--compact"]),
    ("grep_diff_tooling", [sys.executable, "scripts/test_grep_diff_tooling.py", "--compact"]),
    ("runtime_determinism", [sys.executable, "scripts/test_runtime_determinism.py", "--compact"]),
    ("transaction_kernel", [sys.executable, "scripts/test_transaction_kernel.py", "--compact"]),
    ("harness_realism", [sys.executable, "scripts/test_harness_realism.py", "--compact"]),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run agent integration harnesses with NDJSON rollup.")
    add_output_args(parser)
    parser.add_argument(
        "--suite",
        action="append",
        choices=tuple(name for name, _ in SUITES),
        help="Run only the named suite(s). Default: all.",
    )
    args = parser.parse_args()
    compact = output_compact(args)
    selected = {name: cmd for name, cmd in SUITES if not args.suite or name in args.suite}
    checks: list[dict] = []

    for name, cmd in selected.items():
        completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True)
        ok = completed.returncode == 0
        detail: dict = {"exitCode": completed.returncode}
        if not ok:
            detail["stderrTail"] = completed.stderr.strip()[-500:] if completed.stderr else ""
            detail["stdoutTail"] = completed.stdout.strip()[-500:] if completed.stdout else ""
        payload = {"type": "check", "name": name, "ok": ok, "detail": detail}
        checks.append(payload)
        emit_test_line(payload, compact=compact)
        if args.verbose:
            if completed.stdout:
                print(completed.stdout, file=sys.stderr, end="" if completed.stdout.endswith("\n") else "\n")
            if completed.stderr:
                print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")

    return finish_test_run(checks, suite="agent_integration", compact=compact)


if __name__ == "__main__":
    raise SystemExit(main())
