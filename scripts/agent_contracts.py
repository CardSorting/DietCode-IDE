#!/usr/bin/env python3
"""CONTRACT: Frozen runtime contract constants — grep with `rg 'CONTRACT:' scripts/agent_contracts.py`."""

from __future__ import annotations

from typing import Any

# CONTRACT: NDJSON harness summary line schema (type=summary).
SUMMARY_SCHEMA_KEYS = frozenset({"type", "suite", "ok", "checks", "passed", "failed", "failedNames"})

# CONTRACT: NDJSON per-check line schema (type=check).
CHECK_LINE_SCHEMA_KEYS = frozenset({"type", "name", "ok"})

# CONTRACT: RPC success envelope required keys.
RPC_SUCCESS_ENVELOPE_KEYS = frozenset({"id", "ok", "result"})

# CONTRACT: RPC error envelope required keys under error object.
RPC_ERROR_ENVELOPE_KEYS = frozenset({"code", "string_code", "message"})

# CONTRACT: Optional stable diagnostic keys on server error envelopes (grep: rg 'recovery_hint' src/ scripts/).
RPC_ERROR_DIAGNOSTIC_OPTIONAL_KEYS = frozenset({
    "request_id",
    "category",
    "retryable",
    "phase",
    "queue",
    "recovery_hint",
})

# CONTRACT: NDJSON runtime diagnostic line schema (server: ~/.dietcode/agent-runtime.ndjson).
RUNTIME_DIAGNOSTIC_LINE_KEYS = frozenset({
    "type",
    "timestamp",
    "request_id",
    "method",
    "phase",
    "ok",
})

RUNTIME_DIAGNOSTIC_OPTIONAL_KEYS = frozenset({"string_code", "queue", "duration_ms"})

# CONTRACT: Diagnostic snapshot top-level keys (--diagnose).
DIAGNOSTIC_SNAPSHOT_KEYS = frozenset({
    "type",
    "ok",
    "socketActive",
    "rpcReady",
    "socket",
    "token",
    "app",
    "makefileTargets",
    "docs",
    "recentRuntimeLogs",
    "runtimeLimits",
    "socketAudit",
    "contractVersions",
    "contractInventoryVersion",
})

# CONTRACT: Stable golden failure string_code expectations (see scripts/fixtures/rpc/expected_error_codes.json).
GOLDEN_ERROR_CODES = {
    "method_not_found": -32601,
    "invalid_params": -32602,
    "invalid_request": -32600,
    "response_too_large": 413,
    "response_serialization_failed": -32603,
}

# CONTRACT: Makefile targets that must exist for agent runtime verification.
REQUIRED_MAKE_TARGETS = frozenset({
    "test-agent-offline",
    "test-rpc-transaction",
    "test-task-health",
    "test-operator-diagnostics",
    "test-runtime-safety",
    "agent-integration",
    "verify-agent-runtime",
    "release-check-agent-runtime",
    "agent-self-test",
    "control-smoke",
})

# CONTRACT: Live integration suite registry (name → script path).
INTEGRATION_SUITES = {
    "control_smoke": "scripts/control_smoke_test.py",
    "task_server_health": "scripts/test_task_server_health.py",
    "rpc_transaction": "scripts/test_rpc_transaction_health.py",
    "ergonomics": "scripts/test_ergonomics.py",
    "operator_diagnostics": "scripts/test_operator_diagnostics.py",
    "runtime_safety": "scripts/test_runtime_safety.py",
}

# CONTRACT: Offline lockdown suites.
OFFLINE_SUITES = {
    "agent_self_test": "scripts/dietcode_agent_client.py",
    "contract_lockdown": "scripts/test_contract_lockdown.py",
    "release_readiness": "scripts/test_release_readiness.py",
}


def validate_summary_line(payload: dict[str, Any]) -> list[str]:
    """Return validation errors for a summary NDJSON object."""
    errors: list[str] = []
    if payload.get("type") != "summary":
        errors.append("type must be 'summary'")
    missing = SUMMARY_SCHEMA_KEYS - set(payload.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
    if not isinstance(payload.get("failedNames"), list):
        errors.append("failedNames must be a list")
    if payload.get("checks") != payload.get("passed", 0) + payload.get("failed", 0):
        errors.append("checks must equal passed + failed")
    return errors


def validate_check_line(payload: dict[str, Any]) -> list[str]:
    """Return validation errors for a check NDJSON object."""
    errors: list[str] = []
    if payload.get("type") != "check":
        errors.append("type must be 'check'")
    missing = CHECK_LINE_SCHEMA_KEYS - set(payload.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
    name = payload.get("name")
    if not isinstance(name, str) or not name:
        errors.append("name must be a non-empty string")
    return errors


def assert_rpc_error_diagnostics(error: dict[str, Any], *, expect_request_id: str | None = None) -> None:
    """INVARIANT: Server failures expose stable grep-friendly diagnostic fields."""
    assert isinstance(error.get("string_code"), str) and error["string_code"], error
    if expect_request_id is not None:
        assert error.get("request_id") == expect_request_id, error
    assert isinstance(error.get("category"), str) and error["category"], error
    assert isinstance(error.get("retryable"), bool), error
    assert isinstance(error.get("recovery_hint"), str) and error["recovery_hint"], error


def validate_runtime_diagnostic_line(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if payload.get("type") != "runtime_diagnostic":
        errors.append("type must be 'runtime_diagnostic'")
    missing = RUNTIME_DIAGNOSTIC_LINE_KEYS - set(payload.keys())
    if missing:
        errors.append(f"missing keys: {sorted(missing)}")
    if not isinstance(payload.get("ok"), bool):
        errors.append("ok must be boolean")
    return errors


def assert_rpc_envelope(response: dict[str, Any], *, expect_ok: bool) -> None:
    """INVARIANT: Every RPC response is a single terminal envelope."""
    if expect_ok:
        assert response.get("ok") is True, response
        for key in RPC_SUCCESS_ENVELOPE_KEYS:
            assert key in response, f"missing {key} in success envelope"
        assert isinstance(response.get("result"), dict), "result must be object"
    else:
        assert response.get("ok") is False, response
        error = response.get("error", {})
        assert isinstance(error, dict), "error must be object"
        for key in RPC_ERROR_ENVELOPE_KEYS:
            assert key in error, f"missing {key} in error envelope"
        assert isinstance(error.get("string_code"), str) and error["string_code"], "string_code required"
