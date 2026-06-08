#!/usr/bin/env python3
"""Mutation authority audit — bridge patch telemetry vs workspace file changes."""

from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from pathlib import Path
from typing import Any

EXCLUDED_DIR_NAMES = frozenset({
    "__pycache__",
    ".git",
    ".agent_patches",
    "node_modules",
    "build",
    "dist",
    ".dietcode",
    ".hermes",
})
MAX_MANIFEST_FILE_BYTES = 1_048_576

RAW_WRITE_TRANSCRIPT_PATTERNS = tuple(
    re.compile(pat, re.IGNORECASE)
    for pat in (
        r"\bwrite_file\b",
        r"python\s+-c\s+.*open\s*\(",
        r"\bcat\s*>",
        r"\btee\s+",
        r"\bsed\s+-i\b",
        r"multi_replace_file_content",
        r"replace_file_content",
    )
)


def mutation_event_log_path(run_id: str | None = None) -> Path:
    rid = run_id or uuid.uuid4().hex[:16]
    return Path.home() / ".dietcode" / "agent-chat" / "events" / f"{rid}.jsonl"


def _rel_path(path: Path, workspace: Path) -> str:
    try:
        return path.resolve().relative_to(workspace.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def _path_inside_workspace(path: str, workspace: Path) -> bool:
    try:
        resolved = (workspace / path).resolve() if not Path(path).is_absolute() else Path(path).resolve()
        resolved.relative_to(workspace.resolve())
        return True
    except (OSError, ValueError):
        return False


def workspace_manifest(workspace: Path) -> dict[str, str]:
    """Content-hash manifest for auditable files (excludes volatile dirs)."""
    root = workspace.resolve()
    manifest: dict[str, str] = {}
    if not root.is_dir():
        return manifest
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIR_NAMES and not d.startswith(".")]
        base = Path(dirpath)
        for name in filenames:
            if name.startswith("."):
                continue
            file_path = base / name
            try:
                if file_path.stat().st_size > MAX_MANIFEST_FILE_BYTES:
                    continue
                rel = _rel_path(file_path, root)
                digest = hashlib.sha256(file_path.read_bytes()).hexdigest()
                manifest[rel] = digest
            except OSError:
                continue
    return manifest


def diff_manifests(before: dict[str, str], after: dict[str, str]) -> list[str]:
    changed: list[str] = []
    keys = set(before) | set(after)
    for key in sorted(keys):
        if before.get(key) != after.get(key):
            changed.append(key)
    return changed


def read_mutation_event_log(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    events: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("DIETCODE_MUTATION_EVENT:"):
            line = line.split(":", 1)[1]
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if payload.get("eventType") == "mutation.patch.applied":
            events.append(payload)
    return events


def parse_timeline_patch_events(timeline_payload: dict[str, Any], workspace: Path) -> list[dict[str, Any]]:
    """Best-effort patch events from runtime.timeline."""
    result = timeline_payload.get("result")
    if not isinstance(result, dict):
        result = timeline_payload
    events = result.get("events") if isinstance(result, dict) else None
    if not isinstance(events, list):
        return []
    patches: list[dict[str, Any]] = []
    for item in events:
        if not isinstance(item, dict):
            continue
        event_type = str(item.get("eventType") or "")
        method = str(item.get("method") or "")
        if event_type != "mutation_applied" and method != "patch.apply":
            continue
        receipt = item.get("receipt") if isinstance(item.get("receipt"), dict) else {}
        path = str(receipt.get("path") or item.get("path") or "")
        if not path:
            payload = item.get("payload")
            if isinstance(payload, dict):
                path = str(payload.get("path") or "")
        if not path:
            continue
        patches.append(
            {
                "eventType": "mutation.patch.applied",
                "workspace": str(workspace),
                "path": path,
                "beforeHash": str(receipt.get("beforeContentHash") or receipt.get("beforeHash") or ""),
                "afterHash": str(receipt.get("postContentHash") or receipt.get("afterHash") or ""),
                "tool": "dietcode_ide.patch",
                "protocol": "runtime.timeline",
            }
        )
    return patches


def merge_patch_events(*sources: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for source in sources:
        for event in source:
            path = str(event.get("path") or "")
            key = f"{path}:{event.get('beforeHash')}:{event.get('afterHash')}"
            if key in seen:
                continue
            seen.add(key)
            merged.append(event)
    return merged


def scan_transcript_suspicions(transcript: str) -> list[str]:
    evidence: list[str] = []
    for pattern in RAW_WRITE_TRANSCRIPT_PATTERNS:
        if pattern.search(transcript or ""):
            evidence.append(f"transcript_suspicion:{pattern.pattern}")
    return evidence


def audit_mutation_authority(
    workspace: Path,
    *,
    before_manifest: dict[str, str],
    after_manifest: dict[str, str],
    bridge_events: list[dict[str, Any]],
    transcript: str = "",
) -> dict[str, Any]:
    workspace = workspace.resolve()
    changed = diff_manifests(before_manifest, after_manifest)
    evidence: list[str] = []

    for event in bridge_events:
        path = str(event.get("path") or "")
        if path and not _path_inside_workspace(path, workspace):
            evidence.append(f"bridge_path_outside_workspace:{path}")
            return {
                "mode": "violated",
                "bridgePatchCount": len(bridge_events),
                "rawWriteSuspected": True,
                "mutatedFiles": changed,
                "evidence": evidence,
            }

    bridge_paths = {_rel_path(Path(str(e.get("path") or "")), workspace) if Path(str(e.get("path") or "")).is_absolute() else str(e.get("path") or "") for e in bridge_events}
    bridge_paths = {p for p in bridge_paths if p}

    unmatched = [p for p in changed if p not in bridge_paths]
    raw_write_suspected = bool(unmatched)
    evidence.extend(scan_transcript_suspicions(transcript))
    if unmatched:
        evidence.extend(f"changed_without_bridge_event:{p}" for p in unmatched)

    if not changed:
        mode = "no_mutation"
    elif bridge_events and not unmatched:
        mode = "bridge_only"
    elif changed and not bridge_events:
        mode = "violated"
        raw_write_suspected = True
    elif unmatched and bridge_events:
        mode = "unknown"
    else:
        mode = "unknown"

    return {
        "mode": mode,
        "bridgePatchCount": len(bridge_events),
        "rawWriteSuspected": raw_write_suspected,
        "mutatedFiles": changed,
        "evidence": evidence,
    }


def mutation_authority_label(mode: str) -> str:
    labels = {
        "bridge_only": "Bridge verified",
        "no_mutation": "No mutation",
        "unknown": "Unknown — review run",
        "violated": "Violation — agent disabled",
    }
    return labels.get(mode, "Unknown — review run")


def collect_bridge_patch_events(ctx: Any, workspace: Path, event_log: Path) -> list[dict[str, Any]]:
    from dietcode_agent_bundle import fetch_bridge_timeline

    log_events = read_mutation_event_log(event_log)
    timeline_payload = fetch_bridge_timeline(ctx, workspace, limit=80)
    timeline_events = parse_timeline_patch_events(timeline_payload, workspace)
    return merge_patch_events(log_events, timeline_events)


def empty_mutation_authority() -> dict[str, Any]:
    return {
        "mode": "no_mutation",
        "bridgePatchCount": 0,
        "rawWriteSuspected": False,
        "mutatedFiles": [],
        "evidence": [],
    }
