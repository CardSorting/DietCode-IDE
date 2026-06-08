#!/usr/bin/env python3
"""Shared DietCode agent bundle resolution, validation, and readiness checks."""

from __future__ import annotations

import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
PLUGIN_NAME = "dietcode"
CHAT_VERSION = "1.0.0"

BLOCKED_WORKSPACE_SEGMENTS = frozenset({
    "benchmarks/agent_success/fixtures",
    "benchmarks/agent_success/traces",
    "benchmarks/agent_success/expected",
})


@dataclass(frozen=True)
class BundleContext:
    app_bundle: Path | None
    app_path: Path | None
    bridge_cli: Path | None
    plugin_src: Path
    manifest: dict[str, Any]
    ide_root: Path
    source_label: str


class AgentChatError(Exception):
    def __init__(self, message: str, *, code: str, exit_code: int, recovery_hint: str = "") -> None:
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code
        self.recovery_hint = recovery_hint

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": False,
            "error": {
                "code": self.code,
                "message": str(self),
                "recoveryHint": self.recovery_hint,
            },
        }


def repo_root_from_script(script_file: Path) -> Path:
    resolved = script_file.resolve()
    for parent in resolved.parents:
        if parent.suffix == ".app":
            return parent
        if (parent / "agent-bridge" / "package.json").is_file():
            return parent
    return resolved.parents[1]


def _is_app_bundle(path: Path) -> bool:
    return path.suffix == ".app" and (path / "Contents" / "MacOS").is_dir()


def _app_bundle_locations(*, invoked_path: Path | None = None, repo_root: Path) -> list[tuple[str, Path]]:
    ordered: list[tuple[str, Path]] = []

    def queue(label: str, path: Path) -> None:
        key = str(path)
        if any(existing == key for _, existing in ordered):
            return
        ordered.append((label, path))

    env_bundle = os.environ.get("DIETCODE_APP_BUNDLE", "").strip()
    if env_bundle:
        queue("env:DIETCODE_APP_BUNDLE", Path(env_bundle).expanduser())
    if invoked_path:
        for parent in invoked_path.resolve().parents:
            if parent.suffix == ".app":
                queue("invoked:bundle", parent)
                break
    queue("build", repo_root / "build" / "DietCode.app")
    queue("system", Path("/Applications/DietCode.app"))
    queue("user", Path.home() / "Applications" / "DietCode.app")
    return ordered


def _candidate_app_bundles(*, invoked_path: Path | None, repo_root: Path) -> list[tuple[str, Path]]:
    return [
        (label, path.resolve())
        for label, path in _app_bundle_locations(invoked_path=invoked_path, repo_root=repo_root)
        if _is_app_bundle(path)
    ]


def _read_manifest(app_bundle: Path | None, repo_root: Path) -> dict[str, Any]:
    paths: list[Path] = []
    if app_bundle:
        paths.append(app_bundle / "Contents" / "Resources" / "dietcode-agent-bundle.manifest.json")
    paths.extend([
        repo_root / "resources" / "dietcode-agent-bundle.manifest.json",
        repo_root / "build" / "DietCode.app" / "Contents" / "Resources" / "dietcode-agent-bundle.manifest.json",
    ])
    for path in paths:
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    return {"bundleKind": "agent-integration-artifact", "minHermesVersion": "0.15.0"}


def _resolve_plugin_src(app_bundle: Path | None, repo_root: Path) -> Path | None:
    if app_bundle:
        bundled = app_bundle / "Contents" / "Resources" / "integrations" / "hermes" / "dietcode"
        if (bundled / "plugin.yaml").is_file():
            return bundled
    integrations = repo_root / "integrations" / "hermes-dietcode-plugin"
    if (integrations / "plugin.yaml").is_file():
        return integrations
    env_src = os.environ.get("HERMES_PLUGIN_SRC", "").strip()
    if env_src and (Path(env_src) / "plugin.yaml").is_file():
        return Path(env_src)
    installed = HERMES_HOME / "plugins" / PLUGIN_NAME
    if (installed / "plugin.yaml").is_file():
        return installed
    return None


def resolve_context(
    *,
    repo_root: Path,
    app_bundle_arg: str | None = None,
    invoked_path: Path | None = None,
) -> BundleContext:
    selected: Path | None = None
    source_label = "unknown"
    if app_bundle_arg:
        candidate = Path(app_bundle_arg).expanduser().resolve()
        if not _is_app_bundle(candidate):
            raise AgentChatError(f"Not a DietCode.app bundle: {candidate}", code="invalid_app_bundle", exit_code=2)
        selected = candidate
        source_label = "arg:--app-bundle"
    else:
        for label, candidate in _candidate_app_bundles(invoked_path=invoked_path, repo_root=repo_root):
            selected = candidate
            source_label = label
            break

    plugin_src = _resolve_plugin_src(selected, repo_root)
    if plugin_src is None:
        raise AgentChatError(
            "DietCode Hermes plugin not found. Run dietcode-enable-agent first.",
            code="plugin_missing",
            exit_code=5,
            recovery_hint="dietcode-enable-agent",
        )

    if selected:
        app_path = selected / "Contents" / "MacOS" / "DietCode"
        bridge_cli = selected / "Contents" / "Resources" / "bin" / "dietcode-agent-client"
        ide_root = selected
    else:
        app_path = repo_root / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
        bridge_cli = repo_root / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
        ide_root = repo_root

    if bridge_cli and not bridge_cli.is_file() and selected:
        js_cli = selected / "Contents" / "Resources" / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
        if js_cli.is_file():
            bridge_cli = js_cli

    manifest = _read_manifest(selected, repo_root)
    return BundleContext(
        app_bundle=selected,
        app_path=app_path if app_path.is_file() else None,
        bridge_cli=bridge_cli if bridge_cli.is_file() else None,
        plugin_src=plugin_src,
        manifest=manifest,
        ide_root=ide_root,
        source_label=source_label,
    )


def resolve_tool_path(name: str, ctx: BundleContext, repo_root: Path) -> Path | None:
    script_names = {
        "dietcode-enable-agent": "dietcode_enable_agent.py",
        "dietcode-agent-chat": "dietcode_agent_chat.py",
    }
    py_name = script_names.get(name, name)
    if ctx.app_bundle:
        for rel in (f"Contents/Resources/bin/{py_name}", f"Contents/Resources/bin/{name}"):
            path = ctx.app_bundle / rel
            if path.is_file():
                return path
    repo_script = repo_root / "scripts" / py_name
    if repo_script.is_file():
        return repo_script
    resources = repo_root / "resources" / "bin" / name
    if resources.is_file():
        return resources
    return None


def validate_workspace(path: str | Path) -> Path:
    if not path or not str(path).strip():
        raise AgentChatError(
            "Workspace is required. Open a folder in DietCode or pass --workspace.",
            code="workspace_missing",
            exit_code=2,
            recovery_hint="open_folder",
        )
    candidate = Path(str(path).strip()).expanduser()
    try:
        resolved = candidate.resolve(strict=False)
    except OSError as exc:
        raise AgentChatError(f"Workspace path invalid: {exc}", code="workspace_invalid", exit_code=3) from exc
    if not resolved.is_dir():
        raise AgentChatError(
            f"Workspace does not exist: {resolved}",
            code="workspace_missing",
            exit_code=3,
            recovery_hint="open_folder",
        )
    posix = resolved.as_posix()
    for blocked in BLOCKED_WORKSPACE_SEGMENTS:
        if blocked in posix:
            raise AgentChatError(
                f"Workspace path is blocked for agent chat: {blocked}",
                code="workspace_forbidden",
                exit_code=3,
            )
    return resolved


def find_hermes_binary() -> Path | None:
    for candidate in (
        shutil.which("hermes"),
        str(HERMES_HOME / "bin" / "hermes"),
        str(Path.home() / ".local" / "bin" / "hermes"),
    ):
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    return None


def plugin_installed() -> bool:
    return (HERMES_HOME / "plugins" / PLUGIN_NAME / "plugin.yaml").is_file()


def _parse_version(raw: str) -> tuple[int, ...]:
    match = re.search(r"(\d+(?:\.\d+)*)", raw)
    if not match:
        return (0,)
    return tuple(int(part) for part in match.group(1).split("."))


def hermes_version() -> str | None:
    hermes_bin = find_hermes_binary()
    if not hermes_bin:
        return None
    try:
        completed = subprocess.run(
            [str(hermes_bin), "--version"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        line = (completed.stdout or completed.stderr).strip().splitlines()[0]
        match = re.search(r"Hermes Agent v(\d+(?:\.\d+)*)", line)
        if match:
            return match.group(1)
    except Exception:
        return None
    return None


def _bridge_launch_prefix(ctx: BundleContext) -> list[str]:
    if not ctx.bridge_cli:
        return []
    if ctx.bridge_cli.suffix == ".js":
        return ["node", str(ctx.bridge_cli)]
    return [str(ctx.bridge_cli)]


def _normalize_workspace_path(path: str | Path | None) -> str | None:
    if not path:
        return None
    try:
        return str(Path(str(path)).expanduser().resolve())
    except OSError:
        return str(path)


def _run_bridge_profile(
    ctx: BundleContext,
    *,
    workspace: Path | None = None,
    no_start: bool = False,
    timeout: int = 45,
) -> dict[str, Any]:
    """Invoke bridge ``profile`` and return the parsed JSON payload."""
    if not ctx.bridge_cli:
        return {"ok": False, "error": "bridge_cli_missing", "code": "bridge_missing"}
    if not ctx.app_path:
        return {"ok": False, "error": "app_binary_missing", "code": "runtime_unavailable"}
    cmd = [
        *_bridge_launch_prefix(ctx),
        "--compact",
        "--wait-ready",
        "--app",
        str(ctx.app_path),
    ]
    if no_start:
        cmd.append("--no-start")
    if workspace is not None:
        cmd.extend(["--workspace", str(workspace)])
    cmd.append("profile")
    completed = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:300]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:300]}
    payload["exit_code"] = completed.returncode
    observed = _normalize_workspace_path(payload.get("workspacePath"))
    if payload.get("ok") is None:
        if workspace is not None:
            payload["ok"] = completed.returncode == 0 and observed == _normalize_workspace_path(workspace)
        else:
            payload["ok"] = completed.returncode == 0 and bool(observed)
    if observed:
        payload["workspacePath"] = observed
    return payload


def observe_runtime_workspace(ctx: BundleContext, *, timeout: int = 30) -> str | None:
    """Return the active DietCode runtime workspace root without switching."""
    ensure_runtime_socket(ctx)
    payload = _run_bridge_profile(ctx, workspace=None, no_start=True, timeout=timeout)
    return _normalize_workspace_path(payload.get("workspacePath"))


def open_runtime_workspace(ctx: BundleContext, workspace: Path, *, timeout: int = 45) -> dict[str, Any]:
    """Force workspace.openFolder on the DietCode runtime for the requested root."""
    return _run_bridge_profile(ctx, workspace=workspace, no_start=False, timeout=timeout)


def workspace_authority_report(ctx: BundleContext, requested: Path) -> dict[str, Any]:
    """Observe runtime workspace before/after opening the requested root."""
    requested_path = _normalize_workspace_path(requested)
    if not requested_path:
        raise AgentChatError("Requested workspace path is invalid.", code="workspace_invalid", exit_code=3)

    before = observe_runtime_workspace(ctx)
    opened = open_runtime_workspace(ctx, Path(requested_path))
    after = _normalize_workspace_path(opened.get("workspacePath")) or before
    observed = after
    match = observed == requested_path
    switch_needed = before != requested_path
    switch_succeeded = match and (not switch_needed or before != observed)

    return {
        "requestedWorkspace": requested_path,
        "runtimeWorkspaceBefore": before,
        "runtimeWorkspaceAfter": observed,
        "workspaceRootObserved": observed,
        "workspaceSwitchSucceeded": switch_succeeded,
        "workspaceMatch": match,
    }


def enforce_workspace_authority(ctx: BundleContext, requested: Path) -> dict[str, Any]:
    """Switch runtime to requested workspace and fail fast if authority diverges."""
    report = workspace_authority_report(ctx, requested)
    if not report["workspaceMatch"]:
        observed = report.get("workspaceRootObserved") or "(unknown)"
        raise AgentChatError(
            "Workspace mismatch:\n"
            f"requested: {report['requestedWorkspace']}\n"
            f"runtime:   {observed}\n"
            "Refusing to start agent chat against the wrong workspace.",
            code="workspace_mismatch",
            exit_code=3,
            recovery_hint="open_folder",
        )
    return report


def bridge_search_literal(
    ctx: BundleContext,
    workspace: Path,
    query: str,
    *,
    max_results: int = 10,
    timeout: int = 45,
) -> dict[str, Any]:
    """Run bridge search literal in the given workspace."""
    if not ctx.bridge_cli or not ctx.app_path:
        return {"ok": False, "error": "bridge_unavailable"}
    prefix = _bridge_launch_prefix(ctx)
    cmd = [
        *prefix,
        "--compact",
        "--wait-ready",
        "--workspace",
        str(workspace),
        "--app",
        str(ctx.app_path),
        "--max-results",
        str(max_results),
        "search",
        "literal",
        query,
    ]
    completed = subprocess.run(cmd, cwd=str(workspace), capture_output=True, text=True, check=False, timeout=timeout)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:500]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:500]}
    payload["exit_code"] = completed.returncode
    if payload.get("ok") is None:
        payload["ok"] = completed.returncode == 0
    return payload


def run_bridge_verify(ctx: BundleContext, workspace: Path | None = None) -> dict[str, Any]:
    if not ctx.bridge_cli:
        return {"ok": False, "error": "bridge_cli_missing", "code": "bridge_missing"}
    if not ctx.app_path:
        return {"ok": False, "error": "app_binary_missing", "code": "runtime_unavailable"}
    if ctx.bridge_cli.suffix == ".js":
        cmd = ["node", str(ctx.bridge_cli), "verify", "fast", "--compact", "--no-start", "--app", str(ctx.app_path)]
    else:
        cmd = [str(ctx.bridge_cli), "verify", "fast", "--compact", "--no-start", "--app", str(ctx.app_path)]
    if workspace:
        cmd.extend(["--workspace", str(workspace)])
    completed = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=45)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:300]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:300]}
    payload["exit_code"] = completed.returncode
    return payload


def ensure_runtime_socket(ctx: BundleContext) -> None:
    if not ctx.app_path:
        raise AgentChatError(
            "DietCode runtime binary missing from app bundle.",
            code="runtime_unavailable",
            exit_code=7,
            recovery_hint="reinstall_dietcode_app",
        )
    completed = subprocess.run(
        [str(ctx.app_path), "--ensure-socket", "--ensure-timeout", "15"],
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )
    if completed.returncode != 0:
        detail = (completed.stdout or completed.stderr).strip()[:300]
        raise AgentChatError(
            f"DietCode runtime socket unavailable: {detail}",
            code="runtime_unavailable",
            exit_code=7,
            recovery_hint="open_dietcode_app",
        )


def run_enable_doctor(repo_root: Path, ctx: BundleContext, *, compact: bool = True) -> dict[str, Any]:
    tool = resolve_tool_path("dietcode-enable-agent", ctx, repo_root)
    if tool is None:
        raise AgentChatError(
            "dietcode-enable-agent not found in app bundle.",
            code="enable_agent_missing",
            exit_code=6,
        )
    if tool.suffix == ".py" or tool.name.endswith(".py"):
        args = [sys.executable, str(tool), "--doctor"]
    else:
        args = [str(tool), "--doctor"]
    if compact:
        args.append("--compact")
    env = os.environ.copy()
    if ctx.app_bundle:
        env["DIETCODE_APP_BUNDLE"] = str(ctx.app_bundle)
    completed = subprocess.run(args, capture_output=True, text=True, check=False, env=env, timeout=120)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:500]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:500]}
    payload["exit_code"] = completed.returncode
    return payload


def readiness_report(
    ctx: BundleContext,
    repo_root: Path,
    *,
    workspace: Path | None = None,
    doctor: dict[str, Any] | None = None,
    bridge: dict[str, Any] | None = None,
    workspace_authority: dict[str, Any] | None = None,
) -> dict[str, Any]:
    doctor = doctor or run_enable_doctor(repo_root, ctx)
    bridge = bridge or (run_bridge_verify(ctx, workspace) if workspace else run_bridge_verify(ctx))
    hermes = hermes_version()
    min_hermes = str(ctx.manifest.get("minHermesVersion") or "0.15.0")
    hermes_ok = bool(hermes) and _parse_version(hermes) >= _parse_version(min_hermes)
    return {
        "runtime": {
            "ready": bool(ctx.app_path) and doctor.get("ok", False),
            "appPath": str(ctx.app_path) if ctx.app_path else None,
        },
        "bridge": {
            "ready": bool(bridge.get("ok")),
            "cli": str(ctx.bridge_cli) if ctx.bridge_cli else None,
            "verify": bridge,
        },
        "hermes": {
            "ready": hermes_ok and plugin_installed(),
            "version": hermes,
            "minimum": min_hermes,
            "pluginInstalled": plugin_installed(),
        },
        "workspace": str(workspace) if workspace else None,
        "workspaceAuthority": workspace_authority,
        "doctor": doctor,
    }


def assert_chat_ready(ctx: BundleContext, repo_root: Path, workspace: Path) -> dict[str, Any]:
    if not find_hermes_binary():
        raise AgentChatError(
            "Hermes is not installed. Run: dietcode-enable-agent",
            code="hermes_missing",
            exit_code=4,
            recovery_hint="dietcode-enable-agent",
        )
    if not plugin_installed():
        raise AgentChatError(
            "DietCode Hermes plugin is not installed. Run: dietcode-enable-agent",
            code="plugin_missing",
            exit_code=5,
            recovery_hint="dietcode-enable-agent",
        )
    if not ctx.bridge_cli:
        raise AgentChatError(
            "Agent bridge CLI is missing from the DietCode app bundle.",
            code="bridge_missing",
            exit_code=6,
            recovery_hint="reinstall_dietcode_app",
        )
    doctor = run_enable_doctor(repo_root, ctx)
    if not doctor.get("ok"):
        raise AgentChatError(
            f"Doctor check failed: {doctor.get('errors') or doctor.get('error')}",
            code="doctor_failed",
            exit_code=8,
            recovery_hint="dietcode-enable-agent --doctor",
        )
    ensure_runtime_socket(ctx)
    authority = enforce_workspace_authority(ctx, workspace)
    bridge = run_bridge_verify(ctx, workspace)
    if not bridge.get("ok"):
        raise AgentChatError(
            f"Bridge verify failed for workspace: {bridge.get('error', bridge)}",
            code="bridge_verify_failed",
            exit_code=9,
            recovery_hint="dietcode-enable-agent --doctor",
        )
    return readiness_report(
        ctx,
        repo_root,
        workspace=workspace,
        doctor=doctor,
        bridge=bridge,
        workspace_authority=authority,
    )


def build_system_prompt(workspace: Path, prompt: str) -> str:
    return (
        "You are operating inside DietCode.\n"
        "Use the `dietcode_ide` tool for search, file reads, shell inspection, and patches.\n"
        "Do not use raw file writes.\n"
        "Do not read benchmark metadata, expected patches, previous traces, or hidden fixture files.\n"
        "Only mutate files through the DietCode bridge.\n"
        f"Workspace: {workspace}\n"
        f"User request: {prompt}"
    )


def run_hermes_chat(
    ctx: BundleContext,
    workspace: Path,
    prompt: str,
    *,
    max_turns: int = 25,
    timeout: int = 600,
    yolo: bool = False,
) -> tuple[int, str]:
    hermes_bin = find_hermes_binary()
    if not hermes_bin:
        raise AgentChatError("Hermes missing", code="hermes_missing", exit_code=4)
    enforce_workspace_authority(ctx, workspace)
    full_prompt = build_system_prompt(workspace, prompt)
    env = os.environ.copy()
    env["HERMES_HOME"] = str(HERMES_HOME)
    env["DIETCODE_WORKSPACE"] = str(workspace)
    env["HERMES_KANBAN_WORKSPACE"] = str(workspace)
    env["HERMES_ACCEPT_HOOKS"] = "1"
    if ctx.app_bundle:
        env["DIETCODE_APP_BUNDLE"] = str(ctx.app_bundle)
    if ctx.app_path:
        env["DIETCODE_APP_PATH"] = str(ctx.app_path)
    if ctx.bridge_cli:
        env["DIETCODE_BRIDGE_CLI"] = str(ctx.bridge_cli)
    env["DIETCODE_IDE_ROOT"] = str(ctx.ide_root)
    cmd = [
        str(hermes_bin),
        "chat",
        "-q",
        full_prompt,
        "-Q",
        "-t",
        "dietcode",
        "--accept-hooks",
        "--max-turns",
        str(max_turns),
    ]
    if yolo:
        cmd.append("--yolo")
    completed = subprocess.run(
        cmd,
        cwd=str(workspace),
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=max(30, timeout),
    )
    output = (completed.stdout or "").strip()
    if not output:
        output = (completed.stderr or "").strip()
    if completed.returncode != 0 and not output:
        output = f"Hermes exited with code {completed.returncode}"
    return completed.returncode, output
