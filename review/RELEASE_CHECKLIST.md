# Manual release checklist

## Required before publication

- [ ] Review all 200 `spec.txt` and `reference.v` pairs, recording progress in `case_review.csv`.
- [ ] Review every entry in `flagged_cases.csv`.
- [x] Remove embedded implementations and restore mismatched top descriptions/interfaces.
- [x] Replace public `rtlpp_XXXXX` names with semantic case and top-module names.
- [ ] Supply or exclude the two references to absent external memory initialization files.
- [ ] Remove or explicitly exclude the ten cases marked `golden_requires_quarantine_review`.
- [ ] Resolve the four cases marked `reference_requires_toolchain_review` with the release verifier.
- [ ] Finish the fresh Claude Sonnet 4.5 run: Jiekou lacks sufficient balance, and the alternate OpenRouter route needs explicit approval; GPT-4o, Qwen, and DeepSeek are complete.
- [ ] Reconcile manuscript statistics with the extracted data: the release has LoC 30–348 and mean 127.935. One manuscript passage says 30–500 and the benchmark table reports average 120.
- [ ] Complete `LICENSE_REVIEW.md` and add the approved repository license and third-party notices.
- [ ] Add final author names, paper title/venue, DOI or arXiv identifier, and `CITATION.cff`.
- [ ] Confirm whether the name `ScaleBench` and the 200 semantic task IDs are final.
- [ ] Run `python3 scripts/validate.py` after every edit.
- [ ] Inspect `git diff --stat`, `git diff`, and the final GitHub rendering before the first commit.

## Extraction decisions

- The experiment files formerly named `spec_fixed.txt` were the starting point; confirmed leakage and mismatches are repaired and tracked in `description_fixes.csv`.
- Canonical references are the experiment files formerly named `golden_rtl.v`.
- Internal case numbers and `rtlpp_XXXXX` IDs are retained only as provenance metadata; public directories and top modules use semantic task IDs.
- JasperGold TCL files are included as verification metadata.
- Absolute workstation paths were removed from the public manifest.
- Raw model responses, RAG context/databases, result logs, plots, and paper build products are excluded. Generated candidates, compact pass/fail ledgers, and the repair audit are retained for reproducibility.
