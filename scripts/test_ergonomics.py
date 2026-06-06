#!/usr/bin/env python3
"""
DietCode Ergonomics & Patch Validation Verification Suite
Validates the relaxed syntax-checking behaviour introduced in the agent ergonomics pass.

Run with DietCode open and its control socket active:
    python3 scripts/test_ergonomics.py
"""
import json
import os
import time

from dietcode_agent_client import connect, load_token, send_rpc

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def main():
    print("=== DietCode Ergonomics & Patch Validation Verification Suite ===")

    # Establish socket connection
    with connect() as sock:
        token = load_token()
        print(f"Loaded session token: {token[:8]}...")

        # Get workspace root
        res = call(sock, token, "workspace.getRoot")
        workspace_root = res.get("result", {}).get("path")
        print(f"Workspace root: {workspace_root}")
        assert workspace_root, "Failed to get workspace root"

        # ---------------------------------------------------------------
        # Test 1: Markdown file with unbalanced brackets
        # ---------------------------------------------------------------
        print("\nTest 1: Markdown file with unbalanced brackets")
        md_file_path = os.path.join(workspace_root, "test_bracket_md.md")
        with open(md_file_path, "w") as f:
            f.write("# Hello World\n[link without closing paren\n")

        try:
            patch_md = (
                "--- test_bracket_md.md\n"
                "+++ test_bracket_md.md\n"
                "@@ -1,2 +1,3 @@\n"
                " # Hello World\n"
                " [link without closing paren\n"
                "+More unmatched text [here\n"
            )

            res = call(sock, token, "patch.validate", {
                "path": "test_bracket_md.md",
                "patch": patch_md
            })
            print(f"Markdown validation result: {json.dumps(res, indent=2)}")

            # Outer RPC call must succeed
            assert res.get("ok"), "Markdown patch.validate RPC failed"
            validation = res.get("result", {}).get("validation", {})

            # Validation must pass: markdown is exempt from bracket checking
            assert validation.get("ok"), \
                f"Markdown patch validation returned ok=False: {validation.get('rejectedReason')}"

            # syntaxDanger is now hoisted to the root validation dict as a bool
            assert validation.get("syntaxDanger") == False, \
                "Markdown file should have syntaxDanger=False at root of validation"
            print("Test 1: PASSED")

        finally:
            if os.path.exists(md_file_path):
                os.remove(md_file_path)

        # ---------------------------------------------------------------
        # Test 2: Python file with unbalanced brackets only in comment/string
        # ---------------------------------------------------------------
        print("\nTest 2: Python file with unbalanced brackets in comment and string")
        py_file_path = os.path.join(workspace_root, "test_bracket_py.py")
        with open(py_file_path, "w") as f:
            f.write('# (This is a comment with unbalanced paren\ns = "[unbalanced string"\n')

        try:
            patch_py = (
                "--- test_bracket_py.py\n"
                "+++ test_bracket_py.py\n"
                "@@ -1,2 +1,3 @@\n"
                ' # (This is a comment with unbalanced paren\n'
                ' s = "[unbalanced string"\n'
                "+x = 42\n"
            )

            res = call(sock, token, "patch.validate", {
                "path": "test_bracket_py.py",
                "patch": patch_py
            })
            print(f"Python comment/string validation result: {json.dumps(res, indent=2)}")

            assert res.get("ok"), "Python comment/string patch.validate RPC failed"
            validation = res.get("result", {}).get("validation", {})

            assert validation.get("ok"), \
                f"Python comment/string validation returned ok=False: {validation.get('rejectedReason')}"
            assert validation.get("syntaxDanger") == False, \
                "Should not detect syntaxDanger=True for brackets inside comments/strings"
            print("Test 2: PASSED")

        finally:
            if os.path.exists(py_file_path):
                os.remove(py_file_path)

        # ---------------------------------------------------------------
        # Test 3: Python file with a real compile error (ignoreSyntax variants)
        # ---------------------------------------------------------------
        print("\nTest 3: Python file with a compilation syntax error")
        py_err_path = os.path.join(workspace_root, "test_err_py.py")
        with open(py_err_path, "w") as f:
            f.write("def foo():\n    return 42\n")

        try:
            # Introduce a real Python compile error: missing closing paren on def statement
            patch_err = (
                "--- test_err_py.py\n"
                "+++ test_err_py.py\n"
                "@@ -1,2 +1,2 @@\n"
                "-def foo():\n"
                "+def foo(:\n"
                "     return 42\n"
            )

            # Case A: default ignoreSyntax=True (relaxed) — must pass with syntaxWarning
            print("\nCase A: default ignoreSyntax (relaxed mode)")
            res_relaxed = call(sock, token, "patch.validate", {
                "path": "test_err_py.py",
                "patch": patch_err
            })
            print(f"Relaxed validation result: {json.dumps(res_relaxed, indent=2)}")
            assert res_relaxed.get("ok"), "Relaxed patch.validate RPC failed"
            val_relaxed = res_relaxed.get("result", {}).get("validation", {})
            assert val_relaxed.get("ok"), \
                f"Relaxed validation should return ok=True: {val_relaxed.get('rejectedReason')}"
            assert val_relaxed.get("syntaxDanger") == True, \
                "Relaxed validation should report syntaxDanger=True at root"
            assert val_relaxed.get("syntaxWarning"), \
                "Relaxed validation should report a non-empty syntaxWarning"

            # Case B: ignoreSyntax=False (strict) — validation.ok must be False
            print("\nCase B: ignoreSyntax=False (strict mode)")
            res_strict = call(sock, token, "patch.validate", {
                "path": "test_err_py.py",
                "patch": patch_err,
                "ignoreSyntax": False
            })
            print(f"Strict validation result: {json.dumps(res_strict, indent=2)}")
            # The RPC envelope itself succeeds (outer ok=True), but validation.ok=False
            assert res_strict.get("ok"), "Strict patch.validate RPC call failed at socket level"
            val_strict = res_strict.get("result", {}).get("validation", {})
            assert not val_strict.get("ok"), \
                "Strict validation should return validation.ok=False"
            assert val_strict.get("rejectedReason"), \
                "Strict validation should have a non-empty rejectedReason"
            print("Test 3: PASSED")

        finally:
            if os.path.exists(py_err_path):
                os.remove(py_err_path)

        # ---------------------------------------------------------------
        # Test 4: validation failures still expose root syntaxDanger=False
        # ---------------------------------------------------------------
        print("\nTest 4: validation failure shape includes syntaxDanger=False")
        res_missing = call(sock, token, "patch.validate", {
            "path": "missing_ergonomics_target.py",
            "patch": (
                "--- missing_ergonomics_target.py\n"
                "+++ missing_ergonomics_target.py\n"
                "@@ -1 +1 @@\n"
                "-old\n"
                "+new\n"
            )
        })
        print(f"Missing target validation result: {json.dumps(res_missing, indent=2)}")
        assert res_missing.get("ok"), "patch.validate RPC should return validation object for missing target"
        missing_validation = res_missing.get("result", {}).get("validation", {})
        assert missing_validation.get("ok") == False, "Missing target should fail validation"
        assert missing_validation.get("syntaxDanger") == False, \
            "Validation failure should still report syntaxDanger=False at root"
        print("Test 4: PASSED")

        # ---------------------------------------------------------------
        # Test 5: patch.preview mirrors syntaxDanger at the response root
        # ---------------------------------------------------------------
        print("\nTest 5: patch.preview reports root syntaxDanger")
        py_preview_path = os.path.join(workspace_root, "test_preview_py.py")
        with open(py_preview_path, "w") as f:
            f.write("def preview_ok():\n    return 42\n")

        try:
            patch_preview = (
                "--- test_preview_py.py\n"
                "+++ test_preview_py.py\n"
                "@@ -1,2 +1,2 @@\n"
                "-def preview_ok():\n"
                "+def preview_ok(:\n"
                "     return 42\n"
            )
            res_preview = call(sock, token, "patch.preview", {
                "path": "test_preview_py.py",
                "patch": patch_preview
            })
            print(f"patch.preview syntax result: {json.dumps(res_preview, indent=2)}")
            assert res_preview.get("ok"), "patch.preview RPC failed"
            preview_result = res_preview.get("result", {})
            assert preview_result.get("syntaxDanger") == True, \
                "patch.preview should mirror syntaxDanger=True at response root"
            assert preview_result.get("syntaxWarning"), \
                "patch.preview should mirror syntaxWarning at response root"
            print("Test 5: PASSED")
        finally:
            if os.path.exists(py_preview_path):
                os.remove(py_preview_path)

        # ---------------------------------------------------------------
        # Test 6: terminal task state is preserved on rejected follow-up
        # ---------------------------------------------------------------
        print("\nTest 6: task terminal state is not overwritten by rejected follow-up")
        res_task = call(sock, token, "task.start", {
            "goal": "ergonomics terminal state regression"
        })
        print(f"task.start result: {json.dumps(res_task, indent=2)}")
        assert res_task.get("ok"), "task.start RPC failed"
        task_id = res_task.get("result", {}).get("taskId")
        assert task_id, "task.start did not return taskId"

        res_complete = call(sock, token, "task.runLoop", {
            "taskId": task_id,
            "steps": []
        })
        print(f"task.runLoop completion result: {json.dumps(res_complete, indent=2)}")
        assert res_complete.get("ok"), "task.runLoop empty completion RPC failed"
        assert res_complete.get("result", {}).get("task", {}).get("status") == "complete", \
            "Empty runLoop should complete the task"

        res_step_after_complete = call(sock, token, "task.step", {
            "taskId": task_id,
            "step": {"type": "contextSnapshot"}
        })
        print(f"task.step after complete result: {json.dumps(res_step_after_complete, indent=2)}")
        assert res_step_after_complete.get("ok"), "task.step rejection should be returned in stepResult"
        step_result = res_step_after_complete.get("result", {}).get("stepResult", {})
        assert step_result.get("ok") == False, "task.step after complete should be rejected"
        assert step_result.get("error", {}).get("code") == "task_not_active", \
            "task.step after complete should use task_not_active, not budget_exceeded"
        assert res_step_after_complete.get("result", {}).get("task", {}).get("status") == "complete", \
            "Rejected follow-up must not overwrite complete status"

        res_cancel_complete = call(sock, token, "task.cancel", {"taskId": task_id})
        print(f"task.cancel after complete result: {json.dumps(res_cancel_complete, indent=2)}")
        assert not res_cancel_complete.get("ok"), "task.cancel on complete task should return an error"
        assert res_cancel_complete.get("error", {}).get("string_code") == "task_not_active", \
            "task.cancel on complete task should use task_not_active"
        print("Test 6: PASSED")

        # ---------------------------------------------------------------
        # Test 7: read/search invalid params fail explicitly
        # ---------------------------------------------------------------
        print("\nTest 7: read/search invalid params fail explicitly")
        contract_path = os.path.join(workspace_root, "test_contracts.txt")
        with open(contract_path, "w") as f:
            f.write("alpha\nbeta\ngamma\n")

        try:
            invalid_cases = [
                (
                    "file.readRange missing startLine",
                    "file.readRange",
                    {"path": "test_contracts.txt", "endLine": 1},
                    "invalid_params",
                ),
                (
                    "file.readAround negative context",
                    "file.readAround",
                    {"path": "test_contracts.txt", "line": 1, "before": -1},
                    "invalid_params",
                ),
                (
                    "search.files zero maxResults",
                    "search.files",
                    {"query": "test", "maxResults": 0},
                    "invalid_params",
                ),
                (
                    "search.text excessive context",
                    "search.text",
                    {"query": "alpha", "before": 21},
                    "response_too_large",
                ),
                (
                    "search.todo negative maxResults",
                    "search.todo",
                    {"maxResults": -1},
                    "invalid_params",
                ),
                (
                    "analysis.searchRanked negative maxResults",
                    "analysis.searchRanked",
                    {"query": "alpha", "maxResults": -1},
                    "invalid_params",
                ),
            ]

            for label, method, params, expected_code in invalid_cases:
                res_invalid = call(sock, token, method, params)
                print(f"{label}: {json.dumps(res_invalid, indent=2)}")
                assert not res_invalid.get("ok"), f"{label} should fail"
                assert res_invalid.get("error", {}).get("string_code") == expected_code, \
                    f"{label} should use {expected_code}"
            print("Test 7: PASSED")
        finally:
            if os.path.exists(contract_path):
                os.remove(contract_path)

        # ---------------------------------------------------------------
        # Test 8: terminal/verify/repair invalid params fail before side effects
        # ---------------------------------------------------------------
        print("\nTest 8: terminal/verify/repair invalid params fail before side effects")
        side_effect_free_cases = [
            (
                "terminal.run empty command",
                "terminal.run",
                {"command": ""},
                "invalid_params",
            ),
            (
                "verify.run empty command",
                "verify.run",
                {"command": ""},
                "invalid_params",
            ),
            (
                "repair context outside workspace",
                "repair.fromPatchFailure",
                {
                    "files": [
                        {
                            "path": "/tmp/outside_repair_context.txt",
                            "ranges": [{"startLine": 1, "endLine": 1}],
                        }
                    ]
                },
                "outside_workspace",
            ),
            (
                "repair context invalid range",
                "repair.fromPatchFailure",
                {
                    "files": [
                        {
                            "path": "test_contracts.txt",
                            "ranges": [{"startLine": 0, "endLine": 1}],
                        }
                    ]
                },
                "invalid_params",
            ),
        ]

        contract_path = os.path.join(workspace_root, "test_contracts.txt")
        with open(contract_path, "w") as f:
            f.write("alpha\nbeta\ngamma\n")

        try:
            for label, method, params, expected_code in side_effect_free_cases:
                res_invalid = call(sock, token, method, params)
                print(f"{label}: {json.dumps(res_invalid, indent=2)}")
                assert not res_invalid.get("ok"), f"{label} should fail"
                assert res_invalid.get("error", {}).get("string_code") == expected_code, \
                    f"{label} should use {expected_code}"
            print("Test 8: PASSED")
        finally:
            if os.path.exists(contract_path):
                os.remove(contract_path)

        # ---------------------------------------------------------------
        # Test 9: combo.cancel returns correct shape
        # ---------------------------------------------------------------
        print("\nTest 9: combo.cancel returns cancelled=True and comboId echo")
        # We can't start a real combo without a full schemaVersion 1.6.2 plan, so
        # just verify that an unknown comboId returns a proper error (not a silent no-op).
        res_cancel = call(sock, token, "combo.cancel", {"comboId": "nonexistent-test-id"})
        print(f"combo.cancel (unknown id) result: {json.dumps(res_cancel, indent=2)}")
        # Must return an error envelope (ok=False) for unknown ids, not ok=True with garbage
        assert not res_cancel.get("ok"), \
            "combo.cancel with unknown comboId should return ok=False (error), not a silent no-op"
        assert res_cancel.get("error"), \
            "combo.cancel error response must include an error object"
        print("Test 9: PASSED")

    print("\n=== All Ergonomics & Patch Validation Verification Cases Passed Successfully ===")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
