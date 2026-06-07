#!/usr/bin/env python3
"""
SAFETY: Abuse-resistance regression — limits, socket audit, redaction, destructive classification.

Grep: rg 'test_runtime_safety|runtime_safety' scripts/ docs/
"""

from __future__ import annotations

import argparse
import json
import socket
from collections.abc import Callable

from agent_contracts import assert_rpc_envelope
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import (
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    REPO_ROOT,
    SOCKET_PATH,
    connect,
    load_token,
    send_rpc,
)
from runtime_safety import (
    RUNTIME_LIMITS,
    SAFETY_ERROR_CODES,
    audit_socket_path,
    extract_method_permissions,
    load_destructive_methods_fixture,
    parse_limits_from_header,
    redact_diagnostic_snapshot,
    redact_failure_bundle,
    redact_text,
)

FIXTURES_DIR = REPO_ROOT / "scripts/fixtures/safety"


def test_limits_header_alignment() -> None:
    parsed = parse_limits_from_header()
    for key, expected in RUNTIME_LIMITS.items():
        assert key in parsed, f"missing {key} in ControlRuntimeLimits.hpp"
        assert parsed[key] == expected, f"{key}: header={parsed[key]} mirror={expected}"


def test_client_limits_match() -> None:
    assert MAX_REQUEST_BYTES == RUNTIME_LIMITS["kMaxRequestBytes"]
    assert MAX_RESPONSE_BYTES == RUNTIME_LIMITS["kMaxResponseBytes"]


def test_socket_audit_safe_path() -> None:
    audit = audit_socket_path(SOCKET_PATH)
    assert "safe" in audit and "issues" in audit and "checks" in audit


def test_destructive_methods_fixture() -> None:
    methods = load_destructive_methods_fixture()
    assert "patch.apply" in methods
    assert "git.commit" in methods
    catalog = extract_method_permissions()
    for method in methods:
        assert method in catalog["destructive"], f"{method} not destructive in catalog"


def test_execute_methods_documented() -> None:
    fixture = json.loads((FIXTURES_DIR / "destructive_methods.json").read_text(encoding="utf-8"))
    execute = fixture.get("execute_methods", [])
    catalog = extract_method_permissions()
    for method in execute:
        assert method in catalog["execute"] or method in catalog["destructive"], method


def test_redact_token_patterns() -> None:
    sample = "token abcdef0123456789abcdef0123456789 ok"
    redacted = redact_text(sample)
    assert "[REDACTED_TOKEN]" in redacted
    assert "abcdef0123456789abcdef0123456789" not in redacted


def test_redact_diagnostic_snapshot() -> None:
    snapshot = {
        "type": "diagnostic_snapshot",
        "environment": {"DIETCODE_SECRET_KEY": "sekrit", "DIETCODE_SOCKET_PATH": "/tmp/x"},
        "token": {"path": "/tmp/t", "contents": "should-not-appear"},
        "recentRuntimeLogs": [{"request_id": "abcdef0123456789abcdef0123456789"}],
    }
    cleaned = redact_diagnostic_snapshot(snapshot)
    assert cleaned["environment"]["DIETCODE_SECRET_KEY"] == "[REDACTED]"
    assert "contents" not in cleaned["token"]
    assert "[REDACTED_TOKEN]" in cleaned["recentRuntimeLogs"][0]["request_id"]


def test_failure_bundle_truncation() -> None:
    bundle = redact_failure_bundle({"stdout": "x" * 500_000, "stderr": "", "gitDiff": "", "rg": {}})
    assert bundle.get("redacted") is True
    assert len(bundle["stdout"].encode("utf-8")) <= RUNTIME_LIMITS["kMaxFailureBundleBytes"] // 4 + 32


def test_oversized_request_envelope(sock: socket.socket, token: str) -> None:
    del token
    huge = b"x" * (MAX_REQUEST_BYTES + 128) + b"\n"
    sock.sendall(huge)
    line = b""
    while b"\n" not in line:
        chunk = sock.recv(4096)
        if not chunk:
            break
        line += chunk
    response = json.loads(line.decode("utf-8", errors="replace").strip())
    assert_rpc_envelope(response, expect_ok=False)
    assert response["error"]["string_code"] == "request_too_large"


def test_malformed_survival(sock: socket.socket, token: str) -> None:
    for i in range(3):
        sock.sendall(f"not-json-{i}\n".encode("utf-8"))
        line = b""
        while b"\n" not in line:
            line += sock.recv(4096)
        payload = json.loads(line.decode("utf-8").strip())
        assert_rpc_envelope(payload, expect_ok=False)
        assert payload["error"]["string_code"] == "invalid_request"
    ping = send_rpc(sock, token, "rpc.ping", request_id="safety-recover")
    assert_rpc_envelope(ping, expect_ok=True)


def test_source_guardrails_present() -> None:
    server = (REPO_ROOT / "src/platform/macos/control/MacControlServer.mm").read_text(encoding="utf-8")
    assert "kMaxActiveConnections" in server
    assert "kMaxPendingRequestsPerConnection" in server
    assert "kMaxMalformedRequestsPerConnection" in server
    assert "MacControlSocketPathIssue" in server
    for code in ("connection_limit_exceeded", "too_many_pending", "malformed_request_flood"):
        assert code in server
        assert code in SAFETY_ERROR_CODES


def main() -> int:
    parser = argparse.ArgumentParser(description="Runtime abuse-resistance regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("safety.limits_header_alignment", test_limits_header_alignment),
        ("safety.client_limits_match", test_client_limits_match),
        ("safety.socket_audit_shape", test_socket_audit_safe_path),
        ("safety.destructive_methods_fixture", test_destructive_methods_fixture),
        ("safety.execute_methods_documented", test_execute_methods_documented),
        ("safety.redact_token_patterns", test_redact_token_patterns),
        ("safety.redact_diagnostic_snapshot", test_redact_diagnostic_snapshot),
        ("safety.failure_bundle_truncation", test_failure_bundle_truncation),
        ("safety.source_guardrails_present", test_source_guardrails_present),
    ]
    for name, fn in offline:
        recorder.run(name, fn)

    token = load_token()
    live: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("safety.oversized_request", test_oversized_request_envelope),
        ("safety.malformed_survival", test_malformed_survival),
    ]
    for name, fn in live:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            sock = connect(start=False)
            try:
                f(sock, token)
            finally:
                sock.close()

        recorder.run(name, _run)

    return recorder.finish("runtime_safety")


if __name__ == "__main__":
    raise SystemExit(main())
