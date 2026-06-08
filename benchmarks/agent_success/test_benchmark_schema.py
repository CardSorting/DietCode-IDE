#!/usr/bin/env python3
"""Schema contract tests — freeze benchmark surfaces (Phase 4.1)."""

from __future__ import annotations

import inspect
import sys
import unittest
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from benchmark_schema import (  # noqa: E402
    AGENT_INPUT_MANIFEST_FIELDS,
    CONTRACT_NAMES,
    FAILURE_CLASS_VALUES,
    JSONL_CORE_FIELDS,
    MUTATION_TRACE_FIELDS,
    MUTATION_TRACE_FINAL_STATE_FIELDS,
    MUTATION_TRACE_STEP_FIELDS,
    OBSERVABILITY_EVENT_FIELDS,
    OBSERVABILITY_EVENT_TYPES,
    PROTOCOL_NAMES,
    RELEASE_GATE_NAMES,
    RESULTS_ORCHESTRATOR_REQUIRED_SECTIONS,
    TRACE_SCHEMA_VERSION,
)
from contracts import CONTRACTS, ESCALATION_GRAPH  # noqa: E402
from execution_protocols import EXECUTION_PROTOCOLS  # noqa: E402
from run_benchmark import RunMetrics  # noqa: E402


class BenchmarkSchemaTest(unittest.TestCase):
    def test_jsonl_core_fields_frozen_in_run_metrics(self) -> None:
        emitted = set(RunMetrics(task_id="task_001", mode="bridge").to_json().keys())
        for field in (
            "type",
            "taskId",
            "mode",
            "executor",
            "taskSuccess",
            "verifyPassed",
            "wrongFileEdited",
            "timestamp",
        ):
            self.assertIn(field, emitted)
            self.assertIn(field, JSONL_CORE_FIELDS)

    def test_contract_names_match_registry(self) -> None:
        self.assertEqual(set(CONTRACT_NAMES), set(CONTRACTS.keys()))

    def test_protocol_names_match_registry(self) -> None:
        self.assertEqual(set(PROTOCOL_NAMES), set(EXECUTION_PROTOCOLS.keys()))

    def test_failure_classes_cover_escalation_graph(self) -> None:
        for fc in ESCALATION_GRAPH:
            self.assertIn(fc, FAILURE_CLASS_VALUES)

    def test_mutation_trace_field_contract(self) -> None:
        self.assertIn("traceSchemaVersion", MUTATION_TRACE_FIELDS)
        self.assertIn("traceHash", MUTATION_TRACE_FIELDS)
        self.assertEqual(TRACE_SCHEMA_VERSION, "1.0")

    def test_mutation_trace_step_fields(self) -> None:
        self.assertEqual(
            MUTATION_TRACE_STEP_FIELDS,
            {"attempt", "contracts", "protocol", "result", "failureClass"},
        )

    def test_mutation_trace_final_state_fields(self) -> None:
        self.assertEqual(
            MUTATION_TRACE_FINAL_STATE_FIELDS,
            {"passed", "wrongFileEdited", "apiShapeChanged", "rollbackDirty", "destructiveAllowed"},
        )

    def test_release_gate_names_frozen(self) -> None:
        self.assertEqual(len(RELEASE_GATE_NAMES), 10)
        self.assertIn("task_059_semantic_repair_loop_escalation", RELEASE_GATE_NAMES)

    def test_results_orchestrator_sections(self) -> None:
        doc = (BENCHMARK_ROOT / "RESULTS_ORCHESTRATOR.md").read_text(encoding="utf-8")
        for section in RESULTS_ORCHESTRATOR_REQUIRED_SECTIONS:
            self.assertIn(section, doc, f"missing section: {section}")

    def test_observability_event_types(self) -> None:
        self.assertIn("contract.escalated", OBSERVABILITY_EVENT_TYPES)
        self.assertTrue(OBSERVABILITY_EVENT_FIELDS.issuperset({"eventType", "traceId", "spanId"}))

    def test_agent_input_manifest_fields(self) -> None:
        self.assertIn("metadataJson", AGENT_INPUT_MANIFEST_FIELDS)
        self.assertIn("expectedPatch", AGENT_INPUT_MANIFEST_FIELDS)

    def test_no_drift_in_contract_module_exports(self) -> None:
        src = inspect.getsource(sys.modules["contracts"])
        for name in CONTRACT_NAMES:
            self.assertIn(f'"{name}"', src)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
