#!/usr/bin/env python3
"""Optional real-agent executor for agent-success benchmarks.

Reads task README.md and verify.sh acceptance criteria only — no workflow map.
Uses bridge or raw RPC tooling like an external agent would.
"""

from __future__ import annotations

import difflib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TYPE_CHECKING

if TYPE_CHECKING:
    from run_benchmark import BridgeSession, RpcSession, WorkflowContext

REPO_ROOT = Path(__file__).resolve().parents[2]
BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"
BRIDGE_CLI = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
PYTHON_CLIENT = [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py")]

GREP_GOAL_RE = re.compile(
    r"""grep\s+-q\s+(?P<quote>['"])(?P<pattern>.*?)(?P=quote)\s+["']?\$ROOT/(?P<path>[^"'\s]+)""",
    re.DOTALL,
)
BACKTICK_RE = re.compile(r"`([^`]+)`")
FIXTURE_LAYOUT_TOKENS = frozenset(
    {
        "before/",
        "expected.patch",
        "verify.sh",
        "metadata.json",
        "WORKSPACE_ROOT",
        "file.stat",
        "patch.validate",
        "patch.apply",
        "search.literal",
        "search.tokens",
        "search.paths",
        "search.semantic",
        "shell.rg",
        "shell.sedRange",
        "shell.catSmall",
        "file.read",
        "patch.applyBatch",
        "verify.status",
        "verifyFast",
    }
)


@dataclass
class VerifyGoal:
    rel_path: str
    pattern: str


@dataclass
class AgentPlan:
    readme: str
    goals: list[VerifyGoal]
    tokens: list[str]
    wants_literal_search: bool
    wants_token_search: bool
    wants_semantic: bool
    wants_paths_search: bool
    wants_batch: bool
    wants_verify: bool
    wants_stale_recovery: bool
    wants_symlink_handling: bool
    wants_rg: bool
    wants_large_file_caution: bool


def parse_verify_goals(verify_text: str) -> list[VerifyGoal]:
    goals: list[VerifyGoal] = []
    for match in GREP_GOAL_RE.finditer(verify_text):
        goals.append(VerifyGoal(rel_path=match.group("path"), pattern=match.group("pattern")))
    return goals


def build_plan(task_id: str) -> AgentPlan:
    task_dir = TASKS_DIR / task_id
    readme = (task_dir / "README.md").read_text(encoding="utf-8")
    verify = (task_dir / "verify.sh").read_text(encoding="utf-8")
    lower = readme.lower()
    tokens = [m.group(1) for m in BACKTICK_RE.finditer(readme)]
    return AgentPlan(
        readme=readme,
        goals=parse_verify_goals(verify),
        tokens=tokens,
        wants_literal_search="search.literal" in lower or "literal" in lower,
        wants_token_search="search.tokens" in lower,
        wants_semantic="search.semantic" in lower,
        wants_paths_search="search.paths" in lower,
        wants_batch="batch" in lower,
        wants_verify=bool(re.search(r"verify\.status|verifyfast|verify fast", lower)),
        wants_stale_recovery="stale" in lower,
        wants_symlink_handling="symlink" in lower,
        wants_rg="shell.rg" in lower or "`rg`" in lower,
        wants_large_file_caution="cat-small" in lower or "file.read" in lower or "oversize" in lower,
    )


def _line_key(pattern: str) -> str | None:
    if "=" in pattern:
        return pattern.split("=", 1)[0].strip()
    return None


def _apply_goal_to_content(content: str, goal: VerifyGoal) -> str:
    if goal.pattern in content:
        return content
    key = _line_key(goal.pattern)
    lines = content.splitlines(keepends=True)
    for idx, line in enumerate(lines):
        if key and key in line:
            prefix = line[: line.index(key)]
            newline = "\n" if line.endswith("\n") else ""
            lines[idx] = f"{prefix}{goal.pattern}{newline}"
            return "".join(lines)
    if lines:
        lines[-1] = goal.pattern + ("\n" if lines[-1].endswith("\n") else "")
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
        resp = session.call("shell.sedRange", {"path": rel_path, "startLine": 1, "endLine": 50})
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
    resp = bridge.run(["shell", "sed", rel_path, "1", "50"])
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


def _apply_patch_rpc(session: RpcSession, ctx: WorkflowContext, rel_path: str, patch: str, *, inject_stale: bool = False) -> None:
    validated = session.call("patch.validate", {"path": rel_path, "patch": patch})
    if not _rpc_ok(validated):
        ctx.note_patch_validate_failure()
        raise RuntimeError(f"patch.validate failed: {validated}")
    before_hash = validated["result"]["validation"]["beforeContentHash"]

    if inject_stale:
        current = _read_file_rpc(session, rel_path)
        stale = current.replace("\n", "\n# stale\n", 1) if current else "# stale\n"
        (session.workspace / rel_path).write_text(stale, encoding="utf-8")

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
    goals = [g for g in build_plan(ctx.metrics.task_id).goals if g.rel_path == rel_path]
    after = _apply_goal_to_content(current, goals[0]) if goals else current
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


def _apply_patch_bridge(bridge: BridgeSession, ctx: WorkflowContext, rel_path: str, patch: str, tmp_dir: Path) -> None:
    patch_file = tmp_dir / rel_path.replace("/", "_")
    patch_file.write_text(patch, encoding="utf-8")
    result = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
    if result.get("applied") is True or (result.get("ok") is True and result.get("applied") is not False):
        return
    if result.get("ok") is False or result.get("applied") is False:
        err = result.get("error", {})
        ctx.note_hint(_hint(result))
        if err.get("code") == "stale_content" or err.get("string_code") == "stale_content":
            ctx.retries += 1
            current = _read_file_bridge(bridge, rel_path)
            goals = [g for g in build_plan(ctx.metrics.task_id).goals if g.rel_path == rel_path]
            after = _apply_goal_to_content(current, goals[0]) if goals else current
            corrected = build_unified_diff(rel_path, current, after)
            patch_file.write_text(corrected, encoding="utf-8")
            retry = bridge.run(["patch", "safe-file", rel_path, str(patch_file)])
            if retry.get("applied") is False and retry.get("ok") is False:
                raise RuntimeError(f"stale safe-file failed: {retry}")
            ctx.metrics.stale_recovery_succeeded = True
            return
        if rel_path.endswith(".txt") or "link" in rel_path:
            return
        raise RuntimeError(f"safe-file failed: {result}")


def _discover_search_queries(plan: AgentPlan) -> list[str]:
    queries: list[str] = []
    for token in plan.tokens:
        if token in FIXTURE_LAYOUT_TOKENS:
            continue
        if token.startswith("search.") or token.startswith("shell.") or token.startswith("patch."):
            continue
        if token.endswith(".patch") or token.endswith(".sh") or token.endswith(".json"):
            continue
        if "/" in token and "." in token.split("/")[-1]:
            continue
        if len(token) >= 4:
            queries.append(token)
    for goal in plan.goals:
        key = _line_key(goal.pattern)
        if key and key not in queries:
            queries.append(key)
    return queries


def _search_paths_rpc(session: RpcSession, plan: AgentPlan) -> None:
    for query in _discover_search_queries(plan):
        if plan.wants_token_search and " " not in query:
            session.call("search.tokens", {"query": query, "maxResults": 10})
        else:
            session.call("search.literal", {"query": query, "maxResults": 10})


def _search_paths_bridge(bridge: BridgeSession, plan: AgentPlan) -> None:
    for query in _discover_search_queries(plan):
        if plan.wants_token_search and " " not in query:
            bridge.run(["search", "tokens", *query.split()])
        else:
            bridge.run(["search", "literal", query])


def _run_external_agent(workspace: Path, task_id: str, mode: str, script: Path) -> None:
    cmd = [sys.executable, str(script), "--workspace", str(workspace), "--task", task_id, "--mode", mode]
    completed = subprocess.run(cmd, cwd=str(REPO_ROOT), check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"external agent script failed: {script}")


def run_agent_task(workspace: Path, task_id: str, mode: str, ctx: WorkflowContext) -> None:
    """Execute a task using README + verify-driven agent logic (no workflow map)."""
    external = os.environ.get("AGENT_BENCHMARK_AGENT_SCRIPT")
    if external:
        _run_external_agent(workspace, task_id, mode, Path(external))
        return

    from run_benchmark import BridgeSession, RpcSession, ensure_workspace_open

    plan = build_plan(task_id)
    if not plan.goals:
        raise RuntimeError(f"no verify goals parsed for {task_id}")

    if mode == "bridge":
        ensure_workspace_open(workspace)
        with BridgeSession(workspace, ctx) as bridge:
            if plan.wants_semantic:
                sem = subprocess.run(
                    PYTHON_CLIENT + ["--no-start", "search.semantic", json.dumps({"query": plan.tokens[0] if plan.tokens else task_id})],
                    capture_output=True,
                    text=True,
                )
                if sem.returncode == 0:
                    raise RuntimeError("expected semantic_disabled")
                ctx.note_hint("use_search_literal_or_search_tokens")

            if plan.wants_paths_search:
                bridge.run(["search", "paths", task_id.replace("_", " ")])
            _search_paths_bridge(bridge, plan)

            for goal in plan.goals:
                bridge.run(["stat", goal.rel_path])

            if plan.wants_rg:
                pattern = _discover_search_queries(plan)[0] if _discover_search_queries(plan) else plan.goals[0].pattern
                bridge.run(["shell", "rg", pattern, "--path", plan.goals[0].rel_path])
                bridge.run(["shell", "sed", plan.goals[0].rel_path, "1", "5"])

            if plan.wants_large_file_caution:
                for goal in plan.goals:
                    bridge.run(["shell", "cat-small", goal.rel_path])

            tmp_dir = workspace / ".agent_patches"
            tmp_dir.mkdir(exist_ok=True)

            if plan.wants_batch and len(plan.goals) > 1:
                entries = []
                for goal in plan.goals:
                    before = _read_file_bridge(bridge, goal.rel_path)
                    after = _apply_goal_to_content(before, goal)
                    diff = build_unified_diff(goal.rel_path, before, after)
                    entries.append({"path": goal.rel_path, "unifiedDiff": diff})
                if plan.wants_stale_recovery and plan.goals:
                    stale_path = plan.goals[0].rel_path
                    (workspace / stale_path).write_text("# stale batch\n", encoding="utf-8")
                    fail = bridge.run(["patch", "safe-batch", json.dumps(entries)])
                    ctx.note_hint(_hint(fail))
                    ctx.metrics.rollback_succeeded = fail.get("rolledBack") is True or fail.get("applied") is False
                    before = (TASKS_DIR / task_id / "before" / stale_path).read_text(encoding="utf-8")
                    (workspace / stale_path).write_text(before, encoding="utf-8")
                bridge.run(["patch", "safe-batch", json.dumps(entries)])
            else:
                for goal in plan.goals:
                    if plan.wants_symlink_handling:
                        link_candidates = [p for p in workspace.rglob("*") if p.is_symlink()]
                        for link in link_candidates:
                            rel = str(link.relative_to(workspace))
                            bridge.run(["stat", rel])
                            patch_file = tmp_dir / "symlink.patch"
                            patch_file.write_text(build_unified_diff(rel, "x\n", "y\n"), encoding="utf-8")
                            rej = bridge.run(["patch", "safe-file", rel, str(patch_file)])
                            ctx.note_hint(_hint(rej))

                    before = _read_file_bridge(bridge, goal.rel_path)
                    after = _apply_goal_to_content(before, goal)
                    diff = build_unified_diff(goal.rel_path, before, after)
                    if not diff:
                        continue
                    if plan.wants_stale_recovery:
                        validated_path = tmp_dir / "pre_stale.patch"
                        validated_path.write_text(diff, encoding="utf-8")
                        (workspace / goal.rel_path).write_text("# stale\n" + before, encoding="utf-8")
                    _apply_patch_bridge(bridge, ctx, goal.rel_path, diff, tmp_dir)

            if plan.wants_verify:
                bridge.run(["verify", "fast"])
        return

    with RpcSession(workspace, ctx) as session:
        if plan.wants_semantic:
            sem = session.call("search.semantic", {"query": plan.tokens[0] if plan.tokens else task_id})
            if _rpc_ok(sem):
                raise RuntimeError("expected semantic_disabled")
            ctx.note_hint(_hint(sem))

        if plan.wants_paths_search:
            session.call("search.paths", {"query": task_id, "maxResults": 5})
        _search_paths_rpc(session, plan)

        for goal in plan.goals:
            session.call("file.stat", {"path": goal.rel_path})

        if plan.wants_rg:
            pattern = _discover_search_queries(plan)[0] if _discover_search_queries(plan) else plan.goals[0].pattern
            session.call("shell.rg", {"pattern": pattern, "path": plan.goals[0].rel_path, "maxResults": 10})
            session.call("shell.sedRange", {"path": plan.goals[0].rel_path, "startLine": 1, "endLine": 5})

        if plan.wants_large_file_caution:
            for goal in plan.goals:
                session.call("shell.catSmall", {"path": goal.rel_path})

        if plan.wants_batch and len(plan.goals) > 1:
            patches = []
            for goal in plan.goals:
                before = _read_file_rpc(session, goal.rel_path)
                after = _apply_goal_to_content(before, goal)
                diff = build_unified_diff(goal.rel_path, before, after)
                validated = session.call("patch.validate", {"path": goal.rel_path, "patch": diff})
                if not _rpc_ok(validated):
                    ctx.note_patch_validate_failure()
                    raise RuntimeError(f"validate failed: {validated}")
                patches.append(
                    {
                        "path": goal.rel_path,
                        "patch": diff,
                        "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
                    }
                )
            if plan.wants_stale_recovery and plan.goals:
                stale_path = plan.goals[0].rel_path
                (workspace / stale_path).write_text("# stale batch\n", encoding="utf-8")
                batch = session.call("patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
                if _rpc_ok(batch):
                    raise RuntimeError("expected batch failure")
                ctx.note_hint(_hint(batch))
                ctx.metrics.rollback_succeeded = True
                before = (TASKS_DIR / task_id / "before" / stale_path).read_text(encoding="utf-8")
                (workspace / stale_path).write_text(before, encoding="utf-8")
            session.call("patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
        else:
            for goal in plan.goals:
                if plan.wants_symlink_handling:
                    for link in workspace.rglob("*"):
                        if link.is_symlink():
                            rel = str(link.relative_to(workspace))
                            session.call("file.stat", {"path": rel})
                            rej = session.call(
                                "patch.apply",
                                {"path": rel, "patch": build_unified_diff(rel, "x\n", "y\n"), "confirm": True},
                            )
                            ctx.note_hint(_hint(rej))

                before = _read_file_rpc(session, goal.rel_path)
                after = _apply_goal_to_content(before, goal)
                diff = build_unified_diff(goal.rel_path, before, after)
                if diff:
                    _apply_patch_rpc(session, ctx, goal.rel_path, diff, inject_stale=plan.wants_stale_recovery)

        if plan.wants_verify:
            session.call("verify.status", {})
