#!/usr/bin/env python3
"""Deterministic governed-task runner for cockpit vertical-slice smoke (no Hermes)."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from dietcode_agent_client import connect, load_token, send_rpc  # noqa: E402
from dietcode_coherence import apply_patch_with_coherence, read_with_coherence  # noqa: E402

PROBE_NAME = "probe.py"


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

        read = read_with_coherence(sock, token, probe_rel, task_id)
        coherence = read.get("coherence") or {}
        emit_event("context.read", task_id, action="file.read", path=probe_rel)

        patch = _build_patch(probe_rel)
        validated = send_rpc(sock, token, "patch.validate", {"path": probe_rel, "patch": patch})
        if not validated.get("ok"):
            raise RuntimeError(f"patch.validate failed: {validated}")
        validation = validated["result"]["validation"]
        if not validation.get("ok"):
            raise RuntimeError(f"patch validation rejected: {validation}")

        applied = apply_patch_with_coherence(
            sock,
            token,
            task_id=task_id,
            path=probe_rel,
            patch=patch,
            coherence=coherence,
            expect_before_hash=validation["beforeContentHash"],
            emit=emit_event,
            resolved_by="cockpit-smoke-task",
        )
        if not applied.get("ok"):
            raise RuntimeError(f"patch.apply failed: {applied}")

        result = applied.get("result") or {}
        if not (result.get("applied") or result.get("complete") or result.get("patched")):
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
