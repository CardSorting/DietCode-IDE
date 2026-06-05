#!/usr/bin/env python3
import json
import os
import socket
import sys


SOCKET_PATH = os.path.expanduser("~/.dietcode/control.sock")
TOKEN_PATH = os.path.expanduser("~/.dietcode/session.token")


def load_token():
    if not os.path.exists(TOKEN_PATH):
        raise RuntimeError(f"session token not found: {TOKEN_PATH}")
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return f.read().strip()


def call(sock, token, method, params=None, request_id=None):
    payload = {
        "id": request_id or method,
        "schemaVersion": "1.6.2",
        "method": method,
        "params": params or {},
        "token": token,
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
    socket_active = False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as test_sock:
            test_sock.settimeout(0.5)
            test_sock.connect(SOCKET_PATH)
            socket_active = True
    except (ConnectionRefusedError, FileNotFoundError, socket.timeout):
        if os.path.exists(SOCKET_PATH):
            try:
                os.unlink(SOCKET_PATH)
            except Exception:
                pass

    if not socket_active:
        print("control socket not active, launching DietCode in headless mode...")
        import subprocess, time
        app_path = "build/DietCode.app/Contents/MacOS/DietCode"
        if not os.path.exists(app_path):
            print(f"DietCode binary not found at {app_path}. Run 'make app' first.", file=sys.stderr)
            return 1
        subprocess.Popen([app_path, "--headless"])
        for _ in range(50):
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as test_sock:
                    test_sock.connect(SOCKET_PATH)
                    socket_active = True
                    break
            except Exception:
                time.sleep(0.1)
        if not socket_active:
            print("Failed to start DietCode headless process or socket did not initialize.", file=sys.stderr)
            return 1

    token = load_token()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET_PATH)

        checks = [
            ("rpc.ping", {}),
            ("workspace.getRoot", {}),
            ("editor.getOpenFiles", {}),
            ("problems.list", {}),
        ]

        for method, params in checks:
            result = call(sock, token, method, params)
            print(f"ok {method}: {sorted(result.keys())}")
            if method == "workspace.getRoot" and result.get("path"):
                for workspace_method, workspace_params in [
                    ("workspace.grep", {"query": "DietCode", "maxResults": 1}),
                    ("git.status", {}),
                ]:
                    workspace_result = call(sock, token, workspace_method, workspace_params)
                    print(f"ok {workspace_method}: {sorted(workspace_result.keys())}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
