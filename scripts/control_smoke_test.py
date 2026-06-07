#!/usr/bin/env python3
"""Deterministic NDJSON smoke checks for the DietCode control socket."""

from __future__ import annotations

import argparse

from dietcode_agent_client import (
    call,
    connect,
    emit_test_line,
    ensure_workspace_root,
    finish_test_run,
    load_token,
    send_rpc,
)


def record(checks: list[dict], name: str, ok: bool, detail: dict | None = None) -> None:
    payload: dict = {"type": "check", "name": name, "ok": ok}
    if detail is not None:
        payload["detail"] = detail
    checks.append(payload)
    emit_test_line(payload)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run NDJSON control-socket smoke checks.")
    parser.add_argument("--compact", action="store_true", default=True, help="Emit compact NDJSON (default).")
    parser.add_argument("--pretty", action="store_true", help="Emit indented JSON instead of compact NDJSON.")
    args = parser.parse_args()
    compact = not args.pretty

    checks: list[dict] = []
    try:
        with connect() as sock:
            token = load_token()

            ping = send_rpc(sock, token, "rpc.ping")
            pong = ping.get("result", {}).get("pong")
            record(checks, "rpc.ping", ping.get("ok") is True and pong is True, {"pong": pong})

            missing = send_rpc(sock, token, "__agent_harness_no_such_method__")
            record(
                checks,
                "rpc.method_not_found",
                missing.get("ok") is False
                and missing.get("error", {}).get("string_code") == "method_not_found",
                {"string_code": missing.get("error", {}).get("string_code"), "code": missing.get("error", {}).get("code")},
            )

            describe_missing = send_rpc(
                sock,
                token,
                "rpc.describe",
                {"method": "__agent_harness_no_such_method__"},
            )
            record(
                checks,
                "rpc.describe_method_not_found",
                describe_missing.get("ok") is False
                and describe_missing.get("error", {}).get("string_code") == "method_not_found",
                {"string_code": describe_missing.get("error", {}).get("string_code")},
            )

            root = ensure_workspace_root(sock, token)
            record(checks, "workspace.getRoot", bool(root), {"path": root})

            grep = call(sock, token, "workspace.grep", {"query": "DietCode", "maxResults": 1})
            matches = grep.get("matches", [])
            record(
                checks,
                "workspace.grep",
                isinstance(matches, list) and grep.get("mode") == "literal_substring",
                {"matchCount": len(matches), "mode": grep.get("mode")},
            )

            git_status = call(sock, token, "git.status", {})
            record(
                checks,
                "git.status",
                isinstance(git_status.get("modified"), list) and isinstance(git_status.get("staged"), list),
                {"keys": sorted(git_status.keys())},
            )

            open_files = call(sock, token, "editor.getOpenFiles", {})
            record(
                checks,
                "editor.getOpenFiles",
                isinstance(open_files.get("files"), list),
                {"fileCount": len(open_files.get("files", []))},
            )

            problems = call(sock, token, "problems.list", {})
            record(
                checks,
                "problems.list",
                isinstance(problems.get("problems"), list),
                {"problemCount": len(problems.get("problems", []))},
            )
    except Exception as exc:
        record(checks, "smoke.exception", False, {"error": str(exc)})

    return finish_test_run(checks, suite="control_smoke", compact=compact)


if __name__ == "__main__":
    raise SystemExit(main())
