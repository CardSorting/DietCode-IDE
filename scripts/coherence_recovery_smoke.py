#!/usr/bin/env python3
"""Prove coherence recovery: stale patch blocked, re-read, safe retry, verify passes."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES = _SCRIPT_DIR / "fixtures" / "coherence_recovery"
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from agent_test_support import CheckRecorder, add_output_args, output_compact  # noqa: E402
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc  # noqa: E402


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_event(event_type: str, task_id: str, **payload: Any) -> None:
    record = {
        "type": event_type,
        "taskId": task_id,
        "timestamp": _iso_now(),
        "source": "coherence-recovery-smoke",
        **payload,
    }
    print(json.dumps(record, ensure_ascii=False), flush=True)


def _build_patch(rel_path: str, from_value: int, to_value: int) -> str:
    return (
        f"--- {rel_path}\n"
        f"+++ {rel_path}\n"
        "@@ -1,3 +1,3 @@\n"
        ' """Coherence recovery smoke probe — agent reads VALUE=1, external edit may change it."""\n'
        " \n"
        f"-VALUE = {from_value}\n"
        f"+VALUE = {to_value}\n"
    )


def _resolve_kernel_approval(
    sock,
    token: str,
    response: dict[str, Any],
    task_id: str,
    *,
    resolved_by: str = "coherence-recovery-smoke",
) -> dict[str, Any]:
    result = response.get("result") or {}
    if not result.get("approvalRequired"):
        return response

    approval = result.get("approval") or {}
    approval_id = approval.get("approvalId")
    if not approval_id:
        raise RuntimeError(f"approvalRequired without approvalId: {response}")

    emit_event("approval.required", task_id, approvalId=approval_id)
    resolved = send_rpc(
        sock,
        token,
        "approval.resolve",
        {
            "approvalId": approval_id,
            "decision": "approved",
            "reason": "coherence recovery smoke auto-approve",
            "resolvedBy": resolved_by,
        },
    )
    if not resolved.get("ok"):
        return resolved

    emit_event("approval.resolved", task_id, approvalId=approval_id, decision="approved")
    resolution = (resolved.get("result") or {}).get("resolution") or {}
    if resolution.get("executionErrorCode"):
        return {
            "ok": False,
            "error": {
                "string_code": resolution.get("executionErrorCode"),
                "message": resolution.get("executionError") or "approved mutation failed",
            },
        }
    exec_result = resolution.get("executionResult")
    if exec_result:
        return {"ok": True, "result": exec_result}
    return resolved


def _apply_with_approval(sock, token: str, task_id: str, params: dict[str, Any]) -> dict[str, Any]:
    applied = send_rpc(sock, token, "patch.apply", params)
    if not applied.get("ok"):
        return applied
    return _resolve_kernel_approval(sock, token, applied, task_id)


def _current_value(text: str) -> int:
    match = re.search(r"VALUE = (\d+)", text)
    if not match:
        raise RuntimeError(f"probe text missing VALUE assignment: {text!r}")
    return int(match.group(1))


def run_recovery_smoke() -> None:
    task_id = f"task_coherence_recovery_{uuid.uuid4().hex[:8]}"
    probe_name = f".dietcode/coherence_recovery_{uuid.uuid4().hex[:8]}/probe.py"

    sock = connect()
    token = load_token()
    workspace_root = Path(ensure_workspace_root(sock, token))
    probe_abs = workspace_root / probe_name
    probe_abs.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(FIXTURES / "probe.py", probe_abs)
    shutil.copyfile(FIXTURES / "verify.sh", probe_abs.parent / "verify.sh")
    (probe_abs.parent / "verify.sh").chmod(0o755)

    emit_event("task.started", task_id, path=probe_name, workspace=str(workspace_root))

    read_initial = send_rpc(sock, token, "file.read", {"path": probe_name, "taskId": task_id})
    if not read_initial.get("ok"):
        raise RuntimeError(f"initial file.read failed: {read_initial}")
    initial_text = read_initial["result"]["text"]
    stale_coherence = read_initial["result"].get("coherence") or {}
    if _current_value(initial_text) != 1:
        raise RuntimeError(f"expected VALUE=1 after fixture copy, got: {initial_text!r}")
    emit_event("context.read", task_id, action="file.read", path=probe_name, value=1)

    stale_patch = _build_patch(probe_name, 1, 2)
    validated_stale = send_rpc(
        sock, token, "patch.validate", {"path": probe_name, "patch": stale_patch}
    )
    if not validated_stale.get("ok"):
        raise RuntimeError(f"stale patch.validate failed: {validated_stale}")

    probe_abs.write_text(initial_text.replace("VALUE = 1", "VALUE = 3"), encoding="utf-8")
    emit_event("workspace.external_change", task_id, path=probe_name, value=3)

    stale_apply_params: dict[str, Any] = {
        "path": probe_name,
        "patch": stale_patch,
        "confirm": True,
        "expectBeforeHash": validated_stale["result"]["validation"]["beforeContentHash"],
        "taskId": task_id,
    }
    if stale_coherence.get("tokenId"):
        stale_apply_params["coherenceTokenId"] = stale_coherence["tokenId"]
    if stale_coherence.get("workspaceRevision") is not None:
        stale_apply_params["expectedWorkspaceRevision"] = stale_coherence["workspaceRevision"]

    blocked = send_rpc(sock, token, "patch.apply", stale_apply_params)
    if blocked.get("ok"):
        raise RuntimeError(f"expected coherence_mismatch, got success: {blocked}")
    err = blocked.get("error") or {}
    if err.get("string_code") != "coherence_mismatch":
        raise RuntimeError(f"expected coherence_mismatch, got: {blocked}")
    emit_event(
        "context.stale",
        task_id,
        path=probe_name,
        reason=err.get("reason"),
        changedPaths=err.get("changedPaths") or [probe_name],
    )

    reread = send_rpc(sock, token, "file.read", {"path": probe_name, "taskId": task_id})
    if not reread.get("ok"):
        raise RuntimeError(f"recovery file.read failed: {reread}")
    fresh_text = reread["result"]["text"]
    fresh_coherence = reread["result"].get("coherence") or {}
    current = _current_value(fresh_text)
    if current != 3:
        raise RuntimeError(f"expected VALUE=3 after external edit, got {current}")
    emit_event("context.refreshed", task_id, path=probe_name, value=current)

    recovery_patch = _build_patch(probe_name, current, 2)
    validated_recovery = send_rpc(
        sock, token, "patch.validate", {"path": probe_name, "patch": recovery_patch}
    )
    if not validated_recovery.get("ok"):
        raise RuntimeError(f"recovery patch.validate failed: {validated_recovery}")

    emit_event("coherence.retry", task_id, path=probe_name, attempt=1)
    recovery_params: dict[str, Any] = {
        "path": probe_name,
        "patch": recovery_patch,
        "confirm": True,
        "expectBeforeHash": validated_recovery["result"]["validation"]["beforeContentHash"],
        "taskId": task_id,
    }
    if fresh_coherence.get("tokenId"):
        recovery_params["coherenceTokenId"] = fresh_coherence["tokenId"]
    if fresh_coherence.get("workspaceRevision") is not None:
        recovery_params["expectedWorkspaceRevision"] = fresh_coherence["workspaceRevision"]

    applied = _apply_with_approval(sock, token, task_id, recovery_params)
    if not applied.get("ok"):
        raise RuntimeError(f"recovery patch.apply failed: {applied}")
    result = applied.get("result") or {}
    if not (result.get("patched") or result.get("applied") or result.get("complete")):
        raise RuntimeError(f"recovery patch did not apply: {result}")

    if _current_value(probe_abs.read_text(encoding="utf-8")) != 2:
        raise RuntimeError("probe.py was not updated to VALUE = 2")
    emit_event("mutation.applied", task_id, path=probe_name, changedPaths=[probe_name])

    verify_cwd = str(probe_abs.parent.relative_to(workspace_root))
    verify = send_rpc(
        sock,
        token,
        "verify.run",
        {"command": "./verify.sh", "cwd": verify_cwd, "taskId": task_id},
    )
    if not verify.get("ok"):
        raise RuntimeError(f"verify.run failed: {verify}")
    if not verify["result"].get("passed"):
        raise RuntimeError(f"verify.run did not pass: {verify}")
    emit_event("verify.completed", task_id, command="./verify.sh", passed=True)
    emit_event("task.completed", task_id, exitCode=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Coherence recovery vertical smoke.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)
    recorder.run("coherence.recovery_smoke", run_recovery_smoke)
    return recorder.finish("coherence_recovery_smoke")


if __name__ == "__main__":
    raise SystemExit(main())
