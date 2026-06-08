#!/usr/bin/env python3
"""Workspace hashing and trace output security (Phase 4.1 — SLSA-style provenance)."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
RESULTS_DIR = BENCHMARK_ROOT / "results"
TRACES_DIR = RESULTS_DIR / "traces"
WORKSPACES_DIR = BENCHMARK_ROOT / ".workspaces"

_RUN_ID_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$")
_TASK_ID_RE = re.compile(r"^task_\d{3}$")


def volatile_skip(path: Path) -> bool:
    """Exclude approved volatile dirs from workspace integrity hashes."""
    parts = path.parts
    return ".agent_patches" in parts or "__pycache__" in parts or path.suffix == ".pyc"


def hash_workspace(workspace: Path) -> str:
    """Deterministic SHA-256 over sorted relative paths and file bytes."""
    digest = hashlib.sha256()
    if not workspace.is_dir():
        return digest.hexdigest()
    files = sorted(
        p for p in workspace.rglob("*") if p.is_file() and not volatile_skip(p)
    )
    for path in files:
        rel = path.relative_to(workspace).as_posix()
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def validate_run_id(run_id: str) -> None:
    if not _RUN_ID_RE.fullmatch(run_id):
        raise ValueError(f"invalid run_id (path traversal rejected): {run_id!r}")


def validate_task_id(task_id: str) -> None:
    if not _TASK_ID_RE.fullmatch(task_id):
        raise ValueError(f"invalid task_id: {task_id!r}")


def resolve_trace_path(run_id: str, task_id: str) -> Path:
    """Resolve trace path with traversal guards; traces live outside task workspaces."""
    validate_run_id(run_id)
    validate_task_id(task_id)
    out_dir = (TRACES_DIR / run_id).resolve()
    traces_root = TRACES_DIR.resolve()
    if traces_root not in out_dir.parents and out_dir != traces_root:
        raise ValueError(f"trace directory escapes traces root: {out_dir}")
    out = (out_dir / f"{task_id}.mutation_trace.json").resolve()
    if traces_root not in out.parents:
        raise ValueError(f"trace file escapes traces root: {out}")
    return out


def assert_trace_outside_workspace(trace_path: Path, workspace: Path) -> None:
    """Traces must not be written inside the per-task workspace copy."""
    ws = workspace.resolve()
    tp = trace_path.resolve()
    if ws == tp or ws in tp.parents:
        raise ValueError(f"trace path must not be inside workspace: {tp} ⊆ {ws}")


def assert_workspace_isolated(workspace: Path) -> None:
    """Per-task workspaces must live under .workspaces/, not under results/traces."""
    ws = workspace.resolve()
    workspaces_root = WORKSPACES_DIR.resolve()
    traces_root = TRACES_DIR.resolve()
    if workspaces_root not in ws.parents:
        raise ValueError(f"workspace outside isolation root: {ws}")
    if traces_root in ws.parents or ws == traces_root:
        raise ValueError(f"workspace must not live under traces: {ws}")
