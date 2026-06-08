#!/usr/bin/env python3
"""
VERIFY: Full agent-runtime ladder including workflow smoke and docs drift.

Grep: rg 'verify_agent_runtime_full|verify-agent-runtime-full' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from agent_test_support import add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, emit_test_line, finish_test_run

NEXT_COMMANDS = {
    "offline_contract_lockdown": "python3 scripts/test_contract_lockdown.py --compact",
    "offline_docs_code_drift": "python3 scripts/test_docs_code_drift.py --compact",
    "live_deterministic_retrieval": "make test-deterministic-retrieval",
    "live_transaction_kernel": "make test-transaction-kernel",
    "live_harness_realism": "make test-harness-realism",
    "live_agent_workflow_smoke": "make test-agent-workflow-smoke",
    "live_cli_agent_failures": "python3 scripts/test_cli_agent_failures.py --compact",
    "live_release_readiness": "python3 scripts/test_release_readiness.py --compact",
    "live_verify_agent_runtime": "make verify-agent-runtime",
}

LADDER: list[tuple[str, list[str], bool, bool]] = [
    ("offline_self_test", [sys.executable, "scripts/dietcode_agent_client.py", "--self-test", "--compact"], False, False),
    ("offline_contract_lockdown", [sys.executable, "scripts/test_contract_lockdown.py", "--compact"], False, False),
    ("offline_docs_code_drift", [sys.executable, "scripts/test_docs_code_drift.py", "--compact"], False, False),
    ("live_verify_agent_runtime", [sys.executable, "scripts/verify_agent_runtime.py", "--compact"], True, True),
    ("live_agent_workflow_smoke", [sys.executable, "scripts/test_agent_workflow_smoke.py", "--compact"], True, False),
    ("live_cli_agent_failures", [sys.executable, "scripts/test_cli_agent_failures.py", "--compact"], True, False),
    ("live_release_readiness", [sys.executable, "scripts/test_release_readiness.py", "--compact"], True, False),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run verify-agent-runtime-full ladder.")
    add_output_args(parser)
    parser.add_argument("--skip-live", action="store_true", help="Run offline steps only.")
    args = parser.parse_args()
    compact = output_compact(args)
    checks: list[dict] = []

    if not args.skip_live:
        prep = subprocess.run(["make", "restart-agent-server"], cwd=str(REPO_ROOT), capture_output=True, text=True)
        prep_ok = prep.returncode == 0
        payload = {
            "type": "check",
            "name": "prep.restart_agent_server",
            "ok": prep_ok,
            "detail": {"exitCode": prep.returncode, "nextCommand": "make restart-agent-server"},
        }
        checks.append(payload)
        emit_test_line(payload, compact=compact)
        if not prep_ok:
            return finish_test_run(checks, suite="verify_agent_runtime_full", compact=compact)

    for name, cmd, needs_live, skip_if_live_ran_kernel in LADDER:
        if args.skip_live and needs_live:
            continue
        completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True)
        ok = completed.returncode == 0
        detail: dict = {"exitCode": completed.returncode, "nextCommand": NEXT_COMMANDS.get(name, "make verify-agent-runtime-full")}
        if not ok:
            detail["stderrTail"] = completed.stderr.strip()[-400:]
            detail["stdoutTail"] = completed.stdout.strip()[-400:]
        payload = {"type": "check", "name": name, "ok": ok, "detail": detail}
        checks.append(payload)
        emit_test_line(payload, compact=compact)

    summary_ok = all(check.get("ok") for check in checks)
    failed = [check["name"] for check in checks if not check.get("ok")]
    if not summary_ok and failed:
        emit_test_line(
            {
                "type": "next_steps",
                "suite": "verify_agent_runtime_full",
                "failed": failed,
                "rerun": NEXT_COMMANDS.get(failed[0], "make verify-agent-runtime-full"),
            },
            compact=compact,
        )
    return finish_test_run(checks, suite="verify_agent_runtime_full", compact=compact)


if __name__ == "__main__":
    raise SystemExit(main())
