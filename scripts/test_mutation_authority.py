#!/usr/bin/env python3
"""Regression tests for mutation authority audit and sidebar labels."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
SIDEBAR_MM = REPO_ROOT / "src/platform/macos/MacAgentSidebar.mm"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


mutation = _load_module("dietcode_mutation_authority", SCRIPTS / "dietcode_mutation_authority.py")
chat = _load_module("dietcode_agent_chat", SCRIPTS / "dietcode_agent_chat.py")
bundle = _load_module("dietcode_agent_bundle", SCRIPTS / "dietcode_agent_bundle.py")


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
                    "tool": "dietcode_ide.patch",
                    "protocol": "safePatchFile",
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
                    "tool": "dietcode_ide.patch",
                    "protocol": "safePatchFile",
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

    def test_enforce_mutation_authority_exits_on_violation(self) -> None:
        build_bundle = REPO_ROOT / "build" / "DietCode.app"
        if not build_bundle.is_dir():
            self.skipTest("build/DietCode.app missing")
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            ctx = bundle.resolve_context(repo_root=REPO_ROOT, app_bundle_arg=str(build_bundle))
            status = {
                "runtime": {"ready": True},
                "bridge": {"ready": True},
                "hermes": {"ready": True},
                "workspaceAuthority": {"workspaceMatch": True},
            }
            with mock.patch.object(chat, "assert_chat_ready", return_value=status):
                with mock.patch.object(chat, "run_hermes_chat", return_value=(0, "done")):
                    with mock.patch.object(chat, "collect_bridge_patch_events", return_value=[]):
                        with mock.patch.object(chat, "workspace_manifest") as manifest_mock:
                            manifest_mock.side_effect = [{}, {"edited.py": "hash"}]
                            code = chat.cmd_chat(
                                REPO_ROOT,
                                ctx,
                                workspace=ws,
                                prompt="edit",
                                fmt="json",
                                max_turns=5,
                                enforce_mutation_authority=True,
                            )
            self.assertEqual(code, 11)


class SidebarMutationAuthorityTests(unittest.TestCase):
    def test_mutation_authority_labels(self) -> None:
        self.assertEqual(mutation.mutation_authority_label("bridge_only"), "Bridge verified")
        self.assertEqual(mutation.mutation_authority_label("no_mutation"), "No mutation")
        self.assertEqual(mutation.mutation_authority_label("unknown"), "Unknown — review run")
        self.assertEqual(mutation.mutation_authority_label("violated"), "Violation — agent disabled")

    def test_sidebar_mutation_authority_status(self) -> None:
        text = SIDEBAR_MM.read_text(encoding="utf-8") if SIDEBAR_MM.is_file() else ""
        self.assertIn("Mutation path:", text)
        self.assertIn("Bridge verified", text)
        self.assertIn("No mutation", text)
        self.assertIn("Unknown", text)
        self.assertIn("Violation", text)
        self.assertIn("mutationAuthority", text)

    def test_doctor_payload_shape_includes_mutation_authority(self) -> None:
        authority = mutation.empty_mutation_authority()
        self.assertIn("mode", authority)
        self.assertIn("bridgePatchCount", authority)
        self.assertIn("rawWriteSuspected", authority)
        self.assertIn("mutatedFiles", authority)
        self.assertIn("evidence", authority)


if __name__ == "__main__":
    unittest.main()
