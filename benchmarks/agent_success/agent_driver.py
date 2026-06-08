#!/usr/bin/env python3
"""Optional real-agent executor for agent-success benchmarks.

Agent-visible inputs only:
  - README.md (instruction text — no fixture layout section)
  - verify.sh (acceptance criteria)
  - workspace files via bridge / RPC tools

Does NOT read metadata.json, expected.patch, trapType, or workflow bindings.
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
SHELL_CHECK_RE = re.compile(r"""^\s*(?:cd\s+["']?\$WORKSPACE_ROOT["']?\s*&&\s*)?(.+)$""")


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


def _strip_readme(readme_text: str) -> str:
    """Keep only the agent-facing instruction — drop harness fixture layout."""
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


def parse_verify_script(verify_text: str) -> AgentPlan:
    positive: list[PositiveGoal] = []
    negative: list[NegativeGoal] = []
    shell_checks: list[str] = []

    for raw_line in verify_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("set ") or line.startswith(":"):
            continue
        if line.startswith("ROOT="):
            continue

        match = GREP_CLAUSE_RE.search(line)
        if match:
            goal = PositiveGoal(rel_path=match.group("path"), pattern=match.group("pattern"))
            if match.group(1):
                negative.append(NegativeGoal(rel_path=goal.rel_path, pattern=goal.pattern))
            else:
                positive.append(goal)
            continue

        if "python3" in line or line.startswith("cd "):
            shell_checks.append(line)

    return AgentPlan(instruction="", positive_goals=positive, negative_goals=negative, shell_checks=shell_checks)


def build_plan(task_id: str) -> AgentPlan:
    task_dir = TASKS_DIR / task_id
    readme = _strip_readme((task_dir / "README.md").read_text(encoding="utf-8"))
    verify = (task_dir / "verify.sh").read_text(encoding="utf-8")
    plan = parse_verify_script(verify)
    plan.instruction = readme
    return plan


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


def _run_shell_checks(workspace: Path, checks: list[str]) -> None:
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    for check in checks:
        cmd = check.replace("$WORKSPACE_ROOT", str(workspace))
        completed = subprocess.run(["bash", "-lc", cmd], env=env, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            raise RuntimeError(f"shell check failed: {cmd}\n{completed.stderr}")


def _run_external_agent(workspace: Path, task_id: str, mode: str, script: Path) -> None:
    cmd = [sys.executable, str(script), "--workspace", str(workspace), "--task", task_id, "--mode", mode]
    completed = subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"external agent script failed: {script}")


def _target_paths(plan: AgentPlan) -> list[str]:
    seen: list[str] = []
    for goal in plan.positive_goals:
        if goal.rel_path not in seen:
            seen.append(goal.rel_path)
    return seen


def _execute_plan_bridge(workspace: Path, ctx: WorkflowContext, plan: AgentPlan) -> None:
    from run_benchmark import BridgeSession, ensure_workspace_open

    ensure_workspace_open(workspace)
    tmp_dir = workspace / ".agent_patches"
    tmp_dir.mkdir(exist_ok=True)

    with BridgeSession(workspace, ctx) as bridge:
        for key in _search_keys_from_plan(plan):
            bridge.run(["search", "literal", key])

        for rel_path in _target_paths(plan):
            bridge.run(["stat", rel_path])
            before = _read_file_bridge(bridge, rel_path)
            after = before
            for goal in plan.positive_goals:
                if goal.rel_path == rel_path:
                    after = _apply_goal_to_content(after, goal.pattern)
            diff = build_unified_diff(rel_path, before, after)
            if diff:
                _apply_patch_bridge(bridge, ctx, rel_path, diff, tmp_dir, goals=plan.positive_goals)

        if plan.shell_checks:
            _run_shell_checks(workspace, plan.shell_checks)


def _execute_plan_rpc(workspace: Path, ctx: WorkflowContext, plan: AgentPlan) -> None:
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

        if plan.shell_checks:
            _run_shell_checks(workspace, plan.shell_checks)


def run_agent_task(workspace: Path, task_id: str, mode: str, ctx: WorkflowContext) -> None:
    """Execute a task using README + verify.sh only."""
    external = os.environ.get("AGENT_BENCHMARK_AGENT_SCRIPT")
    if external:
        _run_external_agent(workspace, task_id, mode, Path(external))
        return

    plan = build_plan(task_id)
    if not plan.positive_goals and not plan.shell_checks:
        raise RuntimeError(f"no verify goals parsed for {task_id}")

    if mode == "bridge":
        _execute_plan_bridge(workspace, ctx, plan)
    elif mode == "raw_rpc":
        _execute_plan_rpc(workspace, ctx, plan)
    else:
        raise ValueError(f"unknown mode: {mode}")
