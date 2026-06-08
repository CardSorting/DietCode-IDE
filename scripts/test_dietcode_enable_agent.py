#!/usr/bin/env python3
"""Audit: installed-app trust + update safety for dietcode-enable-agent."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ENABLE_PY = REPO_ROOT / "scripts" / "dietcode_enable_agent.py"
ENABLE_BIN = REPO_ROOT / "resources" / "bin" / "dietcode-enable-agent"
BUILD_BUNDLE = REPO_ROOT / "build" / "DietCode.app"
BUNDLED_ENABLE = BUILD_BUNDLE / "Contents" / "Resources" / "bin" / "dietcode-enable-agent"
BUNDLED_PY = BUILD_BUNDLE / "Contents" / "Resources" / "bin" / "dietcode-enable-agent.py"
MANIFEST = REPO_ROOT / "resources" / "dietcode-agent-bundle.manifest.json"
BUNDLED_MANIFEST = BUILD_BUNDLE / "Contents" / "Resources" / "dietcode-agent-bundle.manifest.json"


def _load_module():
    spec = importlib.util.spec_from_file_location("dietcode_enable_agent", ENABLE_PY)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


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


def test_files_exist(rec: Recorder) -> None:
    rec.record("trust.enable_py", ENABLE_PY.is_file())
    rec.record("trust.enable_bin", ENABLE_BIN.is_file())
    rec.record("trust.manifest", MANIFEST.is_file())


def test_manifest_sentence(rec: Recorder) -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    rec.record("trust.bundle_kind", data.get("bundleKind") == "agent-integration-artifact")
    rec.record(
        "trust.summary_sentence",
        "bundled agent integration artifact" in str(data.get("summary", "")).lower(),
        str(data.get("summary")),
    )
    for key in ("runtimeVersion", "bridgeVersion", "pluginVersion", "minHermesVersion"):
        rec.record(f"trust.version.{key}", bool(data.get(key)), str(data.get(key)))


def test_bundle_locations(rec: Recorder) -> None:
    mod = _load_module()
    labels = {label for label, _ in mod._app_bundle_locations()}
    rec.record("trust.candidate.build", "build" in labels)
    rec.record("trust.candidate.system", "system" in labels)
    rec.record("trust.candidate.user", "user" in labels)


def test_resolve_build_bundle(rec: Recorder) -> None:
    if not BUILD_BUNDLE.is_dir():
        rec.record("trust.resolve.build", False, "build bundle missing — run make app")
        return
    mod = _load_module()
    ctx = mod.resolve_context(app_bundle_arg=str(BUILD_BUNDLE))
    rec.record("trust.resolve.build", ctx.app_bundle == BUILD_BUNDLE.resolve())
    rec.record("trust.resolve.plugin_src", (ctx.plugin_src / "plugin.yaml").is_file())


def test_cli_dry_run(rec: Recorder) -> None:
    if not BUILD_BUNDLE.is_dir():
        rec.record("trust.cli.dry_run", False, "build bundle missing")
        return
    completed = subprocess.run(
        [sys.executable, str(ENABLE_PY), "--dry-run", "--compact", "--app-bundle", str(BUILD_BUNDLE), "--skip-hermes-install"],
        capture_output=True,
        text=True,
        check=False,
    )
    ok = completed.returncode == 0
    detail = completed.stdout.strip() or completed.stderr.strip()
    if ok:
        payload = json.loads(detail)
        ok = payload.get("action") == "dry-run" and payload.get("dryRun") is True
        ok = ok and bool(payload.get("changed", {}).get("wouldDeployPlugin"))
    rec.record("trust.cli.dry_run", ok, detail[:400])


def test_cli_doctor(rec: Recorder) -> None:
    if not BUILD_BUNDLE.is_dir():
        rec.record("trust.cli.doctor", False, "build bundle missing")
        return
    completed = subprocess.run(
        [sys.executable, str(ENABLE_PY), "--doctor", "--compact", "--app-bundle", str(BUILD_BUNDLE)],
        capture_output=True,
        text=True,
        check=False,
    )
    detail = completed.stdout.strip() or completed.stderr.strip()
    ok = completed.returncode == 0
    if detail:
        payload = json.loads(detail)
        ok = ok and payload.get("action") == "doctor"
        ok = ok and "runtimeVersion" in payload.get("versions", {})
        ok = ok and "bundled agent integration artifact" in str(payload.get("summary", "")).lower()
    rec.record("trust.cli.doctor", ok, detail[:400])


def test_install_py_dry_run(rec: Recorder) -> None:
    plugin_install = REPO_ROOT / "integrations" / "hermes-dietcode-plugin" / "install.py"
    if not plugin_install.is_file():
        rec.record("trust.install_py_dry_run", False, "plugin missing")
        return
    completed = subprocess.run(
        [sys.executable, str(plugin_install), "--dry-run"],
        capture_output=True,
        text=True,
        check=False,
    )
    ok = completed.returncode == 0
    detail = completed.stdout.strip()
    if ok:
        payload = json.loads(detail)
        ok = payload.get("dry_run") is True
    rec.record("trust.install_py_dry_run", ok, detail[:300])


def test_backup_planning(rec: Recorder) -> None:
    mod = _load_module()
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp) / "config.yaml"
        fake.write_text("toolsets: []\n", encoding="utf-8")
        backup = mod._backup_paths([fake], dry_run=True)
        rec.record("trust.backup.dry_run_path", backup is not None and "dietcode-enable-" in str(backup))


def test_bundled_artifacts(rec: Recorder) -> None:
    rec.record("trust.bundled.enable_bin", BUNDLED_ENABLE.is_file(), str(BUNDLED_ENABLE))
    rec.record("trust.bundled.enable_py", BUNDLED_PY.is_file(), str(BUNDLED_PY))
    rec.record("trust.bundled.manifest", BUNDLED_MANIFEST.is_file(), str(BUNDLED_MANIFEST))


def main() -> int:
    rec = Recorder()
    test_files_exist(rec)
    test_manifest_sentence(rec)
    test_bundle_locations(rec)
    test_resolve_build_bundle(rec)
    test_cli_dry_run(rec)
    test_cli_doctor(rec)
    test_install_py_dry_run(rec)
    test_backup_planning(rec)
    test_bundled_artifacts(rec)
    return rec.finish("dietcode_enable_agent_trust")


if __name__ == "__main__":
    raise SystemExit(main())
