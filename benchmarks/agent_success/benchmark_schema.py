#!/usr/bin/env python3
"""Frozen schema contracts for agent benchmark tooling (Phase 4.1)."""

from __future__ import annotations

TRACE_SCHEMA_VERSION = "1.0"
BENCHMARK_VERSION = "1.2"
RUNTIME_VERSION = "1.6.5"

# JSONL task_result — stable core fields (Phase 4.1).
JSONL_CORE_FIELDS: frozenset[str] = frozenset(
    {
        "type",
        "taskId",
        "mode",
        "executor",
        "taskSuccess",
        "verifyPassed",
        "finalVerifyPassed",
        "wrongFileEdited",
        "staleRecoverySucceeded",
        "rollbackSucceeded",
        "retries",
        "toolCallCount",
        "durationMs",
        "failureCode",
        "recoveryHintsUsed",
        "commandsUsed",
        "patchValidateFailures",
        "destructiveCommandBlocked",
        "sidecarRollbackClean",
        "concurrentMutationDetected",
        "searchReadMismatchDetected",
        "apiShapePreserved",
        "secondInvariantPassed",
        "contractCoverage",
        "contractReliabilityIndex",
        "minimumContractSet",
        "contractEscalationPath",
        "failureClassesObserved",
        "orchestrationSteps",
        "escalationSucceeded",
        "executionProtocolPath",
        "protocolEscalationSucceeded",
        "semanticRepairAttempted",
        "behaviorFailureCaptured",
        "behaviorFailureUncaptured",
        "apiShapeBefore",
        "apiShapeAfter",
        "apiShapeChanged",
        "semanticRepairSucceeded",
        "semanticRollbackTriggered",
        "mcsReferenceMatch",
        "timestamp",
        "attemptCount",
        "passedOnRetry",
        "firstFailureClass",
        "finalFailureClass",
        "agentInputManifest",
        "mutationTraceFile",
        "agentProfile",
    }
)

# mutation_trace.json — stable provenance + narrative fields.
MUTATION_TRACE_FIELDS: frozenset[str] = frozenset(
    {
        "traceSchemaVersion",
        "taskId",
        "runId",
        "parentRunId",
        "mode",
        "timestamp",
        "runtimeVersion",
        "benchmarkVersion",
        "gitCommit",
        "workspaceHashBefore",
        "workspaceHashAfter",
        "traceHash",
        "initialContracts",
        "initialProtocol",
        "steps",
        "finalState",
        "telemetry",
        "attemptCount",
        "passedOnRetry",
        "firstFailureClass",
        "finalFailureClass",
        "events",
        "agentInputManifest",
    }
)

MUTATION_TRACE_STEP_FIELDS: frozenset[str] = frozenset(
    {"attempt", "contracts", "protocol", "result", "failureClass"}
)

MUTATION_TRACE_FINAL_STATE_FIELDS: frozenset[str] = frozenset(
    {"passed", "wrongFileEdited", "apiShapeChanged", "rollbackDirty", "destructiveAllowed"}
)

OBSERVABILITY_EVENT_FIELDS: frozenset[str] = frozenset(
    {"eventType", "traceId", "spanId", "taskId", "attempt", "contract", "protocol", "failureClass"}
)

RELEASE_GATE_NAMES: tuple[str, ...] = (
    "reference_nightmare_10_10",
    "orchestrated_nightmare_10_10",
    "wrong_file_edited_zero",
    "api_shape_changed_zero",
    "rollback_dirty_zero",
    "destructive_allowed_zero",
    "task_052_hidden_invariant_escalation",
    "task_057_lock_read_validate_apply_escalation",
    "task_059_semantic_repair_loop_escalation",
    "mutation_traces_present",
)

RESULTS_ORCHESTRATOR_REQUIRED_SECTIONS: tuple[str, ...] = (
    "What we measured",
    "three-axis control model",
    "Research progression",
    "Failure attribution matrix",
    "Representative case studies",
    "Minimum Contract Set",
    "Retry / Escalation Honesty",
    "Semantic repair matrix",
    "Telemetry emitted per run",
    "What this does not claim",
    "Example escalation traces",
)

# Imported at test time from contracts / execution_protocols to stay single-source.
CONTRACT_NAMES: tuple[str, ...] = (
    "readme",
    "verify_grep",
    "verify_exec",
    "hidden_invariant",
    "execution_trace",
    "behavior_check",
    "authoritative_read",
    "destructive_policy",
    "stale_read_protocol",
    "rollback_protocol",
    "api_shape_contract",
)

PROTOCOL_NAMES: tuple[str, ...] = (
    "single_shot_patch",
    "stale_safe_patch",
    "lock_read_validate_apply",
    "transactional_batch_patch",
    "rollback_cleanup",
    "semantic_repair_loop",
)

FAILURE_CLASS_VALUES: tuple[str, ...] = (
    "hidden_invariant_missing",
    "runtime_behavior_mismatch",
    "execution_trace_required",
    "stale_read_detected",
    "stale_read_protocol_required",
    "destructive_attempt",
    "concurrent_mutation_detected",
    "concurrent_mutation",
    "partial_mutation_detected",
    "sidecar_residue_detected",
    "api_shape_mismatch",
    "behavior_check_failed",
    "semantic_preservation_failed",
    "unclassified_failure",
    "authoritative_read",
)

OBSERVABILITY_EVENT_TYPES: tuple[str, ...] = (
    "orchestration.started",
    "orchestration.attempt",
    "contract.escalated",
    "protocol.escalated",
    "orchestration.passed",
    "orchestration.failed",
)

AGENT_INPUT_MANIFEST_FIELDS: frozenset[str] = frozenset(
    {
        "readme",
        "verifySh",
        "metadataJson",
        "expectedPatch",
        "priorTrace",
        "trapType",
        "mcsReference",
    }
)
