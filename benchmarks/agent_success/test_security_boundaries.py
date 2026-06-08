#!/usr/bin/env python3
"""Security boundary audit for trace output and workspace hashing."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from agent_input_manifest import assert_external_agent_jail, build_agent_input_manifest  # noqa: E402
from contracts import contracts_allow  # noqa: E402
from mutation_trace import write_mutation_trace  # noqa: E402
from workspace_integrity import (  # noqa: E402
    assert_trace_outside_workspace,
    hash_workspace,
    resolve_trace_path,
    validate_run_id,
    volatile_skip,
)


class SecurityBoundaryTest(unittest.TestCase):
    def test_no_trace_writes_inside_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp) / "workspace"
            ws.mkdir()
            trace = ws / "task_001.mutation_trace.json"
            with self.assertRaises(ValueError):
                assert_trace_outside_workspace(trace, ws)

    def test_path_traversal_in_trace_output_rejected(self) -> None:
        with self.assertRaises(ValueError):
            validate_run_id("../escape")
        with self.assertRaises(ValueError):
            resolve_trace_path("ok_run", "not_a_task")

    def test_workspace_hash_excludes_volatile_dirs_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp) / "ws"
            ws.mkdir()
            (ws / "main.py").write_text("a", encoding="utf-8")
            (ws / ".agent_patches").mkdir()
            (ws / ".agent_patches" / "x.patch").write_text("p", encoding="utf-8")
            h1 = hash_workspace(ws)
            (ws / "main.py").write_text("b", encoding="utf-8")
            h2 = hash_workspace(ws)
            self.assertNotEqual(h1, h2)
            self.assertTrue(volatile_skip(ws / ".agent_patches" / "x.patch"))

    def test_destructive_commands_denied_by_policy(self) -> None:
        visible = {"readme", "verify_grep", "destructive_policy"}
        self.assertTrue(contracts_allow(visible, "destructive_policy"))

    def test_external_agent_manifest_denies_metadata(self) -> None:
        manifest = build_agent_input_manifest(external=True, profile="grep_only")
        self.assertFalse(manifest["metadataJson"])
        self.assertFalse(manifest["expectedPatch"])
        self.assertFalse(manifest["priorTrace"])

    def test_external_argv_jail(self) -> None:
        cmd = ["python3", "agent.py", "--workspace", "/tmp/ws", "--task", "task_001"]
        self.assertEqual(assert_external_agent_jail(cmd), [])

    def test_symlink_target_outside_workspace_not_in_hash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp) / "ws"
            outside = Path(tmp) / "outside"
            outside.mkdir()
            ws.mkdir()
            (outside / "secret.txt").write_text("secret", encoding="utf-8")
            (ws / "link.txt").symlink_to(outside / "secret.txt")
            digest = hash_workspace(ws)
            self.assertTrue(digest)
            # Hash includes symlink file node under workspace, not outside tree walk
            self.assertFalse(any("outside" in p.parts for p in ws.rglob("*") if p.is_file()))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
