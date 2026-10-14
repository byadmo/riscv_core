#!/usr/bin/env bash
# Additional adversarial faults; separately counted from the historical 90/72.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-fault-priority}")"
mkdir -p "$out"
cd "$root"

if [[ -n "${IVERILOG_BIN:-}" ]]; then
    compiler=("$IVERILOG_BIN")
elif command -v iverilog >/dev/null 2>&1; then
    compiler=(iverilog)
else
    echo "ERROR: Icarus compiler missing" >&2
    exit 127
fi
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then
    compiler+=("-B${IVERILOG_BACKEND}")
fi
if [[ -n "${VVP_BIN:-}" ]]; then
    simulator=("$VVP_BIN")
elif command -v vvp >/dev/null 2>&1; then
    simulator=(vvp)
else
    echo "ERROR: vvp runtime missing" >&2
    exit 127
fi

core=(rtl/pipeline_core.sv rtl/latency_data_memory.sv
      rtl/alu.sv rtl/control_unit.sv rtl/regfile.sv)
configs=(
    "0 1 0 2 0 2 0 0 0"
    "0 4 3 2 2 3 3 1 0"
    "1 2 2 2 2 3 1 1 9"
    "1 4 3 5 2 1 2 1 8"
)
total=0
for cfg in "${configs[@]}"; do
    read -r ext lat extra ilat ijit dlat djit ready hold <<< "$cfg"
    label="priority_e${ext}_d${lat}x${extra}_i${ilat}x${ijit}_busd${dlat}x${djit}_r${ready}_hold${hold}"
    "${compiler[@]}" -g2012 -s tb_fault_priority \
        -Ptb_fault_priority.EXTERNAL_MODE="$ext" \
        -Ptb_fault_priority.DATA_LATENCY="$lat" \
        -Ptb_fault_priority.DATA_MAX_EXTRA="$extra" \
        -Ptb_fault_priority.I_LATENCY="$ilat" \
        -Ptb_fault_priority.I_JITTER="$ijit" \
        -Ptb_fault_priority.D_LATENCY="$dlat" \
        -Ptb_fault_priority.D_JITTER="$djit" \
        -Ptb_fault_priority.READY_MODE="$ready" \
        -Ptb_fault_priority.DATA_RESPONSE_DELAY="$hold" \
        -o "$out/$label.vvp" "${core[@]}" \
        tb/dual_port_bus_adapter.sv tb/tb_fault_priority.sv
    "${simulator[@]}" "$out/$label.vvp" | tee "$out/$label.log"
    grep -qx "PASS fault-priority suite ext=$ext cases=18 architectural-checks=19008" "$out/$label.log" ||
        { echo "ERROR: missing architectural summary for $label" >&2; exit 1; }
    [[ "$(grep -c '^PASS priority ext=' "$out/$label.log")" -eq 18 ]] ||
        { echo "ERROR: missing individual adversarial cases for $label" >&2; exit 1; }
    if [[ "$ext" == 1 && "$hold" -gt 0 ]]; then
        grep -Eq 'older delayed SW completes.*heldD=[1-9][0-9]*' "$out/$label.log" ||
            { echo "ERROR: delayed older D store response was never held" >&2; exit 1; }
        grep -Eq 'older delayed LW.*heldD=[1-9][0-9]*' "$out/$label.log" ||
            { echo "ERROR: delayed older D load response was never held" >&2; exit 1; }
    fi
    total=$((total+18))
done
[[ "$total" -eq 72 ]] || exit 1
echo "PASS fault-priority regression: 4 configurations, $total independent cases ($((total*1056)) architectural checks)"
echo "Evidence: $out"
