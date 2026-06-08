#!/usr/bin/env python3
"""
DRIFT: Pass VI docs-to-code contract alignment checks.

Grep: rg 'test_docs_code_drift|docs_code_drift' scripts/ Makefile docs/
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from agent_contracts import (
    ERROR_RECOVERY_HINTS,
    GREP_RESPONSE_KEYS,
    REQUIRED_MAKE_TARGETS,
    SEARCH_LITERAL_RESPONSE_KEYS,
    TOOL_REGISTRY_ENTRY_KEYS,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT

DOCS = REPO_ROOT / "docs"
FIXTURES = REPO_ROOT / "scripts" / "fixtures"
RUNTIME_DIAG = REPO_ROOT / "src/platform/macos/control/utils/MacControlRuntimeDiagnostics.mm"


def test_error_codes_doc_lists_recovery() -> None:
    text = (DOCS / "error-codes.md").read_text(encoding="utf-8")
    for code in ERROR_RECOVERY_HINTS:
        assert code in text, f"error-codes.md missing {code}"


def test_recovery_fixture_matches_contract() -> None:
    fixture = json.loads((FIXTURES / "recovery" / "error_recovery_hints.json").read_text(encoding="utf-8"))
    for code, expected in ERROR_RECOVERY_HINTS.items():
        row = fixture.get(code)
        assert row, f"fixture missing {code}"
        assert row["recovery_hint"] == expected["recovery_hint"]
        assert row["nextRecommendedCommand"] == expected["nextRecommendedCommand"]


def test_runtime_diagnostics_source_has_hints() -> None:
    text = RUNTIME_DIAG.read_text(encoding="utf-8")
    for code, expected in ERROR_RECOVERY_HINTS.items():
        assert code in text, f"runtime diagnostics missing {code}"
        assert expected["recovery_hint"] in text, f"recovery hint missing for {code}"


def test_agent_tooling_doc_lists_methods() -> None:
    text = (DOCS / "agent-tooling.md").read_text(encoding="utf-8")
    for method in ("search.literal", "search.tokens", "tool.registry", "tool.capabilities", "patch.validate"):
        assert method in text, f"agent-tooling.md missing {method}"


def test_testing_checklist_has_verify_commands() -> None:
    text = (DOCS / "testing-checklist.md").read_text(encoding="utf-8")
    for target in ("verify-agent-runtime", "verify-agent-runtime-full", "test-agent-workflow-smoke"):
        assert target in text, f"testing-checklist.md missing {target}"


def test_makefile_has_required_targets() -> None:
    text = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    for target in REQUIRED_MAKE_TARGETS:
        assert re.search(rf"^{re.escape(target)}:", text, re.MULTILINE), f"Makefile missing {target}"


def test_contract_key_sets_documented() -> None:
    contracts = (REPO_ROOT / "scripts" / "agent_contracts.py").read_text(encoding="utf-8")
    assert "GREP_RESPONSE_KEYS" in contracts
    assert "SEARCH_LITERAL_RESPONSE_KEYS" in contracts
    assert "TOOL_REGISTRY_ENTRY_KEYS" in contracts
    invariants = (DOCS / "runtime-invariants.md").read_text(encoding="utf-8")
    assert "literal_substring" in invariants
    assert "complete" in invariants or "partial" in invariants or "truncated" in invariants


def test_frozen_key_sets_nonempty() -> None:
    assert len(GREP_RESPONSE_KEYS) >= 10
    assert len(SEARCH_LITERAL_RESPONSE_KEYS) >= 10
    assert "failureRecoveryHint" in TOOL_REGISTRY_ENTRY_KEYS


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass VI docs-to-code drift checks.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("drift.error_codes_doc", test_error_codes_doc_lists_recovery),
        ("drift.recovery_fixture", test_recovery_fixture_matches_contract),
        ("drift.runtime_diagnostics_source", test_runtime_diagnostics_source_has_hints),
        ("drift.agent_tooling_doc", test_agent_tooling_doc_lists_methods),
        ("drift.testing_checklist", test_testing_checklist_has_verify_commands),
        ("drift.makefile_targets", test_makefile_has_required_targets),
        ("drift.contract_key_sets", test_contract_key_sets_documented),
        ("drift.frozen_key_sets_nonempty", test_frozen_key_sets_nonempty),
    ]:
        recorder.run(name, fn)

    return recorder.finish("docs_code_drift")


if __name__ == "__main__":
    raise SystemExit(main())
