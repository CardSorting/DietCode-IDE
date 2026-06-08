#!/usr/bin/env python3
"""
CLOSURE: Pass VI remaining gaps — batch/snapshot/diff partial-success parity.

Grep: rg 'test_partial_success_closure|partial_success_closure' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import socket
import uuid
from collections.abc import Callable
from pathlib import Path

from agent_contracts import (
    INTERNAL_METHOD_NAMESPACES,
    validate_diff_hunks_response,
    validate_patch_apply_batch_success,
    validate_tool_capabilities_response,
    validate_workspace_snapshot,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = REPO_ROOT / "scripts" / "fixtures" / "release"
MULTI_HUNK_PATCH = """\
--- closure_a.py
+++ closure_a.py
@@ -1,2 +1,3 @@
 # a
+line2
 value = 1
--- closure_b.py
+++ closure_b.py
@@ -1,2 +1,3 @@
 # b
+line2
 value = 1
"""


def test_offline_internal_namespaces_fixture() -> None:
    fixture = json.loads((FIXTURES_DIR / "internal_method_namespaces.json").read_text(encoding="utf-8"))
    assert fixture["internalNamespaces"] == list(INTERNAL_METHOD_NAMESPACES)


def test_live_batch_apply_complete(sock: socket.socket, token: str, workspace_root: str) -> None:
    files = ["closure_batch_a.py", "closure_batch_b.py"]
    try:
        for name in files:
            Path(workspace_root, name).write_text(f"# {name}\nvalue = 1\n", encoding="utf-8")
        patches = []
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
            patches.append(
                {
                    "path": name,
                    "patch": patch,
                    "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
                }
            )
        applied = send_rpc(
            sock,
            token,
            "patch.applyBatch",
            {"patches": patches, "dryRun": False, "confirm": True, "idempotencyKey": f"closure-{uuid.uuid4().hex}"},
        )
        assert applied.get("ok"), applied
        result = applied["result"]
        errors = validate_patch_apply_batch_success(result)
        assert not errors, errors
        assert result["complete"] is True
        assert result["partial"] is False
        assert result["nextRecommendedCommand"] == "workspace.revision"
    finally:
        for name in files:
            path = Path(workspace_root) / name
            if path.exists():
                path.unlink()


def test_live_snapshot_truncated(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "workspace.snapshot",
        {
            "snapshotMode": "explicit_paths",
            "paths": ["scripts/agent_contracts.py", "scripts/dietcode_agent_client.py", "Makefile"],
            "maxFiles": 1,
        },
    )
    assert response.get("ok"), response
    result = response["result"]
    errors = validate_workspace_snapshot(result)
    assert not errors, errors
    assert result["truncated"] is True
    assert result["complete"] is False
    assert result["partial"] is True
    assert "snapshot_truncated" in result.get("warnings", [])
    assert result["nextRecommendedCommand"] == "workspace.snapshot"


def test_live_diff_hunks_truncated(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "patch.hunks",
        {"patch": MULTI_HUNK_PATCH, "maxHunks": 1, "includeLines": True},
    )
    assert response.get("ok"), response
    result = response["result"]
    errors = validate_diff_hunks_response(result)
    assert not errors, errors
    assert result["totalHunks"] >= 2
    assert result["returnedHunks"] == 1
    assert result["complete"] is False
    assert result["partial"] is True
    assert result["hasMoreHunks"] is True
    assert result["nextRecommendedCommand"] == "patch.hunks"


def test_live_tool_capabilities_internal(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "tool.capabilities", {})
    assert response.get("ok"), response
    errors = validate_tool_capabilities_response(response["result"])
    assert not errors, errors
    internal = response["result"]["internalNamespaces"]
    assert "analysis." in internal
    assert "language." in internal
    registry = send_rpc(sock, token, "tool.registry", {})
    methods = {entry["method"] for entry in registry["result"]["tools"]}
    assert not any(m.startswith("analysis.") for m in methods)
    assert not any(m.startswith("language.") for m in methods)


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass VI partial-success closure tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    recorder.run("closure.internal_fixture", test_offline_internal_namespaces_fixture)

    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("closure.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("closure.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("partial_success_closure")

    for name, fn in [
        ("closure.batch_apply_complete", test_live_batch_apply_complete),
        ("closure.snapshot_truncated", test_live_snapshot_truncated),
        ("closure.diff_hunks_truncated", test_live_diff_hunks_truncated),
        ("closure.tool_capabilities_internal", test_live_tool_capabilities_internal),
    ]:
        def _run(f: Callable = fn) -> None:
            with connect() as sock:
                if f is test_live_snapshot_truncated or f is test_live_diff_hunks_truncated or f is test_live_tool_capabilities_internal:
                    f(sock, load_token())
                else:
                    f(sock, load_token(), workspace_root)

        recorder.run(name, _run)

    return recorder.finish("partial_success_closure")


if __name__ == "__main__":
    raise SystemExit(main())
