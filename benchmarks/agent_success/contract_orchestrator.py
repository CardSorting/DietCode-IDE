#!/usr/bin/env python3
"""Runtime Contract Orchestrator — adaptive escalation loop for agent execution."""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from contracts import (
    ContractBroker,
    INITIAL_CONTRACTS,
    MCS_REFERENCE,
    ORCHESTRATOR_CLAIM,
    classify_failure,
    compute_mcs_match,
    measure_verify_outcome,
)

if TYPE_CHECKING:
    from run_benchmark import WorkflowContext

BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"

MAX_ORCHESTRATION_STEPS = 8


def _sync_workspace_to_runtime(workspace: Path, mode: str, ctx: WorkflowContext) -> None:
    """Push restored local files to the runtime (RPC patch reads server-side state)."""
    if mode not in ("raw_rpc", "bridge"):
        return
    from run_benchmark import RpcSession, ensure_workspace_open

    ensure_workspace_open(workspace)
    if mode != "raw_rpc":
        return
    with RpcSession(workspace, ctx) as session:
        from agent_driver import _skip_workspace_artifact

        for path in sorted(workspace.rglob("*")):
            if not path.is_file() or _skip_workspace_artifact(path):
                continue
            rel = path.relative_to(workspace).as_posix()
            session.call("file.write", {"path": rel, "content": path.read_text(encoding="utf-8")})


def run_orchestrated_agent(
    workspace: Path,
    task_id: str,
    mode: str,
    ctx: WorkflowContext,
) -> None:
    """Start minimally bounded; classify failures; escalate contracts; retry."""
    from agent_driver import (
        _restore_workspace,
        _snapshot_workspace,
        build_plan_from_contracts,
        execute_plan_with_contracts,
    )

    ctx.agent_profile = "orchestrated"
    broker = ContractBroker()
    fixture_snap = _snapshot_workspace(workspace)

    last_error: str | None = None
    for step in range(MAX_ORCHESTRATION_STEPS):
        if step > 0:
            _restore_workspace(workspace, fixture_snap)
            _sync_workspace_to_runtime(workspace, mode, ctx)
            ctx.retries += 1

        visible = set(broker.visible)
        outcome = measure_verify_outcome(workspace, task_id)

        try:
            plan = build_plan_from_contracts(task_id, visible)
            if not plan.positive_goals and not plan.shell_checks and not plan.negative_goals:
                raise RuntimeError(f"no verify goals parsed for {task_id}")
            execute_plan_with_contracts(
                workspace,
                task_id,
                mode,
                ctx,
                plan,
                visible,
                protocol=broker.active_protocol,
            )
            outcome = measure_verify_outcome(workspace, task_id)
            outcome.concurrent_mutation_observed = ctx.metrics.concurrent_mutation_detected
            outcome.semantic_preservation_failed = ctx.metrics.api_shape_changed
            outcome.behavior_failure_uncaptured = ctx.metrics.behavior_failure_uncaptured
            if outcome.verify_rc == 0 and outcome.invariant_rc in (None, 0):
                _finalize_orchestration(ctx, broker, task_id, succeeded=True)
                return
            last_error = (
                f"verify failed (rc={outcome.verify_rc}): "
                f"{outcome.verify_stderr or outcome.verify_stdout}".strip()
            )
        except Exception as exc:
            last_error = str(exc)
            outcome.execution_error = last_error
            outcome.concurrent_mutation_observed = ctx.metrics.concurrent_mutation_detected
            outcome.semantic_preservation_failed = ctx.metrics.api_shape_changed
            outcome.behavior_failure_uncaptured = ctx.metrics.behavior_failure_uncaptured
            outcome = measure_verify_outcome(workspace, task_id)
            outcome.concurrent_mutation_observed = ctx.metrics.concurrent_mutation_detected
            outcome.semantic_preservation_failed = ctx.metrics.api_shape_changed
            outcome.behavior_failure_uncaptured = ctx.metrics.behavior_failure_uncaptured
            if outcome.execution_error is None:
                outcome.execution_error = last_error

        failure_class = classify_failure(task_id, outcome)
        granted = broker.escalate(failure_class, step=step)
        if not granted:
            break

    ctx.metrics.failure_code = ctx.metrics.failure_code or "OrchestrationExhausted"
    _finalize_orchestration(ctx, broker, task_id, succeeded=False)
    if last_error:
        raise RuntimeError(last_error)
    raise RuntimeError("orchestration exhausted without passing verify")


def _finalize_orchestration(ctx: WorkflowContext, broker: ContractBroker, task_id: str, *, succeeded: bool) -> None:
    m = ctx.metrics
    m.contract_coverage = broker.to_coverage()
    m.minimum_contract_set = broker.visible_contracts()
    m.contract_escalation_path = list(broker.escalation_path)
    m.failure_classes_observed = list(broker.failure_classes)
    m.orchestration_steps = max(1, len(broker.escalation_path) + (1 if succeeded else 0))
    m.escalation_succeeded = succeeded and bool(broker.escalation_path)
    m.execution_protocol_path = list(broker.protocol_path)
    m.protocol_escalation_succeeded = succeeded and len(broker.protocol_path) > 1
    ref = MCS_REFERENCE.get(task_id, [])
    m.mcs_reference_match = compute_mcs_match(m.minimum_contract_set, ref) if succeeded else {}
