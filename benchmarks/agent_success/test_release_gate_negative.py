#!/usr/bin/env python3
"""Negative release gate tests — prove gates fail when evidence is tampered."""

from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contract_ladder import NIGHTMARE_TASKS  # noqa: E402
from mutation_trace import build_mutation_trace, write_mutation_trace  # noqa: E402
from release_check import validate_release_gates  # noqa: E402
from test_release_gates import _orch_row  # noqa: E402


def _passing_bundle() -> tuple[list[dict], list[dict], str]:
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
    return ref, orch, "neg_test"


def _write_traces(run_id: str, traces_dir: Path, orch: list[dict]) -> None:
    import workspace_integrity as wi

    wi.TRACES_DIR = traces_dir
    for row in orch:
        tid = row["taskId"]
        trace = {
            "traceSchemaVersion": "1.0",
            "taskId": tid,
            "runId": run_id,
            "steps": [{"attempt": 1, "contracts": ["readme"], "protocol": "single_shot_patch", "result": "pass"}],
            "finalState": {
                "passed": True,
                "wrongFileEdited": False,
                "apiShapeChanged": False,
                "rollbackDirty": False,
                "destructiveAllowed": False,
            },
            "traceHash": "placeholder",
        }
        from mutation_trace import compute_trace_hash

        trace["traceHash"] = compute_trace_hash(trace)
        write_mutation_trace(run_id, tid, trace)


class NegativeReleaseGateTest(unittest.TestCase):
    def _run_gate(self, mutate) -> list[str]:
        ref, orch, run_id = _passing_bundle()
        mutate(ref, orch, run_id)
        with tempfile.TemporaryDirectory() as tmp:
            import workspace_integrity as wi

            wi.TRACES_DIR = Path(tmp) / "traces"
            if mutate.__name__ != "delete_trace":
                _write_traces(run_id, wi.TRACES_DIR, orch)
            return validate_release_gates(reference_rows=ref, orchestrated_rows=orch, run_id=run_id)

    def test_remove_hidden_invariant_fails(self) -> None:
        def mutate(_ref, orch, _run_id):
            for row in orch:
                if row["taskId"] == "task_052":
                    row["minimumContractSet"] = ["readme", "verify_grep"]
                    row["contractEscalationPath"] = []

        v = self._run_gate(mutate)
        self.assertTrue(any("task_052" in x and "hidden_invariant" in x for x in v))

    def test_remove_lock_protocol_fails(self) -> None:
        def mutate(_ref, orch, _run_id):
            for row in orch:
                if row["taskId"] == "task_057":
                    row["executionProtocolPath"] = ["single_shot_patch"]

        v = self._run_gate(mutate)
        self.assertTrue(any("task_057" in x for x in v))

    def test_api_shape_changed_fails(self) -> None:
        def mutate(_ref, orch, _run_id):
            for row in orch:
                if row["taskId"] == "task_059":
                    row["apiShapeChanged"] = True

        v = self._run_gate(mutate)
        self.assertTrue(any("apiShapeChanged" in x for x in v))

    def test_delete_trace_fails(self) -> None:
        ref, orch, run_id = _passing_bundle()
        with tempfile.TemporaryDirectory() as tmp:
            import workspace_integrity as wi

            wi.TRACES_DIR = Path(tmp) / "traces"
            _write_traces(run_id, wi.TRACES_DIR, orch[:-1])
            v = validate_release_gates(reference_rows=ref, orchestrated_rows=orch, run_id=run_id)
        self.assertTrue(any("missing mutation trace" in x for x in v))

    def test_wrong_file_edited_fails(self) -> None:
        def mutate(_ref, orch, _run_id):
            orch[0]["wrongFileEdited"] = True

        v = self._run_gate(mutate)
        self.assertTrue(any("wrongFileEdited" in x for x in v))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
