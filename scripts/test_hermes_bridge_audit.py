#!/usr/bin/env python3
"""AUDIT: Hermes ↔ DietCode IDE bridge — pass III production hardening checks."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
PLUGIN_ROOT = HERMES_HOME / "plugins" / "dietcode"
BRIDGE_CLI = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
SETUP_SCRIPT = REPO_ROOT / "scripts" / "setup-hermes-bridge.sh"
WATCHDOG_SCRIPT = REPO_ROOT / "scripts" / "hermes-ide-watchdog.sh"
WORKFLOW_SCRIPT = REPO_ROOT / "scripts" / "test_hermes_bridge_workflows.py"
MAKEFILE = REPO_ROOT / "Makefile"
TOKEN_PATH = Path.home() / ".dietcode" / "session.token"
SOCKET_PATH = Path.home() / ".dietcode" / "control.sock"
CONNECT_BIN = HERMES_HOME / "bin" / "dietcode-ide-connect"
IDE_MARKER = PLUGIN_ROOT / ".dietcode-ide-connected"

REQUIRED_PLUGIN_FILES = (
    "lib/agent/ide_bridge_client.py",
    "lib/runtime/ide_hooks.py",
    "lib/tools/ide_bridge_tools.py",
)

SOURCE_PLUGIN = REPO_ROOT.parent / "hermes-agent-main" / "plugins" / "dietcode-plugin" / "dietcode"
if not SOURCE_PLUGIN.is_dir():
    SOURCE_PLUGIN = Path("/Users/bozoegg/Downloads/hermes-agent-main/plugins/dietcode-plugin/dietcode")


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


def _run_bridge(args: list[str]) -> tuple[bool, str]:
    cmd = ["node", str(BRIDGE_CLI), "--compact", "--no-start"]
    if APP_PATH.is_file():
        cmd.extend(["--app", str(APP_PATH)])
    cmd.extend(["--workspace", str(REPO_ROOT), *args])
    completed = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, check=False)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    ok = completed.returncode == 0
    if ok and line:
        try:
            payload = json.loads(line)
            ok = bool(payload.get("ok", True))
            return ok, json.dumps(payload)
        except json.JSONDecodeError:
            ok = False
    return ok, raw[:500]


def test_setup_script_exists(rec: Recorder) -> None:
    rec.record("audit.setup_script", SETUP_SCRIPT.is_file())
    rec.record("audit.watchdog_script", WATCHDOG_SCRIPT.is_file())
    rec.record("audit.workflow_script", WORKFLOW_SCRIPT.is_file())


def test_makefile_targets(rec: Recorder) -> None:
    text = MAKEFILE.read_text(encoding="utf-8")
    for target in ("setup-hermes-bridge:", "test-hermes-bridge-audit:", "verify-hermes-bridge:", "test-hermes-bridge-workflows:"):
        rec.record(f"audit.makefile.{target.rstrip(':')}", target in text)


def test_plugin_files_installed(rec: Recorder) -> None:
    missing = [rel for rel in REQUIRED_PLUGIN_FILES if not (PLUGIN_ROOT / rel).is_file()]
    rec.record("audit.plugin_files", not missing, ", ".join(missing) if missing else "ok")


def test_source_plugin_has_retry(rec: Recorder) -> None:
    client = SOURCE_PLUGIN / "lib/agent/ide_bridge_client.py"
    if not client.is_file():
        rec.record("audit.source_retry", False, "source plugin missing")
        return
    text = client.read_text(encoding="utf-8")
    rec.record("audit.source_retry", "reconnect_bridge" in text and "_execute_bridge_call" in text)
    rec.record("audit.source_post_hook", "_post_tool_call" in (SOURCE_PLUGIN / "lib/runtime/ide_hooks.py").read_text(encoding="utf-8"))


def test_tools_loader_contract(rec: Recorder) -> None:
    loader = PLUGIN_ROOT / "tools_loader.py"
    if not loader.is_file():
        rec.record("audit.tools_loader", False, "missing")
        return
    text = loader.read_text(encoding="utf-8")
    rec.record("audit.tools_loader_dietcode_ide", "dietcode_ide" in text)


def test_hooks_wiring(rec: Recorder) -> None:
    hooks = PLUGIN_ROOT / "hooks.py"
    if not hooks.is_file():
        rec.record("audit.hooks_wiring", False, "missing hooks.py")
        return
    text = hooks.read_text(encoding="utf-8")
    rec.record("audit.hooks_ide_pre", "ide_pre" in text)
    rec.record("audit.hooks_ide_post", "ide_post" in text)


def test_bridge_cli_built(rec: Recorder) -> None:
    rec.record("audit.bridge_cli", BRIDGE_CLI.is_file(), str(BRIDGE_CLI))


def test_runtime_artifacts(rec: Recorder) -> None:
    rec.record("audit.socket_path", SOCKET_PATH.exists(), str(SOCKET_PATH))
    rec.record("audit.token_path", TOKEN_PATH.is_file() and TOKEN_PATH.stat().st_size > 0, str(TOKEN_PATH))


def test_connect_bin(rec: Recorder) -> None:
    rec.record("audit.dietcode_ide_connect_bin", CONNECT_BIN.is_file() and os.access(CONNECT_BIN, os.X_OK), str(CONNECT_BIN))


def test_ide_marker(rec: Recorder) -> None:
    rec.record("audit.ide_connected_marker", IDE_MARKER.is_file(), str(IDE_MARKER))


def test_bridge_verify_live(rec: Recorder) -> None:
    if not BRIDGE_CLI.is_file():
        rec.record("audit.bridge_verify", False, "bridge CLI missing")
        return
    ok, detail = _run_bridge(["verify", "fast"])
    rec.record("audit.bridge_verify", ok, detail)


def test_bridge_profile_live(rec: Recorder) -> None:
    if not BRIDGE_CLI.is_file():
        rec.record("audit.bridge_profile", False, "bridge CLI missing")
        return
    ok, detail = _run_bridge(["profile"])
    if ok:
        try:
            payload = json.loads(detail)
            caps = payload.get("capabilities") or {}
            ok = bool(caps.get("deterministicSearch")) and bool(caps.get("patchReceipts"))
        except json.JSONDecodeError:
            ok = False
    rec.record("audit.bridge_profile", ok, detail[:500])


def test_bridge_search_live(rec: Recorder) -> None:
    if not BRIDGE_CLI.is_file():
        rec.record("audit.bridge_search", False, "bridge CLI missing")
        return
    ok, detail = _run_bridge(["search", "literal", "DietCodeBridgeClient", "--max-results", "3"])
    rec.record("audit.bridge_search", ok, detail[:500])


def test_bridge_stat_live(rec: Recorder) -> None:
    if not BRIDGE_CLI.is_file():
        rec.record("audit.bridge_stat", False, "bridge CLI missing")
        return
    ok, detail = _run_bridge(["stat", "agent-bridge/package.json"])
    rec.record("audit.bridge_stat", ok, detail[:500])


def test_hermes_config(rec: Recorder) -> None:
    cfg_path = HERMES_HOME / "config.yaml"
    if not cfg_path.is_file():
        rec.record("audit.hermes_config", False, "config.yaml missing")
        return
    text = cfg_path.read_text(encoding="utf-8")
    rec.record("audit.config_dietcode_ide", "dietcode:" in text and "ide:" in text)
    rec.record("audit.config_toolset", "dietcode" in text)
    rec.record("audit.config_auto_connect", "auto_connect" in text)
    rec.record("audit.config_prefer_raw_writes", "prefer_over_raw_writes" in text)


def test_hermes_env(rec: Recorder) -> None:
    env_path = HERMES_HOME / ".env"
    if not env_path.is_file():
        rec.record("audit.hermes_env", False, ".env missing")
        return
    text = env_path.read_text(encoding="utf-8")
    rec.record("audit.env_ide_root", "DIETCODE_IDE_ROOT=" in text)
    rec.record("audit.env_bridge_cli", "DIETCODE_BRIDGE_CLI=" in text)
    rec.record("audit.env_app_path", "DIETCODE_APP_PATH=" in text)


def test_python_preflight(rec: Recorder) -> None:
    if not (PLUGIN_ROOT / "lib/agent/ide_bridge_client.py").is_file():
        rec.record("audit.python_preflight", False, "plugin not installed")
        return
    code = """
import importlib.util, json, sys, types
from pathlib import Path
root = Path(sys.argv[1])
plugins_pkg = types.ModuleType("plugins")
plugins_pkg.__path__ = [str(root.parent)]
sys.modules["plugins"] = plugins_pkg
for name, sub in (
    ("plugins.dietcode", root),
    ("plugins.dietcode.lib", root / "lib"),
    ("plugins.dietcode.lib.agent", root / "lib" / "agent"),
):
    pkg = types.ModuleType(name)
    pkg.__path__ = [str(sub)]
    sys.modules[name] = pkg
spec = importlib.util.spec_from_file_location(
    "plugins.dietcode.lib.agent.ide_bridge_client",
    root / "lib/agent/ide_bridge_client.py",
)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
print(json.dumps(mod.ensure_connected(force=True)))
"""
    completed = subprocess.run(
        [sys.executable, "-c", code, str(PLUGIN_ROOT)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "DIETCODE_IDE_ROOT": str(REPO_ROOT), "DIETCODE_BRIDGE_CLI": str(BRIDGE_CLI), "DIETCODE_APP_PATH": str(APP_PATH)},
    )
    ok = completed.returncode == 0
    detail = completed.stdout.strip() or completed.stderr.strip()
    if ok:
        try:
            payload = json.loads(detail.splitlines()[-1])
            ok = bool(payload.get("ok"))
        except json.JSONDecodeError:
            ok = False
    rec.record("audit.python_preflight", ok, detail[:500])


def test_python_reconnect(rec: Recorder) -> None:
    if not (PLUGIN_ROOT / "lib/agent/ide_bridge_client.py").is_file():
        rec.record("audit.python_reconnect", False, "plugin not installed")
        return
    code = """
import importlib.util, json, sys, types
from pathlib import Path
root = Path(sys.argv[1])
for name, sub in (
    ("plugins", root.parent),
    ("plugins.dietcode", root),
    ("plugins.dietcode.lib", root / "lib"),
    ("plugins.dietcode.lib.agent", root / "lib" / "agent"),
):
    pkg = types.ModuleType(name.rsplit(".", 1)[-1] if "." in name else "plugins")
    if name == "plugins":
        pkg = types.ModuleType("plugins")
    else:
        pkg = types.ModuleType(name)
    pkg.__path__ = [str(sub if name != "plugins" else root.parent)]
    pkg.__package__ = name
    sys.modules[name] = pkg
spec = importlib.util.spec_from_file_location(
    "plugins.dietcode.lib.agent.ide_bridge_client",
    root / "lib/agent/ide_bridge_client.py",
)
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
print(json.dumps(mod.reconnect_bridge()))
"""
    completed = subprocess.run(
        [sys.executable, "-c", code, str(PLUGIN_ROOT)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "DIETCODE_IDE_ROOT": str(REPO_ROOT), "DIETCODE_BRIDGE_CLI": str(BRIDGE_CLI), "DIETCODE_APP_PATH": str(APP_PATH)},
    )
    ok = completed.returncode == 0
    detail = completed.stdout.strip() or completed.stderr.strip()
    if ok:
        try:
            payload = json.loads(detail.splitlines()[-1])
            ok = bool(payload.get("ok"))
        except json.JSONDecodeError:
            ok = False
    rec.record("audit.python_reconnect", ok, detail[:500])


def main() -> int:
    parser = argparse.ArgumentParser(description="Hermes bridge audit harness (pass III).")
    parser.add_argument("--compact", action="store_true")
    _ = parser.parse_args()

    rec = Recorder()
    test_setup_script_exists(rec)
    test_makefile_targets(rec)
    test_plugin_files_installed(rec)
    test_source_plugin_has_retry(rec)
    test_tools_loader_contract(rec)
    test_hooks_wiring(rec)
    test_bridge_cli_built(rec)
    test_runtime_artifacts(rec)
    test_connect_bin(rec)
    test_ide_marker(rec)
    test_bridge_verify_live(rec)
    test_bridge_profile_live(rec)
    test_bridge_search_live(rec)
    test_bridge_stat_live(rec)
    test_hermes_config(rec)
    test_hermes_env(rec)
    test_python_preflight(rec)
    test_python_reconnect(rec)
    return rec.finish("hermes_bridge_audit")


if __name__ == "__main__":
    raise SystemExit(main())
