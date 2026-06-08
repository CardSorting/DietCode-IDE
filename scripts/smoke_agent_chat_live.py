#!/usr/bin/env python3
"""Live smoke: bounded agent chat performs a real edit via Hermes + dietcode_ide + bridge."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from dietcode_agent_bundle import (  # noqa: E402
    assert_chat_ready,
    open_runtime_workspace,
    repo_root_from_script,
    resolve_context,
    run_enable_doctor,
    run_hermes_chat,
)

PROBE_REL = "smoke_probe.py"
PROBE_BROKEN = "VALUE = 1\n"
PROBE_FIXED_RE = re.compile(r"VALUE\s*=\s*2\b")
DEFAULT_TIMEOUT = int(os.environ.get("AGENT_CHAT_SMOKE_TIMEOUT", "180"))
DEFAULT_MAX_TURNS = int(os.environ.get("AGENT_CHAT_SMOKE_MAX_TURNS", "10"))


def _smoke_prompt(workspace: Path) -> str:
    return (
        f"Workspace: {workspace}. "
        f"In {PROBE_REL}, change `VALUE = 1` to `VALUE = 2`. "
        "Use dietcode_ide only: stat or search_literal to read, then patch. "
        "One file, one line — apply the patch in this turn."
    )


class Recorder:
    def __init__(self, *, compact: bool) -> None:
        self.compact = compact
        self.events: list[dict[str, Any]] = []
        self.transcript = ""

    def record(self, name: str, ok: bool, detail: str | dict[str, Any] = "") -> None:
        payload: dict[str, Any] = {"type": "check", "name": name, "ok": ok}
        if detail:
            payload["detail"] = detail
        self.events.append(payload)
        if self.compact:
            print(json.dumps(payload), flush=True)

    def progress(self, name: str, detail: dict[str, Any]) -> None:
        payload = {"type": "progress", "name": name, **detail}
        if self.compact:
            print(json.dumps(payload), flush=True)

    def set_transcript(self, text: str) -> None:
        self.transcript = text.strip()
        if self.compact and self.transcript:
            compact = self.transcript if len(self.transcript) <= 1200 else self.transcript[-1200:]
            print(json.dumps({"type": "transcript", "text": compact}), flush=True)

    def finish(self, *, suite: str, skipped: bool = False) -> int:
        checks = [e for e in self.events if e.get("type") == "check"]
        failed = [e for e in checks if not e["ok"]]
        summary: dict[str, Any] = {
            "type": "summary",
            "suite": suite,
            "passed": len(checks) - len(failed),
            "failed": len(failed),
            "total": len(checks),
            "ok": not failed and not skipped,
            "skipped": skipped,
        }
        if self.transcript:
            summary["transcriptChars"] = len(self.transcript)
        print(json.dumps(summary), flush=True)
        return 0 if (not failed and not skipped) else (0 if skipped else 1)


def _bridge_argv(ctx, workspace: Path) -> list[str] | None:
    if not ctx.bridge_cli or not ctx.app_path:
        return None
    prefix = ["node", str(ctx.bridge_cli)] if ctx.bridge_cli.suffix == ".js" else [str(ctx.bridge_cli)]
    return [
        *prefix,
        "--compact",
        "--wait-ready",
        "--workspace",
        str(workspace),
        "--app",
        str(ctx.app_path),
    ]


def _run_bridge(ctx, workspace: Path, tail: list[str], *, timeout: int = 60) -> tuple[bool, dict[str, Any]]:
    base = _bridge_argv(ctx, workspace)
    if base is None:
        return False, {"error": "bridge_unavailable"}
    completed = subprocess.run(
        [*base, *tail],
        cwd=str(workspace),
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:500]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:500]}
    ok = completed.returncode == 0 and payload.get("ok") is not False
    return ok, payload


def _timeline_mentions_patch(timeline_payload: dict[str, Any], rel_path: str) -> bool:
    blob = json.dumps(timeline_payload)
    lowered = blob.lower()
    return rel_path in blob and ("patch" in lowered or "mutation" in lowered)


def _run_hermes_with_heartbeat(
    rec: Recorder,
    ctx,
    workspace: Path,
    *,
    max_turns: int,
    timeout: int,
) -> tuple[int, str]:
    stop = threading.Event()
    started = time.monotonic()

    def _heartbeat() -> None:
        while not stop.wait(15):
            rec.progress(
                "smoke.chat_running",
                {"elapsedSec": int(time.monotonic() - started), "timeoutSec": timeout},
            )

    thread = threading.Thread(target=_heartbeat, daemon=True)
    thread.start()
    try:
        return run_hermes_chat(
            ctx,
            workspace,
            _smoke_prompt(workspace),
            max_turns=max_turns,
            timeout=timeout,
            yolo=True,
        )
    finally:
        stop.set()
        thread.join(timeout=1)


def run_smoke(*, app_bundle: str | None, compact: bool, max_turns: int, timeout: int) -> int:
    rec = Recorder(compact=compact)
    script_file = Path(__file__)
    repo_root = repo_root_from_script(script_file)
    ctx = resolve_context(
        repo_root=repo_root,
        app_bundle_arg=app_bundle,
        invoked_path=script_file,
    )

    doctor = run_enable_doctor(repo_root, ctx)
    rec.record("smoke.doctor", bool(doctor.get("ok")), doctor)

    workspace_dir = tempfile.mkdtemp(prefix="dietcode-agent-chat-smoke-")
    workspace = Path(workspace_dir)
    probe_path = workspace / PROBE_REL

    try:
        probe_path.write_text(PROBE_BROKEN, encoding="utf-8")
        rec.record("smoke.workspace_created", probe_path.is_file(), {"workspace": str(workspace)})

        try:
            assert_chat_ready(ctx, repo_root, workspace)
            rec.record("smoke.chat_ready", True)
        except Exception as exc:
            rec.record("smoke.chat_ready", False, str(exc))
            return rec.finish(suite="smoke_agent_chat_live")

        opened = open_runtime_workspace(ctx, workspace)
        rec.record("smoke.workspace_opened", bool(opened.get("ok")), opened)

        ok_verify, verify_payload = _run_bridge(ctx, workspace, ["verify", "fast"])
        rec.record("smoke.bridge_verify", ok_verify, verify_payload)

        rec.record(
            "smoke.chat_start",
            True,
            {"prompt": _smoke_prompt(workspace), "maxTurns": max_turns, "timeout": timeout},
        )

        chat_exit, transcript = _run_hermes_with_heartbeat(
            rec,
            ctx,
            workspace,
            max_turns=max_turns,
            timeout=timeout,
        )
        rec.set_transcript(transcript)
        rec.record(
            "smoke.chat_exit",
            chat_exit == 0,
            {"chatExit": chat_exit},
        )

        disk_text = probe_path.read_text(encoding="utf-8") if probe_path.is_file() else ""
        rec.record(
            "smoke.file_fixed_disk",
            bool(PROBE_FIXED_RE.search(disk_text)),
            {"content": disk_text.strip()},
        )

        ok_bridge_search, bridge_search = _run_bridge(
            ctx, workspace, ["search", "literal", "VALUE = 2", "--max-results", "5"]
        )
        bridge_hit = False
        if ok_bridge_search:
            result = bridge_search.get("result")
            if not isinstance(result, dict):
                result = bridge_search
            if isinstance(result, dict):
                hits = result.get("results") or []
                bridge_hit = any(
                    isinstance(item, dict) and PROBE_REL in str(item.get("path") or "")
                    for item in hits
                )
        rec.record(
            "smoke.file_fixed_bridge",
            ok_bridge_search and bridge_hit,
            {"searchOk": ok_bridge_search, "bridgeHit": bridge_hit},
        )

        ok_timeline, timeline_payload = _run_bridge(ctx, workspace, ["timeline", "recent", "--limit", "30"])
        disk_fixed = bool(PROBE_FIXED_RE.search(disk_text))
        rec.record(
            "smoke.timeline_patch",
            ok_timeline
            and (_timeline_mentions_patch(timeline_payload, PROBE_REL) or disk_fixed),
            {"timelineOk": ok_timeline, "diskFixed": disk_fixed},
        )

        shutil.rmtree(workspace_dir, ignore_errors=True)
        rec.record("smoke.cleanup", not workspace.exists())
        return rec.finish(suite="smoke_agent_chat_live")
    finally:
        shutil.rmtree(workspace_dir, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Live smoke for dietcode-agent-chat bounded edit path.")
    parser.add_argument("--compact", action="store_true", help="Emit NDJSON checks + summary")
    parser.add_argument("--skip-live", action="store_true", help="Skip live Hermes invocation")
    parser.add_argument("--app-bundle", help="Explicit DietCode.app path")
    parser.add_argument("--max-turns", type=int, default=DEFAULT_MAX_TURNS, help="Hermes max turns for smoke")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="Chat subprocess timeout (seconds)")
    args = parser.parse_args()

    if args.skip_live or os.environ.get("AGENT_CHAT_LIVE", "1").strip() in {"0", "false", "no"}:
        print(
            json.dumps(
                {
                    "type": "summary",
                    "suite": "smoke_agent_chat_live",
                    "ok": True,
                    "skipped": True,
                    "reason": "AGENT_CHAT_LIVE=0 or --skip-live",
                }
            ),
            flush=True,
        )
        return 0

    return run_smoke(
        app_bundle=args.app_bundle,
        compact=args.compact,
        max_turns=max(1, args.max_turns),
        timeout=max(30, args.timeout),
    )


if __name__ == "__main__":
    raise SystemExit(main())
