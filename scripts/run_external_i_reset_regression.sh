#!/usr/bin/env bash
# Independent shared-reset I-port cancellation tests; separate from 90/72/72.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-external-i-reset}")"
mkdir -p "$output"
cd "$root"
compiler=("${IVERILOG_BIN:-iverilog}")
runtime=("${VVP_BIN:-vvp}")
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then
    compiler+=("-B${IVERILOG_BACKEND}")
fi
core=(rtl/pipeline_core.sv rtl/latency_data_memory.sv
      rtl/alu.sv rtl/control_unit.sv rtl/regfile.sv)
total=0
for halt in 0 1; do
    for config in "2 25" "4 35"; do
        read -r ilat dlat <<< "$config"
        name="i_reset_h${halt}_i${ilat}_d${dlat}"
        "${compiler[@]}" -g2012 -s tb_external_i_reset \
            -Ptb_external_i_reset.FAULT_HALT="$halt" \
            -Ptb_external_i_reset.I_LATENCY="$ilat" \
            -Ptb_external_i_reset.D_LATENCY="$dlat" \
            -o "$output/$name.vvp" "${core[@]}" \
            tb/dual_port_bus_adapter.sv tb/tb_external_i_reset.sv
        "${runtime[@]}" "$output/$name.vvp" | tee "$output/$name.log"
        grep -qx "PASS external-I reset suite fault_halt=$halt: 3 distinct in-flight reset conditions" "$output/$name.log"
        [[ "$(grep -c '^PASS external-I reset ' "$output/$name.log")" -eq 4 ]]
        [[ "$(grep -c '^COVER external-I reset ' "$output/$name.log")" -eq 3 ]]
        total=$((total+3))
    done
done
[[ "$total" -eq 12 ]]
echo "PASS external I reset regression: 4 timing/mode configurations, 12 independently exercised reset conditions"
echo "Evidence: $output"
