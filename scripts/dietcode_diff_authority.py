#!/usr/bin/env python3
"""Diff authority — unified diff after agent runs vs mutation authority."""

from __future__ import annotations

import difflib
import uuid
from pathlib import Path
from typing import Any

from dietcode_mutation_authority import workspace_manifest


def agent_chat_run_id() -> str:
    return uuid.uuid4().hex[:16]


def agent_chat_run_dir(run_id: str) -> Path:
    return Path.home() / ".dietcode" / "agent-chat" / "runs" / run_id


def diff_file_path(run_id: str) -> Path:
    return agent_chat_run_dir(run_id) / "diff.patch"


def snapshot_text_files(workspace: Path) -> dict[str, str]:
    """Text snapshot for auditable workspace files (same scope as mutation manifest)."""
    root = workspace.resolve()
    contents: dict[str, str] = {}
    for rel in workspace_manifest(workspace):
        path = root / rel
        try:
            data = path.read_bytes()
            if b"\0" in data[:8192]:
                continue
            contents[rel] = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
    return contents


def build_unified_diff(
    before: dict[str, str],
    after: dict[str, str],
    *,
    changed_paths: list[str] | None = None,
) -> tuple[str, list[str]]:
    paths = changed_paths
    if paths is None:
        paths = sorted({*before, *after})
        paths = [p for p in paths if before.get(p) != after.get(p)]
    chunks: list[str] = []
    for rel in sorted(paths):
        b_lines = before.get(rel, "").splitlines(keepends=True)
        a_lines = after.get(rel, "").splitlines(keepends=True)
        if b_lines == a_lines:
            continue
        chunks.extend(
            difflib.unified_diff(
                b_lines,
                a_lines,
                fromfile=f"a/{rel}",
                tofile=f"b/{rel}",
            )
        )
    changed = [p for p in sorted(paths) if before.get(p) != after.get(p)]
    return "".join(chunks), changed


def parse_diff_changed_files(diff_text: str) -> list[str]:
    changed: list[str] = []
    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            path = line[4:].strip()
            if path.startswith("b/"):
                path = path[2:]
            if path != "/dev/null" and path not in changed:
                changed.append(path)
    return changed


def empty_diff_authority() -> dict[str, Any]:
    return {
        "diffFile": None,
        "changedFiles": [],
        "matchesMutationAuthority": True,
    }


def audit_diff_authority(
    workspace: Path,
    *,
    run_id: str,
    before_contents: dict[str, str],
    mutation_authority: dict[str, Any],
) -> dict[str, Any]:
    after_contents = snapshot_text_files(workspace)
    diff_text, changed = build_unified_diff(before_contents, after_contents)
    run_dir = agent_chat_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    diff_path = diff_file_path(run_id)
    diff_path.write_text(diff_text, encoding="utf-8")

    mutated = set(mutation_authority.get("mutatedFiles") or [])
    diff_changed = set(changed) if changed else set(parse_diff_changed_files(diff_text))

    return {
        "diffFile": str(diff_path),
        "changedFiles": sorted(diff_changed),
        "matchesMutationAuthority": mutated == diff_changed,
    }
