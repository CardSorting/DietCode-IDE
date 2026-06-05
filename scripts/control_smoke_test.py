#!/usr/bin/env python3

from dietcode_agent_client import call, connect, load_token


def main():
    with connect() as sock:
        token = load_token()
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
