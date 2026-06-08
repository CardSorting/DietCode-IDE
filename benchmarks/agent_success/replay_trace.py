#!/usr/bin/env python3
"""Replay verifier for mutation traces (Playwright-style inspectable failure artifacts)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCHMARK_ROOT))

from benchmark_schema import (  # noqa: E402
    CONTRACT_NAMES,
    FAILURE_CLASS_VALUES,
    MUTATION_TRACE_FIELDS,
    PROTOCOL_NAMES,
)
from contracts import ESCALATION_GRAPH  # noqa: E402
from execution_protocols import EXECUTION_PROTOCOLS  # noqa: E402
from mutation_trace import compute_trace_hash  # noqa: E402

CONTRACT_SET = set(CONTRACT_NAMES)
PROTOCOL_SET = set(PROTOCOL_NAMES)
FAILURE_SET = set(FAILURE_CLASS_VALUES)


def _load_jsonl_row(path: Path, task_id: str) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("type") == "task_result" and row.get("taskId") == task_id:
            return row
    return None


def verify_trace(
    trace: dict[str, Any],
    *,
    jsonl_row: dict[str, Any] | None = None,
) -> list[str]:
    """Return violations (empty = trace is replay-consistent)."""
    violations: list[str] = []

    for key in ("taskId", "runId", "steps", "finalState"):
        if key not in trace:
            violations.append(f"missing required field: {key}")

    if trace.get("traceHash"):
        expected = compute_trace_hash(trace)
        if trace["traceHash"] != expected:
            violations.append("traceHash mismatch (tampered or stale)")

    steps = trace.get("steps") or []
    prev_attempt = 0
    for i, step in enumerate(steps):
        attempt = step.get("attempt", 0)
        if attempt <= prev_attempt:
            violations.append(f"steps not strictly ordered by attempt at index {i}")
        prev_attempt = attempt

        for c in step.get("contracts") or []:
            if c not in CONTRACT_SET:
                violations.append(f"illegal contract in step {attempt}: {c}")
        proto = step.get("protocol")
        if proto and proto not in PROTOCOL_SET:
            violations.append(f"illegal protocol in step {attempt}: {proto}")
        fc = step.get("failureClass")
        if fc and fc not in FAILURE_SET:
            violations.append(f"unknown failureClass in step {attempt}: {fc}")

    # failureClass ↔ escalation graph
    for step in steps:
        if step.get("result") != "fail":
            continue
        fc = step.get("failureClass")
        if not fc:
            violations.append(f"fail step {step.get('attempt')} missing failureClass")
            continue
        if fc not in ESCALATION_GRAPH and fc != "authoritative_read":
            violations.append(f"failureClass not in escalation graph: {fc}")

    # Retry honesty consistency
    fail_classes = [s.get("failureClass") for s in steps if s.get("result") == "fail"]
    if trace.get("firstFailureClass") != (fail_classes[0] if fail_classes else None):
        violations.append("firstFailureClass does not match first failing step")
    final_state = trace.get("finalState") or {}
    passed = bool(final_state.get("passed"))
    expected_final_fc = fail_classes[-1] if fail_classes and not passed else None
    if trace.get("finalFailureClass") != expected_final_fc:
        violations.append("finalFailureClass inconsistent with steps/finalState")

    if jsonl_row:
        violations.extend(_verify_against_jsonl(trace, jsonl_row))

    return violations


def _verify_against_jsonl(trace: dict[str, Any], row: dict[str, Any]) -> list[str]:
    violations: list[str] = []
    final_state = trace.get("finalState") or {}
    tid = trace.get("taskId", "?")

    if bool(row.get("verifyPassed")) != bool(final_state.get("passed")):
        violations.append(f"finalState.passed mismatch vs JSONL for {tid}")
    if bool(row.get("wrongFileEdited")) != bool(final_state.get("wrongFileEdited")):
        violations.append(f"wrongFileEdited mismatch vs JSONL for {tid}")
    if bool(row.get("apiShapeChanged")) != bool(final_state.get("apiShapeChanged")):
        violations.append(f"apiShapeChanged mismatch vs JSONL for {tid}")

    rollback_dirty = row.get("sidecarRollbackClean") is False
    if row.get("semanticRollbackTriggered") and not row.get("semanticRepairSucceeded"):
        rollback_dirty = True
    if bool(rollback_dirty) != bool(final_state.get("rollbackDirty")):
        violations.append(f"rollbackDirty mismatch vs JSONL for {tid}")

    if trace.get("workspaceHashAfter") and row.get("workspaceHashAfter"):
        if trace["workspaceHashAfter"] != row["workspaceHashAfter"]:
            violations.append("workspaceHashAfter mismatch vs JSONL")

    for ev in trace.get("events") or []:
        et = ev.get("eventType", "")
        if et == "contract.escalated":
            c = ev.get("contract")
            if c and c not in CONTRACT_SET:
                violations.append(f"illegal escalated contract in events: {c}")
        if et == "protocol.escalated":
            p = ev.get("protocol")
            if p and p not in PROTOCOL_SET:
                violations.append(f"illegal escalated protocol in events: {p}")

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify a mutation trace artifact.")
    parser.add_argument("--trace", type=Path, required=True, help="Path to .mutation_trace.json")
    parser.add_argument("--jsonl", type=Path, default=None, help="Optional JSONL row source")
    args = parser.parse_args()

    if not args.trace.is_file():
        print(f"trace not found: {args.trace}", file=sys.stderr)
        return 1

    trace = json.loads(args.trace.read_text(encoding="utf-8"))
    jsonl_row = None
    if args.jsonl:
        jsonl_row = _load_jsonl_row(args.jsonl, trace.get("taskId", ""))

    violations = verify_trace(trace, jsonl_row=jsonl_row)
    print(f"Replay verify — {args.trace.name}")
    if violations:
        print("FAIL:")
        for v in violations:
            print(f"  - {v}")
        return 1

    print("PASS — trace integrity, ordering, escalation legality, finalState consistency")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
