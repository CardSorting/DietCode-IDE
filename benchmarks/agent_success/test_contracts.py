#!/usr/bin/env python3
"""Tests for Runtime Contract Orchestrator (Phase 3)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from contracts import (  # noqa: E402
    ESCALATION_GRAPH,
    INITIAL_CONTRACTS,
    MCS_REFERENCE,
    ContractBroker,
    classify_failure,
    compute_mcs_match,
    contracts_allow,
)
from contracts import VerifyOutcome  # noqa: E402


class ContractsTest(unittest.TestCase):
    def test_initial_contracts_minimal(self) -> None:
        self.assertEqual(set(INITIAL_CONTRACTS), {"readme", "verify_grep"})

    def test_broker_escalates_on_failure(self) -> None:
        broker = ContractBroker()
        granted = broker.escalate("hidden_invariant_missing", step=0)
        self.assertEqual(granted, "hidden_invariant")
        self.assertIn("hidden_invariant", broker.visible)

    def test_classify_invariant_gap(self) -> None:
        outcome = VerifyOutcome(verify_rc=0, invariant_rc=1, invariant_stderr="AssertionError")
        # task_052 has verify_invariant.sh
        failure = classify_failure("task_052", outcome)
        self.assertEqual(failure, "hidden_invariant_missing")

    def test_classify_behavior_mismatch(self) -> None:
        outcome = VerifyOutcome(verify_rc=1, verify_stderr="AssertionError: run() == 42")
        failure = classify_failure("task_055", outcome)
        self.assertEqual(failure, "behavior_check_failed")

    def test_escalation_graph_covers_key_failures(self) -> None:
        for key in (
            "hidden_invariant_missing",
            "runtime_behavior_mismatch",
            "stale_read_detected",
            "execution_trace_required",
            "concurrent_mutation_detected",
        ):
            self.assertIn(key, ESCALATION_GRAPH)
            action = ESCALATION_GRAPH[key]
            self.assertIn("grantContract", action)

    def test_contracts_allow_verify_exec(self) -> None:
        self.assertFalse(contracts_allow(set(INITIAL_CONTRACTS), "verify_exec"))
        self.assertTrue(contracts_allow({"readme", "verify_grep", "verify_exec"}, "verify_exec"))

    def test_mcs_reference_task_052(self) -> None:
        ref = MCS_REFERENCE["task_052"]
        self.assertIn("hidden_invariant", ref)
        match = compute_mcs_match(["readme", "verify_grep", "hidden_invariant"], ref)
        self.assertTrue(match["matched"])

    def test_chained_escalation_no_duplicate_grant(self) -> None:
        broker = ContractBroker()
        broker.visible.add("verify_exec")
        broker.visible.add("behavior_check")
        granted = broker.escalate("runtime_behavior_mismatch", step=1)
        self.assertIsNone(granted)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
