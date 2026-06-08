#!/usr/bin/env python3
"""
INVARIANT: Transaction kernel closure — revision, batch atomicity, search parity, idempotency.

Grep: rg 'test_transaction_kernel|transaction_kernel' scripts/ docs/ Makefile
"""

from __future__ import annotations

import argparse
import os
import socket
import uuid
from collections.abc import Callable

from agent_contracts import (
    validate_batch_mutation_receipt,
    validate_grep_response,
    validate_mutation_receipt,
    validate_search_text_response,
    validate_search_todo_response,
    validate_workspace_revision,
    validate_workspace_snapshot,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from agent_tooling import parse_unified_diff_hunks, stable_hash_for_string
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "tooling")


def test_offline_rollback_multihunk_parse() -> None:
    patch = open(os.path.join(FIXTURES_DIR, "rollback_multihunk.txt"), encoding="utf-8").read()
    parsed = parse_unified_diff_hunks(patch, include_lines=True)
    assert parsed["totalHunks"] == 1
    assert parsed["totalAddedLines"] >= 2
    assert parsed["totalRemovedLines"] >= 2


def test_offline_rollback_hash_chain() -> None:
    before = "line1\nline2\n"
    after = "line1\nline2-mod\n"
    before_hash = stable_hash_for_string(before)
    after_hash = stable_hash_for_string(after)
    assert before_hash != after_hash
    assert stable_hash_for_string(before) == before_hash


def test_offline_crlf_hash_deterministic() -> None:
    lf = stable_hash_for_string("alpha\r\n")
    crlf_as_lf = stable_hash_for_string("alpha\n")
    assert isinstance(lf, str) and len(lf) == 16
    assert lf != crlf_as_lf


def test_offline_no_trailing_newline_hash() -> None:
    with_newline = stable_hash_for_string("beta\n")
    without_newline = stable_hash_for_string("beta")
    assert with_newline != without_newline


def test_live_workspace_revision(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "workspace.revision", {})
    assert response.get("ok"), response
    errors = validate_workspace_revision(response["result"])
    assert not errors, errors
    assert response["result"]["revisionId"] >= 1


def test_live_workspace_snapshot(sock: socket.socket, token: str) -> None:
    rev = send_rpc(sock, token, "workspace.revision", {})
    revision_id = rev["result"]["revisionId"]
    response = send_rpc(sock, token, "workspace.snapshot", {"sinceRevision": revision_id})
    assert response.get("ok"), response
    errors = validate_workspace_snapshot(response["result"])
    assert not errors, errors


def test_live_search_text_parity(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.text",
        {"query": "CONTRACT:", "maxResults": 5, "include": ["scripts/agent_contracts.py"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    errors = validate_search_text_response(response["result"])
    assert not errors, errors
    assert response["result"]["sortOrder"] == "path_line_column"
    assert response["result"]["symlinkPolicy"] == "skip_never_follow"


def test_live_search_todo_parity(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.todo",
        {"maxResults": 5, "include": ["scripts/agent_contracts.py"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    errors = validate_search_todo_response(response["result"])
    assert not errors, errors


def test_live_grep_symlink_policy(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "workspace.grep", {"query": "x", "maxResults": 1})
    assert response.get("ok"), response
    errors = validate_grep_response(response["result"])
    assert not errors, errors
    assert response["result"]["symlinkPolicy"] == "skip_never_follow"


def test_live_batch_patch_atomic(sock: socket.socket, token: str, workspace_root: str) -> None:
    files = ["kernel_batch_a.py", "kernel_batch_b.py"]
    try:
        for name in files:
            with open(os.path.join(workspace_root, name), "w", encoding="utf-8") as handle:
                handle.write(f"# {name}\nvalue = 1\n")
        patches = []
        validations = []
        for name in files:
            patch = (
                f"--- {name}\n"
                f"+++ {name}\n"
                "@@ -1,2 +1,2 @@\n"
                f"-# {name}\n"
                f"+# {name} patched\n"
                " value = 1\n"
            )
            validated = send_rpc(sock, token, "patch.validate", {"path": name, "patch": patch})
            assert validated.get("ok"), validated
            validation = validated["result"]["validation"]
            patches.append({
                "path": name,
                "patch": patch,
                "expectBeforeHash": validation["beforeContentHash"],
            })
            validations.append(validation)
        dry = send_rpc(
            sock,
            token,
            "patch.applyBatch",
            {"patches": patches, "dryRun": True, "confirm": True},
        )
        assert dry.get("ok"), dry
        assert dry["result"]["applied"] is False
        assert dry["result"]["atomic"] is True
        key = f"batch-{uuid.uuid4().hex}"
        applied = send_rpc(
            sock,
            token,
            "patch.applyBatch",
            {"patches": patches, "dryRun": False, "confirm": True, "idempotencyKey": key},
        )
        assert applied.get("ok"), applied
        assert applied["result"]["applied"] is True
        receipt = applied["result"]["batchMutationReceipt"]
        errors = validate_batch_mutation_receipt(receipt)
        assert not errors, errors
        assert receipt["appliedCount"] == 2
        assert applied["result"]["revisionAfter"] > applied["result"]["revisionBefore"]
        replay = send_rpc(sock, token, "operation.status", {"idempotencyKey": key})
        assert replay.get("ok"), replay
        assert replay["result"]["status"] == "completed"
        status = send_rpc(sock, token, "operation.status", {"idempotencyKey": key})
        assert status["result"]["revisionAfter"] == applied["result"]["revisionAfter"]
    finally:
        for name in files:
            path = os.path.join(workspace_root, name)
            if os.path.exists(path):
                os.remove(path)


def test_live_single_patch_idempotency(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "kernel_idem_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("idem = 1\n")
    try:
        patch = (
            "--- kernel_idem_probe.py\n"
            "+++ kernel_idem_probe.py\n"
            "@@ -1 +1 @@\n"
            "-idem = 1\n"
            "+idem = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "kernel_idem_probe.py", "patch": patch})
        validation = validated["result"]["validation"]
        key = f"single-{uuid.uuid4().hex}"
        params = {
            "path": "kernel_idem_probe.py",
            "patch": patch,
            "confirm": True,
            "expectBeforeHash": validation["beforeContentHash"],
            "idempotencyKey": key,
        }
        first = send_rpc(sock, token, "patch.apply", params)
        assert first.get("ok"), first
        errors = validate_mutation_receipt(first["result"]["mutationReceipt"])
        assert not errors, errors
        second = send_rpc(sock, token, "patch.apply", params)
        assert second.get("ok"), second
        assert second["result"].get("idempotentReplay") is True
        status = send_rpc(sock, token, "operation.status", {"idempotencyKey": key})
        assert status["result"]["status"] == "completed"
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_revision_bumps_on_mutation(sock: socket.socket, token: str, workspace_root: str) -> None:
    before = send_rpc(sock, token, "workspace.revision", {})
    rev_before = before["result"]["revisionId"]
    target = os.path.join(workspace_root, "kernel_rev_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("rev = 1\n")
    try:
        patch = (
            "--- kernel_rev_probe.py\n"
            "+++ kernel_rev_probe.py\n"
            "@@ -1 +1 @@\n"
            "-rev = 1\n"
            "+rev = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "kernel_rev_probe.py", "patch": patch})
        validation = validated["result"]["validation"]
        applied = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": "kernel_rev_probe.py",
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validation["beforeContentHash"],
            },
        )
        assert applied.get("ok"), applied
        after = send_rpc(sock, token, "workspace.revision", {})
        assert after["result"]["revisionId"] > rev_before
        assert "kernel_rev_probe.py" in after["result"]["changedFiles"]
    finally:
        if os.path.exists(target):
            os.remove(target)


def main() -> int:
    parser = argparse.ArgumentParser(description="Transaction kernel closure regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("kernel.rollback_multihunk_parse", test_offline_rollback_multihunk_parse),
        ("kernel.rollback_hash_chain", test_offline_rollback_hash_chain),
        ("kernel.crlf_hash", test_offline_crlf_hash_deterministic),
        ("kernel.no_trailing_newline_hash", test_offline_no_trailing_newline_hash),
    ]:
        recorder.run(name, fn)

    workspace_root: str | None = None
    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("kernel.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("kernel.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("transaction_kernel")

    readonly: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("kernel.workspace_revision", test_live_workspace_revision),
        ("kernel.workspace_snapshot", test_live_workspace_snapshot),
        ("kernel.search_text_parity", test_live_search_text_parity),
        ("kernel.search_todo_parity", test_live_search_todo_parity),
        ("kernel.grep_symlink_policy", test_live_grep_symlink_policy),
    ]
    for name, fn in readonly:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    if workspace_root:
        for name, fn in [
            ("kernel.batch_patch_atomic", test_live_batch_patch_atomic),
            ("kernel.patch_idempotency", test_live_single_patch_idempotency),
            ("kernel.revision_bump", test_live_revision_bumps_on_mutation),
        ]:
            def _run_mut(f: Callable = fn) -> None:
                with connect() as sock:
                    f(sock, load_token(), workspace_root)

            recorder.run(name, _run_mut)

    return recorder.finish("transaction_kernel")


if __name__ == "__main__":
    raise SystemExit(main())
