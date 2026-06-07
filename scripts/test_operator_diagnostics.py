#!/usr/bin/env python3
"""
CONTRACT: Operator diagnostics regression — request correlation, error envelope diagnostics, runtime NDJSON.

Grep: rg 'test_operator_diagnostics|operator_diagnostics' scripts/ docs/
"""

from __future__ import annotations

import argparse
import json
import os
import socket
from collections.abc import Callable

from agent_contracts import (
    DIAGNOSTIC_SNAPSHOT_KEYS,
    assert_rpc_envelope,
    assert_rpc_error_diagnostics,
    validate_runtime_diagnostic_line,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import (
    RUNTIME_DIAGNOSTIC_LOG,
    SOCKET_PATH,
    build_diagnostic_snapshot,
    connect,
    load_token,
    read_runtime_diagnostic_lines,
    send_rpc,
)

CORRELATION_REQUEST_ID = "operator-diag-correlation-1"


def call(sock: socket.socket, token: str, method: str, params: dict | None = None, request_id: str | None = None) -> dict:
    return send_rpc(sock, token, method, params, request_id=request_id)


def test_error_envelope_diagnostics(sock: socket.socket, token: str) -> None:
    response = call(sock, token, "__operator_diag_missing_method__", request_id=CORRELATION_REQUEST_ID)
    assert_rpc_envelope(response, expect_ok=False)
    assert response["id"] == CORRELATION_REQUEST_ID
    assert_rpc_error_diagnostics(response["error"], expect_request_id=CORRELATION_REQUEST_ID)
    assert response["error"].get("phase") in {"response_error", "serialization_fallback"}
    assert isinstance(response["error"].get("recovery_hint"), str)


def test_success_still_one_envelope(sock: socket.socket, token: str) -> None:
    response = call(sock, token, "rpc.ping", request_id="operator-diag-ping")
    assert_rpc_envelope(response, expect_ok=True)
    assert response.get("_client_duration_ms", 0) >= 0


def test_malformed_then_recover(sock: socket.socket, token: str) -> None:
    sock.sendall(b"not-json\n")
    line = b""
    while b"\n" not in line:
        chunk = sock.recv(4096)
        if not chunk:
            break
        line += chunk
    response = json.loads(line.decode("utf-8").strip())
    assert_rpc_envelope(response, expect_ok=False)
    frame = send_rpc(sock, token, "rpc.ping", request_id="operator-diag-recover")
    assert_rpc_envelope(frame, expect_ok=True)


def test_runtime_log_lines_present() -> None:
    lines = read_runtime_diagnostic_lines(limit=5)
    if not lines:
        return
    for line in lines[-3:]:
        errors = validate_runtime_diagnostic_line(line)
        assert not errors, errors


def test_diagnostic_snapshot_shape() -> None:
    snapshot = build_diagnostic_snapshot()
    missing = DIAGNOSTIC_SNAPSHOT_KEYS - set(snapshot.keys())
    assert not missing, f"missing snapshot keys: {sorted(missing)}"
    assert snapshot["type"] == "diagnostic_snapshot"
    assert isinstance(snapshot.get("verificationCommands"), list)


def main() -> int:
    parser = argparse.ArgumentParser(description="Operator diagnostics regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline_checks: list[tuple[str, Callable[[], None]]] = [
        ("diag.snapshot_shape", test_diagnostic_snapshot_shape),
        ("diag.runtime_log_schema", test_runtime_log_lines_present),
    ]
    for name, fn in offline_checks:
        recorder.run(name, fn)

    token = load_token()
    sock = connect(socket_path=SOCKET_PATH, start=False)
    try:
        live_checks: list[tuple[str, Callable[[socket.socket, str], None]]] = [
            ("diag.error_envelope_fields", test_error_envelope_diagnostics),
            ("diag.success_envelope_latency", test_success_still_one_envelope),
            ("diag.malformed_recover", test_malformed_then_recover),
        ]
        for name, fn in live_checks:
            def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
                f(sock, token)

            recorder.run(name, _run)
    finally:
        sock.close()

    if os.path.isfile(RUNTIME_DIAGNOSTIC_LOG):
        text = open(RUNTIME_DIAGNOSTIC_LOG, "r", encoding="utf-8").read()
        recorder.record(
            "diag.runtime_log_has_correlation",
            CORRELATION_REQUEST_ID in text,
            detail={"path": RUNTIME_DIAGNOSTIC_LOG},
        )

    return recorder.finish("operator_diagnostics")


if __name__ == "__main__":
    raise SystemExit(main())
