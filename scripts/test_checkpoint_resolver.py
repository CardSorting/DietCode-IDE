#!/usr/bin/env python3
"""Parity smoke tests for verify command resolution (bridge mirrors Python authority)."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))

from dietcode_verification_authority import resolve_verify_command  # noqa: E402


def resolve_like_bridge(workspace: Path, override: str | None = None) -> str | None:
    """Mirror cockpit/server/verifyCommandResolver.ts resolution order."""
    if override and override.strip():
        return override.strip()
    cmd = resolve_verify_command(workspace)
    if cmd:
        return cmd
    pkg = workspace / "package.json"
    if pkg.is_file():
        try:
            data = json.loads(pkg.read_text(encoding="utf-8"))
            scripts = data.get("scripts") or {}
            if scripts.get("test"):
                return "npm test"
            if scripts.get("verify"):
                return "npm run verify"
        except json.JSONDecodeError:
            pass
    return None


def main() -> int:
    errors: list[str] = []

    with tempfile.TemporaryDirectory() as tmp:
        ws = Path(tmp)
        (ws / "verify.sh").write_text("#!/bin/sh\ntrue\n", encoding="utf-8")
        if resolve_like_bridge(ws) != "./verify.sh":
            errors.append("verify.sh")

        (ws / "verify.sh").unlink()
        (ws / "package.json").write_text(json.dumps({"scripts": {"test": "vitest"}}), encoding="utf-8")
        if resolve_like_bridge(ws) != "npm test":
            errors.append("npm test")

    if resolve_like_bridge(REPO, "./custom.sh") != "./custom.sh":
        errors.append("override")

    if errors:
        for err in errors:
            print(f"FAIL: {err}", file=sys.stderr)
        return 1

    print("checkpoint resolver smoke: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
