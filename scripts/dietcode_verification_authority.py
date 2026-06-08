#!/usr/bin/env python3
"""Verification authority — executable verify after agent mutation."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import time
from pathlib import Path
from typing import Any

from dietcode_diff_authority import agent_chat_run_dir

DEFAULT_FALLBACK_VERIFY_COMMAND = os.environ.get("DIETCODE_AGENT_CHAT_FALLBACK_VERIFY", "").strip()
VERIFY_TIMEOUT_SEC = int(os.environ.get("DIETCODE_AGENT_CHAT_VERIFY_TIMEOUT", "300"))


def verification_json_path(run_id: str) -> Path:
    return agent_chat_run_dir(run_id) / "verification.json"


def verify_stdout_path(run_id: str) -> Path:
    return agent_chat_run_dir(run_id) / "verify.stdout.log"


def verify_stderr_path(run_id: str) -> Path:
    return agent_chat_run_dir(run_id) / "verify.stderr.log"


def empty_verification_authority() -> dict[str, Any]:
    return {
        "verifyCommand": None,
        "executed": False,
        "exitCode": None,
        "passed": False,
        "stdoutFile": None,
        "stderrFile": None,
        "checkedAfterMutation": False,
        "durationMs": 0,
    }


def _public_authority(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "verifyCommand": record.get("verifyCommand"),
        "executed": bool(record.get("executed")),
        "exitCode": record.get("exitCode"),
        "passed": bool(record.get("passed")),
        "stdoutFile": record.get("stdoutFile"),
        "stderrFile": record.get("stderrFile"),
        "checkedAfterMutation": bool(record.get("checkedAfterMutation")),
        "durationMs": int(record.get("durationMs") or 0),
    }


def resolve_verify_command(
    workspace: Path,
    *,
    override: str | None = None,
    fallback: str | None = None,
) -> str | None:
    if override and override.strip():
        return override.strip()
    verify_sh = workspace / "verify.sh"
    if verify_sh.is_file():
        if not os.access(verify_sh, os.X_OK):
            try:
                mode = verify_sh.stat().st_mode
                verify_sh.chmod(mode | stat.S_IXUSR)
            except OSError:
                pass
        return "./verify.sh"
    fb = (fallback if fallback is not None else DEFAULT_FALLBACK_VERIFY_COMMAND).strip()
    return fb or None


def verification_label(authority: dict[str, Any]) -> str:
    if not authority.get("executed"):
        return "Not Run"
    if authority.get("passed"):
        return "Passed"
    return "Failed"


def execute_verification_authority(
    workspace: Path,
    *,
    run_id: str,
    mutation_completed_at: float,
    verify_command: str | None,
) -> dict[str, Any]:
    run_dir = agent_chat_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = verify_stdout_path(run_id)
    stderr_path = verify_stderr_path(run_id)

    if not verify_command:
        record = {
            **empty_verification_authority(),
            "runId": run_id,
            "mutationCompletedAt": mutation_completed_at,
            "verificationStartedAt": None,
        }
        verification_json_path(run_id).write_text(json.dumps(record, indent=2), encoding="utf-8")
        return _public_authority(record)

    started_at = time.time()
    wall_start = time.monotonic()
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace.resolve())}
    try:
        completed = subprocess.run(
            verify_command,
            shell=True,
            cwd=str(workspace),
            capture_output=True,
            text=True,
            check=False,
            timeout=VERIFY_TIMEOUT_SEC,
            env=env,
        )
        exit_code = completed.returncode
        stdout = completed.stdout or ""
        stderr = completed.stderr or ""
    except subprocess.TimeoutExpired as exc:
        exit_code = 124
        stdout = (exc.stdout or "") if isinstance(exc.stdout, str) else ""
        stderr = ((exc.stderr or "") if isinstance(exc.stderr, str) else "") + "\nverification timed out"

    duration_ms = int((time.monotonic() - wall_start) * 1000)
    stdout_path.write_text(stdout, encoding="utf-8")
    stderr_path.write_text(stderr, encoding="utf-8")

    record = {
        "verifyCommand": verify_command,
        "executed": True,
        "exitCode": exit_code,
        "passed": exit_code == 0,
        "stdoutFile": str(stdout_path),
        "stderrFile": str(stderr_path),
        "checkedAfterMutation": started_at >= mutation_completed_at,
        "durationMs": duration_ms,
        "runId": run_id,
        "mutationCompletedAt": mutation_completed_at,
        "verificationStartedAt": started_at,
    }
    verification_json_path(run_id).write_text(json.dumps(record, indent=2), encoding="utf-8")
    return _public_authority(record)


def audit_verification_authority(
    run_id: str,
    authority: dict[str, Any],
    *,
    mutation_completed_at: float,
) -> dict[str, Any]:
    issues: list[str] = []
    run_dir = agent_chat_run_dir(run_id)
    json_path = verification_json_path(run_id)

    if not json_path.is_file():
        issues.append("missing_verification_json")
    else:
        try:
            stored = json.loads(json_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            issues.append("invalid_verification_json")
            stored = {}
        if stored.get("runId") != run_id:
            issues.append("run_id_mismatch")
        started = stored.get("verificationStartedAt")
        mut_at = stored.get("mutationCompletedAt", mutation_completed_at)
        if authority.get("executed") and started is not None and started < mut_at:
            issues.append("verification_before_mutation")
        if authority.get("executed"):
            exit_code = authority.get("exitCode")
            passed = authority.get("passed")
            if passed is not None and exit_code is not None and bool(passed) != (exit_code == 0):
                issues.append("exit_code_passed_inconsistent")

    if authority.get("executed"):
        stdout_file = authority.get("stdoutFile")
        stderr_file = authority.get("stderrFile")
        if not stdout_file or not Path(str(stdout_file)).is_file():
            issues.append("missing_stdout_log")
        if not stderr_file or not Path(str(stderr_file)).is_file():
            issues.append("missing_stderr_log")
        for label, rel in (("stdout", "verify.stdout.log"), ("stderr", "verify.stderr.log")):
            candidate = run_dir / rel
            if authority.get("executed") and not candidate.is_file():
                if f"missing_{label}_log" not in issues:
                    issues.append(f"missing_{label}_log")

    return {"ok": not issues, "issues": issues, "runId": run_id}


def verification_failure_message(authority: dict[str, Any]) -> str:
    if not authority.get("executed"):
        return (
            "Verification authority failure:\n"
            "verification did not run after mutation.\n"
            "Add verify.sh to the workspace or pass --verify-command."
        )
    lines = [
        "Verification authority failure:",
        f"verify command exited nonzero after mutation (exit {authority.get('exitCode')}).",
        "See:",
    ]
    if authority.get("stdoutFile"):
        lines.append(f"  stdout: {authority['stdoutFile']}")
    if authority.get("stderrFile"):
        lines.append(f"  stderr: {authority['stderrFile']}")
    return "\n".join(lines)
