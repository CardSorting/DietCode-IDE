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

# CONTRACT: workspace.grep top-level result keys (literal substring mode).
GREP_RESPONSE_KEYS = frozenset({
    "matches",
    "query",
    "mode",
    "caseSensitive",
    "maxResults",
    "resultOffset",
    "nextResultOffset",
    "hasMore",
    "truncated",
    "scanLimitReached",
    "scannedFiles",
    "filesRead",
    "filesSkippedUnreadable",
    "filesSkippedBinary",
    "filesReadFromDisk",
    "filesReadFromEditor",
    "filesSkippedOversize",
    "filesSkippedExcluded",
    "filesSkippedSymlink",
    "symlinkPolicy",
    "sortOrder",
    "scanDurationMs",
})

# CONTRACT: Shared deterministic search accounting keys (grep/text/todo parity).
SEARCH_ACCOUNTING_KEYS = frozenset({
    "scannedFiles",
    "filesRead",
    "filesSkippedUnreadable",
    "filesSkippedBinary",
    "filesReadFromDisk",
    "filesReadFromEditor",
    "filesSkippedOversize",
    "filesSkippedExcluded",
    "filesSkippedSymlink",
    "symlinkPolicy",
    "sortOrder",
    "scanDurationMs",
    "truncated",
    "scanLimitReached",
})

# CONTRACT: search.text top-level result keys.
SEARCH_TEXT_RESPONSE_KEYS = frozenset({
    "results",
    "query",
    "mode",
    "caseSensitive",
    "maxResults",
    "resultOffset",
    "nextResultOffset",
    "hasMore",
}) | SEARCH_ACCOUNTING_KEYS

# CONTRACT: search.todo top-level result keys.
SEARCH_TODO_RESPONSE_KEYS = frozenset({
    "results",
    "mode",
    "markers",
    "maxResults",
}) | SEARCH_ACCOUNTING_KEYS

# CONTRACT: workspace.revision response keys.
WORKSPACE_REVISION_KEYS = frozenset({
    "revisionId",
    "workspacePath",
    "changedFiles",
    "lastMutationReceipt",
    "lastMutationSource",
    "externalChangeDetected",
    "externallyChangedPaths",
    "mode",
})

# CONTRACT: workspace.snapshot response keys.
WORKSPACE_SNAPSHOT_KEYS = frozenset({
    "revisionId",
    "snapshotId",
    "sinceRevision",
    "revisionDelta",
    "fileHashes",
    "changedFiles",
    "externalChangeDetected",
    "mode",
})

# CONTRACT: patch.applyBatch batchMutationReceipt keys.
BATCH_MUTATION_RECEIPT_KEYS = frozenset({
    "atomic",
    "appliedCount",
    "rolledBack",
    "fileReceipts",
    "rollbackProof",
})

# CONTRACT: operation.status response keys (completed).
OPERATION_STATUS_COMPLETED_KEYS = frozenset({
    "status",
    "idempotencyKey",
    "revisionBefore",
    "revisionAfter",
    "changedFiles",
    "completedAt",
})

# CONTRACT: patch.validate validation object keys.
PATCH_VALIDATION_KEYS = frozenset({
    "ok",
    "targetFileExists",
    "insideWorkspace",
    "patchAppliesCleanly",
    "changedLineCount",
    "requiresConfirmation",
    "syntaxDanger",
    "rejectedReason",
    "beforeContentHash",
    "patchFingerprint",
    "readSource",
})

# CONTRACT: patch.apply mutation receipt keys.
MUTATION_RECEIPT_KEYS = frozenset({
    "path",
    "beforeContentHash",
    "postContentHash",
    "patchFingerprint",
    "readSourceBefore",
    "applyChannel",
    "atomic",
})

# CONTRACT: file.stat response keys.
FILE_STAT_KEYS = frozenset({
    "path",
    "sizeBytes",
    "lineCount",
    "modified",
    "open",
    "dirty",
    "contentHash",
    "readSource",
})

# CONTRACT: workspace.grep match row keys.
GREP_MATCH_KEYS = frozenset({
    "resultIndex",
    "path",
    "line",
    "column",
    "matchSpans",
    "matchCountOnLine",
    "preview",
    "lineSha256",
    "contextBefore",
    "contextAfter",
})

# CONTRACT: diff.hunks top-level result keys.
DIFF_HUNKS_RESPONSE_KEYS = frozenset({
    "files",
    "totalFiles",
    "totalHunks",
    "returnedHunks",
    "totalAddedLines",
    "totalRemovedLines",
    "maxHunks",
    "hunkOffset",
    "nextHunkOffset",
    "hasMoreHunks",
    "includeLines",
    "maxLinesPerHunk",
    "truncated",
    "mode",
    "source",
    "sha256",
})

# CONTRACT: Makefile targets that must exist for agent runtime verification.
REQUIRED_MAKE_TARGETS = frozenset({
    "test-agent-offline",
    "test-rpc-transaction",
    "test-task-health",
    "test-operator-diagnostics",
    "test-runtime-safety",
    "test-grep-diff-tooling",
    "test-runtime-determinism",
    "test-transaction-kernel",
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
    "grep_diff_tooling": "scripts/test_grep_diff_tooling.py",
    "runtime_determinism": "scripts/test_runtime_determinism.py",
    "transaction_kernel": "scripts/test_transaction_kernel.py",
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


def validate_grep_match(match: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = GREP_MATCH_KEYS - set(match.keys())
    if missing:
        errors.append(f"match missing keys: {sorted(missing)}")
    if match.get("mode") is not None:
        errors.append("match must not include mode key")
    spans = match.get("matchSpans")
    if not isinstance(spans, list) or not spans:
        errors.append("matchSpans must be a non-empty list")
    else:
        span = spans[0]
        if not isinstance(span, dict):
            errors.append("matchSpans[0] must be object")
        else:
            for key in ("columnStart", "columnEnd", "offset", "length"):
                if key not in span:
                    errors.append(f"matchSpans[0] missing {key}")
    if not isinstance(match.get("resultIndex"), int):
        errors.append("resultIndex must be int")
    if not isinstance(match.get("line"), int) or match.get("line", 0) < 1:
        errors.append("line must be positive int")
    return errors


def validate_grep_response(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = GREP_RESPONSE_KEYS - set(result.keys())
    if missing:
        errors.append(f"grep missing keys: {sorted(missing)}")
    if result.get("mode") != "literal_substring":
        errors.append("mode must be literal_substring")
    matches = result.get("matches")
    if not isinstance(matches, list):
        errors.append("matches must be list")
    elif matches:
        errors.extend(validate_grep_match(matches[0]))
    has_more = result.get("hasMore")
    next_offset = result.get("nextResultOffset")
    if has_more and next_offset is None:
        errors.append("nextResultOffset required when hasMore is true")
    if not has_more and next_offset is not None:
        errors.append("nextResultOffset must be null when hasMore is false")
    if result.get("sortOrder") and result.get("sortOrder") != "path_line_column":
        errors.append("sortOrder must be path_line_column when present")
    if isinstance(matches, list) and matches and result.get("sortOrder") == "path_line_column":
        errors.extend(validate_grep_sort_order(matches))
    return errors


def validate_mutation_receipt(receipt: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = MUTATION_RECEIPT_KEYS - set(receipt.keys())
    if missing:
        errors.append(f"mutation receipt missing keys: {sorted(missing)}")
    if receipt.get("atomic") is not True:
        errors.append("mutation receipt atomic must be true")
    return errors


def validate_file_stat(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = FILE_STAT_KEYS - set(result.keys())
    if missing:
        errors.append(f"file.stat missing keys: {sorted(missing)}")
    if not isinstance(result.get("contentHash"), str) or len(result.get("contentHash", "")) != 16:
        errors.append("contentHash must be 16-char stable hash")
    if result.get("readSource") not in ("editor", "disk"):
        errors.append("readSource must be editor or disk")
    return errors


def validate_patch_validation(validation: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = PATCH_VALIDATION_KEYS - set(validation.keys())
    if missing:
        errors.append(f"patch validation missing keys: {sorted(missing)}")
    if not isinstance(validation.get("ok"), bool):
        errors.append("validation.ok must be boolean")
    if not isinstance(validation.get("syntaxDanger"), bool):
        errors.append("validation.syntaxDanger must be boolean")
    if validation.get("ok") is False and not validation.get("rejectedReason"):
        errors.append("rejectedReason required when validation.ok is false")
    if validation.get("ok") is True:
        for key in ("beforeContentHash", "patchFingerprint", "readSource"):
            if key not in validation:
                errors.append(f"successful validation missing {key}")
    return errors


def validate_search_accounting(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = SEARCH_ACCOUNTING_KEYS - set(result.keys())
    if missing:
        errors.append(f"search accounting missing keys: {sorted(missing)}")
    if result.get("symlinkPolicy") != "skip_never_follow":
        errors.append("symlinkPolicy must be skip_never_follow")
    if result.get("sortOrder") and result.get("sortOrder") != "path_line_column":
        errors.append("sortOrder must be path_line_column when present")
    return errors


def validate_search_text_response(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = SEARCH_TEXT_RESPONSE_KEYS - set(result.keys())
    if missing:
        errors.append(f"search.text missing keys: {sorted(missing)}")
    if result.get("mode") != "literal_substring":
        errors.append("mode must be literal_substring")
    errors.extend(validate_search_accounting(result))
    return errors


def validate_search_todo_response(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = SEARCH_TODO_RESPONSE_KEYS - set(result.keys())
    if missing:
        errors.append(f"search.todo missing keys: {sorted(missing)}")
    if result.get("mode") != "literal_marker_scan":
        errors.append("mode must be literal_marker_scan")
    errors.extend(validate_search_accounting(result))
    return errors


def validate_workspace_revision(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = WORKSPACE_REVISION_KEYS - set(result.keys())
    if missing:
        errors.append(f"workspace.revision missing keys: {sorted(missing)}")
    if result.get("mode") != "workspace_revision":
        errors.append("mode must be workspace_revision")
    if not isinstance(result.get("revisionId"), int) or result["revisionId"] < 1:
        errors.append("revisionId must be positive int")
    return errors


def validate_workspace_snapshot(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = WORKSPACE_SNAPSHOT_KEYS - set(result.keys())
    if missing:
        errors.append(f"workspace.snapshot missing keys: {sorted(missing)}")
    if result.get("mode") != "workspace_snapshot":
        errors.append("mode must be workspace_snapshot")
    return errors


def validate_batch_mutation_receipt(receipt: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = BATCH_MUTATION_RECEIPT_KEYS - set(receipt.keys())
    if missing:
        errors.append(f"batch receipt missing keys: {sorted(missing)}")
    if receipt.get("atomic") is not True:
        errors.append("batch receipt atomic must be true when fully applied")
    file_receipts = receipt.get("fileReceipts")
    if not isinstance(file_receipts, list):
        errors.append("fileReceipts must be list")
    elif file_receipts:
        errors.extend(validate_mutation_receipt(file_receipts[0]))
    return errors


def validate_grep_sort_order(matches: list[dict[str, Any]]) -> list[str]:
    """INVARIANT: matches are sorted path → line → column when sortOrder is path_line_column."""
    errors: list[str] = []
    previous: tuple[str, int, int] | None = None
    for match in matches:
        current = (str(match.get("path", "")), int(match.get("line", 0)), int(match.get("column", 0)))
        if previous and current < previous:
            errors.append(f"grep sort violation: {previous} before {current}")
        previous = current
    return errors


def validate_diff_hunks_response(result: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    missing = DIFF_HUNKS_RESPONSE_KEYS - set(result.keys())
    if missing:
        errors.append(f"diff.hunks missing keys: {sorted(missing)}")
    if result.get("mode") != "literal_unified_diff_hunks":
        errors.append("mode must be literal_unified_diff_hunks")
    files = result.get("files")
    if not isinstance(files, list):
        errors.append("files must be list")
    has_more = result.get("hasMoreHunks")
    next_offset = result.get("nextHunkOffset")
    if has_more and next_offset is None:
        errors.append("nextHunkOffset required when hasMoreHunks is true")
    if not has_more and next_offset is not None:
        errors.append("nextHunkOffset must be null when hasMoreHunks is false")
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
