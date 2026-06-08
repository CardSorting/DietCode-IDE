#!/usr/bin/env python3
"""
WORKFLOW: Pass VI end-to-end agent workflow smoke tests (RPC + selective CLI).

Grep: rg 'test_agent_workflow_smoke|agent_workflow_smoke' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

from agent_contracts import (
    validate_mutation_receipt,
    validate_patch_validation,
    validate_search_literal_response,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, connect, ensure_workspace_root, load_token, send_rpc

CLIENT = [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py")]


def _write_probe(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def workflow_a_find_and_patch(sock: socket.socket, token: str, workspace_root: str) -> None:
    rel = "workflow_a_probe.py"
    target = Path(workspace_root) / rel
    _write_probe(target, "value = 1\n")
    try:
        search = send_rpc(sock, token, "search.literal", {"query": "workflow_a_probe", "maxResults": 5})
        assert search.get("ok"), search
        assert validate_search_literal_response(search["result"]) == []
        stat = send_rpc(sock, token, "file.stat", {"path": rel})
        assert stat.get("ok"), stat
        patch = (
            f"--- {rel}\n"
            f"+++ {rel}\n"
            "@@ -1 +1 @@\n"
            "-value = 1\n"
            "+value = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": patch})
        assert validated.get("ok"), validated
        validation = validated["result"]["validation"]
        assert validate_patch_validation(validation) == []
        assert validation["ok"] is True
        rev_before = send_rpc(sock, token, "workspace.revision", {})["result"]["revisionId"]
        applied = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": rel,
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validation["beforeContentHash"],
            },
        )
        assert applied.get("ok"), applied
        receipt = applied["result"]["mutationReceipt"]
        assert validate_mutation_receipt(receipt) == []
        rev_after = send_rpc(sock, token, "workspace.revision", {})["result"]["revisionId"]
        assert rev_after > rev_before
        assert applied["result"].get("complete") is True
        assert applied["result"].get("nextRecommendedCommand") == "workspace.revision"
    finally:
        if target.exists():
            target.unlink()


def workflow_b_stale_patch_recovery(sock: socket.socket, token: str, workspace_root: str) -> None:
    rel = "workflow_b_probe.py"
    target = Path(workspace_root) / rel
    _write_probe(target, "stale = 1\n")
    try:
        patch = (
            f"--- {rel}\n"
            f"+++ {rel}\n"
            "@@ -1 +1 @@\n"
            "-stale = 1\n"
            "+stale = 2\n"
        )
        validated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": patch})
        validation = validated["result"]["validation"]
        target.write_text("stale = 99\n", encoding="utf-8")
        stale = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": rel,
                "patch": patch,
                "confirm": True,
                "expectBeforeHash": validation["beforeContentHash"],
            },
        )
        assert stale.get("ok") is False, stale
        error = stale["error"]
        assert error["string_code"] == "stale_content"
        assert error.get("nextRecommendedCommand") == "patch.validate"
        corrected_patch = (
            f"--- {rel}\n"
            f"+++ {rel}\n"
            "@@ -1 +1 @@\n"
            "-stale = 99\n"
            "+stale = 2\n"
        )
        revalidated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": corrected_patch})
        assert revalidated.get("ok"), revalidated
        new_validation = revalidated["result"]["validation"]
        assert new_validation["ok"] is True
        applied = send_rpc(
            sock,
            token,
            "patch.apply",
            {
                "path": rel,
                "patch": corrected_patch,
                "confirm": True,
                "expectBeforeHash": new_validation["beforeContentHash"],
            },
        )
        assert applied.get("ok"), applied
        assert target.read_text(encoding="utf-8") == "stale = 2\n"
    finally:
        if target.exists():
            target.unlink()


def workflow_c_batch_rollback(sock: socket.socket, token: str, workspace_root: str) -> None:
    files = ["workflow_c_a.py", "workflow_c_b.py"]
    try:
        for rel in files:
            _write_probe(Path(workspace_root) / rel, f"# {rel}\nvalue = 1\n")
        patches = []
        for rel in files:
            patch = (
                f"--- {rel}\n"
                f"+++ {rel}\n"
                "@@ -1,2 +1,2 @@\n"
                f"-# {rel}\n"
                f"+# {rel} changed\n"
                " value = 1\n"
            )
            validated = send_rpc(sock, token, "patch.validate", {"path": rel, "patch": patch})
            assert validated.get("ok"), validated
            patches.append(
                {
                    "path": rel,
                    "patch": patch,
                    "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
                }
            )
        (Path(workspace_root) / files[1]).write_text("# workflow_c_b.py\nvalue = 99\n", encoding="utf-8")
        batch = send_rpc(sock, token, "patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
        assert batch.get("ok") is False, batch
        for rel in files:
            text = (Path(workspace_root) / rel).read_text(encoding="utf-8")
            assert "changed" not in text, rel
    finally:
        for rel in files:
            path = Path(workspace_root) / rel
            if path.exists():
                path.unlink()


def workflow_d_deprecated_recovery(sock: socket.socket, token: str) -> None:
    deprecated = send_rpc(sock, token, "search.semantic", {"query": "workflow"})
    assert deprecated.get("ok") is False, deprecated
    error = deprecated["error"]
    assert error["string_code"] == "semantic_disabled"
    assert error.get("nextRecommendedCommand") == "search.literal"
    replacement = send_rpc(
        sock,
        token,
        "search.literal",
        {"query": "workflow", "maxResults": 3, "include": ["scripts/*.py"]},
    )
    assert replacement.get("ok"), replacement
    assert validate_search_literal_response(replacement["result"]) == []


def workflow_a_cli_patch_summary(workspace_root: str) -> None:
    rel = "workflow_a_cli_probe.py"
    target = Path(workspace_root) / rel
    _write_probe(target, "cli = 1\n")
    patch_file = target.with_suffix(".patch")
    try:
        patch = (
            f"--- {rel}\n"
            f"+++ {rel}\n"
            "@@ -1 +1 @@\n"
            "-cli = 1\n"
            "+cli = 2\n"
        )
        patch_file.write_text(patch, encoding="utf-8")
        completed = subprocess.run(
            CLIENT + ["--no-start", "--patch-file", str(patch_file), "--path", rel, "--patch-summary", "--compact"],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        assert completed.returncode == 0, completed.stderr
        payload = json.loads(completed.stdout.strip().splitlines()[-1])
        assert payload.get("type") == "patch_validation_summary"
        assert payload.get("ok") is True
    finally:
        if target.exists():
            target.unlink()
        if patch_file.exists():
            patch_file.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass VI agent workflow smoke tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("workflow.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("workflow.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("agent_workflow_smoke")

    rpc_checks: list[tuple[str, Callable[[socket.socket, str, str], None]]] = [
        ("workflow.a_find_and_patch", workflow_a_find_and_patch),
        ("workflow.b_stale_recovery", workflow_b_stale_patch_recovery),
        ("workflow.c_batch_rollback", workflow_c_batch_rollback),
    ]

    for name, fn in rpc_checks:
        def _run(f: Callable[[socket.socket, str, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token(), workspace_root)

        recorder.run(name, _run)

    def run_d() -> None:
        with connect() as sock:
            workflow_d_deprecated_recovery(sock, load_token())

    recorder.run("workflow.d_deprecated_recovery", run_d)
    recorder.run("workflow.a_cli_patch_summary", lambda: workflow_a_cli_patch_summary(workspace_root))

    return recorder.finish("agent_workflow_smoke")


if __name__ == "__main__":
    raise SystemExit(main())
