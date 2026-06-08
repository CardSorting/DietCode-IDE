#!/usr/bin/env python3
"""
TOOLING: Grep/diff contract regression — literal matching, hunk parsing, live RPC shape.

Grep: rg 'test_grep_diff_tooling|grep_diff_tooling' scripts/ docs/ Makefile
"""

from __future__ import annotations

import argparse
import socket
from collections.abc import Callable

import json

from agent_contracts import validate_diff_hunks_response, validate_grep_response, validate_patch_validation
from agent_test_support import CheckRecorder, add_output_args, output_compact
from agent_tooling import (
    FIXTURES_DIR,
    REPO_ROOT,
    format_diff_hunk_summary,
    format_grep_matches_rg,
    format_patch_validation_summary,
    grep_empty_result_hint,
    literal_match_spans,
    parse_unified_diff_hunks,
    read_text_file_literal,
    rg_workspace,
    stable_hash_for_string,
)
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc


def test_literal_match_spans_case_insensitive() -> None:
    spans = literal_match_spans("Hello TODO world TODO", "todo")
    assert len(spans) == 2
    assert spans[0]["columnStart"] == 7
    assert spans[1]["columnStart"] == 18


def test_literal_match_spans_non_overlapping() -> None:
    spans = literal_match_spans("aaa", "aa")
    assert len(spans) == 1
    assert spans[0]["columnStart"] == 1


def test_stable_hash_known() -> None:
    digest = stable_hash_for_string("alpha")
    assert len(digest) == 16
    assert digest == stable_hash_for_string("alpha")


def test_parse_fixture_diff_hunks() -> None:
    diff_text = (FIXTURES_DIR / "sample_unified_diff.txt").read_text(encoding="utf-8")
    parsed = parse_unified_diff_hunks(diff_text, include_lines=True, max_lines_per_hunk=50)
    assert parsed["totalFiles"] == 1
    assert parsed["totalHunks"] == 1
    assert parsed["totalAddedLines"] == 2
    assert parsed["totalRemovedLines"] == 1
    file_entry = parsed["files"][0]
    assert file_entry["newPath"] == "scripts/example.py"
    hunk = file_entry["hunks"][0]
    assert hunk["oldStart"] == 1
    assert hunk["newStart"] == 1
    kinds = [row["kind"] for row in hunk.get("lines", [])]
    assert "remove" in kinds and "add" in kinds and "context" in kinds


def test_parse_diff_hunk_pagination() -> None:
    diff_text = (FIXTURES_DIR / "sample_unified_diff.txt").read_text(encoding="utf-8")
    page0 = parse_unified_diff_hunks(diff_text, max_hunks=0, hunk_offset=0)
    page1 = parse_unified_diff_hunks(diff_text, max_hunks=0, hunk_offset=1)
    assert page0["returnedHunks"] == 1
    assert page0["hasMoreHunks"] is False
    assert page1["returnedHunks"] == 0


def test_format_grep_rg_lines() -> None:
    text = format_grep_matches_rg([
        {"path": "src/a.py", "line": 10, "column": 3, "preview": "x = TODO"},
    ])
    assert text == "src/a.py:10:3:x = TODO"


def test_format_diff_summary_shape() -> None:
    summary = format_diff_hunk_summary({
        "mode": "literal_unified_diff_hunks",
        "source": "unstaged",
        "totalFiles": 1,
        "totalHunks": 2,
        "returnedHunks": 1,
        "totalAddedLines": 3,
        "totalRemovedLines": 1,
        "hasMoreHunks": True,
        "nextHunkOffset": 1,
        "truncated": True,
        "files": [{"newPath": "a.py", "totalHunks": 2, "returnedHunks": 1, "addedLines": 3, "removedLines": 1, "truncated": True}],
    })
    assert summary["type"] == "diff_summary"
    assert summary["files"][0]["path"] == "a.py"


def test_rg_workspace_contract() -> None:
    result = rg_workspace("TOOLING:", paths=["scripts/agent_tooling.py"], max_lines=5)
    assert result["exitCode"] in (0, 1)
    assert isinstance(result["matchLines"], list)


def test_read_text_file_literal() -> None:
    text = read_text_file_literal(REPO_ROOT / "scripts/agent_contracts.py")
    assert text and "CONTRACT:" in text


def test_grep_empty_result_hint() -> None:
    hint = grep_empty_result_hint({
        "matches": [],
        "query": "ZZZ_NOT_FOUND",
        "scannedFiles": 10,
        "filesRead": 8,
    })
    assert hint and "filesRead=8" in hint and "hint=" in hint


def test_patch_validation_summary_shape() -> None:
    summary = format_patch_validation_summary({
        "ok": False,
        "targetFileExists": True,
        "insideWorkspace": True,
        "patchAppliesCleanly": False,
        "changedLineCount": 2,
        "requiresConfirmation": False,
        "syntaxDanger": False,
        "rejectedReason": "Patch does not apply cleanly.",
    }, path="a.py")
    assert summary["type"] == "patch_validation_summary"
    assert summary["ok"] is False


def test_grep_anchor_fixture() -> None:
    anchor = json.loads((FIXTURES_DIR / "grep_anchor.json").read_text(encoding="utf-8"))
    assert anchor["query"] == "CONTRACT:"
    assert anchor["minMatches"] >= 1


def test_live_grep_schema(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "workspace.grep", {"query": "DietCode", "maxResults": 3})
    assert response.get("ok"), response
    errors = validate_grep_response(response.get("result", {}))
    assert not errors, errors


def test_live_grep_pagination(sock: socket.socket, token: str) -> None:
    first = send_rpc(sock, token, "workspace.grep", {"query": "the", "maxResults": 1, "resultOffset": 0})
    assert first.get("ok"), first
    result = first.get("result", {})
    if not result.get("hasMore"):
        return
    second = send_rpc(
        sock,
        token,
        "workspace.grep",
        {"query": "the", "maxResults": 1, "resultOffset": result.get("nextResultOffset")},
    )
    assert second.get("ok"), second
    matches = second.get("result", {}).get("matches", [])
    if matches:
        assert matches[0].get("resultIndex", -1) >= 1


def test_live_grep_anchor(sock: socket.socket, token: str) -> None:
    anchor = json.loads((FIXTURES_DIR / "grep_anchor.json").read_text(encoding="utf-8"))
    response = send_rpc(sock, token, "workspace.grep", {
        "query": anchor["query"],
        "maxResults": 5,
        "include": anchor["include"],
    })
    assert response.get("ok"), response
    result = response.get("result", {})
    errors = validate_grep_response(result)
    assert not errors, errors
    assert len(result.get("matches", [])) >= anchor["minMatches"]
    assert result.get("filesRead", 0) >= anchor["minFilesRead"]
    assert result.get("filesReadFromDisk", 0) >= 1


def test_live_grep_line_hash(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "workspace.grep", {"query": "DietCode", "maxResults": 1})
    assert response.get("ok"), response
    matches = response.get("result", {}).get("matches", [])
    if not matches:
        return
    match = matches[0]
    preview = match.get("preview", "")
    assert match.get("lineSha256") == stable_hash_for_string(preview)


def _append_tracked_probe_line(workspace_root: str, rel_path: str, marker: str) -> str:
    import os

    target = os.path.join(workspace_root, rel_path)
    original = open(target, encoding="utf-8").read()
    open(target, "a", encoding="utf-8").write(marker)
    return original


def _restore_tracked_probe(workspace_root: str, rel_path: str, original: str) -> None:
    import os

    open(os.path.join(workspace_root, rel_path), "w", encoding="utf-8").write(original)


def test_live_diff_hunks_schema(sock: socket.socket, token: str, workspace_root: str) -> None:
    rel_path = "scripts/agent_contracts.py"
    marker = "\n# tooling_diff_probe\n"
    original = _append_tracked_probe_line(workspace_root, rel_path, marker)
    try:
        response = send_rpc(
            sock,
            token,
            "diff.hunks",
            {
                "source": "file",
                "path": rel_path,
                "maxHunks": 5,
                "includeLines": True,
            },
            request_timeout=30.0,
        )
        assert response.get("ok"), response
        errors = validate_diff_hunks_response(response.get("result", {}))
        assert not errors, errors
        assert response["result"].get("source") == "file"
        assert response["result"].get("totalHunks", 0) >= 1
    finally:
        _restore_tracked_probe(workspace_root, rel_path, original)


def test_live_patch_validate_shape(sock: socket.socket, token: str, workspace_root: str) -> None:
    import os

    target = os.path.join(workspace_root, "tooling_patch_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("value = 1\n")
    try:
        patch = (
            "--- tooling_patch_probe.py\n"
            "+++ tooling_patch_probe.py\n"
            "@@ -1 +1 @@\n"
            "-value = 1\n"
            "+value = 2\n"
        )
        response = send_rpc(sock, token, "patch.validate", {"path": "tooling_patch_probe.py", "patch": patch})
        assert response.get("ok"), response
        validation = response.get("result", {}).get("validation", {})
        errors = validate_patch_validation(validation)
        assert not errors, errors
        assert validation.get("ok") is True
        assert validation.get("patchAppliesCleanly") is True
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_diff_summary_compat(sock: socket.socket, token: str, workspace_root: str) -> None:
    rel_path = "scripts/agent_tooling.py"
    marker = "\n# tooling_diff_summary_probe\n"
    original = _append_tracked_probe_line(workspace_root, rel_path, marker)
    try:
        response = send_rpc(
            sock,
            token,
            "diff.hunks",
            {"source": "file", "path": rel_path, "maxHunks": 3},
            request_timeout=30.0,
        )
        assert response.get("ok"), response
        summary = format_diff_hunk_summary(response.get("result", {}))
        assert summary["type"] == "diff_summary"
        assert summary["totalHunks"] >= 1
    finally:
        _restore_tracked_probe(workspace_root, rel_path, original)


def main() -> int:
    parser = argparse.ArgumentParser(description="Grep/diff tooling contract regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("tooling.literal_match_spans", test_literal_match_spans_case_insensitive),
        ("tooling.literal_non_overlapping", test_literal_match_spans_non_overlapping),
        ("tooling.stable_hash", test_stable_hash_known),
        ("tooling.parse_fixture_hunks", test_parse_fixture_diff_hunks),
        ("tooling.parse_hunk_pagination", test_parse_diff_hunk_pagination),
        ("tooling.format_grep_rg", test_format_grep_rg_lines),
        ("tooling.format_diff_summary", test_format_diff_summary_shape),
        ("tooling.rg_workspace", test_rg_workspace_contract),
        ("tooling.read_text_literal", test_read_text_file_literal),
        ("tooling.grep_empty_hint", test_grep_empty_result_hint),
        ("tooling.patch_validation_summary", test_patch_validation_summary_shape),
        ("tooling.grep_anchor_fixture", test_grep_anchor_fixture),
    ]
    for name, fn in offline:
        recorder.run(name, fn)

    workspace_root: str | None = None
    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("tooling.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("tooling.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("grep_diff_tooling")

    live_sock: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("tooling.live_grep_schema", test_live_grep_schema),
        ("tooling.live_grep_anchor", test_live_grep_anchor),
        ("tooling.live_grep_pagination", test_live_grep_pagination),
        ("tooling.live_grep_line_hash", test_live_grep_line_hash),
    ]
    for name, fn in live_sock:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                token = load_token()
                f(sock, token)

        recorder.run(name, _run)

    if workspace_root:
        for name, fn in [
            ("tooling.live_diff_hunks_schema", test_live_diff_hunks_schema),
            ("tooling.live_diff_summary", test_live_diff_summary_compat),
            ("tooling.live_patch_validate_shape", test_live_patch_validate_shape),
        ]:
            def _run_mut(f: Callable = fn) -> None:
                with connect() as sock:
                    f(sock, load_token(), workspace_root)

            recorder.run(name, _run_mut)

    return recorder.finish("grep_diff_tooling")


if __name__ == "__main__":
    raise SystemExit(main())
