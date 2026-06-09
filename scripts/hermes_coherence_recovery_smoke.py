#!/usr/bin/env python3
"""Hermes bridge path: dietcode_ide patch recovers from coherence_mismatch like kernel smoke."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import sys
import types
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = _SCRIPT_DIR.parent
PLUGIN_ROOT = REPO_ROOT / "integrations" / "hermes-dietcode-plugin"
FIXTURES = _SCRIPT_DIR / "fixtures" / "coherence_recovery"
BRIDGE_CLI = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"

if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from agent_test_support import CheckRecorder, add_output_args, output_compact  # noqa: E402
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc  # noqa: E402
from dietcode_coherence import (  # noqa: E402
    build_line_replacement_patch_for_content,
    current_int_assignment,
    read_with_coherence,
)


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_event(event_type: str, task_id: str, **payload: Any) -> None:
    record = {
        "type": event_type,
        "taskId": task_id,
        "timestamp": _iso_now(),
        "source": "hermes-coherence-recovery-smoke",
        **payload,
    }
    print(json.dumps(record, ensure_ascii=False), flush=True)


def _load_ide_bridge_client():
    """Load integrations plugin as plugins.dietcode (Hermes layout)."""
    root = PLUGIN_ROOT
    for name, sub in (
        ("plugins", root.parent),
        ("plugins.dietcode", root),
        ("plugins.dietcode.lib", root / "lib"),
        ("plugins.dietcode.lib.agent", root / "lib" / "agent"),
    ):
        pkg = types.ModuleType(name)
        pkg.__path__ = [str(sub if name != "plugins" else root.parent)]
        pkg.__package__ = name
        sys.modules[name] = pkg

    for module_name, rel_path in (
        ("plugins.dietcode.lib.agent.coherence_patch", "lib/agent/coherence_patch.py"),
        ("plugins.dietcode.lib.agent.ide_bridge_client", "lib/agent/ide_bridge_client.py"),
    ):
        spec = importlib.util.spec_from_file_location(module_name, root / rel_path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"failed to load module spec for {module_name}")
        mod = importlib.util.module_from_spec(spec)
        mod.__package__ = "plugins.dietcode.lib.agent"
        sys.modules[spec.name] = mod
        spec.loader.exec_module(mod)
    return sys.modules["plugins.dietcode.lib.agent.ide_bridge_client"]


def _value_patch(rel_path: str, content: str, from_value: int, to_value: int) -> str:
    return build_line_replacement_patch_for_content(
        rel_path,
        content,
        search=f"VALUE = {from_value}",
        replace=f"VALUE = {to_value}",
    )


def run_hermes_coherence_smoke() -> None:
    if not BRIDGE_CLI.is_file():
        raise RuntimeError(f"bridge CLI missing: {BRIDGE_CLI}")

    task_id = f"task_hermes_coherence_{uuid.uuid4().hex[:8]}"
    probe_name = f".dietcode/hermes_coherence_{uuid.uuid4().hex[:8]}/probe.py"

    os.environ["DIETCODE_TASK_ID"] = task_id
    os.environ["DIETCODE_IDE_ROOT"] = str(REPO_ROOT)
    os.environ["DIETCODE_BRIDGE_CLI"] = str(BRIDGE_CLI)
    os.environ["DIETCODE_HEADLESS_AUTO_APPROVE"] = "1"
    if APP_PATH.is_file():
        os.environ["DIETCODE_APP_PATH"] = str(APP_PATH)

    bridge = _load_ide_bridge_client()
    bridge.invalidate_preflight_cache()
    preflight = bridge.connect_preflight(warm=True, force=True)
    if not preflight.get("ok"):
        raise RuntimeError(f"bridge preflight failed: {preflight}")

    sock = connect()
    token = load_token()
    workspace_root = Path(ensure_workspace_root(sock, token))
    probe_abs = workspace_root / probe_name
    probe_abs.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(FIXTURES / "probe.py", probe_abs)
    shutil.copyfile(FIXTURES / "verify.sh", probe_abs.parent / "verify.sh")
    (probe_abs.parent / "verify.sh").chmod(0o755)

    emit_event("task.started", task_id, path=probe_name, workspace=str(workspace_root))

    initial = read_with_coherence(sock, token, probe_name, task_id)
    initial_text = initial["text"]
    if current_int_assignment(initial_text) != 1:
        raise RuntimeError(f"expected VALUE=1 after fixture copy, got: {initial_text!r}")
    emit_event("context.read", task_id, action="file.read", path=probe_name, value=1)

    stale_patch = _value_patch(probe_name, initial_text, 1, 2)
    validated_stale = send_rpc(
        sock, token, "patch.validate", {"path": probe_name, "patch": stale_patch}
    )
    if not validated_stale.get("ok"):
        raise RuntimeError(f"stale patch.validate failed: {validated_stale}")

    probe_abs.write_text(initial_text.replace("VALUE = 1", "VALUE = 3"), encoding="utf-8")
    emit_event("workspace.external_change", task_id, path=probe_name, value=3)

    emit_event("hermes.patch.started", task_id, path=probe_name)
    result = bridge.run_safe_file_patch(
        probe_name,
        stale_patch,
        workspace=str(workspace_root),
        timeout=180.0,
    )
    emit_event(
        "hermes.patch.completed",
        task_id,
        path=probe_name,
        applied=bool(result.get("applied")),
        coherenceStale=bool(result.get("coherenceStale")),
    )

    if not result.get("applied"):
        raise RuntimeError(f"Hermes bridge patch did not apply after coherence recovery: {result}")

    if current_int_assignment(probe_abs.read_text(encoding="utf-8")) != 2:
        raise RuntimeError("probe.py was not updated to VALUE = 2")

    emit_event("mutation.applied", task_id, path=probe_name, changedPaths=[probe_name])
    emit_event("task.completed", task_id, exitCode=0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Hermes bridge coherence recovery smoke.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)
    recorder.run("hermes.coherence_recovery", run_hermes_coherence_smoke)
    return recorder.finish("hermes_coherence_recovery_smoke")


if __name__ == "__main__":
    raise SystemExit(main())
