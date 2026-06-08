#!/usr/bin/env python3
"""
SHELL: Pass IX — offline helpers for agent shell wrapper contracts.

Grep: rg 'SHELL:|agent_shell_tooling' scripts/ docs/agent-shell-tooling.md
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = REPO_ROOT / "scripts" / "fixtures" / "shell"


def shell_recovery_hint_for_large_file(*, partial: bool, truncated: bool) -> str:
    if partial or truncated:
        return "use_shell_head_tail_or_sedRange"
    return ""


def format_shell_rg_match_line(match: dict[str, Any]) -> str:
    """ripgrep-style path:line:column:preview."""
    path = match.get("path", "")
    line_no = match.get("line", 0)
    column = match.get("column", 1)
    preview = str(match.get("preview", "")).replace("\n", "\\n")
    return f"{path}:{line_no}:{column}:{preview}"


def sed_range_command(path: str, start: int, end: int) -> str:
    return f"sed -n '{start},{end}p' {path}"


def is_destructive_shell_command(command: str) -> bool:
    """Reject mutation-style sed/shell forms in agent workflows."""
    lowered = command.strip().lower()
    if "sed -i" in lowered:
        return True
    if "|" in command or ";" in command or "&&" in command or "||" in command:
        return True
    if lowered.startswith("rm ") or lowered.startswith("sudo "):
        return True
    return False
