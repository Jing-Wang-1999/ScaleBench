# Repaired-description evaluation

Fresh generation is limited to the eight cases marked
`repaired_evaluation_ready` in `review/repair_evaluation_cohort.csv`. Cases
blocked by absent memory images or quarantined for pathological golden RTL are
not scored.

`scripts/eval_generate.py` sends only the selected `spec.txt` files to a
configured model; it does not send `reference.v` or `sec.tcl`. Generated RTL is
written under `evaluation/generated/<model>/`. `scripts/eval_verify.py` then
checks each candidate against its local reference using the included SEC TCL.

The completed single-sample runs used temperature 0 and a 16,384-token output
limit; OpenRouter reasoning was disabled. GPT-4o passed 0/8 cases (eight formal
counterexamples), Qwen 3.5 397B A17B passed 0/8 (three elaboration errors and
five formal counterexamples), and DeepSeek V3.2 passed 0/8 (one elaboration
error and seven counterexamples). The configured Jiekou account returned
`NOT_ENOUGH_BALANCE` for the fresh Claude Sonnet 4.5 run; an alternate route
through the already-funded OpenRouter account awaits explicit approval. See
`results/combined.csv` for per-case outcomes and `results/cost_summary.json`
for the API cost audit.

External model generation must not be run without authorization for the named
provider, models, and prompt payload. API keys and raw provider responses are
never tracked in this repository.
