#!/usr/bin/env python3
"""Merge available repaired-cohort SEC results into one compact ledger."""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODELS = ("gpt-4o", "claude-sonnet-4.5", "qwen3.5-397b", "deepseek-v3.2")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def column_prefix(model: str) -> str:
    return model.replace("-", "_").replace(".", "_")


def main() -> int:
    cohort = read_csv(ROOT / "review" / "repair_evaluation_cohort.csv")
    by_model = {}
    for model in MODELS:
        path = ROOT / "evaluation" / "results" / f"{model}.csv"
        by_model[model] = (
            {row["task_id"]: row for row in read_csv(path)} if path.is_file() else {}
        )

    base_fields = ["index", "legacy_task_id", "task_id"]
    model_fields = [
        field
        for model in MODELS
        for field in (f"{column_prefix(model)}_sec", f"{column_prefix(model)}_failure_kind")
    ]
    rows = []
    for item in cohort:
        row = {field: item[field] for field in base_fields}
        for model in MODELS:
            prefix = column_prefix(model)
            result = by_model[model].get(item["task_id"], {})
            row[f"{prefix}_sec"] = result.get("sec_result", "")
            row[f"{prefix}_failure_kind"] = result.get("failure_kind", "")
        rows.append(row)

    output = ROOT / "evaluation" / "results" / "combined.csv"
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=base_fields + model_fields, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} rows to {output.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
