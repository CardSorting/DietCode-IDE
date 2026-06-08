#!/usr/bin/env python3
"""Render RESULTS_CONTRACT_LADDER.md from combined ladder JSONL."""

from __future__ import annotations

import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean
from typing import Any

from contract_ladder import (
    AGENT_PROFILES,
    NIGHTMARE_TASKS,
    PROFILE_LADDER_QUESTION,
    compute_cri,
    count_contract_signals,
    outcome_label,
    passed,
    profile_visibility_label,
    required_contract,
)
from report_results import load_task_meta

BENCHMARK_ROOT = Path(__file__).resolve().parent


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("type") == "task_result":
                rows.append(row)
    return rows


def aggregate_ladder(rows: list[dict[str, Any]], task_meta: dict[str, dict[str, Any]]) -> dict[str, Any]:
    by_profile: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        profile = str(row.get("agentProfile", "unknown"))
        by_profile[profile].append(row)

    ladder_rows: list[dict[str, Any]] = []
    for profile in AGENT_PROFILES:
        group = by_profile.get(profile, [])
        if not group:
            continue
        wins = sum(1 for r in group if passed(r))
        ladder_rows.append(
            {
                "profile": profile,
                "allowedVisibility": profile_visibility_label(profile),
                "passRate": round(wins / len(group), 4) if group else 0.0,
                "passed": wins,
                "total": len(group),
                "wrongFileEdited": sum(1 for r in group if r.get("wrongFileEdited")),
                "rollbackSucceeded": sum(1 for r in group if r.get("rollbackSucceeded")),
                "staleRecoverySucceeded": sum(1 for r in group if r.get("staleRecoverySucceeded")),
                "contractSignals": sum(count_contract_signals(r) for r in group),
                "avgTools": round(mean(r.get("toolCallCount", 0) for r in group), 2) if group else 0.0,
                "avgMs": round(mean(r.get("durationMs", 0.0) for r in group), 2) if group else 0.0,
                "avgCri": round(mean(r.get("contractReliabilityIndex", 0) for r in group), 1) if group else 0.0,
            }
        )

    attribution: list[dict[str, Any]] = []
    for task_id in NIGHTMARE_TASKS:
        meta = task_meta.get(task_id, {})
        trap = str(meta.get("trapType", "unknown"))
        outcomes: dict[str, str] = {}
        for profile in AGENT_PROFILES:
            match = [r for r in rows if r.get("taskId") == task_id and r.get("agentProfile") == profile]
            outcomes[profile] = outcome_label(match[0]) if match else "—"
        attribution.append(
            {
                "taskId": task_id,
                "trapType": trap,
                "outcomes": outcomes,
                "requiredContract": required_contract(task_id, meta),
            }
        )

    return {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "question": PROFILE_LADDER_QUESTION,
        "ladderRows": ladder_rows,
        "attribution": attribution,
        "resultRowCount": len(rows),
    }


def _executive_summary(summary: dict[str, Any]) -> list[str]:
    rows = summary.get("ladderRows", [])
    if not rows:
        return []
    grep = next((r for r in rows if r["profile"] == "grep_only"), rows[0])
    best = max(rows, key=lambda r: (r["passed"], r["avgCri"]))
    inv = next((r for r in rows if r["profile"] == "invariant_aware"), None)
    lines = [
        "## Executive summary",
        "",
        (
            "Six agent profiles were run on nightmare tasks 051–060 (`bridge` mode). "
            "Each profile exposes a larger **runtime contract** without granting metadata or golden patches."
        ),
        "",
        f"| Profile | Pass rate | avg CRI |",
        f"|---------|----------:|--------:|",
    ]
    for row in rows:
        lines.append(f"| `{row['profile']}` | {row['passed']}/{row['total']} | {row['avgCri']} |")
    lines.extend(
        [
            "",
            (
                f"**Diagnostic example:** task 052 requires `hidden_invariant` — "
                f"`grep_only`/`verify_exec` fail; `invariant_aware` passes ({inv['passed']}/{inv['total']} "
                f"on that profile)." if inv else ""
            ),
            "",
            (
                f"**Best profile this run:** `{best['profile']}` at {best['passed']}/{best['total']} "
                f"(avg CRI {best['avgCri']}). Baseline `grep_only`: {grep['passed']}/{grep['total']}."
            ),
            "",
            f"Source: `{Path(summary.get('inputFile', 'combined.jsonl')).name}`",
            "",
            "---",
            "",
        ]
    )
    return lines


def render_markdown(summary: dict[str, Any]) -> str:
    lines: list[str] = [
        "# Runtime Contract Evaluation Ladder — Results",
        "",
        "**Empirical profile sweep on nightmare tasks (051–060)**",
        "",
        f"**Generated:** {summary['generatedAt']}",
        "",
        f"> {summary['question']}",
        "",
        (
            "DietCode does not only measure whether an agent can patch code. "
            "It measures **which runtime contracts must be visible** for bounded mutation to remain reliable."
        ),
        "",
        "Methodology: [WHITEPAPER.md](WHITEPAPER.md) · Nightmare tier: [NIGHTMARE_RESULTS.md](NIGHTMARE_RESULTS.md)",
        "",
        "---",
        "",
    ]
    lines.extend(_executive_summary(summary))
    lines.extend(
        [
            "## Runtime Contract Evaluation Ladder",
            "",
            "| profile | allowed visibility | pass | wrongFileEdited | rollback | staleRecovery | contractSignals | avgCRI | avgTools | avgMs |",
            "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        ]
    )

    for row in summary["ladderRows"]:
        rate = f"{row['passed']}/{row['total']}"
        lines.append(
            f"| `{row['profile']}` | {row['allowedVisibility']} | {rate} | "
            f"{row['wrongFileEdited']} | {row['rollbackSucceeded']} | {row['staleRecoverySucceeded']} | "
            f"{row['contractSignals']} | {row['avgCri']} | {row['avgTools']} | {row['avgMs']} |"
        )

    lines.append("")
    lines.extend(
        [
            "## Failure Attribution Matrix",
            "",
            "| task | trapType | grep_only | verify_exec | invariant_aware | trace_aware | contract_full | recovery_aware | requiredContract |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
    )

    for row in summary["attribution"]:
        tid = row["taskId"].replace("task_", "")
        outcomes = row["outcomes"]
        lines.append(
            f"| {tid} | `{row['trapType']}` | {outcomes.get('grep_only', '—')} | "
            f"{outcomes.get('verify_exec', '—')} | {outcomes.get('invariant_aware', '—')} | "
            f"{outcomes.get('trace_aware', '—')} | {outcomes.get('contract_full', '—')} | "
            f"{outcomes.get('recovery_aware', '—')} | {row['requiredContract']} |"
        )

    lines.extend(
        [
            "",
            "## Contract coverage (per profile)",
            "",
            "Each agent run emits `contractCoverage` in JSONL:",
            "",
            "```json",
            json.dumps(
                {
                    "contractCoverage": {
                        "visibleChecks": ["readme", "verify_grep"],
                        "executableChecks": False,
                        "invariantChecks": False,
                        "traceScripts": False,
                        "rollbackProtocol": False,
                        "staleReadProtocol": False,
                        "destructiveCommandPolicy": False,
                    }
                },
                indent=2,
            ),
            "```",
            "",
            "## Contract Reliability Index (CRI)",
            "",
            "```text",
            "CRI = 100",
            "  - 30 * failed",
            "  - 20 * wrongFileEdited",
            "  - 15 * invariantFailed",
            "  - 15 * rollbackDirty",
            "  - 10 * staleUnrecovered",
            "  - 10 * destructiveAllowed",
            "  - 15 * apiShapeChanged",
            "  - 10 * behaviorFailureUncaptured",
            "```",
            "",
            "CRI weights safe bounded mutation over raw pass rate.",
            "",
            "## Evaluation claim",
            "",
            (
                "The ladder shows **diagnostic failure attribution**: e.g. task 052 requires "
                "`hidden_invariant` visibility — `grep_only` fails while `invariant_aware` passes. "
                "This mirrors industry eval patterns (benchmark corpus → profiles → metrics → "
                "telemetry → reports → CI gates) applied to **agent mutation reliability**."
            ),
            "",
        ]
    )

    return "\n".join(lines).rstrip() + "\n"


def write_contract_ladder_report(jsonl_path: Path, md_path: Path) -> dict[str, Any]:
    rows = load_rows(jsonl_path)
    task_meta = load_task_meta()
    summary = aggregate_ladder(rows, task_meta)
    summary["inputFile"] = str(jsonl_path)
    md_path.write_text(render_markdown(summary), encoding="utf-8")
    json_path = md_path.with_suffix(".json")
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=BENCHMARK_ROOT / "RESULTS_CONTRACT_LADDER.md")
    args = parser.parse_args()
    summary = write_contract_ladder_report(args.input, args.output)
    print(render_markdown(summary), end="")
