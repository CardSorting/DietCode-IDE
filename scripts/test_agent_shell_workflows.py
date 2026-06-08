#!/usr/bin/env python3
"""
SHELL: Pass IX — live shell workflow smoke tests (A–E).

Grep: rg 'test_agent_shell_workflows|test-agent-shell-workflows' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from pathlib import Path

from agent_contracts import (
    validate_patch_validation,
    validate_shell_cat_small_response,
    validate_shell_envelope,
    validate_shell_rg_response,
    validate_shell_sed_range_response,
)
from agent_shell_tooling import FIXTURES_DIR, format_shell_rg_match_line
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, connect, ensure_workspace_root, load_token, send_rpc

LARGE_FIXTURE = FIXTURES_DIR / "large_text.txt"


def _ensure_large_fixture() -> Path:
    LARGE_FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    if not LARGE_FIXTURE.exists() or LARGE_FIXTURE.stat().st_size < 100_000:
        line = "LARGE_FIXTURE_LINE=repeat\n"
        LARGE_FIXTURE.write_text(line * 8000, encoding="utf-8")
    return LARGE_FIXTURE


def workflow_a_find_and_inspect(sock: socket.socket, token: str) -> None:
    anchor = json.loads((FIXTURES_DIR / "shell_anchor.json").read_text(encoding="utf-8"))
    rel_path = anchor["path"]
    rg = send_rpc(sock, token, "shell.rg", {"pattern": anchor["pattern"], "path": rel_path, "maxResults": 10})
    assert rg.get("ok"), rg
    result = rg["result"]
    assert not validate_shell_rg_response(result), validate_shell_rg_response(result)
    assert result["matchCount"] >= anchor["minMatches"]
    first = result["matches"][0]
    line_a = format_shell_rg_match_line(first)
    rg2 = send_rpc(sock, token, "shell.rg", {"pattern": anchor["pattern"], "path": rel_path, "maxResults": 10})
    line_b = format_shell_rg_match_line(rg2["result"]["matches"][0])
    assert line_a == line_b, "shell.rg line/column must be stable across calls"
    sed = send_rpc(
        sock,
        token,
        "shell.sedRange",
        {"path": rel_path, "startLine": anchor["sedStart"], "endLine": anchor["sedEnd"]},
    )
    assert sed.get("ok"), sed
    sed_result = sed["result"]
    assert not validate_shell_sed_range_response(sed_result), validate_shell_sed_range_response(sed_result)
    assert anchor["pattern"] in sed_result["stdout"]


def workflow_b_avoid_bad_cat(sock: socket.socket, token: str) -> None:
    large = _ensure_large_fixture()
    rel = os.path.relpath(large, REPO_ROOT)
    cat = send_rpc(sock, token, "shell.catSmall", {"path": rel})
    assert cat.get("ok"), cat
    result = cat["result"]
    assert not validate_shell_cat_small_response(result), validate_shell_cat_small_response(result)
    assert result["partial"] is True or result["truncated"] is True
    assert result["recoveryHint"] == "use_shell_head_tail_or_sedRange"
    assert result["nextRecommendedCommand"] == "shell.sedRange"


def workflow_c_directory_safety(sock: socket.socket, token: str, workspace_root: str) -> None:
    pwd_before = send_rpc(sock, token, "shell.pwd", {})
    assert pwd_before.get("ok"), pwd_before
    assert not validate_shell_envelope(pwd_before["result"])
    inside = send_rpc(sock, token, "shell.cd", {"path": "scripts"})
    assert inside.get("ok"), inside
    assert inside["result"]["cwdAfter"].endswith("scripts")
    rg_from_cwd = send_rpc(sock, token, "shell.rg", {"pattern": "SHELL:", "path": "agent_shell_tooling.py", "maxResults": 1})
    assert rg_from_cwd.get("ok"), rg_from_cwd
    back = send_rpc(sock, token, "shell.cd", {"path": workspace_root})
    assert back.get("ok"), back
    outside = send_rpc(sock, token, "shell.cd", {"path": "/usr"})
    assert not outside.get("ok"), outside
    assert outside.get("error", {}).get("string_code") == "outside_workspace"
    missing = send_rpc(sock, token, "shell.cd", {"path": "scripts/no_such_dir_ix"})
    assert not missing.get("ok"), missing
    assert missing.get("error", {}).get("string_code") == "directory_not_found"
    not_dir = send_rpc(sock, token, "shell.cd", {"path": "README.md"})
    assert not not_dir.get("ok"), not_dir
    assert not_dir.get("error", {}).get("string_code") == "not_directory"
    escape_dir = Path(workspace_root) / "scripts" / "fixtures" / "shell" / "escape_probe"
    escape_dir.mkdir(parents=True, exist_ok=True)
    link = escape_dir / "outside_link"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to("/tmp")
    try:
        escaped = send_rpc(sock, token, "shell.cd", {"path": str(link.relative_to(workspace_root))})
        assert not escaped.get("ok"), escaped
        assert escaped.get("error", {}).get("string_code") == "symlink_escape"
    finally:
        if link.is_symlink() or link.exists():
            link.unlink()


def workflow_d_read_patch_target(sock: socket.socket, token: str) -> None:
    anchor = json.loads((FIXTURES_DIR / "shell_anchor.json").read_text(encoding="utf-8"))
    rel = anchor["path"]
    rg = send_rpc(sock, token, "shell.rg", {"pattern": anchor["pattern"], "path": rel, "maxResults": 1})
    assert rg.get("ok"), rg
    match = rg["result"]["matches"][0]
    line = match["line"]
    start = max(1, line - 1)
    end = line + 1
    sed = send_rpc(sock, token, "shell.sedRange", {"path": rel, "startLine": start, "endLine": end})
    assert sed.get("ok"), sed
    patch = (
        f"--- {rel}\n"
        f"+++ {rel}\n"
        f"@@ -{line} +{line} @@\n"
        f"-{match['preview']}\n"
        f"+{match['preview']} # patched\n"
    )
    validated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": patch})
    assert validated.get("ok"), validated
    assert not validate_patch_validation(validated["result"]["validation"])
    stat = send_rpc(sock, token, "file.stat", {"path": rel})
    assert stat.get("ok"), stat
    assert stat["result"]["path"].endswith(rel.replace("/", os.sep))


def workflow_e_binary_and_symlink_safety(sock: socket.socket, token: str, workspace_root: str) -> None:
    send_rpc(sock, token, "shell.cd", {"path": workspace_root})
    probe_dir = Path(workspace_root) / "scripts" / "fixtures" / "shell" / "safety_probe"
    probe_dir.mkdir(parents=True, exist_ok=True)
    binary = probe_dir / "binary_probe.bin"
    binary.write_bytes(b"\x00binary\n")
    rel_binary = str(binary.relative_to(workspace_root))
    try:
        head = send_rpc(sock, token, "shell.head", {"path": rel_binary, "lines": 5})
        assert not head.get("ok"), head
        assert head.get("error", {}).get("string_code") == "shell_binary_file"
    finally:
        if binary.exists():
            binary.unlink()

    link_target = probe_dir / "text_link.txt"
    link_target.write_text("link target\n", encoding="utf-8")
    symlink = probe_dir / "escape_file_link"
    if symlink.is_symlink() or symlink.exists():
        symlink.unlink()
    symlink.symlink_to("/etc/hosts")
    rel_link = str(symlink.relative_to(workspace_root))
    try:
        cat = send_rpc(sock, token, "shell.catSmall", {"path": rel_link})
        assert not cat.get("ok"), cat
        assert cat.get("error", {}).get("string_code") == "shell_symlink_escape"
    finally:
        if symlink.is_symlink() or symlink.exists():
            symlink.unlink()
        if link_target.exists():
            link_target.unlink()

    rg = send_rpc(sock, token, "shell.rg", {"pattern": "SHELL_ANCHOR_IX:", "path": "scripts/fixtures/shell", "maxResults": 5})
    assert rg.get("ok"), rg
    rg_result = rg["result"]
    assert not validate_shell_rg_response(rg_result), validate_shell_rg_response(rg_result)
    assert "filesSkippedSymlink" in rg_result


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass IX shell workflow smoke tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    sock = connect()
    token = load_token()
    workspace_root = ensure_workspace_root(sock, token)

    live = [
        ("shell.workflow_a_find_inspect", lambda: workflow_a_find_and_inspect(sock, token)),
        ("shell.workflow_b_avoid_bad_cat", lambda: workflow_b_avoid_bad_cat(sock, token)),
        ("shell.workflow_c_directory_safety", lambda: workflow_c_directory_safety(sock, token, workspace_root)),
        ("shell.workflow_d_read_patch_target", lambda: workflow_d_read_patch_target(sock, token)),
        ("shell.workflow_e_binary_symlink_safety", lambda: workflow_e_binary_and_symlink_safety(sock, token, workspace_root)),
    ]
    for name, fn in live:
        recorder.run(name, fn)

    return recorder.finish("agent_shell_workflows")


if __name__ == "__main__":
    raise SystemExit(main())
