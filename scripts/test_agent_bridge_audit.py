#!/usr/bin/env python3
"""
AUDIT: Agent bridge production hardening checks — docs, packaging, API surface.

Grep: rg 'test_agent_bridge_audit|agent_bridge_audit' scripts/ Makefile
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from agent_test_support import CheckRecorder, add_output_args, output_compact

REPO_ROOT = Path(__file__).resolve().parents[1]
BRIDGE = REPO_ROOT / "agent-bridge"
DOCS = REPO_ROOT / "docs" / "agent-bridge.md"
PACKAGED = (
    REPO_ROOT
    / "build"
    / "DietCode.app"
    / "Contents"
    / "Resources"
    / "agent-bridge"
    / "dist"
    / "index.js"
)
LAUNCHER = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "Resources" / "bin" / "dietcode-agent-client"

PUBLIC_METHODS = (
    "connect",
    "getRuntimeProfile",
    "getDiagnostics",
    "searchLiteral",
    "searchTokens",
    "searchPaths",
    "getFileStat",
    "safePatchFile",
    "safePatchBatch",
    "getOperationStatus",
    "getTimeline",
    "getRecentActivity",
    "verifyFast",
)


def test_docs_list_public_api() -> None:
    text = DOCS.read_text(encoding="utf-8")
    for method in PUBLIC_METHODS:
        assert method in text, f"agent-bridge.md missing public method {method}"


def test_docs_forbid_raw_rpc() -> None:
    text = DOCS.read_text(encoding="utf-8")
    assert "should not call raw DietCode RPC" in text or "Do not" in text
    assert "patch.apply" in text


def test_client_exports_no_mock_transport() -> None:
    index = (BRIDGE / "src" / "index.ts").read_text(encoding="utf-8")
    assert "MockRpcTransport" not in index, "MockRpcTransport must not be in public index"


def test_testing_subpath_exists() -> None:
    package = json.loads((BRIDGE / "package.json").read_text(encoding="utf-8"))
    exports = package.get("exports", {})
    assert "./testing" in exports


def test_makefile_has_bridge_targets() -> None:
    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    for target in ("test-agent-bridge", "test-agent-bridge-fast", "agent-bridge-fast"):
        assert re.search(rf"^{re.escape(target)}:", makefile, re.MULTILINE), f"missing {target}"


def test_bridge_has_throwable_error_class() -> None:
    source = (BRIDGE / "src" / "contracts" / "BridgeError.ts").read_text(encoding="utf-8")
    assert "class DietCodeBridgeError extends Error" in source


def test_rpc_transport_serializes_calls() -> None:
    source = (BRIDGE / "src" / "client" / "RpcTransport.ts").read_text(encoding="utf-8")
    assert "callChain" in source
    assert "readJsonFrame" in source


def test_offline_bridge_tests_pass() -> None:
    completed = subprocess.run(
        ["make", "test-agent-bridge-fast"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr[-500:]


def test_packaged_artifact_exists() -> None:
    assert PACKAGED.is_file(), f"missing packaged bridge {PACKAGED}"
    assert LAUNCHER.is_file(), f"missing launcher {LAUNCHER}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent bridge audit harness.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    checks = [
        ("audit.docs_public_api", test_docs_list_public_api),
        ("audit.docs_forbid_raw_rpc", test_docs_forbid_raw_rpc),
        ("audit.no_mock_in_public_index", test_client_exports_no_mock_transport),
        ("audit.testing_subpath", test_testing_subpath_exists),
        ("audit.makefile_targets", test_makefile_has_bridge_targets),
        ("audit.throwable_error_class", test_bridge_has_throwable_error_class),
        ("audit.rpc_transport_serialization", test_rpc_transport_serializes_calls),
        ("audit.offline_tests", test_offline_bridge_tests_pass),
        ("audit.packaged_artifact", test_packaged_artifact_exists),
    ]

    for name, fn in checks:
        recorder.run(name, fn)

    return recorder.finish("agent_bridge_audit")


if __name__ == "__main__":
    raise SystemExit(main())
