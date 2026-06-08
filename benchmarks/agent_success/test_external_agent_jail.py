#!/usr/bin/env python3
"""External-agent honesty audit — jail surface for third-party agents."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from agent_driver import _run_external_agent  # noqa: E402
from agent_input_manifest import (  # noqa: E402
    assert_external_agent_jail,
    assert_task_tree_not_in_agent_env,
    build_agent_input_manifest,
    external_agent_cli_args,
)


class ExternalAgentJailTest(unittest.TestCase):
    def test_external_manifest_denies_harness_secrets(self) -> None:
        m = build_agent_input_manifest(external=True, profile="grep_only")
        self.assertTrue(m["readme"])
        self.assertTrue(m["verifySh"])
        for forbidden in ("metadataJson", "expectedPatch", "priorTrace", "trapType", "mcsReference"):
            self.assertFalse(m[forbidden], forbidden)

    def test_builtin_orchestrated_manifest(self) -> None:
        m = build_agent_input_manifest(external=False, profile="orchestrated")
        self.assertFalse(m["metadataJson"])
        self.assertFalse(m["expectedPatch"])

    def test_cli_args_surface(self) -> None:
        ws = Path("/tmp/ws")
        args = external_agent_cli_args(ws, "task_001", "bridge", Path("agent.py"))
        self.assertIn("--workspace", args)
        self.assertIn("--task", args)
        self.assertNotIn("metadata.json", " ".join(args))

    def test_external_subprocess_argv_jail(self) -> None:
        with mock.patch("agent_driver.subprocess.run") as run:
            run.return_value.returncode = 0
            ws = BENCHMARK_ROOT / "tasks" / "task_001" / "before"
            if not ws.is_dir():
                self.skipTest("task_001 missing")
            script = BENCHMARK_ROOT / "tasks" / "task_001" / "verify.sh"
            with mock.patch.dict(os.environ, {"AGENT_BENCHMARK_AGENT_SCRIPT": str(script)}):
                from agent_driver import run_agent_task
                from run_benchmark import RunMetrics, WorkflowContext

                ctx = WorkflowContext(
                    workspace=ws,
                    meta={},
                    patch="",
                    metrics=RunMetrics(task_id="task_001", mode="bridge"),
                )
                try:
                    run_agent_task(ws, "task_001", "bridge", ctx, profile="grep_only")
                except RuntimeError:
                    pass
                cmd = run.call_args[0][0]
                violations = assert_external_agent_jail(cmd)
                self.assertEqual(violations, [])

    def test_env_must_not_leak_task_metadata(self) -> None:
        env = {"WORKSPACE_ROOT": "/tmp/ws", "HOME": "/home/user"}
        violations = assert_task_tree_not_in_agent_env("task_052", env)
        self.assertEqual(violations, [])
        bad = {
            "HINT": str(BENCHMARK_ROOT / "tasks" / "task_052" / "metadata.json"),
        }
        self.assertTrue(assert_task_tree_not_in_agent_env("task_052", bad))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
