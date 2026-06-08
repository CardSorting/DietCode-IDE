#!/usr/bin/env python3
"""Aggregate agent-success benchmark JSONL results into comparison reports."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
RESULTS_DIR = BENCHMARK_ROOT / "results"
TASKS_DIR = BENCHMARK_ROOT / "tasks"


def load_task_categories() -> dict[str, str]:
    categories: dict[str, str] = {}
    if not TASKS_DIR.is_dir():
        return categories
    for task_dir in sorted(TASKS_DIR.iterdir()):
        meta_path = task_dir / "metadata.json"
        if not meta_path.is_file():
            continue
        with open(meta_path, encoding="utf-8") as handle:
            meta = json.load(handle)
        categories[str(meta.get("id", task_dir.name))] = str(meta.get("category", "unknown"))
    return categories


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


def aggregate(rows: list[dict[str, Any]], categories: dict[str, str], paths: list[Path]) -> dict[str, Any]:
    by_mode: dict[str, list[dict[str, Any]]] = defaultdict(list)
    by_category_mode: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(lambda: defaultdict(list))

    failure_codes: Counter[str] = Counter()
    recovery_hints: Counter[str] = Counter()
    wrong_file_by_mode: Counter[str] = Counter()
    stale_recovery_by_mode: Counter[str] = Counter()
    rollback_by_mode: Counter[str] = Counter()

    for row in rows:
        mode = str(row.get("mode", "unknown"))
        executor = str(row.get("executor", "reference"))
        mode_key = f"{mode}:{executor}" if executor != "reference" else mode
        by_mode[mode_key].append(row)

        task_id = str(row.get("taskId", ""))
        category = categories.get(task_id, "unknown")
        by_category_mode[category][mode_key].append(row)

        code = row.get("failureCode")
        if code:
            failure_codes[str(code)] += 1

        for hint in row.get("recoveryHintsUsed") or []:
            recovery_hints[str(hint)] += 1

        if row.get("wrongFileEdited"):
            wrong_file_by_mode[mode_key] += 1
        if row.get("staleRecoverySucceeded"):
            stale_recovery_by_mode[mode_key] += 1
        if row.get("rollbackSucceeded"):
            rollback_by_mode[mode_key] += 1

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

    return {
        "sourceFiles": [str(p) for p in paths],
        "taskResultCount": len(rows),
        "overallByMode": overall_by_mode,
        "byCategory": by_category,
        "failureCodeCounts": dict(failure_codes.most_common()),
        "recoveryHintsUsedCounts": dict(recovery_hints.most_common()),
        "wrongFileEditedCounts": dict(wrong_file_by_mode),
        "staleRecoverySucceededCounts": dict(stale_recovery_by_mode),
        "rollbackSucceededCounts": dict(rollback_by_mode),
    }


def _fmt_rate(value: float) -> str:
    return f"{value * 100:.1f}%"


def render_markdown(summary: dict[str, Any]) -> str:
    lines: list[str] = [
        "# Agent Success Benchmark Report",
        "",
        f"Task results: **{summary['taskResultCount']}**",
        "",
        "## Overall pass rate by mode",
        "",
        "| Mode | Total | Passed | Pass rate | Avg tool calls | Avg retries | Avg duration (ms) |",
        "|------|------:|-------:|----------:|---------------:|------------:|------------------:|",
    ]

    for mode, stats in summary["overallByMode"].items():
        lines.append(
            f"| {mode} | {stats['total']} | {stats['passed']} | {_fmt_rate(stats['passRate'])} "
            f"| {stats['avgToolCalls']} | {stats['avgRetries']} | {stats['avgDurationMs']} |"
        )

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
    counter_section("Wrong file edited", summary["wrongFileEditedCounts"])
    counter_section("Stale recovery succeeded", summary["staleRecoverySucceededCounts"])
    counter_section("Rollback succeeded", summary["rollbackSucceededCounts"])

    return "\n".join(lines).rstrip() + "\n"


def print_console_table(summary: dict[str, Any]) -> None:
    print(render_markdown(summary), end="")


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

        categories = load_task_categories()
        summary = aggregate(rows, categories, paths)

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
