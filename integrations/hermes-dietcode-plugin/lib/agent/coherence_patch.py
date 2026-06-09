"""Coherence-aware patch helpers for Hermes ↔ bridge safe-file invocations."""
from __future__ import annotations

import os
from typing import Any


def parse_single_line_replacement(unified_diff: str) -> tuple[str, str] | None:
    """Extract one removed line and one added line from a unified diff."""
    removed: list[str] = []
    added: list[str] = []
    for line in unified_diff.splitlines():
        if line.startswith("---") or line.startswith("+++") or line.startswith("@@"):
            continue
        if line.startswith("-"):
            removed.append(line[1:])
        elif line.startswith("+"):
            added.append(line[1:])
    if len(removed) == 1 and len(added) == 1:
        return removed[0], added[0]
    return None


def coherence_patch_bridge_kwargs(
    unified_diff: str,
    *,
    line_search: str = "",
    line_replace: str = "",
    coherence_retry: bool | None = None,
    task_id: str = "",
) -> dict[str, Any]:
    """Build run_bridge kwargs for governed coherence auto-retry."""
    governed_task = (task_id or os.environ.get("DIETCODE_TASK_ID", "")).strip()
    enabled = coherence_retry if coherence_retry is not None else bool(governed_task)
    kwargs: dict[str, Any] = {}
    if governed_task:
        kwargs["task_id"] = governed_task
    if not enabled:
        return kwargs

    kwargs["coherence_retry"] = True
    search = line_search.strip()
    replace = line_replace.strip()
    if not search:
        parsed = parse_single_line_replacement(unified_diff)
        if parsed:
            search, replace = parsed
    if search:
        kwargs["line_search"] = search
    if replace:
        kwargs["line_replace"] = replace
    return kwargs
