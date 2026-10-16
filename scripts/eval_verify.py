#!/usr/bin/env python3
"""Run remote JasperGold SEC for generated ScaleBench candidates."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT.parent / "Comprehensive-RTL-Bench"
sys.path.insert(0, str(BENCH_ROOT / "Tools"))


def classify_failure(log_path: str | None, success: bool, error: str) -> str:
    if success:
        return "equivalent"
    if error:
        return "runner_error"
    text = ""
    if log_path and Path(log_path).is_file():
        text = Path(log_path).read_text(encoding="utf-8", errors="replace")
    if "ERROR (ENL034)" in text or "problem encountered at line" in text:
        return "elaboration_error"
    if "counterexample (cex)" in text or "\ncex\n" in text:
        return "counterexample"
    return "sec_failure"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--server", required=True, choices=("acf3030", "acf3036"))
    parser.add_argument("--config-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    os.environ["SSH_PROFILE"] = args.server
    os.environ["CONFIG_DIR"] = str(args.config_dir.resolve())
    from verification_tools import run_sec_remote

    manifest = json.loads((root / "data" / "manifest.json").read_text())
    by_id = {record["task_id"]: record for record in manifest}
    generation_root = root / "evaluation" / "generated" / args.model
    generation = json.loads((generation_root / "generation_manifest.json").read_text())
    log_root = root / "evaluation" / "logs" / args.model
    log_root.mkdir(parents=True, exist_ok=True)
    results = []
    for candidate in generation["candidates"]:
        record = by_id[candidate["task_id"]]
        try:
            result = run_sec_remote(
                design_name=record["task_id"],
                design_version="v1",
                rtl_golden_path=str(root / record["reference_path"]),
                rtl_revised_path=str(root / candidate["candidate_path"]),
                work_subdir=f"scalebench_{args.model}_{record['index']:03d}",
                timeout=args.timeout,
                download_dir=str(log_root),
                custom_tcl_path=str(root / record["sec_tcl_path"]),
                download_workdir=False,
                stream_output=False,
            )
            success = bool(result["success"])
            error = ""
            log_path = result.get("log_local")
        except Exception as exc:
            success = False
            error = f"{type(exc).__name__}: {exc}"
            log_path = None
        results.append(
            {
                "index": record["index"],
                "legacy_task_id": record["legacy_task_id"],
                "task_id": record["task_id"],
                "model": args.model,
                "sec_result": "pass" if success else ("error" if error else "fail"),
                "failure_kind": classify_failure(log_path, success, error),
                "error": error,
            }
        )
        print(f"{record['task_id']}: {results[-1]['sec_result']}")

    output_root = root / "evaluation" / "results"
    output_root.mkdir(parents=True, exist_ok=True)
    csv_path = output_root / f"{args.model}.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(results)
    passed = sum(row["sec_result"] == "pass" for row in results)
    errors = sum(row["sec_result"] == "error" for row in results)
    failure_kinds = {
        kind: sum(row["failure_kind"] == kind for row in results)
        for kind in sorted({row["failure_kind"] for row in results})
    }
    summary = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "server_profile": args.server,
        "total": len(results),
        "passed": passed,
        "failed": len(results) - passed - errors,
        "errors": errors,
        "pass_rate": passed / len(results),
        "outcome_counts": failure_kinds,
    }
    (output_root / f"{args.model}.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))
    return 0 if errors == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
