#!/usr/bin/env python3
"""Build the complete 200-case historical-failure and repair audit.

Historical result and log locations are command-line inputs because the source
runs are intentionally not distributed with the release repository. The
generated CSV and Markdown contain compact outcomes, never workstation paths.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FRESH_MODELS = (
    ("gpt-4o", "GPT-new"),
    ("claude-sonnet-4.5", "Claude-new"),
    ("qwen3.5-397b", "Qwen-new"),
    ("deepseek-v3.2", "DeepSeek-new"),
)


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def historical_kind(row: dict, log_dir: Path) -> str:
    if row.get("success") is True:
        return "PASS"
    if row.get("error"):
        return "RUNNER"
    log_path = log_dir / f"sec_{row['design_name']}.log"
    text = log_path.read_text(encoding="utf-8", errors="replace")
    lower = text.lower()
    if "counterexample (cex)" in lower or re.search(r"(?mi)^cex\s*$", text):
        return "CEX"
    if "error (enl034)" in lower:
        return "ELAB"
    if "problem encountered at line" in lower:
        return "TOOL"
    if re.search(r"(?mi)^no_properties\s*$", text):
        return "NOPROP"
    if "timeout" in lower or "timed out" in lower:
        return "TIMEOUT"
    return "INDET"


def load_history(results_path: Path, log_dir: Path) -> dict[int, str]:
    payload = json.loads(results_path.read_text(encoding="utf-8"))
    rows = payload["results"]
    if len(rows) != 200:
        raise SystemExit(f"{results_path} has {len(rows)} rows, expected 200")
    outcomes = {int(row["index"]): historical_kind(row, log_dir) for row in rows}
    if set(outcomes) != set(range(200)):
        raise SystemExit(f"{results_path} indices are not exactly 0..199")
    return outcomes


def fresh_kind(row: dict[str, str]) -> str:
    mapping = {
        "equivalent": "PASS",
        "counterexample": "CEX",
        "elaboration_error": "ELAB",
        "sec_failure": "SEC",
        "runner_error": "RUNNER",
    }
    return mapping.get(row.get("failure_kind", ""), row.get("sec_result", "").upper())


def load_fresh(root: Path) -> dict[str, dict[str, str]]:
    results: dict[str, dict[str, str]] = {}
    for model, _ in FRESH_MODELS:
        path = root / "evaluation" / "results" / f"{model}.csv"
        results[model] = (
            {row["task_id"]: fresh_kind(row) for row in load_csv(path)}
            if path.is_file()
            else {}
        )
    return results


def joined_defects(rows: list[dict[str, str]]) -> str:
    labels = {
        "embedded_reference_implementation": "implementation leakage",
        "mismatched_or_missing_top_description": "mismatched/missing top description",
        "incorrect_reset_semantics": "incorrect reset semantics",
        "missing_reset_defaults": "missing reset defaults",
        "nondeterministic_reference_behavior": "pathological golden behavior",
        "incorrect_observable_behavior": "incorrect golden observable behavior",
        "incorrect_timer_semantics": "incorrect timer semantics",
        "incorrect_unassigned_state_semantics": "incorrect unassigned-state semantics",
    }
    values = []
    for row in rows:
        value = labels.get(row["defect"], row["defect"].replace("_", " "))
        if value not in values:
            values.append(value)
    return "; ".join(values)


def disposition(
    record: dict,
    cohort: dict[str, str] | None,
    fixes: list[dict[str, str]],
) -> tuple[str, str]:
    if cohort:
        status = cohort["curation_status"]
        finding = cohort["audit_finding"].rstrip(".") + "."
        if status == "repaired_evaluation_ready":
            return finding, "Fixed: prompt repaired; reevaluated"
        if status == "blocked_missing_memory_image":
            return finding, "Not fixed: required memory image absent"
        if status == "quarantined_golden_pathology":
            return finding, "Prompt repaired; golden quarantined"
        return finding, status.replace("_", " ")
    flags = set(record.get("review_flags", []))
    if "reference_requires_toolchain_review" in flags:
        return (
            "Reference failed the secondary Icarus elaboration smoke test; "
            "JasperGold compatibility needs review.",
            "Pending: reference/toolchain review",
        )
    if fixes:
        return (
            f"Confirmed prompt defect: {joined_defects(fixes)}.",
            "Fixed: prompt repaired",
        )
    return "No confirmed dataset defect.", "N/A: no confirmed dataset defect"


def escape_markdown(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gpt-results", type=Path, required=True)
    parser.add_argument("--gpt-logs", type=Path, required=True)
    parser.add_argument("--claude-results", type=Path, required=True)
    parser.add_argument("--claude-logs", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()

    manifest = json.loads((root / "data" / "manifest.json").read_text(encoding="utf-8"))
    gpt = load_history(args.gpt_results.resolve(), args.gpt_logs.resolve())
    claude = load_history(args.claude_results.resolve(), args.claude_logs.resolve())
    fixes_by_task: dict[str, list[dict[str, str]]] = {}
    for row in load_csv(root / "review" / "description_fixes.csv"):
        fixes_by_task.setdefault(row["task_id"], []).append(row)
    cohort_by_task = {
        row["task_id"]: row
        for row in load_csv(root / "review" / "repair_cohort_status.csv")
    }
    fresh = load_fresh(root)

    rows = []
    for record in manifest:
        index = int(record["index"])
        task_id = record["task_id"]
        consistently_failed = gpt[index] != "PASS" and claude[index] != "PASS"
        reason, resolution = disposition(
            record, cohort_by_task.get(task_id), fixes_by_task.get(task_id, [])
        )
        if consistently_failed and task_id not in cohort_by_task and reason == "No confirmed dataset defect.":
            reason = (
                f"No confirmed dataset defect; observed GPT-old {gpt[index]} and "
                f"Claude-old {claude[index]}."
            )
        rows.append(
            {
                "index": index,
                "task_id": task_id,
                "legacy_task_id": record["legacy_task_id"],
                "gpt4o_historical": gpt[index],
                "claude_sonnet_4_5_historical": claude[index],
                "consistently_failed": "yes" if consistently_failed else "no",
                "failure_reason_or_audit_finding": reason,
                "fix_status": resolution,
                "gpt4o_fresh": fresh["gpt-4o"].get(task_id, "—"),
                "claude_sonnet_4_5_fresh": fresh["claude-sonnet-4.5"].get(task_id, "—"),
                "qwen3_5_397b_fresh": fresh["qwen3.5-397b"].get(task_id, "—"),
                "deepseek_v3_2_fresh": fresh["deepseek-v3.2"].get(task_id, "—"),
            }
        )

    review_root = root / "review"
    csv_path = review_root / "all_case_audit.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    consistent_count = sum(row["consistently_failed"] == "yes" for row in rows)
    dispositions = Counter(row["fix_status"] for row in rows if row["consistently_failed"] == "yes")
    md = [
        "# ScaleBench all-case failure and repair audit",
        "",
        "## Scope and interpretation",
        "",
        "This ledger covers all 200 cases. **Consistently failed** means that the case "
        "failed both complete historical single-sample runs: GPT-4o and Claude Sonnet "
        "4.5. It does not by itself prove a prompt defect. The reason column separates "
        "confirmed dataset findings from ordinary model failures and records only evidence "
        "available in the source SEC logs and curation audit.",
        "",
        "Historical outcome codes: `PASS` = equivalent, `CEX` = formal counterexample, "
        "`ELAB` = elaboration error, `TOOL` = other JasperGold command error, `NOPROP` = "
        "no mapped comparison properties, `TIMEOUT` = explicit timeout, `INDET` = run "
        "ended without a decisive logged outcome, and `RUNNER` = harness error. Fresh "
        "columns are populated only for the eight repaired evaluation-ready cases; `—` "
        "means not rerun.",
        "",
        "## Summary",
        "",
        f"- Historical GPT-4o: {sum(v == 'PASS' for v in gpt.values())}/200 passed.",
        f"- Historical Claude Sonnet 4.5: {sum(v == 'PASS' for v in claude.values())}/200 passed.",
        f"- Consistently failed by both: {consistent_count}/200.",
        "- Of those 142 cases, 20 had confirmed dataset issues: eight prompt repairs are "
        "evaluation-ready, two remain blocked by absent memory images, and ten have repaired "
        "prompts but quarantined golden RTL.",
    ]
    for model, label in FRESH_MODELS:
        values = list(fresh[model].values())
        if values:
            md.append(f"- Fresh {label.removesuffix('-new')}: {values.count('PASS')}/{len(values)} passed.")
    md.extend(
        [
            "",
            "## Complete ledger",
            "",
            "| # | Semantic task | Legacy ID | GPT-old | Claude-old | Both fail? | "
            "Reason / audit finding | Fix status | GPT-new | Claude-new | Qwen-new | DeepSeek-new |",
            "| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in rows:
        values = (
            row["index"],
            f"`{row['task_id']}`",
            f"`{row['legacy_task_id']}`",
            row["gpt4o_historical"],
            row["claude_sonnet_4_5_historical"],
            row["consistently_failed"],
            row["failure_reason_or_audit_finding"],
            row["fix_status"],
            row["gpt4o_fresh"],
            row["claude_sonnet_4_5_fresh"],
            row["qwen3_5_397b_fresh"],
            row["deepseek_v3_2_fresh"],
        )
        md.append("| " + " | ".join(escape_markdown(value) for value in values) + " |")
    md.extend(
        [
            "",
            "The machine-readable companion is `all_case_audit.csv`. Historical source "
            "run locations are supplied to the builder and are deliberately not embedded "
            "in release artifacts.",
            "",
        ]
    )
    (review_root / "ALL_CASE_AUDIT.md").write_text("\n".join(md), encoding="utf-8")
    print(f"wrote {len(rows)} audit rows; {consistent_count} consistently failed")
    print("consistent-failure resolutions:")
    for status, count in sorted(dispositions.items()):
        print(f"  {status}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
