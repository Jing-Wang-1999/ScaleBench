#!/usr/bin/env python3
"""Refresh the public ScaleBench manifests from the released case files."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_JSON = ROOT / "data" / "manifest.json"
MANIFEST_CSV = ROOT / "data" / "manifest.csv"
PUBLIC_FIELDS = (
    "index",
    "task_id",
    "top_module",
    "loc",
    "is_sequential",
    "spec_path",
    "reference_path",
    "sec_tcl_path",
    "spec_sha256",
    "reference_sha256",
    "sec_tcl_sha256",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    previous = json.loads(MANIFEST_JSON.read_text(encoding="utf-8"))
    records = []

    for old_record in previous:
        task_id = old_record["task_id"]
        case_root = ROOT / "data" / "cases" / task_id
        spec_path = case_root / "spec.txt"
        reference_path = case_root / "reference.v"
        sec_tcl_path = case_root / "sec.tcl"
        for path in (spec_path, reference_path, sec_tcl_path):
            if not path.is_file():
                raise SystemExit(f"missing case file: {path.relative_to(ROOT)}")

        records.append(
            {
                "index": old_record["index"],
                "task_id": task_id,
                "top_module": task_id,
                "loc": len(reference_path.read_text(encoding="utf-8").splitlines()),
                "is_sequential": bool(old_record["is_sequential"]),
                "spec_path": spec_path.relative_to(ROOT).as_posix(),
                "reference_path": reference_path.relative_to(ROOT).as_posix(),
                "sec_tcl_path": sec_tcl_path.relative_to(ROOT).as_posix(),
                "spec_sha256": sha256(spec_path),
                "reference_sha256": sha256(reference_path),
                "sec_tcl_sha256": sha256(sec_tcl_path),
            }
        )

    MANIFEST_JSON.write_text(
        json.dumps(records, indent=2) + "\n",
        encoding="utf-8",
    )
    with MANIFEST_CSV.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=PUBLIC_FIELDS,
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(records)

    print(f"refreshed {len(records)} public manifest records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
