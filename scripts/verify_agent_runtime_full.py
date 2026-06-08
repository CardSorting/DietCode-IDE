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
    "live_partial_success_closure": "make test-partial-success-closure",
    "live_broccoliq_runtime_memory": "make test-broccoliq-runtime-memory",
    "live_runtime_native_integration": "make test-runtime-native-integration",
    "live_verify_agent_runtime": "make verify-agent-runtime",
}

LADDER: list[tuple[str, list[str], bool, bool]] = [
    ("offline_self_test", [sys.executable, "scripts/dietcode_agent_client.py", "--self-test", "--compact"], False, False),
    ("offline_contract_lockdown", [sys.executable, "scripts/test_contract_lockdown.py", "--compact"], False, False),
    ("offline_docs_code_drift", [sys.executable, "scripts/test_docs_code_drift.py", "--compact"], False, False),
    ("live_verify_agent_runtime", [sys.executable, "scripts/verify_agent_runtime.py", "--compact"], True, True),
    ("live_agent_workflow_smoke", [sys.executable, "scripts/test_agent_workflow_smoke.py", "--compact"], True, False),
    ("live_cli_agent_failures", [sys.executable, "scripts/test_cli_agent_failures.py", "--compact"], True, False),
    ("live_partial_success_closure", [sys.executable, "scripts/test_partial_success_closure.py", "--compact"], True, False),
    ("live_broccoliq_runtime_memory", [sys.executable, "scripts/test_broccoliq_runtime_memory.py", "--compact"], True, False),
    ("live_runtime_native_integration", [sys.executable, "scripts/test_runtime_native_integration.py", "--compact"], True, False),
    ("live_release_readiness", [sys.executable, "scripts/test_release_readiness.py", "--compact"], True, False),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run verify-agent-runtime-full ladder.")
    add_output_args(parser)
    parser.add_argument("--skip-live", action="store_true", help="Run offline steps only.")
    parser.add_argument(
        "--assume-server-ready",
        action="store_true",
        help="Skip rebuild/restart prep; assume agent server and binary already match HEAD.",
    )
    args = parser.parse_args()
    compact = output_compact(args)
    checks: list[dict] = []

    if not args.skip_live and not args.assume_server_ready:
        emit_test_line(
            {"type": "progress", "step": "prep.restart_agent_server", "status": "running", "note": "rebuild+restart (~60s)"},
            compact=compact,
        )
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
        emit_test_line(
            {"type": "progress", "step": "prep.restart_agent_server", "status": "done"},
            compact=compact,
        )
        ready = subprocess.run(
            [sys.executable, "scripts/dietcode_agent_client.py", "--wait-ready", "--compact", "--error-json", "--quiet"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        ready_ok = ready.returncode == 0
        ready_payload = {
            "type": "check",
            "name": "prep.wait_ready",
            "ok": ready_ok,
            "detail": {"exitCode": ready.returncode, "nextCommand": "make restart-agent-server"},
        }
        checks.append(ready_payload)
        emit_test_line(ready_payload, compact=compact)
        if not ready_ok:
            return finish_test_run(checks, suite="verify_agent_runtime_full", compact=compact)
    elif not args.skip_live and args.assume_server_ready:
        emit_test_line(
            {"type": "progress", "step": "prep.assume_server_ready", "status": "skipped", "note": "no rebuild/restart"},
            compact=compact,
        )

    for name, cmd, needs_live, skip_if_live_ran_kernel in LADDER:
        if args.skip_live and needs_live:
            continue
        if name == "live_verify_agent_runtime" and not args.skip_live:
            cmd = cmd + ["--assume-server-ready"]
        emit_test_line({"type": "progress", "step": name, "status": "running"}, compact=compact)
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
