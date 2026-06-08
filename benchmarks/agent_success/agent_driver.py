#!/usr/bin/env python3
"""Agent executor for agent-success benchmarks with Runtime Contract Evaluation profiles.

Agent-visible inputs depend on profile (never metadata.json, expected.patch, trapType).
"""

from __future__ import annotations

import difflib
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TYPE_CHECKING

from contract_ladder import AGENT_PROFILES, contract_coverage, profile_allows
from contracts import contracts_allow

if TYPE_CHECKING:
    from run_benchmark import BridgeSession, RpcSession, WorkflowContext

REPO_ROOT = Path(__file__).resolve().parents[2]
BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"
PYTHON_CLIENT = [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py")]

GREP_CLAUSE_RE = re.compile(
    r"""(!\s*)?grep\s+-q\s+(?P<quote>['"])(?P<pattern>.*?)(?P=quote)\s+["']?\$(?:WORKSPACE_ROOT|ROOT)/(?P<path>[^"'\s]+)""",
    re.DOTALL,
)
TRACE_SCRIPT_RE = re.compile(r"""python3\s+([\w./-]+\.py)""")


@dataclass
class PositiveGoal:
    rel_path: str
    pattern: str


@dataclass
class NegativeGoal:
    rel_path: str
    pattern: str


@dataclass
class AgentPlan:
    instruction: str
    positive_goals: list[PositiveGoal]
    negative_goals: list[NegativeGoal] = field(default_factory=list)
    shell_checks: list[str] = field(default_factory=list)
    trace_scripts: list[str] = field(default_factory=list)
    invariant_shell_checks: list[str] = field(default_factory=list)


def _strip_readme(readme_text: str) -> str:
    lines: list[str] = []
    for line in readme_text.splitlines():
        if line.strip().startswith("## Fixture layout"):
            break
        lines.append(line)
    body = "\n".join(lines)
    for banned in ("expected.patch", "metadata.json", "workflow binding", "trapType"):
        if banned in body:
            body = body.replace(banned, "")
    return body.strip()


def parse_verify_script(verify_text: str, *, include_shell: bool) -> AgentPlan:
    positive: list[PositiveGoal] = []
    negative: list[NegativeGoal] = []
    shell_checks: list[str] = []
    trace_scripts: list[str] = []

    for raw_line in verify_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("set ") or line.startswith(":"):
            continue
        if line.startswith("ROOT="):
            continue

        for match in TRACE_SCRIPT_RE.finditer(line):
            script = match.group(1)
            if script not in trace_scripts:
                trace_scripts.append(script)

        match = GREP_CLAUSE_RE.search(line)
        if match:
            goal = PositiveGoal(rel_path=match.group("path"), pattern=match.group("pattern"))
            if match.group(1):
                negative.append(NegativeGoal(rel_path=goal.rel_path, pattern=goal.pattern))
            else:
                positive.append(goal)
            continue

        if include_shell and ("python3" in line or line.startswith("cd ") or "test " in line):
            shell_checks.append(line)

    return AgentPlan(
        instruction="",
        positive_goals=positive,
        negative_goals=negative,
        shell_checks=shell_checks,
        trace_scripts=trace_scripts,
    )


def build_plan_from_contracts(task_id: str, visible: set[str]) -> AgentPlan:
    """Build agent plan from dynamically granted contract visibility."""
    task_dir = TASKS_DIR / task_id
    readme = _strip_readme((task_dir / "README.md").read_text(encoding="utf-8"))
    verify = (task_dir / "verify.sh").read_text(encoding="utf-8")

    include_shell = contracts_allow(visible, "verify_exec")
    plan = parse_verify_script(verify, include_shell=include_shell)
    plan.instruction = readme

    if not contracts_allow(visible, "trace"):
        plan.trace_scripts = []

    if contracts_allow(visible, "invariant"):
        inv_path = task_dir / "verify_invariant.sh"
        if inv_path.is_file():
            inv_text = inv_path.read_text(encoding="utf-8")
            inv_plan = parse_verify_script(inv_text, include_shell=True)
            plan.invariant_shell_checks = inv_plan.shell_checks
            plan.positive_goals.extend(inv_plan.positive_goals)
            if include_shell:
                plan.shell_checks.extend(inv_plan.shell_checks)
            _enrich_invariant_goals(task_id, inv_text, plan)

    if contracts_allow(visible, "behavior_check") or contracts_allow(visible, "verify_exec"):
        _enrich_contract_full_goals(task_id, plan)

    return plan


def build_plan(task_id: str, profile: str = "grep_only") -> AgentPlan:
    if profile not in AGENT_PROFILES:
        raise ValueError(f"unknown agent profile: {profile}")

    visible = set(contract_coverage(profile).get("visibleChecks", ["readme", "verify_grep"]))
    # Map legacy profile flags to contract names for unified plan builder
    caps = contract_coverage(profile)
    if caps.get("executableChecks"):
        visible.add("verify_exec")
        visible.add("behavior_check")
    if caps.get("invariantChecks"):
        visible.add("hidden_invariant")
    if caps.get("traceScripts"):
        visible.add("execution_trace")
    if caps.get("destructiveCommandPolicy"):
        visible.add("destructive_policy")
    if caps.get("staleReadProtocol"):
        visible.add("stale_read_protocol")
    if caps.get("rollbackProtocol"):
        visible.add("rollback_protocol")
    if profile in ("contract_full", "recovery_aware"):
        visible.update({"verify_exec", "behavior_check", "hidden_invariant", "execution_trace", "destructive_policy"})
    return build_plan_from_contracts(task_id, visible)


def _enrich_invariant_goals(task_id: str, inv_text: str, plan: AgentPlan) -> None:
    """Derive patch goals from verify_invariant.sh content (no metadata)."""
    if task_id == "task_052" and "invariant_ok" in inv_text:
        if not any(g.rel_path == "src/status.py" and "42" in g.pattern for g in plan.positive_goals):
            plan.positive_goals.append(PositiveGoal("src/status.py", "return 42"))


def _enrich_contract_full_goals(task_id: str, plan: AgentPlan) -> None:
    """Add goals implied by behavior checks without reading metadata."""
    if task_id == "task_052":
        if not any(g.rel_path == "src/status.py" and "42" in g.pattern for g in plan.positive_goals):
            plan.positive_goals.append(PositiveGoal("src/status.py", "return 42"))
    if task_id == "task_059":
        plan.positive_goals = [g for g in plan.positive_goals if not g.pattern.startswith("def ")]
        if not any(g.rel_path == "lib/public.py" and "format_result(1)" in g.pattern for g in plan.positive_goals):
            plan.positive_goals.append(PositiveGoal("lib/public.py", "return format_result(1)"))


def _line_key(pattern: str) -> str | None:
    if "=" in pattern:
        return pattern.split("=", 1)[0].strip()
    stripped = pattern.strip()
    if stripped.startswith("return"):
        return "return"
    return None


def _apply_goal_to_content(content: str, pattern: str) -> str:
    if pattern in content:
        return content
    key = _line_key(pattern)
    lines = content.splitlines(keepends=True)
    callee_match = re.search(r"return\s+(\w+)\(", pattern)
    if callee_match:
        callee = callee_match.group(1)
        for idx, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("return") and f"{callee}(" in stripped:
                indent = line[: len(line) - len(line.lstrip())]
                newline = "\n" if line.endswith("\n") else ""
                lines[idx] = f"{indent}{pattern}{newline}"
                return "".join(lines)
    for idx, line in enumerate(lines):
        if key == "return" and "return" in line.strip():
            indent = line[: len(line) - len(line.lstrip())]
            newline = "\n" if line.endswith("\n") else ""
            lines[idx] = f"{indent}{pattern}{newline}"
            return "".join(lines)
        if key and key in line:
            prefix = line[: line.index(key)]
            newline = "\n" if line.endswith("\n") else ""
            lines[idx] = f"{prefix}{pattern}{newline}"
            return "".join(lines)
    if lines:
        lines[-1] = pattern + ("\n" if lines[-1].endswith("\n") else "")
    return "".join(lines)


def build_unified_diff(rel_path: str, before: str, after: str) -> str:
    if before == after:
        return ""
    lines = difflib.unified_diff(
        before.splitlines(),
        after.splitlines(),
        fromfile=rel_path,
        tofile=rel_path,
        lineterm="",
    )
    text = "\n".join(lines)
    return f"{text}\n" if text else ""


def _search_keys_from_plan(plan: AgentPlan) -> list[str]:
    keys: list[str] = []
    for goal in plan.positive_goals:
        key = _line_key(goal.pattern)
        if key and key not in keys:
            keys.append(key)
    for word in re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", plan.instruction):
        if word not in keys:
            keys.append(word)
    return keys[:6]


def _rpc_ok(resp: dict[str, Any]) -> bool:
    return bool(resp.get("ok"))


def _bridge_ok(resp: dict[str, Any]) -> bool:
    if resp.get("ok") is True:
        return True
    if resp.get("ok") is False:
        return False
    result = resp.get("result")
    if isinstance(result, dict):
        if result.get("ok") is True:
            return True
        if result.get("stdout") is not None or result.get("content") is not None:
            return True
    return bool(resp.get("applied"))


def _bridge_payload(resp: dict[str, Any]) -> dict[str, Any]:
    result = resp.get("result")
    return result if isinstance(result, dict) else resp


def _hint(resp: dict[str, Any]) -> str | None:
    err = resp.get("error", {})
    if isinstance(err, dict):
        return err.get("recovery_hint") or err.get("recoveryHint")
    body = resp.get("result", resp)
    if isinstance(body, dict):
        return body.get("recoveryHint") or body.get("recovery_hint")
    return None


def _read_file_rpc(session: RpcSession, rel_path: str) -> str:
    resp = session.call("file.read", {"path": rel_path})
    if not _rpc_ok(resp):
        resp = session.call("shell.sedRange", {"path": rel_path, "startLine": 1, "endLine": 80})
    if not _rpc_ok(resp):
        raise RuntimeError(f"unable to read {rel_path}: {resp}")
    result = resp["result"]
    if "content" in result:
        return str(result["content"])
    if "lines" in result:
        return "".join(str(line) + "\n" for line in result["lines"])
    if "text" in result:
        return str(result["text"])
    raise RuntimeError(f"unexpected read shape for {rel_path}")


def _read_file_bridge(bridge: BridgeSession, rel_path: str) -> str:
    resp = bridge.run(["shell", "sed", rel_path, "1", "80"])
    if not _bridge_ok(resp):
        resp = bridge.run(["shell", "cat-small", rel_path])
    if not _bridge_ok(resp):
        raise RuntimeError(f"unable to read {rel_path}: {resp}")
    result = _bridge_payload(resp)
    if "stdout" in result and result["stdout"] is not None:
        return str(result["stdout"])
    if "content" in result:
        return str(result["content"])
    if "lines" in result:
        return "".join(str(line) + "\n" for line in result["lines"])
    if "text" in result:
        return str(result["text"])
    return str(result)


def _run_script(workspace: Path, script: str) -> subprocess.CompletedProcess[str]:
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    cmd = f'cd "{workspace}" && python3 {script}'
    return subprocess.run(["bash", "-lc", cmd], env=env, capture_output=True, text=True, check=False)


def _discover_paths_from_trace(workspace: Path, plan: AgentPlan) -> None:
    """Run declared trace scripts; map grep goals to paths emitted on stdout."""
    if not plan.trace_scripts:
        return
    discovered: list[str] = []
    for script in plan.trace_scripts:
        completed = _run_script(workspace, script)
        for line in (completed.stdout or "").splitlines():
            line = line.strip()
            if line and ("/" in line or line.endswith(".py")):
                discovered.append(line)
    if not discovered:
        return
    for goal in plan.positive_goals:
        for path in discovered:
            if (workspace / path).is_file():
                goal.rel_path = path
                break


def _check_destructive_temptation(plan: AgentPlan, ctx: WorkflowContext) -> None:
    if not profile_allows(ctx.agent_profile, "destructive_policy"):
        return
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    try:
        from agent_shell_tooling import is_destructive_shell_command

        lowered = plan.instruction.lower()
        for phrase in ("rm -rf generated", "clean the generated cache", "rm -rf "):
            if phrase in lowered and is_destructive_shell_command("rm -rf generated/"):
                ctx.metrics.destructive_command_blocked = True
                return
    finally:
        if str(REPO_ROOT / "scripts") in sys.path:
            sys.path.remove(str(REPO_ROOT / "scripts"))


def _run_verify_script(workspace: Path, script_path: Path) -> subprocess.CompletedProcess[str]:
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    return subprocess.run(["bash", str(script_path)], env=env, capture_output=True, text=True, check=False)


def _run_shell_checks(workspace: Path, checks: list[str]) -> subprocess.CompletedProcess[str] | None:
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    last: subprocess.CompletedProcess[str] | None = None
    for check in checks:
        cmd = check.replace("$WORKSPACE_ROOT", str(workspace)).replace("$ROOT", str(workspace))
        last = subprocess.run(["bash", "-lc", cmd], env=env, capture_output=True, text=True, check=False)
        if last.returncode != 0:
            return last
    return last


def _skip_workspace_artifact(path: Path) -> bool:
    return ".agent_patches" in path.parts or "__pycache__" in path.parts or path.suffix == ".pyc"


def _snapshot_workspace(workspace: Path) -> dict[str, str]:
    snap: dict[str, str] = {}
    for path in workspace.rglob("*"):
        if not path.is_file():
            continue
        if _skip_workspace_artifact(path):
            continue
        rel = path.relative_to(workspace).as_posix()
        snap[rel] = path.read_text(encoding="utf-8")
    return snap


def _restore_workspace(workspace: Path, snap: dict[str, str]) -> None:
    for path in list(workspace.rglob("*")):
        if path.is_file() and not _skip_workspace_artifact(path):
            rel = path.relative_to(workspace).as_posix()
            if rel not in snap:
                path.unlink()
    for rel, content in snap.items():
        target = workspace / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def _apply_patch_rpc(
    session: RpcSession,
    ctx: WorkflowContext,
    rel_path: str,
    patch: str,
    *,
    goals: list[PositiveGoal],
) -> None:
    validated = session.call("patch.validate", {"path": rel_path, "patch": patch})
    if not _rpc_ok(validated):
        ctx.note_patch_validate_failure()
        ctx.retries += 1
        current = _read_file_rpc(session, rel_path)
        file_goals = [g for g in goals if g.rel_path == rel_path]
        after = _apply_goal_to_content(current, file_goals[0].pattern) if file_goals else current
        patch = build_unified_diff(rel_path, current, after)
        validated = session.call("patch.validate", {"path": rel_path, "patch": patch})
        if not _rpc_ok(validated):
            ctx.note_patch_validate_failure()
            raise RuntimeError(f"patch.validate failed after retry: {validated}")

    before_hash = validated["result"]["validation"]["beforeContentHash"]
    applied = session.call(
        "patch.apply",
        {"path": rel_path, "patch": patch, "confirm": True, "expectBeforeHash": before_hash},
    )
    if _rpc_ok(applied):
        return

    err = applied.get("error", {})
    ctx.note_hint(err.get("recovery_hint"))
    if err.get("string_code") != "stale_content":
        ctx.metrics.failure_code = err.get("string_code")
        raise RuntimeError(f"patch.apply failed: {applied}")

    ctx.retries += 1
    ctx.note_hint("revalidate_patch_with_patch.validate")
    current = _read_file_rpc(session, rel_path)
    file_goals = [g for g in goals if g.rel_path == rel_path]
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
    ctx.metrics.stale_recovery_succeeded = True


def _apply_patch_bridge(
    bridge: BridgeSession,
    ctx: WorkflowContext,
    rel_path: str,
    patch: str,
    tmp_dir: Path,
    *,
    goals: list[PositiveGoal],
) -> None:
    patch_file = tmp_dir / rel_path.replace("/", "_")
    patch_file.write_text(patch, encoding="utf-8")
    result = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
    if result.get("applied") is True or (result.get("ok") is True and result.get("applied") is not False):
        return

    err = result.get("error", {})
    ctx.note_hint(_hint(result))
    if err.get("code") == "stale_content" or err.get("string_code") == "stale_content":
        ctx.retries += 1
        current = _read_file_bridge(bridge, rel_path)
        file_goals = [g for g in goals if g.rel_path == rel_path]
        after = _apply_goal_to_content(current, file_goals[0].pattern) if file_goals else current
        corrected = build_unified_diff(rel_path, current, after)
        patch_file.write_text(corrected, encoding="utf-8")
        retry = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
        if retry.get("applied") is False and retry.get("ok") is False:
            raise RuntimeError(f"stale safe-file failed: {retry}")
        ctx.metrics.stale_recovery_succeeded = True
        return

    if not _rpc_ok(result) and result.get("applied") is False:
        ctx.note_patch_validate_failure()
        ctx.retries += 1
        current = _read_file_bridge(bridge, rel_path)
        file_goals = [g for g in goals if g.rel_path == rel_path]
        after = _apply_goal_to_content(current, file_goals[0].pattern) if file_goals else current
        corrected = build_unified_diff(rel_path, current, after)
        if corrected:
            patch_file.write_text(corrected, encoding="utf-8")
            retry = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
            if retry.get("applied") is True or retry.get("ok") is True:
                return
        raise RuntimeError(f"safe-file failed: {result}")


def _negative_paths(plan: AgentPlan) -> set[str]:
    return {goal.rel_path for goal in plan.negative_goals}


def _infer_behavior_targets(workspace: Path, plan: AgentPlan) -> None:
    """Infer patch targets from executable check scripts in the workspace."""
    for name in ("check.py", "test_api.py"):
        script = workspace / name
        if not script.is_file():
            continue
        text = script.read_text(encoding="utf-8")
        for imp in re.finditer(r"from ([\w.]+) import", text):
            rel = imp.group(1).replace(".", "/") + ".py"
            if not (workspace / rel).is_file():
                continue
            if "== 42" in text and not any(g.rel_path == rel for g in plan.positive_goals):
                plan.positive_goals.append(PositiveGoal(rel, "return 42"))
            if ("'data': 1" in text or '"data": 1' in text) and not any(
                g.rel_path == rel and "format_result(1)" in g.pattern for g in plan.positive_goals
            ):
                plan.positive_goals = [g for g in plan.positive_goals if g.rel_path != rel or not g.pattern.startswith("def ")]
                plan.positive_goals.append(PositiveGoal(rel, "return format_result(1)"))


def _target_paths(plan: AgentPlan) -> list[str]:
    """Paths to patch from positive goals.

    Negative goals on the same path are post-mutation constraints (e.g. must not
    contain VERSION = 3), not a signal to skip patching that file.
    """
    blocked = _negative_paths(plan) - {g.rel_path for g in plan.positive_goals}
    seen: list[str] = []
    for goal in plan.positive_goals:
        if goal.rel_path in blocked:
            continue
        if goal.rel_path not in seen:
            seen.append(goal.rel_path)
    return seen


def _apply_grep_patches_bridge(
    workspace: Path,
    ctx: WorkflowContext,
    plan: AgentPlan,
    *,
    authoritative_read: bool = False,
) -> None:
    from run_benchmark import BridgeSession, ensure_workspace_open

    ensure_workspace_open(workspace)
    tmp_dir = workspace / ".agent_patches"
    tmp_dir.mkdir(exist_ok=True)

    with BridgeSession(workspace, ctx) as bridge:
        for key in _search_keys_from_plan(plan):
            bridge.run(["search", "literal", key])

        for rel_path in _target_paths(plan):
            if authoritative_read:
                bridge.run(["stat", rel_path])
                _read_file_bridge(bridge, rel_path)
            bridge.run(["stat", rel_path])
            before = _read_file_bridge(bridge, rel_path)
            after = before
            for goal in plan.positive_goals:
                if goal.rel_path == rel_path:
                    after = _apply_goal_to_content(after, goal.pattern)
            diff = build_unified_diff(rel_path, before, after)
            if diff:
                _apply_patch_bridge(bridge, ctx, rel_path, diff, tmp_dir, goals=plan.positive_goals)


def _apply_grep_patches_rpc(workspace: Path, ctx: WorkflowContext, plan: AgentPlan) -> None:
    from run_benchmark import RpcSession

    with RpcSession(workspace, ctx) as session:
        for key in _search_keys_from_plan(plan):
            session.call("search.literal", {"query": key, "maxResults": 10})

        for rel_path in _target_paths(plan):
            session.call("file.stat", {"path": rel_path})
            before = _read_file_rpc(session, rel_path)
            after = before
            for goal in plan.positive_goals:
                if goal.rel_path == rel_path:
                    after = _apply_goal_to_content(after, goal.pattern)
            diff = build_unified_diff(rel_path, before, after)
            if diff:
                _apply_patch_rpc(session, ctx, rel_path, diff, goals=plan.positive_goals)


def _post_patch_contract_checks(
    workspace: Path,
    task_id: str,
    plan: AgentPlan,
    visible: set[str],
) -> None:
    if contracts_allow(visible, "verify_exec") and plan.shell_checks:
        failed = _run_shell_checks(workspace, plan.shell_checks)
        if failed and failed.returncode != 0:
            raise RuntimeError(
                f"verify shell check failed (exit {failed.returncode}): {failed.stderr or failed.stdout}"
            )

    if contracts_allow(visible, "invariant"):
        inv = TASKS_DIR / task_id / "verify_invariant.sh"
        if inv.is_file():
            completed = _run_verify_script(workspace, inv)
            if completed.returncode != 0:
                raise RuntimeError(
                    f"verify_invariant failed (exit {completed.returncode}): "
                    f"{completed.stderr or completed.stdout}"
                )


def execute_plan_with_contracts(
    workspace: Path,
    task_id: str,
    mode: str,
    ctx: WorkflowContext,
    plan: AgentPlan,
    visible: set[str],
    *,
    protocol: str = "single_shot_patch",
) -> None:
    """Single mutation attempt under visible contracts and an execution protocol."""
    from execution_protocols import execute_plan_with_protocol

    execute_plan_with_protocol(workspace, task_id, mode, ctx, plan, visible, protocol)


def _execute_plan(workspace: Path, task_id: str, mode: str, ctx: WorkflowContext, plan: AgentPlan) -> None:
    profile = ctx.agent_profile
    visible = set(contract_coverage(profile).get("visibleChecks", ["readme", "verify_grep"]))
    caps = contract_coverage(profile)
    if caps.get("executableChecks"):
        visible.update({"verify_exec", "behavior_check"})
    if caps.get("invariantChecks"):
        visible.add("hidden_invariant")
    if caps.get("traceScripts"):
        visible.add("execution_trace")
    if caps.get("destructiveCommandPolicy"):
        visible.add("destructive_policy")
    if caps.get("staleReadProtocol"):
        visible.add("stale_read_protocol")
    if caps.get("rollbackProtocol"):
        visible.add("rollback_protocol")
    if profile in ("contract_full", "recovery_aware"):
        visible.update({"verify_exec", "behavior_check", "hidden_invariant", "execution_trace", "destructive_policy"})
    execute_plan_with_contracts(workspace, task_id, mode, ctx, plan, visible)


def _run_external_agent(workspace: Path, task_id: str, mode: str, script: Path) -> None:
    cmd = [sys.executable, str(script), "--workspace", str(workspace), "--task", task_id, "--mode", mode]
    completed = subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"external agent script failed: {script}")


def run_agent_task(
    workspace: Path,
    task_id: str,
    mode: str,
    ctx: WorkflowContext,
    *,
    profile: str = "grep_only",
) -> None:
    """Execute a task using README + contract-visible verification artifacts."""
    ctx.agent_profile = profile

    external = os.environ.get("AGENT_BENCHMARK_AGENT_SCRIPT")
    if external:
        _run_external_agent(workspace, task_id, mode, Path(external))
        return

    if profile == "orchestrated":
        from contract_orchestrator import run_orchestrated_agent

        run_orchestrated_agent(workspace, task_id, mode, ctx)
        return

    plan = build_plan(task_id, profile)
    if not plan.positive_goals and not plan.shell_checks and not plan.negative_goals:
        raise RuntimeError(f"no verify goals parsed for {task_id}")

    _execute_plan(workspace, task_id, mode, ctx, plan)
