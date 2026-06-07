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
import time
import uuid
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1.6.2"
SOCKET_PATH = os.path.expanduser(os.environ.get("DIETCODE_SOCKET_PATH", "~/.dietcode/control.sock"))
TOKEN_PATH = os.path.expanduser(os.environ.get("DIETCODE_TOKEN_PATH", "~/.dietcode/session.token"))
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP_PATH = REPO_ROOT / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
MAX_REQUEST_BYTES = 1024 * 1024
MAX_RESPONSE_BYTES = 4 * 1024 * 1024

READ_METHODS = {
    "rpc.ping", "rpc.version", "rpc.methods", "rpc.describe", "chip.list", "chip.describe",
    "combo.status", "combo.result", "combo.list", "recovery.scan", "recovery.schemaInfo", "recovery.list",
    "workspace.getRoot", "workspace.findFiles", "workspace.listFiles", "workspace.grep",
    "workspace.searchStart", "workspace.searchNext", "workspace.searchCancel", "workspace.getRecentFiles",
    "search.files", "search.text", "search.todo", "search.semantic", "search.diagnostics",
    "file.read", "file.readBatch", "file.readRange", "file.readAround", "file.getChunks", "file.stat", "file.statBatch",
    "editor.getActiveFile", "editor.getOpenFiles", "editor.getText", "editor.getSelection",
    "analysis.workspaceSummary", "analysis.searchRanked", "analysis.fileSummary", "analysis.relatedFiles",
    "symbols.document", "symbols.hierarchy", "symbols.outline", "symbols.activeDocument",
    "symbols.references", "symbols.atCursor",
    "diff.workspaceInfo", "diff.stats", "diff.file", "diff.chunk", "diff.hunks",
    "diff.current", "diff.staged", "diff.unstaged", "diff.summary",
    "buffers.snapshot", "buffers.dirty", "buffers.active", "buffers.unsavedDiff",
    "changes.current", "changes.summary", "patch.chunk", "patch.hunks", "problems.list",
    "diagnostics.list", "diagnostics.summary", "diagnostics.cluster", "diagnostics.forFile",
    "language.diagnostics", "language.hover", "language.completions", "language.definition",
    "verify.last", "verify.status", "verify.failures", "terminal.status", "terminal.jobs", "terminal.history",
    "terminal.getOutput", "session.info", "session.workflowState", "session.recentCommands",
    "session.lastSearches", "system.info"
}



class DietCodeRpcError(RuntimeError):
    def __init__(self, method: str, response: dict[str, Any]) -> None:
        err = response.get("error", {})
        self.method = method
        self.response = response
        self.code = err.get("code")
        self.string_code = err.get("string_code")
        self.message = err.get("message")
        super().__init__(f"{method} failed: {self.code}: {self.message}")


class DietCodeTransportError(RuntimeError):
    pass


def local_error_response(request_id: str | None, code: str, message: str) -> dict[str, Any]:
    numeric_code = -32600
    if code == "invalid_params":
        numeric_code = -32602
    elif code == "transport_error":
        numeric_code = -32603
    return {
        "id": request_id or "unknown",
        "ok": False,
        "error": {
            "code": numeric_code,
            "string_code": code,
            "message": message,
        },
    }


def json_text(value: Any, compact: bool = False) -> str:
    if compact:
        return json.dumps(value, separators=(",", ":"), sort_keys=True)
    return json.dumps(value, indent=2, sort_keys=True)


def _path_state(path: str) -> dict[str, Any]:
    expanded = os.path.expanduser(path)
    state: dict[str, Any] = {"path": expanded, "exists": False}
    try:
        st = os.stat(expanded)
    except FileNotFoundError:
        return state
    except OSError as exc:
        state["error"] = str(exc)
        return state
    state.update(
        {
            "exists": True,
            "mode": oct(stat.S_IMODE(st.st_mode)),
            "uid": st.st_uid,
            "ownerIsCurrentUser": st.st_uid == os.getuid(),
        }
    )
    return state


def _probe_socket(timeout: float = 0.5, socket_path: str = SOCKET_PATH) -> tuple[bool, str | None]:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as test_sock:
            test_sock.settimeout(timeout)
            test_sock.connect(socket_path)
            return True, None
    except PermissionError as exc:
        return False, f"permission_denied: {exc}"
    except FileNotFoundError:
        return False, "not_found"
    except ConnectionRefusedError as exc:
        return False, f"connection_refused: {exc}"
    except socket.timeout:
        return False, "timeout"
    except OSError as exc:
        return False, f"os_error: {exc}"


def _connect_probe(timeout: float = 0.5, socket_path: str = SOCKET_PATH) -> bool:
    ok, _ = _probe_socket(timeout=timeout, socket_path=socket_path)
    return ok


def _append_probe_error(errors: list[str] | None, error: str | None) -> None:
    if errors is not None and error and (not errors or errors[-1] != error):
        errors.append(error)


def _wait_for_socket(
    socket_path: str = SOCKET_PATH,
    timeout: float = 10.0,
    interval: float = 0.2,
    errors: list[str] | None = None,
) -> bool:
    deadline = time.monotonic() + max(0.0, timeout)
    while time.monotonic() <= deadline:
        ok, error = _probe_socket(socket_path=socket_path)
        if ok:
            return True
        _append_probe_error(errors, error)
        time.sleep(interval)
    ok, error = _probe_socket(socket_path=socket_path)
    _append_probe_error(errors, error)
    return ok


def _socket_probe_diagnostic(socket_path: str, errors: list[str]) -> str | None:
    if not errors:
        return None
    last_error = errors[-1]
    if last_error.startswith("permission_denied:"):
        return (
            f"control socket exists at {socket_path}, but this process cannot connect to it "
            f"({last_error}). Run the harness with permission to access the DietCode socket."
        )
    return f"last socket probe error for {socket_path}: {last_error}"


def resolve_app_path(app_path: str | os.PathLike[str] | None = None) -> Path:
    configured = app_path or os.environ.get("DIETCODE_APP_PATH")
    return Path(configured).expanduser().resolve() if configured else DEFAULT_APP_PATH


def load_config(config_path: str | None) -> dict[str, Any]:
    configured = config_path or os.environ.get("DIETCODE_AGENT_CONFIG")
    if not configured:
        return {}
    path = Path(configured).expanduser()
    if not path.exists():
        raise RuntimeError(f"agent config not found: {path}")
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise RuntimeError("agent config must be a JSON object")
    return data


def config_value(args: argparse.Namespace, config: dict[str, Any], attr: str, key: str, default: Any) -> Any:
    value = getattr(args, attr)
    if value is not None:
        return value
    return config.get(key, default)


def ensure_socket(
    app_path: str | os.PathLike[str] | None = None,
    timeout: float = 10.0,
    quiet: bool = False,
    socket_path: str = SOCKET_PATH,
    start: bool = True,
    probe_errors: list[str] | None = None,
) -> bool:
    """Ensure the control socket is accepting connections, launching headless if needed."""
    if _wait_for_socket(socket_path=socket_path, timeout=min(timeout, 1.0), errors=probe_errors):
        return True
    if not start:
        return False

    app_binary = resolve_app_path(app_path)
    if not app_binary.exists():
        raise RuntimeError(f"DietCode binary not found at {app_binary}. Run 'make app' first.")

    if not quiet:
        print("control socket not active, asking DietCode to ensure headless control...", file=sys.stderr)
        diagnostic = _socket_probe_diagnostic(socket_path, probe_errors or [])
        if diagnostic:
            print(diagnostic, file=sys.stderr)

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
        return _wait_for_socket(socket_path=socket_path, timeout=2.0, errors=probe_errors)
    if not quiet:
        for line in (completed.stdout + completed.stderr).splitlines():
            print(line, file=sys.stderr)
    if _wait_for_socket(socket_path=socket_path, timeout=2.0, errors=probe_errors):
        return True
    if completed.returncode != 0:
        return False
    return _wait_for_socket(socket_path=socket_path, timeout=2.0, errors=probe_errors)


def load_token(token_path: str = TOKEN_PATH) -> str:
    if not os.path.exists(token_path):
        raise RuntimeError(f"session token not found: {token_path}")
    with open(token_path, "r", encoding="utf-8") as f:
        return f.read().strip()


def status(
    socket_path: str = SOCKET_PATH,
    token_path: str = TOKEN_PATH,
    app_path: str | os.PathLike[str] | None = None,
) -> dict[str, Any]:
    app_binary = resolve_app_path(app_path)
    socket_active, socket_probe_error = _probe_socket(socket_path=socket_path)
    token_state = _path_state(token_path)
    socket_state = _path_state(socket_path)
    rpc_ready = False
    rpc_ping: dict[str, Any] | None = None
    rpc_error: str | None = None
    if socket_active and token_state.get("exists"):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(2.0)
                sock.connect(socket_path)
                rpc_ping = send_rpc(sock, load_token(token_path), "rpc.ping", request_timeout=2.0)
                rpc_ready = bool(rpc_ping.get("ok"))
        except Exception as exc:
            rpc_error = str(exc)

    result: dict[str, Any] = {
        "ok": rpc_ready,
        "socketActive": socket_active,
        "rpcReady": rpc_ready,
        "socket": socket_state,
        "token": token_state,
        "app": {
            "path": str(app_binary),
            "exists": app_binary.exists(),
            "executable": os.access(app_binary, os.X_OK),
        },
        "schemaVersion": SCHEMA_VERSION,
        "limits": {
            "maxRequestBytes": MAX_REQUEST_BYTES,
            "maxResponseBytes": MAX_RESPONSE_BYTES,
        },
    }
    if rpc_ping is not None:
        result["rpcPing"] = rpc_ping
    if rpc_error is not None:
        result["rpcError"] = rpc_error
    if socket_probe_error is not None:
        result["socketProbeError"] = socket_probe_error
    return result


def wait_ready(
    app_path: str | os.PathLike[str] | None = None,
    socket_path: str = SOCKET_PATH,
    token_path: str = TOKEN_PATH,
    timeout: float = 10.0,
    interval: float = 0.2,
    start: bool = True,
    quiet: bool = False,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    if start:
        ensure_socket(app_path=app_path, timeout=timeout, quiet=quiet, socket_path=socket_path, start=True)
    last_state: dict[str, Any] = {}
    while time.monotonic() <= deadline:
        last_state = status(socket_path=socket_path, token_path=token_path, app_path=app_path)
        if last_state.get("ok"):
            return last_state
        time.sleep(interval)
    if last_state:
        return last_state
    return status(socket_path=socket_path, token_path=token_path, app_path=app_path)


def load_params(args: argparse.Namespace) -> dict[str, Any]:
    patch_sources = [args.patch_file is not None, args.patch_stdin]
    if sum(patch_sources) > 1:
        raise ValueError("provide only one of --patch-file or --patch-stdin")
    if any(patch_sources):
        if args.params_json is not None or args.params_file is not None or args.params_stdin:
            raise ValueError("patch input cannot be combined with params_json, --params-file, or --params-stdin")
        if args.patch_stdin:
            patch = sys.stdin.read()
        else:
            with open(args.patch_file, "r", encoding="utf-8") as f:
                patch = f.read()
        params: dict[str, Any] = {"patch": patch}
        if args.path:
            params["path"] = args.path
        if args.confirm:
            params["confirm"] = True
        if args.dry_run is not None:
            params["dryRun"] = args.dry_run
        if args.offset is not None:
            params["offset"] = args.offset
        if args.max_bytes is not None:
            params["maxBytes"] = args.max_bytes
        if args.max_hunks is not None:
            params["maxHunks"] = args.max_hunks
        if args.hunk_offset is not None:
            params["hunkOffset"] = args.hunk_offset
        if args.include_lines:
            params["includeLines"] = True
        if args.max_lines_per_hunk is not None:
            params["maxLinesPerHunk"] = args.max_lines_per_hunk
        return params

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


def batch_requests_from_lines(lines: list[str]) -> list[dict[str, Any]]:
    requests: list[dict[str, Any]] = []
    for index, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            requests.append(
                {
                    "id": f"line:{index}",
                    "localError": local_error_response(f"line:{index}", "invalid_json", str(exc)),
                }
            )
            continue
        if not isinstance(item, dict):
            requests.append(
                {
                    "id": f"line:{index}",
                    "localError": local_error_response(f"line:{index}", "invalid_request", "batch line must be a JSON object"),
                }
            )
            continue
        requests.append(item)
    return requests


def load_batch_requests(args: argparse.Namespace) -> list[dict[str, Any]]:
    if args.batch_file and args.batch_stdin:
        raise ValueError("provide only one of --batch-file or --batch-stdin")
    if args.batch_stdin:
        lines = sys.stdin.readlines()
    elif args.batch_file:
        with open(args.batch_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
    else:
        return []
    return batch_requests_from_lines(lines)


def send_rpc(
    sock: socket.socket,
    token: str,
    method: str,
    params: dict[str, Any] | None = None,
    request_id: str | None = None,
    request_timeout: float | None = None,
    agent_id: str | None = None,
    rationale: str | None = None,
    max_request_bytes: int = MAX_REQUEST_BYTES,
    max_response_bytes: int = MAX_RESPONSE_BYTES,
) -> dict[str, Any]:
    payload = {
        "id": request_id or f"{method}:{uuid.uuid4().hex}",
        "schemaVersion": SCHEMA_VERSION,
        "method": method,
        "params": params or {},
        "token": token,
    }
    if agent_id:
        payload["agentId"] = agent_id
    if rationale:
        payload["rationale"] = rationale
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
            raise DietCodeTransportError(f"socket closed while waiting for {method}")
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
    agent_id: str | None = None,
    rationale: str | None = None,
) -> dict[str, Any]:
    response = send_rpc(sock, token, method, params, request_id, request_timeout=request_timeout, agent_id=agent_id, rationale=rationale)
    if not response.get("ok"):
        raise DietCodeRpcError(method, response)
    return response.get("result", {})


class DietCodeAgentClient:
    """Small context-managed SDK wrapper for long-lived agent sessions."""

    def __init__(
        self,
        app_path: str | os.PathLike[str] | None = None,
        socket_path: str = SOCKET_PATH,
        token_path: str = TOKEN_PATH,
        timeout: float = 10.0,
        request_timeout: float = 30.0,
        start: bool = True,
        retries: int = 0,
        agent_id: str | None = None,
        rationale: str | None = None,
    ) -> None:
        self.app_path = app_path
        self.socket_path = socket_path
        self.token_path = token_path
        self.timeout = timeout
        self.request_timeout = request_timeout
        self.start = start
        self.retries = max(0, retries)
        self.agent_id = agent_id
        self.rationale = rationale
        self.sock: socket.socket | None = None
        self.token: str | None = None

    def __enter__(self) -> "DietCodeAgentClient":
        self.open()
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        self.close()

    def open(self) -> None:
        self.sock = connect(
            timeout=self.timeout,
            app_path=self.app_path,
            socket_path=self.socket_path,
            start=self.start,
        )
        self.token = load_token(self.token_path)

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def reconnect(self) -> None:
        self.close()
        self.open()

    def raw_call(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        request_id: str | None = None,
        agent_id: str | None = None,
        rationale: str | None = None,
    ) -> dict[str, Any]:
        transport_attempts = 0
        token_refreshed = False
        while True:
            if self.sock is None or self.token is None:
                self.open()
            assert self.sock is not None
            assert self.token is not None
            try:
                response = send_rpc(
                    self.sock,
                    self.token,
                    method,
                    params,
                    request_id,
                    request_timeout=self.request_timeout,
                    agent_id=agent_id or self.agent_id,
                    rationale=rationale or self.rationale,
                )
            except (OSError, DietCodeTransportError) as exc:
                max_retries = max(1, self.retries) if method in READ_METHODS else self.retries
                if transport_attempts >= max_retries:
                    raise
                transport_attempts += 1
                self.reconnect()
                continue

            err = response.get("error", {}) if not response.get("ok") else {}
            message = str(err.get("message", ""))
            if (
                err.get("string_code") == "permission_denied"
                and "token" in message.lower()
                and not token_refreshed
            ):
                token_refreshed = True
                self.token = load_token(self.token_path)
                continue
            return response

    def call(
        self,
        method: str,
        params: dict[str, Any] | None = None,
        request_id: str | None = None,
    ) -> dict[str, Any]:
        response = self.raw_call(method, params, request_id)
        if not response.get("ok"):
            raise DietCodeRpcError(method, response)
        return response.get("result", {})

    def batch(self, requests: list[dict[str, Any]]) -> list[dict[str, Any]]:
        responses: list[dict[str, Any]] = []
        for index, request in enumerate(requests, start=1):
            if "localError" in request:
                responses.append(request["localError"])
                continue
            request_id = request.get("id") or f"batch:{index}"
            method = request.get("method")
            params = request.get("params", {})
            if not isinstance(method, str) or not method:
                responses.append(local_error_response(str(request_id), "invalid_request", "batch request missing method"))
                continue
            if not isinstance(params, dict):
                responses.append(local_error_response(str(request_id), "invalid_params", "params must be a JSON object"))
                continue
            try:
                responses.append(self.raw_call(method, params, str(request_id)))
            except Exception as exc:
                responses.append(local_error_response(str(request_id), "transport_error", str(exc)))
        return responses

    def capabilities(self) -> dict[str, Any]:
        return {
            "version": self.call("rpc.version"),
            "methods": self.call("rpc.methods").get("methods", []),
            "limits": {
                "maxRequestBytes": MAX_REQUEST_BYTES,
                "maxResponseBytes": MAX_RESPONSE_BYTES,
            },
            "schemaVersion": SCHEMA_VERSION,
        }


def connect(
    timeout: float = 10.0,
    app_path: str | os.PathLike[str] | None = None,
    socket_path: str = SOCKET_PATH,
    start: bool = True,
) -> socket.socket:
    probe_errors: list[str] = []
    if not ensure_socket(app_path=app_path, timeout=timeout, socket_path=socket_path, start=start, probe_errors=probe_errors):
        diagnostic = _socket_probe_diagnostic(socket_path, probe_errors)
        suffix = f": {diagnostic}" if diagnostic else ""
        raise RuntimeError(f"failed to start DietCode control socket at {socket_path}{suffix}")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(socket_path)
    return sock


def run_self_test() -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    valid = batch_requests_from_lines(['{"id":"a","method":"rpc.ping","params":{}}\n'])
    checks.append({"name": "batch.valid", "ok": valid[0]["method"] == "rpc.ping"})
    checks.append({"name": "batch.empty", "ok": batch_requests_from_lines(["\n"]) == []})

    invalid_json = batch_requests_from_lines(["{bad json}\n"])
    checks.append({"name": "batch.invalid_json", "ok": invalid_json[0]["localError"]["error"]["string_code"] == "invalid_json"})

    invalid_params = batch_requests_from_lines(['{"id":"b","method":"rpc.ping","params":[]}\n'])
    responses = DietCodeAgentClient(start=False).batch(invalid_params)
    checks.append({"name": "batch.invalid_params", "ok": responses[0]["error"]["string_code"] == "invalid_params"})
    checks.append({"name": "batch.invalid_params_code", "ok": responses[0]["error"]["code"] == -32602})

    compact = json_text({"b": 2, "a": 1}, compact=True)
    checks.append({"name": "json.compact", "ok": compact == '{"a":1,"b":2}'})
    fake_args = argparse.Namespace(app=None)
    checks.append({"name": "config.value", "ok": config_value(fake_args, {"app": "configured"}, "app", "app", None) == "configured"})
    patch_args = argparse.Namespace(
        patch_file=None,
        patch_stdin=True,
        params_json=None,
        params_file=None,
        params_stdin=False,
        path="a.txt",
        confirm=True,
        dry_run=None,
        offset=None,
        max_bytes=None,
        max_hunks=None,
        hunk_offset=None,
        include_lines=False,
        max_lines_per_hunk=None,
    )
    patch_args.params_json = "{}"
    try:
        load_params(patch_args)
        conflict_ok = False
    except ValueError:
        conflict_ok = True
    checks.append({"name": "patch.params_conflict", "ok": conflict_ok})
    patch_args.params_json = None
    patch_args.patch_file = "/dev/null"
    patch_args.patch_stdin = False
    patch_args.hunk_offset = 25
    patch_args.include_lines = True
    patch_args.max_lines_per_hunk = 12
    try:
        patch_params = load_params(patch_args)
        cursor_ok = (
            patch_params.get("hunkOffset") == 25
            and patch_params.get("includeLines") is True
            and patch_params.get("maxLinesPerHunk") == 12
            and patch_params.get("patch") == ""
        )
    except ValueError:
        cursor_ok = False
    checks.append({"name": "patch.params_hunk_offset", "ok": cursor_ok})
    checks.append({"name": "read_methods.ping", "ok": "rpc.ping" in READ_METHODS})
    checks.append({"name": "read_methods.batch", "ok": "file.readBatch" in READ_METHODS and "file.statBatch" in READ_METHODS})
    checks.append({"name": "read_methods.search_session", "ok": "workspace.searchStart" in READ_METHODS and "workspace.searchNext" in READ_METHODS})
    checks.append({"name": "read_methods.symbols", "ok": "symbols.hierarchy" in READ_METHODS and "system.info" in READ_METHODS})
    checks.append({"name": "read_methods.mutation", "ok": "patch.apply" not in READ_METHODS})
    diagnostic = _socket_probe_diagnostic("/tmp/control.sock", ["permission_denied: [Errno 1] Operation not permitted"])
    checks.append({"name": "socket_probe.permission_diagnostic", "ok": diagnostic is not None and "cannot connect" in diagnostic})

    ok = all(check["ok"] for check in checks)
    return {"ok": ok, "checks": checks}


def main() -> int:
    parser = argparse.ArgumentParser(description="Ensure and call the DietCode headless control socket.")
    parser.add_argument("--config", help="JSON config file. Can also be set with DIETCODE_AGENT_CONFIG.")
    parser.add_argument("--app", help="Path to DietCode binary. Defaults to build/DietCode.app/Contents/MacOS/DietCode.")
    parser.add_argument("--socket", help="Unix socket path. Defaults to config, DIETCODE_SOCKET_PATH, or ~/.dietcode/control.sock.")
    parser.add_argument("--token-file", help="Session token path. Defaults to config, DIETCODE_TOKEN_PATH, or ~/.dietcode/session.token.")
    parser.add_argument("--timeout", type=float, help="Seconds to wait for socket startup and connect.")
    parser.add_argument("--request-timeout", type=float, help="Seconds to wait for one RPC response.")
    parser.add_argument("--retries", type=int, help="Transport retries after socket errors. Use only for safe/idempotent calls.")
    parser.add_argument("--no-start", action="store_true", help="Do not launch DietCode if the socket is inactive.")
    parser.add_argument("--quiet", action="store_true", help="Suppress diagnostic output on stderr.")
    parser.add_argument("--ensure-only", action="store_true", help="Only ensure the socket is active, then exit.")
    parser.add_argument("--status", action="store_true", help="Print local socket/token/app readiness JSON, then exit.")
    parser.add_argument("--wait-ready", action="store_true", help="Ensure the socket, then wait for authenticated RPC readiness.")
    parser.add_argument("--self-test", action="store_true", help="Run client-only parser/format checks without connecting to DietCode.")
    parser.add_argument("--emit-config", action="store_true", help="Print resolved config JSON without connecting to DietCode.")
    parser.add_argument("--capabilities", action="store_true", help="Print version, method list, schema, and client transport limits.")
    parser.add_argument("--server-version", action="store_true", help="Call rpc.version and exit.")
    parser.add_argument("--list-methods", action="store_true", help="Call rpc.methods and exit.")
    parser.add_argument("--describe", help="Call rpc.describe for one method and exit.")
    parser.add_argument("--raw-response", action="store_true", help="Print the full JSON-RPC response envelope.")
    parser.add_argument("--compact", action="store_true", help="Print compact JSON on one line.")
    parser.add_argument("--listen", action="store_true", help="Listen for asynchronous event notifications.")
    parser.add_argument("--request-id", help="Override the JSON-RPC request id.")
    parser.add_argument("--agent-id", help="Identify the agent calling the RPC.")
    parser.add_argument("--rationale", help="Provide a human-readable explanation for the action.")
    parser.add_argument("--params-file", help="Read RPC params JSON object from a file.")
    parser.add_argument("--params-stdin", action="store_true", help="Read RPC params JSON object from stdin.")
    parser.add_argument("--path", help="Path used with --patch-file or --patch-stdin.")
    parser.add_argument("--grep", help="Call workspace.grep with a literal query.")
    parser.add_argument("--search-text", help="Call search.text with a literal query.")
    parser.add_argument("--search-semantic", help="Call search.semantic with a symbol or conceptual query.")
    parser.add_argument("--result-offset", type=int, help="Zero-based result cursor for workspace.grep or search.text.")
    parser.add_argument("--max-results", type=int, help="Maximum results for workspace.grep or search.text.")
    parser.add_argument("--before", type=int, help="Context lines before each search.text result.")
    parser.add_argument("--after", type=int, help="Context lines after each search.text result.")
    parser.add_argument("--case-sensitive", action="store_true", help="Use case-sensitive literal grep/text search.")
    parser.add_argument("--include", action="append", help="Include glob for grep/text search. May be repeated.")
    parser.add_argument("--exclude", action="append", help="Exclude glob for grep/text search. May be repeated.")
    parser.add_argument("--diff-source", choices=["unstaged", "staged", "file"], help="Call diff.chunk for unstaged, staged, or file diff.")
    parser.add_argument("--diff-hunks", action="store_true", help="Use diff.hunks with --diff-source instead of diff.chunk.")
    parser.add_argument("--offset", type=int, help="Byte offset for diff.chunk or patch.chunk.")
    parser.add_argument("--max-bytes", type=int, help="Maximum bytes for diff.chunk or patch.chunk.")
    parser.add_argument("--max-hunks", type=int, help="Maximum hunk summaries for diff.hunks or patch.hunks.")
    parser.add_argument("--hunk-offset", type=int, help="Zero-based hunk cursor for diff.hunks or patch.hunks.")
    parser.add_argument("--include-lines", action="store_true", help="Include literal per-row old/new line evidence in hunk responses.")
    parser.add_argument("--max-lines-per-hunk", type=int, help="Maximum literal line rows per returned hunk.")
    parser.add_argument("--patch-file", help="Read unified diff patch text from a file.")
    parser.add_argument("--patch-stdin", action="store_true", help="Read unified diff patch text from stdin.")
    parser.add_argument("--patch-hunks", action="store_true", help="Default patch stdin/file calls to patch.hunks instead of patch.validate.")
    parser.add_argument("--confirm", action="store_true", help="Set confirm=true for patch apply calls.")
    parser.add_argument("--dry-run", dest="dry_run", action="store_true", default=None, help="Set dryRun=true for supported calls.")
    parser.add_argument("--no-dry-run", dest="dry_run", action="store_false", help="Set dryRun=false for supported calls.")
    parser.add_argument("--batch-file", help="Read newline-delimited JSON RPC requests from a file.")
    parser.add_argument("--batch-stdin", action="store_true", help="Read newline-delimited JSON RPC requests from stdin.")
    parser.add_argument("method", nargs="?", default="rpc.ping", help="RPC method to call after ensuring the socket.")
    parser.add_argument("params_json", nargs="?", help="JSON object params for the RPC call.")
    args = parser.parse_args()

    try:
        config = load_config(args.config)
        app_path = config_value(args, config, "app", "app", None)
        socket_path = os.path.expanduser(config_value(args, config, "socket", "socket", SOCKET_PATH))
        token_path = os.path.expanduser(config_value(args, config, "token_file", "tokenFile", TOKEN_PATH))
        timeout = float(config_value(args, config, "timeout", "timeout", 10.0))
        request_timeout = float(config_value(args, config, "request_timeout", "requestTimeout", 30.0))
        retries = int(config_value(args, config, "retries", "retries", 0))

        if args.self_test:
            result = run_self_test()
            print(json_text(result, compact=args.compact))
            return 0 if result["ok"] else 1

        if args.emit_config:
            resolved = {
                "app": str(resolve_app_path(app_path)),
                "socket": socket_path,
                "tokenFile": token_path,
                "timeout": timeout,
                "requestTimeout": request_timeout,
                "retries": retries,
            }
            print(json_text(resolved, compact=args.compact))
            return 0

        if args.status:
            state = status(socket_path=socket_path, token_path=token_path, app_path=app_path)
            print(json_text(state, compact=args.compact))
            return 0 if state["ok"] else 1

        if args.wait_ready:
            state = wait_ready(
                app_path=app_path,
                socket_path=socket_path,
                token_path=token_path,
                timeout=timeout,
                start=not args.no_start,
                quiet=args.quiet,
            )
            print(json_text(state, compact=args.compact))
            return 0 if state["ok"] else 1

        if args.ensure_only:
            if ensure_socket(app_path=app_path, timeout=timeout, quiet=args.quiet, socket_path=socket_path, start=not args.no_start):
                print(json_text({"ok": True, "socket": socket_path}, compact=args.compact))
                return 0
            raise RuntimeError(f"failed to start DietCode control socket at {socket_path}")

        if args.batch_stdin and args.params_stdin:
            raise ValueError("provide only one of --batch-stdin or --params-stdin")
        if args.grep and args.search_text:
            raise ValueError("provide only one of --grep or --search-text")
        batch_mode = args.batch_file is not None or args.batch_stdin
        batch_requests = load_batch_requests(args)
        if batch_mode:
            if not batch_requests:
                return 0
            with DietCodeAgentClient(
                app_path=app_path,
                socket_path=socket_path,
                token_path=token_path,
                timeout=timeout,
                request_timeout=request_timeout,
                start=not args.no_start,
                retries=retries,
                agent_id=args.agent_id,
                rationale=args.rationale,
            ) as client:
                responses = client.batch(batch_requests)
            for response in responses:
                print(json_text(response, compact=True))
            return 0 if all(response.get("ok") for response in responses) else 1

        shortcut_method: str | None = None
        shortcut_params: dict[str, Any] = {}
        if args.diff_source:
            shortcut_method = "diff.hunks" if args.diff_hunks else "diff.chunk"
            shortcut_params = {"source": args.diff_source}
            if args.path:
                shortcut_params["path"] = args.path
            if args.offset is not None:
                shortcut_params["offset"] = args.offset
            if args.max_bytes is not None:
                shortcut_params["maxBytes"] = args.max_bytes
            if args.max_hunks is not None:
                shortcut_params["maxHunks"] = args.max_hunks
            if args.hunk_offset is not None:
                shortcut_params["hunkOffset"] = args.hunk_offset
            if args.include_lines:
                shortcut_params["includeLines"] = True
            if args.max_lines_per_hunk is not None:
                shortcut_params["maxLinesPerHunk"] = args.max_lines_per_hunk
        elif args.grep or args.search_text or args.search_semantic:
            shortcut_method = "workspace.grep" if args.grep else ("search.text" if args.search_text else "search.semantic")
            shortcut_params = {"query": args.grep or args.search_text or args.search_semantic}
            if args.max_results is not None:
                shortcut_params["maxResults"] = args.max_results
            if args.result_offset is not None:
                shortcut_params["resultOffset"] = args.result_offset
            if args.case_sensitive:
                shortcut_params["caseSensitive"] = True
            if args.include:
                shortcut_params["include"] = args.include
            if args.exclude:
                shortcut_params["exclude"] = args.exclude
            if args.search_text:
                if args.before is not None:
                    shortcut_params["before"] = args.before
                if args.after is not None:
                    shortcut_params["after"] = args.after
        elif args.capabilities:
            with DietCodeAgentClient(
                app_path=app_path,
                socket_path=socket_path,
                token_path=token_path,
                timeout=timeout,
                request_timeout=request_timeout,
                start=not args.no_start,
                retries=retries,
                agent_id=args.agent_id,
                rationale=args.rationale,
            ) as client:
                response = client.capabilities()
            print(json_text(response, compact=args.compact))
            return 0

        if shortcut_method is None and args.server_version:
            shortcut_method = "rpc.version"
        elif shortcut_method is None and args.list_methods:
            shortcut_method = "rpc.methods"
        elif shortcut_method is None and args.describe:
            shortcut_method = "rpc.describe"
            shortcut_params = {"method": args.describe}

        if args.listen:
            with DietCodeAgentClient(
                app_path=app_path,
                socket_path=socket_path,
                token_path=token_path,
                timeout=timeout,
                request_timeout=request_timeout,
                start=not args.no_start,
                retries=retries,
                agent_id=args.agent_id,
                rationale=args.rationale,
            ) as client:
                client.call("event.subscribe", {"types": ["*"]})
                print("Listening for events... (Press Ctrl+C to stop)")
                sock_buffer = b""
                while True:
                    try:
                        client.sock.settimeout(1.0)
                        chunk = client.sock.recv(65536)
                        if not chunk:
                            print("Socket closed by server.")
                            break
                        sock_buffer += chunk
                        while b"\n" in sock_buffer:
                            line, sock_buffer = sock_buffer.split(b"\n", 1)
                            if not line: continue
                            try:
                                print(json_text(json.loads(line), compact=args.compact))
                            except json.JSONDecodeError:
                                print(f"Failed to decode frame: {line!r}")
                    except socket.timeout:
                        continue
                    except KeyboardInterrupt:
                        break
            return 0

        if shortcut_method:
            with DietCodeAgentClient(
                app_path=app_path,
                socket_path=socket_path,
                token_path=token_path,
                timeout=timeout,
                request_timeout=request_timeout,
                start=not args.no_start,
                retries=retries,
                agent_id=args.agent_id,
                rationale=args.rationale,
            ) as client:
                if args.raw_response:
                    response = client.raw_call(shortcut_method, shortcut_params, args.request_id)
                else:
                    response = client.call(shortcut_method, shortcut_params, args.request_id)
            print(json_text(response, compact=args.compact))
            return 0

        effective_method = args.method
        if (args.patch_file or args.patch_stdin) and effective_method == "rpc.ping":
            effective_method = "patch.hunks" if args.patch_hunks else "patch.validate"
        params = load_params(args)
        with DietCodeAgentClient(
            app_path=app_path,
            socket_path=socket_path,
            token_path=token_path,
            timeout=timeout,
            request_timeout=request_timeout,
            start=not args.no_start,
            retries=retries,
            agent_id=args.agent_id,
            rationale=args.rationale,
        ) as client:
            if args.raw_response:
                response = client.raw_call(effective_method, params, args.request_id)
            else:
                response = client.call(effective_method, params, args.request_id)
        print(json_text(response, compact=args.compact))
        return 0
    except Exception as exc:
        if not args.quiet:
            print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
