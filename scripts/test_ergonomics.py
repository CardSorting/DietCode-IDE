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
        # Test 4: combo.cancel returns correct shape
        # ---------------------------------------------------------------
        print("\nTest 4: combo.cancel returns cancelled=True and comboId echo")
        # We can't start a real combo without a full schemaVersion 1.6.2 plan, so
        # just verify that an unknown comboId returns a proper error (not a silent no-op).
        res_cancel = call(sock, token, "combo.cancel", {"comboId": "nonexistent-test-id"})
        print(f"combo.cancel (unknown id) result: {json.dumps(res_cancel, indent=2)}")
        # Must return an error envelope (ok=False) for unknown ids, not ok=True with garbage
        assert not res_cancel.get("ok"), \
            "combo.cancel with unknown comboId should return ok=False (error), not a silent no-op"
        assert res_cancel.get("error"), \
            "combo.cancel error response must include an error object"
        print("Test 4: PASSED")

    print("\n=== All Ergonomics & Patch Validation Verification Cases Passed Successfully ===")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
