#!/usr/bin/env python3
"""
SHELL: Pass IX — shell wrapper offline + quick live checks.

Grep: rg 'test_agent_shell_tooling|test-agent-shell-tooling' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
from collections.abc import Callable
from pathlib import Path

from agent_contracts import (
    SHELL_ENVELOPE_KEYS,
    SHELL_RG_RESPONSE_KEYS,
    SHELL_SED_RANGE_RESPONSE_KEYS,
    validate_shell_envelope,
    validate_shell_range_response,
)
from agent_shell_tooling import (
    FIXTURES_DIR,
    is_destructive_shell_command,
    sed_range_command,
    shell_recovery_hint_for_large_file,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, connect, load_token, send_rpc

FIXTURES_ROOT = REPO_ROOT / "scripts" / "fixtures" / "shell"


def test_offline_destructive_shell_rejection() -> None:
    assert is_destructive_shell_command("sed -i 's/a/b/' file.txt")
    assert is_destructive_shell_command("cat a | grep b")
    assert not is_destructive_shell_command("sed -n '1,10p' file.txt")


def test_offline_sed_range_command_format() -> None:
    assert sed_range_command("src/foo.cpp", 120, 180) == "sed -n '120,180p' src/foo.cpp"


def test_offline_recovery_hint() -> None:
    assert shell_recovery_hint_for_large_file(partial=True, truncated=False) == "use_shell_head_tail_or_sedRange"
    assert shell_recovery_hint_for_large_file(partial=False, truncated=False) == ""


def test_offline_fixture_contract_keys() -> None:
    rg_fixture = json.loads((FIXTURES_ROOT / "rg_response.json").read_text(encoding="utf-8"))
    missing = SHELL_RG_RESPONSE_KEYS - set(rg_fixture.keys())
    assert not missing, f"rg_response.json missing keys: {sorted(missing)}"
    sed_fixture = json.loads((FIXTURES_ROOT / "sed_range_response.json").read_text(encoding="utf-8"))
    missing_sed = SHELL_SED_RANGE_RESPONSE_KEYS - set(sed_fixture.keys())
    assert not missing_sed, f"sed_range_response.json missing keys: {sorted(missing_sed)}"
    cat_fixture = json.loads((FIXTURES_ROOT / "cat_small_truncated.json").read_text(encoding="utf-8"))
    missing_env = SHELL_ENVELOPE_KEYS - set(cat_fixture.keys())
    assert not missing_env, f"cat_small_truncated.json missing envelope keys: {sorted(missing_env)}"
    assert cat_fixture["recoveryHint"] == "use_shell_head_tail_or_sedRange"
    cd_err = json.loads((FIXTURES_ROOT / "cd_outside_workspace_error.json").read_text(encoding="utf-8"))
    assert cd_err["code"] == "outside_workspace"
    binary_err = json.loads((FIXTURES_ROOT / "binary_rejection_error.json").read_text(encoding="utf-8"))
    assert binary_err["code"] == "shell_binary_file"
    symlink_err = json.loads((FIXTURES_ROOT / "symlink_escape_error.json").read_text(encoding="utf-8"))
    assert symlink_err["code"] == "shell_symlink_escape"


def test_live_head_tail(sock: socket.socket, token: str) -> None:
    rel = "scripts/fixtures/shell/anchor_target.txt"
    head = send_rpc(sock, token, "shell.head", {"path": rel, "lines": 3})
    assert head.get("ok"), head
    assert not validate_shell_range_response(head["result"])
    tail = send_rpc(sock, token, "shell.tail", {"path": rel, "lines": 2})
    assert tail.get("ok"), tail
    assert not validate_shell_range_response(tail["result"])
    pwd = send_rpc(sock, token, "shell.pwd", {})
    assert pwd.get("ok"), pwd
    assert not validate_shell_envelope(pwd["result"])
    assert pwd["result"]["complete"] is True


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass IX shell tooling offline + quick live checks.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("shell.offline.destructive_rejection", test_offline_destructive_shell_rejection),
        ("shell.offline.sed_command_format", test_offline_sed_range_command_format),
        ("shell.offline.recovery_hint", test_offline_recovery_hint),
        ("shell.offline.fixture_contract_keys", test_offline_fixture_contract_keys),
    ]
    for name, fn in offline:
        recorder.run(name, fn)

    sock = connect()
    token = load_token()
    recorder.run("shell.live.head_tail_pwd", lambda: test_live_head_tail(sock, token))

    return recorder.finish("agent_shell_tooling")


if __name__ == "__main__":
    raise SystemExit(main())
