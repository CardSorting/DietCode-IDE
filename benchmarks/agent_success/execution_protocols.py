#!/usr/bin/env python3
"""Execution-side recovery protocols for bounded mutation (Phase 3.1).

Visibility contracts tell the agent what truth exists; execution protocols
determine whether mutation remains safe under changing workspace state.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

from contracts import contracts_allow

if TYPE_CHECKING:
    from agent_driver import AgentPlan, PositiveGoal
    from run_benchmark import BridgeSession, RpcSession, WorkflowContext

BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"

INITIAL_PROTOCOL = "single_shot_patch"

EXECUTION_PROTOCOLS: dict[str, dict[str, Any]] = {
    "single_shot_patch": {
        "description": "Read once, validate, apply — no stale reconciliation.",
        "capabilities": ["validate", "apply"],
        "layer": 0,
    },
    "stale_safe_patch": {
        "description": "On stale_content, re-read and re-apply goals against live file.",
        "capabilities": ["validate", "apply", "stale_reconcile"],
        "layer": 1,
    },
    "lock_read_validate_apply": {
        "description": "Authoritative read, validate, apply; on race strip concurrent lines then reconcile.",
        "capabilities": ["lock", "validate", "apply", "concurrent_reconcile"],
        "layer": 2,
    },
    "transactional_batch_patch": {
        "description": "Batch patches with workspace snapshot rollback between attempts.",
        "capabilities": ["batch", "rollback"],
        "layer": 2,
    },
    "rollback_cleanup": {
        "description": "Restore snapshot and remove sidecar residue before retry.",
        "capabilities": ["rollback", "sidecar_cleanup"],
        "layer": 3,
    },
    "semantic_repair_loop": {
        "description": "Behavior-preserving repair loop with API-shape checks before and after mutation.",
        "capabilities": ["semantic_repair", "api_shape_guard", "behavior_check"],
        "layer": 4,
        "requires": ["verify_exec", "behavior_check", "api_shape_contract"],
    },
}

@dataclass
class TrapContext:
    """Benchmark harness trap simulation (never agent plan input)."""

    concurrent_mutation: str | None = None
    stale_mutation: str | None = None
    sidecar_files: list[str] = field(default_factory=list)


def load_trap_context(task_id: str) -> TrapContext:
    meta_path = TASKS_DIR / task_id / "metadata.json"
    if not meta_path.is_file():
        return TrapContext()
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    return TrapContext(
        concurrent_mutation=meta.get("concurrentMutation"),
        stale_mutation=meta.get("staleMutation"),
        sidecar_files=list(meta.get("sidecarFiles", [])),
    )


def protocol_allows(protocol: str, capability: str) -> bool:
    spec = EXECUTION_PROTOCOLS.get(protocol, {})
    return capability in spec.get("capabilities", [])


def _strip_concurrent_lines(content: str, concurrent_mutation: str | None) -> str:
    if not concurrent_mutation:
        return content
    drop = {line.strip() for line in concurrent_mutation.splitlines() if line.strip()}
    if not drop:
        return content
    kept: list[str] = []
    for line in content.splitlines(keepends=True):
        if line.strip() in drop:
            continue
        kept.append(line)
    return "".join(kept) or content


def reconcile_content_for_goals(
    content: str,
    goals: list[PositiveGoal],
    *,
    concurrent_mutation: str | None = None,
    strip_concurrent: bool = False,
) -> str:
    from agent_driver import _apply_goal_to_content

    body = _strip_concurrent_lines(content, concurrent_mutation) if strip_concurrent else content
    rel_goals = goals  # caller filters per file
    for goal in rel_goals:
        body = _apply_goal_to_content(body, goal.pattern)
    return body


def capture_api_shape(workspace: Path, rel_paths: list[str]) -> str:
    """Extract public `def` signatures from target modules."""
    lines_out: list[str] = []
    for rel in sorted(set(rel_paths)):
        path = workspace / rel
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("def "):
                lines_out.append(f"{rel}:{stripped}")
    return "\n".join(lines_out)


def _discover_behavior_scripts(workspace: Path) -> list[str]:
    found: list[str] = []
    for name in ("test_api.py", "check.py"):
        if (workspace / name).is_file():
            found.append(name)
    return found


def _run_behavior_checks(
    workspace: Path,
    plan: AgentPlan,
) -> subprocess.CompletedProcess[str] | None:
    import os
    import subprocess

    checks = list(plan.shell_checks)
    if not checks:
        for script in _discover_behavior_scripts(workspace):
            checks.append(f'cd "$WORKSPACE_ROOT" && python3 {script}')
    if not checks:
        return None
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    last: subprocess.CompletedProcess[str] | None = None
    for check in checks:
        cmd = check.replace("$WORKSPACE_ROOT", str(workspace)).replace("$ROOT", str(workspace))
        last = subprocess.run(["bash", "-lc", cmd], env=env, capture_output=True, text=True, check=False)
        if last.returncode != 0:
            return last
    return last


def _filter_implementation_goals(plan: AgentPlan) -> AgentPlan:
    """Drop signature grep goals — repair targets implementation lines only."""
    from agent_driver import AgentPlan as Plan

    filtered = [
        g
        for g in plan.positive_goals
        if not g.pattern.strip().startswith("def ")
    ]
    return Plan(
        instruction=plan.instruction,
        positive_goals=filtered,
        negative_goals=list(plan.negative_goals),
        shell_checks=list(plan.shell_checks),
        trace_scripts=list(plan.trace_scripts),
        invariant_shell_checks=list(plan.invariant_shell_checks),
    )


def run_semantic_repair_loop(
    workspace: Path,
    task_id: str,
    mode: str,
    ctx: WorkflowContext,
    plan: AgentPlan,
    visible: set[str],
) -> None:
    """Behavior-preserving repair with API-shape guard and rollback on violation."""
    from agent_driver import (
        _enrich_contract_full_goals,
        _infer_behavior_targets,
        _post_patch_contract_checks,
        _restore_workspace,
        _run_verify_script,
        _snapshot_workspace,
        build_plan_from_contracts,
    )

    spec = EXECUTION_PROTOCOLS["semantic_repair_loop"]
    required_caps = {
        "verify_exec": "verify_exec",
        "behavior_check": "behavior_check",
        "api_shape_contract": "api_shape",
    }
    for required in spec.get("requires", []):
        cap = required_caps.get(required, required)
        if not contracts_allow(visible, cap):
            raise RuntimeError(f"semantic_repair_loop missing contract: {required}")

    metrics = ctx.metrics
    metrics.semantic_repair_attempted = True
    snap = _snapshot_workspace(workspace)
    trap = load_trap_context(task_id)

    repair_plan = _filter_implementation_goals(plan)
    if contracts_allow(visible, "verify_exec") and not repair_plan.shell_checks:
        enriched = build_plan_from_contracts(task_id, visible)
        repair_plan.shell_checks = enriched.shell_checks

    _infer_behavior_targets(workspace, repair_plan)
    _enrich_contract_full_goals(task_id, repair_plan)
    repair_plan = _filter_implementation_goals(repair_plan)

    api_paths = sorted({g.rel_path for g in repair_plan.positive_goals})
    if not api_paths:
        api_paths = sorted({g.rel_path for g in plan.positive_goals if g.rel_path.endswith(".py")})

    metrics.api_shape_before = capture_api_shape(workspace, api_paths)

    before_behavior = _run_behavior_checks(workspace, repair_plan)
    if before_behavior is not None and before_behavior.returncode != 0:
        metrics.behavior_failure_captured = True
    elif before_behavior is None and _discover_behavior_scripts(workspace):
        metrics.behavior_failure_uncaptured = True

    if mode == "bridge":
        _apply_plan_bridge(workspace, ctx, repair_plan, visible, "single_shot_patch", trap)
    elif mode == "raw_rpc":
        _apply_plan_rpc(workspace, ctx, repair_plan, visible, "single_shot_patch", trap)
    else:
        raise ValueError(f"unknown mode: {mode}")

    metrics.api_shape_after = capture_api_shape(workspace, api_paths)
    metrics.api_shape_changed = metrics.api_shape_before != metrics.api_shape_after

    after_behavior = _run_behavior_checks(workspace, repair_plan)
    behavior_ok = after_behavior is None or after_behavior.returncode == 0

    verify_ok = True
    verify = TASKS_DIR / task_id / "verify.sh"
    if verify.is_file():
        completed = _run_verify_script(workspace, verify)
        verify_ok = completed.returncode == 0

    invariant_ok = True
    inv = TASKS_DIR / task_id / "verify_invariant.sh"
    if inv.is_file():
        inv_run = _run_verify_script(workspace, inv)
        invariant_ok = inv_run.returncode == 0

    if metrics.api_shape_changed or not behavior_ok or not verify_ok or not invariant_ok:
        _restore_workspace(workspace, snap)
        _sync_workspace_to_runtime(workspace, mode, ctx)
        ctx.retries += 1
        metrics.semantic_rollback_triggered = True
        metrics.rollback_succeeded = True
        metrics.api_shape_preserved = False
        detail = []
        if metrics.api_shape_changed:
            detail.append("api_shape_changed")
        if not behavior_ok:
            detail.append("behavior_still_failing")
        if not verify_ok:
            detail.append("verify_failed")
        raise RuntimeError(f"semantic repair failed ({', '.join(detail)}); rolled back")

    metrics.semantic_repair_succeeded = True
    metrics.api_shape_preserved = True
    _post_patch_contract_checks(workspace, task_id, repair_plan, visible)


def execute_plan_with_protocol(
    workspace: Path,
    task_id: str,
    mode: str,
    ctx: WorkflowContext,
    plan: AgentPlan,
    visible: set[str],
    protocol: str,
) -> None:
    """Run one mutation attempt under the active execution protocol."""
    from agent_driver import (
        _check_destructive_temptation,
        _discover_paths_from_trace,
        _infer_behavior_targets,
        _post_patch_contract_checks,
        _restore_workspace,
        _run_verify_script,
        _snapshot_workspace,
    )

    if protocol not in EXECUTION_PROTOCOLS:
        raise ValueError(f"unknown execution protocol: {protocol}")

    if protocol == "semantic_repair_loop":
        run_semantic_repair_loop(workspace, task_id, mode, ctx, plan, visible)
        return

    # Signature grep clauses are post-mutation constraints, not patch targets.
    plan = _filter_implementation_goals(plan)

    trap = load_trap_context(task_id)

    if contracts_allow(visible, "destructive_policy"):
        _check_destructive_temptation(plan, ctx)

    if contracts_allow(visible, "verify_exec") or contracts_allow(visible, "behavior_check"):
        _infer_behavior_targets(workspace, plan)

    if contracts_allow(visible, "trace"):
        _discover_paths_from_trace(workspace, plan)

    use_rollback = protocol in ("transactional_batch_patch", "rollback_cleanup") or contracts_allow(
        visible, "recovery"
    )
    snap = _snapshot_workspace(workspace) if use_rollback else {}
    max_attempts = 3 if use_rollback else 1

    for attempt in range(max_attempts):
        if attempt > 0 and snap:
            _restore_workspace(workspace, snap)
            _sync_workspace_to_runtime(workspace, mode, ctx)
            ctx.retries += 1
            ctx.metrics.rollback_succeeded = True
            if protocol == "rollback_cleanup" or contracts_allow(visible, "recovery"):
                _cleanup_sidecars(workspace, trap.sidecar_files)

        if mode == "bridge":
            _apply_plan_bridge(workspace, ctx, plan, visible, protocol, trap)
        elif mode == "raw_rpc":
            _apply_plan_rpc(workspace, ctx, plan, visible, protocol, trap)
        else:
            raise ValueError(f"unknown mode: {mode}")

        try:
            _post_patch_contract_checks(workspace, task_id, plan, visible)
            if contracts_allow(visible, "verify_exec"):
                verify = TASKS_DIR / task_id / "verify.sh"
                completed = _run_verify_script(workspace, verify)
                if completed.returncode != 0:
                    raise RuntimeError(
                        f"verify.sh failed (exit {completed.returncode}): "
                        f"{completed.stderr or completed.stdout}"
                    )
            return
        except RuntimeError:
            if attempt + 1 >= max_attempts:
                raise


def _sync_workspace_to_runtime(workspace: Path, mode: str, ctx: WorkflowContext) -> None:
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


def _cleanup_sidecars(workspace: Path, sidecar_files: list[str]) -> None:
    for rel in sidecar_files:
        path = workspace / rel
        if path.is_file():
            path.unlink()
    if sidecar_files:
        pass  # metrics set by caller if needed


def _apply_plan_rpc(
    workspace: Path,
    ctx: WorkflowContext,
    plan: AgentPlan,
    visible: set[str],
    protocol: str,
    trap: TrapContext,
) -> None:
    from agent_driver import (
        _read_file_rpc,
        _search_keys_from_plan,
        _target_paths,
        build_unified_diff,
    )
    from run_benchmark import RpcSession

    authoritative = contracts_allow(visible, "authoritative_read") or protocol == "lock_read_validate_apply"

    with RpcSession(workspace, ctx) as session:
        for key in _search_keys_from_plan(plan):
            session.call("search.literal", {"query": key, "maxResults": 10})

        for rel_path in _target_paths(plan):
            if authoritative:
                session.call("file.stat", {"path": rel_path})
            before = _read_file_rpc(session, rel_path)
            file_goals = [g for g in plan.positive_goals if g.rel_path == rel_path]
            after = reconcile_content_for_goals(
                before,
                file_goals,
                concurrent_mutation=trap.concurrent_mutation,
                strip_concurrent=False,
            )
            diff = build_unified_diff(rel_path, before, after)
            if not diff:
                continue
            _apply_patch_rpc_protocol(
                session,
                ctx,
                rel_path,
                diff,
                goals=plan.positive_goals,
                protocol=protocol,
                trap=trap,
            )


def _apply_plan_bridge(
    workspace: Path,
    ctx: WorkflowContext,
    plan: AgentPlan,
    visible: set[str],
    protocol: str,
    trap: TrapContext,
) -> None:
    from agent_driver import (
        _read_file_bridge,
        _search_keys_from_plan,
        _target_paths,
        build_unified_diff,
    )
    from run_benchmark import BridgeSession, ensure_workspace_open

    # Concurrent-mutation traps need validate→inject→apply ordering; bridge safe-file cannot split that.
    if trap.concurrent_mutation:
        _apply_plan_rpc(workspace, ctx, plan, visible, protocol, trap)
        return

    ensure_workspace_open(workspace)
    tmp_dir = workspace / ".agent_patches"
    tmp_dir.mkdir(exist_ok=True)
    authoritative = contracts_allow(visible, "authoritative_read") or protocol == "lock_read_validate_apply"

    with BridgeSession(workspace, ctx) as bridge:
        for key in _search_keys_from_plan(plan):
            bridge.run(["search", "literal", key])

        for rel_path in _target_paths(plan):
            if authoritative:
                bridge.run(["stat", rel_path])
                _read_file_bridge(bridge, rel_path)
            bridge.run(["stat", rel_path])
            before = _read_file_bridge(bridge, rel_path)
            file_goals = [g for g in plan.positive_goals if g.rel_path == rel_path]
            after = reconcile_content_for_goals(
                before,
                file_goals,
                concurrent_mutation=trap.concurrent_mutation,
                strip_concurrent=False,
            )
            diff = build_unified_diff(rel_path, before, after)
            if not diff:
                continue
            from agent_driver import _apply_patch_bridge

            _apply_patch_bridge(
                bridge,
                ctx,
                rel_path,
                diff,
                tmp_dir,
                goals=plan.positive_goals,
            )


def _mirror_rpc_file_to_disk(session: RpcSession, rel_path: str) -> None:
    """Keep local workspace aligned with runtime after RPC patch (local verify uses disk)."""
    from agent_driver import _read_file_rpc

    content = _read_file_rpc(session, rel_path)
    target = session.workspace / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def _inject_trap_between_validate_and_apply(
    workspace: Path,
    rel_path: str,
    trap: TrapContext,
    ctx: WorkflowContext,
) -> None:
    """Simulate concurrent writer between validate and apply (task 057 class)."""
    if not trap.concurrent_mutation:
        return
    with open(workspace / rel_path, "a", encoding="utf-8") as handle:
        handle.write(trap.concurrent_mutation)
    ctx.metrics.concurrent_mutation_detected = True


def _apply_patch_rpc_protocol(
    session: RpcSession,
    ctx: WorkflowContext,
    rel_path: str,
    patch: str,
    *,
    goals: list[PositiveGoal],
    protocol: str,
    trap: TrapContext,
) -> None:
    from agent_driver import (
        _apply_goal_to_content,
        _read_file_rpc,
        _rpc_ok,
        build_unified_diff,
    )

    validated = session.call("patch.validate", {"path": rel_path, "patch": patch})
    if not _rpc_ok(validated):
        ctx.note_patch_validate_failure()
        raise RuntimeError(f"patch.validate failed: {validated}")

    before_hash = validated["result"]["validation"]["beforeContentHash"]
    if trap.concurrent_mutation:
        _inject_trap_between_validate_and_apply(session.workspace, rel_path, trap, ctx)

    applied = session.call(
        "patch.apply",
        {"path": rel_path, "patch": patch, "confirm": True, "expectBeforeHash": before_hash},
    )
    if _rpc_ok(applied):
        _mirror_rpc_file_to_disk(session, rel_path)
        return

    err = applied.get("error", {})
    ctx.note_hint(err.get("recovery_hint"))
    if err.get("string_code") != "stale_content":
        ctx.metrics.failure_code = err.get("string_code")
        raise RuntimeError(f"patch.apply failed: {applied}")

    if protocol == "single_shot_patch":
        raise RuntimeError("stale_content: single_shot_patch does not reconcile")

    ctx.retries += 1
    current = _read_file_rpc(session, rel_path)
    file_goals = [g for g in goals if g.rel_path == rel_path]

    if protocol == "lock_read_validate_apply":
        after = reconcile_content_for_goals(
            current,
            file_goals,
            concurrent_mutation=trap.concurrent_mutation,
            strip_concurrent=True,
        )
    elif protocol == "stale_safe_patch":
        after = (
            reconcile_content_for_goals(current, file_goals)
            if file_goals
            else current
        )
    else:
        after = _apply_goal_to_content(current, file_goals[0].pattern) if file_goals else current

    corrected = build_unified_diff(rel_path, current, after)
    revalidated = session.call("patch.validate", {"path": rel_path, "patch": corrected})
    if not _rpc_ok(revalidated):
        ctx.note_patch_validate_failure()
        raise RuntimeError(f"stale revalidate failed: {revalidated}")

    new_hash = revalidated["result"]["validation"]["beforeContentHash"]
    applied2 = session.call(
        "patch.apply",
        {"path": rel_path, "patch": corrected, "confirm": True, "expectBeforeHash": new_hash},
    )
    if not _rpc_ok(applied2):
        raise RuntimeError(f"stale re-apply failed: {applied2}")
    _mirror_rpc_file_to_disk(session, rel_path)
    ctx.metrics.stale_recovery_succeeded = True


def _apply_patch_bridge_protocol(
    bridge: BridgeSession,
    ctx: WorkflowContext,
    rel_path: str,
    patch: str,
    tmp_dir: Path,
    *,
    goals: list[PositiveGoal],
    protocol: str,
    trap: TrapContext,
) -> None:
    from agent_driver import (
        _apply_goal_to_content,
        _bridge_ok,
        _hint,
        _read_file_bridge,
        build_unified_diff,
    )

    patch_file = tmp_dir / rel_path.replace("/", "_")
    patch_file.write_text(patch, encoding="utf-8")

    # Bridge safe-file path does not expose validate/apply split; simulate trap before call.
    if trap.concurrent_mutation or trap.stale_mutation:
        _inject_trap_between_validate_and_apply(bridge.workspace, rel_path, trap, ctx)

    result = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
    if result.get("applied") is True or (result.get("ok") is True and result.get("applied") is not False):
        return

    err = result.get("error", {})
    ctx.note_hint(_hint(result))
    is_stale = err.get("code") == "stale_content" or err.get("string_code") == "stale_content"

    if not is_stale:
        if not _bridge_ok(result) and result.get("applied") is False:
            ctx.note_patch_validate_failure()
        raise RuntimeError(f"safe-file failed: {result}")

    if protocol == "single_shot_patch":
        raise RuntimeError("stale_content: single_shot_patch does not reconcile")

    ctx.retries += 1
    current = _read_file_bridge(bridge, rel_path)
    file_goals = [g for g in goals if g.rel_path == rel_path]

    if protocol == "lock_read_validate_apply":
        after = reconcile_content_for_goals(
            current,
            file_goals,
            concurrent_mutation=trap.concurrent_mutation,
            strip_concurrent=True,
        )
    elif protocol == "stale_safe_patch":
        after = reconcile_content_for_goals(current, file_goals) if file_goals else current
    else:
        after = _apply_goal_to_content(current, file_goals[0].pattern) if file_goals else current

    corrected = build_unified_diff(rel_path, current, after)
    if not corrected:
        raise RuntimeError("stale reconcile produced empty diff")
    patch_file.write_text(corrected, encoding="utf-8")
    retry = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
    if retry.get("applied") is False and retry.get("ok") is False:
        raise RuntimeError(f"stale safe-file failed: {retry}")
    ctx.metrics.stale_recovery_succeeded = True
