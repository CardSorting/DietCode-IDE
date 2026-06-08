#!/usr/bin/env python3
"""Aggregate agent-success benchmark JSONL results into comparison reports."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
RESULTS_DIR = BENCHMARK_ROOT / "results"
TASKS_DIR = BENCHMARK_ROOT / "tasks"


def load_task_meta() -> dict[str, dict[str, Any]]:
    meta_by_id: dict[str, dict[str, Any]] = {}
    if not TASKS_DIR.is_dir():
        return meta_by_id
    for task_dir in sorted(TASKS_DIR.iterdir()):
        meta_path = task_dir / "metadata.json"
        if not meta_path.is_file():
            continue
        with open(meta_path, encoding="utf-8") as handle:
            meta = json.load(handle)
        meta_by_id[str(meta.get("id", task_dir.name))] = meta
    return meta_by_id


def pick_jsonl_files(input_path: Path | None, *, latest_only: bool) -> list[Path]:
    if input_path is not None:
        if not input_path.is_file():
            raise FileNotFoundError(f"results file not found: {input_path}")
        return [input_path]

    files = sorted(RESULTS_DIR.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        raise FileNotFoundError(f"no JSONL files in {RESULTS_DIR}")
    return [files[0]] if latest_only else files


def load_task_results(paths: list[Path]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if row.get("type") == "task_result":
                    rows.append(row)
    return rows


def passed(row: dict[str, Any]) -> bool:
    return bool(row.get("taskSuccess")) and bool(row.get("verifyPassed"))


def _pass_rate(group: list[dict[str, Any]]) -> float:
    if not group:
        return 0.0
    return round(sum(1 for row in group if passed(row)) / len(group), 4)


def _mode_key(row: dict[str, Any]) -> str:
    mode = str(row.get("mode", "unknown"))
    executor = str(row.get("executor", "reference"))
    return f"{executor}:{mode}" if executor != "reference" else mode


def aggregate(rows: list[dict[str, Any]], task_meta: dict[str, dict[str, Any]], paths: list[Path]) -> dict[str, Any]:
    by_mode: dict[str, list[dict[str, Any]]] = defaultdict(list)
    by_category_mode: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(lambda: defaultdict(list))
    by_trap_mode: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(lambda: defaultdict(list))

    failure_codes: Counter[str] = Counter()
    recovery_hints: Counter[str] = Counter()
    wrong_file_by_mode: Counter[str] = Counter()
    stale_recovery_by_mode: Counter[str] = Counter()
    rollback_by_mode: Counter[str] = Counter()
    wrong_file_by_trap: Counter[str] = Counter()
    rollback_by_trap: Counter[str] = Counter()
    recovery_by_trap: Counter[str] = Counter()

    normal_rows: list[dict[str, Any]] = []
    adversarial_rows: list[dict[str, Any]] = []
    nightmare_rows: list[dict[str, Any]] = []
    by_nightmare_trap_mode: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(
        lambda: defaultdict(list)
    )
    nightmare_metric_keys = (
        "destructiveCommandBlocked",
        "sidecarRollbackClean",
        "concurrentMutationDetected",
        "searchReadMismatchDetected",
        "apiShapePreserved",
        "secondInvariantPassed",
        "finalVerifyPassed",
    )
    nightmare_metric_by_mode: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))

    for row in rows:
        mode_key = _mode_key(row)
        by_mode[mode_key].append(row)

        task_id = str(row.get("taskId", ""))
        meta = task_meta.get(task_id, {})
        category = str(meta.get("category", "unknown"))
        by_category_mode[category][mode_key].append(row)

        if meta.get("nightmare"):
            nightmare_rows.append(row)
            trap = str(meta.get("trapType", "unknown"))
            by_nightmare_trap_mode[trap][mode_key].append(row)
            by_trap_mode[trap][mode_key].append(row)
            for key in nightmare_metric_keys:
                if row.get(key):
                    nightmare_metric_by_mode[mode_key][key] += 1
        elif meta.get("adversarial"):
            adversarial_rows.append(row)
            trap = str(meta.get("trapType", "unknown"))
            by_trap_mode[trap][mode_key].append(row)
        else:
            normal_rows.append(row)

        code = row.get("failureCode")
        if code:
            failure_codes[str(code)] += 1

        for hint in row.get("recoveryHintsUsed") or []:
            recovery_hints[str(hint)] += 1

        trap = str(meta.get("trapType", "")) if meta.get("adversarial") else ""
        if row.get("wrongFileEdited"):
            wrong_file_by_mode[mode_key] += 1
            if trap:
                wrong_file_by_trap[trap] += 1
        if row.get("staleRecoverySucceeded"):
            stale_recovery_by_mode[mode_key] += 1
            if trap:
                recovery_by_trap[trap] += 1
        if row.get("rollbackSucceeded"):
            rollback_by_mode[mode_key] += 1
            if trap:
                rollback_by_trap[trap] += 1

    def mode_stats(group: list[dict[str, Any]]) -> dict[str, Any]:
        total = len(group)
        wins = sum(1 for row in group if passed(row))
        return {
            "total": total,
            "passed": wins,
            "passRate": round(wins / total, 4) if total else 0.0,
            "avgToolCalls": round(mean(row.get("toolCallCount", 0) for row in group), 2) if group else 0.0,
            "avgRetries": round(mean(row.get("retries", 0) for row in group), 2) if group else 0.0,
            "avgDurationMs": round(mean(row.get("durationMs", 0.0) for row in group), 2) if group else 0.0,
        }

    overall_by_mode = {mode: mode_stats(group) for mode, group in sorted(by_mode.items())}

    by_category: dict[str, dict[str, Any]] = {}
    for category, mode_groups in sorted(by_category_mode.items()):
        by_category[category] = {mode: mode_stats(group) for mode, group in sorted(mode_groups.items())}

    adversarial_pass_rate = {
        mode: _pass_rate([row for row in adversarial_rows if _mode_key(row) == mode])
        for mode in sorted(by_mode)
    }
    nightmare_pass_rate = {
        mode: _pass_rate([row for row in nightmare_rows if _mode_key(row) == mode])
        for mode in sorted(by_mode)
    }
    normal_pass_rate = {
        mode: _pass_rate([row for row in normal_rows if _mode_key(row) == mode])
        for mode in sorted(by_mode)
    }

    trap_type_pass_rate: dict[str, dict[str, float]] = {}
    for trap, mode_groups in sorted(by_trap_mode.items()):
        trap_type_pass_rate[trap] = {mode: _pass_rate(group) for mode, group in sorted(mode_groups.items())}

    by_trap_rows: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in adversarial_rows:
        task_id = str(row.get("taskId", ""))
        trap = str(task_meta.get(task_id, {}).get("trapType", "unknown"))
        by_trap_rows[trap].append(row)

    adversarial_trap_matrix: list[dict[str, Any]] = []
    for trap in sorted(by_trap_rows):
        group = by_trap_rows[trap]
        adversarial_trap_matrix.append(
            {
                "trapType": trap,
                "passRate": _pass_rate(group),
                "passed": sum(1 for row in group if passed(row)),
                "total": len(group),
                "wrongFileEdited": sum(1 for row in group if row.get("wrongFileEdited")),
                "rollbackSucceeded": sum(1 for row in group if row.get("rollbackSucceeded")),
                "recoverySucceeded": sum(1 for row in group if row.get("staleRecoverySucceeded")),
                "avgRetries": round(mean(row.get("retries", 0) for row in group), 2) if group else 0.0,
            }
        )

    nightmare_trap_matrix: list[dict[str, Any]] = []
    for trap in sorted(by_nightmare_trap_mode):
        group: list[dict[str, Any]] = []
        for mode_group in by_nightmare_trap_mode[trap].values():
            group.extend(mode_group)
        nightmare_trap_matrix.append(
            {
                "trapType": trap,
                "passRate": _pass_rate(group),
                "passed": sum(1 for row in group if passed(row)),
                "total": len(group),
                "wrongFileEdited": sum(1 for row in group if row.get("wrongFileEdited")),
                "rollbackSucceeded": sum(1 for row in group if row.get("rollbackSucceeded")),
                "recoverySucceeded": sum(1 for row in group if row.get("staleRecoverySucceeded")),
                "destructiveCommandBlocked": sum(1 for row in group if row.get("destructiveCommandBlocked")),
                "sidecarRollbackClean": sum(1 for row in group if row.get("sidecarRollbackClean")),
                "concurrentMutationDetected": sum(1 for row in group if row.get("concurrentMutationDetected")),
                "searchReadMismatchDetected": sum(1 for row in group if row.get("searchReadMismatchDetected")),
                "apiShapePreserved": sum(1 for row in group if row.get("apiShapePreserved")),
                "secondInvariantPassed": sum(1 for row in group if row.get("secondInvariantPassed")),
                "finalVerifyPassed": sum(1 for row in group if row.get("finalVerifyPassed")),
                "avgRetries": round(mean(row.get("retries", 0) for row in group), 2) if group else 0.0,
            }
        )

    reference_rows = [row for row in rows if str(row.get("executor", "reference")) == "reference"]
    agent_rows = [row for row in rows if str(row.get("executor")) == "agent"]
    has_reference = bool(reference_rows)
    has_agent = bool(agent_rows)
    evaluation_claim = {
        "referencePassed": sum(1 for row in reference_rows if passed(row)),
        "referenceTotal": len(reference_rows),
        "agentPassed": sum(1 for row in agent_rows if passed(row)),
        "agentTotal": len(agent_rows),
        "hasReferenceResults": has_reference,
        "hasAgentResults": has_agent,
        "frame": (
            "DietCode evaluates bounded agent code mutation as a transactional runtime "
            "problem, not an autocomplete problem."
        ),
    }
    executor_coverage = {
        "reference": "present" if has_reference else "absent",
        "agent": "present" if has_agent else "absent",
    }

    money_table: list[dict[str, Any]] = []
    for mode in sorted(by_mode):
        group = by_mode[mode]
        money_table.append(
            {
                "executorMode": mode,
                "normalPassRate": normal_pass_rate.get(mode, 0.0),
                "adversarialPassRate": adversarial_pass_rate.get(mode, 0.0),
                "nightmarePassRate": nightmare_pass_rate.get(mode, 0.0),
                "wrongFileEdited": sum(1 for row in group if row.get("wrongFileEdited")),
                "rollbackSucceeded": sum(1 for row in group if row.get("rollbackSucceeded")),
                "recoverySucceeded": sum(1 for row in group if row.get("staleRecoverySucceeded")),
            }
        )

    return {
        "inputFiles": [str(p) for p in paths],
        "resultRowCount": len(rows),
        "executorCoverage": executor_coverage,
        "taskResultCount": len(rows),
        "normalTaskCount": len(normal_rows),
        "adversarialTaskCount": len(adversarial_rows),
        "nightmareTaskCount": len(nightmare_rows),
        "overallByMode": overall_by_mode,
        "normalPassRate": normal_pass_rate,
        "adversarialPassRate": adversarial_pass_rate,
        "nightmarePassRate": nightmare_pass_rate,
        "trapTypePassRate": trap_type_pass_rate,
        "adversarialTrapMatrix": adversarial_trap_matrix,
        "nightmareTrapMatrix": nightmare_trap_matrix,
        "nightmareContractMetricsByMode": {
            mode: dict(counts) for mode, counts in sorted(nightmare_metric_by_mode.items())
        },
        "evaluationClaim": evaluation_claim,
        "moneyTable": money_table,
        "byCategory": by_category,
        "failureCodeCounts": dict(failure_codes.most_common()),
        "recoveryHintsUsedCounts": dict(recovery_hints.most_common()),
        "wrongFileEditedCounts": dict(wrong_file_by_mode),
        "wrongFileEditedByTrapType": dict(wrong_file_by_trap),
        "staleRecoverySucceededCounts": dict(stale_recovery_by_mode),
        "recoverySucceededByTrapType": dict(recovery_by_trap),
        "rollbackSucceededCounts": dict(rollback_by_mode),
        "rollbackSucceededByTrapType": dict(rollback_by_trap),
    }


def _fmt_rate(value: float) -> str:
    return f"{value * 100:.1f}%"


def _render_evaluation_claim(claim: dict[str, Any]) -> list[str]:
    ref_passed = claim["referencePassed"]
    ref_total = claim["referenceTotal"]
    lines = [
        "## Evaluation Claim",
        "",
        (
            f"The reference executor passed **{ref_passed}/{ref_total}** tasks, demonstrating "
            "that the tool surface and fixtures are mechanically solvable across both "
            "`raw_rpc` and `bridge` modes."
        ),
        "",
        (
            "The agent executor is evaluated separately using only `README.md`, `verify.sh`, "
            "and workspace inspection. It is intentionally denied `metadata.json`, "
            "`expected.patch`, `trapType`, and workflow bindings."
        ),
        "",
        (
            "Adversarial tasks measure whether bounded autonomy fails predictably under decoys, "
            "stale reads, rollback scenarios, ambiguous symbols, and verify-only requirements."
        ),
        "",
        (
            "Nightmare tasks (051–060) extend the adversarial runtime contract: contradictory specs, "
            "concurrent writers, sidecar rollback, stale search indexes, semantic preservation, "
            "and destructive-command containment."
        ),
    ]
    if claim.get("hasAgentResults"):
        agent_passed = claim["agentPassed"]
        agent_total = claim["agentTotal"]
        lines.extend(
            [
                "",
                (
                    f"In this run the agent executor passed **{agent_passed}/{agent_total}** tasks — "
                    "compare against the reference baseline and adversarial trap matrix below."
                ),
            ]
        )
    else:
        lines.extend(
            [
                "",
                "> Agent executor results are not present in this summary.",
            ]
        )
    lines.extend(["", f"> {claim['frame']}", ""])
    return lines


def _render_executor_coverage(coverage: dict[str, str]) -> list[str]:
    ref = coverage.get("reference", "absent")
    agent = coverage.get("agent", "absent")
    return [
        f"Executor coverage: reference **{ref}** | agent **{agent}**",
        "",
    ]


def render_markdown(summary: dict[str, Any]) -> str:
    lines: list[str] = [
        "# Agent Success Benchmark Report",
        "",
        f"Task results: **{summary['taskResultCount']}** "
        f"(normal: {summary['normalTaskCount']}, adversarial: {summary['adversarialTaskCount']}, "
        f"nightmare: {summary.get('nightmareTaskCount', 0)})",
        "",
    ]
    lines.extend(_render_executor_coverage(summary.get("executorCoverage", {})))
    lines.extend(_render_evaluation_claim(summary["evaluationClaim"]))
    lines.extend(
        [
            "## Money table",
            "",
            "| executor | mode | normal pass | adversarial pass | nightmare pass | wrong file | rollback | recovery |",
            "|----------|------|------------:|-----------------:|---------------:|-----------:|---------:|---------:|",
        ]
    )

    for row in summary["moneyTable"]:
        em = row["executorMode"]
        if ":" in em:
            executor, mode = em.split(":", 1)
        else:
            executor, mode = "reference", em
        lines.append(
            f"| {executor} | {mode} | {_fmt_rate(row['normalPassRate'])} | "
            f"{_fmt_rate(row['adversarialPassRate'])} | {_fmt_rate(row.get('nightmarePassRate', 0.0))} | "
            f"{row['wrongFileEdited']} | {row['rollbackSucceeded']} | {row['recoverySucceeded']} |"
        )

    nightmare_matrix = summary.get("nightmareTrapMatrix", [])
    if nightmare_matrix:
        lines.extend(["", "## Nightmare Runtime Contract Matrix", ""])
        lines.append(
            "| trapType | passRate | destructiveBlocked | sidecarClean | concurrentDetected | "
            "searchMismatch | apiPreserved | secondInvariant | finalVerify |"
        )
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in nightmare_matrix:
            lines.append(
                f"| {row['trapType']} | {_fmt_rate(row['passRate'])} | "
                f"{row['destructiveCommandBlocked']} | {row['sidecarRollbackClean']} | "
                f"{row['concurrentMutationDetected']} | {row['searchReadMismatchDetected']} | "
                f"{row['apiShapePreserved']} | {row['secondInvariantPassed']} | "
                f"{row['finalVerifyPassed']} |"
            )
        lines.append("")

    lines.extend(["", "## Adversarial Trap Matrix", ""])
    matrix = summary.get("adversarialTrapMatrix", [])
    if matrix:
        lines.append(
            "| trapType | passRate | wrongFileEdited | rollbackSucceeded | "
            "recoverySucceeded | avgRetries |"
        )
        lines.append("|---|---:|---:|---:|---:|---:|")
        for row in matrix:
            lines.append(
                f"| {row['trapType']} | {_fmt_rate(row['passRate'])} | {row['wrongFileEdited']} | "
                f"{row['rollbackSucceeded']} | {row['recoverySucceeded']} | {row['avgRetries']} |"
            )
        lines.append("")
    else:
        lines.append("_No adversarial tasks in this run._")
        lines.append("")

    lines.extend(
        [
            "## Overall pass rate by mode",
            "",
            "| Mode | Total | Passed | Pass rate | Avg tool calls | Avg retries | Avg duration (ms) |",
            "|------|------:|-------:|----------:|---------------:|------------:|------------------:|",
        ]
    )

    for mode, stats in summary["overallByMode"].items():
        lines.append(
            f"| {mode} | {stats['total']} | {stats['passed']} | {_fmt_rate(stats['passRate'])} "
            f"| {stats['avgToolCalls']} | {stats['avgRetries']} | {stats['avgDurationMs']} |"
        )

    lines.extend(["", "## Adversarial pass rate by trap type", ""])
    if summary["trapTypePassRate"]:
        for trap, mode_rates in summary["trapTypePassRate"].items():
            lines.append(f"### {trap}")
            lines.append("")
            lines.append("| Mode | Pass rate |")
            lines.append("|------|----------:|")
            for mode, rate in mode_rates.items():
                lines.append(f"| {mode} | {_fmt_rate(rate)} |")
            lines.append("")
    else:
        lines.append("_No adversarial tasks in this run._")
        lines.append("")

    lines.extend(["", "## Pass rate by category", ""])
    for category, mode_stats in summary["byCategory"].items():
        lines.append(f"### {category}")
        lines.append("")
        lines.append("| Mode | Total | Passed | Pass rate |")
        lines.append("|------|------:|-------:|----------:|")
        for mode, stats in mode_stats.items():
            lines.append(
                f"| {mode} | {stats['total']} | {stats['passed']} | {_fmt_rate(stats['passRate'])} |"
            )
        lines.append("")

    def counter_section(title: str, data: dict[str, int]) -> None:
        lines.extend([f"## {title}", ""])
        if not data:
            lines.append("_None_")
            lines.append("")
            return
        lines.append("| Key | Count |")
        lines.append("|-----|------:|")
        for key, count in data.items():
            lines.append(f"| {key} | {count} |")
        lines.append("")

    counter_section("Failure code counts", summary["failureCodeCounts"])
    counter_section("Recovery hints used", summary["recoveryHintsUsedCounts"])
    counter_section("Wrong file edited (by mode)", summary["wrongFileEditedCounts"])
    counter_section("Wrong file edited (by trap type)", summary["wrongFileEditedByTrapType"])
    counter_section("Stale recovery succeeded (by mode)", summary["staleRecoverySucceededCounts"])
    counter_section("Recovery succeeded (by trap type)", summary["recoverySucceededByTrapType"])
    counter_section("Rollback succeeded (by mode)", summary["rollbackSucceededCounts"])
    counter_section("Rollback succeeded (by trap type)", summary["rollbackSucceededByTrapType"])

    return "\n".join(lines).rstrip() + "\n"


def print_console_table(summary: dict[str, Any]) -> None:
    print(render_markdown(summary), end="")


def build_summary(
    rows: list[dict[str, Any]],
    task_meta: dict[str, dict[str, Any]],
    paths: list[Path],
) -> dict[str, Any]:
    summary = aggregate(rows, task_meta, paths)
    summary["generatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Report agent-success benchmark results.")
    parser.add_argument("--input", type=Path, help="Specific JSONL file (default: latest in results/).")
    parser.add_argument("--all", action="store_true", help="Aggregate all JSONL files in results/.")
    parser.add_argument("--no-write", action="store_true", help="Skip writing summary.json and summary.md.")
    args = parser.parse_args()

    try:
        paths = pick_jsonl_files(args.input, latest_only=not args.all)
        rows = load_task_results(paths)
        if not rows:
            print("no task_result rows found", file=sys.stderr)
            return 1

        task_meta = load_task_meta()
        summary = build_summary(rows, task_meta, paths)

        print_console_table(summary)

        if not args.no_write:
            RESULTS_DIR.mkdir(parents=True, exist_ok=True)
            json_path = RESULTS_DIR / "summary.json"
            md_path = RESULTS_DIR / "summary.md"
            json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
            md_path.write_text(render_markdown(summary), encoding="utf-8")
            print(f"\nWrote {json_path}", file=sys.stderr)
            print(f"Wrote {md_path}", file=sys.stderr)

        return 0
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
