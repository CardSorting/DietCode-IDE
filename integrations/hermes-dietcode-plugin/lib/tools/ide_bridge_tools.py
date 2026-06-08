"""DietCode IDE bridge tools — Hermes agents mutate/search via Agent Bridge."""
from __future__ import annotations

import json
import tempfile
import uuid
from pathlib import Path
from typing import Optional

from tools.registry import registry, tool_error

_ACTIONS = frozenset({
    "connect",
    "profile",
    "verify",
    "diagnostics",
    "search_literal",
    "search_tokens",
    "search_paths",
    "stat",
    "patch",
    "patch_batch",
    "operation_status",
    "timeline",
    "activity",
    "shell_pwd",
    "shell_cd",
    "shell_rg",
    "shell_head",
    "shell_tail",
    "shell_sed",
    "shell_cat_small",
})


def _default_idempotency_key(path: str) -> str:
    return f"hermes:patch:{path}:{uuid.uuid4().hex[:12]}"


def dietcode_ide(
    action: str,
    *,
    query: str = "",
    tokens: str = "",
    path: str = "",
    unified_diff: str = "",
    patch_batch_json: str = "",
    pattern: str = "",
    lines: int = 20,
    start_line: int = 1,
    end_line: int = 1,
    workspace: Optional[str] = None,
    max_results: int = 20,
    idempotency_key: str = "",
    since_revision: int = 0,
    timeline_limit: int = 50,
) -> str:
    """DietCode IDE Agent Bridge — deterministic search and safe patch via DietCode runtime."""
    act = (action or "").strip().lower()
    if act not in _ACTIONS:
        return tool_error(
            f"Unknown action {action!r}. Use: {', '.join(sorted(_ACTIONS))}. "
            "Prefer dietcode_ide over raw write_file/patch when the DietCode IDE is connected."
        )

    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import IdeBridgeError, connect_preflight, run_bridge
    except ImportError as exc:
        return tool_error(f"DietCode IDE bridge unavailable: {exc}")

    bridge_kwargs = {
        "workspace": workspace,
        "max_results": max_results if max_results > 0 else None,
        "idempotency_key": idempotency_key.strip() or None,
    }

    try:
        if act == "connect":
            return json.dumps(connect_preflight(warm=True, force=True))

        if act == "profile":
            return json.dumps(run_bridge(["profile"], **bridge_kwargs))

        if act == "verify":
            return json.dumps(run_bridge(["verify", "fast"], **bridge_kwargs))

        if act == "diagnostics":
            return json.dumps(run_bridge(["diagnostics"], **bridge_kwargs))

        if act == "search_literal":
            if not query.strip():
                return tool_error("query required for search_literal")
            return json.dumps(
                run_bridge(["search", "literal", query.strip()], **bridge_kwargs)
            )

        if act == "search_tokens":
            token_list = [t.strip() for t in (tokens or query).split() if t.strip()]
            if not token_list:
                return tool_error("tokens required for search_tokens (space-separated)")
            return json.dumps(
                run_bridge(["search", "tokens", *token_list], **bridge_kwargs)
            )

        if act == "search_paths":
            if not query.strip():
                return tool_error("query required for search_paths")
            return json.dumps(
                run_bridge(["search", "paths", query.strip()], **bridge_kwargs)
            )

        if act == "stat":
            if not path.strip():
                return tool_error("path required for stat")
            return json.dumps(run_bridge(["stat", path.strip()], **bridge_kwargs))

        if act == "patch":
            if not path.strip():
                return tool_error("path required for patch")
            if not unified_diff.strip():
                return tool_error("unified_diff required for patch")
            key = idempotency_key.strip() or _default_idempotency_key(path.strip())
            with tempfile.NamedTemporaryFile("w", suffix=".patch", delete=False, encoding="utf-8") as handle:
                handle.write(unified_diff)
                diff_path = handle.name
            try:
                return json.dumps(
                    run_bridge(
                        ["patch", "safe-file", path.strip(), diff_path],
                        idempotency_key=key,
                        timeout=180.0,
                        workspace=workspace,
                    )
                )
            finally:
                Path(diff_path).unlink(missing_ok=True)

        if act == "patch_batch":
            if not patch_batch_json.strip():
                return tool_error("patch_batch_json required — JSON array of {path, unifiedDiff}")
            key = idempotency_key.strip() or f"hermes:batch:{uuid.uuid4().hex[:12]}"
            return json.dumps(
                run_bridge(
                    ["patch", "safe-batch", patch_batch_json.strip()],
                    idempotency_key=key,
                    timeout=300.0,
                    workspace=workspace,
                )
            )

        if act == "operation_status":
            key = idempotency_key.strip()
            if not key:
                return tool_error("idempotency_key required for operation_status")
            return json.dumps(
                run_bridge(
                    ["operation", "status", key],
                    workspace=workspace,
                )
            )

        if act == "timeline":
            args = ["timeline", "recent"]
            if timeline_limit > 0:
                args.extend(["--limit", str(timeline_limit)])
            if since_revision > 0:
                args.extend(["--since-revision", str(since_revision)])
            return json.dumps(run_bridge(args, workspace=workspace))

        if act == "activity":
            args = ["activity", "recent"]
            if timeline_limit > 0:
                args.extend(["--limit", str(timeline_limit)])
            return json.dumps(run_bridge(args, workspace=workspace))

        if act == "shell_pwd":
            return json.dumps(run_bridge(["shell", "pwd"], workspace=workspace))

        if act == "shell_cd":
            if not path.strip():
                return tool_error("path required for shell_cd")
            return json.dumps(run_bridge(["shell", "cd", path.strip()], workspace=workspace))

        if act == "shell_rg":
            pat = (pattern or query).strip()
            if not pat:
                return tool_error("pattern required for shell_rg")
            args = ["shell", "rg", pat]
            if path.strip():
                args.extend(["--path", path.strip()])
            return json.dumps(run_bridge(args, workspace=workspace))

        if act == "shell_head":
            if not path.strip():
                return tool_error("path required for shell_head")
            args = ["shell", "head", path.strip()]
            if lines > 0:
                args.extend(["--lines", str(lines)])
            return json.dumps(run_bridge(args, workspace=workspace))

        if act == "shell_tail":
            if not path.strip():
                return tool_error("path required for shell_tail")
            args = ["shell", "tail", path.strip()]
            if lines > 0:
                args.extend(["--lines", str(lines)])
            return json.dumps(run_bridge(args, workspace=workspace))

        if act == "shell_sed":
            if not path.strip():
                return tool_error("path required for shell_sed")
            return json.dumps(
                run_bridge(
                    ["shell", "sed", path.strip(), str(start_line), str(end_line)],
                    workspace=workspace,
                )
            )

        if act == "shell_cat_small":
            if not path.strip():
                return tool_error("path required for shell_cat_small")
            return json.dumps(
                run_bridge(["shell", "cat-small", path.strip()], workspace=workspace)
            )

        return tool_error(f"unhandled action: {act}")
    except IdeBridgeError as exc:
        return json.dumps(exc.to_dict(), ensure_ascii=False)
    except Exception as exc:
        return tool_error(f"dietcode_ide failed: {exc}")


registry.register(
    name="dietcode_ide",
    toolset="dietcode",
    schema={
        "name": "dietcode_ide",
        "description": (
            "DietCode IDE Agent Bridge — deterministic search, safe patch with receipts, "
            "operation replay, and bounded shell reads through the DietCode C++ mutation kernel. "
            "Use instead of write_file/patch when connected. Start with action=connect or verify."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": sorted(_ACTIONS),
                    "description": (
                        "connect=preflight+verify; profile/diagnostics=runtime; "
                        "search_*=deterministic search; stat=hash metadata; "
                        "patch/patch_batch=validated apply; operation_status=timeout recovery; "
                        "timeline/activity=journal; shell_*=bounded reads"
                    ),
                },
                "query": {"type": "string", "description": "Search query or rg pattern"},
                "tokens": {"type": "string", "description": "Space-separated tokens (search_tokens)"},
                "path": {"type": "string", "description": "Workspace-relative file path"},
                "unified_diff": {"type": "string", "description": "Unified diff for patch"},
                "patch_batch_json": {"type": "string", "description": "JSON [{path, unifiedDiff}, ...] for patch_batch"},
                "pattern": {"type": "string", "description": "Ripgrep pattern (shell_rg)"},
                "lines": {"type": "integer", "default": 20},
                "start_line": {"type": "integer", "default": 1},
                "end_line": {"type": "integer", "default": 1},
                "workspace": {"type": "string", "description": "Override workspace root"},
                "max_results": {"type": "integer", "default": 20},
                "idempotency_key": {"type": "string", "description": "Replay key for patch/operation_status"},
                "since_revision": {"type": "integer", "default": 0},
                "timeline_limit": {"type": "integer", "default": 50},
            },
            "required": ["action"],
        },
    },
    handler=lambda args, **kw: dietcode_ide(
        args.get("action", ""),
        query=args.get("query", ""),
        tokens=args.get("tokens", ""),
        path=args.get("path", ""),
        unified_diff=args.get("unified_diff", ""),
        patch_batch_json=args.get("patch_batch_json", ""),
        pattern=args.get("pattern", ""),
        lines=int(args.get("lines", 20) or 20),
        start_line=int(args.get("start_line", 1) or 1),
        end_line=int(args.get("end_line", 1) or 1),
        workspace=args.get("workspace"),
        max_results=int(args.get("max_results", 20) or 20),
        idempotency_key=args.get("idempotency_key", ""),
        since_revision=int(args.get("since_revision", 0) or 0),
        timeline_limit=int(args.get("timeline_limit", 50) or 50),
    ),
)
