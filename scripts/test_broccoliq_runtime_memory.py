#!/usr/bin/env python3
"""
INVARIANT: BroccoliQ native runtime memory layer — durable operations, replay, revisions, workflows, verification.

Grep: rg 'test_broccoliq_runtime_memory|test-broccoliq-runtime-memory' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import uuid
from collections.abc import Callable

from agent_contracts import (
    MEMORY_RPC_METHODS,
    MEMORY_SAFETY_BOUNDARY_FORBIDDEN_AUTHORITY,
    validate_memory_operation,
    validate_memory_revision,
    validate_memory_verification,
    validate_memory_workflow,
    validate_mutation_receipt,
    validate_runtime_diagnostics,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from agent_tooling import stable_hash_for_string
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "memory")


def test_offline_memory_rpc_contract_frozen() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "memory_rpc_methods.json"), encoding="utf-8"))
    assert set(fixture["methods"]) == set(MEMORY_RPC_METHODS)
    assert fixture["mutationAuthority"] == "cpp_kernel"
    assert fixture["recordAuthority"] == "runtime_journal"


def test_offline_safety_boundary_no_mutation_authority() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "safety_boundary.json"), encoding="utf-8"))
    forbidden = set(fixture["forbiddenAuthority"])
    assert forbidden == set(MEMORY_SAFETY_BOUNDARY_FORBIDDEN_AUTHORITY)
    assert fixture["mutationKernelRemainsAuthoritative"] is True


def test_offline_schema_tables_present() -> None:
    schema_path = os.path.join(os.path.dirname(__file__), "..", "runtime", "memory", "runtime_memory_schema.sql")
    sql = open(schema_path, encoding="utf-8").read()
    for table in (
        "runtime_operations",
        "runtime_replay_cache",
        "runtime_revisions",
        "runtime_workflows",
        "runtime_workflow_steps",
        "runtime_verification_runs",
        "runtime_telemetry_events",
        "runtime_error_events",
        "runtime_checkpoint",
    ):
        assert f"CREATE TABLE IF NOT EXISTS {table}" in sql


def test_offline_replay_fixture_shape() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "replay_after_restart.json"), encoding="utf-8"))
    assert fixture["idempotencyKey"]
    assert fixture["retained"] is True
    assert "mutationReceipt" in fixture["result"]


def test_offline_expired_replay_fixture() -> None:
    fixture = json.load(open(os.path.join(FIXTURES_DIR, "expired_replay_cache.json"), encoding="utf-8"))
    assert fixture["expired"] is True
    assert fixture["recoveryHint"]
    assert fixture["nextRecommendedCommand"] == "patch.validate"


def test_live_memory_status(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "memory.status", {})
    assert response.get("ok"), response
    errors = validate_runtime_diagnostics(response["result"])
    assert not errors, errors
    assert response["result"]["mutationAuthority"] == "cpp_kernel"
    assert response["result"]["recordAuthority"] == "runtime_journal"


def test_live_operation_persistence(sock: socket.socket, token: str) -> None:
    key = f"broccoliq-{uuid.uuid4().hex}"
    rel_path = "scripts/agent_contracts.py"
    before = send_rpc(sock, token, "file.read", {"path": rel_path})
    assert before.get("ok"), before
    text = before["result"]["text"]
    patch = (
        f"--- a/{rel_path}\n+++ b/{rel_path}\n"
        f"@@ -1,1 +1,2 @@\n"
        f"-{text.splitlines()[0]}\n"
        f"+{text.splitlines()[0]}\n"
        f"+# broccoliq-memory-test\n"
    )
    validated = send_rpc(sock, token, "patch.validate", {"path": rel_path, "patch": patch})
    assert validated.get("ok"), validated
    before_hash = validated["result"]["validation"]["beforeContentHash"]
    applied = send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel_path,
            "patch": patch,
            "expectBeforeHash": before_hash,
            "confirm": True,
            "dryRun": False,
            "idempotencyKey": key,
        },
    )
    assert applied.get("ok"), applied
    errors = validate_mutation_receipt(applied["result"]["mutationReceipt"])
    assert not errors, errors

    mem_op = send_rpc(sock, token, "memory.operation.findByIdempotencyKey", {"idempotencyKey": key})
    assert mem_op.get("ok"), mem_op
    if mem_op["result"].get("status") != "unknown":
        op_errors = validate_memory_operation(mem_op["result"])
        assert not op_errors, op_errors
        assert mem_op["result"]["method"] == "patch.apply"

    revert_patch = (
        f"--- a/{rel_path}\n+++ b/{rel_path}\n"
        f"@@ -1,3 +1,2 @@\n"
        f"-{text.splitlines()[0]}\n"
        f"-# broccoliq-memory-test\n"
        f"+{text.splitlines()[0]}\n"
    )
    rev_val = send_rpc(sock, token, "patch.validate", {"path": rel_path, "patch": revert_patch})
    send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel_path,
            "patch": revert_patch,
            "expectBeforeHash": rev_val["result"]["validation"]["beforeContentHash"],
            "confirm": True,
            "dryRun": False,
        },
    )


def test_live_replay_after_operation_status(sock: socket.socket, token: str) -> None:
    key = f"replay-{uuid.uuid4().hex}"
    status = send_rpc(sock, token, "operation.status", {"idempotencyKey": key})
    assert status.get("ok"), status
    assert status["result"]["status"] == "unknown"


def test_live_revision_journal(sock: socket.socket, token: str) -> None:
    mem_rev = send_rpc(sock, token, "memory.revision.lastMutation", {})
    assert mem_rev.get("ok"), mem_rev
    if mem_rev["result"].get("revisionId"):
        errors = validate_memory_revision(mem_rev["result"])
        assert not errors, errors
    list_rev = send_rpc(sock, token, "memory.revision.list", {"limit": 5})
    assert list_rev.get("ok"), list_rev
    assert isinstance(list_rev["result"]["revisions"], list)


def test_live_workflow_resume_path(sock: socket.socket, token: str) -> None:
    started = send_rpc(
        sock,
        token,
        "memory.workflow.start",
        {"agentId": "test-agent", "workflowId": f"wf-{uuid.uuid4().hex}"},
    )
    assert started.get("ok"), started
    errors = validate_memory_workflow(started["result"])
    assert not errors, errors
    workflow_id = started["result"]["workflowId"]
    stepped = send_rpc(
        sock,
        token,
        "memory.workflow.step",
        {
            "workflowId": workflow_id,
            "command": "search.literal",
            "status": "completed",
            "inputHash": stable_hash_for_string("query"),
            "outputHash": stable_hash_for_string("results"),
            "nextRecommendedCommand": "patch.validate",
        },
    )
    assert stepped.get("ok"), stepped
    completed = send_rpc(sock, token, "memory.workflow.complete", {"workflowId": workflow_id})
    assert completed.get("ok"), completed
    fetched = send_rpc(sock, token, "memory.workflow.get", {"workflowId": workflow_id})
    assert fetched.get("ok"), fetched
    assert fetched["result"]["status"] == "completed"


def test_live_verification_history(sock: socket.socket, token: str) -> None:
    recorded = send_rpc(
        sock,
        token,
        "memory.verify.record",
        {
            "command": "verify-agent-runtime-full",
            "suiteName": "broccoliq-runtime-memory",
            "passedCount": 8,
            "failedCount": 0,
            "durationMs": 1200.0,
        },
    )
    assert recorded.get("ok"), recorded
    latest = send_rpc(sock, token, "memory.verify.latest", {"command": "verify-agent-runtime-full"})
    assert latest.get("ok"), latest
    if latest["result"].get("runId"):
        errors = validate_memory_verification(latest["result"])
        assert not errors, errors
    history = send_rpc(sock, token, "memory.verify.history", {"command": "verify-agent-runtime-full", "limit": 5})
    assert history.get("ok"), history
    assert isinstance(history["result"]["runs"], list)


def test_live_no_mutation_authority_leakage(sock: socket.socket, token: str) -> None:
    status = send_rpc(sock, token, "memory.status", {})
    assert status.get("ok"), status
    result = status["result"]
    for forbidden in MEMORY_SAFETY_BOUNDARY_FORBIDDEN_AUTHORITY:
        assert forbidden not in result
    assert result["mutationAuthority"] == "cpp_kernel"
    assert result["recordAuthority"] == "runtime_journal"


def main() -> int:
    parser = argparse.ArgumentParser(description="BroccoliQ runtime memory integration tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("offline_memory_rpc_contract_frozen", test_offline_memory_rpc_contract_frozen),
        ("offline_safety_boundary_no_mutation_authority", test_offline_safety_boundary_no_mutation_authority),
        ("offline_schema_tables_present", test_offline_schema_tables_present),
        ("offline_replay_fixture_shape", test_offline_replay_fixture_shape),
        ("offline_expired_replay_fixture", test_offline_expired_replay_fixture),
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
        return recorder.finish("test_broccoliq_runtime_memory")

    live: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("live_memory_status", test_live_memory_status),
        ("live_operation_persistence", test_live_operation_persistence),
        ("live_replay_after_operation_status", test_live_replay_after_operation_status),
        ("live_revision_journal", test_live_revision_journal),
        ("live_workflow_resume_path", test_live_workflow_resume_path),
        ("live_verification_history", test_live_verification_history),
        ("live_no_mutation_authority_leakage", test_live_no_mutation_authority_leakage),
    ]

    for name, fn in live:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    return recorder.finish("test_broccoliq_runtime_memory")


if __name__ == "__main__":
    raise SystemExit(main())
