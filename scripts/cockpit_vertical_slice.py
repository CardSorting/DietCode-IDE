#!/usr/bin/env python3
"""Vertical-slice validation: prompt → patch → approval → verify → completion."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, TypeVar

T = TypeVar("T")

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
FIXTURES_ROOT = SCRIPTS / "fixtures" / "cockpit_smoke"
DEFAULT_BRIDGE_PORT = int(os.environ.get("COCKPIT_BRIDGE_PORT", "9477"))
DEFAULT_TIMEOUT = float(os.environ.get("COCKPIT_SMOKE_TIMEOUT", "180"))

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from dietcode_agent_client import connect, load_token, send_rpc  # noqa: E402

FIXTURES = [
    {"name": "npm-test", "dir": "npm-test", "verify": "npm test"},
    {"name": "make-test", "dir": "make-test", "verify": "make test"},
    {"name": "verify-sh", "dir": "verify-sh", "verify": "./verify.sh"},
]


class Recorder:
    def __init__(self, *, compact: bool) -> None:
        self.compact = compact
        self.events: list[dict[str, Any]] = []

    def check(self, name: str, ok: bool, detail: Any = "") -> None:
        payload: dict[str, Any] = {"type": "check", "name": name, "ok": ok}
        if detail:
            payload["detail"] = detail
        self.events.append(payload)
        if self.compact:
            print(json.dumps(payload), flush=True)
        elif not ok:
            print(f"FAIL {name}: {detail}", file=sys.stderr)

    def finish(self, suite: str) -> int:
        checks = [e for e in self.events if e.get("type") == "check"]
        failed = [e for e in checks if not e["ok"]]
        summary = {
            "type": "summary",
            "suite": suite,
            "passed": len(checks) - len(failed),
            "failed": len(failed),
            "total": len(checks),
            "ok": not failed,
        }
        print(json.dumps(summary), flush=True)
        return 0 if not failed else 1


class BridgeClient:
    def __init__(self, port: int) -> None:
        self.base = f"http://127.0.0.1:{port}"

    def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        timeout: float = 30,
    ) -> dict[str, Any]:
        data = None
        headers = {"Accept": "application/json"}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(f"{self.base}{path}", data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}

    def health(self) -> dict[str, Any]:
        return self._request("GET", "/api/health")

    def session(self) -> dict[str, Any]:
        return self._request("GET", "/api/session")

    def clear_session(self) -> dict[str, Any]:
        return self._request("POST", "/api/session/clear")

    def refresh_workspace_anchor(self) -> dict[str, Any]:
        return self._request("POST", "/api/workspace/refresh-anchor")

    def submit_task(self, *, message: str, workspace: str, mode: str = "smoke") -> dict[str, Any]:
        return self._request(
            "POST",
            "/api/tasks",
            {"message": message, "workspace": workspace, "mode": mode},
        )

    def get_task(self, task_id: str) -> dict[str, Any]:
        return self._request("GET", f"/api/tasks/{task_id}")

    def task_checkpoints(self, task_id: str) -> dict[str, Any]:
        return self._request("GET", f"/api/tasks/{task_id}/checkpoints")

    def list_approvals(self, *, status: str = "pending") -> dict[str, Any]:
        return self._request("GET", f"/api/approvals?status={status}&limit=20")

    def resolve_approval(self, approval_id: str) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/api/approvals/{approval_id}/resolve",
            {
                "decision": "approved",
                "reason": "cockpit-smoke auto-approve",
                "resolvedBy": "cockpit-smoke",
            },
        )

    def run_verify(self, task_id: str, command: str | None = None) -> dict[str, Any]:
        body = {"command": command} if command else {}
        return self._request("POST", f"/api/tasks/{task_id}/run-verify", body)


def wait_until(
    fn: Callable[[], T | None],
    *,
    timeout: float,
    interval: float = 0.3,
    label: str = "condition",
) -> T:
    deadline = time.monotonic() + timeout
    last: Any = None
    while time.monotonic() < deadline:
        last = fn()
        if last is not None:
            return last
        time.sleep(interval)
    raise TimeoutError(f"Timed out waiting for {label}; last={last!r}")


def ensure_kernel(rec: Recorder) -> None:
    client = REPO_ROOT / "scripts" / "dietcode_agent_client.py"
    proc = subprocess.run(
        [sys.executable, str(client), "--wait-ready", "--compact", "--error-json", "--quiet"],
        cwd=REPO_ROOT,
        env={**os.environ, "DIETCODE_REPO_ROOT": str(REPO_ROOT)},
        capture_output=True,
        text=True,
    )
    rec.check("kernel.up", proc.returncode == 0, proc.stderr.strip() or proc.stdout.strip())
    if proc.returncode != 0:
        raise RuntimeError("kernel not ready")


def start_bridge(port: int, session_dir: Path) -> subprocess.Popen[str]:
    env = {
        **os.environ,
        "COCKPIT_BRIDGE_PORT": str(port),
        "DIETCODE_SESSION_DIR": str(session_dir),
        "DIETCODE_REPO_ROOT": str(REPO_ROOT),
    }
    return subprocess.Popen(
        ["npx", "tsx", "server/bridge.ts"],
        cwd=REPO_ROOT / "cockpit",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def ensure_bridge(rec: Recorder, port: int, session_dir: Path) -> subprocess.Popen[str] | None:
    client = BridgeClient(port)
    try:
        health = client.health()
        rec.check("bridge.up", health.get("kernelConnected") is True, health)
        return None
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        pass

    proc = start_bridge(port, session_dir)
    try:
        wait_until(
            lambda: _bridge_health_ok(client),
            timeout=45,
            label="bridge health",
        )
        health = client.health()
        rec.check("bridge.up", health.get("kernelConnected") is True, health)
        return proc
    except TimeoutError:
        proc.terminate()
        rec.check("bridge.up", False, "bridge failed to start")
        raise


def _bridge_health_ok(client: BridgeClient) -> bool | None:
    try:
        health = client.health()
        return True if health.get("kernelConnected") else None
    except (urllib.error.URLError, TimeoutError, ConnectionError):
        return None


PROBE_SOURCE = '"""Smoke probe — patch changes VALUE from 1 to 2."""\n\nVALUE = 1\n'


def prepare_smoke_workspace(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    for fixture in FIXTURES:
        target = root / fixture["dir"]
        source = FIXTURES_ROOT / fixture["dir"]
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(source, target)
        verify_sh = target / "verify.sh"
        if verify_sh.is_file():
            verify_sh.chmod(verify_sh.stat().st_mode | 0o111)


def reset_fixture_probe(fixture_workspace: Path) -> None:
    probe = fixture_workspace / "probe.py"
    probe.write_text(PROBE_SOURCE, encoding="utf-8")


def run_verify_command(workspace: Path, command: str) -> int:
    proc = subprocess.run(
        command,
        cwd=workspace,
        shell=True,
        capture_output=True,
        text=True,
    )
    return proc.returncode


def _resolve_kernel_approval(sock, token: str, response: dict[str, Any]) -> None:
    result = response.get("result") or {}
    if not result.get("approvalRequired"):
        return
    approval = result.get("approval") or {}
    approval_id = approval.get("approvalId")
    if not approval_id:
        raise RuntimeError(f"approvalRequired without approvalId: {response}")
    resolved = send_rpc(
        sock,
        token,
        "approval.resolve",
        {
            "approvalId": approval_id,
            "decision": "approved",
            "reason": "cockpit-smoke workspace setup",
            "resolvedBy": "cockpit-smoke",
        },
    )
    if not resolved.get("ok"):
        raise RuntimeError(f"approval.resolve failed: {resolved}")


def open_workspace_kernel(workspace: Path) -> None:
    sock = connect()
    token = load_token()
    current = send_rpc(sock, token, "workspace.getRoot", {})
    current_path = Path(str((current.get("result") or {}).get("path") or "")).resolve()
    if current_path == workspace.resolve():
        return
    opened = send_rpc(sock, token, "workspace.openFolder", {"path": str(workspace)})
    if not opened.get("ok"):
        raise RuntimeError(f"workspace.openFolder failed: {opened}")
    _resolve_kernel_approval(sock, token, opened)
    root = send_rpc(sock, token, "workspace.getRoot", {})
    root_path = Path(str((root.get("result") or {}).get("path") or "")).resolve()
    if root_path != workspace.resolve():
        send_rpc(sock, token, "workspace.refreshAnchor", {})
        refreshed = send_rpc(sock, token, "workspace.getRoot", {})
        root_path = Path(str((refreshed.get("result") or {}).get("path") or root_path)).resolve()
    if root_path != workspace.resolve():
        raise RuntimeError(
            f"workspace root mismatch after openFolder: {root_path!r} != {workspace!r}"
        )


def checkpoint_status(snapshot: dict[str, Any], key: str) -> str | None:
    for cp in snapshot.get("checkpoints") or []:
        if cp.get("key") == key:
            return str(cp.get("status"))
    return None


def run_fixture(
    rec: Recorder,
    client: BridgeClient,
    fixture: dict[str, str],
    *,
    smoke_root: Path,
    timeout: float,
) -> str:
    workspace = smoke_root / fixture["dir"]
    prefix = f"{fixture['name']}"

    try:
        reset_fixture_probe(workspace)
        client.refresh_workspace_anchor()

        fail_rc = run_verify_command(workspace, fixture["verify"])
        rec.check(f"{prefix}.verify.fails_before_patch", fail_rc != 0, {"exitCode": fail_rc})

        submitted = client.submit_task(
            message=f"Change probe.py VALUE from 1 to 2 ({fixture['name']})",
            workspace=str(workspace),
            mode="smoke",
        )
        task = submitted.get("task") or {}
        task_id = str(task.get("taskId") or "")
        rec.check(f"{prefix}.task.submitted", bool(task_id), submitted)

        def _awaiting() -> dict[str, Any] | None:
            current = client.get_task(task_id).get("task") or {}
            if current.get("status") == "awaiting_approval":
                return current
            return None

        wait_until(_awaiting, timeout=timeout, label=f"{prefix} awaiting_approval")
        rec.check(f"{prefix}.approval.visible", True)

        cps = client.task_checkpoints(task_id).get("snapshot") or {}
        drift_status = checkpoint_status(cps, "drift")
        rec.check(
            f"{prefix}.checkpoint.drift",
            drift_status in {"passed", "skipped"},
            {"status": drift_status, "snapshot": cps},
        )
        rec.check(
            f"{prefix}.checkpoint.approval_active",
            checkpoint_status(cps, "approval") == "active",
            cps,
        )

        pending = client.list_approvals(status="pending")
        approvals = pending.get("approvals") or []
        approval_id = None
        for item in approvals:
            if isinstance(item, dict) and str(item.get("taskId") or "") == task_id:
                approval_id = str(item.get("approvalId") or "")
                break
        if not approval_id and approvals and isinstance(approvals[0], dict):
            approval_id = str(approvals[0].get("approvalId") or "")
        rec.check(f"{prefix}.approval.pending", bool(approval_id), pending)

        resolved = client.resolve_approval(str(approval_id))
        rec.check(f"{prefix}.approval.resolved", resolved.get("ok") is not False, resolved)

        def _verify_required() -> dict[str, Any] | None:
            current = client.get_task(task_id).get("task") or {}
            if current.get("status") == "verification_required":
                return current
            return None

        task_after = wait_until(_verify_required, timeout=timeout, label=f"{prefix} verification_required")
        rec.check(f"{prefix}.task.not_completed_before_verify", task_after.get("status") == "verification_required")

        cps2 = client.task_checkpoints(task_id).get("snapshot") or {}
        rec.check(f"{prefix}.checkpoint.mutation", checkpoint_status(cps2, "mutation") == "passed", cps2)
        rec.check(
            f"{prefix}.checkpoint.verification_active",
            checkpoint_status(cps2, "verification") == "active",
            cps2,
        )
        suggested = cps2.get("suggestedVerifyCommand")
        rec.check(
            f"{prefix}.verify.command_resolves",
            suggested == fixture["verify"],
            {"expected": fixture["verify"], "actual": suggested},
        )

        session = client.session()
        diffs = session.get("recentDiffs") or []
        has_probe_diff = any(str(d.get("path") or "").endswith("probe.py") for d in diffs if isinstance(d, dict))
        rec.check(f"{prefix}.diff.panel", has_probe_diff, diffs[:3])

        verify_result = client.run_verify(task_id)
        verify_payload = verify_result.get("verify") or {}
        rec.check(
            f"{prefix}.verify.passes",
            verify_payload.get("passed") is True,
            verify_payload,
        )

        def _completed_verified() -> dict[str, Any] | None:
            current = client.get_task(task_id).get("task") or {}
            if (
                current.get("status") == "completed"
                and current.get("verificationState") == "verified"
            ):
                return current
            return None

        final_task = wait_until(_completed_verified, timeout=timeout, label=f"{prefix} completed+verified")
        rec.check(f"{prefix}.task.completed_after_verify", True, final_task)

        cps3 = client.task_checkpoints(task_id).get("snapshot") or {}
        rec.check(f"{prefix}.checkpoint.can_complete", cps3.get("canComplete") is True, cps3)

        return task_id
    finally:
        reset_fixture_probe(workspace)


def restart_bridge(proc: subprocess.Popen[str] | None, port: int, session_dir: Path) -> subprocess.Popen[str]:
    if proc and proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    return start_bridge(port, session_dir)


def main() -> int:
    parser = argparse.ArgumentParser(description="Cockpit vertical-slice smoke validation.")
    parser.add_argument("--compact", action="store_true")
    parser.add_argument("--port", type=int, default=DEFAULT_BRIDGE_PORT)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    args = parser.parse_args()

    rec = Recorder(compact=args.compact)
    session_dir = Path(
        os.environ.get("DIETCODE_SESSION_DIR") or (REPO_ROOT / "build" / "cockpit-smoke-session")
    )
    session_dir.mkdir(parents=True, exist_ok=True)

    bridge_proc: subprocess.Popen[str] | None = None
    task_ids: list[str] = []

    try:
        ensure_kernel(rec)
        bridge_proc = ensure_bridge(rec, args.port, session_dir)
        client = BridgeClient(args.port)
        client.clear_session()

        rec.check("cockpit.api.up", True)

        smoke_root = Path(
            os.environ.get("COCKPIT_SMOKE_WORKSPACE")
            or (REPO_ROOT / "build" / "cockpit-smoke-ws")
        )
        prepare_smoke_workspace(smoke_root)
        open_workspace_kernel(smoke_root)
        client.refresh_workspace_anchor()
        rec.check("fixture.workspace.ready", smoke_root.is_dir(), str(smoke_root))

        for fixture in FIXTURES:
            task_ids.append(
                run_fixture(rec, client, fixture, smoke_root=smoke_root, timeout=args.timeout)
            )

        snapshot_before = client.session()
        rec.check(
            "session.persisted",
            len(snapshot_before.get("tasks") or []) >= len(FIXTURES),
            {"taskCount": len(snapshot_before.get("tasks") or [])},
        )

        bridge_proc = restart_bridge(bridge_proc, args.port, session_dir)
        wait_until(lambda: _bridge_health_ok(client), timeout=45, label="bridge reload")
        snapshot_after = client.session()
        restored = snapshot_after.get("tasks") or []
        for task_id in task_ids:
            match = next((t for t in restored if t.get("taskId") == task_id), None)
            ok = (
                isinstance(match, dict)
                and match.get("status") == "completed"
                and match.get("verificationState") == "verified"
            )
            rec.check(f"session.reload.{task_id}", ok, match)
    except Exception as exc:
        rec.check("vertical_slice.unhandled", False, str(exc))
    finally:
        if bridge_proc and bridge_proc.poll() is None and os.environ.get("COCKPIT_SMOKE_LEAVE_BRIDGE") != "1":
            bridge_proc.terminate()
            try:
                bridge_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                bridge_proc.kill()

    return rec.finish("cockpit_vertical_slice")


if __name__ == "__main__":
    raise SystemExit(main())
