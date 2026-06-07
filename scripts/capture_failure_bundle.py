#!/usr/bin/env python3
"""
CONTRACT: Minimal local failure bundle — no zip, upload, or telemetry.

Grep: rg 'capture_failure_bundle|failure_bundle' scripts/ docs/
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

from agent_test_support import add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, json_text
from runtime_safety import redact_failure_bundle

CONTRACT_IDS = [
    "C-RPC-01",
    "C-RPC-03",
    "C-CONN-01",
    "C-HARNESS-01",
]


def _run_command(command: list[str], cwd: Path) -> dict:
    started = time.monotonic()
    completed = subprocess.run(command, cwd=str(cwd), capture_output=True, text=True, check=False)
    duration_ms = round((time.monotonic() - started) * 1000.0, 2)
    return {
        "command": command,
        "exitCode": completed.returncode,
        "durationMs": duration_ms,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def _rg(pattern: str, cwd: Path) -> str:
    completed = subprocess.run(
        ["rg", pattern, "src/", "scripts/", "docs/"],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.stdout.strip()


def _git_diff(paths: list[str], cwd: Path) -> str:
    completed = subprocess.run(
        ["git", "diff", "--", *paths],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        check=False,
    )
    return completed.stdout


def build_bundle(command: list[str], *, cwd: Path, compact: bool) -> dict:
    run = _run_command(command, cwd)
    summary_line = None
    for line in reversed(run["stdout"].splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if payload.get("type") == "summary":
            summary_line = payload
            break

    bundle = {
        "type": "failure_bundle",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "command": command,
        "exitCode": run["exitCode"],
        "durationMs": run["durationMs"],
        "stdout": run["stdout"],
        "stderr": run["stderr"],
        "summary": summary_line,
        "contractIds": CONTRACT_IDS,
        "gitDiff": _git_diff(["src/platform/macos/control", "scripts/", "docs/", "Makefile"], cwd),
        "rg": {
            "request_id": _rg("request_id", cwd),
            "runtime_diagnostic": _rg("runtime_diagnostic", cwd),
            "recovery_hint": _rg("recovery_hint", cwd),
        },
        "recoveryCommands": [
            "python3 scripts/dietcode_agent_client.py --diagnose --json",
            "make verify-agent-runtime",
            "rg 'request_id|runtime_diagnostic' ~/.dietcode/agent-runtime.ndjson docs/ src/",
        ],
    }
    return redact_failure_bundle(bundle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture a minimal local failure bundle as NDJSON.")
    add_output_args(parser)
    parser.add_argument("command", nargs=argparse.REMAINDER, help="Command to run (prefix with --).")
    args = parser.parse_args()
    compact = output_compact(args)
    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("usage: capture_failure_bundle.py -- <command...>", file=sys.stderr)
        return 2

    bundle = build_bundle(command, cwd=REPO_ROOT, compact=compact)
    print(json_text(bundle, compact=compact))
    return bundle["exitCode"] if isinstance(bundle["exitCode"], int) else 1


if __name__ == "__main__":
    raise SystemExit(main())
