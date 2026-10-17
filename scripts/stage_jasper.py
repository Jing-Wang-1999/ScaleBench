#!/usr/bin/env python3
"""Stage one ScaleBench candidate for local JasperGold SEC."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_case(task_id: str) -> dict:
    manifest = json.loads((ROOT / "data" / "manifest.json").read_text(encoding="utf-8"))
    for record in manifest:
        if record["task_id"] == task_id:
            return record
    raise SystemExit(f"unknown case: {task_id}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True, help="semantic ScaleBench task ID")
    parser.add_argument("--candidate", type=Path, required=True, help="candidate RTL")
    parser.add_argument("--output", type=Path, required=True, help="fresh staging directory")
    args = parser.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.case):
        parser.error("--case must be a semantic ScaleBench task ID")
    record = load_case(args.case)
    candidate = args.candidate.resolve(strict=True)
    output = args.output.resolve()
    if output.exists():
        parser.error(f"output already exists; use a fresh directory: {output}")

    rtl = output / "input" / "rtl"
    logs = output / "log"
    rtl.mkdir(parents=True)
    logs.mkdir()
    reference = (ROOT / record["reference_path"]).resolve(strict=True)
    source_tcl = (ROOT / record["sec_tcl_path"]).resolve(strict=True)
    golden_name = f"{args.case}.v0.v"
    candidate_name = f"{args.case}.v1.v"
    tcl_name = f"sec_{args.case}.tcl"
    log_name = f"log/sec_{args.case}.v1.log"

    shutil.copy2(reference, rtl / golden_name)
    shutil.copy2(candidate, rtl / candidate_name)
    shutil.copy2(source_tcl, output / tcl_name)
    command = f"jaspergold -sec -batch -tcl {tcl_name} 2>&1 | tee {log_name}"
    run_script = output / "run.sh"
    run_script.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n" + command + "\n",
        encoding="utf-8",
    )
    run_script.chmod(0o755)
    stage = {
        "task_id": args.case,
        "top_module": record["top_module"],
        "reference": f"input/rtl/{golden_name}",
        "candidate": f"input/rtl/{candidate_name}",
        "tcl": tcl_name,
        "command": command,
        "reference_sha256": digest(reference),
        "candidate_sha256": digest(candidate),
        "tcl_sha256": digest(source_tcl),
    }
    (output / "stage.json").write_text(
        json.dumps(stage, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"staged JasperGold SEC workspace: {output}")
    print(f"run: cd {output} && ./run.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
