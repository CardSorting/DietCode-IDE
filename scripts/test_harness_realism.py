#!/usr/bin/env python3
"""
HARNESS: Pass IV realism — deterministic search.files, symlink escape, transport, concurrency.

Grep: rg 'test_harness_realism|harness_realism' scripts/ docs/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import tempfile
import uuid
from collections.abc import Callable
from pathlib import Path

from agent_contracts import (
    validate_file_stat,
    validate_grep_response,
    validate_search_files_response,
    validate_workspace_snapshot,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import (
    DietCodeTransportError,
    connect,
    ensure_workspace_root,
    load_token,
    send_rpc,
)
from harness_support import SEED_FIXTURE, cleanup_fixture_workspace, create_symlink_fixture_workspace

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures" / "harness"
REPO_ROOT = Path(__file__).resolve().parents[1]


def test_offline_search_files_golden_fixture() -> None:
    golden = json.loads((FIXTURES_DIR / "search_files_golden.json").read_text(encoding="utf-8"))
    assert golden["searchMode"] == "deterministic_path_match"
    assert golden["sortOrder"] == "match_reason_path"
    assert "score" not in json.dumps(golden)


def test_offline_symlink_policy_fixture() -> None:
    policy = json.loads((FIXTURES_DIR / "symlink_policy.json").read_text(encoding="utf-8"))
    assert policy["symlinkPolicy"] == "skip_never_follow"


def test_live_search_files_deterministic(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.files",
        {"query": "agent_contracts.py", "maxResults": 5, "include": ["scripts/*"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    result = response["result"]
    errors = validate_search_files_response(result)
    assert not errors, errors
    assert result["searchMode"] == "deterministic_path_match"
    assert result["sortOrder"] == "match_reason_path"
    assert "score" not in json.dumps(result)
    results = result["results"]
    for i in range(len(results) - 1):
        a, b = results[i], results[i + 1]
        rank = lambda r: 0 if r["matchReason"] == "basename_exact" else 1
        assert rank(a["matchReason"]) <= rank(b["matchReason"])
        if rank(a["matchReason"]) == rank(b["matchReason"]):
            assert a["path"] <= b["path"]


def test_live_search_files_stable_order(sock: socket.socket, token: str) -> None:
    params = {"query": "agent", "maxResults": 10, "include": ["scripts/*.py"]}
    first = send_rpc(sock, token, "search.files", params, request_timeout=30.0)
    second = send_rpc(sock, token, "search.files", params, request_timeout=30.0)
    assert first.get("ok") and second.get("ok")
    paths1 = [(r["path"], r["matchReason"]) for r in first["result"]["results"]]
    paths2 = [(r["path"], r["matchReason"]) for r in second["result"]["results"]]
    assert paths1 == paths2


def test_live_snapshot_completeness(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "workspace.snapshot",
        {"snapshotMode": "mutated_only", "maxFiles": 50},
    )
    assert response.get("ok"), response
    errors = validate_workspace_snapshot(response["result"])
    assert not errors, errors
    snap = response["result"]
    assert snap["snapshotMode"] == "mutated_only"
    assert snap["hashAlgorithm"] == "fnv1a_16hex"
    assert "complete" in snap
    assert "filesHashed" in snap


def _open_fixture_workspace(sock: socket.socket, token: str, fixture_root: Path) -> None:
    response = send_rpc(sock, token, "workspace.openFolder", {"path": str(fixture_root)})
    assert response.get("ok"), response


def test_live_symlink_harness(sock: socket.socket, token: str) -> None:
    fixture_root, paths = create_symlink_fixture_workspace()
    try:
        _open_fixture_workspace(sock, token, fixture_root)
        grep = send_rpc(sock, token, "workspace.grep", {"query": "normal content", "maxResults": 5})
        assert grep.get("ok"), grep
        grep_result = grep["result"]
        assert validate_grep_response(grep_result) == []
        assert grep_result.get("filesSkippedSymlink", 0) >= 1
        stat = send_rpc(sock, token, "file.stat", {"path": paths["link_inside"]})
        assert stat.get("ok"), stat
        stat_result = stat["result"]
        assert stat_result.get("isSymlink") is True
        assert stat_result.get("insideWorkspace") is True
        escape_stat = send_rpc(sock, token, "file.stat", {"path": paths["escape_link"]})
        if escape_stat.get("ok"):
            assert escape_stat["result"].get("pathEscapesWorkspace") is True
        broken = send_rpc(sock, token, "file.stat", {"path": paths["broken_link"]})
        assert broken.get("ok"), broken
        assert broken["result"].get("isSymlink") is True
        patch = (
            "--- link_inside.txt\n"
            "+++ link_inside.txt\n"
            "@@ -1 +1 @@\n"
            "-normal content\n"
            "+mutated\n"
        )
        apply_resp = send_rpc(
            sock,
            token,
            "patch.apply",
            {"path": paths["link_inside"], "patch": patch, "confirm": True},
        )
        assert not apply_resp.get("ok"), apply_resp
        assert apply_resp["error"]["string_code"] == "symlink_target"
    finally:
        cleanup_fixture_workspace(fixture_root)
        _open_fixture_workspace(sock, token, REPO_ROOT)


def test_live_transport_idempotency_recovery(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "harness_transport_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write("transport = 1\n")
    try:
        patch = (
            "--- harness_transport_probe.py\n"
            "+++ harness_transport_probe.py\n"
            "@@ -1 +1 @@\n"
            "-transport = 1\n"
            "+transport = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "harness_transport_probe.py", "patch": patch})
        validation = validated["result"]["validation"]
        key = f"transport-{uuid.uuid4().hex}"
        params = {
            "path": "harness_transport_probe.py",
            "patch": patch,
            "confirm": True,
            "expectBeforeHash": validation["beforeContentHash"],
            "idempotencyKey": key,
        }
        first = send_rpc(sock, token, "patch.apply", params)
        assert first.get("ok"), first
        unknown = send_rpc(sock, token, "operation.status", {"idempotencyKey": "missing-key-" + uuid.uuid4().hex})
        assert unknown["result"]["status"] == "unknown"
        replay = send_rpc(sock, token, "patch.apply", params)
        assert replay.get("ok"), replay
        assert replay["result"].get("idempotentReplay") is True
        status = send_rpc(sock, token, "operation.status", {"idempotencyKey": key})
        assert status["result"]["status"] == "completed"
        assert status["result"]["mutationReceipt"]["postContentHash"] == first["result"]["mutationReceipt"]["postContentHash"]
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_concurrent_stale_write(sock: socket.socket, token: str, workspace_root: str) -> None:
    target = os.path.join(workspace_root, "harness_concurrent_probe.py")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(f"# seed {SEED_FIXTURE}\nvalue = 1\n")
    try:
        patch = (
            "--- harness_concurrent_probe.py\n"
            "+++ harness_concurrent_probe.py\n"
            "@@ -1,2 +1,2 @@\n"
            f"-# seed {SEED_FIXTURE}\n"
            f"+# seed {SEED_FIXTURE} mutated\n"
            " value = 1\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": "harness_concurrent_probe.py", "patch": patch})
        validation = validated["result"]["validation"]
        rev_before = send_rpc(sock, token, "workspace.revision", {})["result"]["revisionId"]
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(f"# seed {SEED_FIXTURE}\nvalue = 99\n")
        stale = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": "harness_concurrent_probe.py",
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validation["beforeContentHash"],
            },
        )
        assert not stale.get("ok"), stale
        assert stale["error"]["string_code"] == "stale_content"
        rev_after = send_rpc(sock, token, "workspace.revision", {})["result"]["revisionId"]
        assert rev_after == rev_before
    finally:
        if os.path.exists(target):
            os.remove(target)


def test_live_batch_one_stale_file(sock: socket.socket, token: str, workspace_root: str) -> None:
    files = ["harness_batch_ok.py", "harness_batch_stale.py"]
    try:
        for name in files:
            with open(os.path.join(workspace_root, name), "w", encoding="utf-8") as handle:
                handle.write("x = 1\n")
        patches = []
        for name in files:
            patch = f"--- {name}\n+++ {name}\n@@ -1 +1 @@\n-x = 1\n+x = 2\n"
            validated = send_rpc(sock, token, "patch.validate", {"path": name, "patch": patch})
            patches.append({
                "path": name,
                "patch": patch,
                "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            })
        with open(os.path.join(workspace_root, files[1]), "w", encoding="utf-8") as handle:
            handle.write("x = 99\n")
        batch = send_rpc(sock, token, "patch.applyBatch", {"patches": patches, "dryRun": False, "confirm": True})
        assert not batch.get("ok"), batch
        assert batch["error"]["string_code"] == "stale_content"
        with open(os.path.join(workspace_root, files[0]), encoding="utf-8") as handle:
            assert handle.read() == "x = 1\n"
    finally:
        for name in files:
            path = os.path.join(workspace_root, name)
            if os.path.exists(path):
                os.remove(path)


def test_offline_transport_disconnect() -> None:
    from harness_support import socketpair_drop_after_request

    client_sock, thread = socketpair_drop_after_request({})
    try:
        client_sock.settimeout(1.0)
        try:
            send_rpc(client_sock, "token", "rpc.ping", request_timeout=0.5)
            raised = False
        except (DietCodeTransportError, TimeoutError, OSError):
            raised = True
        assert raised
    finally:
        client_sock.close()
        thread.join(timeout=2.0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass IV harness realism regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("harness.search_files_golden", test_offline_search_files_golden_fixture),
        ("harness.symlink_policy_fixture", test_offline_symlink_policy_fixture),
        ("harness.transport_disconnect", test_offline_transport_disconnect),
    ]:
        recorder.run(name, fn)

    workspace_root: str | None = None
    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("harness.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("harness.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("harness_realism")

    readonly: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("harness.search_files_deterministic", test_live_search_files_deterministic),
        ("harness.search_files_stable_order", test_live_search_files_stable_order),
        ("harness.snapshot_completeness", test_live_snapshot_completeness),
        ("harness.symlink_escape", test_live_symlink_harness),
    ]
    for name, fn in readonly:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    if workspace_root:
        for name, fn in [
            ("harness.transport_idempotency", test_live_transport_idempotency_recovery),
            ("harness.concurrent_stale_write", test_live_concurrent_stale_write),
            ("harness.batch_stale_atomic", test_live_batch_one_stale_file),
        ]:
            def _run_mut(f: Callable = fn) -> None:
                with connect() as sock:
                    f(sock, load_token(), workspace_root)

            recorder.run(name, _run_mut)

    return recorder.finish("harness_realism")


if __name__ == "__main__":
    raise SystemExit(main())
