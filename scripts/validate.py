#!/usr/bin/env python3
"""Validate the structure and integrity of a ScaleBench release checkout."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"FAIL: {message}")


def main() -> int:
    failures: list[str] = []
    manifest_path = ROOT / "data" / "manifest.json"
    try:
        records = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL: cannot read manifest: {error}")
        return 1

    if len(records) != 200:
        fail(f"manifest contains {len(records)} cases, expected 200", failures)
    indices = [record.get("index") for record in records]
    if indices != list(range(200)):
        fail("indices are not exactly 0..199 in order", failures)
    task_ids = [record.get("task_id") for record in records]
    if len(set(task_ids)) != len(task_ids):
        fail("task IDs are not unique", failures)
    legacy_task_ids = [record.get("legacy_task_id") for record in records]
    if len(set(legacy_task_ids)) != len(legacy_task_ids):
        fail("legacy task IDs are not unique", failures)

    observed_flags: dict[str, int] = {}
    allowed_case_files = {"spec.txt", "reference.v", "sec.tcl"}
    for record in records:
        task_id = record.get("task_id", "")
        legacy_task_id = record.get("legacy_task_id", "")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", task_id):
            fail(f"invalid task ID {task_id!r}", failures)
            continue
        if task_id.startswith("rtlpp_"):
            fail(f"internal RTLPP ID remains public: {task_id}", failures)
        if not re.fullmatch(r"rtlpp_\d{5}", legacy_task_id):
            fail(f"invalid legacy task ID for {task_id}: {legacy_task_id!r}", failures)
        if record.get("top_module") != task_id:
            fail(f"top module mismatch for {task_id}", failures)

        paths_and_hashes = (
            ("spec_path", "spec_sha256"),
            ("reference_path", "reference_sha256"),
            ("sec_tcl_path", "sec_tcl_sha256"),
        )
        resolved: dict[str, Path] = {}
        for path_key, hash_key in paths_and_hashes:
            relative = Path(record.get(path_key, ""))
            if relative.is_absolute() or ".." in relative.parts:
                fail(f"unsafe path for {task_id}: {relative}", failures)
                continue
            path = ROOT / relative
            resolved[path_key] = path
            if not path.is_file():
                fail(f"missing {relative}", failures)
            elif sha256(path) != record.get(hash_key):
                fail(f"SHA-256 mismatch for {relative}", failures)

        spec = resolved.get("spec_path")
        reference = resolved.get("reference_path")
        tcl = resolved.get("sec_tcl_path")
        if spec and spec.is_file():
            text = spec.read_text(encoding="utf-8", errors="replace")
            expected = "spec_missing_top_module_interface"
            has_flag = expected in record.get("review_flags", [])
            detected = not bool(
                re.search(rf"(?m)^\s*module\s+{re.escape(task_id)}\b", text)
            )
            if has_flag != detected:
                fail(f"stale missing-interface flag for {task_id}", failures)
            expected = "spec_contains_implementation_body"
            has_flag = expected in record.get("review_flags", [])
            detected = bool(re.search(r"(?m)^\s*endmodule\b", text))
            if has_flag != detected:
                fail(f"stale implementation-body flag for {task_id}", failures)
            if "rtlpp_" in text.lower():
                fail(f"internal RTLPP ID remains in prompt for {task_id}", failures)
        if reference and reference.is_file():
            text = reference.read_text(encoding="utf-8", errors="replace")
            if not re.search(rf"(?m)^\s*module\s+{re.escape(task_id)}\b", text):
                fail(f"reference lacks top module {task_id}", failures)
            expected = "reference_requires_external_memory_file"
            has_flag = expected in record.get("review_flags", [])
            detected = bool(re.search(r"\$readmem[hb]\s*\(", text))
            if has_flag != detected:
                fail(f"stale external-memory flag for {task_id}", failures)
        if tcl and tcl.is_file():
            text = tcl.read_text(encoding="utf-8", errors="replace")
            if task_id not in text:
                fail(f"SEC TCL does not name {task_id}", failures)

        case_dir = ROOT / "data" / "cases" / task_id
        if case_dir.is_dir():
            actual_files = {path.name for path in case_dir.iterdir() if path.is_file()}
            if actual_files != allowed_case_files:
                fail(
                    f"unexpected case files for {task_id}: {sorted(actual_files)}",
                    failures,
                )
        for flag in record.get("review_flags", []):
            observed_flags[flag] = observed_flags.get(flag, 0) + 1

    case_dirs = [path for path in (ROOT / "data" / "cases").iterdir() if path.is_dir()]
    if len(case_dirs) != 200:
        fail(f"found {len(case_dirs)} case directories, expected 200", failures)
    if {path.name for path in case_dirs} != set(task_ids):
        fail("case directory names do not exactly match semantic task IDs", failures)

    csv_checks = (
        (ROOT / "data" / "manifest.csv", "manifest CSV"),
        (ROOT / "review" / "case_review.csv", "case-review CSV"),
        (ROOT / "review" / "semantic_names.csv", "semantic-name CSV"),
    )
    for csv_path, label in csv_checks:
        try:
            with csv_path.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream))
        except OSError as error:
            fail(f"cannot read {label}: {error}", failures)
            continue
        if [row.get("task_id") for row in rows] != task_ids:
            fail(f"{label} task order does not match manifest", failures)

    expected_flag_rows = []
    for record in records:
        for flag in record.get("review_flags", []):
            expected_flag_rows.append(
                {
                    "index": str(record["index"]),
                    "legacy_task_id": record["legacy_task_id"],
                    "task_id": record["task_id"],
                    "loc": str(record["loc"]),
                    "flag": flag,
                    "path": record[
                        "spec_path" if flag.startswith("spec_") else "reference_path"
                    ],
                }
            )
    flagged_path = ROOT / "review" / "flagged_cases.csv"
    try:
        with flagged_path.open(encoding="utf-8", newline="") as stream:
            actual_flag_rows = list(csv.DictReader(stream))
        if actual_flag_rows != expected_flag_rows:
            fail("flagged-cases CSV does not match manifest review flags", failures)
    except OSError as error:
        fail(f"cannot read flagged-cases CSV: {error}", failures)

    fixes_path = ROOT / "review" / "description_fixes.csv"
    try:
        with fixes_path.open(encoding="utf-8", newline="") as stream:
            fix_rows = list(csv.DictReader(stream))
        fixed_indices = {int(row["index"]) for row in fix_rows}
        manifest_fixed_indices = {
            record["index"] for record in records if record.get("description_fixes")
        }
        if fixed_indices != manifest_fixed_indices:
            fail("description-fixes CSV does not match manifest", failures)
    except (OSError, KeyError, ValueError) as error:
        fail(f"cannot validate description-fixes CSV: {error}", failures)

    cohort_path = ROOT / "review" / "repair_evaluation_cohort.csv"
    try:
        with cohort_path.open(encoding="utf-8", newline="") as stream:
            cohort_rows = list(csv.DictReader(stream))
        cohort_ids = [row["task_id"] for row in cohort_rows]
        if len(cohort_ids) != 8 or len(set(cohort_ids)) != 8:
            fail("repair evaluation cohort must contain eight unique cases", failures)
    except (OSError, KeyError) as error:
        fail(f"cannot validate repair evaluation cohort: {error}", failures)
        cohort_ids = []

    evaluated_models = ["gpt-4o", "qwen3.5-397b", "deepseek-v3.2"]
    claude_artifacts = (
        ROOT
        / "evaluation"
        / "generated"
        / "claude-sonnet-4.5"
        / "generation_manifest.json"
    ).is_file() or (ROOT / "evaluation" / "results" / "claude-sonnet-4.5.csv").is_file()
    if claude_artifacts:
        evaluated_models.append("claude-sonnet-4.5")
    for model in evaluated_models:
        generation_path = (
            ROOT / "evaluation" / "generated" / model / "generation_manifest.json"
        )
        result_csv_path = ROOT / "evaluation" / "results" / f"{model}.csv"
        result_json_path = ROOT / "evaluation" / "results" / f"{model}.json"
        try:
            generation = json.loads(generation_path.read_text(encoding="utf-8"))
            candidates = generation["candidates"]
            if [row["task_id"] for row in candidates] != cohort_ids:
                fail(f"{model} generation order does not match cohort", failures)
            for candidate in candidates:
                relative = Path(candidate["candidate_path"])
                if relative.is_absolute() or ".." in relative.parts:
                    fail(f"unsafe generated-candidate path for {model}", failures)
                    continue
                path = ROOT / relative
                if not path.is_file():
                    fail(f"missing generated candidate {relative}", failures)
                elif sha256(path) != candidate["candidate_sha256"]:
                    fail(f"generated-candidate hash mismatch for {relative}", failures)

            with result_csv_path.open(encoding="utf-8", newline="") as stream:
                result_rows = list(csv.DictReader(stream))
            if [row["task_id"] for row in result_rows] != cohort_ids:
                fail(f"{model} result order does not match cohort", failures)
            result_summary = json.loads(result_json_path.read_text(encoding="utf-8"))
            passed = sum(row["sec_result"] == "pass" for row in result_rows)
            errors = sum(row["sec_result"] == "error" for row in result_rows)
            if result_summary.get("total") != len(result_rows):
                fail(f"{model} result total is stale", failures)
            if result_summary.get("passed") != passed:
                fail(f"{model} result pass count is stale", failures)
            if result_summary.get("errors") != errors:
                fail(f"{model} result error count is stale", failures)
        except (OSError, KeyError, json.JSONDecodeError) as error:
            fail(f"cannot validate {model} evaluation artifacts: {error}", failures)

    cost_path = ROOT / "evaluation" / "results" / "cost_summary.json"
    try:
        cost_summary = json.loads(cost_path.read_text(encoding="utf-8"))
        if cost_summary["maximum_total_including_untracked_attempt_usd"] > cost_summary[
            "authorized_limit_usd"
        ]:
            fail("evaluation API cost exceeded its authorized limit", failures)
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        fail(f"cannot validate evaluation cost summary: {error}", failures)

    audit_csv_path = ROOT / "review" / "all_case_audit.csv"
    audit_md_path = ROOT / "review" / "ALL_CASE_AUDIT.md"
    try:
        with audit_csv_path.open(encoding="utf-8", newline="") as stream:
            audit_rows = list(csv.DictReader(stream))
        if [row.get("task_id") for row in audit_rows] != task_ids:
            fail("all-case audit order does not match manifest", failures)
        consistent = sum(row.get("consistently_failed") == "yes" for row in audit_rows)
        if consistent != 142:
            fail(f"all-case audit has {consistent} consistent failures, expected 142", failures)
        audit_text = audit_md_path.read_text(encoding="utf-8")
        table_rows = sum(bool(re.match(r"^\| \d+ \|", line)) for line in audit_text.splitlines())
        if table_rows != 200:
            fail(f"all-case Markdown audit has {table_rows} rows, expected 200", failures)
    except (OSError, KeyError) as error:
        fail(f"cannot validate all-case audit: {error}", failures)

    viewer_files = (
        ROOT / "viewer" / "index.html",
        ROOT / "viewer" / "review.html",
        ROOT / "viewer" / "assets" / "styles.css",
        ROOT / "viewer" / "assets" / "app.js",
        ROOT / "scripts" / "build_viewer.py",
        ROOT / ".github" / "workflows" / "pages.yml",
    )
    for viewer_path in viewer_files:
        if not viewer_path.is_file():
            fail(f"missing viewer file {viewer_path.relative_to(ROOT)}", failures)
            continue
        viewer_text = viewer_path.read_text(encoding="utf-8", errors="replace")
        if viewer_path.is_relative_to(ROOT / "viewer") and "rtlpp_" in viewer_text.lower():
            fail(
                f"legacy task-name pattern appears in public viewer source "
                f"{viewer_path.relative_to(ROOT)}",
                failures,
            )

    local_path_markers = (
        "/" + "home" + "/",
        "projects" + "_3rd_year",
        "jwang" + "jw",
    )
    oversized = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        relative = path.relative_to(ROOT)
        if relative.parts[:2] in {
            ("evaluation", "logs"),
            ("evaluation", "raw_responses"),
        }:
            continue
        if path.stat().st_size > 10 * 1024 * 1024:
            oversized.append(relative.as_posix())
        if path.suffix.lower() in {".md", ".json", ".csv", ".txt", ".v", ".tcl", ".py"}:
            text = path.read_text(encoding="utf-8", errors="replace")
            if any(marker in text for marker in local_path_markers):
                fail(f"local workstation path marker in {relative}", failures)
    if oversized:
        fail(f"files larger than 10 MiB: {oversized}", failures)

    locs = [record["loc"] for record in records]
    sequential = sum(bool(record["is_sequential"]) for record in records)
    print(
        "SUMMARY: "
        f"cases={len(records)}, sequential={sequential}, "
        f"combinational={len(records) - sequential}, "
        f"loc={min(locs)}..{max(locs)}, mean={sum(locs) / len(locs):.3f}"
    )
    if observed_flags:
        print(
            "REVIEW FLAGS: "
            + ", ".join(f"{name}={count}" for name, count in sorted(observed_flags.items()))
        )
    if failures:
        print(f"RESULT: failed with {len(failures)} issue(s)")
        return 1
    print("RESULT: structural validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
