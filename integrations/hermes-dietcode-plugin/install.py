# -*- coding: utf-8 -*-
"""Seamless Hermes integration — config defaults and BroccoliDB runtime setup."""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_PLUGIN_NAME = "dietcode"
_MARKER = ".dietcode-integrated"
_IDE_MARKER = ".dietcode-ide-connected"


def plugin_root() -> Path:
    return Path(__file__).resolve().parent


def _ensure_plugin_namespace() -> None:
    """Bootstrap minimal ``plugins.dietcode.*`` tree for standalone install.py runs."""
    try:
        import plugins.dietcode.lib.agent.ide_bridge_client  # noqa: F401
        return
    except ImportError:
        pass

    import types

    plugin_dir = plugin_root()
    plugins_dir = plugin_dir.parent
    if "plugins" not in sys.modules:
        plugins_pkg = types.ModuleType("plugins")
        plugins_pkg.__path__ = [str(plugins_dir)]  # type: ignore[attr-defined]
        plugins_pkg.__package__ = "plugins"
        sys.modules["plugins"] = plugins_pkg

    for name, path in (
        ("plugins.dietcode", plugin_dir),
        ("plugins.dietcode.lib", plugin_dir / "lib"),
        ("plugins.dietcode.lib.agent", plugin_dir / "lib" / "agent"),
    ):
        if name not in sys.modules:
            pkg = types.ModuleType(name)
            pkg.__path__ = [str(path)]  # type: ignore[attr-defined]
            pkg.__package__ = name
            sys.modules[name] = pkg


def broccolidb_root() -> Path:
    return plugin_root() / "broccolidb"


def _integration_marker() -> Path:
    try:
        from hermes_constants import get_hermes_home

        return get_hermes_home() / "plugins" / _PLUGIN_NAME / _MARKER
    except Exception:
        return Path.home() / ".hermes" / "plugins" / _PLUGIN_NAME / _MARKER


def broccolidb_runtime_ready() -> bool:
    root = broccolidb_root()
    if not (root / "package.json").is_file():
        return False
    nm = root / "node_modules"
    return nm.is_dir() and any(nm.iterdir())


def ensure_broccolidb_runtime(*, auto_npm: bool = False, timeout: int = 300) -> dict[str, Any]:
    """Ensure node_modules exists; optionally run ``npm ci``."""
    root = broccolidb_root()
    if not (root / "package.json").is_file():
        return {"ok": False, "error": "broccolidb/package.json missing from plugin bundle"}

    if broccolidb_runtime_ready():
        return {"ok": True, "root": str(root), "action": "ready"}

    if not auto_npm or not shutil.which("npm"):
        return {
            "ok": False,
            "root": str(root),
            "action": "npm_ci_required",
            "hint": f"cd {root} && npm ci",
        }

    try:
        proc = subprocess.run(
            ["npm", "ci"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "CI": "1"},
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()[:500]
            return {"ok": False, "action": "npm_ci_failed", "error": err or f"exit {proc.returncode}"}
        return {"ok": True, "root": str(root), "action": "npm_ci"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "action": "npm_ci_timeout", "error": f"npm ci exceeded {timeout}s"}
    except OSError as exc:
        return {"ok": False, "action": "npm_ci_error", "error": str(exc)}


def apply_seamless_defaults(*, save: bool = True) -> dict[str, Any]:
    """Merge DietCode-friendly defaults into the active Hermes config."""
    try:
        from hermes_cli.config import load_config, save_config
    except ImportError:
        return {"ok": False, "error": "hermes_cli not available"}

    config = load_config()
    changed: list[str] = []

    plugins_cfg = config.setdefault("plugins", {})
    if not isinstance(plugins_cfg, dict):
        plugins_cfg = {}
        config["plugins"] = plugins_cfg

    enabled = plugins_cfg.get("enabled")
    if enabled is None:
        enabled = []
    if not isinstance(enabled, list):
        enabled = []
    enabled_set = set(enabled)
    if _PLUGIN_NAME not in enabled_set:
        enabled_set.add(_PLUGIN_NAME)
        plugins_cfg["enabled"] = sorted(enabled_set)
        changed.append("plugins.enabled")

    disabled = plugins_cfg.get("disabled") or []
    if isinstance(disabled, list) and _PLUGIN_NAME in disabled:
        disabled = [x for x in disabled if x != _PLUGIN_NAME]
        plugins_cfg["disabled"] = disabled
        changed.append("plugins.disabled")

    toolsets = config.get("toolsets")
    if toolsets is None:
        toolsets = ["hermes-cli"]
    if not isinstance(toolsets, list):
        toolsets = ["hermes-cli"]
    if _PLUGIN_NAME not in toolsets:
        toolsets = list(toolsets) + [_PLUGIN_NAME]
        config["toolsets"] = toolsets
        changed.append("toolsets")

    jz = config.setdefault("joyzoning", {})
    if isinstance(jz, dict):
        gov = jz.setdefault("governance", {})
        if isinstance(gov, dict) and "enabled" not in gov:
            gov["enabled"] = True
            changed.append("joyzoning.governance.enabled")

    dietcode_cfg = config.setdefault("dietcode", {})
    if isinstance(dietcode_cfg, dict):
        ide = dietcode_cfg.setdefault("ide", {})
        if isinstance(ide, dict):
            detected_root = auto_detect_ide_root()
            if detected_root and not ide.get("root"):
                ide["root"] = detected_root
                changed.append("dietcode.ide.root")
            for key, default in (
                ("enabled", True),
                ("auto_connect", True),
                ("auto_build", True),
                ("prefer_over_raw_writes", True),
                ("auto_open_workspace", True),
            ):
                if key not in ide:
                    ide[key] = default
                    changed.append(f"dietcode.ide.{key}")
            for env_key, cfg_key in (
                ("DIETCODE_IDE_ROOT", "root"),
                ("DIETCODE_BRIDGE_CLI", "bridge_cli"),
                ("DIETCODE_APP_PATH", "app_path"),
                ("DIETCODE_SOCKET_PATH", "socket_path"),
                ("DIETCODE_TOKEN_PATH", "token_path"),
            ):
                val = os.environ.get(env_key, "").strip()
                if val and not ide.get(cfg_key):
                    ide[cfg_key] = val
                    changed.append(f"dietcode.ide.{cfg_key}")

    if save and changed:
        save_config(config)
        logger.info("DietCode: applied seamless defaults (%s)", ", ".join(changed))

    _sync_hermes_env_from_config(config)

    try:
        _integration_marker().write_text("ok\n", encoding="utf-8")
    except OSError:
        pass

    return {"ok": True, "changed": changed, "saved": bool(save and changed)}


def auto_detect_ide_root() -> str | None:
    """Delegate to ide_bridge_client auto-detect when importable."""
    _ensure_plugin_namespace()
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import auto_detect_ide_root as _detect

        return _detect()
    except ImportError:
        return None


def _sync_hermes_env_from_config(config: dict[str, Any]) -> None:
    """Mirror dietcode.ide paths into ~/.hermes/.env for subprocess agents."""
    try:
        from hermes_constants import get_hermes_home

        env_path = get_hermes_home() / ".env"
    except Exception:
        env_path = Path.home() / ".hermes" / ".env"

    dietcode = config.get("dietcode", {}) if isinstance(config, dict) else {}
    ide = dietcode.get("ide", {}) if isinstance(dietcode, dict) else {}
    if not isinstance(ide, dict):
        return

    mapping = {
        "DIETCODE_IDE_ROOT": ide.get("root"),
        "DIETCODE_REPO_ROOT": ide.get("root"),
        "DIETCODE_BRIDGE_CLI": ide.get("bridge_cli"),
        "DIETCODE_APP_PATH": ide.get("app_path"),
        "DIETCODE_SOCKET_PATH": ide.get("socket_path"),
        "DIETCODE_TOKEN_PATH": ide.get("token_path"),
    }
    lines: list[str] = []
    if env_path.is_file():
        lines = env_path.read_text(encoding="utf-8").splitlines()

    changed = False
    for key, value in mapping.items():
        val = str(value or "").strip()
        if not val:
            continue
        found = False
        for idx, line in enumerate(lines):
            if line.startswith(f"{key}="):
                if line != f"{key}={val}":
                    lines[idx] = f"{key}={val}"
                    changed = True
                found = True
                break
        if not found:
            lines.append(f"{key}={val}")
            changed = True

    if changed:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def ensure_ide_bridge_runtime(*, auto_build: bool = True) -> dict[str, Any]:
    """Ensure agent-bridge CLI exists and DietCode socket is reachable when configured."""
    _ensure_plugin_namespace()
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import (
            _load_ide_config,
            connect_preflight,
            ensure_bridge_built,
            ensure_runtime_socket,
            probe_bridge_available,
        )
    except ImportError as exc:
        return {"ok": False, "error": str(exc)}

    cfg = _load_ide_config()
    if not cfg.enabled:
        return {"ok": True, "action": "disabled"}

    probe = probe_bridge_available()
    if not probe.get("ok"):
        built = ensure_bridge_built(auto_build=auto_build)
        if not built.get("ok"):
            return built
        probe = probe_bridge_available()

    if cfg.auto_connect:
        socket_step = ensure_runtime_socket()
        if not socket_step.get("ok"):
            return socket_step

    preflight = connect_preflight(warm=True, force=True)
    try:
        marker = _integration_marker().parent / _IDE_MARKER
        if preflight.get("ok"):
            marker.write_text(
                f"ok socket={preflight.get('socket_path')}\n",
                encoding="utf-8",
            )
        elif marker.is_file():
            marker.unlink(missing_ok=True)
    except OSError:
        pass
    return preflight


def run_install_wizard(*, auto_npm: bool = True, auto_build: bool = True) -> dict[str, Any]:
    """CLI / drag-and-drop installer — config + optional npm ci + IDE bridge."""
    cfg = apply_seamless_defaults(save=True)
    runtime = ensure_broccolidb_runtime(auto_npm=auto_npm)
    ide = ensure_ide_bridge_runtime(auto_build=auto_build)
    return {"config": cfg, "broccolidb": runtime, "ide_bridge": ide}


if __name__ == "__main__":
    import json

    argv = __import__("sys").argv
    dry_run = "--dry-run" in argv
    skip_npm = "--skip-npm" in argv
    if dry_run:
        cfg = apply_seamless_defaults(save=False)
        result = {
            "ok": True,
            "dry_run": True,
            "config": cfg,
            "broccolidb": {"ok": True, "action": "skipped"},
            "ide_bridge": {"ok": True, "action": "skipped"},
        }
    else:
        result = run_install_wizard(auto_npm=not skip_npm)
    print(json.dumps(result, indent=2))
