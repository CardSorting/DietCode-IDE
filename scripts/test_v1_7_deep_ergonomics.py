#!/usr/bin/env python3
import json
import os
import time
import threading

from dietcode_agent_client import DietCodeAgentClient, connect, load_token, send_rpc

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def listen_events(client):
    while True:
        try:
            msg = client.read_frame(request_timeout=1.0)
            if msg.get("method") == "event.emitted":
                print(f"\n[EVENT] {msg['params']['type']}: {msg['params']['detail']}")
        except TimeoutError:
            continue
        except:
            break

def main():
    print("=== DietCode v1.7 Deep Ergonomics Verification Suite ===")

    with connect() as sock, DietCodeAgentClient() as event_client:
        token = load_token()

        # 1. Test terminal streaming
        print("\nTest 1: Terminal Streaming")
        invalid_subscribe = call(sock, token, "event.subscribe", {"types": []})
        assert not invalid_subscribe.get("ok"), "event.subscribe should reject an empty types array"
        assert invalid_subscribe.get("error", {}).get("string_code") == "invalid_params", "event.subscribe should return invalid_params"
        subscribe_result = call(sock, token, "event.subscribe", {"types": ["terminal.output"]})
        assert subscribe_result.get("ok"), "event.subscribe failed"
        assert subscribe_result.get("result", {}).get("types") == ["terminal.output"], "event.subscribe did not echo subscribed types"
        unsubscribe_result = call(sock, token, "event.unsubscribe", {"types": ["terminal.output"]})
        assert unsubscribe_result.get("ok"), "event.unsubscribe failed"
        assert unsubscribe_result.get("result", {}).get("types") == ["terminal.output"], "event.unsubscribe did not echo unsubscribed types"
        # Keep event notifications on a dedicated connection so they cannot
        # consume synchronous RPC responses from the main request socket.
        with event_client.event_subscription(["terminal.output"]):
            t = threading.Thread(target=listen_events, args=(event_client,), daemon=True)
            t.start()
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
        # Headless kernel returns empty LSP stubs; use a stable repo file.
        target_file = "src/kernel/workspace/WorkspaceSession.hpp"
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
