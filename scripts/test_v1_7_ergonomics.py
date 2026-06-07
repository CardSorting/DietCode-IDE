#!/usr/bin/env python3
import json
import os
import time

from dietcode_agent_client import connect, load_token, send_rpc

def call(sock, token, method, params=None, request_id=None):
    return send_rpc(sock, token, method, params, request_id)

def main():
    print("=== DietCode v1.7 Ergonomics Verification Suite ===")

    with connect() as sock:
        token = load_token()
        
        # 1. Test workspace.findFiles
        print("\nTest 1: workspace.findFiles (glob)")
        res = call(sock, token, "workspace.findFiles", {"pattern": "src/core/*.hpp"})
        print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "workspace.findFiles failed"
        files = res.get("result", {}).get("files", [])
        assert len(files) > 0, "Should find at least one header in src/core"
        assert all(f.endswith(".hpp") for f in files), "All found files should match pattern"

        # 2. Test file.readBatch
        print("\nTest 2: file.readBatch")
        paths = files[:2]
        res = call(sock, token, "file.readBatch", {"paths": paths})
        # print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "file.readBatch failed"
        results = res.get("result", {}).get("results", {})
        for p in paths:
            assert p in results, f"Result for {p} missing"
            assert results[p].get("ok"), f"Read for {p} failed"
            assert "text" in results[p], f"Text for {p} missing"

        # 3. Test file.statBatch
        print("\nTest 3: file.statBatch")
        res = call(sock, token, "file.statBatch", {"paths": paths})
        print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "file.statBatch failed"
        results = res.get("result", {}).get("results", {})
        for p in paths:
            assert p in results, f"Stat for {p} missing"
            assert results[p].get("ok"), f"Stat for {p} failed"
            assert "sizeBytes" in results[p], f"sizeBytes for {p} missing"
            assert "lineCount" in results[p], f"lineCount for {p} missing"

        # 4. Test symbols.hierarchy
        print("\nTest 4: symbols.hierarchy")
        # Use a file likely to have nested symbols, e.g., src/platform/macos/control/MacControlServer.mm
        # (Though our simple parser might not find many nested ones, let's try)
        res = call(sock, token, "symbols.hierarchy", {"path": "src/platform/macos/control/MacControlServer.mm"})
        # print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "symbols.hierarchy failed"
        symbols = res.get("result", {}).get("symbols", [])
        assert isinstance(symbols, list), "Symbols should be a list"
        if symbols:
            print(f"Found {len(symbols)} root symbols")
            # Check for children
            has_children = any(len(s.get("children", [])) > 0 for s in symbols)
            print(f"Nested symbols found: {has_children}")
            # Even if no children found (due to simple parser), check record format
            s = symbols[0]
            assert "offset" in s, "Offset missing"
            assert "endOffset" in s, "endOffset missing"
            assert "children" in s, "children field missing"

        # 5. Test workspace.grep enrichment
        print("\nTest 5: workspace.grep enrichment")
        res = call(sock, token, "workspace.grep", {"query": "executeMethod", "maxResults": 5})
        print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "workspace.grep failed"
        matches = res.get("result", {}).get("matches", [])
        if matches:
            m = matches[0]
            spans = m.get("matchSpans", [])
            assert len(spans) > 0, "matchSpans missing"
            s = spans[0]
            assert "offset" in s, "Span offset missing"
            assert "length" in s, "Span length missing"

        # 6. Test system.info
        print("\nTest 6: system.info")
        res = call(sock, token, "system.info")
        print(f"Result: {json.dumps(res, indent=2)}")
        assert res.get("ok"), "system.info failed"
        info = res.get("result", {})
        assert "os" in info, "OS info missing"
        assert "arch" in info, "Arch info missing"
        assert "memoryGB" in info, "Memory info missing"
        assert "appVersion" in info, "App version missing"

    print("\n=== All v1.7 Ergonomics Verification Cases Passed Successfully ===")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
