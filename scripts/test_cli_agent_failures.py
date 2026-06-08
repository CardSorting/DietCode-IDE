#!/usr/bin/env python3
"""
CLI: Pass VI CLI failure ergonomics — real subprocess checks.

Grep: rg 'test_cli_agent_failures|cli_agent_failures' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT

CLIENT = [sys.executable, str(REPO_ROOT / "scripts" / "dietcode_agent_client.py")]


def _run_cli(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        CLIENT + ["--no-start"] + args,
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
    )


def test_invalid_json_params() -> None:
    completed = _run_cli(["rpc.ping", "{not-json"])
    assert completed.returncode == 1
    assert "params JSON is invalid" in completed.stderr or "invalid" in completed.stderr.lower()


def test_conflicting_search_shortcuts() -> None:
    completed = _run_cli(["--grep", "foo", "--search-text", "bar"])
    assert completed.returncode == 1
    assert "only one" in completed.stderr.lower()


def test_search_semantic_deprecation_warning() -> None:
    completed = _run_cli(["--search-semantic", "foo", "--compact"])
    assert "deprecated" in completed.stderr.lower()
    assert completed.returncode == 1


def test_grep_rg_zero_matches_exit() -> None:
    completed = _run_cli(
        ["--grep", "ZZZ_NOT_PRESENT_ANCHOR_12345", "--grep-format", "rg", "--max-results", "1", "--include", "scripts/agent_contracts.py"]
    )
    assert completed.returncode == 1
    assert completed.stdout.strip() == ""


def test_error_json_envelope() -> None:
    completed = _run_cli(["--error-json", "--compact", "search.semantic", '{"query":"x"}'])
    assert completed.returncode == 1
    payload = json.loads(completed.stderr.strip().splitlines()[-1])
    assert payload.get("ok") is False
    assert payload["error"]["string_code"] == "semantic_disabled"
    assert payload["error"].get("nextRecommendedCommand") == "search.literal"


def test_self_test_passes() -> None:
    completed = _run_cli(["--self-test", "--compact"])
    assert completed.returncode == 0
    payload = json.loads(completed.stdout.strip().splitlines()[-1])
    assert payload.get("ok") is True


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass VI CLI failure ergonomics tests.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("cli.invalid_json_params", test_invalid_json_params),
        ("cli.conflicting_search_shortcuts", test_conflicting_search_shortcuts),
        ("cli.search_semantic_deprecation", test_search_semantic_deprecation_warning),
        ("cli.grep_rg_zero_exit", test_grep_rg_zero_matches_exit),
        ("cli.error_json_envelope", test_error_json_envelope),
        ("cli.self_test", test_self_test_passes),
    ]:
        recorder.run(name, fn)

    return recorder.finish("cli_agent_failures")


if __name__ == "__main__":
    raise SystemExit(main())
