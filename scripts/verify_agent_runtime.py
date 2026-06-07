#!/usr/bin/env python3
"""
CONTRACT: Strongest safe local verification ladder — grep-friendly NDJSON rollup.

Grep: rg 'verify_agent_runtime|verify-agent-runtime' scripts/ Makefile docs/
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from agent_test_support import add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, emit_test_line, finish_test_run

# Ordered ladder: offline first, then live-server contracts.
LADDER: list[tuple[str, list[str], bool]] = [
    ("offline_self_test", [sys.executable, "scripts/dietcode_agent_client.py", "--self-test", "--compact"], False),
    ("offline_contract_lockdown", [sys.executable, "scripts/test_contract_lockdown.py", "--compact"], False),
    ("live_control_smoke", [sys.executable, "scripts/control_smoke_test.py", "--compact"], True),
    ("live_task_health", [sys.executable, "scripts/test_task_server_health.py", "--compact"], True),
    ("live_rpc_transaction", [sys.executable, "scripts/test_rpc_transaction_health.py", "--compact"], True),
    ("live_ergonomics", [sys.executable, "scripts/test_ergonomics.py", "--compact"], True),
    ("live_operator_diagnostics", [sys.executable, "scripts/test_operator_diagnostics.py", "--compact"], True),
    ("live_runtime_safety", [sys.executable, "scripts/test_runtime_safety.py", "--compact"], True),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run verify-agent-runtime ladder with NDJSON summary.")
    add_output_args(parser)
    parser.add_argument("--skip-live", action="store_true", help="Run offline steps only.")
    args = parser.parse_args()
    compact = output_compact(args)
    checks: list[dict] = []

    if not args.skip_live:
        prep = subprocess.run(
            ["make", "app"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        if prep.returncode != 0:
            payload = {
                "type": "check",
                "name": "prep.make_app",
                "ok": False,
                "detail": {"exitCode": prep.returncode, "stderrTail": prep.stderr[-500:]},
            }
            checks.append(payload)
            emit_test_line(payload, compact=compact)
            return finish_test_run(checks, suite="verify_agent_runtime", compact=compact)
        ready = subprocess.run(
            [sys.executable, "scripts/dietcode_agent_client.py", "--wait-ready", "--compact", "--error-json", "--quiet"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        prep_ok = ready.returncode == 0
        payload = {"type": "check", "name": "prep.wait_ready", "ok": prep_ok, "detail": {"exitCode": ready.returncode}}
        checks.append(payload)
        emit_test_line(payload, compact=compact)
        if not prep_ok:
            return finish_test_run(checks, suite="verify_agent_runtime", compact=compact)

    for name, cmd, needs_live in LADDER:
        if args.skip_live and needs_live:
            continue
        completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True)
        ok = completed.returncode == 0
        detail: dict = {"exitCode": completed.returncode}
        if not ok:
            detail["stderrTail"] = completed.stderr.strip()[-400:]
            detail["stdoutTail"] = completed.stdout.strip()[-400:]
        payload = {"type": "check", "name": name, "ok": ok, "detail": detail}
        checks.append(payload)
        emit_test_line(payload, compact=compact)
        if args.verbose and completed.stdout:
            print(completed.stdout, file=sys.stderr, end="" if completed.stdout.endswith("\n") else "\n")

    return finish_test_run(checks, suite="verify_agent_runtime", compact=compact)


if __name__ == "__main__":
    raise SystemExit(main())
