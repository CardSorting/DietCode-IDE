#!/usr/bin/env python3
import json
import os
import socket
import sys
import time
import shutil
import hashlib

SOCKET_PATH = os.path.expanduser("~/.dietcode/control.sock")
TOKEN_PATH = os.path.expanduser("~/.dietcode/session.token")
BACKUPS_DIR = os.path.expanduser("~/.dietcode/backups")
AUDIT_LOG_DIR = os.path.expanduser("~/.dietcode")
AUDIT_LOG_PATH = os.path.join(AUDIT_LOG_DIR, "control_audit.log")

def load_token():
    if not os.path.exists(TOKEN_PATH):
        raise RuntimeError(f"Session token not found at {TOKEN_PATH}")
    with open(TOKEN_PATH, "r") as f:
        return f.read().strip()

def call(sock, token, method, params=None, request_id=None):
    payload = {
        "id": request_id or method,
        "method": method,
        "params": params or {},
        "token": token
    }
    sock.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
    data = bytearray()
    while not data.endswith(b"\n"):
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"socket closed while waiting for {method}")
        data.extend(chunk)
    response = json.loads(data.decode("utf-8"))
    return response

def get_sha256(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()

def main():
    print("=== DietCode v1.6.2 Manifest Discipline Verification Suite ===")
    
    if not os.path.exists(SOCKET_PATH):
        print(f"Control socket not found: {SOCKET_PATH}", file=sys.stderr)
        return 1

    token = load_token()
    print(f"Loaded session token: {token[:8]}...")

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
        test_file_path = os.path.join(workspace_root, "test_target_v1_6_2.txt")
        
        def reset_test_file():
            with open(test_file_path, "w") as f:
                f.write("Line 1: Initial state\nLine 2: Unchanged content\nLine 3: Base state\n")

        reset_test_file()
        print(f"Created test file at: {test_file_path}")

        try:
            print("Opening file in editor...")
            call(sock, token, "workspace.openFile", {"path": "test_target_v1_6_2.txt"})
            time.sleep(0.5)

            diff_content = (
                "--- test_target_v1_6_2.txt\n"
                "+++ test_target_v1_6_2.txt\n"
                "@@ -1,3 +1,3 @@\n"
                " Line 1: Initial state\n"
                "-Line 2: Unchanged content\n"
                "+Line 2: Mutated content by combo\n"
                " Line 3: Base state\n"
            )

            combo_plan = {
                "schemaVersion": "1.6.2",
                "goal": "Test v1.6.2 Manifest Discipline",
                "policy": {
                    "permissions": ["edit", "read"]
                },
                "budget": {
                    "maxSteps": 5,
                    "maxFilesTouched": 2
                },
                "scope": {
                    "include": ["test_target_v1_6_2.txt"]
                },
                "steps": [
                    {
                        "id": "s1",
                        "chip": "patch.apply@1",
                        "params": {
                            "path": "test_target_v1_6_2.txt",
                            "patch": diff_content,
                            "allowDirtyBuffer": True
                        }
                    }
                ]
            }

            def run_combo(cid):
                shutil.rmtree(os.path.join(BACKUPS_DIR, cid), ignore_errors=True)
                reset_test_file()
                res = call(sock, token, "combo.run", {"combo": combo_plan, "comboId": cid})
                assert res.get("ok"), f"Combo execution failed: {res}"
                backup_dir = os.path.join(BACKUPS_DIR, cid)
                m_path = os.path.join(backup_dir, "manifest.json")
                s_path = os.path.join(backup_dir, "manifest.sha256")
                return backup_dir, m_path, s_path

            # Case 1: Valid manifest passes rollback
            print("\nCase 1: Valid manifest passes rollback")
            cid1 = "test-combo-c1"
            backup_dir, m_path, s_path = run_combo(cid1)
            assert os.path.exists(m_path), "manifest.json missing!"
            assert os.path.exists(s_path), "manifest.sha256 missing!"
            
            # Verify canonical JSON key ordering and lack of whitespace
            with open(m_path, "r") as m_file:
                raw_json = m_file.read()
                assert "\n" not in raw_json, "Canonical JSON must not contain formatting whitespaces/newlines"
                parsed = json.loads(raw_json)
                expected_keys = sorted(parsed.keys())
                actual_keys = list(parsed.keys())
                print(f"Actual top-level keys: {actual_keys}")
                assert actual_keys == expected_keys, "Manifest keys are not in alphabetical order!"
                # Check top-level keys contains only whitelisted
                whitelisted = {"schemaVersion", "comboId", "createdAt", "workspaceRootHash", "chipVersions", "files"}
                for k in actual_keys:
                    assert k in whitelisted, f"Top-level key {k} is not whitelisted"

            # Rollback
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid1})
            print(f"Rollback result: {rollback_res}")
            assert rollback_res.get("ok"), "Rollback failed"

            # Case 2: Unknown top-level field rejected
            print("\nCase 2: Unknown top-level field rejected")
            cid2 = "test-combo-c2"
            backup_dir, m_path, s_path = run_combo(cid2)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            parsed["hostile_field"] = "some reasoning trace"
            canonical = json.dumps(parsed, separators=(",", ":"), sort_keys=True)
            with open(m_path, "w") as f:
                f.write(canonical)
            with open(s_path, "w") as f:
                f.write(get_sha256(canonical) + "\n")
            
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid2})
            print(f"Rollback with unknown top field result: {rollback_res}")
            assert not rollback_res.get("ok")
            assert rollback_res.get("error", {}).get("string_code") == "backup_manifest_invalid"
            assert "unknown" in rollback_res.get("error", {}).get("message").lower()

            # Case 3: Unknown file field rejected
            print("\nCase 3: Unknown file field rejected")
            cid3 = "test-combo-c3"
            backup_dir, m_path, s_path = run_combo(cid3)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            parsed["files"][0]["unauthorized_flag"] = True
            canonical = json.dumps(parsed, separators=(",", ":"), sort_keys=True)
            with open(m_path, "w") as f:
                f.write(canonical)
            with open(s_path, "w") as f:
                f.write(get_sha256(canonical) + "\n")
            
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid3})
            print(f"Rollback with unknown file field result: {rollback_res}")
            assert not rollback_res.get("ok")
            assert rollback_res.get("error", {}).get("string_code") == "backup_manifest_invalid"
            assert "unknown" in rollback_res.get("error", {}).get("message").lower()

            # Case 4: Oversized manifest rejected
            print("\nCase 4: Oversized manifest rejected")
            cid4 = "test-combo-c4"
            backup_dir, m_path, s_path = run_combo(cid4)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            parsed["chipVersions"] = ["a" * 300000] # Make it >256KB
            canonical = json.dumps(parsed, separators=(",", ":"), sort_keys=True)
            with open(m_path, "w") as f:
                f.write(canonical)
            with open(s_path, "w") as f:
                f.write(get_sha256(canonical) + "\n")
            
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid4})
            print(f"Rollback with oversized manifest result: {rollback_res}")
            assert not rollback_res.get("ok")
            assert rollback_res.get("error", {}).get("string_code") == "backup_manifest_invalid"
            assert "exceeds" in rollback_res.get("error", {}).get("message").lower()

            # Case 5: Missing blob detected
            print("\nCase 5: Missing blob detected")
            cid5 = "test-combo-c5"
            backup_dir, m_path, s_path = run_combo(cid5)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            blob_hash = parsed["files"][0]["backupBlobHash"]
            blob_path = os.path.join(backup_dir, f"{blob_hash}.blob")
            assert os.path.exists(blob_path), "Blob file should exist"
            os.remove(blob_path)
            
            scan_res = call(sock, token, "recovery.scan")
            found = False
            for bk in scan_res.get("result", {}).get("backups", []):
                if bk.get("comboId") == cid5:
                    print(f"Scan status for missing blob: {bk.get('status')}")
                    assert bk.get("status") == "blob_missing"
                    found = True
            assert found, "Combo not found in recovery scan"

            # Case 6: Blob hash mismatch detected
            print("\nCase 6: Blob hash mismatch detected")
            cid6 = "test-combo-c6"
            backup_dir, m_path, s_path = run_combo(cid6)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            blob_hash = parsed["files"][0]["backupBlobHash"]
            blob_path = os.path.join(backup_dir, f"{blob_hash}.blob")
            with open(blob_path, "w") as f:
                f.write("corrupt blob content")
            
            scan_res = call(sock, token, "recovery.scan")
            found = False
            for bk in scan_res.get("result", {}).get("backups", []):
                if bk.get("comboId") == cid6:
                    print(f"Scan status for blob hash mismatch: {bk.get('status')}")
                    assert bk.get("status") == "blob_hash_mismatch"
                    found = True
            assert found, "Combo not found in recovery scan"

            # Case 7: Checksum mismatch detected
            print("\nCase 7: Checksum mismatch detected")
            cid7 = "test-combo-c7"
            backup_dir, m_path, s_path = run_combo(cid7)
            with open(s_path, "w") as f:
                f.write("badchecksumhashvalue123\n")
            
            scan_res = call(sock, token, "recovery.scan")
            found = False
            for bk in scan_res.get("result", {}).get("backups", []):
                if bk.get("comboId") == cid7:
                    print(f"Scan status for checksum mismatch: {bk.get('status')}")
                    assert bk.get("status") == "checksum_mismatch"
                    found = True
            assert found, "Combo not found in recovery scan"
            
            # also verify rollback is rejected with backup_corrupt
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid7})
            print(f"Rollback with checksum mismatch result: {rollback_res}")
            assert not rollback_res.get("ok")
            assert rollback_res.get("error", {}).get("string_code") == "backup_corrupt"

            # Case 8: Unsupported schema becomes inspect-only
            print("\nCase 8: Unsupported schema becomes inspect-only")
            cid8 = "test-combo-c8"
            backup_dir, m_path, s_path = run_combo(cid8)
            with open(m_path, "r") as f:
                parsed = json.loads(f.read())
            parsed["schemaVersion"] = "1.6.1"
            canonical = json.dumps(parsed, separators=(",", ":"), sort_keys=True)
            with open(m_path, "w") as f:
                f.write(canonical)
            if os.path.exists(s_path):
                os.remove(s_path)
            
            scan_res = call(sock, token, "recovery.scan")
            found = False
            for bk in scan_res.get("result", {}).get("backups", []):
                if bk.get("comboId") == cid8:
                    print(f"Scan status for legacy schema: {bk.get('status')}")
                    assert bk.get("status") == "unsupported_schema"
                    found = True
            assert found, "Combo not found in recovery scan"

            # Case 9: Rollback blocked on legacy manifest
            print("\nCase 9: Rollback blocked on legacy manifest")
            rollback_res = call(sock, token, "combo.rollback", {"comboId": cid8})
            print(f"Rollback legacy result: {rollback_res}")
            assert not rollback_res.get("ok")
            assert rollback_res.get("error", {}).get("string_code") == "backup_manifest_invalid"

            # Case 10: Audit log rotates at 5MB limit
            print("\nCase 10: Audit log rotates at 5MB limit")
            # Clear/Prepare logs
            log1_path = AUDIT_LOG_PATH + ".1"
            log2_path = AUDIT_LOG_PATH + ".2"
            log3_path = AUDIT_LOG_PATH + ".3"
            for p in [AUDIT_LOG_PATH, log1_path, log2_path, log3_path]:
                if os.path.exists(p):
                    os.remove(p)
            
            # Create pre-existing rotated logs to test cascade
            with open(log2_path, "w") as f:
                f.write("legacy log 2\n")
            with open(log1_path, "w") as f:
                f.write("legacy log 1\n")
                
            # Create a log file slightly above 5MB
            oversize_data = "A" * (5 * 1024 * 1024 + 100)
            with open(AUDIT_LOG_PATH, "w") as f:
                f.write(oversize_data)
                
            # Trigger an RPC call that logs audit info
            call(sock, token, "rpc.ping")
            time.sleep(0.1) # brief sleep for IO persistence
            
            # Check if rotation happened correctly:
            # - log3_path should contain "legacy log 2"
            # - log2_path should contain "legacy log 1"
            # - log1_path should contain the 5MB log
            # - AUDIT_LOG_PATH should contain the new audit log entry
            assert os.path.exists(log3_path), "log.3 should exist"
            assert os.path.exists(log2_path), "log.2 should exist"
            assert os.path.exists(log1_path), "log.1 should exist"
            assert os.path.exists(AUDIT_LOG_PATH), "active log should exist"
            
            with open(log3_path, "r") as f:
                content3 = f.read()
                print(f"log.3 content: {content3.strip()}")
                assert content3 == "legacy log 2\n"
                
            with open(log2_path, "r") as f:
                content2 = f.read()
                print(f"log.2 content: {content2.strip()}")
                assert content2 == "legacy log 1\n"
                
            assert os.path.getsize(log1_path) > 5 * 1024 * 1024, "log.1 should be the oversized log"
            assert os.path.getsize(AUDIT_LOG_PATH) < 1000, "Active log should be small"
            
            print("\nAll v1.6.2 Manifest Discipline Verification Cases Passed Successfully!")
            return 0

        finally:
            if os.path.exists(test_file_path):
                os.remove(test_file_path)
            for i in range(1, 9):
                shutil.rmtree(os.path.join(BACKUPS_DIR, f"test-combo-c{i}"), ignore_errors=True)

if __name__ == "__main__":
    raise SystemExit(main())
