#!/usr/bin/env python3
"""Run the open-source ScaleBench equivalence checks with Yosys.

The verifier returns one of three verdicts:

* ``equivalent``: the selected contract completed a proof;
* ``non_equivalent``: a concrete counterexample was produced; or
* ``hold``: the frontend, contract, resource limit, or induction did not
  support a reliable verdict.

Exit codes are 0, 1, and 2 respectively.  A hold is never counted as a model
failure.  JasperGold SEC remains the authoritative fallback for holds and for
any disagreement with this open-source route.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SUPPORTED_STATE = {
    "$dff",
    "$dffe",
    "$sdff",
    "$sdffe",
    "$sdffce",
}
MAX_STATE_BITS = 4096


@dataclass(frozen=True)
class Case:
    task_id: str
    top: str
    sequential: bool
    reference: Path
    sec_tcl: Path


class VerificationHold(RuntimeError):
    """An unsupported or inconclusive proof condition."""


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def quote_yosys_path(path: Path) -> str:
    text = str(path)
    if any(character in text for character in ("\n", "\r", "\x00")):
        raise VerificationHold("source path contains an unsafe character")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def checked_identifier(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", value):
        raise VerificationHold(f"unsupported Verilog identifier: {value!r}")
    return value


def run_yosys(
    executable: str,
    script_name: str,
    work: Path,
    timeout: int,
) -> tuple[int, str]:
    command = [executable, "-Q", "-s", script_name]
    try:
        completed = subprocess.run(
            command,
            cwd=work,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        log = completed.stdout + completed.stderr
        returncode = completed.returncode
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        log = stdout + stderr
        returncode = 124
    (work / f"{Path(script_name).stem}.log").write_text(log, encoding="utf-8")
    return returncode, log


def load_cases() -> dict[str, Case]:
    records = json.loads((ROOT / "data" / "manifest.json").read_text(encoding="utf-8"))
    cases = {}
    for record in records:
        task_id = record["task_id"]
        cases[task_id] = Case(
            task_id=task_id,
            top=record["top_module"],
            sequential=bool(record["is_sequential"]),
            reference=(ROOT / record["reference_path"]).resolve(strict=True),
            sec_tcl=(ROOT / record["sec_tcl_path"]).resolve(strict=True),
        )
    return cases


def parse_sec_contract(case: Case) -> tuple[str, str | None]:
    text = case.sec_tcl.read_text(encoding="utf-8")
    clock_match = re.search(r"(?m)^clock\s+(\S+)\s*$", text)
    reset_match = re.search(r"(?m)^reset\s+(\S+)\s*$", text)
    if not clock_match or not reset_match:
        raise VerificationHold("SEC script does not declare exactly one clock/reset contract")
    clock = checked_identifier(clock_match.group(1))
    reset = reset_match.group(1)
    if reset == "-none":
        return clock, None
    return clock, checked_identifier(reset)


def infer_reset_active(case: Case, reset: str) -> int:
    reference = case.reference.read_text(encoding="utf-8", errors="replace")
    specification = (case.reference.parent / "spec.txt").read_text(
        encoding="utf-8", errors="replace"
    )
    reset_pattern = re.escape(reset)
    low_evidence = bool(
        re.search(r"active[ -]?low", specification, flags=re.IGNORECASE)
        or re.search(rf"\bif\s*\(\s*[!~]\s*{reset_pattern}\b", reference)
        or re.search(rf"\b{reset_pattern}\s*==\s*1\s*'\s*b0", reference)
        or re.search(r"(?:_n|resetn|rstn)$", reset, flags=re.IGNORECASE)
    )
    high_evidence = bool(
        re.search(r"active[ -]?high", specification, flags=re.IGNORECASE)
        or re.search(rf"\bif\s*\(\s*{reset_pattern}\s*\)", reference)
        or re.search(rf"\b{reset_pattern}\s*==\s*1\s*'\s*b1", reference)
    )
    if low_evidence and high_evidence:
        raise VerificationHold(f"conflicting reset-polarity evidence for {reset}")
    if low_evidence:
        return 0
    if high_evidence:
        return 1
    raise VerificationHold(f"cannot infer the active level of reset {reset}")


def module_interface(module: dict) -> dict[str, tuple[str, int, int, int]]:
    return {
        name: (
            port["direction"],
            len(port["bits"]),
            port.get("offset", 0),
            port.get("upto", 0),
        )
        for name, port in module["ports"].items()
    }


def binary_parameter(cell: dict, name: str) -> int:
    value = cell.get("parameters", {}).get(name)
    if not isinstance(value, str) or not re.fullmatch(r"[01]+", value):
        raise VerificationHold(f"cannot read {cell['type']} {name} parameter")
    return int(value, 2)


def preflight_state_size(
    case: Case,
    source: Path,
    side: str,
    work: Path,
    yosys: str,
    timeout: int,
) -> int:
    script_name = f"preflight_{side}.ys"
    commands = [
        f"read_verilog -sv {quote_yosys_path(source)}",
        f"hierarchy -check -top {case.top}",
        "proc; opt; memory -nomap; flatten; opt_clean",
        f"write_json preflight_{side}.json",
    ]
    (work / script_name).write_text("\n".join(commands) + "\n", encoding="utf-8")
    code, _ = run_yosys(yosys, script_name, work, timeout)
    if code != 0:
        raise VerificationHold(f"Yosys {side} preflight failed; see preflight_{side}.log")
    document = json.loads((work / f"preflight_{side}.json").read_text(encoding="utf-8"))
    module = document["modules"][case.top]
    state_bits = 0
    for cell in module["cells"].values():
        kind = cell["type"]
        if kind.startswith("$mem"):
            state_bits += binary_parameter(cell, "WIDTH") * binary_parameter(cell, "SIZE")
        elif any(token in kind.lower() for token in ("ff", "latch")):
            state_bits += len(cell.get("connections", {}).get("Q", ()))
    if state_bits > MAX_STATE_BITS:
        raise VerificationHold(
            f"state size {state_bits} exceeds the {MAX_STATE_BITS}-bit open-source limit"
        )
    return state_bits


def lower_sources(
    case: Case,
    candidate: Path,
    work: Path,
    yosys: str,
    timeout: int,
) -> tuple[dict, dict]:
    for source, side in ((case.reference, "golden"), (candidate, "candidate")):
        commands = [
            f"read_verilog -sv {quote_yosys_path(source)}",
            f"hierarchy -check -top {case.top}",
            "proc -noopt; flatten; opt_expr -keepdc; opt_clean",
            "memory_collect; memory_map; async2sync; opt_expr -keepdc; opt_clean",
            "check -assert",
            f"write_json {side}.json",
        ]
        script_name = f"lower_{side}.ys"
        (work / script_name).write_text("\n".join(commands) + "\n", encoding="utf-8")
        code, _ = run_yosys(yosys, script_name, work, timeout)
        if code != 0:
            raise VerificationHold(
                f"Yosys {side} frontend/elaboration failed; see lower_{side}.log"
            )
    modules = []
    for side in ("golden", "candidate"):
        document = json.loads((work / f"{side}.json").read_text(encoding="utf-8"))
        try:
            modules.append(document["modules"][case.top])
        except KeyError as error:
            raise VerificationHold(f"lowered {side} design lacks top {case.top}") from error
    if module_interface(modules[0]) != module_interface(modules[1]):
        raise VerificationHold("reference and candidate interfaces differ")
    return modules[0], modules[1]


def has_state(module: dict) -> bool:
    return any(
        any(token in cell["type"].lower() for token in ("ff", "latch", "mem"))
        for cell in module["cells"].values()
    )


def prove_combinational(
    case: Case,
    candidate: Path,
    work: Path,
    yosys: str,
    timeout: int,
) -> dict:
    golden, revised = lower_sources(case, candidate, work, yosys, timeout)
    if has_state(golden) or has_state(revised):
        raise VerificationHold("combinational contract found retained state")
    if any(
        port["direction"] not in ("input", "output")
        for port in golden["ports"].values()
    ):
        raise VerificationHold("bidirectional ports require a separate contract")

    models = {}
    for name, module in (("source_golden", golden), ("source_candidate", revised)):
        model = copy.deepcopy(module)
        model.get("attributes", {}).pop("top", None)
        models[name] = model
    write_json(work / "models.json", {"modules": models})

    inputs = []
    declarations = []
    connections = {"golden": [], "candidate": []}
    defined_terms = []
    equality_terms = []
    output_bits = 0
    for index, (port_name, port) in enumerate(golden["ports"].items()):
        checked_identifier(port_name)
        width = len(port["bits"])
        if port["direction"] == "input":
            shared_name = f"input_{index}"
            inputs.append(f"input wire [{width - 1}:0] {shared_name}")
            for side in connections:
                connections[side].append(f".{port_name}({shared_name})")
            continue
        for side in connections:
            declarations.append(f"wire [{width - 1}:0] {side}_{index};")
            connections[side].append(f".{port_name}({side}_{index})")
        for bit in range(width):
            reference = f"golden_{index}[{bit}]"
            candidate_bit = f"candidate_{index}[{bit}]"
            defined = f"!({reference} === 1'bx)"
            defined_terms.append(f"({defined})")
            equality_terms.append(
                f"(!({defined}) || (!({candidate_bit} === 1'bx) && "
                f"({reference} === {candidate_bit})))"
            )
            output_bits += 1
    if not equality_terms:
        raise VerificationHold("design has no primary outputs")

    wrapper = [
        "module refinement_contract(",
        ",\n".join(
            inputs
            + [
                "output wire reference_all_defined",
                "output wire refinement_ok",
            ]
        ),
        ");",
        *declarations,
        "source_golden golden_instance(" + ", ".join(connections["golden"]) + ");",
        "source_candidate candidate_instance("
        + ", ".join(connections["candidate"])
        + ");",
        "assign reference_all_defined = " + " &&\n".join(defined_terms) + ";",
        "assign refinement_ok = " + " &&\n".join(equality_terms) + ";",
        "endmodule",
        "",
    ]
    (work / "contract.sv").write_text("\n".join(wrapper), encoding="utf-8")
    setup = "\n".join(
        [
            "read_json models.json",
            "read_verilog -formal -sv contract.sv",
            "hierarchy -check -top refinement_contract",
            "proc -noopt; flatten; opt_expr -keepdc; opt_clean; check -assert",
        ]
    )
    stages = {
        "domain": (
            "sat -set-def-inputs -set reference_all_defined 1 "
            "-show-ports -dump_json domain_witness.json"
        ),
        "proof": (
            "sat -set-def-inputs -prove refinement_ok 1 "
            "-show-ports -dump_json counterexample.json"
        ),
    }
    logs = {}
    for name, command in stages.items():
        (work / f"{name}.ys").write_text(setup + "\n" + command + "\n", encoding="utf-8")
        code, log = run_yosys(yosys, f"{name}.ys", work, timeout)
        if code != 0:
            raise VerificationHold(f"combinational {name} stage did not complete")
        logs[name] = log
    nonempty = "SAT solving finished - model found:" in logs["domain"]
    equivalent = "SAT proof finished - no model found: SUCCESS!" in logs["proof"]
    counterexample = (
        "SAT proof finished - model found: FAIL!" in logs["proof"]
        and (work / "counterexample.json").is_file()
    )
    if not nonempty:
        raise VerificationHold("reference-defined output domain is empty")
    if not equivalent and not counterexample:
        raise VerificationHold("combinational proof produced no complete verdict")
    return {
        "contract": "reference_defined_bit_refinement_v1",
        "output_bits": output_bits,
        "equivalent": equivalent,
        "counterexample": counterexample,
    }


def validate_clock(module: dict, clock: str, *, allow_async: bool) -> int:
    try:
        clock_port = module["ports"][clock]
    except KeyError as error:
        raise VerificationHold(f"clock {clock} is not a top-level port") from error
    if clock_port["direction"] != "input" or len(clock_port["bits"]) != 1:
        raise VerificationHold("clock must be a scalar input")
    state_bits = 0
    allowed = set(SUPPORTED_STATE)
    if allow_async:
        allowed.update({"$adff", "$adffe"})
    for cell in module["cells"].values():
        kind = cell["type"]
        if kind in allowed:
            if cell["connections"]["CLK"] != clock_port["bits"]:
                raise VerificationHold("multiple or gated clocks require a separate harness")
            state_bits += len(cell["connections"]["Q"])
        elif any(token in kind.lower() for token in ("ff", "latch", "mem")):
            raise VerificationHold(f"unsupported state cell: {kind}")
    if state_bits > MAX_STATE_BITS:
        raise VerificationHold(
            f"state size {state_bits} exceeds the {MAX_STATE_BITS}-bit open-source limit"
        )
    return state_bits


def run_temporal_stages(
    work: Path,
    setup: str,
    yosys: str,
    timeout: int,
    sequence_length: int,
    max_steps: int,
    check_reference_defined: bool = False,
) -> tuple[bool, bool]:
    startup_command = (
        f"sat -seq {sequence_length} -set-assumes -set-def-inputs -set-init-def "
        "-prove-asserts -verify -show-ports -dump_json startup_witness.json"
    )
    induction_command = (
        f"sat -seq {sequence_length} -tempinduct -maxsteps {max_steps} "
        "-set-assumes -set-def-inputs -set-init-def -prove-asserts -verify "
        "-show-ports -dump_json induction_witness.json"
    )
    logs = {}
    codes = {}
    for stage, command in (
        ("startup", startup_command),
        ("induction", induction_command),
    ):
        (work / f"{stage}.ys").write_text(setup + command + "\n", encoding="utf-8")
        codes[stage], logs[stage] = run_yosys(yosys, f"{stage}.ys", work, timeout)

    startup_passed = (
        codes["startup"] == 0
        and "SAT proof finished - no model found: SUCCESS!" in logs["startup"]
    )
    startup_failed = (
        "SAT proof finished - model found: FAIL!" in logs["startup"]
        and (work / "startup_witness.json").is_file()
    )
    induction_passed = (
        codes["induction"] == 0
        and "Induction step proven: SUCCESS!" in logs["induction"]
    )
    if startup_failed and check_reference_defined:
        witness = json.loads((work / "startup_witness.json").read_text(encoding="utf-8"))
        reference_waves = [
            row.get("wave", "")
            for row in witness.get("signal", [])
            if row.get("name") == "reference_defined"
        ]
        if any("0" in wave for wave in reference_waves):
            raise VerificationHold("reference output is undefined in the startup domain")
    if startup_failed:
        return False, True
    if not startup_passed:
        raise VerificationHold("startup proof is inconclusive; see startup.log")
    if not induction_passed:
        raise VerificationHold("temporal induction is inconclusive; see induction.log")
    return True, False


def prove_reset_sequential(
    case: Case,
    candidate: Path,
    work: Path,
    yosys: str,
    timeout: int,
    max_steps: int,
    clock: str,
    reset: str,
    reset_active: int,
) -> dict:
    golden, revised = lower_sources(case, candidate, work, yosys, timeout)
    for module in (golden, revised):
        if reset not in module["ports"]:
            raise VerificationHold(f"reset {reset} is not a top-level port")
        port = module["ports"][reset]
        if port["direction"] != "input" or len(port["bits"]) != 1:
            raise VerificationHold("reset must be a scalar input")
        validate_clock(module, clock, allow_async=True)

    commands = []
    for source, side in ((case.reference, "gold"), (candidate, "gate")):
        commands.extend(
            [
                "design -reset",
                f"read_verilog -sv {quote_yosys_path(source)}",
                f"hierarchy -check -top {case.top}",
                "proc; opt; memory; opt; flatten; async2sync; opt; check -assert",
                f"design -stash {side}",
            ]
        )
    commands.extend(
        [
            "design -reset",
            f"design -copy-from gold -as gold {case.top}",
            f"design -copy-from gate -as gate {case.top}",
            "miter -equiv -flatten gold gate miter",
            "prep -top miter",
            "write_json miter.json",
            "write_verilog miter.v",
        ]
    )
    (work / "miter.ys").write_text("\n".join(commands) + "\n", encoding="utf-8")
    code, _ = run_yosys(yosys, "miter.ys", work, timeout)
    if code != 0:
        raise VerificationHold("cycle-model miter preparation failed; see miter.log")
    document = json.loads((work / "miter.json").read_text(encoding="utf-8"))
    miter = document["modules"]["miter"]
    inputs = [
        (name, port)
        for name, port in miter["ports"].items()
        if port["direction"] == "input"
    ]
    declarations = [
        f"input wire [{len(port['bits']) - 1}:0] {checked_identifier(name)}"
        for name, port in inputs
    ]
    connections = [f".{name}({name})" for name, _ in inputs]
    connections.append(".trigger(trigger)")
    wrapper = "\n".join(
        [
            "module reset_contract(" + ",\n".join(declarations) + ");",
            "wire trigger;",
            "miter dut(" + ", ".join(connections) + ");",
            "reg started = 1'b0;",
            f"always @(posedge in_{clock}) started <= 1'b1;",
            "always @* begin",
            f"  if (!started) assume(in_{reset} == 1'b{reset_active});",
            "  assert(!started || !trigger);",
            "end",
            "endmodule",
            "",
        ]
    )
    (work / "contract.sv").write_text(wrapper, encoding="utf-8")
    setup = "\n".join(
        [
            "read_verilog -formal -sv miter.v contract.sv",
            "prep -flatten -top reset_contract",
            "opt; chformal -lower; check -assert",
            "",
        ]
    )
    equivalent, counterexample = run_temporal_stages(
        work,
        setup,
        yosys,
        timeout,
        sequence_length=2,
        max_steps=max_steps,
    )
    return {
        "contract": "reset_initialized_cycle_sec_v1",
        "clock": clock,
        "reset": reset,
        "reset_active": reset_active,
        "equivalent": equivalent,
        "counterexample": counterexample,
    }


def initialization(module: dict) -> dict[int, str]:
    values = {}
    for net in module["netnames"].values():
        value = net.get("attributes", {}).get("init")
        if value is None:
            continue
        if len(value) != len(net["bits"]):
            raise VerificationHold("malformed initialization attribute")
        for bit, initial in zip(net["bits"], reversed(value)):
            if initial not in ("0", "1") or not isinstance(bit, int):
                continue
            if bit in values and values[bit] != initial:
                raise VerificationHold("contradictory initialization attributes")
            values[bit] = initial
    return values


def expose_state(module: dict) -> tuple[dict, list[int]]:
    exposed = copy.deepcopy(module)
    bits = []
    for cell in exposed["cells"].values():
        if cell["type"] in SUPPORTED_STATE:
            bits.extend(cell["connections"]["Q"])
    if len(set(bits)) != len(bits) or not all(isinstance(bit, int) for bit in bits):
        raise VerificationHold("state bit drivers need separate review")
    if "evaluation_state" in exposed["ports"] or "evaluation_state" in exposed["netnames"]:
        raise VerificationHold("reserved evaluation_state name collision")
    exposed["ports"]["evaluation_state"] = {
        "direction": "output",
        "bits": bits or ["0"],
    }
    exposed["attributes"] = {}
    return exposed, bits


def state_aliases(module: dict, bits: list[int]) -> dict[tuple[str, int], int]:
    positions = {bit: index for index, bit in enumerate(bits)}
    aliases = {}
    for name, net in module["netnames"].items():
        if net.get("hide_name"):
            continue
        width = len(net["bits"])
        offset = net.get("offset", 0)
        for index, bit in enumerate(net["bits"]):
            if bit not in positions:
                continue
            logical_index = offset + (width - 1 - index if net.get("upto") else index)
            aliases[(name, logical_index)] = positions[bit]
    return aliases


def state_mapping(
    golden: dict,
    candidate: dict,
    golden_bits: list[int],
    candidate_bits: list[int],
) -> list[tuple[int, int]]:
    if golden == candidate and len(golden_bits) == len(candidate_bits):
        return list(zip(range(len(golden_bits)), range(len(candidate_bits))))
    left = state_aliases(golden, golden_bits)
    right = state_aliases(candidate, candidate_bits)
    pairs = {}
    used_right = set()
    for alias in sorted(set(left) & set(right)):
        lhs = left[alias]
        rhs = right[alias]
        if lhs in pairs or rhs in used_right:
            continue
        pairs[lhs] = rhs
        used_right.add(rhs)
    if len(pairs) != len(golden_bits) or len(used_right) != len(candidate_bits):
        raise VerificationHold(
            "complete named-state correspondence was not found; use JasperGold"
        )
    return sorted(pairs.items())


def state_contract(
    golden: dict,
    candidate: dict,
    golden_bits: list[int],
    candidate_bits: list[int],
    pairs: list[tuple[int, int]],
    clock: str,
) -> str:
    inputs = [
        (name, port)
        for name, port in golden["ports"].items()
        if port["direction"] == "input"
    ]
    outputs = [
        (name, port)
        for name, port in golden["ports"].items()
        if port["direction"] == "output" and name != "evaluation_state"
    ]
    if not outputs:
        raise VerificationHold("design has no observable outputs")
    declarations = [
        f"input wire [{len(port['bits']) - 1}:0] {checked_identifier(name)}"
        for name, port in inputs
    ]
    declarations.extend(
        [
            "output wire outputs_equal",
            "output wire reference_defined",
            "output wire states_equal",
        ]
    )
    connections = [f".{name}({name})" for name, _ in inputs]
    lines = [
        "module state_contract(" + ",\n".join(declarations) + ");",
        f"wire [{max(1, len(golden_bits)) - 1}:0] golden_state;",
        f"wire [{max(1, len(candidate_bits)) - 1}:0] candidate_state;",
    ]
    golden_connections = list(connections)
    candidate_connections = list(connections)
    equality = []
    defined = []
    for index, (name, port) in enumerate(outputs):
        width = len(port["bits"])
        lines.append(f"wire [{width - 1}:0] golden_out_{index}, candidate_out_{index};")
        golden_connections.append(f".{name}(golden_out_{index})")
        candidate_connections.append(f".{name}(candidate_out_{index})")
        equality.append(f"(golden_out_{index} === candidate_out_{index})")
        defined.extend(
            f"!(golden_out_{index}[{bit}] === 1'bx)" for bit in range(width)
        )
    golden_connections.append(".evaluation_state(golden_state)")
    candidate_connections.append(".evaluation_state(candidate_state)")
    lines.extend(
        [
            "golden dut_golden(" + ", ".join(golden_connections) + ");",
            "candidate dut_candidate(" + ", ".join(candidate_connections) + ");",
            "assign outputs_equal = " + " && ".join(equality) + ";",
            "assign reference_defined = " + " && ".join(defined) + ";",
        ]
    )
    state_equality = [
        f"(golden_state[{left}] === candidate_state[{right}])"
        for left, right in pairs
    ]
    lines.append("assign states_equal = " + (" && ".join(state_equality) or "1'b1") + ";")
    golden_init = initialization(golden)
    candidate_init = initialization(candidate)
    free_pairs = [
        (left, right)
        for left, right in pairs
        if golden_bits[left] not in golden_init
        and candidate_bits[right] not in candidate_init
    ]
    initial_conditions = [
        f"(golden_state[{left}] == candidate_state[{right}])"
        for left, right in free_pairs
    ]
    lines.extend(["reg started = 1'b0;", f"always @(posedge {clock}) started <= 1'b1;", "always @* begin"])
    if initial_conditions:
        lines.append("  if (!started) assume(" + " && ".join(initial_conditions) + ");")
    lines.extend(
        [
            "  assert(reference_defined);",
            "  assert(outputs_equal);",
            "  assert(states_equal);",
            "end",
            "endmodule",
            "",
        ]
    )
    return "\n".join(lines)


def prove_no_reset_sequential(
    case: Case,
    candidate: Path,
    work: Path,
    yosys: str,
    timeout: int,
    max_steps: int,
    clock: str,
) -> dict:
    golden, revised = lower_sources(case, candidate, work, yosys, timeout)
    state_counts = [
        validate_clock(module, clock, allow_async=False)
        for module in (golden, revised)
    ]
    exposed_golden, golden_bits = expose_state(golden)
    exposed_candidate, candidate_bits = expose_state(revised)
    pairs = state_mapping(
        exposed_golden,
        exposed_candidate,
        golden_bits,
        candidate_bits,
    )
    write_json(
        work / "exposed.json",
        {"modules": {"golden": exposed_golden, "candidate": exposed_candidate}},
    )
    (work / "contract.sv").write_text(
        state_contract(
            exposed_golden,
            exposed_candidate,
            golden_bits,
            candidate_bits,
            pairs,
            clock,
        ),
        encoding="utf-8",
    )
    setup = "\n".join(
        [
            "read_json exposed.json",
            "read_verilog -formal -sv contract.sv",
            "hierarchy -check -top state_contract",
            "proc -noopt; flatten; opt_expr -keepdc; opt_clean",
            "chformal -lower; check -assert",
            "",
        ]
    )
    equivalent, counterexample = run_temporal_stages(
        work,
        setup,
        yosys,
        timeout,
        sequence_length=2,
        max_steps=max_steps,
        check_reference_defined=True,
    )
    return {
        "contract": "named_state_correspondence_sec_v1",
        "clock": clock,
        "state_bits": state_counts,
        "mapped_state_bits": len(pairs),
        "equivalent": equivalent,
        "counterexample": counterexample,
    }


def artifact_hashes(work: Path) -> dict[str, str]:
    suffixes = {".json", ".log", ".sv", ".ys", ".vcd"}
    return {
        path.name: digest(path)
        for path in sorted(work.iterdir())
        if path.is_file() and path.suffix in suffixes and path.name != "result.json"
    }


def verify_case(
    case: Case,
    candidate: Path,
    output: Path,
    yosys: str,
    timeout: int,
    max_steps: int,
) -> dict:
    candidate = candidate.resolve(strict=True)
    output = output.resolve()
    if output.exists():
        raise ValueError(f"output already exists; use a fresh directory: {output}")
    output.mkdir(parents=True)
    started = time.monotonic()
    result = {
        "task_id": case.task_id,
        "top_module": case.top,
        "status": "hold",
        "equivalent": None,
        "counterexample": False,
        "reference_sha256": digest(case.reference),
        "candidate_sha256": digest(candidate),
        "authoritative_fallback": "JasperGold SEC",
    }
    try:
        version = subprocess.run(
            [yosys, "-V"],
            text=True,
            capture_output=True,
            timeout=15,
            check=True,
        )
        result["tool_version"] = version.stdout.strip()
        if case.sequential:
            state_sizes = []
            for source, side in ((case.reference, "golden"), (candidate, "candidate")):
                state_sizes.append(
                    preflight_state_size(
                        case,
                        source,
                        side,
                        output,
                        yosys,
                        timeout,
                    )
                )
            result["preflight_state_bits"] = state_sizes
            clock, reset = parse_sec_contract(case)
            if reset is None:
                proof = prove_no_reset_sequential(
                    case,
                    candidate,
                    output,
                    yosys,
                    timeout,
                    max_steps,
                    clock,
                )
            else:
                active = infer_reset_active(case, reset)
                proof = prove_reset_sequential(
                    case,
                    candidate,
                    output,
                    yosys,
                    timeout,
                    max_steps,
                    clock,
                    reset,
                    active,
                )
        else:
            proof = prove_combinational(case, candidate, output, yosys, timeout)
        result.update(proof)
        same_source = result["reference_sha256"] == result["candidate_sha256"]
        if proof["counterexample"] and same_source:
            result.update(
                status="hold",
                equivalent=None,
                counterexample=False,
                hold=(
                    "self-comparison exposed an unsupported initial-state contract; "
                    "use JasperGold"
                ),
            )
        elif proof["equivalent"]:
            result["status"] = "equivalent"
        elif proof["counterexample"]:
            result["status"] = "non_equivalent"
            result["equivalent"] = False
    except (VerificationHold, OSError, KeyError, subprocess.SubprocessError) as error:
        result["hold"] = str(error)
    result["elapsed_seconds"] = round(time.monotonic() - started, 3)
    result["artifact_sha256"] = artifact_hashes(output)
    write_json(output / "result.json", result)
    return result


def print_result(result: dict) -> None:
    detail = result.get("hold", result.get("contract", ""))
    print(f"{result['task_id']}: {result['status']}" + (f" ({detail})" if detail else ""))


def result_exit_code(result: dict) -> int:
    if result["status"] == "equivalent":
        return 0
    if result["status"] == "non_equivalent":
        return 1
    return 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--case", help="semantic ScaleBench task ID")
    selection.add_argument(
        "--self-check-all",
        action="store_true",
        help="verify every reference against itself",
    )
    parser.add_argument("--candidate", type=Path, help="candidate RTL for --case")
    parser.add_argument("--output", type=Path, required=True, help="fresh evidence directory")
    parser.add_argument("--yosys", default=shutil.which("yosys") or "yosys")
    parser.add_argument("--timeout", type=int, default=60, help="seconds per Yosys stage")
    parser.add_argument("--max-steps", type=int, default=12, help="temporal-induction limit")
    args = parser.parse_args()
    if min(args.timeout, args.max_steps) < 1:
        parser.error("--timeout and --max-steps must be positive")
    cases = load_cases()

    if args.self_check_all:
        if args.candidate:
            parser.error("--candidate cannot be used with --self-check-all")
        root = args.output.resolve()
        if root.exists():
            parser.error(f"output already exists; use a fresh directory: {root}")
        root.mkdir(parents=True)
        results = []
        for case in cases.values():
            result = verify_case(
                case,
                case.reference,
                root / case.task_id,
                args.yosys,
                args.timeout,
                args.max_steps,
            )
            results.append(result)
            print_result(result)
        counts = {
            status: sum(result["status"] == status for result in results)
            for status in ("equivalent", "non_equivalent", "hold")
        }
        summary = {"total": len(results), "counts": counts, "results": results}
        write_json(root / "summary.json", summary)
        print(json.dumps({"total": len(results), "counts": counts}, indent=2))
        return 0 if counts == {"equivalent": len(results), "non_equivalent": 0, "hold": 0} else 2

    if args.case not in cases:
        parser.error(f"unknown case: {args.case}")
    if not args.candidate:
        parser.error("--candidate is required with --case")
    result = verify_case(
        cases[args.case],
        args.candidate,
        args.output,
        args.yosys,
        args.timeout,
        args.max_steps,
    )
    print_result(result)
    return result_exit_code(result)


if __name__ == "__main__":
    raise SystemExit(main())
