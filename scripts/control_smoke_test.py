#!/usr/bin/env python3
import json
import os
import socket
import sys


SOCKET_PATH = os.path.expanduser("~/.dietcode/control.sock")


def call(sock, method, params=None, request_id=None):
    payload = {
        "id": request_id or method,
        "method": method,
        "params": params or {},
    }
    sock.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
    data = bytearray()
    while not data.endswith(b"\n"):
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"socket closed while waiting for {method}")
        data.extend(chunk)
    response = json.loads(data.decode("utf-8"))
    if not response.get("ok"):
        err = response.get("error", {})
        raise RuntimeError(f"{method} failed: {err.get('code')}: {err.get('message')}")
    return response.get("result", {})


def main():
    if not os.path.exists(SOCKET_PATH):
        print(f"control socket not found: {SOCKET_PATH}", file=sys.stderr)
        return 1

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET_PATH)

        checks = [
            ("rpc.ping", {}),
            ("workspace.getRoot", {}),
            ("workspace.grep", {"query": "DietCode", "maxResults": 1}),
            ("editor.getOpenFiles", {}),
            ("problems.list", {}),
            ("git.status", {}),
        ]

        for method, params in checks:
            result = call(sock, method, params)
            print(f"ok {method}: {sorted(result.keys())}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
