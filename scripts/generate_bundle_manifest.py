#!/usr/bin/env python3
"""Regenerate dietcode-agent-bundle.manifest.json from repo version sources."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "resources" / "dietcode-agent-bundle.manifest.json"
INFO_PLIST = REPO_ROOT / "resources" / "Info.plist"
BRIDGE_PACKAGE = REPO_ROOT / "agent-bridge" / "package.json"
PLUGIN_YAML = REPO_ROOT / "integrations" / "hermes-dietcode-plugin" / "plugin.yaml"


def _read_runtime_version() -> str:
    with INFO_PLIST.open("rb") as fh:
        plist = plistlib.load(fh)
    return str(plist.get("CFBundleShortVersionString") or "unknown")


def _read_json_version(path: Path) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    return str(data.get("version") or "unknown")


def _read_plugin_version() -> str:
    text = PLUGIN_YAML.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^\s#]+)", text, re.MULTILINE)
    return match.group(1) if match else "unknown"


def build_manifest() -> dict[str, str]:
    existing = {}
    if MANIFEST_PATH.is_file():
        existing = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    return {
        "bundleKind": "agent-integration-artifact",
        "summary": "DietCode now ships a bundled agent integration artifact, not merely a benchmark bridge.",
        "runtimeVersion": _read_runtime_version(),
        "bridgeVersion": _read_json_version(BRIDGE_PACKAGE),
        "pluginVersion": _read_plugin_version(),
        "minHermesVersion": str(existing.get("minHermesVersion") or "0.15.0"),
        "schemaVersion": str(existing.get("schemaVersion") or "1.6.2"),
        "contractVersion": str(existing.get("contractVersion") or "1.0.0"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output", type=Path, default=MANIFEST_PATH)
    args = parser.parse_args()
    manifest = build_manifest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
