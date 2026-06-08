#!/usr/bin/env python3
"""
INVARIANT: Pass VIII — native runtime integration (timeline, identity, continuity, diagnostics parity).

Grep: rg 'test_runtime_native_integration|test-runtime-native-integration' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import uuid
from collections.abc import Callable

from agent_contracts import (
    MEMORY_SAFETY_BOUNDARY_FORBIDDEN_AUTHORITY,
    RUNTIME_OPERATION_IDENTITY_KEYS,
    RUNTIME_RPC_METHODS,
    validate_memory_operation,
    validate_runtime_diagnostics,
    validate_runtime_operation_identity,
    validate_runtime_timeline,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "runtime")


def test_offline_runtime_rpc_contract_frozen() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "runtime_rpc_methods.json"), encoding="utf-8"))
    assert set(fixture["methods"]) == set(RUNTIME_RPC_METHODS)
    assert fixture["recordAuthority"] == "runtime_journal"
    assert fixture["mutationAuthority"] == "cpp_kernel"


def test_offline_operation_identity_fixture() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "operation_identity_golden.json"), encoding="utf-8"))
    assert set(fixture["correlation"].keys()) == set(RUNTIME_OPERATION_IDENTITY_KEYS)
    assert not validate_runtime_operation_identity(fixture["correlation"])


def test_offline_timeline_event_fixture() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "timeline_event_golden.json"), encoding="utf-8"))
    assert fixture["mode"] == "runtime_timeline_event"
    assert fixture["eventType"] in ("mutation_applied", "revision_recorded", "error_recorded")


def test_offline_startup_continuity_fixture() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "startup_continuity_golden.json"), encoding="utf-8"))
    assert "lastKnownRevision" in fixture["startup"]
    assert "replayCacheRestoredCount" in fixture["startup"]


def test_live_runtime_diagnostics_parity(sock, token: str) -> None:
    for method in ("runtime.diagnostics", "memory.status"):
        response = send_rpc(sock, token, method, {})
        assert response.get("ok"), response
        errors = validate_runtime_diagnostics(response["result"])
        assert not errors, errors
        for forbidden in MEMORY_SAFETY_BOUNDARY_FORBIDDEN_AUTHORITY:
            assert forbidden not in response["result"]


def test_live_runtime_timeline(sock, token: str) -> None:
    response = send_rpc(sock, token, "runtime.timeline", {"limit": 10, "compact": True})
    assert response.get("ok"), response
    errors = validate_runtime_timeline(response["result"])
    assert not errors, errors
    assert response["result"]["sortOrder"] == "timestamp_desc"


def test_live_workspace_activity(sock, token: str) -> None:
    response = send_rpc(sock, token, "workspace.activity", {"limit": 5})
    assert response.get("ok"), response
    assert response["result"]["mode"] == "runtime_timeline"


def test_live_timeline_errors_only(sock, token: str) -> None:
    stale = send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": "scripts/agent_contracts.py",
            "patch": "--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y\n",
            "expectBeforeHash": "deadbeef00000000",
            "confirm": True,
            "dryRun": False,
        },
    )
    assert stale.get("ok") is False
    response = send_rpc(sock, token, "runtime.timeline", {"errorsOnly": True, "limit": 10})
    assert response.get("ok"), response
    assert response["result"]["errorsOnly"] is True
    if response["result"].get("events"):
        assert response["result"]["events"][0].get("stringCode")


def test_live_operation_correlation(sock, token: str) -> None:
    key = f"native-{uuid.uuid4().hex}"
    rel_path = "scripts/agent_contracts.py"
    before = send_rpc(sock, token, "file.read", {"path": rel_path})
    assert before.get("ok"), before
    text = before["result"]["text"]
    patch = (
        f"--- a/{rel_path}\n+++ b/{rel_path}\n"
        f"@@ -1,1 +1,2 @@\n"
        f"-{text.splitlines()[0]}\n"
        f"+{text.splitlines()[0]}\n"
        f"+# pass-viii-native\n"
    )
    validated = send_rpc(sock, token, "patch.validate", {"path": rel_path, "patch": patch})
    assert validated.get("ok"), validated
    applied = send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel_path,
            "patch": patch,
            "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            "confirm": True,
            "dryRun": False,
            "idempotencyKey": key,
        },
    )
    assert applied.get("ok"), applied

    correlate = send_rpc(sock, token, "runtime.correlate", {"idempotencyKey": key})
    assert correlate.get("ok"), correlate
    identity = correlate["result"].get("correlation", {})
    assert not validate_runtime_operation_identity(identity)

    timeline = send_rpc(sock, token, "runtime.timeline", {"sinceRevision": 1, "limit": 20})
    assert timeline.get("ok"), timeline

    compact = send_rpc(sock, token, "runtime.operation.recent", {"limit": 5, "compact": True})
    assert compact.get("ok"), compact
    assert compact["result"]["mode"] == "runtime_operation_summary"

    revert = (
        f"--- a/{rel_path}\n+++ b/{rel_path}\n"
        f"@@ -1,3 +1,2 @@\n"
        f"-{text.splitlines()[0]}\n"
        f"-# pass-viii-native\n"
        f"+{text.splitlines()[0]}\n"
    )
    rev_val = send_rpc(sock, token, "patch.validate", {"path": rel_path, "patch": revert})
    send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel_path,
            "patch": revert,
            "expectBeforeHash": rev_val["result"]["validation"]["beforeContentHash"],
            "confirm": True,
            "dryRun": False,
        },
    )


def test_live_progress_diagnostics_consistency(sock, token: str) -> None:
    diag = send_rpc(sock, token, "runtime.diagnostics", {})
    assert diag.get("ok"), diag
    assert "complete" in diag["result"]
    assert "warnings" in diag["result"]
    assert "nextRecommendedCommand" in diag["result"]
    timeline = send_rpc(sock, token, "runtime.timeline", {"limit": 3})
    assert timeline.get("ok"), timeline
    for key in ("complete", "partial", "warnings", "nextRecommendedCommand"):
        assert key in timeline["result"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass VIII native runtime integration tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("offline_runtime_rpc_contract_frozen", test_offline_runtime_rpc_contract_frozen),
        ("offline_operation_identity_fixture", test_offline_operation_identity_fixture),
        ("offline_timeline_event_fixture", test_offline_timeline_event_fixture),
        ("offline_startup_continuity_fixture", test_offline_startup_continuity_fixture),
    ]
    for name, fn in offline:
        recorder.run(name, fn)

    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("live.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("live.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("test_runtime_native_integration")

    live: list[tuple[str, Callable]] = [
        ("live_runtime_diagnostics_parity", test_live_runtime_diagnostics_parity),
        ("live_runtime_timeline", test_live_runtime_timeline),
        ("live_workspace_activity", test_live_workspace_activity),
        ("live_timeline_errors_only", test_live_timeline_errors_only),
        ("live_operation_correlation", test_live_operation_correlation),
        ("live_progress_diagnostics_consistency", test_live_progress_diagnostics_consistency),
    ]
    for name, fn in live:
        def _run(f: Callable = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    return recorder.finish("test_runtime_native_integration")


if __name__ == "__main__":
    raise SystemExit(main())
