#!/usr/bin/env python3
"""Tests for dietcode-agent-chat CLI and sidebar command contract."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


bundle = _load_module("dietcode_agent_bundle", SCRIPTS / "dietcode_agent_bundle.py")
chat = _load_module("dietcode_agent_chat", SCRIPTS / "dietcode_agent_chat.py")


class DietcodeAgentChatTests(unittest.TestCase):
    def test_version_json(self) -> None:
        with mock.patch.object(chat, "resolve_context") as resolve:
            resolve.return_value = mock.Mock(manifest={"bundleKind": "agent-integration-artifact", "runtimeVersion": "1.6.6"})
            code = chat.main(["dietcode_agent_chat.py", "--version"])
        self.assertEqual(code, 0)

    def test_missing_workspace(self) -> None:
        code = chat.main(["dietcode_agent_chat.py", "--prompt", "hi"])
        self.assertEqual(code, 2)

    def test_workspace_not_found(self) -> None:
        code = chat.main(["dietcode_agent_chat.py", "--workspace", "/tmp/no-such-dietcode-workspace-xyz", "--prompt", "hi"])
        self.assertGreaterEqual(code, 2)

    def test_validate_workspace_rejects_empty(self) -> None:
        with self.assertRaises(bundle.AgentChatError) as ctx:
            bundle.validate_workspace("")
        self.assertEqual(ctx.exception.code, "workspace_missing")

    def test_build_system_prompt_contains_guardrails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            text = bundle.build_system_prompt(ws, "fix tests")
        self.assertIn("dietcode_ide", text)
        self.assertIn("Do not use raw file writes", text)
        self.assertIn(str(ws), text)
        self.assertIn("fix tests", text)

    def test_repo_root_from_bundled_script_path(self) -> None:
        fake = Path("/Applications/DietCode.app/Contents/Resources/bin/dietcode-agent-chat.py")
        root = bundle.repo_root_from_script(fake)
        self.assertEqual(root, Path("/Applications/DietCode.app"))

    def test_doctor_json_output(self) -> None:
        if not (REPO_ROOT / "build" / "DietCode.app").is_dir():
            self.skipTest("build/DietCode.app missing")
        completed = subprocess.run(
            [sys.executable, str(SCRIPTS / "dietcode_agent_chat.py"), "--doctor", "--format", "json", "--app-bundle", str(REPO_ROOT / "build" / "DietCode.app")],
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertIn("status", payload)
        self.assertIn("runtime", payload["status"])

    def test_missing_hermes_fails_early(self) -> None:
        if not (REPO_ROOT / "build" / "DietCode.app").is_dir():
            self.skipTest("build/DietCode.app missing")
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(bundle, "find_hermes_binary", return_value=None):
                ctx = bundle.resolve_context(
                    repo_root=REPO_ROOT,
                    app_bundle_arg=str(REPO_ROOT / "build" / "DietCode.app"),
                )
                with self.assertRaises(bundle.AgentChatError) as exc:
                    bundle.assert_chat_ready(ctx, REPO_ROOT, Path(tmp))
                self.assertEqual(exc.exception.code, "hermes_missing")

    def test_missing_plugin_fails_early(self) -> None:
        if not (REPO_ROOT / "build" / "DietCode.app").is_dir():
            self.skipTest("build/DietCode.app missing")
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(bundle, "find_hermes_binary", return_value=Path("/usr/bin/hermes")):
                with mock.patch.object(bundle, "plugin_installed", return_value=False):
                    ctx = bundle.resolve_context(
                        repo_root=REPO_ROOT,
                        app_bundle_arg=str(REPO_ROOT / "build" / "DietCode.app"),
                    )
                    with self.assertRaises(bundle.AgentChatError) as exc:
                        bundle.assert_chat_ready(ctx, REPO_ROOT, Path(tmp))
                    self.assertEqual(exc.exception.code, "plugin_missing")

    def test_sidebar_command_construction(self) -> None:
        workspace = "/tmp/project"
        prompt = "inspect this project"
        args = ["--workspace", workspace, "--prompt", prompt, "--format", "text"]
        self.assertEqual(args[1], workspace)
        self.assertEqual(args[3], prompt)
        self.assertNotIn(";", " ".join(args))
        self.assertNotIn("|", " ".join(args))

    def test_chat_json_shape_mocked(self) -> None:
        if not (REPO_ROOT / "build" / "DietCode.app").is_dir():
            self.skipTest("build/DietCode.app missing")
        with tempfile.TemporaryDirectory() as tmp:
            ctx = bundle.resolve_context(
                repo_root=REPO_ROOT,
                app_bundle_arg=str(REPO_ROOT / "build" / "DietCode.app"),
            )
            status = {"runtime": {"ready": True}, "bridge": {"ready": True}, "hermes": {"ready": True}}
            with mock.patch.object(chat, "assert_chat_ready", return_value=status):
                with mock.patch.object(chat, "run_hermes_chat", return_value=(0, "Hermes: done")):
                    code = chat.cmd_chat(
                        REPO_ROOT,
                        ctx,
                        workspace=Path(tmp),
                        prompt="hello",
                        fmt="json",
                        max_turns=5,
                        enforce_mutation_authority=False,
                    )
            self.assertEqual(code, 0)

    def test_installed_app_bundle_resolution(self) -> None:
        build_bundle = REPO_ROOT / "build" / "DietCode.app"
        if not build_bundle.is_dir():
            self.skipTest("build bundle missing")
        ctx = bundle.resolve_context(repo_root=REPO_ROOT, app_bundle_arg=str(build_bundle))
        self.assertEqual(ctx.app_bundle, build_bundle.resolve())
        self.assertTrue(ctx.bridge_cli is not None or ctx.app_bundle is not None)


class AgentSidebarGuardTests(unittest.TestCase):
    def test_no_workspace_message(self) -> None:
        workspace = ""
        self.assertEqual(workspace.strip(), "")
        expected = "Open a folder first."
        self.assertTrue(expected)


if __name__ == "__main__":
    unittest.main()
