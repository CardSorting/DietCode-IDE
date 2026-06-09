#!/usr/bin/env python3
"""Regression tests for mutation authority audit helpers."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


mutation = _load_module("dietcode_mutation_authority", SCRIPTS / "dietcode_mutation_authority.py")


class MutationAuthorityAuditTests(unittest.TestCase):
    def test_mutation_authority_no_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "unchanged.py").write_text("x = 1\n", encoding="utf-8")
            manifest = mutation.workspace_manifest(ws)
            report = mutation.audit_mutation_authority(
                ws,
                before_manifest=manifest,
                after_manifest=manifest,
                bridge_events=[],
            )
            self.assertEqual(report["mode"], "no_mutation")
            self.assertEqual(report["bridgePatchCount"], 0)
            self.assertFalse(report["rawWriteSuspected"])
            self.assertEqual(report["mutatedFiles"], [])

    def test_mutation_authority_bridge_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            rel = "src/foo.py"
            before = {rel: "aaa"}
            after = {rel: "bbb"}
            events = [
                {
                    "eventType": "mutation.patch.applied",
                    "workspace": str(ws),
                    "path": rel,
                    "beforeHash": "aaa",
                    "afterHash": "bbb",
                    "tool": "patch.apply",
                    "protocol": "kernel_rpc",
                }
            ]
            report = mutation.audit_mutation_authority(
                ws,
                before_manifest=before,
                after_manifest=after,
                bridge_events=events,
            )
            self.assertEqual(report["mode"], "bridge_only")
            self.assertEqual(report["bridgePatchCount"], 1)
            self.assertFalse(report["rawWriteSuspected"])
            self.assertEqual(report["mutatedFiles"], [rel])

    def test_mutation_authority_unknown_or_violated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            rel = "secret.py"
            before: dict[str, str] = {}
            after = {rel: "hash"}
            report = mutation.audit_mutation_authority(
                ws,
                before_manifest=before,
                after_manifest=after,
                bridge_events=[],
                transcript="write_file(path, content)",
            )
            self.assertEqual(report["mode"], "violated")
            self.assertTrue(report["rawWriteSuspected"])
            self.assertGreaterEqual(len(report["evidence"]), 1)

    def test_mutation_authority_path_escape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            events = [
                {
                    "eventType": "mutation.patch.applied",
                    "workspace": str(ws),
                    "path": "/etc/passwd",
                    "beforeHash": "a",
                    "afterHash": "b",
                    "tool": "patch.apply",
                    "protocol": "kernel_rpc",
                }
            ]
            report = mutation.audit_mutation_authority(
                ws,
                before_manifest={},
                after_manifest={"etc.txt": "x"},
                bridge_events=events,
            )
            self.assertEqual(report["mode"], "violated")
            self.assertTrue(any("bridge_path_outside_workspace" in item for item in report["evidence"]))


class MutationAuthorityCollectTests(unittest.TestCase):
    def test_collect_patch_events_from_log_only(self) -> None:
        import json

        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            log = ws / "events.jsonl"
            event = {
                "eventType": "mutation.patch.applied",
                "workspace": str(ws),
                "path": "src/foo.py",
                "beforeHash": "aaa",
                "afterHash": "bbb",
                "tool": "patch.apply",
                "protocol": "kernel_rpc",
            }
            log.write_text(json.dumps(event) + "\n", encoding="utf-8")
            events = mutation.collect_bridge_patch_events(None, ws, log)
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0]["path"], "src/foo.py")


class MutationAuthorityLabelTests(unittest.TestCase):
    def test_mutation_authority_labels(self) -> None:
        self.assertEqual(mutation.mutation_authority_label("bridge_only"), "Bridge verified")
        self.assertEqual(mutation.mutation_authority_label("no_mutation"), "No mutation")
        self.assertEqual(mutation.mutation_authority_label("unknown"), "Unknown — review run")
        self.assertEqual(mutation.mutation_authority_label("violated"), "Violation — agent disabled")

    def test_doctor_payload_shape_includes_mutation_authority(self) -> None:
        authority = mutation.empty_mutation_authority()
        self.assertIn("mode", authority)
        self.assertIn("bridgePatchCount", authority)
        self.assertIn("rawWriteSuspected", authority)
        self.assertIn("mutatedFiles", authority)
        self.assertIn("evidence", authority)


if __name__ == "__main__":
    unittest.main()
