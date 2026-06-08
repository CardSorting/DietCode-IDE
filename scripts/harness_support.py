#!/usr/bin/env python3
"""HARNESS: Realistic fixture workspaces for Pass IV integration tests."""

from __future__ import annotations

import os
import shutil
import socket
import tempfile
import threading
from pathlib import Path
from typing import Any

SEED_FIXTURE = "harness-pass4-v1"


def create_symlink_fixture_workspace(base: Path | None = None) -> tuple[Path, dict[str, str]]:
    """Create an isolated workspace with normal files and symlink edge cases."""
    root = Path(base) if base else Path(tempfile.mkdtemp(prefix="dietcode_symlink_harness_"))
    root.mkdir(parents=True, exist_ok=True)
    outside = root.parent / f"{root.name}_outside"
    outside.mkdir(exist_ok=True)
    (outside / "secret.txt").write_text("outside secret\n", encoding="utf-8")

    subdir = root / "subdir"
    subdir.mkdir(exist_ok=True)
    (root / "normal.txt").write_text("normal content\n", encoding="utf-8")
    (subdir / "real_file.txt").write_text("real in subdir\n", encoding="utf-8")
    (root / "link_inside.txt").symlink_to("normal.txt")
    (root / "link_dir").symlink_to("subdir")
    (root / "escape_link").symlink_to(outside / "secret.txt")
    nested = root / "nested_escape"
    nested.mkdir(exist_ok=True)
    rel_outside = os.path.relpath(outside / "secret.txt", nested)
    (nested / "sub").symlink_to(rel_outside)
    (root / "broken_link").symlink_to("missing_target.txt")

    paths = {
        "root": str(root),
        "outside": str(outside),
        "normal": "normal.txt",
        "link_inside": "link_inside.txt",
        "link_dir": "link_dir",
        "escape_link": "escape_link",
        "broken_link": "broken_link",
        "nested_escape": "nested_escape/sub",
        "subdir_real": "subdir/real_file.txt",
    }
    return root, paths


def cleanup_fixture_workspace(root: Path, outside_name: str | None = None) -> None:
    outside = root.parent / f"{root.name}_outside" if outside_name is None else Path(outside_name)
    if root.exists():
        shutil.rmtree(root, ignore_errors=True)
    if outside.exists():
        shutil.rmtree(outside, ignore_errors=True)


def socketpair_drop_after_request(
    success_response: dict[str, Any],
) -> tuple[socket.socket, threading.Thread]:
    """Mock server that closes socket after accepting one request (simulates disconnect)."""
    client_sock, server_sock = socket.socketpair()

    def serve() -> None:
        try:
            request_buffer = bytearray()
            while b"\n" not in request_buffer:
                chunk = server_sock.recv(65536)
                if not chunk:
                    return
                request_buffer.extend(chunk)
            # Simulate lost response: close without sending reply.
            server_sock.close()
        finally:
            pass

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return client_sock, thread


def socketpair_timeout_then_success(
    delay_before_response: float,
    response: dict[str, Any],
) -> tuple[socket.socket, threading.Thread]:
    """Mock server that delays response beyond client timeout."""
    import json
    import time

    client_sock, server_sock = socket.socketpair()

    def serve() -> None:
        try:
            request_buffer = bytearray()
            while b"\n" not in request_buffer:
                chunk = server_sock.recv(65536)
                if not chunk:
                    return
                request_buffer.extend(chunk)
            time.sleep(delay_before_response)
            payload = json.dumps(response, separators=(",", ":")).encode("utf-8") + b"\n"
            server_sock.sendall(payload)
        finally:
            server_sock.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return client_sock, thread
