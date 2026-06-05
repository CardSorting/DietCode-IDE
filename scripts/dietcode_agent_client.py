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
SOCKET_PATH = os.path.expanduser(os.environ.get("DIETCODE_SOCKET_PATH", "~/.dietcode/control.sock"))
TOKEN_PATH = os.path.expanduser(os.environ.get("DIETCODE_TOKEN_PATH", "~/.dietcode/session.token"))
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
MAX_REQUEST_BYTES = 1024 * 1024
MAX_RESPONSE_BYTES = 4 * 1024 * 1024


def _connect_probe(timeout: float = 0.5, socket_path: str = SOCKET_PATH) -> bool:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as test_sock:
            test_sock.settimeout(timeout)
            test_sock.connect(socket_path)
            return True
    except (ConnectionRefusedError, FileNotFoundError, socket.timeout, OSError):
        return False


def _unlink_stale_socket(socket_path: str = SOCKET_PATH) -> None:
    try:
        st = os.lstat(socket_path)
    except FileNotFoundError:
        return
    if stat.S_ISSOCK(st.st_mode) and st.st_uid == os.getuid():
        try:
            os.unlink(socket_path)
        except OSError:
            pass


def resolve_app_path(app_path: str | os.PathLike[str] | None = None) -> Path:
    configured = app_path or os.environ.get("DIETCODE_APP_PATH")
    return Path(configured).expanduser() if configured else DEFAULT_APP_PATH


def ensure_socket(
    app_path: str | os.PathLike[str] | None = None,
    timeout: float = 10.0,
    quiet: bool = False,
    socket_path: str = SOCKET_PATH,
    start: bool = True,
) -> bool:
    """Ensure the control socket is accepting connections, launching headless if needed."""
    if _connect_probe(socket_path=socket_path):
        return True
    if not start:
        return False

    _unlink_stale_socket(socket_path)
    app_binary = resolve_app_path(app_path)
    if not app_binary.exists():
        raise RuntimeError(f"DietCode binary not found at {app_binary}. Run 'make app' first.")

    if not quiet:
        print("control socket not active, asking DietCode to ensure headless control...", file=sys.stderr)

    try:
        completed = subprocess.run(
            [str(app_binary), "--ensure-socket", "--ensure-timeout", str(timeout)],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout + 2.0,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    if not quiet:
        for line in (completed.stdout + completed.stderr).splitlines():
            print(line, file=sys.stderr)
    if completed.returncode != 0:
        return False
    return _connect_probe(socket_path=socket_path)


def load_token(token_path: str = TOKEN_PATH) -> str:
    if not os.path.exists(token_path):
        raise RuntimeError(f"session token not found: {token_path}")
    with open(token_path, "r", encoding="utf-8") as f:
        return f.read().strip()


def load_params(args: argparse.Namespace) -> dict[str, Any]:
    sources = [args.params_json is not None, args.params_file is not None, args.params_stdin]
    if sum(sources) > 1:
        raise ValueError("provide only one of params_json, --params-file, or --params-stdin")
    if args.params_stdin:
        raw = sys.stdin.read()
    elif args.params_file:
        with open(args.params_file, "r", encoding="utf-8") as f:
            raw = f.read()
    else:
        raw = args.params_json or "{}"
    params = json.loads(raw)
    if not isinstance(params, dict):
        raise ValueError("params must decode to a JSON object")
    return params


def send_rpc(
    sock: socket.socket,
    token: str,
    method: str,
    params: dict[str, Any] | None = None,
    request_id: str | None = None,
    request_timeout: float | None = None,
    max_request_bytes: int = MAX_REQUEST_BYTES,
    max_response_bytes: int = MAX_RESPONSE_BYTES,
) -> dict[str, Any]:
    payload = {
        "id": request_id or method,
        "schemaVersion": SCHEMA_VERSION,
        "method": method,
        "params": params or {},
        "token": token,
    }
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(encoded) > max_request_bytes:
        raise RuntimeError(f"request exceeds maximum allowed size of {max_request_bytes} bytes")
    if request_timeout is not None:
        sock.settimeout(request_timeout)
    sock.sendall(encoded)
    data = bytearray()
    while not data.endswith(b"\n"):
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"socket closed while waiting for {method}")
        data.extend(chunk)
        if len(data) > max_response_bytes + 1:
            raise RuntimeError(f"response exceeds maximum allowed size of {max_response_bytes} bytes")
    return json.loads(data.decode("utf-8"))


def call(
    sock: socket.socket,
    token: str,
    method: str,
    params: dict[str, Any] | None = None,
    request_id: str | None = None,
    request_timeout: float | None = None,
) -> dict[str, Any]:
    response = send_rpc(sock, token, method, params, request_id, request_timeout=request_timeout)
    if not response.get("ok"):
        err = response.get("error", {})
        raise RuntimeError(f"{method} failed: {err.get('code')}: {err.get('message')}")
    return response.get("result", {})


def connect(
    timeout: float = 10.0,
    app_path: str | os.PathLike[str] | None = None,
    socket_path: str = SOCKET_PATH,
    start: bool = True,
) -> socket.socket:
    if not ensure_socket(app_path=app_path, timeout=timeout, socket_path=socket_path, start=start):
        raise RuntimeError(f"failed to start DietCode control socket at {socket_path}")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(socket_path)
    return sock


def main() -> int:
    parser = argparse.ArgumentParser(description="Ensure and call the DietCode headless control socket.")
    parser.add_argument("--app", help="Path to DietCode binary. Defaults to build/DietCode.app/Contents/MacOS/DietCode.")
    parser.add_argument("--socket", default=SOCKET_PATH, help="Unix socket path. Defaults to DIETCODE_SOCKET_PATH or ~/.dietcode/control.sock.")
    parser.add_argument("--token-file", default=TOKEN_PATH, help="Session token path. Defaults to DIETCODE_TOKEN_PATH or ~/.dietcode/session.token.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Seconds to wait for socket startup and connect.")
    parser.add_argument("--request-timeout", type=float, default=30.0, help="Seconds to wait for one RPC response.")
    parser.add_argument("--no-start", action="store_true", help="Do not launch DietCode if the socket is inactive.")
    parser.add_argument("--quiet", action="store_true", help="Suppress diagnostic output on stderr.")
    parser.add_argument("--ensure-only", action="store_true", help="Only ensure the socket is active, then exit.")
    parser.add_argument("--raw-response", action="store_true", help="Print the full JSON-RPC response envelope.")
    parser.add_argument("--compact", action="store_true", help="Print compact JSON on one line.")
    parser.add_argument("--params-file", help="Read RPC params JSON object from a file.")
    parser.add_argument("--params-stdin", action="store_true", help="Read RPC params JSON object from stdin.")
    parser.add_argument("method", nargs="?", default="rpc.ping", help="RPC method to call after ensuring the socket.")
    parser.add_argument("params_json", nargs="?", help="JSON object params for the RPC call.")
    args = parser.parse_args()

    try:
        if args.ensure_only:
            if ensure_socket(app_path=args.app, timeout=args.timeout, quiet=args.quiet, socket_path=args.socket, start=not args.no_start):
                print(json.dumps({"ok": True, "socket": args.socket}, separators=(",", ":") if args.compact else None))
                return 0
            raise RuntimeError(f"failed to start DietCode control socket at {args.socket}")

        params = load_params(args)
        with connect(timeout=args.timeout, app_path=args.app, socket_path=args.socket, start=not args.no_start) as sock:
            token = load_token(args.token_file)
            if args.raw_response:
                response = send_rpc(sock, token, args.method, params, request_timeout=args.request_timeout)
            else:
                response = call(sock, token, args.method, params, request_timeout=args.request_timeout)
        if args.compact:
            print(json.dumps(response, separators=(",", ":"), sort_keys=True))
        else:
            print(json.dumps(response, indent=2, sort_keys=True))
        return 0
    except Exception as exc:
        if not args.quiet:
            print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
