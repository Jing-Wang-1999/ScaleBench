#!/usr/bin/env python3
"""Validate the public ScaleBench release."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
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
CASE_FILES = {"spec.txt", "reference.v", "sec.tcl"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"FAIL: {message}")


def validate_manifest(failures: list[str]) -> list[dict]:
    manifest_path = ROOT / "data" / "manifest.json"
    try:
        records = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read manifest: {error}", failures)
        return []

    if len(records) != 200:
        fail(f"manifest contains {len(records)} cases, expected 200", failures)
    if [record.get("index") for record in records] != list(range(200)):
        fail("manifest indices are not exactly 0..199", failures)

    task_ids = [record.get("task_id") for record in records]
    if len(set(task_ids)) != len(task_ids):
        fail("task IDs are not unique", failures)

    for record in records:
        task_id = record.get("task_id", "")
        if set(record) != set(PUBLIC_FIELDS):
            fail(f"non-public manifest fields for {task_id}", failures)
        if not re.fullmatch(r"[a-z][a-z0-9_]*", task_id):
            fail(f"invalid semantic task ID {task_id!r}", failures)
            continue
        if record.get("top_module") != task_id:
            fail(f"top-module mismatch for {task_id}", failures)

        resolved = {}
        for path_key, hash_key in (
            ("spec_path", "spec_sha256"),
            ("reference_path", "reference_sha256"),
            ("sec_tcl_path", "sec_tcl_sha256"),
        ):
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

        reference = resolved.get("reference_path")
        if reference and reference.is_file():
            text = reference.read_text(encoding="utf-8", errors="replace")
            if not re.search(rf"(?m)^\s*module\s+{re.escape(task_id)}\b", text):
                fail(f"reference lacks top module {task_id}", failures)
            if re.search(r"\$readmem[hb]\s*\(", text):
                fail(f"reference requires an external memory image: {task_id}", failures)
            observed_loc = len(text.splitlines())
            if observed_loc != record.get("loc"):
                fail(f"stale LoC for {task_id}", failures)

        spec = resolved.get("spec_path")
        if spec and spec.is_file():
            text = spec.read_text(encoding="utf-8", errors="replace")
            if not re.search(rf"(?m)^\s*module\s+{re.escape(task_id)}\b", text):
                fail(f"specification lacks module interface for {task_id}", failures)
            if re.search(r"(?m)^\s*endmodule\b", text):
                fail(f"specification contains an implementation body: {task_id}", failures)

        sec_tcl = resolved.get("sec_tcl_path")
        if sec_tcl and sec_tcl.is_file():
            text = sec_tcl.read_text(encoding="utf-8", errors="replace")
            if task_id not in text:
                fail(f"SEC script does not name {task_id}", failures)

        case_dir = ROOT / "data" / "cases" / task_id
        if not case_dir.is_dir():
            fail(f"missing case directory for {task_id}", failures)
        else:
            files = {path.name for path in case_dir.iterdir() if path.is_file()}
            if files != CASE_FILES:
                fail(f"unexpected files for {task_id}: {sorted(files)}", failures)

    case_root = ROOT / "data" / "cases"
    case_dirs = {path.name for path in case_root.iterdir() if path.is_dir()}
    if case_dirs != set(task_ids):
        fail("case directories do not exactly match the manifest", failures)
    return records


def validate_csv(records: list[dict], failures: list[str]) -> None:
    try:
        with (ROOT / "data" / "manifest.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            reader = csv.DictReader(stream)
            rows = list(reader)
            if tuple(reader.fieldnames or ()) != PUBLIC_FIELDS:
                fail("manifest CSV has non-public fields", failures)
    except OSError as error:
        fail(f"cannot read manifest CSV: {error}", failures)
        return
    if [row.get("task_id") for row in rows] != [
        record.get("task_id") for record in records
    ]:
        fail("manifest CSV order does not match JSON", failures)


def validate_public_boundary(failures: list[str]) -> None:
    for forbidden in ("review", "evaluation", "LICENSE_REVIEW.md"):
        if (ROOT / forbidden).exists():
            fail(f"internal material remains public: {forbidden}", failures)

    banned_markers = (
        "rtlpp_",
        "legacy_task_id",
        "source_case",
        "original_top_module",
        "description_fixes",
        "curation_status",
        "review_flags",
        "repaired_evaluation_ready",
        "quarantined_",
    )
    scan_roots = (ROOT / "data", ROOT / "viewer", ROOT / "README.md", ROOT / "UPSTREAM.md")
    for scan_root in scan_roots:
        paths = [scan_root] if scan_root.is_file() else scan_root.rglob("*")
        for path in paths:
            if not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="replace").lower()
            for marker in banned_markers:
                if marker.lower() in text:
                    fail(
                        f"internal marker {marker!r} in {path.relative_to(ROOT)}",
                        failures,
                    )


def validate_iverilog(records: list[dict], failures: list[str]) -> None:
    executable = shutil.which("iverilog")
    if not executable:
        print("INFO: iverilog not installed; reference elaboration skipped")
        return
    for record in records:
        completed = subprocess.run(
            [
                executable,
                "-g2012",
                "-tnull",
                "-s",
                record["top_module"],
                str(ROOT / record["reference_path"]),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode:
            detail = completed.stderr.strip().splitlines()[-1]
            fail(f"Icarus elaboration failed for {record['task_id']}: {detail}", failures)


def main() -> int:
    failures: list[str] = []
    records = validate_manifest(failures)
    validate_csv(records, failures)
    validate_public_boundary(failures)
    validate_iverilog(records, failures)

    viewer_files = (
        ROOT / "viewer" / "index.html",
        ROOT / "viewer" / "review.html",
        ROOT / "viewer" / "assets" / "styles.css",
        ROOT / "viewer" / "assets" / "app.js",
        ROOT / "scripts" / "build_viewer.py",
        ROOT / "scripts" / "stage_jasper.py",
        ROOT / "scripts" / "verify_yosys.py",
        ROOT / ".github" / "workflows" / "pages.yml",
    )
    for path in viewer_files:
        if not path.is_file():
            fail(f"missing browser file {path.relative_to(ROOT)}", failures)

    sequential = sum(bool(record.get("is_sequential")) for record in records)
    print(
        f"SUMMARY: cases={len(records)}, sequential={sequential}, "
        f"combinational={len(records) - sequential}, failures={len(failures)}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
