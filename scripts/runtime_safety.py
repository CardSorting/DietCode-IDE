#!/usr/bin/env python3
"""
SAFETY: Local runtime abuse-resistance constants, redaction, and socket audit.

Grep: rg 'SAFETY:|RUNTIME_LIMITS|redact_' scripts/runtime_safety.py docs/runtime-invariants.md
"""

from __future__ import annotations

import os
import re
import stat
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
LIMITS_HEADER = REPO_ROOT / "src/domain/control/ControlRuntimeLimits.hpp"
METHOD_CATALOG = REPO_ROOT / "src/platform/macos/control/services/MacControlMethodCatalog.mm"

# SAFETY: Mirror of ControlRuntimeLimits.hpp (verified by test_runtime_safety.py).
RUNTIME_LIMITS: dict[str, int] = {
    "kMaxRequestBytes": 1024 * 1024,
    "kMaxResponseBytes": 4 * 1024 * 1024,
    "kMaxActiveConnections": 8,
    "kMaxPendingRequestsPerConnection": 32,
    "kMaxMalformedRequestsPerConnection": 16,
    "kMaxNestedCallWaitSeconds": 120,
    "kSocketListenBacklog": 5,
    "kMaxRuntimeDiagnosticLogBytes": 5 * 1024 * 1024,
    "kMaxAuditLogBytes": 5 * 1024 * 1024,
    "kMaxFailureBundleBytes": 2 * 1024 * 1024,
    "kSocketFileMode": 0o600,
    "kDietcodeDirMode": 0o700,
}

SAFETY_ERROR_CODES = frozenset({
    "connection_limit_exceeded",
    "too_many_pending",
    "malformed_request_flood",
    "nested_call_timeout",
    "socket_symlink",
    "socket_wrong_owner",
    "socket_unsafe_permissions",
    "socket_unsafe_type",
    "socket_unsafe_path",
    "request_too_large",
})

REDACTED_ENV_SUFFIXES = ("_TOKEN", "_SECRET", "_KEY", "_PASSWORD", "_CREDENTIAL")
REDACT_TOKEN_PATTERN = re.compile(r"\b[0-9a-f]{32}\b", re.IGNORECASE)
REDACT_BEARER_PATTERN = re.compile(r"Bearer\s+\S+", re.IGNORECASE)


def parse_limits_from_header(path: Path = LIMITS_HEADER) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    limits: dict[str, int] = {}
    for match in re.finditer(r"constexpr\s+[\w\s]+\s+(k\w+)\s*=\s*([^;]+);", text):
        name, raw = match.group(1), match.group(2).strip()
        if name in ("kSocketFileMode", "kDietcodeDirMode"):
            limits[name] = int(raw, 8)
        elif "*" in raw:
            parts = re.split(r"\s*\*\s*", raw.replace(" ", ""))
            value = 1
            for part in parts:
                if part.isdigit():
                    value *= int(part)
                elif part.startswith("1024"):
                    value *= 1024
            limits[name] = value
        elif raw.isdigit():
            limits[name] = int(raw)
    return limits


def audit_socket_path(path: str) -> dict[str, Any]:
    expanded = os.path.expanduser(path)
    parent = os.path.dirname(expanded)
    result: dict[str, Any] = {
        "path": expanded,
        "safe": True,
        "issues": [],
        "stringCode": None,
        "checks": {},
    }

    def _check(target: str) -> dict[str, Any] | None:
        try:
            st = os.lstat(target)
        except FileNotFoundError:
            return None
        except OSError as exc:
            return {"exists": False, "error": str(exc)}
        mode = stat.S_IMODE(st.st_mode)
        entry = {
            "exists": True,
            "isSymlink": stat.S_ISLNK(st.st_mode),
            "mode": oct(mode),
            "uid": st.st_uid,
            "ownerIsCurrentUser": st.st_uid == os.getuid(),
        }
        if entry["isSymlink"]:
            result["issues"].append("socket_symlink")
            result["stringCode"] = "socket_symlink"
            result["safe"] = False
        elif not entry["ownerIsCurrentUser"]:
            result["issues"].append("socket_wrong_owner")
            result["stringCode"] = "socket_wrong_owner"
            result["safe"] = False
        return entry

    result["checks"]["parent"] = _check(parent)
    result["checks"]["socket"] = _check(expanded)
    if result["checks"]["socket"] and result["checks"]["socket"].get("mode") not in (None, oct(RUNTIME_LIMITS["kSocketFileMode"])):
        mode = result["checks"]["socket"].get("mode")
        if mode and mode not in ("0o600", "0o1400"):  # allow setgid artifacts on some FS
            if int(mode, 8) & 0o077:
                result["issues"].append("socket_unsafe_permissions")
                result["stringCode"] = result["stringCode"] or "socket_unsafe_permissions"
                result["safe"] = False
    return result


def redact_text(text: str) -> str:
    redacted = REDACT_BEARER_PATTERN.sub("Bearer [REDACTED]", text)
    redacted = REDACT_TOKEN_PATTERN.sub("[REDACTED_TOKEN]", redacted)
    return redacted


def redact_env(env: dict[str, str | None]) -> dict[str, Any]:
    redacted: dict[str, Any] = {}
    for key, value in env.items():
        upper = key.upper()
        if any(upper.endswith(suffix) or suffix in upper for suffix in REDACTED_ENV_SUFFIXES):
            redacted[key] = "[REDACTED]" if value else None
        else:
            redacted[key] = value
    return redacted


def redact_diagnostic_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    cleaned = dict(snapshot)
    if "environment" in cleaned and isinstance(cleaned["environment"], dict):
        cleaned["environment"] = redact_env(cleaned["environment"])
    if "token" in cleaned and isinstance(cleaned["token"], dict):
        token = dict(cleaned["token"])
        token.pop("contents", None)
        cleaned["token"] = token
    if "rpcPing" in cleaned:
        cleaned["rpcPing"] = redact_object(cleaned["rpcPing"])
    if "recentRuntimeLogs" in cleaned and isinstance(cleaned["recentRuntimeLogs"], list):
        cleaned["recentRuntimeLogs"] = [redact_object(line) for line in cleaned["recentRuntimeLogs"]]
    return cleaned


def redact_object(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: redact_object(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact_object(v) for v in value]
    if isinstance(value, str):
        return redact_text(value)
    return value


def truncate_text(text: str, max_bytes: int) -> str:
    encoded = text.encode("utf-8", errors="replace")
    if len(encoded) <= max_bytes:
        return text
    truncated = encoded[:max_bytes].decode("utf-8", errors="ignore")
    return truncated + "\n[TRUNCATED]"


def redact_failure_bundle(bundle: dict[str, Any]) -> dict[str, Any]:
    max_bytes = RUNTIME_LIMITS["kMaxFailureBundleBytes"]
    cleaned = dict(bundle)
    for field in ("stdout", "stderr", "gitDiff"):
        if field in cleaned and isinstance(cleaned[field], str):
            cleaned[field] = truncate_text(redact_text(cleaned[field]), max_bytes // 4)
    if "rg" in cleaned and isinstance(cleaned["rg"], dict):
        cleaned["rg"] = {k: truncate_text(redact_text(v), max_bytes // 8) for k, v in cleaned["rg"].items()}
    cleaned["redacted"] = True
    return cleaned


def extract_method_permissions(catalog_text: str | None = None) -> dict[str, list[str]]:
    text = catalog_text or METHOD_CATALOG.read_text(encoding="utf-8")
    methods: dict[str, list[str]] = {"read": [], "edit": [], "execute": [], "destructive": []}
    for match in re.finditer(r'@"name": @"([^"]+)".*?@"permission": @"([^"]+)"', text, re.DOTALL):
        name, perm = match.group(1), match.group(2)
        lower = perm.lower()
        if "destructive" in lower:
            methods["destructive"].append(name)
        elif "execute" in lower:
            methods["execute"].append(name)
        elif "edit" in lower:
            methods["edit"].append(name)
        else:
            methods["read"].append(name)
    for key in methods:
        methods[key] = sorted(set(methods[key]))
    return methods


def load_destructive_methods_fixture() -> list[str]:
    fixture = REPO_ROOT / "scripts/fixtures/safety/destructive_methods.json"
    if fixture.is_file():
        import json

        data = json.loads(fixture.read_text(encoding="utf-8"))
        return list(data.get("methods", []))
    return extract_method_permissions()["destructive"]
