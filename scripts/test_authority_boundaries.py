#!/usr/bin/env python3
"""
AUTHORITY: Pass XI — journal vs live authority boundary enforcement.

Grep: rg 'test_authority_boundaries|test-authority-boundaries' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import os
import uuid
from pathlib import Path

from agent_contracts import (
    JOURNAL_AUTHORITY_KEYS,
    validate_journal_authority_labels,
    validate_runtime_diagnostics,
    validate_runtime_timeline,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, connect, ensure_workspace_root, load_token, send_rpc

FIXTURES = REPO_ROOT / "scripts" / "fixtures" / "authority"


def test_offline_journal_authority_fixture() -> None:
    fixture = json.loads((FIXTURES / "journal_authority_labels.json").read_text(encoding="utf-8"))
    assert not validate_journal_authority_labels(fixture)
    assert fixture["notCurrentFileTruth"] is True


def test_offline_bridge_recovery_fixture() -> None:
    fixture = json.loads((FIXTURES / "bridge_recovery_runtime_wins.json").read_text(encoding="utf-8"))
    assert fixture["recoverySource"] == "runtime"
    assert fixture["recoveryHint"] == fixture["runtimeHint"]


def test_live_runtime_surfaces_label_journal(sock, token: str) -> None:
    for method, params in (
        ("runtime.diagnostics", {}),
        ("runtime.timeline", {"limit": 5}),
        ("workspace.activity", {"limit": 5}),
        ("operation.status", {"idempotencyKey": "nonexistent-authority-probe"}),
    ):
        response = send_rpc(sock, token, method, params)
        assert response.get("ok"), response
        result = response["result"]
        assert not validate_journal_authority_labels(result), validate_journal_authority_labels(result)


def test_live_memory_surfaces_label_journal(sock, token: str) -> None:
    for method, params in (
        ("memory.revision.list", {"limit": 5}),
        ("memory.verify.latest", {"command": "verify-agent-runtime-full"}),
    ):
        response = send_rpc(sock, token, method, params)
        assert response.get("ok"), response
        assert not validate_journal_authority_labels(response["result"])


def test_replay_not_file_truth_after_external_drift(sock, token: str, workspace_root: str) -> None:
    rel = f"authority_drift_{uuid.uuid4().hex[:8]}.txt"
    abs_path = Path(workspace_root) / rel
    abs_path.write_text("before\n", encoding="utf-8")
    patch = f"--- {rel}\n+++ {rel}\n@@ -1 +1 @@\n-before\n+after\n"
    validated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": patch})
    assert validated.get("ok"), validated
    before_hash = validated["result"]["validation"]["beforeContentHash"]
    applied = send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel,
            "patch": patch,
            "expectBeforeHash": before_hash,
            "confirm": True,
            "idempotencyKey": f"authority-{uuid.uuid4().hex}",
        },
    )
    assert applied.get("ok"), applied
    idempotency_key = applied["result"].get("idempotencyKey") or applied["id"].split(":")[-1]

    abs_path.write_text("externally mutated\n", encoding="utf-8")

    timeline = send_rpc(sock, token, "runtime.timeline", {"limit": 20})
    assert timeline.get("ok"), timeline
    assert timeline["result"]["notCurrentFileTruth"] is True

    status = send_rpc(sock, token, "operation.status", {"idempotencyKey": idempotency_key})
    assert status.get("ok"), status
    assert status["result"]["notCurrentFileTruth"] is True

    stat = send_rpc(sock, token, "file.stat", {"path": rel})
    assert stat.get("ok"), stat
    assert stat["result"]["contentHash"] != before_hash

    stale_apply = send_rpc(
        sock,
        token,
        "patch.apply",
        {
            "path": rel,
            "patch": patch,
            "expectBeforeHash": before_hash,
            "confirm": True,
            "idempotencyKey": f"authority-stale-{uuid.uuid4().hex}",
        },
    )
    assert not stale_apply.get("ok"), stale_apply
    assert stale_apply.get("error", {}).get("string_code") == "stale_content"

    try:
        abs_path.unlink()
    except FileNotFoundError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass XI authority boundary tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("authority.offline.journal_fixture", test_offline_journal_authority_fixture),
        ("authority.offline.bridge_recovery_fixture", test_offline_bridge_recovery_fixture),
    ]:
        recorder.run(name, fn)

    sock = connect()
    token = load_token()
    workspace_root = ensure_workspace_root(sock, token)

    for name, fn in [
        ("authority.live.runtime_labels", lambda: test_live_runtime_surfaces_label_journal(sock, token)),
        ("authority.live.memory_labels", lambda: test_live_memory_surfaces_label_journal(sock, token)),
        (
            "authority.live.replay_not_file_truth",
            lambda: test_replay_not_file_truth_after_external_drift(sock, token, workspace_root),
        ),
    ]:
        recorder.run(name, fn)

    return recorder.finish("authority_boundaries")


if __name__ == "__main__":
    raise SystemExit(main())
