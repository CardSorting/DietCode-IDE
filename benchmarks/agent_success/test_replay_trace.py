#!/usr/bin/env python3
"""Unit tests for mutation trace replay verifier."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from mutation_trace import MutationTraceRecorder, build_mutation_trace, compute_trace_hash  # noqa: E402
from replay_trace import verify_trace  # noqa: E402
from test_release_gates import _orch_row  # noqa: E402


class ReplayTraceTest(unittest.TestCase):
    def test_valid_trace_passes(self) -> None:
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
        row = _orch_row(
            "task_059",
            executionProtocolPath=["single_shot_patch", "semantic_repair_loop"],
        )
        trace = build_mutation_trace(
            task_id="task_059",
            run_id="replay_test",
            mode="bridge",
            recorder=rec,
            metrics_json=row,
            succeeded=True,
        )
        self.assertEqual([], verify_trace(trace, jsonl_row=row))

    def test_tampered_hash_fails(self) -> None:
        trace = {
            "taskId": "task_052",
            "runId": "x",
            "steps": [
                {
                    "attempt": 1,
                    "contracts": ["readme"],
                    "protocol": "single_shot_patch",
                    "result": "pass",
                }
            ],
            "finalState": {
                "passed": True,
                "wrongFileEdited": False,
                "apiShapeChanged": False,
                "rollbackDirty": False,
                "destructiveAllowed": False,
            },
            "traceHash": "deadbeef",
        }
        self.assertTrue(any("traceHash" in v for v in verify_trace(trace)))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
