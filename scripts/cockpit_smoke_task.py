#!/usr/bin/env python3
"""Deterministic governed-task runner for cockpit vertical-slice smoke (no Hermes)."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from dietcode_agent_client import connect, load_token, send_rpc  # noqa: E402

PROBE_NAME = "probe.py"
APPROVAL_TIMEOUT = float(__import__("os").environ.get("COCKPIT_SMOKE_APPROVAL_TIMEOUT", "120"))


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_event(event_type: str, task_id: str, **payload: Any) -> None:
    record = {
        "type": event_type,
        "taskId": task_id,
        "timestamp": _iso_now(),
        "source": "smoke-task",
        **payload,
    }
    print(json.dumps(record, ensure_ascii=False), flush=True)


def _probe_rel_path(workspace: Path, kernel_root: Path) -> str:
    if workspace.resolve() == kernel_root.resolve():
        return PROBE_NAME
    rel = workspace.resolve().relative_to(kernel_root.resolve())
    return str(rel / PROBE_NAME)


def _build_patch(probe_rel: str) -> str:
    return (
        f"--- {probe_rel}\n"
        f"+++ {probe_rel}\n"
        "@@ -1,4 +1,4 @@\n"
        ' """Smoke probe — patch changes VALUE from 1 to 2."""\n'
        " \n"
        "-VALUE = 1\n"
        "+VALUE = 2\n"
    )


def _approval_status(result: dict[str, Any]) -> str | None:
    if not result.get("ok"):
        return None
    body = result.get("result") or {}
    if isinstance(body.get("status"), str):
        return body["status"]
    approval = body.get("approval")
    if isinstance(approval, dict) and isinstance(approval.get("status"), str):
        return approval["status"]
    return None


def _wait_for_approval(sock, token: str, approval_id: str, task_id: str) -> bool:
    deadline = time.monotonic() + APPROVAL_TIMEOUT
    while time.monotonic() < deadline:
        polled = send_rpc(sock, token, "approval.get", {"approvalId": approval_id})
        status = _approval_status(polled)
        if status == "approved":
            emit_event("approval.resolved", task_id, approvalId=approval_id, decision="approved")
            return True
        if status in {"rejected", "expired", "failed"}:
            emit_event(
                "task.failed",
                task_id,
                exitCode=2,
                error=f"Approval {approval_id} ended with status {status}",
            )
            return False
        time.sleep(0.35)
    emit_event("task.failed", task_id, exitCode=2, error="Approval wait timed out")
    return False


def run_smoke_task(*, task_id: str, message: str, workspace: Path, mode: str) -> int:
    workspace = workspace.resolve()
    emit_event(
        "task.started",
        task_id,
        message=message,
        workspace=str(workspace),
        mode=mode,
    )

    try:
        sock = connect()
        token = load_token()

        root = send_rpc(sock, token, "workspace.getRoot", {})
        kernel_root = Path(str((root.get("result") or {}).get("path") or "")).resolve()
        if not kernel_root.exists():
            raise RuntimeError(f"kernel workspace root missing: {kernel_root}")
        try:
            workspace.resolve().relative_to(kernel_root)
        except ValueError as exc:
            raise RuntimeError(
                f"task workspace {workspace} is not under kernel root {kernel_root}"
            ) from exc
        probe_rel = _probe_rel_path(workspace, kernel_root)

        status = send_rpc(sock, token, "workspace.status", {"taskId": task_id})
        if not status.get("ok"):
            raise RuntimeError(f"workspace.status failed: {status}")
        emit_event(
            "context.read",
            task_id,
            action="workspace.status",
            driftDetected=bool(status.get("result", {}).get("driftDetected")),
        )

        read = send_rpc(sock, token, "file.read", {"path": probe_rel, "taskId": task_id})
        if not read.get("ok"):
            raise RuntimeError(f"file.read failed: {read}")
        coherence = (read.get("result") or {}).get("coherence") or {}
        emit_event("context.read", task_id, action="file.read", path=probe_rel)

        patch = _build_patch(probe_rel)
        validated = send_rpc(sock, token, "patch.validate", {"path": probe_rel, "patch": patch})
        if not validated.get("ok"):
            raise RuntimeError(f"patch.validate failed: {validated}")
        validation = validated["result"]["validation"]
        if not validation.get("ok"):
            raise RuntimeError(f"patch validation rejected: {validation}")

        apply_params: dict[str, Any] = {
            "path": probe_rel,
            "patch": patch,
            "confirm": True,
            "expectBeforeHash": validation["beforeContentHash"],
            "taskId": task_id,
        }
        if coherence.get("tokenId"):
            apply_params["coherenceTokenId"] = coherence["tokenId"]
        if coherence.get("workspaceRevision") is not None:
            apply_params["expectedWorkspaceRevision"] = coherence["workspaceRevision"]
        applied = send_rpc(sock, token, "patch.apply", apply_params)
        if not applied.get("ok"):
            raise RuntimeError(f"patch.apply failed: {applied}")

        result = applied.get("result") or {}
        if result.get("approvalRequired"):
            approval = result.get("approval") or {}
            approval_id = approval.get("approvalId")
            if not approval_id:
                raise RuntimeError("approvalRequired without approvalId")
            emit_event("approval.required", task_id, approvalId=approval_id)
            if not _wait_for_approval(sock, token, str(approval_id), task_id):
                return 2
        elif not result.get("applied") and not result.get("complete"):
            raise RuntimeError(f"patch.apply did not apply: {result}")

        probe_text = (workspace / PROBE_NAME).read_text(encoding="utf-8")
        if "VALUE = 2" not in probe_text:
            raise RuntimeError("probe.py was not updated to VALUE = 2")

        emit_event(
            "mutation.applied",
            task_id,
            path=probe_rel,
            changedPaths=[probe_rel],
        )
        emit_event("task.completed", task_id, exitCode=0)
        return 0
    except Exception as exc:
        emit_event("task.failed", task_id, exitCode=1, error=str(exc))
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministic cockpit smoke governed task.")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--mode", default="smoke")
    args = parser.parse_args()
    return run_smoke_task(
        task_id=args.task_id,
        message=args.message,
        workspace=Path(args.workspace),
        mode=args.mode,
    )


if __name__ == "__main__":
    raise SystemExit(main())
