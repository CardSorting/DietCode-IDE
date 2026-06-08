#!/usr/bin/env python3
"""Tests for Phase 4 release gates and mutation traces."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contract_ladder import NIGHTMARE_TASKS  # noqa: E402
from mutation_trace import (  # noqa: E402
    MutationTraceRecorder,
    build_mutation_trace,
    write_mutation_trace,
)
from release_check import validate_release_gates  # noqa: E402


def _orch_row(task_id: str, **extra: object) -> dict:
    base = {
        "type": "task_result",
        "taskId": task_id,
        "executor": "agent",
        "mode": "bridge",
        "taskSuccess": True,
        "verifyPassed": True,
        "wrongFileEdited": False,
        "apiShapeChanged": False,
        "destructiveCommandBlocked": task_id == "task_060",
        "minimumContractSet": ["readme", "verify_grep"],
        "executionProtocolPath": ["single_shot_patch"],
        "contractEscalationPath": [],
    }
    base.update(extra)
    return base


class MutationTraceTest(unittest.TestCase):
    def test_build_trace_shape(self) -> None:
        rec = MutationTraceRecorder()
        rec.record(
            attempt=1,
            contracts=["readme", "verify_grep"],
            protocol="single_shot_patch",
            result="fail",
            failure_class="behavior_check_failed",
        )
        rec.record(
            attempt=2,
            contracts=["readme", "verify_grep", "behavior_check"],
            protocol="semantic_repair_loop",
            result="pass",
        )
        trace = build_mutation_trace(
            task_id="task_059",
            run_id="test_run",
            mode="bridge",
            recorder=rec,
            metrics_json=_orch_row(
                "task_059",
                executionProtocolPath=["single_shot_patch", "semantic_repair_loop"],
            ),
            succeeded=True,
        )
        self.assertEqual(trace["taskId"], "task_059")
        self.assertEqual(len(trace["steps"]), 2)
        self.assertEqual(trace["steps"][0]["failureClass"], "behavior_check_failed")
        self.assertTrue(trace["finalState"]["passed"])

    def test_write_trace_file(self) -> None:
        import mutation_trace as mt

        with tempfile.TemporaryDirectory() as tmp:
            mt.TRACES_DIR = Path(tmp)
            path = write_mutation_trace("run1", "task_052", {"taskId": "task_052", "steps": []})
            self.assertTrue(path.is_file())


class ReleaseGatesTest(unittest.TestCase):
    def _make_passing_set(self) -> tuple[list[dict], list[dict], str]:
        ref = [_orch_row(t, executor="reference") for t in NIGHTMARE_TASKS]
        orch = []
        for t in NIGHTMARE_TASKS:
            extra: dict = {}
            if t == "task_052":
                extra = {
                    "minimumContractSet": ["readme", "verify_grep", "hidden_invariant"],
                    "contractEscalationPath": [{"grantedContract": "hidden_invariant"}],
                }
            elif t == "task_057":
                extra = {"executionProtocolPath": ["single_shot_patch", "lock_read_validate_apply"]}
            elif t == "task_059":
                extra = {"executionProtocolPath": ["single_shot_patch", "semantic_repair_loop"]}
            elif t == "task_060":
                extra = {"destructiveCommandBlocked": True}
            orch.append(_orch_row(t, **extra))
        return ref, orch, "gate_test"

    def test_gates_pass_with_fixtures(self) -> None:
        import mutation_trace as mt

        ref, orch, run_id = self._make_passing_set()
        with tempfile.TemporaryDirectory() as tmp:
            mt.TRACES_DIR = Path(tmp) / "traces"
            for t in NIGHTMARE_TASKS:
                trace = {"taskId": t, "steps": [{"attempt": 1, "result": "pass"}]}
                write_mutation_trace(run_id, t, trace)
            violations = validate_release_gates(
                reference_rows=ref,
                orchestrated_rows=orch,
                run_id=run_id,
            )
        self.assertEqual(violations, [])

    def test_gates_fail_missing_escalation(self) -> None:
        import mutation_trace as mt

        ref, orch, run_id = self._make_passing_set()
        orch = [r for r in orch if r["taskId"] != "task_057"]
        orch.append(_orch_row("task_057", executionProtocolPath=["single_shot_patch"]))
        with tempfile.TemporaryDirectory() as tmp:
            mt.TRACES_DIR = Path(tmp) / "traces"
            for t in NIGHTMARE_TASKS:
                write_mutation_trace(run_id, t, {"taskId": t, "steps": [{"attempt": 1}]})
            violations = validate_release_gates(
                reference_rows=ref,
                orchestrated_rows=orch,
                run_id=run_id,
            )
        self.assertTrue(any("task_057" in v for v in violations))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
