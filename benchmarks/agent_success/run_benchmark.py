#!/usr/bin/env python3
"""Agent success benchmark runner — Mode A (raw RPC) and Mode B (Agent Bridge)."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

REPO_ROOT = Path(__file__).resolve().parents[2]
BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"
RESULTS_DIR = BENCHMARK_ROOT / "results"
WORKSPACES_DIR = BENCHMARK_ROOT / ".workspaces"

sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(BENCHMARK_ROOT))
from dietcode_agent_client import connect, load_token, send_rpc  # noqa: E402

PYTHON_CLIENT = [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py")]
BRIDGE_CLI = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"


@dataclass
class RunMetrics:
    task_id: str
    mode: str
    executor: str = "reference"
    task_success: bool = False
    verify_passed: bool = False
    wrong_file_edited: bool = False
    stale_recovery_succeeded: bool = False
    rollback_succeeded: bool = False
    retries: int = 0
    tool_call_count: int = 0
    duration_ms: float = 0.0
    failure_code: str | None = None
    recovery_hints_used: list[str] = field(default_factory=list)
    commands_used: list[str] = field(default_factory=list)
    patch_validate_failures: int = 0

    def to_json(self) -> dict[str, Any]:
        return {
            "type": "task_result",
            "taskId": self.task_id,
            "mode": self.mode,
            "executor": self.executor,
            "taskSuccess": self.task_success,
            "verifyPassed": self.verify_passed,
            "wrongFileEdited": self.wrong_file_edited,
            "staleRecoverySucceeded": self.stale_recovery_succeeded,
            "rollbackSucceeded": self.rollback_succeeded,
            "retries": self.retries,
            "toolCallCount": self.tool_call_count,
            "durationMs": round(self.duration_ms, 2),
            "failureCode": self.failure_code,
            "recoveryHintsUsed": self.recovery_hints_used,
            "commandsUsed": self.commands_used,
            "patchValidateFailures": self.patch_validate_failures,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }


@dataclass
class WorkflowContext:
    workspace: Path
    meta: dict[str, Any]
    patch: str
    metrics: RunMetrics
    tool_calls: int = 0
    retries: int = 0
    hints: list[str] = field(default_factory=list)
    commands_used: list[str] = field(default_factory=list)
    patch_validate_failures: int = 0

    def note_hint(self, hint: str | None) -> None:
        if hint and hint not in self.hints:
            self.hints.append(hint)

    def note_command(self, command: str) -> None:
        self.commands_used.append(command)

    def note_patch_validate_failure(self) -> None:
        self.patch_validate_failures += 1

    def bump(self, n: int = 1) -> None:
        self.tool_calls += n


def _sync_metrics_from_ctx(ctx: WorkflowContext) -> None:
    ctx.metrics.tool_call_count = ctx.tool_calls
    ctx.metrics.retries = ctx.retries
    ctx.metrics.recovery_hints_used = list(ctx.hints)
    ctx.metrics.commands_used = list(ctx.commands_used)
    ctx.metrics.patch_validate_failures = ctx.patch_validate_failures


def _rpc_ok(resp: dict[str, Any]) -> bool:
    return bool(resp.get("ok"))


class RpcSession:
    def __init__(self, workspace: Path, ctx: WorkflowContext) -> None:
        self.workspace = workspace
        self.ctx = ctx
        self.sock: socket.socket | None = None
        self.token: str | None = None

    def __enter__(self) -> RpcSession:
        self.sock = connect(start=True)
        self.token = load_token()
        self._open_workspace()
        return self

    def __exit__(self, *args: object) -> None:
        if self.sock is not None:
            self.sock.close()

    def _open_workspace(self) -> None:
        assert self.sock and self.token
        self.ctx.bump()
        self.ctx.note_command("workspace.openFolder")
        resp = send_rpc(self.sock, self.token, "workspace.openFolder", {"path": str(self.workspace)})
        if not resp.get("ok"):
            raise RuntimeError(f"workspace.openFolder failed: {resp}")

    def call(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        assert self.sock and self.token
        self.ctx.bump()
        self.ctx.note_command(method)
        resp = send_rpc(self.sock, self.token, method, params or {})
        if method == "patch.validate" and not _rpc_ok(resp):
            self.ctx.note_patch_validate_failure()
        return resp


class BridgeSession:
    def __init__(self, workspace: Path, ctx: WorkflowContext) -> None:
        self.workspace = workspace
        self.ctx = ctx

    def __enter__(self) -> BridgeSession:
        if not BRIDGE_CLI.exists():
            raise RuntimeError(f"bridge CLI not built: {BRIDGE_CLI} — run `make agent-bridge-fast`")
        return self

    def __exit__(self, *args: object) -> None:
        pass

    def run(self, args: list[str]) -> dict[str, Any]:
        self.ctx.bump()
        self.ctx.note_command(" ".join(args))
        cmd = ["node", str(BRIDGE_CLI), "--compact", "--no-start", "--workspace", str(self.workspace), *args]
        completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            try:
                return json.loads((completed.stderr or completed.stdout).strip().splitlines()[-1])
            except (json.JSONDecodeError, IndexError):
                return {"ok": False, "error": {"code": "bridge_cli_error", "message": completed.stderr or completed.stdout}}
        line = completed.stdout.strip().splitlines()[-1]
        return json.loads(line)


def copy_task_workspace(task_id: str) -> Path:
    src = TASKS_DIR / task_id / "before"
    if not src.is_dir():
        raise FileNotFoundError(f"missing fixture: {src}")
    WORKSPACES_DIR.mkdir(parents=True, exist_ok=True)
    dest = WORKSPACES_DIR / f"{task_id}_{uuid.uuid4().hex[:8]}"
    shutil.copytree(src, dest, symlinks=True)
    for outside in (TASKS_DIR / task_id / f"{task_id}_outside", TASKS_DIR / f"{task_id}_outside"):
        if outside.is_dir():
            dest_outside = dest.parent / f"{task_id}_outside"
            if dest_outside.exists():
                shutil.rmtree(dest_outside)
            shutil.copytree(outside, dest_outside, symlinks=True)
            break
    return dest


def ensure_workspace_open(workspace: Path) -> None:
    """Open the task workspace on the shared runtime (required before bridge CLI reuse)."""
    with connect(start=False) as sock:
        resp = send_rpc(sock, load_token(), "workspace.openFolder", {"path": str(workspace)})
        if not resp.get("ok"):
            raise RuntimeError(f"workspace.openFolder failed: {resp}")


def load_task(task_id: str) -> dict[str, Any]:
    with open(TASKS_DIR / task_id / "metadata.json", encoding="utf-8") as handle:
        return json.load(handle)


def load_expected_patch(task_id: str) -> str:
    return (TASKS_DIR / task_id / "expected.patch").read_text(encoding="utf-8")


def run_verify(task_id: str, workspace: Path) -> bool:
    script = TASKS_DIR / task_id / "verify.sh"
    env = {**os.environ, "WORKSPACE_ROOT": str(workspace)}
    completed = subprocess.run(["bash", str(script)], env=env, capture_output=True, text=True, check=False)
    return completed.returncode == 0


def check_wrong_files(workspace: Path, target_files: list[str], task_id: str, meta: dict[str, Any] | None = None) -> bool:
    before_root = TASKS_DIR / task_id / "before"
    targets = set(target_files)
    if meta:
        targets.update(meta.get("decoyFiles", []))
    for path in workspace.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        rel = str(path.relative_to(workspace))
        if rel in targets:
            continue
        before_path = before_root / rel
        if before_path.is_file() and before_path.read_text(encoding="utf-8") != path.read_text(encoding="utf-8"):
            return True
    return False


def _hint(resp: dict[str, Any]) -> str | None:
    err = resp.get("error", {})
    if isinstance(err, dict):
        return err.get("recovery_hint") or err.get("recoveryHint")
    body = resp.get("result", resp)
    if isinstance(body, dict):
        return body.get("recoveryHint") or body.get("recovery_hint")
    return None


def _extract_file_patch(full_patch: str, path: str) -> str:
    blocks: list[str] = []
    current: list[str] = []
    in_target = False
    for line in full_patch.splitlines(keepends=True):
        if line.startswith("--- "):
            if current and in_target:
                blocks.append("".join(current))
            current = [line]
            in_target = line[4:].strip() == path
        elif current:
            current.append(line)
    if current and in_target:
        blocks.append("".join(current))
    if not blocks:
        raise ValueError(f"no patch block for {path}")
    return blocks[0]


def _correct_patch_for_content(patch: str, content: str) -> str:
    for line in patch.splitlines():
        if line.startswith("-") and not line.startswith("---"):
            return patch.replace(line, f"-{content.rstrip()}", 1)
    return patch


def apply_patch_rpc(session: RpcSession, path: str, patch: str, *, stale_mutation: str | None = None) -> None:
    ctx = session.ctx
    validated = session.call("patch.validate", {"path": path, "patch": patch})
    if not _rpc_ok(validated):
        raise RuntimeError(f"patch.validate failed: {validated}")
    before_hash = validated["result"]["validation"]["beforeContentHash"]

    if stale_mutation is not None:
        (session.workspace / path).write_text(stale_mutation, encoding="utf-8")

    applied = session.call(
        "patch.apply",
        {"path": path, "patch": patch, "confirm": True, "expectBeforeHash": before_hash},
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
    content = (session.workspace / path).read_text(encoding="utf-8")
    corrected = _correct_patch_for_content(patch, content)
    revalidated = session.call("patch.validate", {"path": path, "patch": corrected})
    if not _rpc_ok(revalidated):
        raise RuntimeError(f"stale revalidate failed: {revalidated}")
    new_hash = revalidated["result"]["validation"]["beforeContentHash"]
    applied2 = session.call(
        "patch.apply",
        {"path": path, "patch": corrected, "confirm": True, "expectBeforeHash": new_hash},
    )
    if not _rpc_ok(applied2):
        raise RuntimeError(f"stale re-apply failed: {applied2}")
    ctx.metrics.stale_recovery_succeeded = True


def apply_batch_rpc(session: RpcSession, targets: list[str], full_patch: str) -> None:
    patches = []
    for target in targets:
        file_patch = _extract_file_patch(full_patch, target)
        validated = session.call("patch.validate", {"path": target, "patch": file_patch})
        if not _rpc_ok(validated):
            raise RuntimeError(f"patch.validate failed for {target}")
        patches.append(
            {
                "path": target,
                "patch": file_patch,
                "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            }
        )
    batch = session.call("patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
    if not _rpc_ok(batch):
        raise RuntimeError(f"patch.applyBatch failed: {batch}")


# --- RPC workflows ---


def wf_literal_search_patch(session: RpcSession, ctx: WorkflowContext) -> None:
    search = session.call("search.literal", {"query": ctx.meta["searchQuery"], "maxResults": 10})
    if not _rpc_ok(search):
        raise RuntimeError(f"search.literal failed: {search}")
    result = search["result"]
    if result.get("truncated") or result.get("partial"):
        ctx.note_hint(result.get("recoveryHint"))
    session.call("file.stat", {"path": ctx.meta["targetFiles"][0]})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_token_search_patch(session: RpcSession, ctx: WorkflowContext) -> None:
    query = " ".join(ctx.meta["searchTokens"])
    search = session.call("search.tokens", {"query": query, "maxResults": 10})
    if not _rpc_ok(search):
        raise RuntimeError(f"search.tokens failed: {search}")
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_multi_file_patch(session: RpcSession, ctx: WorkflowContext) -> None:
    for target in ctx.meta["targetFiles"]:
        apply_patch_rpc(session, target, _extract_file_patch(ctx.patch, target))


def wf_multi_file_batch_patch(session: RpcSession, ctx: WorkflowContext) -> None:
    apply_batch_rpc(session, ctx.meta["targetFiles"], ctx.patch)


def wf_stale_content_recovery(session: RpcSession, ctx: WorkflowContext) -> None:
    apply_patch_rpc(
        session,
        ctx.meta["targetFiles"][0],
        ctx.patch,
        stale_mutation=ctx.meta.get("staleMutation"),
    )


def wf_symlink_rejection(session: RpcSession, ctx: WorkflowContext) -> None:
    rejected = session.call(
        "patch.apply",
        {"path": ctx.meta["symlinkPath"], "patch": ctx.patch, "confirm": True},
    )
    if _rpc_ok(rejected):
        raise RuntimeError("expected symlink rejection")
    err = rejected.get("error", {})
    ctx.note_hint(err.get("recovery_hint"))
    if err.get("string_code") not in ("symlink_target", "permission_denied"):
        raise RuntimeError(f"unexpected error: {err}")
    apply_patch_rpc(session, ctx.meta["realPath"], ctx.patch)


def wf_symlink_escape_read(session: RpcSession, ctx: WorkflowContext) -> None:
    escape = session.call("file.stat", {"path": ctx.meta["escapeLink"]})
    ctx.note_hint(_hint(escape))
    apply_patch_rpc(session, ctx.meta["realPath"], ctx.patch)


def wf_large_file_shell_avoidance(session: RpcSession, ctx: WorkflowContext) -> None:
    cat = session.call("shell.catSmall", {"path": ctx.meta["largePath"]})
    if _rpc_ok(cat):
        result = cat["result"]
        if result.get("partial") or result.get("truncated"):
            ctx.note_hint(result.get("recoveryHint") or "use_shell_head_tail_or_sedRange")
    anchor = ctx.meta["anchorPath"]
    session.call("shell.sedRange", {"path": anchor, "startLine": 1, "endLine": 3})
    apply_patch_rpc(session, anchor, ctx.patch)


def wf_large_file_read_avoidance(session: RpcSession, ctx: WorkflowContext) -> None:
    read = session.call("file.read", {"path": ctx.meta["largePath"]})
    if _rpc_ok(read):
        result = read["result"]
        if result.get("partial") or result.get("truncated"):
            ctx.note_hint(result.get("recoveryHint"))
    header = ctx.meta["headerPath"]
    session.call("shell.head", {"path": header, "lines": 5})
    apply_patch_rpc(session, header, ctx.patch)


def wf_shell_rg_sed_patch(session: RpcSession, ctx: WorkflowContext) -> None:
    target = ctx.meta["targetPath"]
    rg = session.call("shell.rg", {"pattern": ctx.meta["pattern"], "path": target, "maxResults": 10})
    if not _rpc_ok(rg):
        raise RuntimeError(f"shell.rg failed: {rg}")
    line = rg["result"]["matches"][0]["line"]
    session.call("shell.sedRange", {"path": target, "startLine": max(1, line - 1), "endLine": line + 1})
    apply_patch_rpc(session, target, ctx.patch)


def wf_batch_rollback(session: RpcSession, ctx: WorkflowContext) -> None:
    targets = ctx.meta["targetFiles"]
    patches = []
    for target in targets:
        file_patch = _extract_file_patch(ctx.patch, target)
        validated = session.call("patch.validate", {"path": target, "patch": file_patch})
        if not _rpc_ok(validated):
            raise RuntimeError(f"validate failed: {validated}")
        patches.append(
            {
                "path": target,
                "patch": file_patch,
                "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            }
        )
    stale_file = ctx.meta["staleFile"]
    (session.workspace / stale_file).write_text(ctx.meta["staleMutation"], encoding="utf-8")
    batch = session.call("patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
    if _rpc_ok(batch):
        raise RuntimeError("expected batch failure")
    ctx.note_hint(_hint(batch))
    unchanged = all(
        (session.workspace / t).read_text(encoding="utf-8") == (TASKS_DIR / ctx.meta["id"] / "before" / t).read_text(encoding="utf-8")
        for t in targets
    )
    ctx.metrics.rollback_succeeded = unchanged
    for target in targets:
        before = (TASKS_DIR / ctx.meta["id"] / "before" / target).read_text(encoding="utf-8")
        (session.workspace / target).write_text(before, encoding="utf-8")
    apply_batch_rpc(session, targets, ctx.patch)


def wf_batch_validation_rollback(session: RpcSession, ctx: WorkflowContext) -> None:
    targets = ctx.meta["targetFiles"]
    patches = []
    for target in targets:
        file_patch = _extract_file_patch(ctx.patch, target)
        validated = session.call("patch.validate", {"path": target, "patch": file_patch})
        if not _rpc_ok(validated):
            raise RuntimeError(f"validate failed: {validated}")
        patches.append(
            {
                "path": target,
                "patch": file_patch,
                "expectBeforeHash": validated["result"]["validation"]["beforeContentHash"],
            }
        )
    bad = ctx.meta["badPatchFile"]
    (session.workspace / bad).write_text("y = 99\n", encoding="utf-8")
    batch = session.call("patch.applyBatch", {"patches": patches, "confirm": True, "dryRun": False})
    if not _rpc_ok(batch):
        ctx.metrics.rollback_succeeded = True
        ctx.note_hint(_hint(batch))
    (session.workspace / bad).write_text("y = 1\n", encoding="utf-8")
    apply_batch_rpc(session, targets, ctx.patch)


def wf_semantic_recovery(session: RpcSession, ctx: WorkflowContext) -> None:
    sem = session.call("search.semantic", {"query": ctx.meta["semanticQuery"]})
    if _rpc_ok(sem):
        raise RuntimeError("expected semantic_disabled")
    err = sem.get("error", {})
    ctx.note_hint(err.get("recovery_hint"))
    if err.get("string_code") != "semantic_disabled":
        raise RuntimeError(f"unexpected: {err}")
    lit = session.call("search.literal", {"query": ctx.meta["literalQuery"], "maxResults": 5})
    if not _rpc_ok(lit):
        raise RuntimeError(f"search.literal failed: {lit}")
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_semantic_paths_recovery(session: RpcSession, ctx: WorkflowContext) -> None:
    sem = session.call("search.semantic", {"query": ctx.meta["semanticQuery"]})
    if _rpc_ok(sem):
        raise RuntimeError("expected semantic_disabled")
    ctx.note_hint(_hint(sem))
    session.call("search.paths", {"query": ctx.meta["pathsQuery"], "maxResults": 5})
    session.call("search.literal", {"query": ctx.meta["literalQuery"], "maxResults": 5})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_partial_search_pagination(session: RpcSession, ctx: WorkflowContext) -> None:
    query = ctx.meta["searchQuery"]
    max_results = int(ctx.meta.get("maxResults", 2))
    offset = 0
    found = False
    while not found:
        search = session.call(
            "search.literal",
            {"query": query, "maxResults": max_results, "resultOffset": offset},
        )
        if not _rpc_ok(search):
            raise RuntimeError(f"search failed: {search}")
        result = search["result"]
        if result.get("truncated") or result.get("hasMore"):
            ctx.note_hint(result.get("recoveryHint") or "paginate_search")
        items = result.get("results", result.get("matches", []))
        for match in items:
            if match.get("path") == ctx.meta["targetPath"]:
                found = True
                break
        if result.get("hasMore"):
            offset = int(result.get("nextResultOffset", offset + max_results))
        else:
            break
    if not found:
        raise RuntimeError("target not found via pagination")
    apply_patch_rpc(session, ctx.meta["targetPath"], ctx.patch)


def wf_partial_grep_truncation(session: RpcSession, ctx: WorkflowContext) -> None:
    query = ctx.meta["searchQuery"]
    grep = session.call("workspace.grep", {"query": query, "maxResults": ctx.meta.get("maxResults", 1)})
    if not _rpc_ok(grep):
        raise RuntimeError(f"grep failed: {grep}")
    if grep["result"].get("truncated"):
        ctx.note_hint("narrow_include_glob")
        session.call(
            "workspace.grep",
            {"query": query, "maxResults": 10, "include": [ctx.meta["targetPath"]]},
        )
    apply_patch_rpc(session, ctx.meta["targetPath"], ctx.patch)


def wf_verify_after_mutation(session: RpcSession, ctx: WorkflowContext) -> None:
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)
    session.call("verify.status", {})


def wf_verify_after_mutation_batch(session: RpcSession, ctx: WorkflowContext) -> None:
    apply_batch_rpc(session, ctx.meta["targetFiles"], ctx.patch)
    session.call("verify.status", {})


def wf_adv_wrong_file_decoy(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("search.literal", {"query": "TIMEOUT_MS", "maxResults": 10})
    session.call("file.stat", {"path": ctx.meta["targetFiles"][0]})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_adv_verify_only(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("file.stat", {"path": ctx.meta["targetFiles"][0]})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_adv_preserve_partial(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("file.read", {"path": ctx.meta["targetFiles"][0]})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_adv_failed_patch_retry(session: RpcSession, ctx: WorkflowContext) -> None:
    path = ctx.meta["targetFiles"][0]
    bad = ctx.meta.get("badPatch", "")
    bad_val = session.call("patch.validate", {"path": path, "patch": bad})
    if not _rpc_ok(bad_val):
        ctx.note_patch_validate_failure()
    ctx.retries += 1
    apply_patch_rpc(session, path, ctx.patch)


def wf_adv_multi_file_coord(session: RpcSession, ctx: WorkflowContext) -> None:
    for target in ctx.meta["targetFiles"]:
        apply_patch_rpc(session, target, _extract_file_patch(ctx.patch, target))


def wf_adv_stale_read(session: RpcSession, ctx: WorkflowContext) -> None:
    apply_patch_rpc(
        session,
        ctx.meta["targetFiles"][0],
        ctx.patch,
        stale_mutation=ctx.meta.get("staleMutation"),
    )


def wf_adv_rollback_corruption(session: RpcSession, ctx: WorkflowContext) -> None:
    path = ctx.meta["targetFiles"][0]
    task_id = ctx.meta["id"]
    before = (TASKS_DIR / task_id / "before" / path).read_text(encoding="utf-8")
    bad = ctx.meta.get("badPatch", "")
    bad_val = session.call("patch.validate", {"path": path, "patch": bad})
    if _rpc_ok(bad_val):
        before_hash = bad_val["result"]["validation"]["beforeContentHash"]
        applied = session.call(
            "patch.apply",
            {"path": path, "patch": bad, "confirm": True, "expectBeforeHash": before_hash},
        )
        if not _rpc_ok(applied):
            ctx.note_hint(_hint(applied))
    (session.workspace / path).write_text(before, encoding="utf-8")
    ctx.metrics.rollback_succeeded = True
    apply_patch_rpc(session, path, ctx.patch)


def wf_adv_noop_trap(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("shell.rg", {"pattern": "MARKER", "path": "app.py", "maxResults": 5})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_adv_path_containment(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("file.stat", {"path": ctx.meta["targetFiles"][0]})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


def wf_adv_ambiguous_symbol(session: RpcSession, ctx: WorkflowContext) -> None:
    session.call("search.literal", {"query": "fetch", "maxResults": 10})
    session.call("file.read", {"path": "providers/__init__.py"})
    apply_patch_rpc(session, ctx.meta["targetFiles"][0], ctx.patch)


RPC_WORKFLOWS: dict[str, Callable[[RpcSession, WorkflowContext], None]] = {
    "literal_search_patch": wf_literal_search_patch,
    "token_search_patch": wf_token_search_patch,
    "multi_file_patch": wf_multi_file_patch,
    "multi_file_batch_patch": wf_multi_file_batch_patch,
    "stale_content_recovery": wf_stale_content_recovery,
    "symlink_rejection": wf_symlink_rejection,
    "symlink_escape_read": wf_symlink_escape_read,
    "large_file_shell_avoidance": wf_large_file_shell_avoidance,
    "large_file_read_avoidance": wf_large_file_read_avoidance,
    "shell_rg_sed_patch": wf_shell_rg_sed_patch,
    "batch_rollback": wf_batch_rollback,
    "batch_validation_rollback": wf_batch_validation_rollback,
    "semantic_recovery": wf_semantic_recovery,
    "semantic_paths_recovery": wf_semantic_paths_recovery,
    "partial_search_pagination": wf_partial_search_pagination,
    "partial_grep_truncation": wf_partial_grep_truncation,
    "verify_after_mutation": wf_verify_after_mutation,
    "verify_after_mutation_batch": wf_verify_after_mutation_batch,
    "adv_wrong_file_decoy": wf_adv_wrong_file_decoy,
    "adv_verify_only": wf_adv_verify_only,
    "adv_preserve_partial": wf_adv_preserve_partial,
    "adv_failed_patch_retry": wf_adv_failed_patch_retry,
    "adv_multi_file_coord": wf_adv_multi_file_coord,
    "adv_stale_read": wf_adv_stale_read,
    "adv_rollback_corruption": wf_adv_rollback_corruption,
    "adv_noop_trap": wf_adv_noop_trap,
    "adv_path_containment": wf_adv_path_containment,
    "adv_ambiguous_symbol": wf_adv_ambiguous_symbol,
}


def run_task_rpc(workspace: Path, ctx: WorkflowContext) -> None:
    workflow = RPC_WORKFLOWS.get(ctx.meta["workflow"])
    if workflow is None:
        raise RuntimeError(f"unknown workflow: {ctx.meta['workflow']}")
    with RpcSession(workspace, ctx) as session:
        workflow(session, ctx)
    _sync_metrics_from_ctx(ctx)


def run_task_bridge(workspace: Path, ctx: WorkflowContext) -> None:
    meta = ctx.meta
    workflow = meta["workflow"]
    task_id = meta["id"]
    patch_file = TASKS_DIR / task_id / "expected.patch"
    ensure_workspace_open(workspace)

    # Stale recovery requires mutating between validate and apply — use RPC workflow.
    if workflow in ("stale_content_recovery", "adv_stale_read"):
        run_task_rpc(workspace, ctx)
        return

    adv_bridge_rpc = {
        "adv_failed_patch_retry",
        "adv_rollback_corruption",
        "adv_multi_file_coord",
        "adv_noop_trap",
    }
    if workflow in adv_bridge_rpc:
        run_task_rpc(workspace, ctx)
        return

    with BridgeSession(workspace, ctx) as bridge:
        if workflow == "literal_search_patch":
            bridge.run(["search", "literal", meta["searchQuery"]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow == "token_search_patch":
            bridge.run(["search", "tokens", *meta["searchTokens"]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow == "multi_file_patch":
            for target in meta["targetFiles"]:
                fp = workspace / f"_patch_{target.replace('/', '_')}"
                fp.write_text(_extract_file_patch(ctx.patch, target), encoding="utf-8")
                bridge.run(["patch", "safe-file", target, str(fp)])
        elif workflow in ("multi_file_batch_patch", "verify_after_mutation_batch"):
            entries = [
                {"path": t, "unifiedDiff": _extract_file_patch(ctx.patch, t)} for t in meta["targetFiles"]
            ]
            bridge.run(["patch", "safe-batch", json.dumps(entries)])
        elif workflow == "symlink_rejection":
            rej = bridge.run(["patch", "safe-file", meta["symlinkPath"], str(patch_file)])
            if rej.get("ok") is not False and rej.get("applied") is not False:
                raise RuntimeError("expected symlink rejection")
            ctx.note_hint(_hint(rej))
            bridge.run(["patch", "safe-file", meta["realPath"], str(patch_file)])
        elif workflow == "symlink_escape_read":
            bridge.run(["stat", meta["escapeLink"]])
            bridge.run(["patch", "safe-file", meta["realPath"], str(patch_file)])
        elif workflow == "large_file_shell_avoidance":
            bridge.run(["shell", "cat-small", meta["largePath"]])
            bridge.run(["shell", "sed", meta["anchorPath"], "1", "3"])
            bridge.run(["patch", "safe-file", meta["anchorPath"], str(patch_file)])
        elif workflow == "large_file_read_avoidance":
            bridge.run(["shell", "cat-small", meta["largePath"]])
            bridge.run(["shell", "head", meta["headerPath"], "--lines", "5"])
            bridge.run(["patch", "safe-file", meta["headerPath"], str(patch_file)])
        elif workflow == "shell_rg_sed_patch":
            bridge.run(["shell", "rg", meta["pattern"], "--path", meta["targetPath"]])
            bridge.run(["shell", "sed", meta["targetPath"], "1", "3"])
            bridge.run(["patch", "safe-file", meta["targetPath"], str(patch_file)])
        elif workflow == "batch_rollback":
            entries = [{"path": t, "unifiedDiff": _extract_file_patch(ctx.patch, t)} for t in meta["targetFiles"]]
            (workspace / meta["staleFile"]).write_text(meta["staleMutation"], encoding="utf-8")
            fail = bridge.run(["patch", "safe-batch", json.dumps(entries)])
            if fail.get("applied") is not False:
                ctx.metrics.rollback_succeeded = bool(fail.get("rolledBack"))
            for t in meta["targetFiles"]:
                before = (TASKS_DIR / task_id / "before" / t).read_text(encoding="utf-8")
                (workspace / t).write_text(before, encoding="utf-8")
            bridge.run(["patch", "safe-batch", json.dumps(entries)])
        elif workflow == "batch_validation_rollback":
            entries = [{"path": t, "unifiedDiff": _extract_file_patch(ctx.patch, t)} for t in meta["targetFiles"]]
            (workspace / meta["badPatchFile"]).write_text("y = 99\n", encoding="utf-8")
            fail = bridge.run(["patch", "safe-batch", json.dumps(entries)])
            ctx.metrics.rollback_succeeded = fail.get("rolledBack") is True or fail.get("applied") is False
            (workspace / meta["badPatchFile"]).write_text("y = 1\n", encoding="utf-8")
            bridge.run(["patch", "safe-batch", json.dumps(entries)])
        elif workflow == "semantic_recovery":
            sem = subprocess.run(
                PYTHON_CLIENT + ["--no-start", "search.semantic", json.dumps({"query": meta["semanticQuery"]})],
                capture_output=True,
                text=True,
            )
            if sem.returncode == 0:
                raise RuntimeError("expected semantic_disabled")
            ctx.note_hint("use_search_literal_or_search_tokens")
            bridge.run(["search", "literal", meta["literalQuery"]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow == "semantic_paths_recovery":
            subprocess.run(
                PYTHON_CLIENT + ["--no-start", "search.semantic", json.dumps({"query": meta["semanticQuery"]})],
                capture_output=True,
            )
            bridge.run(["search", "paths", meta["pathsQuery"]])
            bridge.run(["search", "literal", meta["literalQuery"]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow == "partial_search_pagination":
            bridge.run(["search", "literal", meta["searchQuery"]])
            bridge.run(["patch", "safe-file", meta["targetPath"], str(patch_file)])
        elif workflow == "partial_grep_truncation":
            bridge.run(["search", "literal", meta["searchQuery"]])
            bridge.run(["patch", "safe-file", meta["targetPath"], str(patch_file)])
        elif workflow == "verify_after_mutation":
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
            bridge.run(["verify", "fast"])
        elif workflow == "adv_wrong_file_decoy":
            bridge.run(["search", "literal", "TIMEOUT_MS"])
            bridge.run(["stat", meta["targetFiles"][0]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow in ("adv_verify_only", "adv_preserve_partial", "adv_path_containment"):
            bridge.run(["stat", meta["targetFiles"][0]])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        elif workflow == "adv_ambiguous_symbol":
            bridge.run(["search", "literal", "fetch"])
            bridge.run(["patch", "safe-file", meta["targetFiles"][0], str(patch_file)])
        else:
            raise RuntimeError(f"unsupported bridge workflow: {workflow}")

        if meta.get("expectsVerify") and workflow != "verify_after_mutation":
            bridge.run(["verify", "fast"])

    _sync_metrics_from_ctx(ctx)


def run_single_task(task_id: str, mode: str, *, executor: str = "reference") -> RunMetrics:
    metrics = RunMetrics(task_id=task_id, mode=mode, executor=executor)
    started = time.monotonic()
    workspace: Path | None = None
    try:
        meta = load_task(task_id)
        meta["id"] = task_id
        patch = load_expected_patch(task_id)
        workspace = copy_task_workspace(task_id)
        ctx = WorkflowContext(workspace=workspace, meta=meta, patch=patch, metrics=metrics)
        if executor == "reference":
            if mode == "raw_rpc":
                run_task_rpc(workspace, ctx)
            elif mode == "bridge":
                run_task_bridge(workspace, ctx)
            else:
                raise ValueError(f"unknown mode: {mode}")
        elif executor == "agent":
            from agent_driver import run_agent_task

            run_agent_task(workspace, task_id, mode, ctx)
            _sync_metrics_from_ctx(ctx)
        else:
            raise ValueError(f"unknown executor: {executor}")
        metrics.task_success = True
    except Exception as exc:
        metrics.failure_code = metrics.failure_code or type(exc).__name__
    finally:
        metrics.duration_ms = (time.monotonic() - started) * 1000.0
        if workspace and metrics.task_success:
            try:
                meta = load_task(task_id)
                metrics.verify_passed = run_verify(task_id, workspace)
                metrics.wrong_file_edited = check_wrong_files(
                    workspace, meta.get("targetFiles", []), task_id, meta
                )
                if not metrics.verify_passed:
                    metrics.task_success = False
            except Exception:
                metrics.verify_passed = False
                metrics.task_success = False
        if workspace and WORKSPACES_DIR in workspace.parents:
            shutil.rmtree(workspace, ignore_errors=True)
    return metrics


def list_tasks() -> list[str]:
    if not TASKS_DIR.is_dir():
        return []
    return sorted(p.name for p in TASKS_DIR.iterdir() if p.is_dir() and p.name.startswith("task_"))


def write_results(results: list[RunMetrics], run_id: str) -> Path:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out = RESULTS_DIR / f"{run_id}.jsonl"
    with open(out, "w", encoding="utf-8") as handle:
        for item in results:
            handle.write(json.dumps(item.to_json(), separators=(",", ":")) + "\n")
        summary = {
            "type": "summary",
            "runId": run_id,
            "tasks": len(results),
            "passed": sum(1 for r in results if r.task_success and r.verify_passed),
            "failed": sum(1 for r in results if not (r.task_success and r.verify_passed)),
            "modes": sorted({r.mode for r in results}),
            "executors": sorted({r.executor for r in results}),
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        handle.write(json.dumps(summary, separators=(",", ":")) + "\n")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Run agent success benchmarks.")
    parser.add_argument("--mode", choices=["raw_rpc", "bridge", "both"], default="both")
    parser.add_argument(
        "--executor",
        choices=["reference", "agent"],
        default="reference",
        help="reference = deterministic workflow baseline; agent = README-driven agent driver.",
    )
    parser.add_argument("--task", action="append", help="Run specific task id (repeatable).")
    parser.add_argument("--assume-server-ready", action="store_true")
    parser.add_argument("--run-id", help="Results filename stem.")
    args = parser.parse_args()

    if not args.assume_server_ready:
        subprocess.run(PYTHON_CLIENT + ["--wait-ready", "--compact", "--quiet"], cwd=str(REPO_ROOT), check=False)

    tasks = args.task or list_tasks()
    if not tasks:
        print("no tasks found — run generate_fixtures.py first", file=sys.stderr)
        return 1

    run_id = args.run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    modes = ["raw_rpc", "bridge"] if args.mode == "both" else [args.mode]
    results: list[RunMetrics] = []

    for task_id in tasks:
        for mode in modes:
            metrics = run_single_task(task_id, mode, executor=args.executor)
            results.append(metrics)
            print(json.dumps(metrics.to_json(), separators=(",", ":")))

    out = write_results(results, run_id)
    ok = all(r.task_success and r.verify_passed for r in results)
    print(json.dumps({"type": "benchmark_complete", "ok": ok, "resultsFile": str(out)}, separators=(",", ":")))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
