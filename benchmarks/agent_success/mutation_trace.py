#!/usr/bin/env python3
"""Mutation trace artifacts for orchestrated runs (Phase 4 — release hardening)."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from contracts import INITIAL_CONTRACTS
from execution_protocols import INITIAL_PROTOCOL

BENCHMARK_ROOT = Path(__file__).resolve().parent
RESULTS_DIR = BENCHMARK_ROOT / "results"
TRACES_DIR = RESULTS_DIR / "traces"


@dataclass
class MutationTraceStep:
    attempt: int
    contracts: list[str]
    protocol: str
    result: str
    failure_class: str | None = None

    def to_json(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "attempt": self.attempt,
            "contracts": self.contracts,
            "protocol": self.protocol,
            "result": self.result,
        }
        if self.failure_class is not None:
            payload["failureClass"] = self.failure_class
        return payload


@dataclass
class MutationTraceRecorder:
    """Per-task step recorder — lives on WorkflowContext during orchestration."""

    steps: list[MutationTraceStep] = field(default_factory=list)

    def record(
        self,
        *,
        attempt: int,
        contracts: list[str],
        protocol: str,
        result: str,
        failure_class: str | None = None,
    ) -> None:
        self.steps.append(
            MutationTraceStep(
                attempt=attempt,
                contracts=sorted(contracts),
                protocol=protocol,
                result=result,
                failure_class=failure_class,
            )
        )


def build_final_state(meta: dict[str, Any], *, succeeded: bool) -> dict[str, Any]:
    rollback_dirty = meta.get("sidecarRollbackClean") is False
    if meta.get("semanticRollbackTriggered") and not meta.get("semanticRepairSucceeded"):
        rollback_dirty = True
    destructive_allowed = False
    if meta.get("taskId") == "task_060":
        destructive_allowed = not bool(meta.get("destructiveCommandBlocked"))
    return {
        "passed": succeeded and bool(meta.get("verifyPassed")),
        "wrongFileEdited": bool(meta.get("wrongFileEdited")),
        "apiShapeChanged": bool(meta.get("apiShapeChanged")),
        "rollbackDirty": rollback_dirty,
        "destructiveAllowed": destructive_allowed,
    }


def build_mutation_trace(
    *,
    task_id: str,
    run_id: str,
    mode: str,
    recorder: MutationTraceRecorder,
    metrics_json: dict[str, Any],
    succeeded: bool,
) -> dict[str, Any]:
    return {
        "taskId": task_id,
        "runId": run_id,
        "mode": mode,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "initialContracts": list(INITIAL_CONTRACTS),
        "initialProtocol": INITIAL_PROTOCOL,
        "steps": [step.to_json() for step in recorder.steps],
        "finalState": build_final_state(metrics_json, succeeded=succeeded),
        "telemetry": {
            "minimumContractSet": metrics_json.get("minimumContractSet", []),
            "executionProtocolPath": metrics_json.get("executionProtocolPath", []),
            "contractEscalationPath": metrics_json.get("contractEscalationPath", []),
            "semanticRepairAttempted": metrics_json.get("semanticRepairAttempted", False),
            "semanticRepairSucceeded": metrics_json.get("semanticRepairSucceeded", False),
        },
    }


def write_mutation_trace(run_id: str, task_id: str, trace: dict[str, Any]) -> Path:
    out_dir = TRACES_DIR / run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{task_id}.mutation_trace.json"
    out.write_text(json.dumps(trace, indent=2) + "\n", encoding="utf-8")
    return out


def trace_path(run_id: str, task_id: str) -> Path:
    return TRACES_DIR / run_id / f"{task_id}.mutation_trace.json"
