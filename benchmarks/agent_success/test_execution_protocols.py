#!/usr/bin/env python3
"""Tests for execution-side recovery protocols (Phase 3.1)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contracts import ContractBroker, ESCALATION_GRAPH, VerifyOutcome, classify_failure  # noqa: E402
from execution_protocols import (  # noqa: E402
    EXECUTION_PROTOCOLS,
    INITIAL_PROTOCOL,
    reconcile_content_for_goals,
    _strip_concurrent_lines,
)
from agent_driver import PositiveGoal  # noqa: E402


class ExecutionProtocolsTest(unittest.TestCase):
    def test_initial_protocol(self) -> None:
        self.assertEqual(INITIAL_PROTOCOL, "single_shot_patch")

    def test_registry_has_lock_protocol(self) -> None:
        self.assertIn("lock_read_validate_apply", EXECUTION_PROTOCOLS)

    def test_strip_concurrent_version_line(self) -> None:
        content = "VERSION = 1\nVERSION = 3\n"
        cleaned = _strip_concurrent_lines(content, "VERSION = 3\n")
        self.assertNotIn("VERSION = 3", cleaned)
        self.assertIn("VERSION = 1", cleaned)

    def test_reconcile_concurrent_to_goal(self) -> None:
        content = "VERSION = 1\nVERSION = 3\n"
        goals = [PositiveGoal("src/runtime.py", "VERSION = 2")]
        result = reconcile_content_for_goals(
            content,
            goals,
            concurrent_mutation="VERSION = 3\n",
            strip_concurrent=True,
        )
        self.assertIn("VERSION = 2", result)
        self.assertNotIn("VERSION = 3", result)

    def test_broker_grants_protocol_on_concurrent_failure(self) -> None:
        broker = ContractBroker()
        granted = broker.escalate("concurrent_mutation_detected", step=0)
        self.assertEqual(granted, "stale_read_protocol")
        self.assertEqual(broker.active_protocol, "lock_read_validate_apply")
        self.assertEqual(
            broker.protocol_path,
            ["single_shot_patch", "lock_read_validate_apply"],
        )

    def test_classify_concurrent_from_observed_flag(self) -> None:
        outcome = VerifyOutcome(verify_rc=1, concurrent_mutation_observed=True)
        self.assertEqual(classify_failure("task_057", outcome), "concurrent_mutation_detected")

    def test_escalation_graph_dual_axis(self) -> None:
        action = ESCALATION_GRAPH["concurrent_mutation_detected"]
        self.assertEqual(action["grantContract"], "stale_read_protocol")
        self.assertEqual(action["grantProtocol"], "lock_read_validate_apply")

    def test_negative_goal_does_not_block_positive_path(self) -> None:
        from agent_driver import AgentPlan, NegativeGoal, _target_paths

        plan = AgentPlan(
            instruction="",
            positive_goals=[PositiveGoal("src/runtime.py", "VERSION = 2")],
            negative_goals=[NegativeGoal("src/runtime.py", "VERSION = 3")],
        )
        self.assertEqual(_target_paths(plan), ["src/runtime.py"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
