#!/usr/bin/env python3
"""
RELEASE: Release readiness regression — versions, stability labels, docs, fixtures.

Grep: rg 'test_release_readiness|release-check-agent-runtime' scripts/ docs/
"""

from __future__ import annotations

import argparse
import json
import re
from collections.abc import Callable
from pathlib import Path

from agent_contracts import REQUIRED_MAKE_TARGETS
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import REPO_ROOT, SCHEMA_VERSION, connect, load_token, send_rpc
from release_versions import (
    CONTRACT_INVENTORY_VERSION,
    RUNTIME_VERSIONS,
    STABILITY_LABELS,
    assert_versions_synced,
    load_surface_classification,
    runtime_versions_payload,
)

DOCS = {
    "testing": REPO_ROOT / "docs/testing.md",
    "checkpoint_model": REPO_ROOT / "docs/checkpoint-model.md",
    "getting_started": REPO_ROOT / "docs/getting-started.md",
}


def test_versions_synced() -> None:
    assert_versions_synced()
    assert SCHEMA_VERSION == RUNTIME_VERSIONS["clientSchema"]


def test_runtime_versions_payload() -> None:
    payload = runtime_versions_payload()
    assert "contractVersions" in payload
    versions = payload["contractVersions"]
    assert versions["contractInventory"] == CONTRACT_INVENTORY_VERSION
    assert versions["harnessSummary"] == "1.0"


def test_surface_classification_labels() -> None:
    data = load_surface_classification()
    assert data.get("version")
    for section in ("cli_flags", "rpc_methods", "envelope_keys", "makefile_targets", "fixtures"):
        block = data[section]
        for label in STABILITY_LABELS:
            assert label in block, f"{section} missing label {label}"
            assert isinstance(block[label], list)


def test_stable_makefile_targets_exist() -> None:
    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    stable = load_surface_classification()["makefile_targets"]["stable"]
    for target in stable:
        assert re.search(rf"^{re.escape(target)}:", makefile, re.MULTILINE), f"missing target {target}"


def test_stable_fixtures_exist() -> None:
    for rel in load_surface_classification()["fixtures"]["stable"]:
        path = REPO_ROOT / rel
        assert path.is_file(), f"missing fixture {rel}"


def test_release_docs_present() -> None:
    for name, path in DOCS.items():
        assert path.is_file(), f"missing doc: {name} ({path})"


def test_testing_doc_mentions_release() -> None:
    text = DOCS["testing"].read_text(encoding="utf-8")
    assert "checkpoint-core" in text
    assert "verify-agent-runtime-full" in text or "release-check-agent-runtime" in text


def test_emit_config_has_versions() -> None:
    client = (REPO_ROOT / "scripts/dietcode_agent_client.py").read_text(encoding="utf-8")
    assert "runtime_versions_payload" in client
    payload = runtime_versions_payload()
    assert "contractVersions" in payload


def test_release_target_in_contracts() -> None:
    assert "release-check-agent-runtime" in REQUIRED_MAKE_TARGETS


def test_rpc_version_contracts(sock, token: str) -> None:
    response = send_rpc(sock, token, "rpc.version", request_id="release-rpc-version")
    assert response.get("ok") is True
    result = response["result"]
    assert "contractVersions" in result
    versions = result["contractVersions"]
    assert versions["contractInventory"] == CONTRACT_INVENTORY_VERSION
    assert versions["controlProtocol"] == RUNTIME_VERSIONS["controlProtocol"]


def test_rpc_describe_contracts(sock, token: str) -> None:
    response = send_rpc(sock, token, "rpc.describe", {"method": "rpc.ping"}, request_id="release-rpc-describe")
    assert response.get("ok") is True
    assert "contractVersions" in response["result"]
    assert response["result"]["contractVersions"]["rpcEnvelope"] == RUNTIME_VERSIONS["rpcEnvelope"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Release readiness regression suite.")
    add_output_args(parser)
    parser.add_argument("--offline-only", action="store_true", help="Skip live-server RPC version checks.")
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    offline: list[tuple[str, Callable[[], None]]] = [
        ("release.versions_synced", test_versions_synced),
        ("release.versions_payload", test_runtime_versions_payload),
        ("release.surface_classification", test_surface_classification_labels),
        ("release.stable_makefile_targets", test_stable_makefile_targets_exist),
        ("release.stable_fixtures", test_stable_fixtures_exist),
        ("release.docs_present", test_release_docs_present),
        ("release.testing_doc", test_testing_doc_mentions_release),
        ("release.emit_config_versions", test_emit_config_has_versions),
        ("release.makefile_target_registered", test_release_target_in_contracts),
    ]
    for name, fn in offline:
        recorder.run(name, fn)

    if not args.offline_only:
        token = load_token()
        live: list[tuple[str, Callable]] = [
            ("release.rpc_version_contracts", test_rpc_version_contracts),
            ("release.rpc_describe_contracts", test_rpc_describe_contracts),
        ]
        for name, fn in live:
            def _run(f: Callable = fn) -> None:
                sock = connect(start=False)
                try:
                    f(sock, token)
                finally:
                    sock.close()

            recorder.run(name, _run)

    return recorder.finish("release_readiness")


if __name__ == "__main__":
    raise SystemExit(main())
