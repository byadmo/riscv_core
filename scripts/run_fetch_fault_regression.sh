#!/usr/bin/env bash
# Independent local instruction-fetch boundary and precise FAULT_HALT=1 checks.
# No edits to RTL, existing tests, documentation or CI are made by this script.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-fetch-fault}")"
mkdir -p "$out"
cd "$root"

if [[ -n "${IVERILOG_BIN:-}" ]]; then
    compiler=("$IVERILOG_BIN")
elif command -v iverilog >/dev/null 2>&1; then
    compiler=(iverilog)
else
    echo "ERROR: Icarus Verilog compiler not found; set IVERILOG_BIN or PATH" >&2
    exit 127
fi
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then
    compiler+=("-B${IVERILOG_BACKEND}")
fi
if [[ -n "${VVP_BIN:-}" ]]; then
    runtime=("$VVP_BIN")
elif command -v vvp >/dev/null 2>&1; then
    runtime=(vvp)
else
    echo "ERROR: vvp not found; set VVP_BIN or PATH" >&2
    exit 127
fi

sources=(rtl/pipeline_core.sv rtl/latency_data_memory.sv
         rtl/alu.sv rtl/control_unit.sv rtl/regfile.sv)

# external, data-latency, data-jitter, I-latency, I-jitter, D-latency,
# D-jitter, ready-throttle, delayed-D-response-ready
configs=(
    "0 1 0 2 0 3 0 0 0"
    "0 2 3 2 2 3 2 1 0"
    "0 4 3 2 2 3 2 1 0"
    "1 1 0 2 2 3 2 1 0"
    "1 2 2 4 3 1 4 1 5"
    "1 4 3 1 0 6 2 1 5"
)

config_count=0
scenario_count=0
fetch_fault_count=0
valid_count=0
observed_held_i=0
observed_held_d=0
for cfg in "${configs[@]}"; do
    read -r ext latency extra ilat ijit dlat djit throttle hold <<< "$cfg"
    label="fetch_e${ext}_d${latency}x${extra}_i${ilat}x${ijit}_busd${dlat}x${djit}_r${throttle}_hold${hold}"
    echo "--- fetch boundary $label ---"
    "${compiler[@]}" -g2012 -s tb_fetch_fault \
        -Ptb_fetch_fault.EXTERNAL_MODE="$ext" \
        -Ptb_fetch_fault.DATA_LATENCY="$latency" \
        -Ptb_fetch_fault.DATA_MAX_EXTRA="$extra" \
        -Ptb_fetch_fault.I_LATENCY="$ilat" \
        -Ptb_fetch_fault.I_JITTER="$ijit" \
        -Ptb_fetch_fault.D_LATENCY="$dlat" \
        -Ptb_fetch_fault.D_JITTER="$djit" \
        -Ptb_fetch_fault.READY_MODE="$throttle" \
        -Ptb_fetch_fault.DATA_RESPONSE_DELAY="$hold" \
        -o "$out/$label.vvp" "${sources[@]}" \
        tb/dual_port_bus_adapter.sv tb/tb_fetch_fault.sv

    # Generate one *actual* waveform from simulated RTL, not a synthetic trace.
    if [[ "$label" == "fetch_e1_d2x2_i4x3_busd1x4_r1_hold5" ]]; then
        "${runtime[@]}" "$out/$label.vvp" "+vcd=$out/fetch_fault_handshakes.vcd" |
            tee "$out/$label.log"
    else
        "${runtime[@]}" "$out/$label.vvp" | tee "$out/$label.log"
    fi
    grep -q "^PASS fetch-fault suite ext=$ext cases=12 fault=8 valid=4 architectural-checks=12672$" \
        "$out/$label.log" ||
        { echo "ERROR: fetch summary missing/malformed for $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS fetch-fault ext=' "$out/$label.log")" -eq 8 ]] ||
        { echo "ERROR: expected 8 fetch faults in $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS fetch-valid ext=' "$out/$label.log")" -eq 3 ]] ||
        { echo "ERROR: expected 3 redirected/no-fault cases in $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS fetch-reset ext=' "$out/$label.log")" -eq 1 ]] ||
        { echo "ERROR: expected reset+restart case in $label" >&2; exit 1; }
    if [[ "$ext" == 1 ]]; then
        if grep -Eq 'Iheld=[1-9][0-9]*' "$out/$label.log"; then
            observed_held_i=1
        fi
        if grep -Eq 'Dheld=[1-9][0-9]*' "$out/$label.log"; then
            observed_held_d=1
        fi
    fi
    config_count=$((config_count+1))
    scenario_count=$((scenario_count+12))
    fetch_fault_count=$((fetch_fault_count+8))
    valid_count=$((valid_count+4))
done

if [[ "$observed_held_i" != 1 || "$observed_held_d" != 1 ]]; then
    echo "ERROR: external I and D response-backpressure not both observed: I=$observed_held_i D=$observed_held_d" >&2
    exit 1
fi
if [[ ! -s "$out/fetch_fault_handshakes.vcd" ]] ||
   ! grep -q '^\$var ' "$out/fetch_fault_handshakes.vcd" ||
   ! grep -q 'fault_cause' "$out/fetch_fault_handshakes.vcd" ||
   ! grep -q 'i_req_addr' "$out/fetch_fault_handshakes.vcd"; then
    echo "ERROR: authentic fetch/bus waveform was not captured" >&2
    exit 1
fi

# Existing opt-out path is a *separate* compatibility result. Its four
# simulations must EXIT NONZERO for the established memory-access $fatal;
# never count these simulator rejections as new architectural fetch faults.
for fault in 0 1 2 3; do
    label="legacy_memory_fatal_${fault}"
    "${compiler[@]}" -g2012 -s tb_memory_fault \
        -Ptb_memory_fault.FAULT_CASE="$fault" \
        -o "$out/$label.vvp" "${sources[@]}" tb/tb_memory_fault.sv
    if "${runtime[@]}" "$out/$label.vvp" >"$out/$label.log" 2>&1; then
        echo "ERROR: legacy FAULT_HALT=0 memory fault $fault unexpectedly succeeded" >&2
        exit 1
    fi
    grep -q 'Unsupported memory access:' "$out/$label.log" ||
        { cat "$out/$label.log"; echo "ERROR: legacy rejection not the expected fatal" >&2; exit 1; }
    echo "PASS expected legacy FAULT_HALT=0 simulator rejection $fault"
done

# Run the existing, independently checked 4-program integrated default-mode
# test too, without changing any of its sources or historical check counts.
"${compiler[@]}" -g2012 -s tb_integrated_rv32i \
    -o "$out/legacy_integrated.vvp" "${sources[@]}" tb/tb_integrated_rv32i.sv
"${runtime[@]}" "$out/legacy_integrated.vvp" | tee "$out/legacy_integrated.log"
grep -q '^PASS ALL: 4 integrated RV32I programs, 4224 architectural state checks$' \
    "$out/legacy_integrated.log" ||
    { echo "ERROR: legacy integrated architectural verification did not pass" >&2; exit 1; }

echo "PASS fetch-range FAULT_HALT=1 matrix: $config_count configurations, $scenario_count cases ($fetch_fault_count sticky fetch faults, $valid_count valid), $((scenario_count*1056)) architectural comparisons"
echo "PASS fetch-range external backpressure: held I and held D responses observed, no invalid I request offered"
echo "PASS fetch-range FAULT_HALT=0 legacy: 4 expected simulator rejections + 4 integrated programs (4224 historical checks)"
echo "Actual VCD: $out/fetch_fault_handshakes.vcd"
echo "Run logs and compiled simulations: $out"
