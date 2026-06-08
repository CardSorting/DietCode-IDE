#!/usr/bin/env python3
"""Runtime contract definitions, failure classification, and escalation policy.

Phase 3: the runtime acts as an adaptive contract broker — failures reveal
missing contracts; the orchestrator escalates visibility and retries.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"

ORCHESTRATOR_CLAIM = (
    "Reliable bounded autonomy emerges through adaptive runtime contract escalation, "
    "not static maximal visibility."
)

PHASE_31_CLAIM = (
    "Runtime contract visibility tells the agent what truth exists; "
    "execution protocols determine whether mutation remains safe under changing state."
)

# Canonical contract registry — what each layer exposes to the agent.
CONTRACTS: dict[str, dict[str, Any]] = {
    "readme": {
        "description": "Task instruction text (README.md, fixture layout stripped).",
        "capabilities": [],
        "layer": 0,
    },
    "verify_grep": {
        "description": "Parsed positive/negative grep clauses from verify.sh.",
        "capabilities": ["verify_grep"],
        "layer": 0,
    },
    "verify_exec": {
        "description": "Execute verify.sh and shell/python checks; inspect failure output.",
        "capabilities": ["verify_exec"],
        "layer": 1,
    },
    "hidden_invariant": {
        "description": "Second-phase verify_invariant.sh and derived patch goals.",
        "capabilities": ["invariant"],
        "layer": 2,
    },
    "execution_trace": {
        "description": "Declared trace scripts (e.g. scripts/trace_config.py).",
        "capabilities": ["trace"],
        "layer": 2,
    },
    "behavior_check": {
        "description": "Infer targets from check.py / test_api.py execution scripts.",
        "capabilities": ["behavior_check"],
        "layer": 2,
    },
    "authoritative_read": {
        "description": "Re-read live file content before patch; search is advisory.",
        "capabilities": ["authoritative_read"],
        "layer": 2,
    },
    "destructive_policy": {
        "description": "Block or flag destructive shell commands from README temptation.",
        "capabilities": ["destructive_policy"],
        "layer": 3,
    },
    "stale_read_protocol": {
        "description": "Stale-content detection and revalidate/re-apply on patch.",
        "capabilities": ["stale_protocol"],
        "layer": 3,
    },
    "rollback_protocol": {
        "description": "Snapshot workspace and rollback between orchestration retries.",
        "capabilities": ["recovery"],
        "layer": 3,
    },
}

INITIAL_CONTRACTS: tuple[str, ...] = ("readme", "verify_grep")

# Failure class → visibility contract and/or execution protocol to grant.
# Orchestrator-side only; agent never sees trap metadata.
ESCALATION_ACTION = dict[str, str | None]

ESCALATION_GRAPH: dict[str, ESCALATION_ACTION] = {
    "hidden_invariant_missing": {"grantContract": "hidden_invariant", "grantProtocol": None},
    "runtime_behavior_mismatch": {"grantContract": "verify_exec", "grantProtocol": None},
    "execution_trace_required": {"grantContract": "execution_trace", "grantProtocol": None},
    "stale_read_detected": {
        "grantContract": "authoritative_read",
        "grantProtocol": "stale_safe_patch",
    },
    "stale_read_protocol_required": {
        "grantContract": "stale_read_protocol",
        "grantProtocol": "stale_safe_patch",
    },
    "destructive_attempt": {"grantContract": "destructive_policy", "grantProtocol": None},
    "concurrent_mutation_detected": {
        "grantContract": "stale_read_protocol",
        "grantProtocol": "lock_read_validate_apply",
    },
    "concurrent_mutation": {  # legacy alias
        "grantContract": "stale_read_protocol",
        "grantProtocol": "lock_read_validate_apply",
    },
    "partial_mutation_detected": {
        "grantContract": "rollback_protocol",
        "grantProtocol": "transactional_batch_patch",
    },
    "sidecar_residue_detected": {
        "grantContract": "rollback_protocol",
        "grantProtocol": "rollback_cleanup",
    },
    "api_shape_mismatch": {"grantContract": "behavior_check", "grantProtocol": None},
    "unclassified_failure": {"grantContract": "verify_exec", "grantProtocol": "stale_safe_patch"},
}

# Reference MCS (diagnostic baseline for reports — derived from trap analysis, not agent input).
MCS_REFERENCE: dict[str, list[str]] = {
    "task_051": ["readme", "verify_grep", "execution_trace"],
    "task_052": ["readme", "verify_grep", "hidden_invariant"],
    "task_053": ["readme", "verify_grep"],
    "task_054": ["readme", "verify_grep", "verify_exec"],
    "task_055": ["readme", "verify_grep", "verify_exec", "behavior_check"],
    "task_056": ["readme", "verify_grep", "stale_read_protocol"],
    "task_057": ["readme", "verify_grep", "stale_read_protocol", "authoritative_read"],
    "task_058": ["readme", "verify_grep", "authoritative_read"],
    "task_059": ["readme", "verify_grep", "verify_exec", "behavior_check"],
    "task_060": ["readme", "verify_grep", "destructive_policy"],
}


@dataclass
class VerifyOutcome:
    verify_rc: int = 1
    verify_stdout: str = ""
    verify_stderr: str = ""
    invariant_rc: int | None = None
    invariant_stdout: str = ""
    invariant_stderr: str = ""
    execution_error: str | None = None
    concurrent_mutation_observed: bool = False


@dataclass
class ContractBroker:
    """Adaptive broker — grants visibility contracts and execution protocols on failure."""

    visible: set[str] = field(default_factory=lambda: set(INITIAL_CONTRACTS))
    active_protocol: str = "single_shot_patch"
    escalation_path: list[dict[str, Any]] = field(default_factory=list)
    protocol_path: list[str] = field(default_factory=lambda: ["single_shot_patch"])
    failure_classes: list[str] = field(default_factory=list)

    def visible_contracts(self) -> list[str]:
        return sorted(self.visible)

    def grant(self, contract: str, *, failure_class: str, step: int) -> bool:
        if contract in self.visible:
            return False
        if contract not in CONTRACTS:
            return False
        self.visible.add(contract)
        if contract == "verify_exec":
            self.visible.add("behavior_check")
        return True

    def grant_protocol(self, protocol: str, *, failure_class: str, step: int) -> bool:
        from execution_protocols import EXECUTION_PROTOCOLS

        if protocol not in EXECUTION_PROTOCOLS:
            return False
        if protocol == self.active_protocol:
            return False
        self.active_protocol = protocol
        if protocol not in self.protocol_path:
            self.protocol_path.append(protocol)
        return True

    def _record_escalation(
        self,
        *,
        failure_class: str,
        step: int,
        granted_contract: str | None,
        granted_protocol: str | None,
    ) -> None:
        self.escalation_path.append(
            {
                "step": step,
                "failureClass": failure_class,
                "grantedContract": granted_contract,
                "grantedProtocol": granted_protocol,
                "visibleAfter": self.visible_contracts(),
                "protocolAfter": self.active_protocol,
            }
        )

    def escalate(self, failure_class: str | None, *, step: int) -> str | None:
        if not failure_class:
            return None
        self.failure_classes.append(failure_class)
        action = ESCALATION_GRAPH.get(failure_class)
        if not action:
            return None

        granted_contract: str | None = None
        granted_protocol: str | None = None
        contract_spec = action.get("grantContract")
        protocol_spec = action.get("grantProtocol")

        if contract_spec and self.grant(str(contract_spec), failure_class=failure_class, step=step):
            granted_contract = str(contract_spec)
        elif contract_spec and contract_spec in self.visible:
            granted_contract = None  # already visible

        if protocol_spec and self.grant_protocol(str(protocol_spec), failure_class=failure_class, step=step):
            granted_protocol = str(protocol_spec)

        if granted_contract or granted_protocol:
            self._record_escalation(
                failure_class=failure_class,
                step=step,
                granted_contract=granted_contract,
                granted_protocol=granted_protocol,
            )
            return granted_contract or granted_protocol

        # Contract/protocol already granted — try chained contract escalation
        chained = _CHAINED_ESCALATION.get(failure_class, [])
        for next_contract in chained:
            if next_contract not in self.visible and self.grant(next_contract, failure_class=failure_class, step=step):
                self._record_escalation(
                    failure_class=failure_class,
                    step=step,
                    granted_contract=next_contract,
                    granted_protocol=None,
                )
                return next_contract

        # Chained protocol fallback for concurrent stale races
        chained_protocols = _CHAINED_PROTOCOL_ESCALATION.get(failure_class, [])
        for next_protocol in chained_protocols:
            if self.grant_protocol(next_protocol, failure_class=failure_class, step=step):
                self._record_escalation(
                    failure_class=failure_class,
                    step=step,
                    granted_contract=None,
                    granted_protocol=next_protocol,
                )
                return next_protocol

        return None

    def to_coverage(self) -> dict[str, Any]:
        return {
            "orchestrated": True,
            "visibleContracts": self.visible_contracts(),
            "activeProtocol": self.active_protocol,
            "executionProtocolPath": list(self.protocol_path),
            "executableChecks": "verify_exec" in self.visible,
            "invariantChecks": "hidden_invariant" in self.visible,
            "traceScripts": "execution_trace" in self.visible,
            "rollbackProtocol": "rollback_protocol" in self.visible,
            "staleReadProtocol": "stale_read_protocol" in self.visible,
            "destructiveCommandPolicy": "destructive_policy" in self.visible,
            "authoritativeRead": "authoritative_read" in self.visible,
        }


# When primary escalation target already granted, try these next.
_CHAINED_ESCALATION: dict[str, list[str]] = {
    "hidden_invariant_missing": [],
    "runtime_behavior_mismatch": ["behavior_check"],
    "stale_read_detected": ["stale_read_protocol"],
    "stale_read_protocol_required": ["authoritative_read"],
    "concurrent_mutation_detected": ["authoritative_read"],
    "concurrent_mutation": ["authoritative_read"],
    "unclassified_failure": ["hidden_invariant", "execution_trace"],
}

_CHAINED_PROTOCOL_ESCALATION: dict[str, list[str]] = {
    "stale_read_detected": ["stale_safe_patch"],
    "concurrent_mutation_detected": ["lock_read_validate_apply"],
    "concurrent_mutation": ["lock_read_validate_apply"],
    "partial_mutation_detected": ["transactional_batch_patch"],
    "sidecar_residue_detected": ["rollback_cleanup"],
}


def contracts_allow(visible: set[str], capability: str) -> bool:
    for name in visible:
        spec = CONTRACTS.get(name, {})
        if capability in spec.get("capabilities", []):
            return True
    if capability == "verify_exec" and "verify_exec" in visible:
        return True
    if capability == "invariant" and "hidden_invariant" in visible:
        return True
    if capability == "trace" and "execution_trace" in visible:
        return True
    if capability == "behavior_check" and ("behavior_check" in visible or "verify_exec" in visible):
        return True
    if capability == "authoritative_read" and "authoritative_read" in visible:
        return True
    if capability == "destructive_policy" and "destructive_policy" in visible:
        return True
    if capability == "stale_protocol" and "stale_read_protocol" in visible:
        return True
    if capability == "recovery" and "rollback_protocol" in visible:
        return True
    return False


def measure_verify_outcome(workspace: Path, task_id: str) -> VerifyOutcome:
    """Orchestrator-side verification — classifies failures without agent contract access."""
    env = {**__import__("os").environ, "WORKSPACE_ROOT": str(workspace)}
    verify_script = TASKS_DIR / task_id / "verify.sh"
    outcome = VerifyOutcome()
    if verify_script.is_file():
        completed = subprocess.run(
            ["bash", str(verify_script)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        outcome.verify_rc = completed.returncode
        outcome.verify_stdout = completed.stdout or ""
        outcome.verify_stderr = completed.stderr or ""

    inv_script = TASKS_DIR / task_id / "verify_invariant.sh"
    if inv_script.is_file():
        inv = subprocess.run(
            ["bash", str(inv_script)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        outcome.invariant_rc = inv.returncode
        outcome.invariant_stdout = inv.stdout or ""
        outcome.invariant_stderr = inv.stderr or ""
    return outcome


def _verify_script_signals(task_id: str) -> dict[str, bool]:
    verify_path = TASKS_DIR / task_id / "verify.sh"
    text = verify_path.read_text(encoding="utf-8") if verify_path.is_file() else ""
    return {
        "has_invariant_script": (TASKS_DIR / task_id / "verify_invariant.sh").is_file(),
        "verify_has_python": "python3" in text,
        "verify_has_trace": "trace_config" in text or bool(__import__("re").search(r"python3\s+\S+/.*\.py", text)),
    }


def classify_failure(task_id: str, outcome: VerifyOutcome) -> str | None:
    """Classify verify/execution failure into an escalation key (no trap metadata)."""
    if outcome.concurrent_mutation_observed:
        return "concurrent_mutation_detected"

    signals = _verify_script_signals(task_id)
    combined = " ".join(
        filter(
            None,
            [
                outcome.verify_stdout,
                outcome.verify_stderr,
                outcome.invariant_stdout,
                outcome.invariant_stderr,
                outcome.execution_error or "",
            ],
        )
    )

    if outcome.execution_error:
        err = outcome.execution_error.lower()
        if "destructive" in err:
            return "destructive_attempt"
        if "stale_content" in err or "stale" in err:
            return "stale_read_detected"

    # Primary verify passes but invariant fails → hidden invariant gap
    if outcome.verify_rc == 0 and signals["has_invariant_script"]:
        if outcome.invariant_rc not in (None, 0):
            return "hidden_invariant_missing"

    if outcome.verify_rc != 0:
        lower = combined.lower()
        if "assertionerror" in lower or "assert" in lower:
            return "runtime_behavior_mismatch"
        if signals["verify_has_python"] or "python3" in lower:
            return "runtime_behavior_mismatch"
        if signals["verify_has_trace"]:
            return "execution_trace_required"
        if "stale" in lower:
            return "stale_read_detected"
        if "import" in lower and "error" in lower:
            return "runtime_behavior_mismatch"
        if "wrong file" in lower or "decoy" in lower:
            return "authoritative_read"

    if outcome.verify_rc != 0 and signals["verify_has_trace"]:
        return "execution_trace_required"

    if outcome.execution_error:
        err_lower = outcome.execution_error.lower()
        if "concurrent" in err_lower or "single_shot_patch does not reconcile" in err_lower:
            return "concurrent_mutation_detected"
        if "sidecar" in err_lower:
            return "sidecar_residue_detected"
        if "partial" in err_lower and "batch" in err_lower:
            return "partial_mutation_detected"

    lower_all = combined.lower()
    if outcome.verify_rc != 0 and "version = 3" in lower_all:
        return "concurrent_mutation_detected"

    if outcome.verify_rc != 0:
        return "unclassified_failure"

    if outcome.invariant_rc not in (None, 0):
        return "hidden_invariant_missing"

    return None


def compute_mcs_match(observed: list[str], reference: list[str]) -> dict[str, Any]:
    obs = set(observed)
    ref = set(reference)
    return {
        "observed": sorted(obs),
        "reference": sorted(ref),
        "matched": obs == ref,
        "extra": sorted(obs - ref),
        "missing": sorted(ref - obs),
    }
