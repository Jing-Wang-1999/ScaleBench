#!/usr/bin/env python3
"""Rebuild the aggregate API cost ledger from generation manifests."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODELS = ("gpt-4o", "claude-sonnet-4.5", "qwen3.5-397b", "deepseek-v3.2")
INITIAL_QWEN_MAXIMUM_USD = 0.03955029
FAILED_JIEKOU_ATTEMPTS = 4
EACH_FAILED_JIEKOU_ATTEMPT_MAXIMUM_USD = 0.425135
FAILED_JIEKOU_ATTEMPTS_MAXIMUM_USD = (
    FAILED_JIEKOU_ATTEMPTS * EACH_FAILED_JIEKOU_ATTEMPT_MAXIMUM_USD
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--authorized-limit-usd", type=float, default=20.0)
    args = parser.parse_args()
    root = args.root.resolve()

    models = {}
    accounted_total = 0.0
    ceiling_total = INITIAL_QWEN_MAXIMUM_USD + FAILED_JIEKOU_ATTEMPTS_MAXIMUM_USD
    for model in MODELS:
        path = root / "evaluation" / "generated" / model / "generation_manifest.json"
        if not path.is_file():
            models[model] = {"status": "not_run"}
            continue
        generation = json.loads(path.read_text(encoding="utf-8"))
        accounted = float(generation.get("reported_successful_request_cost_usd") or 0.0)
        ceiling = float(generation["conservative_request_ceiling_usd"])
        models[model] = {
            "status": "completed",
            "provider": generation["model"]["provider"],
            "model_id": generation["model"]["model_id"],
            "successful_request_cost_usd": accounted,
            "conservative_request_ceiling_usd": ceiling,
        }
        accounted_total += accounted
        ceiling_total += ceiling

    payload = {
        "authorized_limit_usd": args.authorized_limit_usd,
        "models": models,
        "accounted_successful_request_total_usd": accounted_total,
        "untracked_initial_qwen_attempt_maximum_usd": INITIAL_QWEN_MAXIMUM_USD,
        "failed_jiekou_claude_attempt_count": FAILED_JIEKOU_ATTEMPTS,
        "failed_jiekou_claude_attempts_maximum_usd": FAILED_JIEKOU_ATTEMPTS_MAXIMUM_USD,
        "maximum_total_including_untracked_attempt_usd": (
            accounted_total
            + INITIAL_QWEN_MAXIMUM_USD
            + FAILED_JIEKOU_ATTEMPTS_MAXIMUM_USD
        ),
        "conservative_completed_request_ceiling_including_untracked_attempt_usd": ceiling_total,
        "within_authorized_limit": ceiling_total <= args.authorized_limit_usd,
        "note": (
            "The initial Qwen response contained no Verilog and predated per-response "
            "accounting. Four Claude requests to Jiekou reset without responses; a later "
            "health check returned NOT_ENOUGH_BALANCE, so inference charges are unlikely, "
            "but all four are conservatively bounded as full 16384-token outputs. "
            "OpenRouter entries use reported request costs; other providers use token "
            "counts at the audited public list price. The conservative ceiling assumes "
            "every completed request could have consumed its full configured output limit."
        ),
    }
    output = root / "evaluation" / "results" / "cost_summary.json"
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    if not payload["within_authorized_limit"]:
        raise SystemExit("conservative completed-request ceiling exceeds authorized limit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
