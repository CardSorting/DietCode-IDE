#!/usr/bin/env python3
"""Agent input boundary manifest — what the driver may expose to agents."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"

FORBIDDEN_AGENT_INPUTS = (
    "metadata.json",
    "expected.patch",
    "trapType",
    "MCS_REFERENCE",
    "priorTrace",
)


def build_agent_input_manifest(*, external: bool, profile: str) -> dict[str, bool]:
    """Document which benchmark artifacts reach the agent surface."""
    if external:
        return {
            "readme": True,
            "verifySh": True,
            "metadataJson": False,
            "expectedPatch": False,
            "priorTrace": False,
            "trapType": False,
            "mcsReference": False,
        }
    # Built-in driver: orchestrator still never passes metadata/patch into plan building.
    return {
        "readme": True,
        "verifySh": profile in ("orchestrated", "contract_full", "recovery_aware", "verify_exec"),
        "metadataJson": False,
        "expectedPatch": False,
        "priorTrace": False,
        "trapType": False,
        "mcsReference": False,
    }


def external_agent_cli_args(workspace: Path, task_id: str, mode: str, script: Path) -> list[str]:
    """Canonical argv for external agent scripts — jail surface."""
    return [
        os.environ.get("PYTHON", "python3"),
        str(script),
        "--workspace",
        str(workspace),
        "--task",
        task_id,
        "--mode",
        mode,
    ]


def assert_external_agent_jail(cmd: list[str], env: dict[str, str] | None = None) -> list[str]:
    """Return violations if external agent invocation leaks forbidden inputs."""
    violations: list[str] = []
    joined = " ".join(cmd)
    for forbidden in FORBIDDEN_AGENT_INPUTS:
        if forbidden in joined:
            violations.append(f"forbidden token in argv: {forbidden}")
    for arg in cmd:
        p = Path(arg)
        if p.name in ("metadata.json", "expected.patch"):
            violations.append(f"forbidden path in argv: {arg}")
    if env:
        for key, val in env.items():
            blob = f"{key}={val}"
            if "trapType" in blob or "MCS_REFERENCE" in blob:
                violations.append(f"forbidden env leak: {key}")
            if "expected.patch" in val or "metadata.json" in val:
                violations.append(f"forbidden path in env: {key}")
    return violations


def assert_task_tree_not_in_agent_env(task_id: str, env: dict[str, str]) -> list[str]:
    """Harness metadata paths must not appear in agent environment."""
    violations: list[str] = []
    task_dir = str(TASKS_DIR / task_id)
    for key, val in env.items():
        if task_dir in val and ("metadata.json" in val or "expected.patch" in val):
            violations.append(f"task metadata path in env[{key}]")
    return violations
