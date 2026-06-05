#!/usr/bin/env python3
import socket
import sys

from dietcode_agent_client import SOCKET_PATH, call, ensure_socket, load_token


def main():
    if not ensure_socket():
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
