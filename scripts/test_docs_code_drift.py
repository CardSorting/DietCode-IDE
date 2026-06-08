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
    INTERNAL_METHOD_NAMESPACES,
    REQUIRED_MAKE_TARGETS,
    SEARCH_LITERAL_RESPONSE_KEYS,
    SHELL_ENVELOPE_KEYS,
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


def test_internal_namespaces_documented() -> None:
    fixture = json.loads((FIXTURES / "release" / "internal_method_namespaces.json").read_text(encoding="utf-8"))
    assert fixture["internalNamespaces"] == list(INTERNAL_METHOD_NAMESPACES)
    tooling = (DOCS / "agent-tooling.md").read_text(encoding="utf-8")
    for prefix in INTERNAL_METHOD_NAMESPACES:
        assert prefix in tooling, f"agent-tooling.md must document internal namespace {prefix}"


def test_testing_checklist_has_verify_commands() -> None:
    text = (DOCS / "testing-checklist.md").read_text(encoding="utf-8")
    for target in (
        "verify-agent-runtime",
        "verify-agent-runtime-full",
        "test-agent-workflow-smoke",
        "test-agent-shell-tooling",
        "test-agent-shell-workflows",
    ):
        assert target in text, f"testing-checklist.md missing {target}"


def test_agent_shell_tooling_doc_lists_methods() -> None:
    text = (DOCS / "agent-shell-tooling.md").read_text(encoding="utf-8")
    for method in (
        "shell.pwd",
        "shell.cd",
        "shell.rg",
        "shell.head",
        "shell.tail",
        "shell.sedRange",
        "shell.catSmall",
        "use_shell_head_tail_or_sedRange",
    ):
        assert method in text, f"agent-shell-tooling.md missing {method}"


def test_agent_bridge_doc_lists_shell_methods() -> None:
    text = (DOCS / "agent-bridge.md").read_text(encoding="utf-8")
    for method in ("shellPwd", "shellRg", "shellSedRange", "shellCatSmall"):
        assert method in text, f"agent-bridge.md missing {method}"


def test_shell_error_codes_documented() -> None:
    text = (DOCS / "error-codes.md").read_text(encoding="utf-8")
    for code in (
        "shell_timeout",
        "shell_binary_file",
        "shell_symlink_escape",
        "shell_outside_workspace",
        "shell_rg_failed",
    ):
        assert code in text, f"error-codes.md missing {code}"


def test_shell_envelope_keys_nonempty() -> None:
    assert "complete" in SHELL_ENVELOPE_KEYS
    assert "partial" in SHELL_ENVELOPE_KEYS
    assert len(SHELL_ENVELOPE_KEYS) >= 15


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


def test_root_readme_mentions_audit_and_verify() -> None:
    text = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    for needle in ("agent-runtime-audit.md", "verify-agent-runtime-full", "restart-agent-server"):
        assert needle in text, f"README.md missing {needle}"


def test_build_instructions_mentions_agent_verify() -> None:
    text = (DOCS / "build-instructions.md").read_text(encoding="utf-8")
    for needle in ("verify-agent-runtime", "restart-agent-server", "test-docs-code-drift"):
        assert needle in text, f"build-instructions.md missing {needle}"


def test_agent_environment_mentions_restart_target() -> None:
    text = (DOCS / "agent-environment.md").read_text(encoding="utf-8")
    assert "restart-agent-server" in text, "agent-environment.md must document make restart-agent-server"


def test_file_structure_documents_control_tree() -> None:
    text = (DOCS / "file-structure.md").read_text(encoding="utf-8")
    for needle in ("MacControlServer.mm", "agent_contracts.py", "fixtures/"):
        assert needle in text, f"file-structure.md missing {needle}"


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
        ("drift.internal_namespaces", test_internal_namespaces_documented),
        ("drift.testing_checklist", test_testing_checklist_has_verify_commands),
        ("drift.agent_shell_tooling_doc", test_agent_shell_tooling_doc_lists_methods),
        ("drift.agent_bridge_shell_doc", test_agent_bridge_doc_lists_shell_methods),
        ("drift.shell_error_codes", test_shell_error_codes_documented),
        ("drift.shell_envelope_keys", test_shell_envelope_keys_nonempty),
        ("drift.makefile_targets", test_makefile_has_required_targets),
        ("drift.contract_key_sets", test_contract_key_sets_documented),
        ("drift.frozen_key_sets_nonempty", test_frozen_key_sets_nonempty),
        ("drift.root_readme", test_root_readme_mentions_audit_and_verify),
        ("drift.build_instructions", test_build_instructions_mentions_agent_verify),
        ("drift.agent_environment", test_agent_environment_mentions_restart_target),
        ("drift.file_structure", test_file_structure_documents_control_tree),
    ]:
        recorder.run(name, fn)

    return recorder.finish("docs_code_drift")


if __name__ == "__main__":
    raise SystemExit(main())
