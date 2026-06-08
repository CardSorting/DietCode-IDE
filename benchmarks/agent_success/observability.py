#!/usr/bin/env python3
"""Lightweight observability event taxonomy (OpenTelemetry-aligned, local JSON)."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ObservabilityRecorder:
    """Correlated trace/span events for orchestrated mutation runs."""

    trace_id: str = field(default_factory=lambda: uuid.uuid4().hex)
    _span_seq: int = 0
    events: list[dict[str, Any]] = field(default_factory=list)

    def _next_span_id(self) -> str:
        self._span_seq += 1
        return f"{self._span_seq:04x}"

    def emit(
        self,
        event_type: str,
        *,
        task_id: str,
        attempt: int | None = None,
        contract: str | None = None,
        protocol: str | None = None,
        failure_class: str | None = None,
        extra: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "eventType": event_type,
            "traceId": self.trace_id,
            "spanId": self._next_span_id(),
            "taskId": task_id,
        }
        if attempt is not None:
            payload["attempt"] = attempt
        if contract is not None:
            payload["contract"] = contract
        if protocol is not None:
            payload["protocol"] = protocol
        if failure_class is not None:
            payload["failureClass"] = failure_class
        if extra:
            payload.update(extra)
        self.events.append(payload)
        return payload
