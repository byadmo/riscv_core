#!/usr/bin/env bash
# Verified educational RV32I pipeline regression. Requires Icarus Verilog 12+.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-regression}")"
mkdir -p "$output"
cd "$output"
ivl=(iverilog)
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then
    ivl+=("-B${IVERILOG_BACKEND}")
fi
run_one() {
    local top="$1" name="$2" pattern="$3"
    shift 3
    echo "--- ${name} ---"
    "${ivl[@]}" -g2012 -s "$top" -o "$output/${name}.vvp" "$@"
    vvp "$output/${name}.vvp" | tee "$output/${name}.log"
    grep -q "$pattern" "$output/${name}.log"
}
run_one tb_alu alu "tb_alu PASS" \
  "$root/rtl/alu.sv" "$root/tb/tb_alu.sv"
run_one tb_register_file register_file "tb_register_file PASS" \
  "$root/rtl/register_file.sv" "$root/tb/tb_register_file.sv"
run_one tb_control_unit control_unit "tb_control_unit PASS" \
  "$root/rtl/control_unit.sv" "$root/tb/tb_control_unit.sv"
core=("$root/rtl/pipeline_core.sv" "$root/rtl/alu.sv"
      "$root/rtl/control_unit.sv" "$root/rtl/regfile.sv")
echo '--- integrated architectural programs ---'
"${ivl[@]}" -g2012 -s tb_integrated_rv32i -o "$output/integrated.vvp" \
  "${core[@]}" "$root/tb/tb_integrated_rv32i.sv"
vvp "$output/integrated.vvp" "+vcd=$output/rv32i_integrated.vcd" | tee "$output/integrated.log"
grep -q '^PASS ALL: 4 integrated RV32I programs, 4224 architectural state checks' "$output/integrated.log"
echo '--- independent control-flow program ---'
"${ivl[@]}" -g2012 -s tb_controlflow_rv32i -o "$output/controlflow.vvp" \
  "${core[@]}" "$root/tb/tb_controlflow_rv32i.sv"
vvp "$output/controlflow.vvp" | tee "$output/controlflow.log"
grep -q '^PASS controlflow:' "$output/controlflow.log"
echo 'PASS regression: 3 standalone modules + 4 integrated programs + 1 control-flow program'
echo "Evidence and logs: $output"
