#!/usr/bin/env python3
"""Installed-app trust + update safety for DietCode ↔ Hermes agent integration."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
HERMES_HOME = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
PLUGIN_NAME = "dietcode"
ENV_KEYS = (
    "DIETCODE_IDE_ROOT",
    "DIETCODE_REPO_ROOT",
    "DIETCODE_APP_PATH",
    "DIETCODE_APP_BUNDLE",
    "DIETCODE_BRIDGE_CLI",
    "DIETCODE_SOCKET_PATH",
    "DIETCODE_TOKEN_PATH",
)


@dataclass
class BundleContext:
    app_bundle: Path | None
    app_path: Path | None
    bridge_cli: Path | None
    plugin_src: Path
    manifest: dict[str, Any]
    ide_root: Path
    source_label: str


@dataclass
class ChangeLog:
    action: str
    dry_run: bool = False
    backup_dir: str | None = None
    summary: str = ""
    changed: dict[str, Any] = field(default_factory=dict)
    versions: dict[str, Any] = field(default_factory=dict)
    ok: bool = True
    errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "action": self.action,
            "dryRun": self.dry_run,
            "summary": self.summary,
            "backupDir": self.backup_dir,
            "versions": self.versions,
            "changed": self.changed,
            "errors": self.errors,
        }


def _parse_version(raw: str) -> tuple[int, ...]:
    match = re.search(r"(\d+(?:\.\d+)*)", raw)
    if not match:
        return (0,)
    return tuple(int(part) for part in match.group(1).split("."))


def _version_gte(left: str, right: str) -> bool:
    a = _parse_version(left)
    b = _parse_version(right)
    length = max(len(a), len(b))
    a = a + (0,) * (length - len(a))
    b = b + (0,) * (length - len(b))
    return a >= b


def _is_app_bundle(path: Path) -> bool:
    return path.suffix == ".app" and (path / "Contents" / "MacOS").is_dir()


def _app_bundle_locations(*, invoked_path: Path | None = None) -> list[tuple[str, Path]]:
    """Known DietCode.app locations — installed + dev (may or may not exist)."""
    ordered: list[tuple[str, Path]] = []

    def queue(label: str, path: Path) -> None:
        key = str(path)
        if any(existing == key for _, existing in ordered):
            return
        ordered.append((label, path))

    env_bundle = os.environ.get("DIETCODE_APP_BUNDLE", "").strip()
    if env_bundle:
        queue("env:DIETCODE_APP_BUNDLE", Path(env_bundle).expanduser())

    if invoked_path:
        for parent in invoked_path.resolve().parents:
            if parent.suffix == ".app":
                queue("invoked:bundle", parent)
                break

    queue("build", REPO_ROOT / "build" / "DietCode.app")
    queue("system", Path("/Applications/DietCode.app"))
    queue("user", Path.home() / "Applications" / "DietCode.app")
    return ordered


def _candidate_app_bundles(*, invoked_path: Path | None = None) -> list[tuple[str, Path]]:
    return [
        (label, path.resolve())
        for label, path in _app_bundle_locations(invoked_path=invoked_path)
        if _is_app_bundle(path)
    ]


def _read_manifest(app_bundle: Path | None) -> dict[str, Any]:
    paths: list[Path] = []
    if app_bundle:
        paths.append(app_bundle / "Contents" / "Resources" / "dietcode-agent-bundle.manifest.json")
    paths.extend([
        REPO_ROOT / "resources" / "dietcode-agent-bundle.manifest.json",
        REPO_ROOT / "build" / "DietCode.app" / "Contents" / "Resources" / "dietcode-agent-bundle.manifest.json",
    ])
    for path in paths:
        if path.is_file():
            return json.loads(path.read_text(encoding="utf-8"))
    return {
        "bundleKind": "agent-integration-artifact",
        "summary": "DietCode now ships a bundled agent integration artifact, not merely a benchmark bridge.",
        "runtimeVersion": "unknown",
        "bridgeVersion": "unknown",
        "pluginVersion": "unknown",
        "minHermesVersion": "0.15.0",
    }


def _runtime_version_from_bundle(app_bundle: Path | None) -> str:
    if not app_bundle:
        return "unknown"
    plist_path = app_bundle / "Contents" / "Info.plist"
    if not plist_path.is_file():
        return "unknown"
    with plist_path.open("rb") as fh:
        plist = plistlib.load(fh)
    return str(plist.get("CFBundleShortVersionString") or "unknown")


def _bridge_version_from_bundle(app_bundle: Path | None) -> str:
    if not app_bundle:
        package = REPO_ROOT / "agent-bridge" / "package.json"
        if package.is_file():
            return str(json.loads(package.read_text(encoding="utf-8")).get("version") or "unknown")
        return "unknown"
    package = app_bundle / "Contents" / "Resources" / "agent-bridge" / "package.json"
    if package.is_file():
        return str(json.loads(package.read_text(encoding="utf-8")).get("version") or "unknown")
    return "unknown"


def _plugin_version_from_src(plugin_src: Path) -> str:
    plugin_yaml = plugin_src / "plugin.yaml"
    if not plugin_yaml.is_file():
        return "unknown"
    match = re.search(r"^version:\s*([^\s#]+)", plugin_yaml.read_text(encoding="utf-8"), re.MULTILINE)
    return match.group(1) if match else "unknown"


def _resolve_plugin_src(app_bundle: Path | None) -> Path | None:
    if app_bundle:
        bundled = app_bundle / "Contents" / "Resources" / "integrations" / "hermes" / "dietcode"
        if (bundled / "plugin.yaml").is_file():
            return bundled
    integrations = REPO_ROOT / "integrations" / "hermes-dietcode-plugin"
    if (integrations / "plugin.yaml").is_file():
        return integrations
    env_src = os.environ.get("HERMES_PLUGIN_SRC", "").strip()
    if env_src and (Path(env_src) / "plugin.yaml").is_file():
        return Path(env_src)
    return None


def resolve_context(*, app_bundle_arg: str | None = None, invoked_path: Path | None = None) -> BundleContext:
    selected: Path | None = None
    source_label = "unknown"

    if app_bundle_arg:
        candidate = Path(app_bundle_arg).expanduser().resolve()
        if not _is_app_bundle(candidate):
            raise SystemExit(f"Not a DietCode.app bundle: {candidate}")
        selected = candidate
        source_label = "arg:--app-bundle"
    else:
        for label, candidate in _candidate_app_bundles(invoked_path=invoked_path):
            selected = candidate
            source_label = label
            break

    plugin_src = _resolve_plugin_src(selected)
    if plugin_src is None:
        raise SystemExit("DietCode Hermes plugin not found in app bundle or integrations/.")

    if selected:
        app_path = selected / "Contents" / "MacOS" / "DietCode"
        bridge_cli = selected / "Contents" / "Resources" / "bin" / "dietcode-agent-client"
        ide_root = selected
    else:
        app_path = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
        bridge_cli = REPO_ROOT / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
        ide_root = REPO_ROOT

    if bridge_cli and not bridge_cli.is_file():
        js_cli = None
        if selected:
            js_cli = selected / "Contents" / "Resources" / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js"
        if js_cli and js_cli.is_file():
            bridge_cli = js_cli

    manifest = _read_manifest(selected)
    return BundleContext(
        app_bundle=selected,
        app_path=app_path if app_path.is_file() else None,
        bridge_cli=bridge_cli if bridge_cli and bridge_cli.is_file() else None,
        plugin_src=plugin_src,
        manifest=manifest,
        ide_root=ide_root,
        source_label=source_label,
    )


def _hermes_version() -> str | None:
    try:
        hermes_bin = shutil.which("hermes") or str(HERMES_HOME / "bin" / "hermes")
        if not Path(hermes_bin).exists():
            return None
        completed = subprocess.run(
            [hermes_bin, "--version"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        text = (completed.stdout or completed.stderr).strip()
        line = text.splitlines()[0] if text else ""
        match = re.search(r"Hermes Agent v(\d+(?:\.\d+)*)", line)
        if match:
            return match.group(1)
        match = re.search(r"\bv(\d+(?:\.\d+)+)\b", line)
        return match.group(1) if match else line.strip() or None
    except Exception:
        return None


def _installed_plugin_version() -> str | None:
    plugin_yaml = HERMES_HOME / "plugins" / PLUGIN_NAME / "plugin.yaml"
    if not plugin_yaml.is_file():
        return None
    return _plugin_version_from_src(plugin_yaml.parent)


def _read_env_lines(path: Path) -> list[str]:
    if not path.is_file():
        return []
    return path.read_text(encoding="utf-8").splitlines()


def _env_get(lines: list[str], key: str) -> str | None:
    prefix = f"{key}="
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix):]
    return None


def _plan_env_changes(lines: list[str], values: dict[str, str]) -> tuple[list[str], list[dict[str, str | None]]]:
    planned = list(lines)
    changes: list[dict[str, str | None]] = []
    for key, value in values.items():
        if not value:
            continue
        before = _env_get(planned, key)
        after = value
        if before == after:
            continue
        changes.append({"key": key, "before": before, "after": after})
        replaced = False
        for idx, line in enumerate(planned):
            if line.startswith(f"{key}="):
                planned[idx] = f"{key}={after}"
                replaced = True
                break
        if not replaced:
            planned.append(f"{key}={after}")
    return planned, changes


def _backup_paths(paths: list[Path], *, dry_run: bool) -> Path | None:
    existing = [path for path in paths if path.exists()]
    if not existing:
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_dir = HERMES_HOME / "backups" / f"dietcode-enable-{stamp}"
    if dry_run:
        return backup_dir
    backup_dir.mkdir(parents=True, exist_ok=True)
    for path in existing:
        dest = backup_dir / path.name
        if path.is_dir():
            shutil.copytree(path, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(path, dest)
    manifest = {
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "files": [str(path) for path in existing],
    }
    (backup_dir / "backup-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return backup_dir


def _run_bridge_verify(ctx: BundleContext) -> dict[str, Any]:
    if not ctx.bridge_cli or not ctx.app_path:
        return {"ok": False, "error": "bridge_cli_or_app_missing"}
    cmd: list[str]
    if ctx.bridge_cli.suffix == ".js":
        cmd = ["node", str(ctx.bridge_cli), "verify", "fast", "--compact", "--no-start", "--app", str(ctx.app_path)]
    else:
        cmd = [str(ctx.bridge_cli), "verify", "fast", "--compact", "--no-start", "--app", str(ctx.app_path)]
    completed = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=30)
    raw = (completed.stdout or completed.stderr).strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        payload = json.loads(line) if line else {"ok": False, "error": raw[:300]}
    except json.JSONDecodeError:
        payload = {"ok": False, "error": raw[:300]}
    payload["exit_code"] = completed.returncode
    return payload


def collect_versions(ctx: BundleContext) -> dict[str, Any]:
    hermes_version = _hermes_version()
    min_hermes = str(ctx.manifest.get("minHermesVersion") or "0.15.0")
    return {
        "bundleKind": ctx.manifest.get("bundleKind"),
        "summary": ctx.manifest.get("summary"),
        "runtimeVersion": {
            "bundled": ctx.manifest.get("runtimeVersion"),
            "observed": _runtime_version_from_bundle(ctx.app_bundle),
        },
        "bridgeVersion": {
            "bundled": ctx.manifest.get("bridgeVersion"),
            "observed": _bridge_version_from_bundle(ctx.app_bundle),
        },
        "pluginVersion": {
            "bundled": ctx.manifest.get("pluginVersion"),
            "source": _plugin_version_from_src(ctx.plugin_src),
            "installed": _installed_plugin_version(),
        },
        "hermesVersion": {
            "observed": hermes_version,
            "minimum": min_hermes,
            "compatible": hermes_version is None or _version_gte(hermes_version, min_hermes),
        },
        "schemaVersion": ctx.manifest.get("schemaVersion"),
        "contractVersion": ctx.manifest.get("contractVersion"),
    }


def cmd_doctor(ctx: BundleContext, *, compact: bool) -> int:
    log = ChangeLog(action="doctor", summary=ctx.manifest.get("summary", ""))
    log.versions = collect_versions(ctx)
    log.changed["resolution"] = {
        "appBundle": str(ctx.app_bundle) if ctx.app_bundle else None,
        "source": ctx.source_label,
        "pluginSrc": str(ctx.plugin_src),
        "bridgeCli": str(ctx.bridge_cli) if ctx.bridge_cli else None,
        "appPath": str(ctx.app_path) if ctx.app_path else None,
        "hermesHome": str(HERMES_HOME),
        "pluginInstalled": (HERMES_HOME / "plugins" / PLUGIN_NAME / "plugin.yaml").is_file(),
    }

    locations = [
        {"label": label, "path": str(path), "exists": _is_app_bundle(path)}
        for label, path in _app_bundle_locations()
    ]
    log.changed["appBundleCandidates"] = locations

    if not ctx.bridge_cli:
        log.ok = False
        log.errors.append("bridge_cli_missing")
    elif ctx.app_path:
        verify = _run_bridge_verify(ctx)
        log.changed["bridgeVerify"] = verify
        if not verify.get("ok"):
            log.ok = False
            log.errors.append("bridge_verify_failed")

    hermes = log.versions.get("hermesVersion", {})
    if hermes.get("observed") and not hermes.get("compatible"):
        log.ok = False
        log.errors.append("hermes_version_below_minimum")

    plugin = log.versions.get("pluginVersion", {})
    if plugin.get("installed") and plugin.get("bundled") and plugin["installed"] != plugin["bundled"]:
        log.changed["pluginDrift"] = {
            "installed": plugin.get("installed"),
            "bundled": plugin.get("bundled"),
        }

    _emit(log, compact=compact)
    return 0 if log.ok else 1


def cmd_dry_run(ctx: BundleContext, *, compact: bool) -> int:
    log = ChangeLog(action="dry-run", dry_run=True, summary="No changes written.")
    log.versions = collect_versions(ctx)
    dest = HERMES_HOME / "plugins" / PLUGIN_NAME
    env_path = HERMES_HOME / ".env"
    config_path = HERMES_HOME / "config.yaml"

    env_values = {
        "DIETCODE_IDE_ROOT": str(ctx.ide_root),
        "DIETCODE_REPO_ROOT": str(ctx.ide_root),
        "DIETCODE_APP_PATH": str(ctx.app_path or ""),
        "DIETCODE_APP_BUNDLE": str(ctx.app_bundle or ""),
        "DIETCODE_BRIDGE_CLI": str(ctx.bridge_cli or ""),
    }
    _, env_changes = _plan_env_changes(_read_env_lines(env_path), env_values)

    backup_targets = [dest, env_path, config_path]
    backup_dir = _backup_paths(backup_targets, dry_run=True)

    log.backup_dir = str(backup_dir) if backup_dir else None
    log.changed = {
        "wouldBackup": [str(path) for path in backup_targets if path.exists()],
        "wouldDeployPlugin": {
            "source": str(ctx.plugin_src),
            "dest": str(dest),
            "version": _plugin_version_from_src(ctx.plugin_src),
        },
        "wouldRunInstallPy": str(dest / "install.py"),
        "env": env_changes,
        "resolution": {
            "appBundle": str(ctx.app_bundle),
            "source": ctx.source_label,
        },
    }
    if not _hermes_version():
        log.changed["wouldInstallHermes"] = True

    _emit(log, compact=compact)
    return 0


def _deploy_plugin(ctx: BundleContext, *, dry_run: bool) -> dict[str, Any]:
    dest = HERMES_HOME / "plugins" / PLUGIN_NAME
    before_version = _installed_plugin_version()
    detail = {
        "source": str(ctx.plugin_src),
        "dest": str(dest),
        "beforeVersion": before_version,
        "afterVersion": _plugin_version_from_src(ctx.plugin_src),
    }
    if dry_run:
        detail["deployed"] = False
        return detail
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "rsync", "-a", "--delete",
            "--exclude", "broccolidb/node_modules",
            "--exclude", "broccolidb/scratch",
            "--exclude", "__pycache__",
            "--exclude", "*.pyc",
            f"{ctx.plugin_src}/",
            f"{dest}/",
        ],
        check=True,
    )
    detail["deployed"] = True
    return detail


def _run_install_py(ctx: BundleContext, *, dry_run: bool) -> dict[str, Any]:
    install_py = HERMES_HOME / "plugins" / PLUGIN_NAME / "install.py"
    if not install_py.is_file():
        return {"ok": False, "error": "install.py missing"}
    env = os.environ.copy()
    env.update({
        "HERMES_HOME": str(HERMES_HOME),
        "DIETCODE_IDE_ROOT": str(ctx.ide_root),
        "DIETCODE_REPO_ROOT": str(ctx.ide_root),
        "DIETCODE_APP_PATH": str(ctx.app_path or ""),
        "DIETCODE_APP_BUNDLE": str(ctx.app_bundle or ""),
        "DIETCODE_BRIDGE_CLI": str(ctx.bridge_cli or ""),
    })
    args = [sys.executable, str(install_py)]
    if dry_run:
        args.append("--dry-run")
    completed = subprocess.run(args, capture_output=True, text=True, check=False, env=env, timeout=180)
    raw = completed.stdout.strip() or completed.stderr.strip()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        payload = {"ok": completed.returncode == 0, "raw": raw[:500]}
    payload["exit_code"] = completed.returncode
    return payload


def _apply_env(ctx: BundleContext, *, dry_run: bool) -> list[dict[str, str | None]]:
    env_path = HERMES_HOME / ".env"
    values = {
        "DIETCODE_IDE_ROOT": str(ctx.ide_root),
        "DIETCODE_REPO_ROOT": str(ctx.ide_root),
        "DIETCODE_APP_PATH": str(ctx.app_path or ""),
        "DIETCODE_APP_BUNDLE": str(ctx.app_bundle or ""),
        "DIETCODE_BRIDGE_CLI": str(ctx.bridge_cli or ""),
    }
    planned, changes = _plan_env_changes(_read_env_lines(env_path), values)
    if changes and not dry_run:
        env_path.parent.mkdir(parents=True, exist_ok=True)
        env_path.write_text("\n".join(planned) + ("\n" if planned else ""), encoding="utf-8")
    return changes


def cmd_enable(ctx: BundleContext, *, compact: bool, install_hermes: bool) -> int:
    log = ChangeLog(action="enable", summary=ctx.manifest.get("summary", ""))
    log.versions = collect_versions(ctx)

    dest = HERMES_HOME / "plugins" / PLUGIN_NAME
    backup_dir = _backup_paths([dest, HERMES_HOME / ".env", HERMES_HOME / "config.yaml"], dry_run=False)
    log.backup_dir = str(backup_dir) if backup_dir else None

    if install_hermes and not _hermes_version():
        log.changed["hermesInstall"] = {"started": True}
        subprocess.run(
            ["bash", "-c", "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup"],
            check=True,
        )
        log.changed["hermesInstall"]["completed"] = True
        log.versions = collect_versions(ctx)

    log.changed["plugin"] = _deploy_plugin(ctx, dry_run=False)
    install_result = _run_install_py(ctx, dry_run=False)
    log.changed["installPy"] = install_result
    log.changed["env"] = _apply_env(ctx, dry_run=False)

    if ctx.app_path and ctx.app_path.is_file():
        subprocess.run([str(ctx.app_path), "--ensure-socket", "--ensure-timeout", "15"], check=False)
        log.changed["socket"] = {"ensured": True}

    if ctx.bridge_cli and ctx.app_path:
        log.changed["bridgeVerify"] = _run_bridge_verify(ctx)

    if install_result.get("exit_code", 1) != 0:
        log.ok = False
        log.errors.append("install_py_failed")

    _emit(log, compact=compact)
    return 0 if log.ok else 1


def cmd_uninstall(ctx: BundleContext, *, compact: bool) -> int:
    log = ChangeLog(action="uninstall", summary="Removed DietCode Hermes integration artifacts.")
    dest = HERMES_HOME / "plugins" / PLUGIN_NAME
    env_path = HERMES_HOME / ".env"
    marker = dest / ".dietcode-ide-connected"

    backup_dir = _backup_paths([dest, env_path, HERMES_HOME / "config.yaml"], dry_run=False)
    log.backup_dir = str(backup_dir) if backup_dir else None

    removed: list[str] = []
    if dest.exists():
        shutil.rmtree(dest)
        removed.append(str(dest))
    if marker.exists():
        marker.unlink()
        removed.append(str(marker))

    env_lines = _read_env_lines(env_path)
    env_changes: list[dict[str, str | None]] = []
    kept: list[str] = []
    for line in env_lines:
        if any(line.startswith(f"{key}=") for key in ENV_KEYS):
            key = line.split("=", 1)[0]
            env_changes.append({"key": key, "before": line.split("=", 1)[1], "after": None})
            continue
        kept.append(line)
    if env_changes:
        env_path.write_text("\n".join(kept) + ("\n" if kept else ""), encoding="utf-8")

    log.changed = {
        "removed": removed,
        "env": env_changes,
        "note": "Hermes itself was not removed. Config.yaml was backed up but not auto-reverted.",
    }
    _emit(log, compact=compact)
    return 0


def _emit(log: ChangeLog, *, compact: bool) -> None:
    payload = log.to_dict()
    if compact:
        print(json.dumps(payload))
    else:
        print(json.dumps(payload, indent=2))
        print()
        print(log.summary or "DietCode agent integration")
        if log.backup_dir:
            print(f"Backup: {log.backup_dir}")
        if log.changed.get("env"):
            print("Env changes:")
            for item in log.changed["env"]:
                print(f"  {item['key']}: {item.get('before')!r} -> {item.get('after')!r}")
        if log.changed.get("plugin"):
            plugin = log.changed["plugin"]
            print(f"Plugin: {plugin.get('beforeVersion')} -> {plugin.get('afterVersion')} ({plugin.get('source')})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="DietCode bundled agent integration — trust + update safety.")
    parser.add_argument("--app-bundle", help="Explicit DietCode.app path")
    parser.add_argument("--compact", action="store_true", help="Emit NDJSON summary only")
    parser.add_argument("--dry-run", action="store_true", help="Show planned changes without writing")
    parser.add_argument("--doctor", action="store_true", help="Diagnose bundle resolution and versions")
    parser.add_argument("--uninstall", action="store_true", help="Remove DietCode plugin + env wiring")
    parser.add_argument("--skip-hermes-install", action="store_true", help="Do not lazy-install Hermes")
    args = parser.parse_args(argv)

    invoked = Path(argv[0]) if argv else Path(sys.argv[0])
    ctx = resolve_context(app_bundle_arg=args.app_bundle, invoked_path=invoked)

    if args.doctor:
        return cmd_doctor(ctx, compact=args.compact)
    if args.dry_run:
        return cmd_dry_run(ctx, compact=args.compact)
    if args.uninstall:
        return cmd_uninstall(ctx, compact=args.compact)
    return cmd_enable(ctx, compact=args.compact, install_hermes=not args.skip_hermes_install)


if __name__ == "__main__":
    raise SystemExit(main())
