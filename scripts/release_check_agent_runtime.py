#!/usr/bin/env python3
"""
RELEASE: Release-grade agent runtime verification ladder.

Grep: rg 'release-check-agent-runtime|release_check_agent_runtime' scripts/ Makefile docs/
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from agent_test_support import add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, emit_test_line, finish_test_run
from release_versions import load_surface_classification

# Ordered ladder: offline gates first, then live-server contracts, then release rollup.
LADDER: list[tuple[str, list[str], bool]] = [
    ("offline_self_test", [sys.executable, "scripts/dietcode_agent_client.py", "--self-test", "--compact"], False),
    ("offline_contract_lockdown", [sys.executable, "scripts/test_contract_lockdown.py", "--compact"], False),
    ("offline_release_readiness", [sys.executable, "scripts/test_release_readiness.py", "--compact", "--offline-only"], False),
    ("live_release_readiness", [sys.executable, "scripts/test_release_readiness.py", "--compact"], True),
    ("live_control_smoke", [sys.executable, "scripts/control_smoke_test.py", "--compact"], True),
    ("live_task_health", [sys.executable, "scripts/test_task_server_health.py", "--compact"], True),
    ("live_rpc_transaction", [sys.executable, "scripts/test_rpc_transaction_health.py", "--compact"], True),
    ("live_runtime_safety", [sys.executable, "scripts/test_runtime_safety.py", "--compact"], True),
    ("live_grep_diff_tooling", [sys.executable, "scripts/test_grep_diff_tooling.py", "--compact"], True),
    ("live_runtime_determinism", [sys.executable, "scripts/test_runtime_determinism.py", "--compact"], True),
    ("live_transaction_kernel", [sys.executable, "scripts/test_transaction_kernel.py", "--compact"], True),
    ("live_harness_realism", [sys.executable, "scripts/test_harness_realism.py", "--compact"], True),
    ("live_operator_diagnostics", [sys.executable, "scripts/test_operator_diagnostics.py", "--compact"], True),
    ("live_ergonomics", [sys.executable, "scripts/test_ergonomics.py", "--compact"], True),
    ("live_agent_integration", [sys.executable, "scripts/run_agent_integration_tests.py", "--compact"], True),
]


def _validate_stable_fixtures() -> tuple[bool, dict]:
    data = load_surface_classification()
    missing = [rel for rel in data["fixtures"]["stable"] if not (REPO_ROOT / rel).is_file()]
    return not missing, {"missing": missing}


def _docs_command_sanity() -> tuple[bool, dict]:
    required_snippets = [
        ("docs/release-upgrade-rollback.md", "make release-check-agent-runtime"),
        ("docs/maintainer-guide.md", "rg "),
        ("docs/deprecation-policy.md", "deprecated"),
        ("docs/runtime-contracts.md", "contractInventory"),
    ]
    errors: list[str] = []
    for rel, needle in required_snippets:
        path = REPO_ROOT / rel
        if not path.is_file():
            errors.append(f"missing {rel}")
            continue
        if needle not in path.read_text(encoding="utf-8"):
            errors.append(f"{rel} missing snippet: {needle}")
    return not errors, {"errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser(description="Run release-check-agent-runtime ladder.")
    add_output_args(parser)
    parser.add_argument("--skip-live", action="store_true", help="Run offline steps only.")
    args = parser.parse_args()
    compact = output_compact(args)
    checks: list[dict] = []

    if not args.skip_live:
        prep = subprocess.run(["make", "app"], cwd=str(REPO_ROOT), capture_output=True, text=True)
        if prep.returncode != 0:
            payload = {"type": "check", "name": "prep.make_app", "ok": False, "detail": {"exitCode": prep.returncode}}
            checks.append(payload)
            emit_test_line(payload, compact=compact)
            return finish_test_run(checks, suite="release_check_agent_runtime", compact=compact)
        ready = subprocess.run(
            [sys.executable, "scripts/dietcode_agent_client.py", "--wait-ready", "--compact", "--error-json", "--quiet"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        payload = {"type": "check", "name": "prep.wait_ready", "ok": ready.returncode == 0, "detail": {"exitCode": ready.returncode}}
        checks.append(payload)
        emit_test_line(payload, compact=compact)
        if ready.returncode != 0:
            return finish_test_run(checks, suite="release_check_agent_runtime", compact=compact)

    fixtures_ok, fixtures_detail = _validate_stable_fixtures()
    payload = {"type": "check", "name": "offline_fixture_validation", "ok": fixtures_ok, "detail": fixtures_detail}
    checks.append(payload)
    emit_test_line(payload, compact=compact)

    docs_ok, docs_detail = _docs_command_sanity()
    payload = {"type": "check", "name": "offline_docs_command_sanity", "ok": docs_ok, "detail": docs_detail}
    checks.append(payload)
    emit_test_line(payload, compact=compact)

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

    return finish_test_run(checks, suite="release_check_agent_runtime", compact=compact)


if __name__ == "__main__":
    raise SystemExit(main())
