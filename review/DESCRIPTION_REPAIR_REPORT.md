# ScaleBench naming and description repair report

## Outcome

- All 200 public case IDs, directories, top modules, prompts, and SEC scripts now use semantic snake-case names. The old `rtlpp_NNNNN` values remain only as `legacy_task_id` provenance metadata.
- Thirty-three prompts with objective extraction defects were repaired: 17 embedded implementations were removed, 17 mismatched or missing top descriptions/interfaces were restored, and one case had both defects.
- A second, reference-aware audit examined the 20 cases that both complete baseline runs failed and that also had a concrete data-quality issue. Eight are repaired and suitable for fresh evaluation, two are blocked by missing memory images, and ten are quarantined because their golden RTL is stubbed, undriven, multiply driven, or otherwise pathological.
- Structural validation passes with 200 cases and no remaining prompt implementation-body or missing-interface flags.

The complete rename map is in `semantic_names.csv`, every prompt amendment is in `description_fixes.csv`, and the 20-case disposition is in `repair_cohort_status.csv`. `ALL_CASE_AUDIT.md` is the requested 200-row ledger combining historical failure evidence, curation status, and fresh results.

## Baseline evidence

Only two complete, error-free, per-case direct-generation SEC runs were found locally:

| Model | Passed | Total | Pass rate |
| --- | ---: | ---: | ---: |
| GPT-4o | 29 | 200 | 14.5% |
| Claude Sonnet 4.5 | 41 | 200 | 20.5% |

The two models both failed 142 cases. No complete per-case DeepSeek ScaleBench result was found, so a broader “all models failed” intersection cannot be reconstructed from the available artifacts. `all_baseline_models_failed.csv` contains the 142-case intersection; `baseline_direct_results.csv` contains all 200 outcomes.

## Repaired cases selected for fresh evaluation

| Index | New task ID | Repair |
| ---: | --- | --- |
| 29 | `clocked_signed_magnitude_calculator` | Removed an inconsistent embedded implementation; retained exact 21-bit and blocking-assignment behavior. |
| 119 | `dma_tdsp_bus_arbiter` | Removed leaked RTL and corrected reset to asynchronous active-high. |
| 135 | `z80_dual_psg_audio_controller` | Replaced the helper-module interface with the matched full top description and interface. |
| 142 | `configurable_system_timer_50k_a` | Restored its timer description and exact `0xC34F` / 49999 / 0 reset defaults. |
| 143 | `configurable_system_timer_50k_b` | Restored its timer description and exact `0xC34F` / 49999 / 0 reset defaults. |
| 144 | `programmable_alarm_timer_50m` | Replaced an unrelated VGA prompt and specified `0x02FAF07F` / 61567 / 762 defaults. |
| 151 | `configurable_system_timer_50m` | Replaced an unrelated AXI prompt and specified `0x02FAF07F` / 61567 / 762 defaults. |
| 192 | `xr16_processor_core` | Replaced an unrelated AXI prompt/helper interface with the matched simplified processor behavior. |

All eight failed both baseline runs, so their pre-repair pass rate is 0/8 for GPT-4o and 0/8 for Claude Sonnet 4.5.

## Cases not scored after audit

- Missing assets: `ddr2_sequencer_memory_4kx32` and `soc_instruction_memory_16kx32` require HEX images that are absent from the available project trees.
- Golden-reference quarantine: `multimedia_soc_gpio_router`, `nios_jtag_debug_control_stub`, `vga_game_controller_stub`, `csa_multiplier_with_stalled_output`, `multimedia_soc_interface_stub`, `or1k_data_cache_wrapper_stub`, `direct_irq_io_timer_controller`, `axi_master_engine_stub_a`, `axi_master_engine_stub_b`, and `masked_irq_io_timer_controller` contain nondeterministic, empty-helper, multiply-driven, or unreachable reference behavior. Their prompts now document the discovered behavior, but scoring them would measure golden pathologies rather than description quality.

## Fresh-model performance

| Model | Evaluated | SEC passes | Pass rate | Status |
| --- | ---: | ---: | ---: | --- |
| GPT-4o | 8 | 0 | 0.0% | Completed: 8 formal counterexamples. |
| Claude Sonnet 4.5 | — | — | — | Jiekou returned insufficient balance; alternate OpenRouter route awaits approval. |
| Qwen 3.5 397B A17B | 8 | 0 | 0.0% | Completed: 3 elaboration errors and 5 formal counterexamples. |
| DeepSeek V3.2 | 8 | 0 | 0.0% | Completed: 1 elaboration error and 7 formal counterexamples. |

This is single-sample direct generation at temperature 0 with a 16,384-token output limit; OpenRouter reasoning was disabled. No generated RTL was manually corrected. All three completed fresh runs failed all eight repaired cases. GPT-4o produced eight elaboratively valid candidates but each had a JasperGold counterexample. DeepSeek produced seven elaboratively valid candidates and Qwen produced five, but all of those also had counterexamples.

| Task ID | GPT-4o | Claude | Qwen | DeepSeek |
| --- | --- | --- | --- | --- |
| `clocked_signed_magnitude_calculator` | Counterexample | Pending | Elaboration error | Counterexample |
| `dma_tdsp_bus_arbiter` | Counterexample | Pending | Counterexample | Counterexample |
| `z80_dual_psg_audio_controller` | Counterexample | Pending | Elaboration error | Elaboration error |
| `configurable_system_timer_50k_a` | Counterexample | Pending | Counterexample | Counterexample |
| `configurable_system_timer_50k_b` | Counterexample | Pending | Counterexample | Counterexample |
| `programmable_alarm_timer_50m` | Counterexample | Pending | Counterexample | Counterexample |
| `configurable_system_timer_50m` | Counterexample | Pending | Elaboration error | Counterexample |
| `xr16_processor_core` | Counterexample | Pending | Counterexample | Counterexample |

The generation flow transmitted only the eight repaired `spec.txt` files to the configured model endpoints; it did not transmit `reference.v` or `sec.tcl`. Golden and generated RTL were sent only to the configured `acf3036` host for JasperGold SEC. Machine-readable results are in `evaluation/results/combined.csv`.

The completed requests account for $0.18737 at provider-reported costs or token counts at audited public list prices. Four Jiekou Claude attempts returned no response and a later health check reported insufficient balance; charges are unlikely, but bounding all four plus the initial untracked Qwen attempt as full outputs gives $1.92746. A still looser ceiling that also assumes every completed request used its full output allowance is $4.09857, below the authorized $20 limit. See `evaluation/results/cost_summary.json`.

## Remaining release decisions

- Manually review all semantic names and repaired prompts using `case_review.csv`.
- Decide whether to remove the ten quarantined golden-reference cases or retain them with explicit benchmark exclusions.
- Restore or exclude the two missing-memory-image cases.
- Review four references that do not elaborate under Icarus Verilog 10.2: `memory_data_controller`, `control_pad_register`, `inert_skeleton_stub_b`, and `adpcm_codec`. These are recorded as toolchain-review flags rather than automatic exclusions because the study's JasperGold parser may accept constructs that Icarus rejects.
- Complete the license and citation review before publication.
