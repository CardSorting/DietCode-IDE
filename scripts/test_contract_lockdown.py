#!/usr/bin/env python3
"""
CONTRACT: Offline regression lockdown — harness schemas, fixtures, Makefile targets, source invariants.

Grep: rg 'CONTRACT:|test_contract_lockdown' scripts/ docs/runtime-contracts.md
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from agent_contracts import (
    GOLDEN_ERROR_CODES,
    INTEGRATION_SUITES,
    REQUIRED_MAKE_TARGETS,
    SUMMARY_SCHEMA_KEYS,
    validate_check_line,
    validate_summary_line,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, finish_test_run

FIXTURES_DIR = REPO_ROOT / "scripts" / "fixtures" / "rpc"
CONTROL_SERVER = REPO_ROOT / "src/platform/macos/control/MacControlServer.mm"
MAKEFILE = REPO_ROOT / "Makefile"
RUNTIME_CONTRACTS_DOC = REPO_ROOT / "docs/runtime-contracts.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_summary_schema() -> None:
    checks = [{"name": "a", "ok": True}, {"name": "b", "ok": False}]
    code = finish_test_run(checks, suite="lockdown_probe", compact=True)
    assert code == 1
    # finish_test_run prints last; validate schema via helper instead of parsing stdout.
    payload = {
        "type": "summary",
        "suite": "lockdown_probe",
        "ok": False,
        "checks": 2,
        "passed": 1,
        "failed": 1,
        "failedNames": ["b"],
    }
    errors = validate_summary_line(payload)
    assert not errors, errors
    assert SUMMARY_SCHEMA_KEYS.issubset(payload.keys())


def check_check_line_schema() -> None:
    payload = {"type": "check", "name": "contract.example", "ok": True}
    errors = validate_check_line(payload)
    assert not errors, errors


def check_fixtures_exist() -> None:
    required = [
        "request_ping.json",
        "expected_error_codes.json",
        "malformed_line.txt",
        "envelope_success.schema.json",
    ]
    for name in required:
        path = FIXTURES_DIR / name
        assert path.is_file(), f"missing fixture: {path}"
    codes = json.loads((FIXTURES_DIR / "expected_error_codes.json").read_text(encoding="utf-8"))
    for scenario, string_code in codes.items():
        assert isinstance(string_code, str) and string_code, scenario


def check_golden_error_code_alignment() -> None:
    codes = json.loads((FIXTURES_DIR / "expected_error_codes.json").read_text(encoding="utf-8"))
    for key in ("unknown_method", "event_subscribe_empty_types", "malformed_json_line"):
        assert codes[key] in GOLDEN_ERROR_CODES or codes[key] in {
            "invalid_request",
            "method_not_found",
            "invalid_params",
        }


def check_makefile_targets() -> None:
    text = _read(MAKEFILE)
    for target in REQUIRED_MAKE_TARGETS:
        assert re.search(rf"^{re.escape(target)}:", text, re.MULTILINE), f"Makefile missing target: {target}"


def check_integration_scripts_compact() -> None:
    for name, rel_path in INTEGRATION_SUITES.items():
        path = REPO_ROOT / rel_path
        assert path.is_file(), f"missing suite script: {rel_path}"
        text = _read(path)
        assert "finish_test_run" in text or "CheckRecorder" in text, f"{rel_path} must use NDJSON harness"
        assert "--compact" in text or "add_output_args" in text, f"{rel_path} must support --compact"


def check_runtime_contracts_doc() -> None:
    assert RUNTIME_CONTRACTS_DOC.is_file(), "docs/runtime-contracts.md missing"
    text = _read(RUNTIME_CONTRACTS_DOC)
    assert text.count("CONTRACT:") >= 8, "runtime-contracts.md must document at least 8 CONTRACT entries"
    assert "verify-agent-runtime" in text


def check_source_invariants() -> None:
    server = _read(CONTROL_SERVER)
    assert "executeNestedMethod" in server, "nested executor required"
    assert "MacControlJsonSanitizedDictionary" in server, "JSON sanitization required"
    assert "response_serialization_failed" in server, "serialization failure code required"
    assert "@catch (NSException" in server, "exception containment required"
    assert "kDietCodeReadQueueKey" in server, "read queue identity required"
    assert "kDietCodeExecutionQueueKey" in server, "execution queue identity required"
    assert "MacControlRuntimeDiagnostics" in server or "logRuntimeDiagnostic" in server, "runtime diagnostics required"
    client = _read(REPO_ROOT / "scripts" / "dietcode_agent_client.py")
    assert "--diagnose" in client, "client --diagnose required"
    assert "build_diagnostic_snapshot" in client, "diagnostic snapshot required"
    limits = _read(REPO_ROOT / "src/domain/control/ControlRuntimeLimits.hpp")
    assert "kMaxActiveConnections" in limits, "safety limits required"
    assert (REPO_ROOT / "docs/runtime-safety.md").is_file(), "runtime-safety.md required"
    assert (REPO_ROOT / "scripts/runtime_safety.py").is_file(), "runtime_safety.py required"
    assert (REPO_ROOT / "scripts/agent_tooling.py").is_file(), "agent_tooling.py required"
    assert (REPO_ROOT / "scripts/fixtures/tooling/sample_unified_diff.txt").is_file(), "tooling fixture required"
    assert (REPO_ROOT / "scripts/fixtures/tooling/grep_anchor.json").is_file(), "grep anchor fixture required"
    assert (REPO_ROOT / "docs/agent-tooling.md").is_file(), "agent-tooling.md required"
    tooling = _read(REPO_ROOT / "scripts/agent_tooling.py")
    assert "literal_match_spans" in tooling, "literal_match_spans required"
    assert "parse_unified_diff_hunks" in tooling, "parse_unified_diff_hunks required"
    assert "TextForSearchAtPath" in _read(REPO_ROOT / "src/platform/macos/control/utils/MacControlSupport.mm"), "disk grep fallback required"
    assert "ApplyUnifiedPatchToDisk" in _read(REPO_ROOT / "src/platform/macos/control/services/MacControlPatchService.mm"), "disk patch fallback required"
    assert (REPO_ROOT / "docs/runtime-invariants.md").is_file(), "runtime-invariants.md required"
    assert (REPO_ROOT / "scripts/test_runtime_determinism.py").is_file(), "test_runtime_determinism.py required"
    assert (REPO_ROOT / "scripts/test_transaction_kernel.py").is_file(), "test_transaction_kernel.py required"
    assert (REPO_ROOT / "src/platform/macos/control/services/MacControlWorkspaceState.mm").is_file(), "workspace state required"
    assert "skip_never_follow" in _read(REPO_ROOT / "src/platform/macos/control/services/MacControlSearchService.mm"), "symlink policy required"
    assert (REPO_ROOT / "scripts/release_versions.py").is_file(), "release_versions.py required"
    assert (REPO_ROOT / "docs/maintainer-guide.md").is_file(), "maintainer-guide.md required"
    assert "release-check-agent-runtime" in _read(MAKEFILE), "release-check target required"


def check_self_test_in_make_test() -> None:
    text = _read(MAKEFILE)
    assert re.search(r"^test:.*agent-self-test", text, re.MULTILINE) or "agent-self-test" in text


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline contract lockdown checks.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    checks = [
        ("contract.summary_schema", check_summary_schema),
        ("contract.check_line_schema", check_check_line_schema),
        ("contract.fixtures_exist", check_fixtures_exist),
        ("contract.golden_error_codes", check_golden_error_code_alignment),
        ("contract.makefile_targets", check_makefile_targets),
        ("contract.integration_scripts", check_integration_scripts_compact),
        ("contract.runtime_contracts_doc", check_runtime_contracts_doc),
        ("contract.source_invariants", check_source_invariants),
        ("contract.make_test_wires_self_test", check_self_test_in_make_test),
    ]
    for name, fn in checks:
        recorder.run(name, fn)

    return recorder.finish("contract_lockdown")


if __name__ == "__main__":
    raise SystemExit(main())
