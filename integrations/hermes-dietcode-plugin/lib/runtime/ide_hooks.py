# -*- coding: utf-8 -*-
"""DietCode IDE bridge hooks — auto-connect, workspace bootstrap, write routing."""
from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

_IDE_READY_ATTR = "_dietcode_ide_ready"


def _emit_coherence_task_event(payload: dict[str, Any]) -> None:
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import _emit_task_event

        if payload.get("operatorInterventionRequired"):
            _emit_task_event(
                "coherence.operator_required",
                path=payload.get("path"),
                reason=payload.get("reason"),
                changedPaths=payload.get("changedPaths"),
            )
        elif payload.get("coherenceStale"):
            _emit_task_event(
                "context.stale",
                path=payload.get("path"),
                reason=payload.get("reason"),
                changedPaths=payload.get("changedPaths"),
            )
    except Exception as exc:
        logger.debug("DietCode IDE coherence task event skipped: %s", exc)


def _set_manager_ready(ready: bool) -> None:
    try:
        from hermes_cli.plugins import get_plugin_manager

        setattr(get_plugin_manager(), _IDE_READY_ATTR, ready)
    except Exception:
        pass


def _on_session_start(**_: object) -> None:
    """Warm DietCode IDE bridge: build, socket, verify, open workspace."""
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import (
            _load_ide_config,
            bootstrap_agent_workspace,
            connect_preflight,
        )

        cfg = _load_ide_config()
        if not cfg.enabled:
            _set_manager_ready(False)
            return

        result = connect_preflight(warm=True, force=True)
        ready = bool(result.get("ok"))
        _set_manager_ready(ready)

        if ready:
            logger.info(
                "DietCode IDE bridge ready (socket=%s, latencyMs=%s)",
                result.get("socket_path"),
                (result.get("steps") or {}).get("verify", {}).get("latencyMs"),
            )
            ws = os.environ.get("HERMES_KANBAN_WORKSPACE", "").strip() or os.environ.get(
                "DIETCODE_WORKSPACE", ""
            ).strip()
            if ws or cfg.auto_open_workspace:
                ws_result = bootstrap_agent_workspace(ws or None)
                if not ws_result.get("ok"):
                    logger.warning("DietCode IDE workspace bootstrap: %s", ws_result.get("error"))
        else:
            logger.warning(
                "DietCode IDE bridge preflight incomplete: %s — call dietcode_ide(action='connect')",
                result.get("error") or result.get("action"),
            )
    except Exception as exc:
        _set_manager_ready(False)
        logger.debug("DietCode IDE bridge session hook skipped: %s", exc)


def _pre_tool_call(tool_name: str = "", args: Any = None, **_: Any) -> dict[str, str] | None:
    """Route governed writes through dietcode_ide when the bridge is live."""
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import (
            _load_ide_config,
            is_ide_bridge_ready,
            is_raw_write_tool,
        )
        from plugins.dietcode.lib.agent.joyzoning.convergence_gate import block_dict

        cfg = _load_ide_config()
        if not cfg.enabled or not cfg.prefer_over_raw_writes:
            return None
        if not is_raw_write_tool(tool_name):
            return None
        if not is_ide_bridge_ready():
            return None

        rel = ""
        if isinstance(args, dict):
            rel = str(args.get("path") or args.get("file_path") or args.get("target") or "").strip()

        hint = (
            "DietCode IDE bridge is connected — use dietcode_ide for safe mutations with receipts. "
            "Example: dietcode_ide(action='patch', path='"
            f"{rel or '<path>'}"
            "', unified_diff='...'). "
            "For reads: dietcode_ide(action='shell_rg'|'stat'|'search_literal'). "
            "Set dietcode.ide.prefer_over_raw_writes: false to allow raw write_file/patch."
        )
        return block_dict(hint)
    except Exception as exc:
        logger.debug("DietCode IDE pre_tool_call skipped: %s", exc)
        return None


def _post_tool_call(
    *,
    tool_name: str = "",
    args: Any = None,
    result: Any = None,
    **_: Any,
) -> None:
    """Refresh bridge readiness after connect/verify; log IDE patch outcomes."""
    if tool_name != "dietcode_ide":
        return
    try:
        from plugins.dietcode.lib.agent.ide_bridge_client import reconnect_bridge

        action = ""
        if isinstance(args, dict):
            action = str(args.get("action") or "").strip().lower()

        if action in ("connect", "verify"):
            report = reconnect_bridge()
            _set_manager_ready(bool(report.get("ok")))
            return

        if action not in ("patch", "patch_batch"):
            return

        if not isinstance(result, str):
            return

        payload: dict[str, Any] | None = None
        try:
            import json

            payload = json.loads(result)
        except json.JSONDecodeError:
            return

        if not isinstance(payload, dict):
            return

        if payload.get("applied") or payload.get("ok"):
            logger.info(
                "DietCode IDE mutation via %s (idempotency=%s)",
                action,
                payload.get("idempotencyKey") or payload.get("idempotency_key"),
            )
        elif payload.get("stale"):
            logger.warning("DietCode IDE stale patch on %s — revalidate before retry", action)
        elif payload.get("coherenceStale"):
            changed = payload.get("changedPaths") or []
            logger.warning(
                "DietCode IDE coherence stale on %s — re-read changed paths before retry: %s",
                action,
                changed,
            )
            _emit_coherence_task_event(payload)
        elif payload.get("operatorInterventionRequired"):
            logger.warning(
                "DietCode IDE coherence recovery exhausted on %s — operator intervention required",
                action,
            )
            _emit_coherence_task_event(payload)
    except Exception as exc:
        logger.debug("DietCode IDE post_tool_call skipped: %s", exc)
