#!/usr/bin/env python3
"""Smoke tests for claim-ready benchmark reporting."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from report_results import build_summary, load_task_meta, load_task_results, render_markdown  # noqa: E402


def _task_row(
    *,
    task_id: str,
    mode: str = "bridge",
    executor: str = "reference",
    ok: bool = True,
) -> dict:
    return {
        "type": "task_result",
        "taskId": task_id,
        "mode": mode,
        "executor": executor,
        "taskSuccess": ok,
        "verifyPassed": ok,
        "wrongFileEdited": False,
        "staleRecoverySucceeded": False,
        "rollbackSucceeded": False,
        "retries": 0,
        "toolCallCount": 1,
        "durationMs": 1.0,
        "failureCode": None,
        "recoveryHintsUsed": [],
        "commandsUsed": [],
        "patchValidateFailures": 0,
    }


class ReportResultsSmokeTest(unittest.TestCase):
    def test_reference_only_summary_claim_format(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = Path(tmp) / "reference_only.jsonl"
            rows = [
                _task_row(task_id="task_001", mode="raw_rpc"),
                _task_row(task_id="task_021", mode="bridge"),
            ]
            jsonl.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")

            loaded = load_task_results([jsonl])
            summary = build_summary(loaded, load_task_meta(), [jsonl])
            md = render_markdown(summary)

            self.assertEqual(summary["resultRowCount"], 2)
            self.assertEqual(summary["inputFiles"], [str(jsonl)])
            self.assertRegex(summary["generatedAt"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
            self.assertEqual(summary["executorCoverage"], {"reference": "present", "agent": "absent"})
            self.assertIn("## Evaluation Claim", md)
            self.assertIn("Executor coverage: reference **present** | agent **absent**", md)
            self.assertIn("> Agent executor results are not present in this summary.", md)
            self.assertIn("## Adversarial Trap Matrix", md)
            self.assertIn("| trapType | passRate | wrongFileEdited | rollbackSucceeded |", md)
            self.assertIn("wrong_file_decoy", md)
            self.assertIn("Nightmare tasks (051–060)", md)
            self.assertIn(
                "DietCode evaluates bounded agent code mutation as a transactional runtime problem",
                md,
            )

    def test_nightmare_matrix_when_nightmare_rows_present(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = Path(tmp) / "nightmare.jsonl"
            row = _task_row(task_id="task_051", mode="bridge")
            row.update(
                {
                    "destructiveCommandBlocked": False,
                    "sidecarRollbackClean": False,
                    "concurrentMutationDetected": False,
                    "searchReadMismatchDetected": False,
                    "apiShapePreserved": False,
                    "secondInvariantPassed": True,
                    "finalVerifyPassed": True,
                }
            )
            jsonl.write_text(json.dumps(row) + "\n", encoding="utf-8")

            md = render_markdown(build_summary(load_task_results([jsonl]), load_task_meta(), [jsonl]))

            self.assertIn("## Nightmare Runtime Contract Matrix", md)
            self.assertIn("spec_shadowing", md)

    def test_mixed_executor_summary_includes_agent_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = Path(tmp) / "mixed.jsonl"
            rows = [
                _task_row(task_id="task_001", executor="reference"),
                _task_row(task_id="task_001", executor="agent"),
            ]
            jsonl.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")

            summary = build_summary(load_task_results([jsonl]), load_task_meta(), [jsonl])
            md = render_markdown(summary)

            self.assertEqual(summary["executorCoverage"]["agent"], "present")
            self.assertNotIn("> Agent executor results are not present in this summary.", md)
            self.assertIn("agent executor passed **1/1**", md)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
