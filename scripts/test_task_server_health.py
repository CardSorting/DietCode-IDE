#!/usr/bin/env python3
"""
Live-server regression: task methods must not poison the control socket.

Grep anchor: rg 'task.runLoop|executeNestedMethod' src/platform/macos/control
"""

from __future__ import annotations

import argparse
import socket
from collections.abc import Callable

from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import connect, load_token, send_rpc


def call(sock: socket.socket, token: str, method: str, params: dict | None = None) -> dict:
    return send_rpc(sock, token, method, params)


def test_task_runloop_same_connection(sock: socket.socket, token: str) -> None:
    started = call(sock, token, "task.start", {"goal": "task server health regression"})
    assert started.get("ok"), "task.start failed"
    task_id = started.get("result", {}).get("taskId")
    assert task_id, "task.start missing taskId"

    completed = call(sock, token, "task.runLoop", {"taskId": task_id, "steps": []})
    assert completed.get("ok"), f"task.runLoop failed: {completed.get('error')}"
    assert completed.get("result", {}).get("task", {}).get("status") == "complete"

    described = call(sock, token, "rpc.describe", {"method": "task.runLoop"})
    assert described.get("ok"), "rpc.describe failed after task.runLoop on same connection"
    methods = described.get("result", {}).get("methods", [])
    assert methods and methods[0].get("name") == "task.runLoop"


def test_task_result_same_connection(sock: socket.socket, token: str) -> None:
    started = call(sock, token, "task.start", {"goal": "task result health regression"})
    task_id = started.get("result", {}).get("taskId")
    assert task_id, "task.start missing taskId"

    result = call(sock, token, "task.result", {"taskId": task_id})
    assert result.get("ok"), f"task.result failed: {result.get('error')}"
    assert "finalDiff" in result.get("result", {}), "task.result missing finalDiff"
    assert "verify" in result.get("result", {}), "task.result missing verify"

    ping = call(sock, token, "rpc.ping", {})
    assert ping.get("ok") and ping.get("result", {}).get("pong") is True


def test_invalid_task_runloop_params(sock: socket.socket, token: str) -> None:
    invalid = call(sock, token, "task.runLoop", {"taskId": "missing-task-id", "steps": []})
    assert not invalid.get("ok"), "task.runLoop with unknown taskId should fail"
    assert invalid.get("error", {}).get("string_code") == "invalid_params"

    ping = call(sock, token, "rpc.ping", {})
    assert ping.get("ok"), "rpc.ping failed after invalid task.runLoop"


def main() -> int:
    parser = argparse.ArgumentParser(description="Task/socket health NDJSON regression checks.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    tests = [
        ("task.runloop_same_connection", test_task_runloop_same_connection),
        ("task.result_same_connection", test_task_result_same_connection),
        ("task.invalid_params_survives", test_invalid_task_runloop_params),
    ]

    for name, fn in tests:
        def _run(fn: Callable = fn) -> None:
            with connect() as sock:
                token = load_token()
                fn(sock, token)

        recorder.run(name, _run)

    return recorder.finish("task_server_health")


if __name__ == "__main__":
    raise SystemExit(main())
