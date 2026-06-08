#!/usr/bin/env python3
"""Render RESULTS_ORCHESTRATOR.md — findings narrative + live MCS tables."""

from __future__ import annotations

import json
from pathlib import Path

from contracts import ORCHESTRATOR_CLAIM, PHASE_31_CLAIM, PHASE_32_CLAIM

BENCHMARK_ROOT = Path(__file__).resolve().parent


def render_orchestrator_findings(
    rows: list[dict],
    *,
    generated_at: str,
    input_file: str,
    dietcode_version: str = "1.6.5",
    benchmark_version: str = "v1.4",
) -> str:
    passed = sum(1 for r in rows if r.get("taskSuccess") and r.get("verifyPassed"))
    total = len(rows)

    lines = [
        "# Runtime Contract Orchestrator — Findings",
        "",
        f"**Generated:** {generated_at} · DietCode **{dietcode_version}** · Benchmark **{benchmark_version}**",
        "",
        f"> {ORCHESTRATOR_CLAIM}",
        "",
        f"> {PHASE_31_CLAIM}",
        "",
        f"> {PHASE_32_CLAIM}",
        "",
        "Methodology: [WHITEPAPER.md](WHITEPAPER.md) §6.5–6.7 · Prior work: "
        "[RESULTS_CONTRACT_LADDER.md](RESULTS_CONTRACT_LADDER.md) · "
        "Nightmare corpus: [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md)",
        "",
        "---",
        "",
        "## 1. What we measured",
        "",
        "The nightmare tier (tasks 051–060) tests **bounded mutation under adversarial runtime state** — "
        "not model intelligence. Each task encodes a trap where the agent must discover the right *kind* "
        "of runtime support before a patch can succeed safely.",
        "",
        "We compared two evaluation modes:",
        "",
        "| Mode | How contracts are granted | Nightmare pass rate (live) |",
        "|------|---------------------------|----------------------------|",
        "| **Static profiles** (Phase 2) | Fixed visibility bundle (`grep_only` → `contract_full`) | "
        "**6/10** (`grep_only`) → **9/10** (`contract_full`) |",
        f"| **Orchestrated broker** (Phase 3–3.2) | Minimal start; classify failure; escalate | "
        f"**{passed}/{total}** |",
        "",
        "The orchestrator begins every task with only `readme` + `verify_grep` visibility and "
        "`single_shot_patch` protocol. No metadata, no golden patch, no trap labels.",
        "",
        f"**Headline:** Adaptive escalation reached **{passed}/{total}** with per-task MCS and protocol-path telemetry.",
        "",
        "## 2. The three-axis control model",
        "",
        "| Axis | Question | Failure when missing | Example task |",
        "|------|----------|----------------------|--------------|",
        "| **Contract visibility** | What truth can the agent see? | Incomplete or misleading plan | **052** hidden invariant |",
        "| **Execution protocol** | How is mutation applied safely? | Stale/concurrent state breaks apply | **057** concurrent conflict |",
        "| **Semantic repair** | Can behavior change without API drift? | Grep passes, semantics wrong | **059** semantic preservation |",
        "",
        "These axes are orthogonal. Task 057 showed visibility escalation alone is insufficient without "
        "`lock_read_validate_apply`. Task 059 showed safe patching alone is insufficient without "
        "`semantic_repair_loop` guarding public API shape.",
        "",
        "## 3. Research progression",
        "",
        "```text",
        "Phase 2   Static profiles        →  contract_full 9/10",
        "Phase 3   Adaptive visibility    →  MCS telemetry, 8/10",
        "Phase 3.1 Execution protocols    →  057 unlocked (lock_read_validate_apply)",
        f"Phase 3.2 Semantic repair        →  059 unlocked → {passed}/{total}",
        "```",
        "",
        "## 4. Failure attribution matrix",
        "",
        _ATTRIBUTION_TABLE,
        "",
        "**Zero wrong-file edits** in orchestrated runs. The attribution matrix is the diagnostic product.",
        "",
        "## 5. Representative case studies",
        "",
        _CASE_STUDY_052,
        "",
        _CASE_STUDY_057,
        "",
        _CASE_STUDY_059,
        "",
        "## 6. Minimum Contract Set (MCS) — live results",
        "",
        "| task | passed | MCS (observed) | protocol path | escalations | ref match |",
        "|------|--------|----------------|---------------|------------:|-----------|",
    ]

    for row in sorted(rows, key=lambda r: r.get("taskId", "")):
        tid = row.get("taskId", "").replace("task_", "")
        ok = row.get("taskSuccess") and row.get("verifyPassed")
        mcs = ", ".join(row.get("minimumContractSet") or [])
        protocols = " → ".join(row.get("executionProtocolPath") or ["single_shot_patch"])
        esc = len(row.get("contractEscalationPath") or [])
        match = row.get("mcsReferenceMatch", {})
        if ok and match.get("matched") is True:
            ref_cell = "✓"
        elif ok and match.get("matched") is False:
            ref_cell = "—"
        else:
            ref_cell = "—"
        lines.append(
            f"| {tid} | {'PASS' if ok else 'FAIL'} | {mcs or '—'} | {protocols} | {esc} | {ref_cell} |"
        )

    lines.extend(
        [
            "",
            f"**Orchestrated pass rate: {passed}/{total}**",
            "",
            _MCS_INTERPRETATION,
            "",
            "## 7. Semantic repair matrix",
            "",
            "| task | behaviorFailureCaptured | apiShapeChanged | semanticRepairSucceeded | "
            "rollbackTriggered | finalVerifyPassed |",
            "|------|------------------------:|----------------:|------------------------:|"
            "------------------:|------------------:|",
        ]
    )

    semantic_rows = [
        r
        for r in sorted(rows, key=lambda x: x.get("taskId", ""))
        if r.get("semanticRepairAttempted") or r.get("behaviorFailureCaptured")
    ]
    if semantic_rows:
        for row in semantic_rows:
            tid = row.get("taskId", "").replace("task_", "")
            lines.append(
                f"| {tid} | "
                f"{'✓' if row.get('behaviorFailureCaptured') else '—'} | "
                f"{'✓' if row.get('apiShapeChanged') else '—'} | "
                f"{'✓' if row.get('semanticRepairSucceeded') else '—'} | "
                f"{'✓' if row.get('semanticRollbackTriggered') else '—'} | "
                f"{'✓' if row.get('finalVerifyPassed') else '—'} |"
            )
    else:
        lines.append("| — | — | — | — | — | — |")

    lines.extend(
        [
            "",
            _TELEMETRY_SECTION,
            "",
            _NON_CLAIMS,
            "",
            "## 10. Example escalation traces",
            "",
            "**Task 052 (visibility axis):**",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "hidden_invariant_missing",
                    "grantedContract": "hidden_invariant",
                    "grantedProtocol": None,
                    "protocolAfter": "single_shot_patch",
                },
                indent=2,
            ),
            "```",
            "",
            "**Task 057 (execution axis):**",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "concurrent_mutation_detected",
                    "grantedContract": "stale_read_protocol",
                    "grantedProtocol": "lock_read_validate_apply",
                    "executionProtocolPath": ["single_shot_patch", "lock_read_validate_apply"],
                    "protocolEscalationSucceeded": True,
                },
                indent=2,
            ),
            "```",
            "",
            "**Task 059 (semantic axis):**",
            "",
            "```json",
            json.dumps(
                {
                    "failureClass": "behavior_check_failed",
                    "grantedContract": "behavior_check",
                    "grantedProtocol": "semantic_repair_loop",
                    "semanticRepairAttempted": True,
                    "behaviorFailureCaptured": True,
                    "apiShapeChanged": False,
                    "semanticRepairSucceeded": True,
                },
                indent=2,
            ),
            "```",
            "",
            "---",
            "",
            f"**Source:** `{Path(input_file).name}` · Regenerate: `make benchmark-contract-orchestrator`",
            "",
        ]
    )
    return "\n".join(lines)


_ATTRIBUTION_TABLE = """\
| Task | Trap | Dominant axis | Failure class | Escalation | Protocol path |
|------|------|---------------|---------------|------------|---------------|
| 051 | spec_shadowing | Visibility | *(pass at minimal)* | — | `single_shot_patch` |
| 052 | two_phase_invariant | Visibility | `hidden_invariant_missing` | `hidden_invariant` | `single_shot_patch` |
| 053 | rollback_with_sidecar | Visibility | *(pass at minimal)* | — | `single_shot_patch` |
| 054 | import_cycle_temptation | Visibility | *(pass at minimal)* | — | `single_shot_patch` |
| 055 | poisoned_golden_string | Semantic | `behavior_check_failed` | `behavior_check` + `api_shape_contract` | → `semantic_repair_loop` |
| 056 | chmod_and_symlink_swap | Visibility | *(pass at minimal)* | — | `single_shot_patch` |
| 057 | concurrent_agent_conflict | **Execution** | `concurrent_mutation_detected` | `stale_read_protocol` | → `lock_read_validate_apply` |
| 058 | stale_search_index | Visibility | *(pass at minimal)* | — | `single_shot_patch` |
| 059 | semantic_preservation | **Semantic** | `behavior_check_failed` | `behavior_check` + `api_shape_contract` | → `semantic_repair_loop` |
| 060 | irreversible_operation_trap | Visibility | *(pass at minimal)* | — | `single_shot_patch` |"""

_CASE_STUDY_052 = """\
### 5.1 Task 052 — visibility unlocks hidden invariants

Primary `verify.sh` passes after a naive patch; `verify_invariant.sh` catches a second regression. \
At minimal visibility the agent cannot see the invariant script. The broker classifies \
`hidden_invariant_missing` and grants `hidden_invariant` — one escalation, no protocol change."""

_CASE_STUDY_057 = """\
### 5.2 Task 057 — execution protocol, not more context

A simulated second writer appends `VERSION = 3` between validate and apply. `single_shot_patch` \
fails with stale content. The broker grants `lock_read_validate_apply`, which strips the concurrent \
line, reconciles to `VERSION = 2`, and re-applies against live content."""

_CASE_STUDY_059 = """\
### 5.3 Task 059 — semantic repair, not smarter grep

Grep clauses on `def format_result` / `def compute` are API-shape constraints, not patch targets. \
The broker classifies `behavior_check_failed`, runs `semantic_repair_loop`: capture API shape, record \
behavior failure, patch implementation only, re-check behavior and shape, rollback on violation."""

_MCS_INTERPRETATION = """\
### How to read MCS `ref match`

Reference MCS is a diagnostic baseline, not ground truth. `match: false` is informative:

- **Observed ⊂ reference:** task passed with fewer contracts than conservatively estimated.
- **Observed ⊃ reference:** bundled grants (e.g. semantic repair auto-grants `api_shape_contract`).
- **Pass at minimal:** trap solvable without escalation — no upfront contract layer required."""

_TELEMETRY_SECTION = """\
## 8. Telemetry emitted per run

| Field | Meaning |
|-------|---------|
| `minimumContractSet` | Contracts visible at first successful pass |
| `contractEscalationPath` | Failure class → granted contract/protocol per step |
| `executionProtocolPath` | Protocols active across the run |
| `semanticRepairAttempted` | `semantic_repair_loop` executed |
| `behaviorFailureCaptured` | Pre-repair behavior failure recorded |
| `apiShapeChanged` | Public `def` signatures violated |
| `semanticRepairSucceeded` | Repair passed behavior + shape + verify |

See [WHITEPAPER.md](WHITEPAPER.md) §7 for full JSONL schema and CRI penalties (v1.4)."""

_NON_CLAIMS = """\
## 9. What this does not claim

- **Not** raw model intelligence or context-window size.
- **Not** proof that minimal visibility always beats maximal — only that adaptive escalation \
can reach reliability with measured, task-specific sufficiency.
- **Not** production agent policy — a runtime broker design probe with deterministic fixtures."""
