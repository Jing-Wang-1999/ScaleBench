# ScaleBench

ScaleBench is a specification-to-RTL benchmark containing 200 Verilog designs. It was assembled for the CorrectRTL study from the RTL-PP corpus and selected to cover a broad range of design sizes.

This repository is a review-ready, curated release of the benchmark. Public cases use semantic names, malformed prompts have been repaired, and compact historical evaluation outcomes are retained for audit. Generated RTL, raw model responses, RAG databases, plots, logs, and paper build products are intentionally excluded.

## Dataset summary

| Property | Value |
| --- | ---: |
| Designs | 200 |
| Sequential | 152 |
| Combinational | 48 |
| Minimum reference LoC | 30 |
| Maximum reference LoC | 348 |
| Mean reference LoC | 127.935 |

## Layout

```text
data/
  manifest.json
  manifest.csv
  cases/
    synchronous_instruction_rom/
      spec.txt
      reference.v
      sec.tcl
    ...
review/
  RELEASE_CHECKLIST.md
  DESCRIPTION_REPAIR_REPORT.md
  ALL_CASE_AUDIT.md
  all_case_audit.csv
  case_review.csv
  semantic_names.csv
  description_fixes.csv
  flagged_cases.csv
evaluation/
  README.md
scripts/
  extract_release.py
  apply_curations.py
  import_baseline_results.py
  eval_generate.py
  eval_verify.py
  validate.py
```

Each case contains:

- `spec.txt`: the curated natural-language prompt. Confirmed implementation leakage and mismatched descriptions/interfaces have been repaired.
- `reference.v`: the golden Verilog implementation.
- `sec.tcl`: the JasperGold sequential-equivalence script retained as verification metadata. It expects the original `input/rtl/<task>.v0.v` and `<task>.v1.v` staging convention and requires Cadence JasperGold.

`data/manifest.json` is the canonical machine-readable index. It uses repository-relative paths and includes SHA-256 digests. Public `task_id` values are semantic Verilog identifiers; internal `rtlpp_NNNNN` values are retained only as `legacy_task_id` provenance metadata. `data/manifest.csv` is a compact review view.

Use `review/case_review.csv` as the editable manual-review ledger. Its blank status columns are intentionally separate from the canonical manifest and can be filled in one case at a time.

## Validation

Only Python 3 and its standard library are needed to validate the release structure:

```bash
python3 scripts/validate.py
```

The validator checks case count and uniqueness, semantic task IDs, relative paths, file hashes, top-module names, review flags, accidental local paths, and oversized files. The curated tree has no remaining prompt implementation-body or missing-interface flags. `review/flagged_cases.csv` retains two missing-memory-image cases, ten golden-reference cases that require quarantine review, and four additional references that need toolchain compatibility review after an Icarus elaboration smoke test.

## Benchmark viewer

The dependency-free viewer in `viewer/` lets reviewers browse all 200 cases by semantic task name, filter by design type and curation status, inspect `spec.txt`, `reference.v`, and `sec.tcl`, and mark cases reviewed in browser-local storage. Legacy RTLPP identifiers are deliberately excluded from the public interface.

Build and preview it locally:

```bash
python3 scripts/build_viewer.py --output _site
python3 -m http.server 8000 --directory _site
```

Then open `http://127.0.0.1:8000/`. The GitHub Pages workflow publishes the same build at `https://jing-wang-1999.github.io/ScaleBench/` when the repository is public and Pages is configured to use GitHub Actions.

## Curation audit

All 200 cases were renamed according to their described function. Thirty-three prompts with confirmed structural defects were repaired. A reference-aware audit then examined the 20 cases that both complete baseline model runs failed and that also had a concrete data issue: eight are suitable for fresh evaluation, two are blocked by missing memory images, and ten are quarantined for pathological golden RTL.

See [`review/ALL_CASE_AUDIT.md`](review/ALL_CASE_AUDIT.md) for the complete 200-case table and [`review/DESCRIPTION_REPAIR_REPORT.md`](review/DESCRIPTION_REPAIR_REPORT.md) for detailed repair rationale.

## Evaluation

Generate a candidate Verilog implementation from `spec.txt`, with the exact module name and interface stated there, and compare it against `reference.v` using formal equivalence. The included TCL files document the study flow, but the commercial verifier itself is not distributed.

The compact baseline ledgers report GPT-4o at 29/200 (14.5%) and Claude Sonnet 4.5 at 41/200 (20.5%), with 142 cases failed by both. Fresh single-sample evaluation on the eight `repaired_evaluation_ready` cases produced 0/8 SEC passes for GPT-4o, Qwen 3.5 397B A17B, and DeepSeek V3.2. The configured Jiekou account lacked sufficient balance for the fresh Claude run; using the funded OpenRouter account as an alternate route requires separate approval. See [`evaluation/README.md`](evaluation/README.md) and the repair report for the per-case breakdown.

## Provenance and licensing

See [UPSTREAM.md](UPSTREAM.md) for dataset provenance. A repository-level license has deliberately not been selected during extraction; [LICENSE_REVIEW.md](LICENSE_REVIEW.md) records the decision that must be completed before public release.

## Release status

This tree is staged for manual review. Review every row in `review/case_review.csv` and `review/flagged_cases.csv`, resolve the quarantine/missing-asset decisions, and complete the licensing and citation items in `review/RELEASE_CHECKLIST.md` before making the repository public.
