#!/usr/bin/env python3
"""
RPC transactional boundary regression: one envelope per request, socket survives failures.

Grep: rg 'rpc_transaction|envelope_shape' scripts/
"""

from __future__ import annotations

import argparse
import json
import socket
from collections.abc import Callable

from agent_contracts import GOLDEN_ERROR_CODES, assert_rpc_envelope, assert_rpc_error_diagnostics
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import (
    REPO_ROOT,
    SOCKET_PATH,
    connect,
    load_token,
    send_rpc,
)

FIXTURES_DIR = REPO_ROOT / "scripts" / "fixtures" / "rpc"


def call(sock: socket.socket, token: str, method: str, params: dict | None = None) -> dict:
    return send_rpc(sock, token, method, params)


def _expected_codes() -> dict[str, str]:
    import json

    return json.loads((FIXTURES_DIR / "expected_error_codes.json").read_text(encoding="utf-8"))


def test_golden_ping_success(sock: socket.socket, token: str) -> None:
    import json

    fixture = json.loads((FIXTURES_DIR / "request_ping.json").read_text(encoding="utf-8"))
    response = call(sock, token, fixture["method"], fixture.get("params", {}))
    assert_rpc_envelope(response, expect_ok=True)
    assert response.get("result", {}).get("pong") is True


def test_invalid_params_envelope(sock: socket.socket, token: str) -> None:
    expected = _expected_codes()["event_subscribe_empty_types"]
    response = call(sock, token, "event.subscribe", {})
    assert_rpc_envelope(response, expect_ok=False)
    assert response["error"]["string_code"] == expected
    assert response["error"]["code"] == GOLDEN_ERROR_CODES[expected]
    ping = call(sock, token, "rpc.ping", {})
    assert_rpc_envelope(ping, expect_ok=True)


def test_method_not_found_envelope(sock: socket.socket, token: str) -> None:
    expected = _expected_codes()["unknown_method"]
    response = call(sock, token, "__rpc_transaction_no_such_method__")
    assert_rpc_envelope(response, expect_ok=False)
    assert response["error"]["string_code"] == expected
    assert response["error"]["code"] == GOLDEN_ERROR_CODES[expected]
    assert_rpc_error_diagnostics(response["error"])
    ping = call(sock, token, "rpc.ping", {})
    assert ping.get("ok") is True


def test_unknown_task_id_envelope(sock: socket.socket, token: str) -> None:
    expected = _expected_codes()["task_unknown_task_id"]
    response = call(sock, token, "task.runLoop", {"taskId": "missing-task-fixture", "steps": []})
    assert_rpc_envelope(response, expect_ok=False)
    assert response["error"]["string_code"] == expected
    described = call(sock, token, "rpc.describe", {"method": "task.runLoop"})
    assert_rpc_envelope(described, expect_ok=True)


def test_task_failure_containment(sock: socket.socket, token: str) -> None:
    started = call(sock, token, "task.start", {"goal": "rpc transaction containment"})
    task_id = started["result"]["taskId"]
    failed = call(sock, token, "task.runLoop", {"taskId": task_id, "steps": [{"type": "unknown_step"}]})
    assert failed.get("ok") is True, "runLoop returns outer ok with step rejection in results"
    results = failed.get("result", {}).get("results", [])
    assert results and results[0].get("ok") is False
    described = call(sock, token, "rpc.describe", {"method": "task.runLoop"})
    assert_rpc_envelope(described, expect_ok=True)


def test_malformed_line_survives() -> None:
    expected = _expected_codes()["malformed_json_line"]
    malformed = (FIXTURES_DIR / "malformed_line.txt").read_bytes()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET_PATH)
        token = load_token()
        sock.sendall(malformed if malformed.endswith(b"\n") else malformed + b"\n")
        line = b""
        while b"\n" not in line:
            chunk = sock.recv(4096)
            if not chunk:
                break
            line += chunk
        response = json.loads(line.decode("utf-8").strip())
        assert_rpc_envelope(response, expect_ok=False)
        assert response["error"]["string_code"] == expected
        ping = send_rpc(sock, token, "rpc.ping")
        assert_rpc_envelope(ping, expect_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="RPC transactional boundary NDJSON checks.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    socket_tests = [
        ("rpc.golden_ping_success", test_golden_ping_success),
        ("rpc.invalid_params_envelope", test_invalid_params_envelope),
        ("rpc.method_not_found_envelope", test_method_not_found_envelope),
        ("rpc.unknown_task_id_envelope", test_unknown_task_id_envelope),
        ("rpc.task_failure_containment", test_task_failure_containment),
    ]
    for name, fn in socket_tests:
        def _run(fn: Callable = fn) -> None:
            with connect() as sock:
                fn(sock, load_token())

        recorder.run(name, _run)

    recorder.run("rpc.malformed_line_survives", test_malformed_line_survives)

    return recorder.finish("rpc_transaction")


if __name__ == "__main__":
    raise SystemExit(main())
