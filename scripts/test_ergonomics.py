#!/usr/bin/env python3
"""
DietCode Ergonomics & Patch Validation Verification Suite.
Emits NDJSON check lines plus a final summary (pipe-friendly for agents).

Run with DietCode open and its control socket active:
    python3 scripts/test_ergonomics.py --compact
    make test-ergonomics
"""

from __future__ import annotations

import argparse
import os
import socket
from collections.abc import Callable

from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc


def call(sock: socket.socket, token: str, method: str, params: dict | None = None) -> dict:
    return send_rpc(sock, token, method, params)


def test_markdown_brackets(sock: socket.socket, token: str, workspace_root: str) -> None:
    md_file_path = os.path.join(workspace_root, "test_bracket_md.md")
    with open(md_file_path, "w", encoding="utf-8") as f:
        f.write("# Hello World\n[link without closing paren\n")
    try:
        patch_md = (
            "--- test_bracket_md.md\n"
            "+++ test_bracket_md.md\n"
            "@@ -1,2 +1,3 @@\n"
            " # Hello World\n"
            " [link without closing paren\n"
            "+More unmatched text [here\n"
        )
        res = call(sock, token, "patch.validate", {"path": "test_bracket_md.md", "patch": patch_md})
        assert res.get("ok"), "Markdown patch.validate RPC failed"
        validation = res.get("result", {}).get("validation", {})
        assert validation.get("ok"), f"Markdown validation ok=False: {validation.get('rejectedReason')}"
        assert validation.get("syntaxDanger") is False
    finally:
        if os.path.exists(md_file_path):
            os.remove(md_file_path)


def test_python_comment_brackets(sock: socket.socket, token: str, workspace_root: str) -> None:
    py_file_path = os.path.join(workspace_root, "test_bracket_py.py")
    with open(py_file_path, "w", encoding="utf-8") as f:
        f.write('# (This is a comment with unbalanced paren\ns = "[unbalanced string"\n')
    try:
        patch_py = (
            "--- test_bracket_py.py\n"
            "+++ test_bracket_py.py\n"
            "@@ -1,2 +1,3 @@\n"
            ' # (This is a comment with unbalanced paren\n'
            ' s = "[unbalanced string"\n'
            "+x = 42\n"
        )
        res = call(sock, token, "patch.validate", {"path": "test_bracket_py.py", "patch": patch_py})
        assert res.get("ok"), "Python comment/string patch.validate RPC failed"
        validation = res.get("result", {}).get("validation", {})
        assert validation.get("ok"), f"Python validation ok=False: {validation.get('rejectedReason')}"
        assert validation.get("syntaxDanger") is False
    finally:
        if os.path.exists(py_file_path):
            os.remove(py_file_path)


def test_python_compile_error_modes(sock: socket.socket, token: str, workspace_root: str) -> None:
    py_err_path = os.path.join(workspace_root, "test_err_py.py")
    with open(py_err_path, "w", encoding="utf-8") as f:
        f.write("def foo():\n    return 42\n")
    try:
        patch_err = (
            "--- test_err_py.py\n"
            "+++ test_err_py.py\n"
            "@@ -1,2 +1,2 @@\n"
            "-def foo():\n"
            "+def foo(:\n"
            "     return 42\n"
        )
        res_relaxed = call(sock, token, "patch.validate", {"path": "test_err_py.py", "patch": patch_err})
        assert res_relaxed.get("ok"), "Relaxed patch.validate RPC failed"
        val_relaxed = res_relaxed.get("result", {}).get("validation", {})
        assert val_relaxed.get("ok"), f"Relaxed validation ok=False: {val_relaxed.get('rejectedReason')}"
        assert val_relaxed.get("syntaxDanger") is True
        assert val_relaxed.get("syntaxWarning")

        res_strict = call(
            sock,
            token,
            "patch.validate",
            {"path": "test_err_py.py", "patch": patch_err, "ignoreSyntax": False},
        )
        assert res_strict.get("ok"), "Strict patch.validate RPC call failed at socket level"
        val_strict = res_strict.get("result", {}).get("validation", {})
        assert not val_strict.get("ok"), "Strict validation should return validation.ok=False"
        assert val_strict.get("rejectedReason")
    finally:
        if os.path.exists(py_err_path):
            os.remove(py_err_path)


def test_missing_target_shape(sock: socket.socket, token: str, _workspace_root: str) -> None:
    res_missing = call(
        sock,
        token,
        "patch.validate",
        {
            "path": "missing_ergonomics_target.py",
            "patch": (
                "--- missing_ergonomics_target.py\n"
                "+++ missing_ergonomics_target.py\n"
                "@@ -1 +1 @@\n"
                "-old\n"
                "+new\n"
            ),
        },
    )
    assert res_missing.get("ok"), "patch.validate RPC should return validation object for missing target"
    missing_validation = res_missing.get("result", {}).get("validation", {})
    assert missing_validation.get("ok") is False
    assert missing_validation.get("syntaxDanger") is False


def test_patch_preview_syntax_danger(sock: socket.socket, token: str, workspace_root: str) -> None:
    py_preview_path = os.path.join(workspace_root, "test_preview_py.py")
    with open(py_preview_path, "w", encoding="utf-8") as f:
        f.write("def preview_ok():\n    return 42\n")
    try:
        patch_preview = (
            "--- test_preview_py.py\n"
            "+++ test_preview_py.py\n"
            "@@ -1,2 +1,2 @@\n"
            "-def preview_ok():\n"
            "+def preview_ok(:\n"
            "     return 42\n"
        )
        res_preview = call(sock, token, "patch.preview", {"path": "test_preview_py.py", "patch": patch_preview})
        assert res_preview.get("ok"), "patch.preview RPC failed"
        preview_result = res_preview.get("result", {})
        assert preview_result.get("syntaxDanger") is True
        assert preview_result.get("syntaxWarning")
    finally:
        if os.path.exists(py_preview_path):
            os.remove(py_preview_path)


def test_task_terminal_state(sock: socket.socket, token: str, _workspace_root: str) -> None:
    res_task = call(sock, token, "task.start", {"goal": "ergonomics terminal state regression"})
    assert res_task.get("ok"), "task.start RPC failed"
    task_id = res_task.get("result", {}).get("taskId")
    assert task_id, "task.start did not return taskId"

    res_complete = call(sock, token, "task.runLoop", {"taskId": task_id, "steps": []})
    assert res_complete.get("ok"), "task.runLoop empty completion RPC failed"
    assert res_complete.get("result", {}).get("task", {}).get("status") == "complete"

    res_step_after_complete = call(
        sock,
        token,
        "task.step",
        {"taskId": task_id, "step": {"type": "contextSnapshot"}},
    )
    assert res_step_after_complete.get("ok"), "task.step rejection should be returned in stepResult"
    step_result = res_step_after_complete.get("result", {}).get("stepResult", {})
    assert step_result.get("ok") is False
    assert step_result.get("error", {}).get("code") == "task_not_active"
    assert res_step_after_complete.get("result", {}).get("task", {}).get("status") == "complete"

    res_cancel_complete = call(sock, token, "task.cancel", {"taskId": task_id})
    assert not res_cancel_complete.get("ok"), "task.cancel on complete task should return an error"
    assert res_cancel_complete.get("error", {}).get("string_code") == "task_not_active"


def _assert_invalid_params(
    sock: socket.socket,
    token: str,
    label: str,
    method: str,
    params: dict,
    expected_code: str,
) -> None:
    res_invalid = call(sock, token, method, params)
    assert not res_invalid.get("ok"), f"{label} should fail"
    assert res_invalid.get("error", {}).get("string_code") == expected_code, (
        f"{label} expected {expected_code}, got {res_invalid.get('error', {}).get('string_code')}"
    )


def test_read_search_invalid_params(sock: socket.socket, token: str, workspace_root: str) -> None:
    contract_path = os.path.join(workspace_root, "test_contracts.txt")
    with open(contract_path, "w", encoding="utf-8") as f:
        f.write("alpha\nbeta\ngamma\n")
    try:
        cases = [
            ("file.readRange missing startLine", "file.readRange", {"path": "test_contracts.txt", "endLine": 1}, "invalid_params"),
            ("file.readAround negative context", "file.readAround", {"path": "test_contracts.txt", "line": 1, "before": -1}, "invalid_params"),
            ("search.files zero maxResults", "search.files", {"query": "test", "maxResults": 0}, "invalid_params"),
            ("search.text excessive context", "search.text", {"query": "alpha", "before": 21}, "response_too_large"),
            ("search.todo negative maxResults", "search.todo", {"maxResults": -1}, "invalid_params"),
            ("analysis.searchRanked negative maxResults", "analysis.searchRanked", {"query": "alpha", "maxResults": -1}, "invalid_params"),
        ]
        for label, method, params, expected_code in cases:
            _assert_invalid_params(sock, token, label, method, params, expected_code)
    finally:
        if os.path.exists(contract_path):
            os.remove(contract_path)


def test_side_effect_free_invalid_params(sock: socket.socket, token: str, workspace_root: str) -> None:
    contract_path = os.path.join(workspace_root, "test_contracts.txt")
    with open(contract_path, "w", encoding="utf-8") as f:
        f.write("alpha\nbeta\ngamma\n")
    try:
        cases = [
            ("terminal.run empty command", "terminal.run", {"command": ""}, "invalid_params"),
            ("verify.run empty command", "verify.run", {"command": ""}, "invalid_params"),
            (
                "repair context outside workspace",
                "repair.fromPatchFailure",
                {"files": [{"path": "/tmp/outside_repair_context.txt", "ranges": [{"startLine": 1, "endLine": 1}]}]},
                "outside_workspace",
            ),
            (
                "repair context invalid range",
                "repair.fromPatchFailure",
                {"files": [{"path": "test_contracts.txt", "ranges": [{"startLine": 0, "endLine": 1}]}]},
                "invalid_params",
            ),
        ]
        for label, method, params, expected_code in cases:
            _assert_invalid_params(sock, token, label, method, params, expected_code)
    finally:
        if os.path.exists(contract_path):
            os.remove(contract_path)


def test_combo_cancel_unknown_id(sock: socket.socket, token: str, _workspace_root: str) -> None:
    res_cancel = call(sock, token, "combo.cancel", {"comboId": "nonexistent-test-id"})
    assert not res_cancel.get("ok"), "combo.cancel with unknown comboId should return ok=False"
    assert res_cancel.get("error"), "combo.cancel error response must include an error object"


def main() -> int:
    parser = argparse.ArgumentParser(description="NDJSON ergonomics and patch-validation contract checks.")
    add_output_args(parser)
    args = parser.parse_args()
    compact = output_compact(args)
    recorder = CheckRecorder(compact=compact, verbose=args.verbose)

    tests = [
        ("patch.markdown_brackets", test_markdown_brackets),
        ("patch.python_comment_brackets", test_python_comment_brackets),
        ("patch.python_compile_modes", test_python_compile_error_modes),
        ("patch.missing_target_shape", test_missing_target_shape),
        ("patch.preview_syntax_danger", test_patch_preview_syntax_danger),
        ("task.terminal_state", test_task_terminal_state),
        ("params.read_search_invalid", test_read_search_invalid_params),
        ("params.side_effect_free_invalid", test_side_effect_free_invalid_params),
        ("combo.cancel_unknown_id", test_combo_cancel_unknown_id),
    ]

    workspace_root: str | None = None
    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("workspace.getRoot", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("workspace.getRoot", False, {"error": str(exc)})
        return recorder.finish("ergonomics")

    for name, fn in tests:
        def _run(fn: Callable = fn) -> None:
            with connect() as sock:
                token = load_token()
                fn(sock, token, workspace_root)

        recorder.run(name, _run)

    return recorder.finish("ergonomics")


if __name__ == "__main__":
    raise SystemExit(main())
