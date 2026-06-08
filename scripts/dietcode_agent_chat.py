#!/usr/bin/env python3
"""Bounded DietCode agent chat — Hermes + dietcode_ide + agent bridge."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from dietcode_agent_bundle import (
    CHAT_VERSION,
    AgentChatError,
    assert_chat_ready,
    observe_runtime_workspace,
    readiness_report,
    repo_root_from_script,
    resolve_context,
    run_hermes_chat,
    validate_workspace,
    workspace_authority_report,
)


def _emit(payload: dict[str, Any], *, fmt: str) -> None:
    if fmt == "json":
        print(json.dumps(payload, indent=2))
    else:
        if payload.get("ok"):
            transcript = payload.get("transcript") or payload.get("message", "")
            if transcript:
                print(transcript)
        else:
            err = payload.get("error")
            if isinstance(err, dict):
                print(err.get("message") or err, file=sys.stderr)
                hint = err.get("recoveryHint")
                if hint:
                    print(f"Recovery: {hint}", file=sys.stderr)
            else:
                print(payload.get("message") or payload, file=sys.stderr)


def _workspace_authority_for_doctor(ctx, workspace: Path | None) -> dict[str, Any] | None:
    if workspace is None:
        observed = observe_runtime_workspace(ctx)
        return {
            "requestedWorkspace": None,
            "runtimeWorkspaceBefore": observed,
            "runtimeWorkspaceAfter": observed,
            "workspaceRootObserved": observed,
            "workspaceSwitchSucceeded": True,
            "workspaceMatch": True,
        }
    return workspace_authority_report(ctx, workspace)


def cmd_version(ctx_manifest: dict[str, Any]) -> int:
    payload = {
        "ok": True,
        "action": "version",
        "chatVersion": CHAT_VERSION,
        "bundleKind": ctx_manifest.get("bundleKind"),
        "runtimeVersion": ctx_manifest.get("runtimeVersion"),
        "bridgeVersion": ctx_manifest.get("bridgeVersion"),
        "pluginVersion": ctx_manifest.get("pluginVersion"),
        "minHermesVersion": ctx_manifest.get("minHermesVersion"),
    }
    print(json.dumps(payload, indent=2))
    return 0


def cmd_doctor(repo_root: Path, ctx, *, fmt: str, workspace: Path | None) -> int:
    authority = _workspace_authority_for_doctor(ctx, workspace)
    status = readiness_report(ctx, repo_root, workspace=workspace, workspace_authority=authority)
    ok = bool(status["runtime"]["ready"]) and bool(status["bridge"]["ready"]) and bool(status["hermes"]["ready"])
    if authority and workspace is not None:
        ok = ok and bool(authority.get("workspaceMatch"))
    payload: dict[str, Any] = {
        "ok": ok,
        "action": "doctor",
        "summary": ctx.manifest.get("summary"),
        "status": status,
        "workspaceAuthority": authority,
    }
    if fmt == "json":
        print(json.dumps(payload, indent=2))
    else:
        parts = [
            f"Runtime: {'ready' if status['runtime']['ready'] else 'not ready'}",
            f"Bridge: {'ready' if status['bridge']['ready'] else 'not ready'}",
            f"Hermes: {'ready' if status['hermes']['ready'] else 'not ready'}",
        ]
        if authority:
            parts.append(f"Workspace requested: {authority.get('requestedWorkspace') or '(none)'}")
            parts.append(f"Workspace active: {authority.get('workspaceRootObserved') or '(unknown)'}")
            if not authority.get("workspaceMatch", True):
                parts.append("Workspace mismatch — agent disabled")
        elif status.get("workspace"):
            parts.append(f"Workspace: {status['workspace']}")
        print("\n".join(parts))
    return 0 if ok else 1


def cmd_chat(repo_root: Path, ctx, *, workspace: Path, prompt: str, fmt: str, max_turns: int) -> int:
    try:
        status = assert_chat_ready(ctx, repo_root, workspace)
        authority = status.get("workspaceAuthority")
        exit_code, transcript = run_hermes_chat(ctx, workspace, prompt, max_turns=max_turns)
        ok = exit_code == 0
        payload: dict[str, Any] = {
            "ok": ok,
            "action": "chat",
            "workspace": str(workspace),
            "exitCode": exit_code,
            "transcript": transcript,
            "status": status,
            "workspaceAuthority": authority,
        }
        _emit(payload, fmt=fmt)
        return 0 if ok else 10
    except AgentChatError as exc:
        payload = exc.to_dict()
        payload["action"] = "chat"
        _emit(payload, fmt=fmt)
        return exc.exit_code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="DietCode bounded agent chat CLI.")
    parser.add_argument("--workspace", help="Workspace root for agent operations")
    parser.add_argument("--prompt", help="User request for Hermes")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--doctor", action="store_true", help="Readiness doctor only")
    parser.add_argument("--version", action="store_true", help="Print chat + bundle versions")
    parser.add_argument("--app-bundle", help="Explicit DietCode.app path")
    parser.add_argument("--max-turns", type=int, default=25)
    if argv is None:
        script_file = Path(sys.argv[0])
        parsed_argv = sys.argv[1:]
    elif argv and not argv[0].startswith("-"):
        script_file = Path(argv[0])
        parsed_argv = argv[1:]
    else:
        script_file = Path(__file__)
        parsed_argv = argv
    args = parser.parse_args(parsed_argv)
    repo_root = repo_root_from_script(script_file)
    try:
        ctx = resolve_context(repo_root=repo_root, app_bundle_arg=args.app_bundle, invoked_path=script_file)
    except AgentChatError as exc:
        _emit(exc.to_dict(), fmt=args.format)
        return exc.exit_code

    if args.version:
        return cmd_version(ctx.manifest)

    workspace: Path | None = None
    if args.workspace:
        try:
            workspace = validate_workspace(args.workspace)
        except AgentChatError as exc:
            _emit(exc.to_dict(), fmt=args.format)
            return exc.exit_code

    if args.doctor:
        return cmd_doctor(repo_root, ctx, fmt=args.format, workspace=workspace)

    if not args.prompt:
        err = AgentChatError("--prompt is required for chat", code="prompt_missing", exit_code=2)
        _emit(err.to_dict(), fmt=args.format)
        return err.exit_code

    if workspace is None:
        err = AgentChatError(
            "Workspace is required. Open a folder in DietCode or pass --workspace.",
            code="workspace_missing",
            exit_code=2,
            recovery_hint="open_folder",
        )
        _emit(err.to_dict(), fmt=args.format)
        return err.exit_code

    return cmd_chat(
        repo_root,
        ctx,
        workspace=workspace,
        prompt=args.prompt,
        fmt=args.format,
        max_turns=max(1, args.max_turns),
    )


if __name__ == "__main__":
    raise SystemExit(main())
