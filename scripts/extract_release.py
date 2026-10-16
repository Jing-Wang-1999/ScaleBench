#!/usr/bin/env python3
"""Extract the public ScaleBench core from CorrectRTL's internal dataset tree."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="CorrectRTL data/rtlpp_balanced_200 directory",
    )
    parser.add_argument(
        "--verification-source",
        type=Path,
        required=True,
        help="RTLPP-processed/ready/Star-repos/designs directory",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="ScaleBench repository root",
    )
    args = parser.parse_args()

    dataset_path = args.source / "dataset.json"
    records = json.loads(dataset_path.read_text(encoding="utf-8"))
    if len(records) != 200:
        raise SystemExit(f"expected 200 source records, found {len(records)}")
    if [record["index"] for record in records] != list(range(200)):
        raise SystemExit("source indices are not exactly 0..199 in order")

    data_root = args.output / "data"
    cases_root = data_root / "cases"
    manifest_path = data_root / "manifest.json"
    if cases_root.exists() or manifest_path.exists():
        raise SystemExit("output data already exists; refusing to overwrite it")
    cases_root.mkdir(parents=True)

    manifest = []
    flagged = []
    seen_tasks: set[str] = set()

    for source_record in records:
        index = source_record["index"]
        task_id = source_record["design_name"]
        if not re.fullmatch(r"rtlpp_\d{5}", task_id):
            raise SystemExit(f"unexpected task id: {task_id}")
        if task_id in seen_tasks:
            raise SystemExit(f"duplicate task id: {task_id}")
        seen_tasks.add(task_id)

        source_case = args.source / "cases" / f"case_{index:04d}"
        source_spec = source_case / "spec_fixed.txt"
        source_reference = source_case / "golden_rtl.v"
        source_tcl = args.verification_source / task_id / f"sec_{task_id}.tcl"
        for required in (source_spec, source_reference, source_tcl):
            if not required.is_file():
                raise SystemExit(f"missing source file: {required}")

        case_root = cases_root / task_id
        case_root.mkdir()
        spec_path = case_root / "spec.txt"
        reference_path = case_root / "reference.v"
        tcl_path = case_root / "sec.tcl"
        shutil.copyfile(source_spec, spec_path)
        shutil.copyfile(source_reference, reference_path)
        shutil.copyfile(source_tcl, tcl_path)

        spec_text = spec_path.read_text(encoding="utf-8", errors="replace")
        reference_text = reference_path.read_text(encoding="utf-8", errors="replace")
        flags = []
        if not re.search(
            rf"(?m)^\s*module\s+{re.escape(task_id)}\b", spec_text
        ):
            flags.append("spec_missing_top_module_interface")
        if re.search(r"(?m)^\s*endmodule\b", spec_text):
            flags.append("spec_contains_implementation_body")
        if re.search(r"\$readmem[hb]\s*\(", reference_text):
            flags.append("reference_requires_external_memory_file")

        record = {
            "index": index,
            "source_case": f"case_{index:04d}",
            "task_id": task_id,
            "top_module": task_id,
            "loc": source_record["loc"],
            "is_sequential": source_record["is_sequential"],
            "spec_path": spec_path.relative_to(args.output).as_posix(),
            "reference_path": reference_path.relative_to(args.output).as_posix(),
            "sec_tcl_path": tcl_path.relative_to(args.output).as_posix(),
            "spec_sha256": sha256(spec_path),
            "reference_sha256": sha256(reference_path),
            "sec_tcl_sha256": sha256(tcl_path),
            "review_flags": flags,
        }
        manifest.append(record)
        for flag in flags:
            flagged.append(
                {
                    "index": index,
                    "task_id": task_id,
                    "loc": source_record["loc"],
                    "flag": flag,
                    "path": record[
                        "spec_path"
                        if flag.startswith("spec_")
                        else "reference_path"
                    ],
                }
            )

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    csv_fields = [
        "index",
        "source_case",
        "task_id",
        "top_module",
        "loc",
        "is_sequential",
        "spec_path",
        "reference_path",
        "sec_tcl_path",
        "review_flags",
    ]
    with (data_root / "manifest.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=csv_fields, lineterminator="\n")
        writer.writeheader()
        for record in manifest:
            row = {field: record[field] for field in csv_fields}
            row["review_flags"] = ";".join(record["review_flags"])
            writer.writerow(row)

    flagged_path = args.output / "review" / "flagged_cases.csv"
    flagged_path.parent.mkdir(parents=True, exist_ok=True)
    with flagged_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=["index", "task_id", "loc", "flag", "path"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(flagged)

    review_path = args.output / "review" / "case_review.csv"
    review_fields = [
        "index",
        "task_id",
        "loc",
        "is_sequential",
        "review_flags",
        "reviewed",
        "spec_ok",
        "reference_ok",
        "notes",
    ]
    with review_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=review_fields, lineterminator="\n"
        )
        writer.writeheader()
        for record in manifest:
            writer.writerow(
                {
                    "index": record["index"],
                    "task_id": record["task_id"],
                    "loc": record["loc"],
                    "is_sequential": record["is_sequential"],
                    "review_flags": ";".join(record["review_flags"]),
                    "reviewed": "",
                    "spec_ok": "",
                    "reference_ok": "",
                    "notes": "",
                }
            )

    print(f"extracted {len(manifest)} cases to {cases_root}")
    print(f"wrote {len(flagged)} review flags to {flagged_path}")
    print(f"wrote {len(manifest)} review rows to {review_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
