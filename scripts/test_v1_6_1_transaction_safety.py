#!/usr/bin/env python3
import json
import os
import socket
import sys
import time
import shutil

from dietcode_agent_client import SOCKET_PATH, ensure_socket, load_token, send_rpc

BACKUPS_DIR = os.path.expanduser("~/.dietcode/backups")

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def main():
    print("=== DietCode v1.6.1 Transaction Safety Verification Suite ===")
    
    if not ensure_socket():
        print("Failed to start DietCode headless process or socket did not initialize.", file=sys.stderr)
        return 1

    token = load_token()
    print(f"Loaded session token: {token[:8]}...")

    # Establish socket connection
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET_PATH)
        
        # Test 1: ping
        print("\nTest 1: Ping control server")
        res = call(sock, token, "rpc.ping")
        print(f"Ping result: {res}")
        assert res.get("ok"), "Ping failed"

        # Get workspace root
        res = call(sock, token, "workspace.getRoot")
        workspace_root = res.get("result", {}).get("path")
        if not workspace_root:
            print("Workspace not open. Opening '/Users/bozoegg/Desktop/DietCode-IDE'...")
            open_res = call(sock, token, "workspace.openFolder", {"path": "/Users/bozoegg/Desktop/DietCode-IDE"})
            print(f"Open folder result: {open_res}")
            res = call(sock, token, "workspace.getRoot")
            workspace_root = res.get("result", {}).get("path")
        print(f"Workspace root: {workspace_root}")
        assert workspace_root, "Failed to get workspace root"

        # Create a test target file
        test_file_path = os.path.join(workspace_root, "test_target_v1_6_1.txt")
        with open(test_file_path, "w") as f:
            f.write("Line 1: Initial state\nLine 2: Unchanged content\nLine 3: Base state\n")
        print(f"Created test file at: {test_file_path}")

        try:
            # Let's open the file in the workspace
            print("Opening file in editor...")
            call(sock, token, "workspace.openFile", {"path": "test_target_v1_6_1.txt"})
            time.sleep(1.0)

            # Construct a basic combo plan to apply a patch
            # Patch to replace Line 2
            diff_content = (
                "--- test_target_v1_6_1.txt\n"
                "+++ test_target_v1_6_1.txt\n"
                "@@ -1,3 +1,3 @@\n"
                " Line 1: Initial state\n"
                "-Line 2: Unchanged content\n"
                "+Line 2: Mutated content by combo\n"
                " Line 3: Base state\n"
            )

            combo_plan = {
                "schemaVersion": "1.6.2",
                "goal": "Test transaction safety",
                "policy": {
                    "permissions": ["edit", "read"]
                },
                "budget": {
                    "maxSteps": 5,
                    "maxFilesTouched": 2
                },
                "scope": {
                    "include": ["test_target_v1_6_1.txt"]
                },
                "steps": [
                    {
                        "id": "s1",
                        "chip": "patch.apply@1",
                        "params": {
                            "path": "test_target_v1_6_1.txt",
                            "patch": diff_content
                        }
                    }
                ]
            }

            print("\nTest 2: Running mutation combo")
            combo_id = f"test-combo-{int(time.time() * 1000)}"
            # Cleanup old backup if exists
            shutil.rmtree(os.path.join(BACKUPS_DIR, combo_id), ignore_errors=True)

            res = call(sock, token, "combo.run", {"combo": combo_plan, "comboId": combo_id})
            print(f"Combo Run Result: {json.dumps(res, indent=2)}")
            assert res.get("ok"), "Combo execution failed"

            # Check that manifest.json and backup blobs were created correctly
            combo_backup_dir = os.path.join(BACKUPS_DIR, combo_id)
            manifest_path = os.path.join(combo_backup_dir, "manifest.json")
            assert os.path.exists(manifest_path), "manifest.json was not created!"
            
            with open(manifest_path, "r") as m_file:
                manifest_data = json.load(m_file)
                print(f"Created backup manifest.json: {json.dumps(manifest_data, indent=2)}")
                assert manifest_data.get("schemaVersion") == "1.6.2", "Schema version mismatch"
                files_entry = manifest_data.get("files", [])
                assert len(files_entry) == 1, "Expected exactly one backed up file"
                assert files_entry[0].get("workspaceRelativePath") == "test_target_v1_6_1.txt"
                assert files_entry[0].get("domain") == "buffer" # It is open in editor
                
                # Check blob exists
                blob_hash = files_entry[0].get("backupBlobHash")
                blob_path = os.path.join(combo_backup_dir, f"{blob_hash}.blob")
                assert os.path.exists(blob_path), f"Backup blob {blob_path} missing!"

            # Test 3: recovery.scan read-only status report
            print("\nTest 3: recovery.scan read-only inspection")
            scan_res = call(sock, token, "recovery.scan")
            print(f"Scan Result: {json.dumps(scan_res, indent=2)}")
            assert scan_res.get("ok"), "recovery.scan failed"
            backups = scan_res.get("result", {}).get("backups", [])
            my_backup = [b for b in backups if b.get("comboId") == combo_id]
            assert len(my_backup) == 1, "Our backup not found in scan!"
            assert my_backup[0].get("status") == "postimage_match", "Expected backup status to be postimage_match"

            # Test 4: Postimage mismatch check
            print("\nTest 4: Rollback precondition - external modification check")
            # Modify the file directly on disk (hash will mismatch expected postimage)
            with open(test_file_path, "a") as f:
                f.write("Line 4: Hostile external edit\n")
            
            # Now call combo.rollback and verify it fails close with rollback_postimage_mismatch
            rollback_res = call(sock, token, "combo.rollback", {"comboId": combo_id})
            print(f"Rollback Response (after external edit): {json.dumps(rollback_res, indent=2)}")
            assert not rollback_res.get("ok"), "Rollback should have failed due to external edit!"
            assert rollback_res.get("error", {}).get("string_code") == "rollback_postimage_mismatch", "Expected rollback_postimage_mismatch"

            # Revert the external edit to restore expected postimage state
            with open(test_file_path, "w") as f:
                f.write("Line 1: Initial state\nLine 2: Mutated content by combo\nLine 3: Base state\n")

            # Test 5: Missing manifest check
            print("\nTest 5: Rollback precondition - missing manifest check")
            os.rename(manifest_path, manifest_path + ".bk")
            try:
                rollback_res = call(sock, token, "combo.rollback", {"comboId": combo_id})
                print(f"Rollback Response (missing manifest): {json.dumps(rollback_res, indent=2)}")
                assert not rollback_res.get("ok"), "Rollback should have failed due to missing manifest"
                assert rollback_res.get("error", {}).get("string_code") == "backup_manifest_missing", "Expected backup_manifest_missing"
            finally:
                os.rename(manifest_path + ".bk", manifest_path)

            # Test 6: Symlink escape check
            print("\nTest 6: Rollback precondition - symlink escape check")
            # Replace file with symlink to a file outside workspace
            os.remove(test_file_path)
            outside_file = "/tmp/dietcode_outside_target.txt"
            with open(outside_file, "w") as f:
                f.write("Secret data outside workspace")
            os.symlink(outside_file, test_file_path)

            try:
                rollback_res = call(sock, token, "combo.rollback", {"comboId": combo_id})
                print(f"Rollback Response (symlink escape): {json.dumps(rollback_res, indent=2)}")
                assert not rollback_res.get("ok"), "Rollback should have failed due to symlink escape"
                # PathIsInsideWorkspace should reject symlinks pointing outside the workspace, returning NO.
                # So PathIsInsideWorkspace fails, returning rollback_target_escaped.
                assert rollback_res.get("error", {}).get("string_code") in ["rollback_target_escaped", "rollback_postimage_mismatch"], "Expected rollback_target_escaped or postimage mismatch"
            finally:
                os.remove(test_file_path)
                os.remove(outside_file)

            # Recreate correct postimage file
            with open(test_file_path, "w") as f:
                f.write("Line 1: Initial state\nLine 2: Mutated content by combo\nLine 3: Base state\n")

            # Test 7: Successful Rollback
            print("\nTest 7: Successful rollback execution")
            rollback_res = call(sock, token, "combo.rollback", {"comboId": combo_id})
            print(f"Successful Rollback Response: {json.dumps(rollback_res, indent=2)}")
            assert rollback_res.get("ok"), "Rollback failed under valid conditions!"
            
            # Verify file content is fully restored
            with open(test_file_path, "r") as f:
                restored_text = f.read()
                print(f"Restored file content:\n{restored_text}")
                assert "Line 2: Unchanged content" in restored_text, "Rollback content restoration failed!"
            print("Rollback verify: SUCCESS")

        finally:
            # Clean up test target
            if os.path.exists(test_file_path):
                os.remove(test_file_path)
            shutil.rmtree(os.path.join(BACKUPS_DIR, combo_id), ignore_errors=True)

    print("\n=== All Transaction Safety Verification Cases Passed Successfully ===")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
