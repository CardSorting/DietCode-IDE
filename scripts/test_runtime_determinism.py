#!/usr/bin/env python3
"""
INVARIANT: Runtime determinism — state hashes, grep ordering, stale-write rejection.

Grep: rg 'test_runtime_determinism|runtime_determinism' scripts/ docs/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import socket
from collections.abc import Callable

from agent_contracts import (
    validate_file_stat,
    validate_grep_response,
    validate_mutation_receipt,
    validate_patch_validation,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from agent_tooling import stable_hash_for_string
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "tooling")


def test_live_grep_deterministic_order(sock: socket.socket, token: str) -> None:
    params = {
        "query": "CONTRACT:",
        "maxResults": 10,
        "include": ["scripts/agent_contracts.py"],
    }
    first = send_rpc(sock, token, "workspace.grep", params)
    second = send_rpc(sock, token, "workspace.grep", params)
    assert first.get("ok") and second.get("ok"), (first, second)
    r1 = first["result"]
    r2 = second["result"]
    assert r1.get("sortOrder") == "path_line_column"
    paths1 = [(m["path"], m["line"], m["column"]) for m in r1.get("matches", [])]
    paths2 = [(m["path"], m["line"], m["column"]) for m in r2.get("matches", [])]
    assert paths1 == paths2
    assert not validate_grep_response(r1)
    assert r1.get("scanDurationMs", 0) >= 0


def test_live_grep_skip_accounting(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "workspace.grep", {"query": "x", "maxResults": 1})
    assert response.get("ok"), response
    result = response["result"]
    accounted = (
        result.get("filesRead", 0)
        + result.get("filesSkippedUnreadable", 0)
        + result.get("filesSkippedBinary", 0)
        + result.get("filesSkippedOversize", 0)
        + result.get("filesSkippedExcluded", 0)
    )
    assert accounted <= result.get("scannedFiles", 0) + 1


def test_live_file_stat_content_hash(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "file.stat", {"path": "scripts/agent_contracts.py"})
    assert response.get("ok"), response
    errors = validate_file_stat(response["result"])
    assert not errors, errors


def test_live_patch_validate_precondition_hashes(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "determinism_patch_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("value = 1\n")
    try:
        patch = (
            "--- determinism_patch_probe.py\n"
            "+++ determinism_patch_probe.py\n"
            "@@ -1 +1 @@\n"
            "-value = 1\n"
            "+value = 2\n"
        )
        response = send_rpc(sock, token, "patch.validate", {"path": "determinism_patch_probe.py", "patch": patch})
        assert response.get("ok"), response
        validation = response["result"]["validation"]
        errors = validate_patch_validation(validation)
        assert not errors, errors
        assert validation["beforeContentHash"] == stable_hash_for_string("value = 1\n")
        assert validation["patchFingerprint"] == stable_hash_for_string(patch)
        assert validation["readSource"] in ("editor", "disk")
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_patch_stale_content_rejection(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "determinism_stale_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("alpha = 1\n")
    try:
        patch = (
            "--- determinism_stale_probe.py\n"
            "+++ determinism_stale_probe.py\n"
            "@@ -1 +1 @@\n"
            "-alpha = 1\n"
            "+alpha = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "determinism_stale_probe.py", "patch": patch})
        assert validated.get("ok"), validated
        with open(target, "w", encoding="utf-8") as handle:
            handle.write("alpha = 99\n")
        apply_resp = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": "determinism_stale_probe.py",
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            },
        )
        assert not apply_resp.get("ok"), apply_resp
        assert apply_resp["error"]["string_code"] == "stale_content"
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_patch_mutation_receipt(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "determinism_apply_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("beta = 1\n")
    try:
        patch = (
            "--- determinism_apply_probe.py\n"
            "+++ determinism_apply_probe.py\n"
            "@@ -1 +1 @@\n"
            "-beta = 1\n"
            "+beta = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "determinism_apply_probe.py", "patch": patch})
        assert validated.get("ok"), validated
        validation = validated["result"]["validation"]
        apply_resp = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": "determinism_apply_probe.py",
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validation["beforeContentHash"],
            },
        )
        assert apply_resp.get("ok"), apply_resp
        receipt = apply_resp["result"]["mutationReceipt"]
        errors = validate_mutation_receipt(receipt)
        assert not errors, errors
        assert receipt["beforeContentHash"] == validation["beforeContentHash"]
        assert receipt["postContentHash"] != receipt["beforeContentHash"]
        assert receipt["patchFingerprint"] == validation["patchFingerprint"]
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_corrupted_patch_fixture_offline() -> None:
    from agent_tooling import parse_unified_diff_hunks

    patch = open(os.path.join(FIXTURES_DIR, "corrupted_patch.txt"), encoding="utf-8").read()
    parsed = parse_unified_diff_hunks(patch)
    assert parsed["totalHunks"] == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Runtime determinism regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    recorder.run("determinism.corrupted_patch_fixture", test_corrupted_patch_fixture_offline)

    workspace_root: str | None = None
    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("determinism.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("determinism.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("runtime_determinism")

    live_readonly: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("determinism.grep_order_stable", test_live_grep_deterministic_order),
        ("determinism.grep_skip_accounting", test_live_grep_skip_accounting),
        ("determinism.file_stat_hash", test_live_file_stat_content_hash),
    ]
    for name, fn in live_readonly:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    if workspace_root:
        for name, fn in [
            ("determinism.patch_validate_hashes", test_live_patch_validate_precondition_hashes),
            ("determinism.patch_stale_reject", test_live_patch_stale_content_rejection),
            ("determinism.patch_mutation_receipt", test_live_patch_mutation_receipt),
        ]:
            def _run_mut(f: Callable = fn) -> None:
                with connect() as sock:
                    f(sock, load_token(), workspace_root)

            recorder.run(name, _run_mut)

    return recorder.finish("runtime_determinism")


if __name__ == "__main__":
    raise SystemExit(main())
