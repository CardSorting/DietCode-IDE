#!/usr/bin/env python3
"""Tests for semantic repair protocol (Phase 3.2)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contracts import ContractBroker, ESCALATION_GRAPH, classify_failure  # noqa: E402
from contracts import VerifyOutcome  # noqa: E402
from contract_ladder import compute_cri  # noqa: E402
from execution_protocols import (  # noqa: E402
    EXECUTION_PROTOCOLS,
    _filter_implementation_goals,
    capture_api_shape,
)
from agent_driver import AgentPlan, PositiveGoal  # noqa: E402


class SemanticRepairTest(unittest.TestCase):
    def test_semantic_protocol_registered(self) -> None:
        self.assertIn("semantic_repair_loop", EXECUTION_PROTOCOLS)
        self.assertIn("api_shape_contract", EXECUTION_PROTOCOLS["semantic_repair_loop"]["requires"])

    def test_broker_grants_semantic_repair(self) -> None:
        broker = ContractBroker()
        granted = broker.escalate("behavior_check_failed", step=0)
        self.assertEqual(granted, "behavior_check")
        self.assertEqual(broker.active_protocol, "semantic_repair_loop")
        self.assertIn("api_shape_contract", broker.visible)

    def test_escalation_graph_semantic(self) -> None:
        action = ESCALATION_GRAPH["behavior_check_failed"]
        self.assertEqual(action["grantProtocol"], "semantic_repair_loop")

    def test_filter_signature_goals(self) -> None:
        plan = AgentPlan(
            instruction="",
            positive_goals=[
                PositiveGoal("lib/public.py", "def compute"),
                PositiveGoal("lib/public.py", "return format_result(1)"),
            ],
        )
        filtered = _filter_implementation_goals(plan)
        self.assertEqual(len(filtered.positive_goals), 1)
        self.assertIn("format_result(1)", filtered.positive_goals[0].pattern)

    def test_capture_api_shape(self) -> None:
        root = BENCHMARK_ROOT / "tasks" / "task_059" / "before"
        shape = capture_api_shape(root, ["lib/public.py"])
        self.assertIn("def compute", shape)
        self.assertIn("def format_result", shape)

    def test_cri_api_shape_penalty(self) -> None:
        ok = {"taskSuccess": True, "verifyPassed": True, "apiShapeChanged": False}
        bad = {"taskSuccess": True, "verifyPassed": True, "apiShapeChanged": True}
        self.assertGreater(compute_cri(ok), compute_cri(bad))

    def test_classify_semantic_preservation(self) -> None:
        outcome = VerifyOutcome(semantic_preservation_failed=True)
        self.assertEqual(classify_failure("task_059", outcome), "semantic_preservation_failed")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
