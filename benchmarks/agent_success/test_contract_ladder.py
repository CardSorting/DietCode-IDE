#!/usr/bin/env python3
"""Smoke tests for Runtime Contract Evaluation Ladder."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contract_ladder import (  # noqa: E402
    AGENT_PROFILES,
    compute_cri,
    contract_coverage,
    outcome_label,
    profile_visibility_label,
)
from render_contract_ladder import aggregate_ladder, render_markdown  # noqa: E402


class ContractLadderTest(unittest.TestCase):
    def test_profiles_are_cumulative(self) -> None:
        grep = contract_coverage("grep_only")
        full = contract_coverage("contract_full")
        self.assertFalse(grep["executableChecks"])
        self.assertTrue(full["executableChecks"])
        self.assertTrue(full["invariantChecks"])
        self.assertTrue(full["traceScripts"])
        self.assertTrue(full["destructiveCommandPolicy"])
        self.assertFalse(grep["rollbackProtocol"])
        self.assertTrue(contract_coverage("recovery_aware")["rollbackProtocol"])

    def test_cri_penalizes_failures(self) -> None:
        ok = {"taskSuccess": True, "verifyPassed": True, "wrongFileEdited": False, "secondInvariantPassed": True}
        bad = {"taskSuccess": False, "verifyPassed": False, "wrongFileEdited": True}
        self.assertGreater(compute_cri(ok), compute_cri(bad))

    def test_ladder_report_renders(self) -> None:
        rows = []
        for profile in ("grep_only", "verify_exec"):
            rows.append(
                {
                    "type": "task_result",
                    "taskId": "task_051",
                    "mode": "bridge",
                    "executor": "agent",
                    "agentProfile": profile,
                    "taskSuccess": profile != "grep_only",
                    "verifyPassed": profile != "grep_only",
                    "wrongFileEdited": False,
                    "toolCallCount": 9,
                    "durationMs": 500.0,
                    "contractReliabilityIndex": 100 if profile != "grep_only" else 70,
                }
            )
        summary = aggregate_ladder(rows, {"task_051": {"trapType": "spec_shadowing"}})
        md = render_markdown(summary)
        self.assertIn("Runtime Contract Evaluation Ladder", md)
        self.assertIn("Failure Attribution Matrix", md)
        self.assertIn("grep_only", md)
        self.assertIn("spec_shadowing", md)

    def test_all_profiles_defined(self) -> None:
        self.assertEqual(len(AGENT_PROFILES), 6)
        for profile in AGENT_PROFILES:
            self.assertIn("+", profile_visibility_label(profile) or "README")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
