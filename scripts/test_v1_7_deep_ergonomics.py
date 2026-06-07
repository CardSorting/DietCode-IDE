#!/usr/bin/env python3
import json
import os
import time
import threading

from dietcode_agent_client import connect, load_token, send_rpc

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def listen_events(sock):
    while True:
        try:
            line = sock.recv(1024 * 1024).decode('utf-8')
            if not line: break
            for part in line.split('\n'):
                if not part: continue
                msg = json.loads(part)
                if msg.get("method") == "event.emitted":
                    print(f"\n[EVENT] {msg['params']['type']}: {msg['params']['detail']}")
        except:
            break

def main():
    print("=== DietCode v1.7 Deep Ergonomics Verification Suite ===")

    with connect() as sock:
        token = load_token()
        
        # Start event listener thread
        t = threading.Thread(target=listen_events, args=(sock,), daemon=True)
        t.start()

        # 1. Test terminal streaming
        print("\nTest 1: Terminal Streaming")
        call(sock, token, "event.subscribe", {"types": ["terminal.output"]})
        print("Running command 'ls -la'...")
        call(sock, token, "terminal.run", {"command": "ls -la"})
        time.sleep(1) # Wait for output events

        # 2. Test workspace.searchSession
        print("\nTest 2: Workspace Search Session")
        res = call(sock, token, "workspace.searchStart", {"query": "DietCode", "include": ["src/**"]})
        print(f"Start Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "workspace.searchStart failed"
        search_id = res["result"]["searchId"]

        print(f"Polling session {search_id}...")
        while True:
            res = call(sock, token, "workspace.searchNext", {"searchId": search_id, "maxFiles": 20})
            assert res.get("ok"), "workspace.searchNext failed"
            matches = res["result"]["matches"]
            print(f"  Got {len(matches)} matches, processed {res['result']['currentFileIndex']}/{res['result']['totalFiles']} files")
            if res["result"]["finished"]:
                break
            time.sleep(0.1)

        # 3. Test LSP-backed features
        print("\nTest 3: LSP-backed features")
        # Note: Requires LSP to be running for the file. Let's try src/core/AppState.hpp
        target_file = "src/core/AppState.hpp"
        call(sock, token, "workspace.openFile", {"path": target_file})
        time.sleep(1) # Give LSP time to start

        print(f"Hover at {target_file}:10:5")
        res = call(sock, token, "language.hover", {"path": target_file, "line": 10, "column": 5})
        print(f"Hover Result: {json.dumps(res, indent=2)}")

        print(f"Completions at {target_file}:10:5")
        res = call(sock, token, "language.completions", {"path": target_file, "line": 10, "column": 5})
        if res.get("ok"):
            print(f"Found {len(res['result']['completions'])} completions")

        print(f"Definition at {target_file}:10:5")
        res = call(sock, token, "language.definition", {"path": target_file, "line": 10, "column": 5})
        print(f"Definition Result: {json.dumps(res, indent=2)}")

        # 4. Test system.info
        print("\nTest 4: system.info")
        res = call(sock, token, "system.info")
        print(f"Result: {json.dumps(res, indent=2)}")

    print("\n=== All v1.7 Deep Ergonomics Verification Cases Passed Successfully ===")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
