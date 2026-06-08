#!/usr/bin/env python3
"""Live workflow tests for Hermes ↔ DietCode IDE bridge (mirrors bridge live workflows A–C)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BRIDGE_CLI = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"


class Recorder:
    def __init__(self) -> None:
        self.events: list[dict] = []

    def record(self, name: str, ok: bool, detail: str = "") -> None:
        self.events.append({"name": name, "ok": ok, "detail": detail})
        if not ok:
            print(json.dumps({"type": "fail", "name": name, "detail": detail}), file=sys.stderr)

    def finish(self, suite: str) -> int:
        failed = [e for e in self.events if not e["ok"]]
        summary = {
            "type": "summary",
            "suite": suite,
            "passed": len(self.events) - len(failed),
            "failed": len(failed),
            "total": len(self.events),
            "ok": not failed,
        }
        print(json.dumps(summary))
        return 1 if failed else 0


def _run(args: list[str]) -> tuple[bool, dict]:
    cmd = ["node", str(BRIDGE_CLI), "--compact", "--wait-ready", "--workspace", str(REPO_ROOT), *args]
    if APP_PATH.is_file():
        cmd[4:4] = ["--app", str(APP_PATH)]
    completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {}
    except json.JSONDecodeError:
        payload = {"error": raw[:500]}
    ok = completed.returncode == 0 and bool(payload.get("ok", True))
    return ok, payload


def workflow_a_connect(rec: Recorder) -> None:
    ok, payload = _run(["verify", "fast"])
    rec.record("workflow.a.verify", ok, json.dumps(payload)[:300])
    ok, payload = _run(["profile"])
    caps = payload.get("capabilities") or {}
    ok = ok and bool(caps.get("deterministicSearch")) and bool(caps.get("patchReceipts"))
    rec.record("workflow.a.profile", ok, json.dumps(payload)[:300])


def workflow_b_search(rec: Recorder) -> None:
    ok, payload = _run(["search", "literal", "DietCodeBridgeClient", "--max-results", "5"])
    rec.record("workflow.b.search_literal", ok, json.dumps(payload)[:300])
    ok, payload = _run(["stat", "agent-bridge/package.json"])
    result = payload.get("result") if isinstance(payload.get("result"), dict) else payload
    ok = ok and bool(result.get("path") or result.get("contentHash"))
    rec.record("workflow.b.stat", ok, json.dumps(payload)[:300])


def workflow_c_observability(rec: Recorder) -> None:
    ok, payload = _run(["diagnostics"])
    rec.record("workflow.c.diagnostics", ok, json.dumps(payload)[:300])
    ok, payload = _run(["timeline", "recent", "--limit", "5"])
    rec.record("workflow.c.timeline", ok, json.dumps(payload)[:300])
    ok, payload = _run(["activity", "recent", "--limit", "5"])
    rec.record("workflow.c.activity", ok, json.dumps(payload)[:300])


def main() -> int:
    parser = argparse.ArgumentParser(description="Hermes bridge live workflow harness.")
    parser.add_argument("--compact", action="store_true")
    _ = parser.parse_args()

    if not BRIDGE_CLI.is_file():
        print(json.dumps({"type": "summary", "suite": "hermes_bridge_workflows", "ok": False, "error": "bridge CLI missing"}))
        return 1

    rec = Recorder()
    workflow_a_connect(rec)
    workflow_b_search(rec)
    workflow_c_observability(rec)
    return rec.finish("hermes_bridge_workflows")


if __name__ == "__main__":
    raise SystemExit(main())
