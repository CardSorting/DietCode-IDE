#!/usr/bin/env python3
import json
import os
import socket
import sys
import time
import shutil
import hashlib
import plistlib

from dietcode_agent_client import SOCKET_PATH, ensure_socket, load_token, send_rpc

BACKUPS_DIR = os.path.expanduser("~/.dietcode/backups")
AUDIT_LOG_DIR = os.path.expanduser("~/.dietcode")
AUDIT_LOG_PATH = os.path.join(AUDIT_LOG_DIR, "control_audit.log")

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def get_sha256(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()

def main():
    print("=== DietCode v1.6.5 Release Constant Hygiene Verification Suite ===")
    
    if not ensure_socket():
        print("Failed to start DietCode headless process or socket did not initialize.", file=sys.stderr)
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

        # Clean all backups directory first for clean test
        shutil.rmtree(BACKUPS_DIR, ignore_errors=True)
        os.makedirs(BACKUPS_DIR, exist_ok=True)

        # Create target test file
        test_file_path = os.path.join(workspace_root, "test_target_v1_6_5.txt")
        with open(test_file_path, "w") as f:
            f.write("Line 1: base content\n")

        try:
            # 1. Create a valid v1.6.2 backup
            print("\nCreating valid v1.6.2 backup...")
            valid_cid = "combo-valid-g1"
            valid_dir = os.path.join(BACKUPS_DIR, valid_cid)
            os.makedirs(valid_dir, exist_ok=True)
            valid_manifest = {
                "schemaVersion": "1.6.2",
                "comboId": valid_cid,
                "createdAt": "2026-06-05T00:00:00Z",
                "workspaceRootHash": "dummy",
                "chipVersions": [],
                "files": []
            }
            valid_canonical = json.dumps(valid_manifest, separators=(",", ":"), sort_keys=True)
            with open(os.path.join(valid_dir, "manifest.json"), "w") as f:
                f.write(valid_canonical)
            with open(os.path.join(valid_dir, "manifest.sha256"), "w") as f:
                f.write(get_sha256(valid_canonical) + "\n")

            # 2. Create a legacy v1.6.1 backup
            print("Creating legacy v1.6.1 backup...")
            legacy_cid = "combo-legacy-g2"
            legacy_dir = os.path.join(BACKUPS_DIR, legacy_cid)
            os.makedirs(legacy_dir, exist_ok=True)
            legacy_manifest = {
                "schemaVersion": "1.6.1",
                "comboId": legacy_cid,
                "createdAt": "2026-05-01T12:00:00Z", # Old date
                "workspaceRootHash": "dummy",
                "chipVersions": [],
                "files": []
            }
            legacy_canonical = json.dumps(legacy_manifest, separators=(",", ":"), sort_keys=True)
            with open(os.path.join(legacy_dir, "manifest.json"), "w") as f:
                f.write(legacy_canonical)

            # 3. Create a corrupt backup (no checksum/missing files)
            print("Creating corrupt backup...")
            corrupt_cid = "combo-corrupt-g3"
            corrupt_dir = os.path.join(BACKUPS_DIR, corrupt_cid)
            os.makedirs(corrupt_dir, exist_ok=True)
            corrupt_manifest = {
                "schemaVersion": "1.6.2",
                "comboId": corrupt_cid,
                "createdAt": "2026-04-15T08:00:00Z", # Older date
                "workspaceRootHash": "dummy",
                "chipVersions": [],
                "files": []
            }
            # Write manifest but NO checksum, making it corrupt
            with open(os.path.join(corrupt_dir, "manifest.json"), "w") as f:
                f.write(json.dumps(corrupt_manifest, separators=(",", ":"), sort_keys=True))

            # Test recovery.list
            print("\nTesting recovery.list...")
            list_res = call(sock, token, "recovery.list")
            print(f"recovery.list result: {list_res}")
            assert list_res.get("ok")
            backups = list_res.get("result", {}).get("backups", [])
            assert len(backups) == 3, f"Expected 3 backups, got {len(backups)}"
            
            status_map = {b["comboId"]: b["status"] for b in backups}
            assert status_map[valid_cid] == "valid", f"Expected valid, got {status_map[valid_cid]}"
            assert status_map[legacy_cid] == "legacy", f"Expected legacy, got {status_map[legacy_cid]}"
            assert status_map[corrupt_cid] == "corrupt", f"Expected corrupt, got {status_map[corrupt_cid]}"

            # Test deleteBackup with corrupt requiring confirmation
            print("\nTesting deleteBackup on corrupt without confirmation (should reject)...")
            del_res = call(sock, token, "recovery.deleteBackup", {"comboId": corrupt_cid, "confirm": False})
            print(f"deleteBackup result: {del_res}")
            assert not del_res.get("ok")
            assert del_res.get("error", {}).get("string_code") == "confirmation_required"

            # Test deleteBackup with corrupt with confirmation
            print("Testing deleteBackup on corrupt with confirmation (should succeed)...")
            del_res = call(sock, token, "recovery.deleteBackup", {"comboId": corrupt_cid, "confirm": True})
            print(f"deleteBackup result: {del_res}")
            assert del_res.get("ok")
            assert not os.path.exists(corrupt_dir), "Corrupt directory should be deleted"

            # Re-create corrupt for prune tests
            os.makedirs(corrupt_dir, exist_ok=True)
            with open(os.path.join(corrupt_dir, "manifest.json"), "w") as f:
                f.write(json.dumps(corrupt_manifest, separators=(",", ":"), sort_keys=True))

            # Test prune dry-run keepLastN
            print("\nTesting recovery.prune dryRun=True keepLastN=1...")
            prune_res = call(sock, token, "recovery.prune", {"keepLastN": 1, "dryRun": True})
            print(f"Prune dry-run keepLastN=1 result: {prune_res}")
            assert prune_res.get("ok")
            res_info = prune_res.get("result", {})
            assert res_info.get("dryRun") is True
            assert legacy_cid in res_info.get("pruned")
            assert any(s["comboId"] == corrupt_cid for s in res_info.get("skipped")), "Corrupt should be skipped due to confirmation requirement"

            # Test prune dry-run keepLastN with confirmInvalid
            print("Testing recovery.prune dryRun=True keepLastN=1 confirmInvalid=True...")
            prune_res = call(sock, token, "recovery.prune", {"keepLastN": 1, "dryRun": True, "confirmInvalid": True})
            print(f"Prune dry-run result: {prune_res}")
            assert prune_res.get("ok")
            res_info = prune_res.get("result", {})
            assert legacy_cid in res_info.get("pruned")
            assert corrupt_cid in res_info.get("pruned"), "Corrupt should now be pruned with confirmInvalid=True"

            # Test prune dry-run olderThanDays
            print("\nTesting recovery.prune dryRun=True olderThanDays=10...")
            prune_res = call(sock, token, "recovery.prune", {"olderThanDays": 10, "dryRun": True, "confirmInvalid": True})
            print(f"Prune dry-run olderThanDays=10 result: {prune_res}")
            assert prune_res.get("ok")
            res_info = prune_res.get("result", {})
            assert legacy_cid in res_info.get("pruned")
            assert corrupt_cid in res_info.get("pruned")
            assert valid_cid not in res_info.get("pruned"), "Valid backup is brand new and shouldn't be pruned"

            # Test actual prune execution
            print("\nExecuting actual recovery.prune olderThanDays=10 confirmInvalid=True...")
            prune_res = call(sock, token, "recovery.prune", {"olderThanDays": 10, "dryRun": False, "confirmInvalid": True})
            print(f"Actual prune result: {prune_res}")
            assert prune_res.get("ok")
            assert not os.path.exists(legacy_dir), "Legacy backup should be deleted"
            assert not os.path.exists(corrupt_dir), "Corrupt backup should be deleted"
            assert os.path.exists(valid_dir), "Valid backup should still exist"

            # Test active backup handling using a second socket connection during an active combo
            print("\nTesting active backup GC rejection...")
            
            # Setup a verify loop/step that runs a command that sleeps to keep the combo active
            combo_plan = {
                "schemaVersion": "1.6.2",
                "goal": "Keep active for testing",
                "policy": {
                    "permissions": ["execute", "read"]
                },
                "budget": {
                    "maxSteps": 2,
                    "maxFilesTouched": 2
                },
                "scope": {
                    "include": ["test_target_v1_6_5.txt"]
                },
                "steps": [
                    {
                        "id": "s1",
                        "chip": "verify.run@1",
                        "params": {
                            "command": "sleep 3"
                        }
                    }
                ]
            }

            active_cid = f"combo-active-{int(time.time() * 1000)}"
            
            # Start the combo asynchronously
            payload = {
                "id": "run-active",
                "schemaVersion": "1.6.2",
                "method": "combo.run",
                "params": {"combo": combo_plan, "comboId": active_cid},
                "token": token
            }
            
            sock.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
            time.sleep(1.0) # wait for combo to become active
            
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock2:
                sock2.connect(SOCKET_PATH)
                
                # Check status
                list_res = call(sock2, token, "recovery.list")
                print(f"recovery.list during active combo: {list_res}")
                backups = list_res.get("result", {}).get("backups", [])
                
                status_map = {b["comboId"]: b["status"] for b in backups}
                print(f"Combo statuses during execution: {status_map}")
                assert status_map.get(active_cid) == "active", f"Expected active status, got {status_map.get(active_cid)}"
                
                # Try to delete active backup (should fail)
                del_res = call(sock2, token, "recovery.deleteBackup", {"comboId": active_cid, "confirm": True})
                print(f"deleteBackup on active result: {del_res}")
                assert not del_res.get("ok")
                assert del_res.get("error", {}).get("string_code") == "invalid_state"
                
                # Try to prune active backup even with confirmInvalid=true (should be skipped)
                prune_res = call(sock2, token, "recovery.prune", {"keepLastN": 0, "dryRun": False, "confirmInvalid": True})
                print(f"Prune with active result (confirmInvalid=True): {prune_res}")
                assert prune_res.get("ok")
                skipped_list = prune_res.get("result", {}).get("skipped", [])
                assert any(s["comboId"] == active_cid for s in skipped_list), "Active combo should have been skipped in prune even with confirmInvalid=True"
            
            # Read response of the active run from first socket
            data = bytearray()
            while not data.endswith(b"\n"):
                chunk = sock.recv(65536)
                if not chunk:
                    break
                data.extend(chunk)
            print(f"Active combo run completed with: {data.decode('utf-8').strip()}")

            # Verify deletion audit logs exist and are detailed with comboId/path
            print("\nVerifying control_audit.log contains deletion entries with detailed path/comboId...")
            assert os.path.exists(AUDIT_LOG_PATH), "Audit log file should exist"
            with open(AUDIT_LOG_PATH, "r") as f:
                audit_content = f.read()
                print(f"Last audit entries:\n" + "\n".join(audit_content.splitlines()[-5:]))
                
                # check for corrupt deletion audits
                assert "recovery.deleteBackup" in audit_content or "recovery.prune" in audit_content
                assert "deleted comboId: combo-valid-g1" in audit_content
                assert "path:" in audit_content and "backups/combo-valid-g1" in audit_content

            # Test 12: Version Constant Hygiene
            print("\nTest 12: Checking Version Constant Hygiene")
            v_res = call(sock, token, "rpc.version")
            print(f"rpc.version result: {v_res}")
            assert v_res.get("ok"), "rpc.version failed"
            app_version = v_res.get("result", {}).get("appVersion")
            assert app_version == "1.6.5", f"Expected 1.6.5, got {app_version}"

            ping_res = call(sock, token, "rpc.ping")
            assert ping_res.get("result", {}).get("version") == "1.6.5"

            # Check Info.plist in build directory
            plist_path = "build/DietCode.app/Contents/Info.plist"
            assert os.path.exists(plist_path), "Info.plist in build dir missing"
            with open(plist_path, "rb") as f:
                plist = plistlib.load(f)
            plist_version = plist.get("CFBundleShortVersionString")
            print(f"Info.plist CFBundleShortVersionString: {plist_version}")
            assert plist_version == "1.6.5", f"Info.plist version mismatch! Got {plist_version}"

            print("\nAll v1.6.5 Release Constant Hygiene Verification Cases Passed Successfully!")
            return 0

        finally:
            if os.path.exists(test_file_path):
                os.remove(test_file_path)
            shutil.rmtree(os.path.join(BACKUPS_DIR, valid_cid), ignore_errors=True)
            shutil.rmtree(os.path.join(BACKUPS_DIR, legacy_cid), ignore_errors=True)
            shutil.rmtree(os.path.join(BACKUPS_DIR, corrupt_cid), ignore_errors=True)
            shutil.rmtree(os.path.join(BACKUPS_DIR, active_cid), ignore_errors=True)

if __name__ == "__main__":
    raise SystemExit(main())
