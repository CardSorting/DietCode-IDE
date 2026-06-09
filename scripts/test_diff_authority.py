#!/usr/bin/env python3
"""Regression tests for diff authority audit helpers."""

from __future__ import annotations

import importlib.util
import shutil
import sys
import tempfile
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


diff_auth = _load_module("dietcode_diff_authority", SCRIPTS / "dietcode_diff_authority.py")
mutation = _load_module("dietcode_mutation_authority", SCRIPTS / "dietcode_mutation_authority.py")


class DiffAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_home = tempfile.mkdtemp(prefix="dietcode-diff-home-")
        self.home_patch = unittest.mock.patch.object(Path, "home", return_value=Path(self.temp_home))
        self.home_patch.start()

    def tearDown(self) -> None:
        self.home_patch.stop()
        shutil.rmtree(self.temp_home, ignore_errors=True)

    def test_build_unified_diff_detects_change(self) -> None:
        before = {"smoke_probe.py": "VALUE = 1\n"}
        after = {"smoke_probe.py": "VALUE = 2\n"}
        text, changed = diff_auth.build_unified_diff(before, after)
        self.assertIn("smoke_probe.py", changed)
        self.assertIn("VALUE = 1", text)
        self.assertIn("VALUE = 2", text)

    def test_audit_diff_authority_matches_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            probe = ws / "smoke_probe.py"
            probe.write_text("VALUE = 2\n", encoding="utf-8")
            before = {"smoke_probe.py": "VALUE = 1\n"}
            mutation_report = {
                "mode": "bridge_only",
                "mutatedFiles": ["smoke_probe.py"],
                "bridgePatchCount": 1,
                "rawWriteSuspected": False,
                "evidence": [],
            }
            report = diff_auth.audit_diff_authority(
                ws,
                run_id="testrun01",
                before_contents=before,
                mutation_authority=mutation_report,
            )
            self.assertTrue(report["matchesMutationAuthority"])
            self.assertEqual(report["changedFiles"], ["smoke_probe.py"])
            diff_path = Path(report["diffFile"])
            self.assertTrue(diff_path.is_file())
            self.assertIn("smoke_probe.py", diff_path.read_text(encoding="utf-8"))

    def test_audit_diff_authority_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            (ws / "a.py").write_text("b\n", encoding="utf-8")
            before = {"a.py": "a\n"}
            mutation_report = mutation.empty_mutation_authority()
            report = diff_auth.audit_diff_authority(
                ws,
                run_id="testrun02",
                before_contents=before,
                mutation_authority=mutation_report,
            )
            self.assertFalse(report["matchesMutationAuthority"])


if __name__ == "__main__":
    unittest.main()
