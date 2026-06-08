#!/usr/bin/env python3
"""Governed Hermes task runner for DietCode Cockpit — emits NDJSON task events on stdout."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from dietcode_agent_bundle import (  # noqa: E402
    AgentChatError,
    assert_chat_ready,
    build_system_prompt,
    find_hermes_binary,
    repo_root_from_script,
    resolve_context,
    run_bridge_verify,
    enforce_workspace_authority,
    HERMES_HOME,
)


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_event(event_type: str, task_id: str, **payload: Any) -> None:
    record = {
        "type": event_type,
        "taskId": task_id,
        "timestamp": _iso_now(),
        "source": "governed-task",
        **payload,
    }
    print(json.dumps(record, ensure_ascii=False), flush=True)


def tail_task_event_log(path: Path, task_id: str, stop: threading.Event) -> None:
    offset = 0
    while not stop.is_set():
        if not path.is_file():
            time.sleep(0.25)
            continue
        try:
            with path.open("r", encoding="utf-8") as handle:
                handle.seek(offset)
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if record.get("taskId") and record.get("taskId") != task_id:
                        continue
                    print(json.dumps(record, ensure_ascii=False), flush=True)
                offset = handle.tell()
        except OSError:
            pass
        time.sleep(0.35)


def run_governed_task(
    *,
    task_id: str,
    message: str,
    workspace: Path,
    mode: str,
    max_turns: int,
    timeout: int,
) -> int:
    repo_root = repo_root_from_script(Path(__file__))
    ctx = resolve_context(repo_root)
    workspace = workspace.resolve()

    emit_event(
        "task.started",
        task_id,
        message=message,
        workspace=str(workspace),
        mode=mode,
    )

    try:
        assert_chat_ready(ctx, repo_root, workspace)
        enforce_workspace_authority(ctx, workspace)
        bridge = run_bridge_verify(ctx, workspace)
        if not bridge.get("ok"):
            raise AgentChatError(
                f"Bridge verify failed: {bridge.get('error', bridge)}",
                code="bridge_verify_failed",
                exit_code=9,
            )

        hermes_bin = find_hermes_binary()
        if not hermes_bin:
            raise AgentChatError("Hermes missing", code="hermes_missing", exit_code=4)

        event_log = Path.home() / ".dietcode" / "agent-chat" / "tasks" / f"{task_id}.events.ndjson"
        event_log.parent.mkdir(parents=True, exist_ok=True)
        if event_log.is_file():
            event_log.unlink()

        env = os.environ.copy()
        env["HERMES_HOME"] = str(HERMES_HOME)
        env["DIETCODE_WORKSPACE"] = str(workspace)
        env["HERMES_KANBAN_WORKSPACE"] = str(workspace)
        env["HERMES_ACCEPT_HOOKS"] = "1"
        env["DIETCODE_TASK_ID"] = task_id
        env["DIETCODE_TASK_EVENT_LOG"] = str(event_log)
        if mode == "supervised":
            env["DIETCODE_SUPERVISED"] = "1"
            env["DIETCODE_TASK_MODE"] = "supervised"
        else:
            env["DIETCODE_TASK_MODE"] = "trusted"
        if ctx.app_bundle:
            env.setdefault("DIETCODE_APP_BUNDLE", str(ctx.app_bundle))
        kernel_binary = repo_root / "build" / "dietcode-kernel"
        if not env.get("DIETCODE_APP_PATH"):
            if kernel_binary.is_file():
                env["DIETCODE_APP_PATH"] = str(kernel_binary)
            elif ctx.app_path:
                env["DIETCODE_APP_PATH"] = str(ctx.app_path)
        if ctx.bridge_cli:
            env["DIETCODE_BRIDGE_CLI"] = str(ctx.bridge_cli)
        env["DIETCODE_IDE_ROOT"] = str(ctx.ide_root)

        full_prompt = build_system_prompt(workspace, message)
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
        if mode == "trusted":
            cmd.append("--yolo")

        stop_tail = threading.Event()
        tail_thread = threading.Thread(
            target=tail_task_event_log,
            args=(event_log, task_id, stop_tail),
            daemon=True,
        )
        tail_thread.start()

        emit_event("agent.message", task_id, role="user", text=message)

        proc = subprocess.Popen(
            cmd,
            cwd=str(workspace),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        stdout_chunks: list[str] = []
        assert proc.stdout is not None
        for line in proc.stdout:
            text = line.rstrip("\n")
            if not text.strip():
                continue
            stdout_chunks.append(text)
            emit_event("agent.message", task_id, role="assistant", text=text)

        try:
            proc.wait(timeout=max(30, timeout))
        except subprocess.TimeoutExpired:
            proc.kill()
            emit_event("task.failed", task_id, error="Hermes task timed out", code="timeout")
            return 1

        stderr_text = (proc.stderr.read() if proc.stderr else "").strip()
        if stderr_text:
            emit_event("agent.message", task_id, role="system", text=stderr_text[:2000])

        stop_tail.set()
        tail_thread.join(timeout=2)

        transcript = "\n".join(stdout_chunks).strip()
        if proc.returncode == 0:
            emit_event("task.completed", task_id, exitCode=0, transcript=transcript[-4000:])
            return 0

        emit_event(
            "task.failed",
            task_id,
            exitCode=proc.returncode,
            error=transcript or stderr_text or f"Hermes exited {proc.returncode}",
        )
        return proc.returncode or 1

    except AgentChatError as exc:
        emit_event("task.failed", task_id, error=str(exc), code=exc.code)
        return exc.exit_code
    except Exception as exc:
        emit_event("task.failed", task_id, error=str(exc), code="internal_error")
        return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run a governed Hermes task for DietCode Cockpit.")
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--mode", default="supervised", choices=["supervised", "trusted"])
    parser.add_argument("--max-turns", type=int, default=25)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args(argv)

    return run_governed_task(
        task_id=args.task_id,
        message=args.message,
        workspace=Path(args.workspace).expanduser(),
        mode=args.mode,
        max_turns=args.max_turns,
        timeout=args.timeout,
    )


if __name__ == "__main__":
    raise SystemExit(main())
