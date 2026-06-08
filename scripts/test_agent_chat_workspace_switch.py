#!/usr/bin/env python3
"""Regression: runtime must switch to requested workspace (authority drift guard)."""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from dietcode_agent_bundle import (  # noqa: E402
    bridge_search_literal,
    observe_runtime_workspace,
    open_runtime_workspace,
    repo_root_from_script,
    resolve_context,
    workspace_authority_report,
)

APP_BUNDLE = REPO_ROOT / "build" / "DietCode.app"
MARKER_A = "workspace_switch_marker_a.txt"
MARKER_B = "workspace_switch_marker_b_only.txt"


class WorkspaceSwitchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not APP_BUNDLE.is_dir():
            raise unittest.SkipTest("build/DietCode.app missing — run make app")
        cls.ctx = resolve_context(
            repo_root=REPO_ROOT,
            app_bundle_arg=str(APP_BUNDLE),
            invoked_path=SCRIPTS / "dietcode_agent_chat.py",
        )
        if not cls.ctx.app_path or not cls.ctx.bridge_cli:
            raise unittest.SkipTest("bundled runtime or bridge CLI missing")

    def setUp(self) -> None:
        self.workspace_a = REPO_ROOT
        self.temp_dir = tempfile.mkdtemp(prefix="dietcode-workspace-switch-")
        self.workspace_b = Path(self.temp_dir)
        (self.workspace_a / MARKER_A).write_text("marker-a\n", encoding="utf-8")
        (self.workspace_b / MARKER_B).write_text("marker-b-only\n", encoding="utf-8")

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        marker_a = self.workspace_a / MARKER_A
        if marker_a.is_file():
            marker_a.unlink()

    def test_runtime_switches_from_a_to_b(self) -> None:
        opened_a = open_runtime_workspace(self.ctx, self.workspace_a)
        self.assertTrue(opened_a.get("ok"), opened_a)
        before = observe_runtime_workspace(self.ctx)
        self.assertEqual(before, str(self.workspace_a.resolve()))

        authority = workspace_authority_report(self.ctx, self.workspace_b)
        self.assertTrue(authority["workspaceSwitchSucceeded"], authority)
        self.assertTrue(authority["workspaceMatch"], authority)
        self.assertEqual(authority["requestedWorkspace"], str(self.workspace_b.resolve()))
        self.assertEqual(authority["runtimeWorkspaceBefore"], str(self.workspace_a.resolve()))
        self.assertEqual(authority["runtimeWorkspaceAfter"], str(self.workspace_b.resolve()))
        self.assertEqual(authority["workspaceRootObserved"], str(self.workspace_b.resolve()))

        observed = observe_runtime_workspace(self.ctx)
        self.assertEqual(observed, str(self.workspace_b.resolve()))
        self.assertNotEqual(observed, str(self.workspace_a.resolve()))

    def test_bridge_search_sees_b_not_a_marker(self) -> None:
        open_runtime_workspace(self.ctx, self.workspace_a)
        workspace_authority_report(self.ctx, self.workspace_b)

        b_search = bridge_search_literal(self.ctx, self.workspace_b, "marker-b-only")
        self.assertTrue(b_search.get("ok") is not False, b_search)
        result = b_search.get("result") if isinstance(b_search.get("result"), dict) else b_search
        hits = result.get("results") if isinstance(result, dict) else []
        self.assertTrue(
            any(isinstance(item, dict) and MARKER_B in str(item.get("path") or "") for item in hits),
            json.dumps(b_search)[:500],
        )

        a_search = bridge_search_literal(self.ctx, self.workspace_b, "marker-a")
        result_a = a_search.get("result") if isinstance(a_search.get("result"), dict) else a_search
        hits_a = result_a.get("results") if isinstance(result_a, dict) else []
        self.assertFalse(
            any(isinstance(item, dict) and MARKER_A in str(item.get("path") or "") for item in hits_a),
            "workspace B search must not see workspace A marker",
        )

    def test_doctor_json_includes_workspace_authority(self) -> None:
        import dietcode_agent_chat as chat

        open_runtime_workspace(self.ctx, self.workspace_a)
        code = chat.cmd_doctor(
            REPO_ROOT,
            self.ctx,
            fmt="json",
            workspace=self.workspace_b,
        )
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
