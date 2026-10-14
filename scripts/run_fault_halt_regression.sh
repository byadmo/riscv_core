#!/usr/bin/env bash
# Architectural FAULT_HALT=1 test suite, independent of RTL implementation.
# Leaves existing FAULT_HALT=0 expected-fatal behaviour under regression too.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-fault-halt-regression}")"
mkdir -p "$output"
cd "$root"

# Use a normal system Icarus installation if available. In the isolated
# development checkout a locally extracted Icarus toolchain may be supplied.
# Keep -B relative to the CPU checkout to handle parent paths with spaces.
if [[ -n "${IVERILOG_BIN:-}" ]]; then
    ivl=("$IVERILOG_BIN")
elif command -v iverilog >/dev/null 2>&1; then
    ivl=(iverilog)
elif [[ -x ../toolchain/root/usr/bin/iverilog ]]; then
    ivl=(../toolchain/root/usr/bin/iverilog)
    if [[ -z "${IVERILOG_BACKEND:-}" ]]; then
        ivl+=(-B../toolchain/root/usr/lib/x86_64-linux-gnu/ivl)
    fi
else
    echo "ERROR: install Icarus Verilog or set IVERILOG_BIN" >&2
    exit 1
fi
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then
    ivl+=("-B${IVERILOG_BACKEND}")
fi
if [[ -n "${VVP_BIN:-}" ]]; then
    sim=("$VVP_BIN")
elif command -v vvp >/dev/null 2>&1; then
    sim=(vvp)
elif [[ -x ../toolchain/root/usr/bin/vvp ]]; then
    sim=(../toolchain/root/usr/bin/vvp)
else
    echo "ERROR: install Icarus Verilog vvp or set VVP_BIN" >&2
    exit 1
fi

core=(rtl/pipeline_core.sv rtl/latency_data_memory.sv
      rtl/alu.sv rtl/control_unit.sv rtl/regfile.sv)
adapter=tb/dual_port_bus_adapter.sv
tb=tb/tb_fault_halt.sv

# Mode 0=internal I/D, mode 1=independent external I/D.
# mode data_lat data_extra i_lat d_lat i_jitter d_jitter ready_mode d_rsp_hold
# Each config executes 12 fault programs + 3 no-fault programs and compares
# every x-register (32) and every data-memory word (1,024) per program.
configs=(
    "0 1 0 2 3 2 2 1 0"
    "0 2 3 2 3 2 2 1 0"
    "0 4 3 2 3 2 2 1 0"
    "1 1 0 2 3 2 2 1 0"
    "1 2 3 4 1 3 4 1 3"
    "1 4 3 1 6 0 2 1 4"
)
config_count=0
scenarios=0
for config in "${configs[@]}"; do
    read -r mode data_lat data_extra i_lat d_lat i_jitter d_jitter ready_mode hold <<< "$config"
    label="mode${mode}_d${data_lat}x${data_extra}_i${i_lat}x${i_jitter}_extd${d_lat}x${d_jitter}_r${ready_mode}_h${hold}"
    echo "--- fault halt $label ---"
    "${ivl[@]}" -g2012 -s tb_fault_halt \
        -Ptb_fault_halt.EXTERNAL_MODE="$mode" \
        -Ptb_fault_halt.DATA_LATENCY="$data_lat" \
        -Ptb_fault_halt.DATA_MAX_EXTRA="$data_extra" \
        -Ptb_fault_halt.I_LATENCY="$i_lat" \
        -Ptb_fault_halt.D_LATENCY="$d_lat" \
        -Ptb_fault_halt.I_JITTER="$i_jitter" \
        -Ptb_fault_halt.D_JITTER="$d_jitter" \
        -Ptb_fault_halt.READY_MODE="$ready_mode" \
        -Ptb_fault_halt.DATA_RESPONSE_DELAY="$hold" \
        -o "$output/$label.vvp" "${core[@]}" "$adapter" "$tb"
    "${sim[@]}" "$output/$label.vvp" | tee "$output/$label.log"
    grep -q "^PASS fault-halt regression ext=$mode scenarios=15 fault-cases=12 state-checks=15840$" "$output/$label.log" ||
        { echo "ERROR: fault regression summary absent for $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS fault halt' "$output/$label.log")" -eq 12 ]] ||
        { echo "ERROR: not all 12 expected fault cases passed in $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS no-fault' "$output/$label.log")" -eq 3 ]] ||
        { echo "ERROR: not all 3 valid cases passed in $label" >&2; exit 1; }
    config_count=$((config_count+1))
    scenarios=$((scenarios+15))
done

# Explicit backwards-compatibility gate: old default FAULT_HALT=0 must
# continue to reject these accesses by simulator $fatal, NOT quietly halt.
legacy_faults=0
for case_number in 0 1 2 3; do
    label="legacy_fatal_${case_number}"
    echo "--- legacy unsupported memory access fatal $case_number ---"
    "${ivl[@]}" -g2012 -s tb_memory_fault \
        -Ptb_memory_fault.FAULT_CASE="$case_number" \
        -o "$output/$label.vvp" "${core[@]}" tb/tb_memory_fault.sv
    if "${sim[@]}" "$output/$label.vvp" > "$output/$label.log" 2>&1; then
        echo "ERROR: FAULT_HALT=0 legacy fault $case_number unexpectedly succeeded" >&2
        exit 1
    fi
    grep -q 'Unsupported memory access:' "$output/$label.log" ||
        { echo "ERROR: legacy fault $case_number failed for another reason" >&2; cat "$output/$label.log"; exit 1; }
    legacy_faults=$((legacy_faults+1))
    echo "PASS legacy fatal case=$case_number"
done

echo "PASS FAULT_HALT matrix: $config_count configurations, $scenarios scenarios ($((scenarios*1056)) architectural state comparisons)"
echo "PASS FAULT_HALT legacy: $legacy_faults expected simulator-fatal memory access rejections"
echo "Logs and simulation builds: $output"
