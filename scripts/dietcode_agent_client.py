#!/usr/bin/env python3
"""Small agent-facing client helpers for the DietCode control socket."""

from __future__ import annotations

import argparse
import json
import os
import socket
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1.6.2"
SOCKET_PATH = os.path.expanduser("~/.dietcode/control.sock")
TOKEN_PATH = os.path.expanduser("~/.dietcode/session.token")
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"


def _connect_probe(timeout: float = 0.5) -> bool:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as test_sock:
            test_sock.settimeout(timeout)
            test_sock.connect(SOCKET_PATH)
            return True
    except (ConnectionRefusedError, FileNotFoundError, socket.timeout, OSError):
        return False


def _unlink_stale_socket() -> None:
    try:
        st = os.lstat(SOCKET_PATH)
    except FileNotFoundError:
        return
    if stat.S_ISSOCK(st.st_mode) and st.st_uid == os.getuid():
        try:
            os.unlink(SOCKET_PATH)
        except OSError:
            pass


def resolve_app_path(app_path: str | os.PathLike[str] | None = None) -> Path:
    configured = app_path or os.environ.get("DIETCODE_APP_PATH")
    return Path(configured).expanduser() if configured else DEFAULT_APP_PATH


def ensure_socket(
    app_path: str | os.PathLike[str] | None = None,
    timeout: float = 10.0,
    quiet: bool = False,
) -> bool:
    """Ensure the control socket is accepting connections, launching headless if needed."""
    if _connect_probe():
        return True

    _unlink_stale_socket()
    app_binary = resolve_app_path(app_path)
    if not app_binary.exists():
        raise RuntimeError(f"DietCode binary not found at {app_binary}. Run 'make app' first.")

    if not quiet:
        print("control socket not active, asking DietCode to ensure headless control...")

    output_target = subprocess.DEVNULL if quiet else None
    try:
        completed = subprocess.run(
            [str(app_binary), "--ensure-socket", "--ensure-timeout", str(timeout)],
            stdin=subprocess.DEVNULL,
            stdout=output_target,
            stderr=output_target,
            timeout=timeout + 2.0,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    return completed.returncode == 0 or _connect_probe()


def load_token() -> str:
    if not os.path.exists(TOKEN_PATH):
        raise RuntimeError(f"session token not found: {TOKEN_PATH}")
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        return f.read().strip()


def send_rpc(
    sock: socket.socket,
    token: str,
    method: str,
    params: dict[str, Any] | None = None,
    request_id: str | None = None,
) -> dict[str, Any]:
    payload = {
        "id": request_id or method,
        "schemaVersion": SCHEMA_VERSION,
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
    return json.loads(data.decode("utf-8"))


def call(
    sock: socket.socket,
    token: str,
    method: str,
    params: dict[str, Any] | None = None,
    request_id: str | None = None,
) -> dict[str, Any]:
    response = send_rpc(sock, token, method, params, request_id)
    if not response.get("ok"):
        err = response.get("error", {})
        raise RuntimeError(f"{method} failed: {err.get('code')}: {err.get('message')}")
    return response.get("result", {})


def connect(timeout: float = 10.0, app_path: str | os.PathLike[str] | None = None) -> socket.socket:
    if not ensure_socket(app_path=app_path, timeout=timeout):
        raise RuntimeError(f"failed to start DietCode control socket at {SOCKET_PATH}")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(SOCKET_PATH)
    return sock


def main() -> int:
    parser = argparse.ArgumentParser(description="Ensure and call the DietCode headless control socket.")
    parser.add_argument("--app", help="Path to DietCode binary. Defaults to build/DietCode.app/Contents/MacOS/DietCode.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Seconds to wait for socket startup.")
    parser.add_argument("--quiet", action="store_true", help="Suppress startup status output.")
    parser.add_argument("--ensure-only", action="store_true", help="Only ensure the socket is active, then exit.")
    parser.add_argument("--raw-response", action="store_true", help="Print the full JSON-RPC response envelope.")
    parser.add_argument("method", nargs="?", default="rpc.ping", help="RPC method to call after ensuring the socket.")
    parser.add_argument("params_json", nargs="?", default="{}", help="JSON object params for the RPC call.")
    args = parser.parse_args()

    try:
        if args.ensure_only:
            if ensure_socket(app_path=args.app, timeout=args.timeout, quiet=args.quiet):
                if not args.quiet:
                    print(f"control socket active at {SOCKET_PATH}")
                return 0
            raise RuntimeError(f"failed to start DietCode control socket at {SOCKET_PATH}")

        params = json.loads(args.params_json)
        if not isinstance(params, dict):
            raise ValueError("params_json must decode to an object")
        with connect(timeout=args.timeout, app_path=args.app) as sock:
            token = load_token()
            if args.raw_response:
                response = send_rpc(sock, token, args.method, params)
            else:
                response = call(sock, token, args.method, params)
        print(json.dumps(response, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        if not args.quiet:
            print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
