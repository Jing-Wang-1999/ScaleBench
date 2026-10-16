#!/usr/bin/env python3
"""Apply the reviewed semantic naming and specification repairs to ScaleBench.

This is a one-time migration from the internal ``rtlpp_NNNNN`` extraction.  It
keeps the legacy identifier in the manifest for traceability while making the
public task ID, directory, top module, prompt, and SEC metadata semantic.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path


SEMANTIC_IDS = """
synchronous_instruction_rom
write_once_register
clocked_hamming_encoder
two_bit_hpi_address_register
lcd_output_register
ddr2_sequencer_ram
parallel_serial_shift_register
led_pio_register
lcd_reset_output_register
parallel_io_register
ble_packet_memory
single_to_multi_axi_interconnect
ddr2_sequencer_memory_4kx32
memory_data_register_controller
signed_vector_max_relu
loadable_eight_bit_counter
two_state_mealy_fsm
input_sequence_detector_fsm
soc_instruction_memory_16kx32
ultrasonic_pulse_counter_fsm
crc32_byte_stream
complex_coefficient_multiplier
hpi_data_port_register
axi_slave_bus_functional_model
cordic_rotation_initializer
crc32_enabled_byte_update
crc32_stream_accumulator
single_port_sram_2048x128
scan_chain_signal_wrapper
clocked_signed_magnitude_calculator
scan_chain_data_wrapper
inert_axi_interface_stub
three_channel_countdown_timer
processor_memory_debug_bridge
clocked_output_pattern_counter
serial_crc32_generator
microblaze_processor_interface
axi_lite_nine_master_bridge
parallel_serial_crc32_engine
amplitude_demodulator
four_bit_pattern_sequence_generator
processor_memory_control_unit
fir_stream_passthrough
ultrasonic_sensor_controller
simplified_fft_stream
axi_crossbar_transaction_router
axi_protocol_converter_4
axi_bus_functional_master
programmable_timebase_generator
axi_protocol_converter_1
signed_logarithmic_multiplier
dma_axi_channel_arbiter
multiport_axi_crossbar
six_bank_rom_selector
lcd_command_controller
empty_multiport_axi_stub
parallel_crc32_d8
lcd_command_sequencer
pcie_axi_dma_bridge
dual_slave_axi_interconnect
cpu_execution_core
byte_parallel_crc32
i2c_command_sender
one_to_two_axi_crossbar
crc32_polynomial_update
axi_data_width_converter
pulse_per_second_receiver
netbios_name_encoder
rgb_to_ycbcr_converter
cpu_debug_slave_bridge
one_to_two_axi_crossbar_lite
empty_three_port_axi_stub
cordic_rotator
camera_register_initializer
multiport_axi_crossbar_switch
pipelined_log2
timing_adapter_fifo
memory_data_controller
bidirectional_axi_bridge
streaming_to_memory_mapped_adapter
binary_to_bcd_converter_a
cortex_m0_processor
three_sensor_interface
decimation_sinc_filter_a
instruction_mmu_tlb
one_to_many_axi_crossbar
radar_timing_controller
vga_sync_generator
pushbutton_debouncer_a
three_slave_axi_interconnect
streaming_to_mm_adapter_b
bcd_time_converter
nios_debug_slave_bridge_a
streaming_to_mm_adapter_c
microblaze_system_wrapper
nios_debug_slave_bridge_b
triple_speed_ethernet_mac
binary_to_bcd_converter_b
uart_axi_address_mapper
key_input_pio_register
inert_skeleton_stub_a
nios_debug_slave_bridge_c
nios_debug_slave_bridge_d
control_pad_register
ps2_wishbone_controller
nios_debug_slave_bridge_e
nios_jtag_debug_bridge_a
dip_switch_pio_a
pci_bus_controller
dip_switch_pio_b
inert_skeleton_stub_b
datapath_register_bank
trigger_timer
ddr3_jtag_debug_bridge
automatic_gain_controller
virtual_world_interface
nios_debug_slave_bridge_f
watchdog_timer
multimedia_soc_gpio_router
dma_tdsp_bus_arbiter
axi_ad9361_interface
decimation_sinc_filter_b
pushbutton_debouncer_b
fpu_division_prenormalizer
axi_lite_six_master_stub
adpcm_codec
avalon_memory_mapped_master
hardware_random_number_generator
axi_protocol_converter_5
nios_jtag_debug_bridge_b
ethernet_receive_synchronizer_a
response_waitrequest_adapter_a
axi_protocol_converter_2
empty_dma_channel_stub
instruction_decoder
z80_dual_psg_audio_controller
uart_transceiver_a
response_waitrequest_adapter_b
axi_protocol_converter_3
fft_processing_chain
dma_instruction_sequencer
uart_transceiver_b
configurable_system_timer_50k_a
configurable_system_timer_50k_b
programmable_alarm_timer_50m
nios_jtag_debug_control_stub
vga_game_controller_stub
uart_transceiver_c
interval_timer
soc_configurable_timer
uart_transceiver_d
configurable_system_timer_50m
hardware_instantiation_wrapper
high_resolution_timer
multi_slave_axi_crossbar
configurable_interrupt_timer
synchronized_adjustable_clock_timer
ethernet_receive_synchronizer_b
fpu_division_postnormalizer
uart_transceiver_e
processor_execution_stage
fft256_processor
fpga_pong_game
sdram_control_interface_a
sdram_control_interface_b
burst_transaction_bridge
axi_slave_master_bridge_a
eight_beat_burst_reader
configurable_system_timer_d
four_slave_axi_interconnect
or1k_data_cache_controller_a
csa_multiplier_with_stalled_output
mt19937_axi_stream_rng
axi_crossbar_switch
rv32i_execution_alu
multimedia_soc_interface_stub
mipi_dphy_transmitter
processor_axi_interface_wrapper
signed_polynomial_datapath
zero_length_encoding_fsm
single_precision_fpu_addsub
axi_slave_master_bridge_b
or1k_data_cache_wrapper_stub
mipi_axi_receiver
axi_register_slice
axi_stream_cobs_decoder
io_timer_interrupt_controller_a
fpu_addsub_postnormalizer
processor_axi_debug_controller
direct_irq_io_timer_controller
ibex_load_store_unit_a
ibex_load_store_unit_b
xr16_processor_core
axi_master_engine_stub_a
axi_master_engine_stub_b
axi_lite_protocol_bridge
io_timer_interrupt_controller_c
ethernet_ip_packet_processor
masked_irq_io_timer_controller
io_timer_interrupt_controller_e
""".strip().splitlines()


MISSING_INTERFACE_INDICES = {
    90, 91, 93, 118, 135, 142, 143, 144, 145, 146, 151, 171,
    175, 182, 192, 193, 194,
}
CODE_LEAK_INDICES = {
    1, 29, 32, 68, 81, 95, 96, 98, 99, 115, 119, 133, 155, 178,
    189, 194, 198,
}
ASSET_BLOCKED_INDICES = {12, 18}
GOLDEN_QUARANTINE_INDICES = {
    118, 145, 146, 171, 175, 182, 189, 193, 194, 198,
}
EVALUATION_READY_REPAIR_INDICES = {29, 119, 135, 142, 143, 144, 151, 192}
TOOLCHAIN_REVIEW_INDICES = {77, 103, 110, 125}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def module_names(text: str) -> list[str]:
    return re.findall(r"(?m)^\s*module\s+([A-Za-z_$][\w$]*)", text)


def replace_identifier(text: str, old: str, new: str) -> str:
    return re.sub(rf"(?<![\w$]){re.escape(old)}(?![\w$])", new, text)


def replace_top_name_in_prompt(text: str, old: str, new: str) -> str:
    """Rename a described top without touching ports that share its old name."""
    text = text.replace(f"`{old}`", f"`{new}`")
    patterns = (
        rf"(?i)(\bmodule\s+(?:named\s+)?)({re.escape(old)})(?![\w$])",
        rf"(?i)(\btop(?:-level)?\s+module\s+(?:is\s+)?)({re.escape(old)})(?![\w$])",
    )
    for pattern in patterns:
        text = re.sub(pattern, rf"\g<1>{new}", text)
    return text


def strip_implementation_blocks(text: str) -> str:
    pattern = re.compile(r"```(?:verilog|systemverilog)?\s*\n(.*?)```", re.S | re.I)

    def replacement(match: re.Match[str]) -> str:
        return "" if re.search(r"(?m)^\s*endmodule\b", match.group(1)) else match.group(0)

    text = pattern.sub(replacement, text)
    text = re.sub(
        r"(?mi)^#{1,6}\s*(?:final\s+)?verilog\s+module(?:\s*\([^\n]*\))?:?\s*$\n?",
        "",
        text,
    )
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def module_header(reference: str, top: str) -> str:
    start_match = re.search(rf"(?m)^\s*module\s+{re.escape(top)}\b", reference)
    if not start_match:
        raise ValueError(f"reference lacks top module {top}")
    end = reference.find(");", start_match.start())
    if end < 0:
        raise ValueError(f"cannot find end of module header for {top}")
    return reference[start_match.start(): end + 2].strip()


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--upstream-jsonl",
        type=Path,
        required=True,
        help="Path to the original RTLPP.jsonl used to restore mismatched prompts",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="ScaleBench repository root",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = root / "data" / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    upstream = [
        json.loads(line)
        for line in args.upstream_jsonl.read_text(encoding="utf-8").splitlines()
    ]

    if len(manifest) != 200 or len(SEMANTIC_IDS) != 200:
        raise SystemExit("manifest and semantic-name table must both contain 200 rows")
    if len(set(SEMANTIC_IDS)) != 200:
        raise SystemExit("semantic task IDs are not unique")
    if any(not re.fullmatch(r"[a-z][a-z0-9_]*", name) for name in SEMANTIC_IDS):
        raise SystemExit("semantic task IDs must be lowercase Verilog identifiers")
    if not all(re.fullmatch(r"rtlpp_\d{5}", row["task_id"]) for row in manifest):
        raise SystemExit("this migration only accepts an uncurated rtlpp_NNNNN manifest")
    legacy_to_semantic = {
        record["task_id"]: semantic_id
        for record, semantic_id in zip(manifest, SEMANTIC_IDS)
    }
    source_case_to_semantic = {
        record["source_case"]: semantic_id
        for record, semantic_id in zip(manifest, SEMANTIC_IDS)
    }

    semantic_rows: list[dict[str, object]] = []
    fix_rows: list[dict[str, object]] = []
    staged: list[tuple[Path, Path, dict[str, object], str, str, str]] = []

    for record, semantic_id in zip(manifest, SEMANTIC_IDS):
        index = record["index"]
        legacy_id = record["task_id"]
        old_case_dir = root / "data" / "cases" / legacy_id
        new_case_dir = root / "data" / "cases" / semantic_id
        if new_case_dir.exists():
            raise SystemExit(f"target case directory already exists: {new_case_dir}")

        spec = (old_case_dir / "spec.txt").read_text(encoding="utf-8")
        reference = (old_case_dir / "reference.v").read_text(encoding="utf-8")
        sec_tcl = (old_case_dir / "sec.tcl").read_text(encoding="utf-8")
        upstream_row = upstream[int(legacy_id.removeprefix("rtlpp_"))]
        upstream_modules = module_names(upstream_row["code"])
        reference_modules = module_names(reference)
        original_tops = []
        for name in upstream_modules:
            if name not in reference_modules and name not in original_tops:
                original_tops.append(name)
        if len(original_tops) != 1:
            raise SystemExit(
                f"cannot uniquely recover original top for {legacy_id}: {original_tops}"
            )
        original_top = original_tops[0]

        replacement_count = len(
            re.findall(rf"(?m)^(\s*module\s+){re.escape(legacy_id)}\b", reference)
        )
        if replacement_count != 1:
            raise SystemExit(
                f"expected one top declaration for {legacy_id}, found {replacement_count}"
            )
        reference = re.sub(
            rf"(?m)^(\s*module\s+){re.escape(legacy_id)}\b",
            rf"\g<1>{semantic_id}",
            reference,
            count=1,
        )
        sec_tcl = replace_identifier(sec_tcl, legacy_id, semantic_id)

        fixes: list[str] = []
        if index in MISSING_INTERFACE_INDICES:
            spec = upstream_row["instruction"].strip() + "\n"
            fixes.append("restored_matched_upstream_description")
        if index in CODE_LEAK_INDICES:
            spec = strip_implementation_blocks(spec)
            fixes.append("removed_embedded_implementation")

        spec = replace_top_name_in_prompt(spec, original_top, semantic_id)
        spec = replace_identifier(spec, legacy_id, semantic_id)
        for internal_id, public_id in legacy_to_semantic.items():
            spec = replace_identifier(spec, internal_id, public_id)
        for source_case, public_id in source_case_to_semantic.items():
            spec = replace_identifier(spec, source_case, public_id)
        if index in MISSING_INTERFACE_INDICES:
            spec = (
                spec.rstrip()
                + "\n\nModule Interface:\n"
                + module_header(reference, semantic_id)
                + "\n"
            )
            fixes.append("appended_exact_top_interface")
        if not re.search(rf"(?m)^\s*module\s+{re.escape(semantic_id)}\b", spec):
            raise SystemExit(f"curated prompt lacks interface for {semantic_id}")
        if re.search(r"(?m)^\s*endmodule\b", spec):
            raise SystemExit(f"curated prompt still contains implementation for {semantic_id}")

        staged.append((old_case_dir, new_case_dir, record, spec, reference, sec_tcl))
        semantic_rows.append(
            {
                "index": index,
                "legacy_task_id": legacy_id,
                "task_id": semantic_id,
                "original_top_module": original_top,
            }
        )
        for defect, repair in (
            (
                "mismatched_or_missing_top_description",
                "restored matched upstream instruction and appended exact interface",
            ),
            (
                "embedded_reference_implementation",
                "removed fenced implementation while retaining requirements and interface",
            ),
        ):
            applies = (
                index in MISSING_INTERFACE_INDICES
                if defect.startswith("mismatched")
                else index in CODE_LEAK_INDICES
            )
            if applies:
                fix_rows.append(
                    {
                        "index": index,
                        "legacy_task_id": legacy_id,
                        "task_id": semantic_id,
                        "defect": defect,
                        "repair": repair,
                    }
                )
        record["legacy_task_id"] = legacy_id
        record["original_top_module"] = original_top
        record["task_id"] = semantic_id
        record["top_module"] = semantic_id
        record["description_fixes"] = fixes
        record["review_flags"] = [
            flag
            for flag in record["review_flags"]
            if flag == "reference_requires_external_memory_file"
        ]
        if index in GOLDEN_QUARANTINE_INDICES:
            record["review_flags"].append("golden_requires_quarantine_review")
            record["curation_status"] = "quarantined_golden_pathology"
        elif index in ASSET_BLOCKED_INDICES:
            record["curation_status"] = "blocked_missing_memory_image"
        elif index in EVALUATION_READY_REPAIR_INDICES:
            record["curation_status"] = "repaired_evaluation_ready"
        elif fixes:
            record["curation_status"] = "repaired_review_ready"
        else:
            record["curation_status"] = "review_ready"
        if index in TOOLCHAIN_REVIEW_INDICES:
            record["review_flags"].append("reference_requires_toolchain_review")

    for old_case_dir, new_case_dir, record, spec, reference, sec_tcl in staged:
        old_case_dir.rename(new_case_dir)
        spec_path = new_case_dir / "spec.txt"
        reference_path = new_case_dir / "reference.v"
        tcl_path = new_case_dir / "sec.tcl"
        spec_path.write_text(spec, encoding="utf-8")
        reference_path.write_text(reference, encoding="utf-8")
        tcl_path.write_text(sec_tcl, encoding="utf-8")
        record["spec_path"] = spec_path.relative_to(root).as_posix()
        record["reference_path"] = reference_path.relative_to(root).as_posix()
        record["sec_tcl_path"] = tcl_path.relative_to(root).as_posix()
        record["spec_sha256"] = sha256(spec_path)
        record["reference_sha256"] = sha256(reference_path)
        record["sec_tcl_sha256"] = sha256(tcl_path)

    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    manifest_fields = [
        "index", "source_case", "legacy_task_id", "task_id", "top_module",
        "original_top_module", "loc", "is_sequential", "spec_path",
        "reference_path", "sec_tcl_path", "description_fixes", "curation_status",
        "review_flags",
    ]
    manifest_rows = []
    for record in manifest:
        row = {field: record[field] for field in manifest_fields}
        row["description_fixes"] = ";".join(record["description_fixes"])
        row["review_flags"] = ";".join(record["review_flags"])
        manifest_rows.append(row)
    write_csv(root / "data" / "manifest.csv", manifest_fields, manifest_rows)
    write_csv(
        root / "review" / "semantic_names.csv",
        ["index", "legacy_task_id", "task_id", "original_top_module"],
        semantic_rows,
    )
    write_csv(
        root / "review" / "description_fixes.csv",
        ["index", "legacy_task_id", "task_id", "defect", "repair"],
        fix_rows,
    )

    review_fields = [
        "index", "legacy_task_id", "task_id", "loc", "is_sequential",
        "description_fixes", "curation_status", "review_flags", "reviewed", "spec_ok",
        "reference_ok", "notes",
    ]
    review_rows = []
    for record in manifest:
        review_rows.append(
            {
                "index": record["index"],
                "legacy_task_id": record["legacy_task_id"],
                "task_id": record["task_id"],
                "loc": record["loc"],
                "is_sequential": record["is_sequential"],
                "description_fixes": ";".join(record["description_fixes"]),
                "curation_status": record["curation_status"],
                "review_flags": ";".join(record["review_flags"]),
                "reviewed": "",
                "spec_ok": "",
                "reference_ok": "",
                "notes": "",
            }
        )
    write_csv(root / "review" / "case_review.csv", review_fields, review_rows)

    flagged_rows = []
    for record in manifest:
        for flag in record["review_flags"]:
            flagged_rows.append(
                {
                    "index": record["index"],
                    "legacy_task_id": record["legacy_task_id"],
                    "task_id": record["task_id"],
                    "loc": record["loc"],
                    "flag": flag,
                    "path": record["reference_path"],
                }
            )
    write_csv(
        root / "review" / "flagged_cases.csv",
        ["index", "legacy_task_id", "task_id", "loc", "flag", "path"],
        flagged_rows,
    )

    print(f"renamed {len(manifest)} cases with semantic task IDs")
    print(f"recorded {len(fix_rows)} description repairs across {len(set(r['index'] for r in fix_rows))} cases")
    print(f"retained {len(flagged_rows)} unresolved external-memory flags")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
