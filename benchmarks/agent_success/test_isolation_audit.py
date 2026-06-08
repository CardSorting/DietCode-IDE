#!/usr/bin/env python3
"""Workspace isolation audit — per-task clean state (Playwright-style contexts)."""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from mutation_trace import write_mutation_trace  # noqa: E402
from run_benchmark import WORKSPACES_DIR, copy_task_workspace  # noqa: E402
from workspace_integrity import hash_workspace, volatile_skip  # noqa: E402


class IsolationAuditTest(unittest.TestCase):
    def test_sidecars_from_053_do_not_appear_in_054(self) -> None:
        if not (BENCHMARK_ROOT / "tasks" / "task_053").is_dir():
            self.skipTest("task_053 fixture missing")
        ws053 = copy_task_workspace("task_053")
        try:
            (ws053 / "src" / "runtime.py.bak").parent.mkdir(parents=True, exist_ok=True)
            (ws053 / "src" / "runtime.py.bak").write_text("sidecar", encoding="utf-8")
            (ws053 / ".cache").mkdir(exist_ok=True)
            (ws053 / ".cache" / "agent_tmp.json").write_text("{}", encoding="utf-8")

            ws054 = copy_task_workspace("task_054")
            try:
                self.assertFalse((ws054 / "src" / "runtime.py.bak").exists())
                self.assertFalse((ws054 / ".cache" / "agent_tmp.json").exists())
            finally:
                if WORKSPACES_DIR in ws054.parents:
                    shutil.rmtree(ws054, ignore_errors=True)
        finally:
            if WORKSPACES_DIR in ws053.parents:
                shutil.rmtree(ws053, ignore_errors=True)

    def test_pycache_does_not_affect_hashes(self) -> None:
        if not (BENCHMARK_ROOT / "tasks" / "task_001").is_dir():
            self.skipTest("task_001 fixture missing")
        ws = copy_task_workspace("task_001")
        try:
            before = hash_workspace(ws)
            cache = ws / "pkg" / "__pycache__"
            cache.mkdir(parents=True, exist_ok=True)
            (cache / "mod.cpython-313.pyc").write_bytes(b"\x00\x01")
            after = hash_workspace(ws)
            self.assertEqual(before, after)
            self.assertTrue(volatile_skip(cache / "mod.cpython-313.pyc"))
        finally:
            shutil.rmtree(ws, ignore_errors=True)

    def test_trace_files_outside_task_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import workspace_integrity as wi

            wi.TRACES_DIR = Path(tmp) / "traces"
            traces_root = wi.TRACES_DIR
            ws = Path(tmp) / "workspace"
            ws.mkdir()
            (ws / "main.py").write_text("x", encoding="utf-8")
            path = write_mutation_trace(
                "iso_run",
                "task_001",
                {"taskId": "task_001", "steps": [{"attempt": 1}]},
                workspace=ws,
            )
            self.assertNotIn(path, list(ws.rglob("*")))
            self.assertIn(traces_root.resolve(), path.resolve().parents)

    def test_generated_artifacts_do_not_leak_between_runs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            import workspace_integrity as wi

            wi.TRACES_DIR = Path(tmp) / "traces"
            traces_root = wi.TRACES_DIR
            run_a = traces_root / "run_a"
            run_b = traces_root / "run_b"
            write_mutation_trace("run_a", "task_052", {"taskId": "task_052", "steps": []})
            self.assertFalse((run_b / "task_052.mutation_trace.json").exists())
            self.assertTrue((run_a / "task_052.mutation_trace.json").exists())


if __name__ == "__main__":
    raise SystemExit(unittest.main())
