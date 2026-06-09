#!/usr/bin/env python3
"""Regression tests for verification authority helpers."""

from __future__ import annotations

import importlib.util
import json
import shutil
import stat
import sys
import tempfile
import time
import unittest
import unittest.mock
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


verify_auth = _load_module("dietcode_verification_authority", SCRIPTS / "dietcode_verification_authority.py")


class VerificationAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_home = tempfile.mkdtemp(prefix="dietcode-verify-home-")
        self.home_patch = unittest.mock.patch.object(Path, "home", return_value=Path(self.temp_home))
        self.home_patch.start()

    def tearDown(self) -> None:
        self.home_patch.stop()
        shutil.rmtree(self.temp_home, ignore_errors=True)

    def test_verification_authority_success(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            script = ws / "verify.sh"
            script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            script.chmod(script.stat().st_mode | stat.S_IXUSR)
            mut_at = time.time()
            authority = verify_auth.execute_verification_authority(
                ws,
                run_id="okrun01",
                mutation_completed_at=mut_at,
                verify_command="./verify.sh",
            )
            self.assertTrue(authority["executed"])
            self.assertTrue(authority["passed"])
            self.assertEqual(authority["exitCode"], 0)
            self.assertTrue(authority["checkedAfterMutation"])
            audit = verify_auth.audit_verification_authority("okrun01", authority, mutation_completed_at=mut_at)
            self.assertTrue(audit["ok"])

    def test_verification_authority_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            script = ws / "verify.sh"
            script.write_text("#!/bin/sh\nexit 3\n", encoding="utf-8")
            script.chmod(script.stat().st_mode | stat.S_IXUSR)
            mut_at = time.time()
            authority = verify_auth.execute_verification_authority(
                ws,
                run_id="failrun1",
                mutation_completed_at=mut_at,
                verify_command="./verify.sh",
            )
            self.assertTrue(authority["executed"])
            self.assertFalse(authority["passed"])
            self.assertEqual(authority["exitCode"], 3)

    def test_verification_authority_missing_logs(self) -> None:
        authority = {
            "verifyCommand": "./verify.sh",
            "executed": True,
            "exitCode": 0,
            "passed": True,
            "stdoutFile": str(Path(self.temp_home) / "missing.stdout.log"),
            "stderrFile": str(Path(self.temp_home) / "missing.stderr.log"),
            "checkedAfterMutation": True,
            "durationMs": 1,
        }
        audit = verify_auth.audit_verification_authority("norun001", authority, mutation_completed_at=time.time())
        self.assertFalse(audit["ok"])
        self.assertIn("missing_stdout_log", audit["issues"])

    def test_verification_authority_ordering(self) -> None:
        mut_at = time.time()
        authority = verify_auth.execute_verification_authority(
            Path(tempfile.mkdtemp()),
            run_id="ordrun01",
            mutation_completed_at=mut_at - 10,
            verify_command="true",
        )
        stored = json.loads(verify_auth.verification_json_path("ordrun01").read_text(encoding="utf-8"))
        self.assertGreaterEqual(stored["verificationStartedAt"], stored["mutationCompletedAt"])
        self.assertTrue(authority["checkedAfterMutation"])

    def test_verification_labels(self) -> None:
        self.assertEqual(verify_auth.verification_label({"executed": True, "passed": True}), "Passed")
        self.assertEqual(verify_auth.verification_label({"executed": True, "passed": False}), "Failed")
        self.assertEqual(verify_auth.verification_label({"executed": False}), "Not Run")


if __name__ == "__main__":
    unittest.main()
