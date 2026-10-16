#!/usr/bin/env python3
"""Import compact per-case outcomes from the two complete baseline SEC runs."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def load_results(path: Path, expected_legacy_ids: list[str]) -> tuple[dict[int, bool], dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    results = payload.get("results", [])
    by_index = {row["index"]: row for row in results}
    if sorted(by_index) != list(range(200)):
        raise SystemExit(f"{path} does not contain exactly indices 0..199")
    for index, legacy_id in enumerate(expected_legacy_ids):
        if by_index[index].get("design_name") != legacy_id:
            raise SystemExit(f"legacy ID mismatch at index {index} in {path}")
        if by_index[index].get("error") is not None:
            raise SystemExit(f"verification error at index {index} in {path}")
    return {index: bool(row["success"]) for index, row in by_index.items()}, payload


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gpt4o-results", type=Path, required=True)
    parser.add_argument("--claude-results", type=Path, required=True)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root / "data" / "manifest.json").read_text(encoding="utf-8"))
    legacy_ids = [record["legacy_task_id"] for record in manifest]
    gpt4o, gpt_payload = load_results(args.gpt4o_results, legacy_ids)
    claude, claude_payload = load_results(args.claude_results, legacy_ids)

    fields = [
        "index", "legacy_task_id", "task_id", "gpt4o_baseline",
        "claude_sonnet_4_5_baseline", "both_baselines_failed",
        "description_fixes", "curation_status", "review_flags",
    ]
    rows = []
    failed_both = []
    audited_failure_cohort = []
    repair_cohort = []
    for record in manifest:
        index = record["index"]
        both_failed = not gpt4o[index] and not claude[index]
        row = {
            "index": index,
            "legacy_task_id": record["legacy_task_id"],
            "task_id": record["task_id"],
            "gpt4o_baseline": "pass" if gpt4o[index] else "fail",
            "claude_sonnet_4_5_baseline": "pass" if claude[index] else "fail",
            "both_baselines_failed": str(both_failed).lower(),
            "description_fixes": ";".join(record["description_fixes"]),
            "curation_status": record["curation_status"],
            "review_flags": ";".join(record["review_flags"]),
        }
        rows.append(row)
        if both_failed:
            failed_both.append(row)
            if record["description_fixes"] or record["curation_status"] in {
                "blocked_missing_memory_image",
                "quarantined_golden_pathology",
            }:
                audited_failure_cohort.append(row)
            if record["curation_status"] == "repaired_evaluation_ready":
                repair_cohort.append(row)

    review = root / "review"
    write_csv(review / "baseline_direct_results.csv", fields, rows)
    write_csv(review / "all_baseline_models_failed.csv", fields, failed_both)
    write_csv(review / "audited_failure_cohort.csv", fields, audited_failure_cohort)
    write_csv(review / "repair_evaluation_cohort.csv", fields, repair_cohort)
    summary = {
        "scope": "two complete direct-generation runs with SEC outcomes",
        "models": {
            "gpt-4o": {
                "verified": gpt_payload["verified"],
                "passed": gpt_payload["passed"],
                "failed": gpt_payload["failed"],
                "pass_rate": gpt_payload["pass_rate"],
            },
            "claude-sonnet-4.5": {
                "verified": claude_payload["verified"],
                "passed": claude_payload["passed"],
                "failed": claude_payload["failed"],
                "pass_rate": claude_payload["pass_rate"],
            },
        },
        "both_baselines_failed": len(failed_both),
        "audited_failure_cohort": len(audited_failure_cohort),
        "repair_evaluation_cohort": len(repair_cohort),
        "note": (
            "No complete per-case DeepSeek ScaleBench result was found, so it is "
            "not used to define the per-case intersection."
        ),
    }
    (review / "baseline_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"imported 200 outcomes; both_failed={len(failed_both)}; "
        f"audited_cohort={len(audited_failure_cohort)}; "
        f"repair_cohort={len(repair_cohort)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
