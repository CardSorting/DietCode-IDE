#!/usr/bin/env python3
"""Verify Agent Chat sidebar + bundled CLI production artifacts."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD = REPO_ROOT / "build" / "DietCode.app"
BIN = BUILD / "Contents" / "Resources" / "bin"
SIDEBAR_MM = REPO_ROOT / "src/platform/macos/MacAgentSidebar.mm"
CHAT_TEST = REPO_ROOT / "scripts/test_dietcode_agent_chat.py"


class Recorder:
    def __init__(self) -> None:
        self.events: list[dict] = []

    def record(self, name: str, ok: bool, detail: str = "") -> None:
        self.events.append({"name": name, "ok": ok, "detail": detail})
        if not ok:
            print(json.dumps({"type": "fail", "name": name, "detail": detail}), file=sys.stderr)

    def finish(self) -> int:
        failed = [e for e in self.events if not e["ok"]]
        print(json.dumps({
            "type": "summary",
            "suite": "verify_agent_chat_sidebar",
            "passed": len(self.events) - len(failed),
            "failed": len(failed),
            "total": len(self.events),
            "ok": not failed,
        }))
        return 1 if failed else 0


def main() -> int:
    rec = Recorder()
    rec.record("sidebar.source", SIDEBAR_MM.is_file())
    rec.record("chat.script", (REPO_ROOT / "scripts/dietcode_agent_chat.py").is_file())
    rec.record("chat.launcher", (REPO_ROOT / "resources/bin/dietcode-agent-chat").is_file())
    rec.record("bundle.module", (REPO_ROOT / "scripts/dietcode_agent_bundle.py").is_file())
    rec.record("smoke.live_script", (REPO_ROOT / "scripts/smoke_agent_chat_live.py").is_file())

    for name in (
        "dietcode-agent-chat",
        "dietcode-agent-chat.py",
        "dietcode_agent_bundle.py",
        "dietcode_mutation_authority.py",
        "dietcode_diff_authority.py",
        "dietcode_verification_authority.py",
    ):
        rec.record(f"bundled.{name}", (BIN / name).is_file(), str(BIN / name))

    text = SIDEBAR_MM.read_text(encoding="utf-8") if SIDEBAR_MM.is_file() else ""
    rec.record("sidebar.uses_chat_cli", "dietcode-agent-chat" in text)
    rec.record("sidebar.uses_real_chat_on_send", "launchChatTool:chatPath" in text.replace(" ", "") or ("launchChatTool" in text and "--prompt" in text))
    rec.record("sidebar.stop_button", "_stopButton" in text)
    rec.record("sidebar.open_folder_guard", "Open a folder first." in text)
    rec.record("sidebar.workspace_requested_label", "Workspace requested:" in text)
    rec.record("sidebar.workspace_active_label", "Workspace active:" in text)
    rec.record("sidebar.workspace_mismatch_guard", "Workspace mismatch" in text)
    rec.record("sidebar.mutation_path_label", "Mutation path:" in text)
    rec.record("sidebar.mutation_violation_guard", "Violation" in text and "mutationAuthority" in text)
    rec.record("mutation.authority_module", (REPO_ROOT / "scripts/dietcode_mutation_authority.py").is_file())
    rec.record("mutation.authority_test", (REPO_ROOT / "scripts/test_mutation_authority.py").is_file())
    rec.record("diff.authority_module", (REPO_ROOT / "scripts/dietcode_diff_authority.py").is_file())
    rec.record("diff.authority_test", (REPO_ROOT / "scripts/test_diff_authority.py").is_file())
    rec.record("sidebar.view_diff_button", "View Diff" in text and "viewDiff:" in text)
    rec.record("verification.authority_module", (REPO_ROOT / "scripts/dietcode_verification_authority.py").is_file())
    rec.record("verification.authority_test", (REPO_ROOT / "scripts/test_verification_authority.py").is_file())
    rec.record("sidebar.view_verify_log_button", "View Verify Log" in text and "viewVerifyLog:" in text)
    rec.record("workspace.switch_test", (REPO_ROOT / "scripts/test_agent_chat_workspace_switch.py").is_file())
    rec.record("sidebar.async_dispatch", "dispatch_get_global_queue" in text)

    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8") if (REPO_ROOT / "Makefile").is_file() else ""
    rec.record("makefile.smoke_target", "smoke-agent-chat-live:" in makefile)

    if CHAT_TEST.is_file():
        completed = subprocess.run([sys.executable, str(CHAT_TEST)], cwd=str(REPO_ROOT), capture_output=True, text=True, check=False, timeout=180)
        rec.record("chat.unit_tests", completed.returncode == 0, completed.stdout[-400:] + completed.stderr[-400:])
    else:
        rec.record("chat.unit_tests", False, "missing test file")

    return rec.finish()


if __name__ == "__main__":
    raise SystemExit(main())
