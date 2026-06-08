"""DietCode IDE Agent Bridge client — production wrapper for ``dietcode-agent-client``."""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

DEFAULT_SOCKET_PATH = Path.home() / ".dietcode" / "control.sock"


def _emit_task_event(event_type: str, **payload: Any) -> None:
    task_id = os.environ.get("DIETCODE_TASK_ID", "").strip()
    if not task_id:
        return
    from datetime import datetime, timezone

    record = {
        "type": event_type,
        "taskId": task_id,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "dietcode_ide",
        **payload,
    }
    log_path = os.environ.get("DIETCODE_TASK_EVENT_LOG", "").strip()
    if not log_path:
        return
    try:
        path = Path(log_path).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        logger.debug("task event log write failed", exc_info=True)
DEFAULT_TOKEN_PATH = Path.home() / ".dietcode" / "session.token"
_PREFLIGHT_CACHE: dict[str, Any] | None = None
_PREFLIGHT_CACHE_AT: float = 0.0
_PREFLIGHT_TTL_SEC = 30.0
_BRIDGE_READY: bool = False

_RAW_WRITE_TOOLS = frozenset({
    "write_file",
    "patch",
    "multi_replace_file_content",
    "replace_file_content",
})


class IdeBridgeError(Exception):
    """Agent bridge CLI or configuration failure with stable recovery metadata."""

    def __init__(
        self,
        message: str,
        *,
        code: str = "bridge_error",
        recovery_hint: str = "",
        retry_safe: bool = False,
        raw_error: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.recovery_hint = recovery_hint
        self.retry_safe = retry_safe
        self.raw_error = raw_error or {}

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": False,
            "error": {
                "code": self.code,
                "message": str(self),
                "recoveryHint": self.recovery_hint,
                "retrySafe": self.retry_safe,
                "rawError": self.raw_error,
            },
        }


@dataclass(frozen=True)
class IdeBridgeConfig:
    enabled: bool = True
    auto_connect: bool = True
    auto_build: bool = True
    prefer_over_raw_writes: bool = True
    auto_open_workspace: bool = True
    root: Optional[str] = None
    bridge_cli: Optional[str] = None
    app_path: Optional[str] = None
    socket_path: str = str(DEFAULT_SOCKET_PATH)
    token_path: str = str(DEFAULT_TOKEN_PATH)
    connect_timeout_sec: int = 15
    request_timeout_sec: int = 120


def _load_ide_config() -> IdeBridgeConfig:
    cfg = IdeBridgeConfig()
    try:
        from hermes_cli.config import load_config

        raw = load_config()
        dietcode = raw.get("dietcode", {}) if isinstance(raw, dict) else {}
        if isinstance(dietcode, dict):
            ide = dietcode.get("ide", {})
            if isinstance(ide, dict):
                return IdeBridgeConfig(
                    enabled=bool(ide.get("enabled", True)),
                    auto_connect=bool(ide.get("auto_connect", True)),
                    auto_build=bool(ide.get("auto_build", True)),
                    prefer_over_raw_writes=bool(ide.get("prefer_over_raw_writes", True)),
                    auto_open_workspace=bool(ide.get("auto_open_workspace", True)),
                    root=str(ide.get("root") or "").strip() or None,
                    bridge_cli=str(ide.get("bridge_cli") or "").strip() or None,
                    app_path=str(ide.get("app_path") or "").strip() or None,
                    socket_path=str(ide.get("socket_path") or DEFAULT_SOCKET_PATH),
                    token_path=str(ide.get("token_path") or DEFAULT_TOKEN_PATH),
                    connect_timeout_sec=int(ide.get("connect_timeout_sec", 15) or 15),
                    request_timeout_sec=int(ide.get("request_timeout_sec", 120) or 120),
                )
    except Exception:
        pass
    detected = auto_detect_ide_root()
    if detected:
        return IdeBridgeConfig(root=detected)
    return cfg


def _is_app_bundle(path: Path) -> bool:
    return path.suffix == ".app" and (path / "Contents" / "MacOS").is_dir()


def _app_bundle_from_binary(binary: Path) -> Optional[Path]:
    for parent in binary.resolve().parents:
        if _is_app_bundle(parent):
            return parent
    return None


def _standard_app_bundle_locations() -> list[Path]:
    return [
        Path("/Applications/DietCode.app"),
        Path.home() / "Applications" / "DietCode.app",
    ]


def resolve_app_bundle(explicit: Optional[str] = None) -> Optional[Path]:
    """Locate DietCode.app — installed bundle or dev build."""
    if explicit and str(explicit).strip():
        candidate = Path(explicit).expanduser()
        if _is_app_bundle(candidate):
            return candidate.resolve()
        if candidate.suffix == ".app":
            return None
        bundle = _app_bundle_from_binary(candidate)
        if bundle:
            return bundle

    for key in ("DIETCODE_APP_PATH", "DIETCODE_APP_BUNDLE"):
        val = os.environ.get(key, "").strip()
        if not val:
            continue
        candidate = Path(val).expanduser()
        if _is_app_bundle(candidate):
            return candidate.resolve()
        bundle = _app_bundle_from_binary(candidate)
        if bundle:
            return bundle

    ide_root = resolve_ide_root(skip_app_scan=True)
    if ide_root:
        dev_bundle = ide_root / "build" / "DietCode.app"
        if _is_app_bundle(dev_bundle):
            return dev_bundle.resolve()

    for location in _standard_app_bundle_locations():
        if _is_app_bundle(location):
            return location.resolve()

    return None


def auto_detect_ide_root() -> Optional[str]:
    """Best-effort DietCode IDE checkout or installed app bundle discovery."""
    seeds: list[Path] = []
    for key in ("DIETCODE_IDE_ROOT", "DIETCODE_REPO_ROOT", "DIETCODE_APP_BUNDLE"):
        val = os.environ.get(key, "").strip()
        if val:
            seeds.append(Path(val).expanduser())
    seeds.extend([
        Path.home() / "Desktop" / "DietCode-IDE",
        Path.home() / "DietCode-IDE",
        Path.cwd(),
        *Path.cwd().parents,
        *_standard_app_bundle_locations(),
    ])
    seen: set[str] = set()
    for seed in seeds:
        try:
            resolved = seed.resolve()
        except OSError:
            continue
        key = str(resolved)
        if key in seen:
            continue
        seen.add(key)
        if _is_app_bundle(resolved):
            return key
        if (resolved / "agent-bridge" / "package.json").is_file():
            return key
        if (resolved / "build" / "DietCode.app").is_dir():
            return key
    return None


def resolve_ide_root(
    explicit: Optional[str] = None,
    *,
    skip_app_scan: bool = False,
) -> Optional[Path]:
    """Locate DietCode repo root or installed ``DietCode.app`` bundle."""
    if explicit and str(explicit).strip():
        candidate = Path(explicit).expanduser().resolve()
        if _is_app_bundle(candidate):
            return candidate
        return candidate

    ide_cfg = _load_ide_config()
    if ide_cfg.root:
        candidate = Path(ide_cfg.root).expanduser().resolve()
        if candidate.exists():
            return candidate

    for key in ("DIETCODE_IDE_ROOT", "DIETCODE_REPO_ROOT", "DIETCODE_APP_BUNDLE"):
        val = os.environ.get(key, "").strip()
        if val:
            candidate = Path(val).expanduser().resolve()
            if candidate.exists():
                return candidate

    if not skip_app_scan:
        bundle = resolve_app_bundle()
        if bundle:
            return bundle

    for seed in [Path.cwd(), *Path.cwd().parents]:
        if (seed / "agent-bridge" / "package.json").is_file():
            return seed.resolve()
        if (seed / "build" / "DietCode.app").is_dir():
            return seed.resolve()

    return None


def resolve_app_path(explicit: Optional[str] = None) -> Optional[Path]:
    if explicit and str(explicit).strip():
        candidate = Path(explicit).expanduser()
        if candidate.is_file():
            return candidate.resolve()

    ide_cfg = _load_ide_config()
    if ide_cfg.app_path:
        candidate = Path(ide_cfg.app_path).expanduser()
        if candidate.is_file():
            return candidate.resolve()

    val = os.environ.get("DIETCODE_APP_PATH", "").strip()
    if val:
        candidate = Path(val).expanduser()
        if candidate.is_file():
            return candidate.resolve()

    bundle = resolve_app_bundle()
    if bundle:
        candidate = bundle / "Contents" / "MacOS" / "DietCode"
        if candidate.is_file():
            return candidate.resolve()

    ide_root = resolve_ide_root(skip_app_scan=True)
    if ide_root and not _is_app_bundle(ide_root):
        candidate = ide_root / "build" / "DietCode.app" / "Contents" / "MacOS" / "DietCode"
        if candidate.is_file():
            return candidate.resolve()

    return None


def _bridge_cli_candidates(
    ide_root: Optional[Path],
    app_bundle: Optional[Path],
) -> list[Path]:
    candidates: list[Path] = []
    ide_cfg = _load_ide_config()
    if ide_cfg.bridge_cli:
        candidates.append(Path(ide_cfg.bridge_cli).expanduser())
    env_cli = os.environ.get("DIETCODE_BRIDGE_CLI", "").strip()
    if env_cli:
        candidates.append(Path(env_cli).expanduser())

    bundles: list[Path] = []
    if app_bundle:
        bundles.append(app_bundle)
    if ide_root and _is_app_bundle(ide_root):
        bundles.append(ide_root)
    for bundle in bundles:
        candidates.extend([
            bundle / "Contents" / "Resources" / "bin" / "dietcode-agent-client",
            bundle / "Contents" / "Resources" / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js",
        ])

    if ide_root and not _is_app_bundle(ide_root):
        candidates.extend([
            ide_root / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js",
            ide_root / "build" / "DietCode.app" / "Contents" / "Resources" / "bin" / "dietcode-agent-client",
            ide_root / "build" / "DietCode.app" / "Contents" / "Resources" / "agent-bridge" / "dist" / "cli" / "dietcode-agent-client.js",
        ])
    return candidates


def resolve_bridge_cli(*, required: bool = True) -> Optional[Path]:
    ide_root = resolve_ide_root()
    app_bundle = resolve_app_bundle()
    for candidate in _bridge_cli_candidates(ide_root, app_bundle):
        if candidate.is_file():
            return candidate.resolve()
    if required:
        raise IdeBridgeError(
            "DietCode agent bridge CLI not found. Run: make -C <dietcode-ide> setup-hermes-bridge "
            "or set DIETCODE_BRIDGE_CLI / dietcode.ide.bridge_cli",
            code="bridge_cli_missing",
            recovery_hint="run_setup_hermes_bridge",
            retry_safe=True,
        )
    return None


def resolve_socket_path() -> Path:
    ide_cfg = _load_ide_config()
    env_socket = os.environ.get("DIETCODE_SOCKET_PATH", "").strip()
    if env_socket:
        return Path(env_socket).expanduser()
    return Path(ide_cfg.socket_path).expanduser()


def resolve_workspace_root(explicit: Optional[str] = None) -> str:
    if explicit and str(explicit).strip():
        return str(Path(explicit).expanduser().resolve())

    for key in ("DIETCODE_WORKSPACE", "HERMES_KANBAN_WORKSPACE"):
        val = os.environ.get(key, "").strip()
        if val:
            return str(Path(val).expanduser().resolve())

    return str(Path.cwd().resolve())


def socket_ready(socket_path: Optional[Path] = None) -> bool:
    path = socket_path or resolve_socket_path()
    return path.is_socket() or path.exists()


def token_ready(token_path: Optional[Path] = None) -> bool:
    path = token_path or Path(_load_ide_config().token_path).expanduser()
    return path.is_file() and path.stat().st_size > 0


def is_ide_bridge_ready() -> bool:
    """Return True when the last preflight succeeded and runtime artifacts exist."""
    if _BRIDGE_READY:
        return True
    cfg = _load_ide_config()
    if not cfg.enabled:
        return False
    return bool(resolve_bridge_cli(required=False)) and socket_ready() and token_ready()


def is_raw_write_tool(tool_name: str) -> bool:
    return (tool_name or "").strip() in _RAW_WRITE_TOOLS


def resolve_exec_command() -> list[str]:
    """Return argv prefix to invoke the bridge CLI (launcher script or node + js)."""
    cli = resolve_bridge_cli(required=True)
    if cli.name == "dietcode-agent-client" and os.access(cli, os.X_OK):
        return [str(cli)]
    return [_node_executable(), str(cli)]


def _node_executable() -> str:
    node = shutil.which("node")
    if not node:
        raise IdeBridgeError(
            "node is not on PATH — required to run dietcode-agent-client",
            code="node_missing",
            recovery_hint="install_node",
        )
    return node


def ensure_bridge_built(*, auto_build: Optional[bool] = None, timeout: int = 300) -> dict[str, Any]:
    """Build agent-bridge when dist CLI is missing."""
    ide_cfg = _load_ide_config()
    if auto_build is None:
        auto_build = ide_cfg.auto_build

    existing = resolve_bridge_cli(required=False)
    if existing:
        return {"ok": True, "action": "ready", "bridge_cli": str(existing)}

    ide_root = resolve_ide_root()
    if not ide_root:
        return {
            "ok": False,
            "action": "ide_root_missing",
            "error": "DIETCODE_IDE_ROOT not resolved — cannot auto-build bridge",
        }

    if not auto_build:
        return {
            "ok": False,
            "action": "build_required",
            "hint": f"cd {ide_root} && make agent-bridge-fast",
        }

    makefile = ide_root / "Makefile"
    if not makefile.is_file():
        return {"ok": False, "action": "build_required", "error": f"no Makefile at {ide_root}"}

    try:
        proc = subprocess.run(
            ["make", "agent-bridge-fast"],
            cwd=ide_root,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()[:500]
            return {"ok": False, "action": "build_failed", "error": err or f"exit {proc.returncode}"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "action": "build_timeout", "error": f"make agent-bridge-fast exceeded {timeout}s"}
    except OSError as exc:
        return {"ok": False, "action": "build_error", "error": str(exc)}

    built = resolve_bridge_cli(required=False)
    if not built:
        return {"ok": False, "action": "build_failed", "error": "make completed but CLI still missing"}
    return {"ok": True, "action": "built", "bridge_cli": str(built)}


def ensure_runtime_socket(*, timeout_sec: Optional[int] = None) -> dict[str, Any]:
    """Ensure DietCode control socket via --ensure-socket."""
    ide_cfg = _load_ide_config()
    socket_path = resolve_socket_path()
    if socket_ready(socket_path):
        return {"ok": True, "action": "socket_ready", "socket_path": str(socket_path)}

    app = resolve_app_path()
    if not app:
        return {
            "ok": False,
            "action": "app_missing",
            "error": "DietCode binary not found — build with: make app",
            "recovery_hint": "build_dietcode_app",
        }

    timeout = timeout_sec if timeout_sec is not None else ide_cfg.connect_timeout_sec
    try:
        proc = subprocess.run(
            [str(app), "--ensure-socket", "--ensure-timeout", str(timeout)],
            capture_output=True,
            text=True,
            timeout=timeout + 5,
            check=False,
            env={**os.environ, "DIETCODE_REPO_ROOT": str(resolve_ide_root() or Path.cwd())},
        )
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()[:500]
            return {"ok": False, "action": "ensure_socket_failed", "error": err or f"exit {proc.returncode}"}
    except subprocess.TimeoutExpired:
        return {"ok": False, "action": "ensure_socket_timeout", "error": f"timed out after {timeout}s"}
    except OSError as exc:
        return {"ok": False, "action": "ensure_socket_error", "error": str(exc)}

    if socket_ready(socket_path):
        return {"ok": True, "action": "socket_started", "socket_path": str(socket_path)}
    return {"ok": False, "action": "socket_missing", "error": f"socket not present at {socket_path}"}


def connect_preflight(*, warm: bool = False, force: bool = False) -> dict[str, Any]:
    """Resolve paths, build bridge, ensure socket, optionally verify runtime."""
    global _PREFLIGHT_CACHE, _PREFLIGHT_CACHE_AT, _BRIDGE_READY

    ide_cfg = _load_ide_config()
    if not ide_cfg.enabled:
        _BRIDGE_READY = False
        return {"ok": True, "action": "disabled", "enabled": False}

    now = time.monotonic()
    if not force and _PREFLIGHT_CACHE is not None and (now - _PREFLIGHT_CACHE_AT) < _PREFLIGHT_TTL_SEC:
        return dict(_PREFLIGHT_CACHE)

    report: dict[str, Any] = {"ok": False, "steps": {}}

    build = ensure_bridge_built()
    report["steps"]["build"] = build
    if not build.get("ok"):
        report["error"] = build.get("error") or build.get("hint")
        report["action"] = build.get("action")
        _PREFLIGHT_CACHE = report
        _PREFLIGHT_CACHE_AT = now
        return report

    cli = resolve_bridge_cli(required=True)
    app = resolve_app_path()
    report["bridge_cli"] = str(cli)
    report["app_path"] = str(app) if app else None
    report["ide_root"] = str(resolve_ide_root()) if resolve_ide_root() else None
    report["socket_path"] = str(resolve_socket_path())

    if ide_cfg.auto_connect:
        socket_step = ensure_runtime_socket()
        report["steps"]["socket"] = socket_step
        if not socket_step.get("ok"):
            report["error"] = socket_step.get("error")
            report["action"] = socket_step.get("action")
            _PREFLIGHT_CACHE = report
            _PREFLIGHT_CACHE_AT = now
            return report

    if warm:
        try:
            verify = _execute_bridge_call(
                ["verify", "fast"],
                auto_start=False,
                timeout=30.0,
            )
            report["steps"]["verify"] = verify
            report["ok"] = bool(verify.get("ok"))
        except IdeBridgeError as exc:
            report["steps"]["verify"] = exc.to_dict()
            report["error"] = str(exc)
            report["action"] = "verify_failed"
    else:
        report["ok"] = True
        report["action"] = "preflight_ok"

    _BRIDGE_READY = bool(report.get("ok"))
    _PREFLIGHT_CACHE = report
    _PREFLIGHT_CACHE_AT = now
    return report


def invalidate_preflight_cache() -> None:
    global _PREFLIGHT_CACHE, _PREFLIGHT_CACHE_AT, _BRIDGE_READY
    _PREFLIGHT_CACHE = None
    _PREFLIGHT_CACHE_AT = 0.0
    _BRIDGE_READY = False


def ensure_connected(*, force: bool = False) -> dict[str, Any]:
    """Public entry — idempotent connect used by hooks, health, and agents."""
    return connect_preflight(warm=True, force=force)


def reconnect_bridge() -> dict[str, Any]:
    """Force socket rebuild + verify after transport failure."""
    invalidate_preflight_cache()
    socket_step = ensure_runtime_socket()
    if not socket_step.get("ok"):
        return {
            "ok": False,
            "action": "reconnect_failed",
            "socket": socket_step,
            "recovery_hint": "run_setup_hermes_bridge",
        }
    return ensure_connected(force=True)


def bootstrap_agent_workspace(explicit: Optional[str] = None) -> dict[str, Any]:
    """Open the active workspace on the DietCode runtime (kanban worker or cwd)."""
    cfg = _load_ide_config()
    if not cfg.enabled or not cfg.auto_open_workspace:
        return {"ok": True, "action": "skipped"}
    workspace = resolve_workspace_root(explicit)
    try:
        result = run_bridge(["profile"], workspace=workspace, wait_ready=True, auto_start=True)
        return {"ok": True, "action": "workspace_opened", "workspace": workspace, "profile": result}
    except IdeBridgeError as exc:
        return exc.to_dict()


def probe_bridge_available() -> dict[str, Any]:
    """Lightweight availability check without throwing."""
    try:
        ide_cfg = _load_ide_config()
        if not ide_cfg.enabled:
            return {"ok": False, "action": "disabled"}

        cli = resolve_bridge_cli(required=False)
        if not cli:
            return {"ok": False, "error": "bridge CLI not resolved", "action": "bridge_cli_missing"}

        app = resolve_app_path()
        return {
            "ok": True,
            "enabled": ide_cfg.enabled,
            "auto_connect": ide_cfg.auto_connect,
            "bridge_cli": str(cli),
            "app_path": str(app) if app else None,
            "ide_root": str(resolve_ide_root()) if resolve_ide_root() else None,
            "socket_path": str(resolve_socket_path()),
            "socket_ready": socket_ready(),
        }
    except IdeBridgeError as exc:
        return exc.to_dict()


def _parse_bridge_error(payload: dict[str, Any]) -> IdeBridgeError:
    err = payload.get("error")
    if isinstance(err, dict):
        return IdeBridgeError(
            str(err.get("message") or payload),
            code=str(err.get("code") or "bridge_error"),
            recovery_hint=str(err.get("recoveryHint") or err.get("recovery_hint") or ""),
            retry_safe=bool(err.get("retrySafe") or err.get("retry_safe")),
            raw_error=err,
        )
    return IdeBridgeError(str(err or payload), code="bridge_error")


_RETRYABLE_CODES = frozenset({
    "transport_error",
    "preflight_failed",
    "runtime_unavailable",
    "bridge_cli_missing",
    "nested_call_timeout",
})


def _execute_bridge_call(
    args: list[str],
    *,
    workspace: Optional[str] = None,
    auto_start: Optional[bool] = None,
    wait_ready: bool = False,
    timeout: Optional[float] = None,
    max_results: Optional[int] = None,
    idempotency_key: Optional[str] = None,
) -> dict[str, Any]:
    """Invoke bridge CLI once (no preflight/retry wrapper)."""
    ide_cfg = _load_ide_config()
    exec_cmd = resolve_exec_command()
    root = resolve_workspace_root(workspace)
    app = resolve_app_path()
    socket_path = resolve_socket_path()

    if auto_start is None:
        auto_start = ide_cfg.auto_connect and not socket_ready(socket_path)

    cmd = [*exec_cmd, "--compact", "--error-json"]
    if not auto_start:
        cmd.append("--no-start")
    if wait_ready or auto_start:
        cmd.append("--wait-ready")
    if app:
        cmd.extend(["--app", str(app)])
    if socket_path != DEFAULT_SOCKET_PATH:
        cmd.extend(["--socket", str(socket_path)])
    token_path = Path(ide_cfg.token_path).expanduser()
    if token_path != DEFAULT_TOKEN_PATH:
        cmd.extend(["--token", str(token_path)])
    if max_results is not None and max_results > 0:
        cmd.extend(["--max-results", str(max_results)])
    if idempotency_key:
        cmd.extend(["--idempotency-key", idempotency_key])
    cmd.extend(["--workspace", root, *args])

    action_label = " ".join(args[:3]) if args else "bridge"
    _emit_task_event("tool.call.started", action=action_label, workspace=root)

    request_timeout = timeout if timeout is not None else float(ide_cfg.request_timeout_sec)
    if os.environ.get("DIETCODE_SUPERVISED") == "1" and any(
        token in args for token in ("patch", "safe-file", "safe-batch")
    ):
        request_timeout = max(request_timeout, 30 * 60)
    env = {**os.environ}
    if app:
        env.setdefault("DIETCODE_APP_PATH", str(app))
    ide_root = resolve_ide_root()
    if ide_root:
        env.setdefault("DIETCODE_IDE_ROOT", str(ide_root))
    env.setdefault("DIETCODE_SOCKET_PATH", str(socket_path))

    try:
        proc = subprocess.run(
            cmd,
            cwd=root,
            env=env,
            capture_output=True,
            text=True,
            timeout=request_timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        invalidate_preflight_cache()
        raise IdeBridgeError(
            f"bridge CLI timed out after {request_timeout}s: {' '.join(args)}",
            code="nested_call_timeout",
            recovery_hint="operation_status",
            retry_safe=True,
        ) from exc
    except OSError as exc:
        invalidate_preflight_cache()
        raise IdeBridgeError(f"Failed to run bridge CLI: {exc}", code="transport_error") from exc

    raw = (proc.stdout or proc.stderr or "").strip()
    if not raw:
        invalidate_preflight_cache()
        detail = proc.stderr or proc.stdout or f"exit {proc.returncode}"
        raise IdeBridgeError(f"bridge CLI produced no output: {detail}", code="transport_error")

    line = raw.splitlines()[-1]
    try:
        data = json.loads(line)
    except json.JSONDecodeError as exc:
        invalidate_preflight_cache()
        raise IdeBridgeError(
            f"bridge CLI returned non-JSON (exit {proc.returncode}): {line[:500]}",
            code="transport_error",
        ) from exc

    if isinstance(data, dict):
        data.setdefault("exit_code", proc.returncode)
        data.setdefault("workspace_root", root)
        if data.get("approvalRequired"):
            approval = data.get("approval") if isinstance(data.get("approval"), dict) else {}
            _emit_task_event(
                "approval.required",
                approvalId=approval.get("approvalId"),
                action=action_label,
                preview=approval.get("preview"),
            )
        elif data.get("applied") or data.get("mutationReceipt"):
            receipt = data.get("mutationReceipt") if isinstance(data.get("mutationReceipt"), dict) else {}
            _emit_task_event(
                "file.diff",
                path=receipt.get("path") or data.get("path"),
                action=action_label,
            )
        _emit_task_event(
            "tool.call.completed",
            action=action_label,
            ok=proc.returncode == 0 and data.get("ok") is not False,
            approvalRequired=bool(data.get("approvalRequired")),
        )
        if proc.returncode != 0 or data.get("ok") is False:
            if data.get("ok") is not False:
                data["ok"] = False
            if proc.returncode != 0:
                invalidate_preflight_cache()
            raise _parse_bridge_error(data)
        return data

    return {
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "workspace_root": root,
        "data": data,
    }


def run_bridge(
    args: list[str],
    *,
    workspace: Optional[str] = None,
    auto_start: Optional[bool] = None,
    wait_ready: bool = False,
    timeout: Optional[float] = None,
    max_results: Optional[int] = None,
    idempotency_key: Optional[str] = None,
    retry_on_failure: bool = True,
) -> dict[str, Any]:
    """Run ``dietcode-agent-client`` with preflight and one transport reconnect retry."""
    ide_cfg = _load_ide_config()
    if not ide_cfg.enabled:
        raise IdeBridgeError("dietcode.ide.enabled is false", code="ide_disabled")

    preflight = connect_preflight(warm=False)
    if not preflight.get("ok"):
        raise IdeBridgeError(
            str(preflight.get("error") or "IDE bridge preflight failed"),
            code=str(preflight.get("action") or "preflight_failed"),
            recovery_hint="run_setup_hermes_bridge",
            retry_safe=True,
        )

    try:
        return _execute_bridge_call(
            args,
            workspace=workspace,
            auto_start=auto_start,
            wait_ready=wait_ready,
            timeout=timeout,
            max_results=max_results,
            idempotency_key=idempotency_key,
        )
    except IdeBridgeError as exc:
        if not retry_on_failure or not exc.retry_safe or exc.code not in _RETRYABLE_CODES:
            raise
        logger.info("DietCode IDE bridge retry after %s", exc.code)
        reconnect_bridge()
        return _execute_bridge_call(
            args,
            workspace=workspace,
            auto_start=True,
            wait_ready=True,
            timeout=timeout,
            max_results=max_results,
            idempotency_key=idempotency_key,
        )
