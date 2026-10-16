#!/usr/bin/env python3
"""Generate RTL for the audited, evaluation-ready repaired prompts.

The script sends only ``spec.txt`` content to the selected configured model. It
never sends the golden RTL or SEC collateral. Running it requires explicit
authorization for external model calls.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BENCH_ROOT = ROOT.parent / "Comprehensive-RTL-Bench"
sys.path.insert(0, str(BENCH_ROOT))

from Tools import llm_client  # noqa: E402


# GPT-4o uses the OpenAI list price. Claude Sonnet 4.5 uses Anthropic's current
# rate card. Qwen uses its OpenRouter list price. DeepSeek uses the most
# expensive listed provider rate observed during the release audit, not the
# cheaper headline rate, so the preflight ceiling remains conservative under
# provider routing.
PRICING_USD_PER_MILLION = {
    "gpt-4o": (2.50, 10.00),
    "claude-sonnet-4.5": (5.00, 25.00),
    "qwen3.5-397b": (0.39, 2.34),
    "deepseek-v3.2": (3.00, 4.50),
}
OPENROUTER_MODEL_IDS = {
    "claude-sonnet-4.5": "anthropic/claude-sonnet-4.5",
}


def configured_model(alias: str, route: str) -> tuple[dict, dict]:
    resolved = llm_client._resolve_model_from_registry(alias)
    if not resolved:
        raise SystemExit(f"model alias {alias!r} is not in the local registry")
    if route == "openrouter":
        model_id = OPENROUTER_MODEL_IDS.get(alias)
        if not model_id:
            raise SystemExit(f"no audited OpenRouter model ID configured for {alias!r}")
        credential_source = llm_client._resolve_model_from_registry("qwen3.5-397b")
        if not credential_source or credential_source["provider"] != "openrouter":
            raise SystemExit("no configured OpenRouter credential source")
        resolved = {
            **credential_source,
            "model_id": model_id,
        }
    key = llm_client._load_first_key_from_file(resolved["api_keys_file"])
    if not key:
        raise SystemExit(f"no configured API key for {alias!r}")
    config = {
        "provider": resolved["provider"],
        "model": resolved["model_id"],
        "deployment_name": resolved["model_id"],
        "endpoint": (resolved.get("endpoint") or "").rstrip("/"),
        "api_key": key,
        "api_version": "2024-10-21",
    }
    public = {
        "alias": alias,
        "provider": resolved["provider"],
        "model_id": resolved["model_id"],
    }
    return config, public


def extract_verilog(response: str) -> str:
    blocks = re.findall(
        r"```(?:systemverilog|verilog|sv)?\s*\n(.*?)```", response, re.S | re.I
    )
    text = max(blocks, key=len) if blocks else response
    start = re.search(r"(?m)^\s*(?:`timescale[^\n]*\n\s*)?module\b", text)
    if not start:
        raise ValueError("model response contains no Verilog module")
    text = text[start.start():].strip()
    end = list(re.finditer(r"(?m)^\s*endmodule\b", text))
    if not end:
        raise ValueError("model response contains no endmodule")
    return text[: end[-1].end()].strip() + "\n"


def openrouter_total_usage(config: dict) -> float | None:
    if config.get("provider") != "openrouter":
        return None
    base = (config.get("endpoint") or "https://openrouter.ai/api").rstrip("/")
    url = base + "/credits" if base.endswith("/v1") else base + "/v1/credits"
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {config['api_key']}"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
        data = payload.get("data", payload)
        return float(data["total_usage"])
    except Exception:
        return None


def chat_completion_with_usage(
    *,
    messages: list[dict[str, str]],
    config: dict,
    max_tokens: int,
    timeout: int,
    max_attempts: int,
) -> tuple[str, dict, dict]:
    """Call an OpenAI-compatible endpoint and retain token/cost accounting."""
    base = config["endpoint"].rstrip("/")
    provider = config["provider"]
    headers = {"Content-Type": "application/json"}
    if provider == "azure":
        deployment = config["deployment_name"]
        api_version = config["api_version"]
        url = (
            f"{base}/openai/deployments/{deployment}/chat/completions"
            f"?api-version={api_version}"
        )
        headers["api-key"] = config["api_key"]
    else:
        url = (
            base + "/chat/completions"
            if base.endswith("/v1")
            else base + "/v1/chat/completions"
        )
        headers["Authorization"] = f"Bearer {config['api_key']}"
    payload = {
        "model": config["model"],
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.0,
    }
    if provider == "openrouter":
        payload["reasoning"] = {"enabled": False}
    routing = llm_client._build_provider_routing_body(provider)
    if routing:
        payload.update(routing)
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    last_error: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8", errors="replace"))
            if data.get("error"):
                raise RuntimeError(f"{provider} error: {data['error']}")
            message = data["choices"][0]["message"]
            content = message.get("content") or ""
            if isinstance(content, list):
                content = "".join(
                    item.get("text", "") for item in content if isinstance(item, dict)
                )
            diagnostic = {
                "id": data.get("id"),
                "model": data.get("model"),
                "provider": data.get("provider"),
                "usage": data.get("usage") or {},
                "content": content,
                "reasoning": message.get("reasoning"),
            }
            return str(content).strip(), data.get("usage") or {}, diagnostic
        except (OSError, TimeoutError, RuntimeError) as exc:
            last_error = exc
            if attempt < max_attempts:
                time.sleep(2**attempt)
    raise RuntimeError(f"{provider} request failed after retries: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="Configured registry alias")
    parser.add_argument("--max-tokens", type=int, default=16384)
    parser.add_argument("--max-attempts", type=int, default=3)
    parser.add_argument("--budget-usd", type=float, required=True)
    parser.add_argument(
        "--route",
        choices=("registry", "openrouter"),
        default="registry",
        help="Use the registry provider or an audited OpenRouter route",
    )
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest = json.loads((root / "data" / "manifest.json").read_text())
    by_id = {record["task_id"]: record for record in manifest}
    with (root / "review" / "repair_evaluation_cohort.csv").open(newline="") as stream:
        cohort = list(csv.DictReader(stream))
    if len(cohort) != 8:
        raise SystemExit(f"expected 8 evaluation-ready repairs, found {len(cohort)}")

    output_root = root / "evaluation" / "generated" / args.model
    output_root.mkdir(parents=True, exist_ok=True)
    pending_specs = []
    for row in cohort:
        record = by_id[row["task_id"]]
        candidate_path = output_root / record["task_id"] / "candidate.v"
        if args.overwrite or not candidate_path.exists():
            pending_specs.append((root / record["spec_path"]).read_text(encoding="utf-8"))
    if args.model not in PRICING_USD_PER_MILLION:
        raise SystemExit(f"no audited price ceiling configured for {args.model}")
    input_rate, output_rate = PRICING_USD_PER_MILLION[args.model]
    # One token per input character is deliberately conservative for these
    # English prompts. Output is bounded by max_tokens at the API request.
    single_attempt_ceiling = (
        sum(len(spec) + 500 for spec in pending_specs) * input_rate
        + len(pending_specs) * args.max_tokens * output_rate
    ) / 1_000_000
    # A disconnected response may still have been processed and billed. Count
    # every permitted retry as a full request to enforce the budget even when
    # the provider returns no usage record.
    estimated_ceiling = single_attempt_ceiling * args.max_attempts
    if estimated_ceiling > args.budget_usd:
        raise SystemExit(
            f"estimated request ceiling ${estimated_ceiling:.4f} exceeds "
            f"budget ${args.budget_usd:.2f}"
        )
    print(
        f"budget preflight: {len(pending_specs)} calls, conservative ceiling "
        f"${estimated_ceiling:.4f} <= ${args.budget_usd:.2f}"
    )

    config, public_model = configured_model(args.model, args.route)
    usage_before = openrouter_total_usage(config)
    raw_root = root / "evaluation" / "raw_responses" / args.model
    raw_root.mkdir(parents=True, exist_ok=True)
    outcomes = []
    reported_request_cost = 0.0
    for row in cohort:
        request_cost = None
        record = by_id[row["task_id"]]
        case_root = output_root / record["task_id"]
        candidate_path = case_root / "candidate.v"
        if candidate_path.exists() and not args.overwrite:
            print(f"reuse {record['task_id']}")
        else:
            case_root.mkdir(parents=True, exist_ok=True)
            spec = (root / record["spec_path"]).read_text(encoding="utf-8")
            prompt = (
                "Implement the following hardware specification in synthesizable "
                "Verilog. Match the required top-module name and interface exactly. "
                "Return only complete Verilog source code; include any helper modules "
                "that are required.\n\n" + spec
            )
            response, usage, diagnostic = chat_completion_with_usage(
                messages=[
                    {
                        "role": "system",
                        "content": "You are an expert RTL designer. Follow the specification exactly.",
                    },
                    {"role": "user", "content": prompt},
                ],
                config=config,
                max_tokens=args.max_tokens,
                timeout=600,
                max_attempts=args.max_attempts,
            )
            (raw_root / f"{record['task_id']}.json").write_text(
                json.dumps(diagnostic, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            if usage.get("cost") is not None:
                request_cost = float(usage["cost"])
                accounting_method = "provider_reported"
            else:
                prompt_tokens = int(usage.get("prompt_tokens") or 0)
                completion_tokens = int(usage.get("completion_tokens") or 0)
                request_cost = (
                    prompt_tokens * input_rate + completion_tokens * output_rate
                ) / 1_000_000
                accounting_method = "token_count_at_audited_list_price"
            reported_request_cost += request_cost
            if reported_request_cost > args.budget_usd:
                raise SystemExit(
                    f"reported spend ${reported_request_cost:.4f} exceeded "
                    f"budget ${args.budget_usd:.2f}; stopping"
                )
            candidate_path.write_text(extract_verilog(response), encoding="utf-8")
            print(f"generated {record['task_id']}")
        outcomes.append(
            {
                "index": record["index"],
                "task_id": record["task_id"],
                "candidate_path": candidate_path.relative_to(root).as_posix(),
                "candidate_sha256": hashlib.sha256(candidate_path.read_bytes()).hexdigest(),
                "reported_request_cost_usd": request_cost,
                "cost_accounting_method": (
                    accounting_method if request_cost is not None else "reused_candidate"
                ),
            }
        )

    payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "model": public_model,
        "prompt_scope": "specification only; golden RTL was not sent",
        "max_tokens": args.max_tokens,
        "temperature": 0.0,
        "budget_usd": args.budget_usd,
        "max_attempts_per_case": args.max_attempts,
        "single_attempt_request_ceiling_usd": single_attempt_ceiling,
        "conservative_request_ceiling_usd": estimated_ceiling,
        "openrouter_usage_delta_usd": None,
        "reported_successful_request_cost_usd": reported_request_cost,
        "candidates": outcomes,
    }
    usage_after = openrouter_total_usage(config)
    if usage_before is not None and usage_after is not None:
        payload["openrouter_usage_delta_usd"] = max(0.0, usage_after - usage_before)
    (output_root / "generation_manifest.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    print(f"completed {len(outcomes)} candidates for {args.model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
