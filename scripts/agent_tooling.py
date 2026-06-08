#!/usr/bin/env python3
"""
TOOLING: Literal grep/diff helpers for agent ergonomics — no semantic search or fuzzy matching.

Grep: rg 'TOOLING:|literal_match_spans|parse_unified_diff' scripts/agent_tooling.py docs/
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = REPO_ROOT / "scripts/fixtures/tooling"

HUNK_HEADER_RE = re.compile(r"^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@")


def stable_hash_for_string(text: str) -> str:
    """Mirror MacControlSerialization StableHashForString (FNV-1a 64-bit, 16 hex chars)."""
    data = text.encode("utf-8")
    hash_val = 1469598103934665603
    for byte in data:
        hash_val ^= byte
        hash_val = (hash_val * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return f"{hash_val:016x}"


def literal_match_spans(line: str, query: str, *, case_sensitive: bool = False) -> list[dict[str, Any]]:
    """Mirror LiteralMatchSpans in MacControlSupport.mm — literal substring only."""
    if not query:
        return []
    haystack = line if case_sensitive else line.lower()
    needle = query if case_sensitive else query.lower()
    spans: list[dict[str, Any]] = []
    pos = 0
    while True:
        found = haystack.find(needle, pos)
        if found < 0:
            break
        column_start = found + 1
        column_end = found + len(needle)
        spans.append({
            "columnStart": column_start,
            "columnEnd": column_end,
            "text": line[found : found + len(needle)],
        })
        pos = found + max(len(needle), 1)
    return spans


def context_lines(lines: list[str], start: int, end: int) -> list[str]:
    """Mirror ContextLines — inclusive 0-based indices, clamped."""
    if not lines:
        return []
    lo = max(0, start)
    hi = min(len(lines) - 1, end)
    if hi < lo:
        return []
    return lines[lo : hi + 1]


def clean_unified_diff_path(raw_path: str) -> str:
    path = (raw_path or "").strip()
    tab = path.find("\t")
    if tab >= 0:
        path = path[:tab]
    if len(path) >= 2 and path.startswith('"') and path.endswith('"'):
        path = path[1:-1]
    if path == "/dev/null":
        return path
    if path.startswith("a/") or path.startswith("b/"):
        return path[2:]
    return path


def parse_unified_diff_hunks(
    diff_text: str,
    *,
    max_hunks: int = 500,
    hunk_offset: int = 0,
    include_lines: bool = False,
    max_lines_per_hunk: int = 200,
) -> dict[str, Any]:
    """Offline mirror of UnifiedDiffHunksResponse in MacControlDiffParsing.mm."""
    limit = min(max_hunks, 5000) if max_hunks > 0 else 500
    offset = max(hunk_offset, 0)
    line_limit = min(max_lines_per_hunk, 1000) if max_lines_per_hunk > 0 else 200

    lines = diff_text.split("\n")
    if diff_text and diff_text.endswith("\n") and lines:
        lines = lines[:-1]

    files: list[dict[str, Any]] = []
    current_file: dict[str, Any] | None = None
    current_hunks: list[dict[str, Any]] = []
    current_hunk: dict[str, Any] | None = None
    current_line_rows: list[dict[str, Any]] | None = None
    added = removed = context = 0
    old_line_cursor = new_line_cursor = 0
    current_hunk_total_line_rows = 0
    current_hunk_returned_line_rows = 0
    current_hunk_lines_truncated = False
    collect_current_lines = False

    total_files = total_hunks = returned_hunks = 0
    total_added = total_removed = 0
    truncated = False
    current_file_total_hunks = 0
    current_file_omitted_before = 0
    current_file_omitted_after = 0
    current_file_added = 0
    current_file_removed = 0

    def ensure_file(line_number: int) -> None:
        nonlocal current_file, current_hunks
        if current_file is not None:
            return
        current_hunks = []
        current_file = {
            "oldPath": "",
            "newPath": "",
            "fileHeader": "",
            "lineStart": line_number,
        }

    def finish_hunk() -> None:
        nonlocal current_hunk, current_line_rows, added, removed, context
        nonlocal old_line_cursor, new_line_cursor
        nonlocal current_hunk_total_line_rows, current_hunk_returned_line_rows
        nonlocal current_hunk_lines_truncated, collect_current_lines
        nonlocal total_hunks, returned_hunks, truncated
        nonlocal total_added, total_removed
        nonlocal current_file_total_hunks, current_file_omitted_before, current_file_omitted_after
        nonlocal current_file_added, current_file_removed
        if current_hunk is None:
            return
        current_hunk["addedLines"] = added
        current_hunk["removedLines"] = removed
        current_hunk["contextLines"] = context
        if include_lines:
            current_hunk["lines"] = current_line_rows or []
            current_hunk["totalLineRows"] = current_hunk_total_line_rows
            current_hunk["returnedLineRows"] = current_hunk_returned_line_rows
            current_hunk["linesTruncated"] = current_hunk_lines_truncated
        hunk_index = total_hunks
        current_hunk["hunkIndex"] = hunk_index
        current_hunk["hunkOrdinal"] = hunk_index + 1
        total_hunks += 1
        current_file_total_hunks += 1
        total_added += added
        total_removed += removed
        current_file_added += added
        current_file_removed += removed
        if hunk_index < offset:
            current_file_omitted_before += 1
        elif returned_hunks < limit:
            current_hunks.append(current_hunk)
            returned_hunks += 1
        else:
            truncated = True
            current_file_omitted_after += 1
        current_hunk = None
        current_line_rows = None
        added = removed = context = 0
        old_line_cursor = new_line_cursor = 0
        current_hunk_total_line_rows = 0
        current_hunk_returned_line_rows = 0
        current_hunk_lines_truncated = False
        collect_current_lines = False

    def finish_file() -> None:
        nonlocal current_file, current_hunks, total_files
        nonlocal current_file_total_hunks, current_file_omitted_before, current_file_omitted_after
        nonlocal current_file_added, current_file_removed
        if current_file is None:
            return
        finish_hunk()
        has_file_evidence = (
            current_file_total_hunks > 0
            or bool(current_file.get("fileHeader"))
            or bool(current_file.get("oldPath"))
            or bool(current_file.get("newPath"))
        )
        if has_file_evidence:
            total_files += 1
        has_metadata_only = current_file_total_hunks == 0 and has_file_evidence
        if current_hunks or has_metadata_only:
            current_file["hunks"] = current_hunks
            current_file["returnedHunks"] = len(current_hunks)
            current_file["totalHunks"] = current_file_total_hunks
            current_file["omittedBefore"] = current_file_omitted_before
            current_file["omittedAfter"] = current_file_omitted_after
            current_file["addedLines"] = current_file_added
            current_file["removedLines"] = current_file_removed
            current_file["truncated"] = current_file_omitted_after > 0
            files.append(current_file)
        current_file = None
        current_hunks = []
        current_file_total_hunks = 0
        current_file_omitted_before = 0
        current_file_omitted_after = 0
        current_file_added = 0
        current_file_removed = 0

    for index, line in enumerate(lines):
        line_number = index + 1
        if line.startswith("diff --git "):
            finish_file()
            ensure_file(line_number)
            current_file["fileHeader"] = line
            parts = line.split()
            if len(parts) >= 4:
                current_file["oldPath"] = clean_unified_diff_path(parts[2])
                current_file["newPath"] = clean_unified_diff_path(parts[3])
            continue
        if line.startswith("--- "):
            ensure_file(line_number)
            current_file["oldPath"] = clean_unified_diff_path(line[4:])
            current_file["oldHeaderLine"] = line_number
            continue
        if line.startswith("+++ "):
            ensure_file(line_number)
            current_file["newPath"] = clean_unified_diff_path(line[4:])
            current_file["newHeaderLine"] = line_number
            continue

        match = HUNK_HEADER_RE.match(line)
        if match:
            ensure_file(line_number)
            finish_hunk()
            old_start = int(match.group(1))
            old_count = int(match.group(2) or "1")
            new_start = int(match.group(3))
            new_count = int(match.group(4) or "1")
            current_hunk = {
                "header": line,
                "lineStart": line_number,
                "lineEnd": line_number,
                "oldStart": old_start,
                "oldLines": old_count,
                "newStart": new_start,
                "newLines": new_count,
            }
            old_line_cursor = old_start
            new_line_cursor = new_start
            candidate_hunk_index = total_hunks
            collect_current_lines = include_lines and offset <= candidate_hunk_index < offset + limit
            current_line_rows = [] if collect_current_lines else None
            current_hunk_total_line_rows = 0
            current_hunk_returned_line_rows = 0
            current_hunk_lines_truncated = False
            continue

        if current_hunk is not None:
            current_hunk["lineEnd"] = line_number
            kind = "meta"
            old_line_value: Any = None
            new_line_value: Any = None
            text = line
            if line.startswith("+") and not line.startswith("+++"):
                kind = "add"
                new_line_value = new_line_cursor
                text = line[1:]
                added += 1
                new_line_cursor += 1
            elif line.startswith("-") and not line.startswith("---"):
                kind = "remove"
                old_line_value = old_line_cursor
                text = line[1:]
                removed += 1
                old_line_cursor += 1
            elif line.startswith(" "):
                kind = "context"
                old_line_value = old_line_cursor
                new_line_value = new_line_cursor
                text = line[1:]
                context += 1
                old_line_cursor += 1
                new_line_cursor += 1
            elif line.startswith("\\"):
                kind = "meta"
            if include_lines and collect_current_lines:
                current_hunk_total_line_rows += 1
                if current_hunk_returned_line_rows < line_limit:
                    current_line_rows.append({
                        "diffLine": line_number,
                        "kind": kind,
                        "oldLine": old_line_value,
                        "newLine": new_line_value,
                        "raw": line,
                        "text": text,
                    })
                    current_hunk_returned_line_rows += 1
                else:
                    current_hunk_lines_truncated = True

    finish_file()
    has_more_hunks = offset + returned_hunks < total_hunks
    return {
        "files": files,
        "totalFiles": total_files,
        "totalHunks": total_hunks,
        "returnedHunks": returned_hunks,
        "totalAddedLines": total_added,
        "totalRemovedLines": total_removed,
        "maxHunks": limit,
        "hunkOffset": offset,
        "nextHunkOffset": offset + returned_hunks if has_more_hunks else None,
        "hasMoreHunks": has_more_hunks,
        "includeLines": include_lines,
        "maxLinesPerHunk": line_limit,
        "truncated": truncated,
    }


def format_grep_matches_rg(matches: list[dict[str, Any]]) -> str:
    """ripgrep-style path:line:column:preview lines (one match per line)."""
    rows: list[str] = []
    for match in matches:
        path = match.get("path", "")
        line_no = match.get("line", 0)
        column = match.get("column", 1)
        preview = str(match.get("preview", "")).replace("\n", "\\n")
        rows.append(f"{path}:{line_no}:{column}:{preview}")
    return "\n".join(rows)


def format_diff_hunk_summary(payload: dict[str, Any]) -> dict[str, Any]:
    """Compact agent-facing diff summary from diff.hunks result."""
    file_summaries: list[dict[str, Any]] = []
    for entry in payload.get("files", []):
        if not isinstance(entry, dict):
            continue
        path = entry.get("newPath") or entry.get("oldPath") or ""
        file_summaries.append({
            "path": path,
            "totalHunks": entry.get("totalHunks", 0),
            "returnedHunks": entry.get("returnedHunks", 0),
            "addedLines": entry.get("addedLines", 0),
            "removedLines": entry.get("removedLines", 0),
            "truncated": bool(entry.get("truncated")),
        })
    return {
        "type": "diff_summary",
        "mode": payload.get("mode", "literal_unified_diff_hunks"),
        "source": payload.get("source"),
        "path": payload.get("path") or None,
        "totalFiles": payload.get("totalFiles", 0),
        "totalHunks": payload.get("totalHunks", 0),
        "returnedHunks": payload.get("returnedHunks", 0),
        "totalAddedLines": payload.get("totalAddedLines", 0),
        "totalRemovedLines": payload.get("totalRemovedLines", 0),
        "hasMoreHunks": payload.get("hasMoreHunks", False),
        "nextHunkOffset": payload.get("nextHunkOffset"),
        "truncated": payload.get("truncated", False),
        "files": file_summaries,
    }


def partial_success_hint(result: dict[str, Any]) -> str | None:
    """Deterministic stderr hint when ok:true but result is partial or truncated."""
    if not isinstance(result, dict):
        return None
    if result.get("partial") is not True and result.get("truncated") is not True:
        return None
    parts: list[str] = []
    if result.get("partial") is True:
        parts.append("partial=true")
    if result.get("truncated") is True:
        parts.append("truncated=true")
    warnings = result.get("warnings")
    if isinstance(warnings, list) and warnings:
        parts.append(f"warnings={warnings}")
    if result.get("fallbackUsed") is True:
        parts.append("fallbackUsed=true")
    if result.get("nextRecommendedCommand"):
        parts.append(f"nextRecommendedCommand={result['nextRecommendedCommand']}")
    if result.get("recoveryHint"):
        parts.append(f"recoveryHint={result['recoveryHint']}")
    if result.get("nextResultOffset") is not None:
        parts.append(f"nextResultOffset={result['nextResultOffset']}")
    return "; ".join(parts) if parts else None


def grep_empty_result_hint(result: dict[str, Any]) -> str | None:
    """Deterministic guidance when workspace.grep returns zero matches."""
    matches = result.get("matches")
    if isinstance(matches, list) and matches:
        return None
    scanned = result.get("scannedFiles", 0)
    files_read = result.get("filesRead", 0)
    skipped = result.get("filesSkippedUnreadable", 0)
    binary = result.get("filesSkippedBinary", 0)
    oversize = result.get("filesSkippedOversize", 0)
    excluded = result.get("filesSkippedExcluded", 0)
    parts = [
        f"query={result.get('query')!r}",
        f"scannedFiles={scanned}",
        f"filesRead={files_read}",
        f"sortOrder={result.get('sortOrder', 'unknown')}",
    ]
    if skipped:
        parts.append(f"filesSkippedUnreadable={skipped}")
    if binary:
        parts.append(f"filesSkippedBinary={binary}")
    if oversize:
        parts.append(f"filesSkippedOversize={oversize}")
    if excluded:
        parts.append(f"filesSkippedExcluded={excluded}")
    if files_read == 0 and scanned > 0:
        parts.append("hint=no readable files; verify workspace root and include/exclude globs")
    elif scanned == 0:
        parts.append("hint=workspace empty or filters excluded all files")
    else:
        parts.append("hint=literal substring not present in scanned readable files")
    return "; ".join(parts)


def format_patch_validation_summary(validation: dict[str, Any], *, path: str | None = None) -> dict[str, Any]:
    """Compact agent-facing patch.validate summary."""
    return {
        "type": "patch_validation_summary",
        "path": path,
        "ok": validation.get("ok"),
        "patchAppliesCleanly": validation.get("patchAppliesCleanly"),
        "syntaxDanger": validation.get("syntaxDanger"),
        "requiresConfirmation": validation.get("requiresConfirmation"),
        "changedLineCount": validation.get("changedLineCount"),
        "rejectedReason": validation.get("rejectedReason") or None,
        "targetFileExists": validation.get("targetFileExists"),
        "insideWorkspace": validation.get("insideWorkspace"),
    }


def read_text_file_literal(path: Path) -> str | None:
    """Offline disk read mirror used by search services (UTF-8, rejects NUL bytes)."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    if "\0" in text:
        return None
    return text


def rg_workspace(
    pattern: str,
    *,
    cwd: Path | None = None,
    paths: list[str] | None = None,
    max_lines: int = 200,
) -> dict[str, Any]:
    """Run ripgrep with stable NDJSON-friendly output (offline workspace audit)."""
    root = cwd or REPO_ROOT
    cmd = ["rg", "--line-number", "--column", "--no-heading", "--max-count", str(max_lines), pattern]
    if paths:
        cmd.extend(paths)
    else:
        cmd.extend(["src/", "scripts/", "docs/"])
    completed = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True, check=False)
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    return {
        "pattern": pattern,
        "exitCode": completed.returncode,
        "matchLines": lines,
        "matchCount": len(lines),
        "stderr": completed.stderr.strip(),
    }
