#!/usr/bin/env python3
"""Mutation trace artifacts for orchestrated runs (Phase 4 — release hardening)."""

from __future__ import annotations

import hashlib
import json
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from agent_input_manifest import build_agent_input_manifest
from benchmark_schema import BENCHMARK_VERSION, RUNTIME_VERSION, TRACE_SCHEMA_VERSION
from contracts import INITIAL_CONTRACTS
from execution_protocols import INITIAL_PROTOCOL
from observability import ObservabilityRecorder
from workspace_integrity import (
    assert_trace_outside_workspace,
    hash_workspace,
    resolve_trace_path,
)

BENCHMARK_ROOT = Path(__file__).resolve().parent
from workspace_integrity import RESULTS_DIR, TRACES_DIR  # noqa: E402


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
    observability: ObservabilityRecorder = field(default_factory=ObservabilityRecorder)

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
        event_type = "orchestration.passed" if result == "pass" else "orchestration.attempt"
        self.observability.emit(
            event_type,
            task_id="",  # filled at build time
            attempt=attempt,
            protocol=protocol,
            failure_class=failure_class,
        )


def get_git_commit() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(BENCHMARK_ROOT.parents[1]),
            capture_output=True,
            text=True,
            check=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


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


def compute_retry_honesty(steps: list[MutationTraceStep], *, succeeded: bool) -> dict[str, Any]:
    fail_steps = [s for s in steps if s.result == "fail"]
    first_fail = fail_steps[0].failure_class if fail_steps else None
    last_fail = fail_steps[-1].failure_class if fail_steps and not succeeded else None
    attempt_count = len(steps) if steps else 1
    passed_on_retry = succeeded and attempt_count > 1
    return {
        "attemptCount": attempt_count,
        "passedOnRetry": passed_on_retry,
        "firstFailureClass": first_fail,
        "finalFailureClass": last_fail,
    }


def compute_trace_hash(trace: dict[str, Any]) -> str:
    payload = {k: v for k, v in trace.items() if k != "traceHash"}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def build_mutation_trace(
    *,
    task_id: str,
    run_id: str,
    mode: str,
    recorder: MutationTraceRecorder,
    metrics_json: dict[str, Any],
    succeeded: bool,
    workspace_hash_before: str = "",
    workspace_hash_after: str = "",
    parent_run_id: str | None = None,
    external_agent: bool = False,
) -> dict[str, Any]:
    retry = compute_retry_honesty(recorder.steps, succeeded=succeeded)
    events = []
    for ev in recorder.observability.events:
        item = dict(ev)
        item["taskId"] = task_id
        events.append(item)

    trace: dict[str, Any] = {
        "traceSchemaVersion": TRACE_SCHEMA_VERSION,
        "taskId": task_id,
        "runId": run_id,
        "mode": mode,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "runtimeVersion": RUNTIME_VERSION,
        "benchmarkVersion": BENCHMARK_VERSION,
        "gitCommit": get_git_commit(),
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
        "attemptCount": retry["attemptCount"],
        "passedOnRetry": retry["passedOnRetry"],
        "firstFailureClass": retry["firstFailureClass"],
        "finalFailureClass": retry["finalFailureClass"],
        "events": events,
        "agentInputManifest": build_agent_input_manifest(
            external=external_agent,
            profile=metrics_json.get("agentProfile", "orchestrated"),
        ),
    }
    if parent_run_id:
        trace["parentRunId"] = parent_run_id
    if workspace_hash_before:
        trace["workspaceHashBefore"] = workspace_hash_before
    if workspace_hash_after:
        trace["workspaceHashAfter"] = workspace_hash_after
    trace["traceHash"] = compute_trace_hash(trace)
    return trace


def write_mutation_trace(
    run_id: str,
    task_id: str,
    trace: dict[str, Any],
    *,
    workspace: Path | None = None,
) -> Path:
    out = resolve_trace_path(run_id, task_id)
    if workspace is not None:
        assert_trace_outside_workspace(out, workspace)
    out.parent.mkdir(parents=True, exist_ok=True)
    if "traceHash" not in trace:
        trace = dict(trace)
        trace["traceHash"] = compute_trace_hash(trace)
    out.write_text(json.dumps(trace, indent=2) + "\n", encoding="utf-8")
    return out


def trace_path(run_id: str, task_id: str) -> Path:
    return resolve_trace_path(run_id, task_id)


def hash_workspace_for_trace(workspace: Path) -> str:
    return hash_workspace(workspace)
