#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Prefer an installed Icarus Verilog, but also accept the local unpacked .deb
# toolchain when one was supplied for this checkout.
if command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    compiler=(iverilog)
    runtime=(vvp)
elif [[ -x "$project_root/../toolchain/iverilog-root/usr/bin/iverilog" &&
        -x "$project_root/../toolchain/iverilog-root/usr/bin/vvp" ]]; then
    toolchain_root="$project_root/../toolchain/iverilog-root/usr"
    # Icarus internally invokes its backend through a shell; relative -B/-M
    # paths avoid failures when the checkout's parent directory has spaces.
    ivl_lib="../toolchain/iverilog-root/usr/lib/x86_64-linux-gnu/ivl"
    compiler=("$toolchain_root/bin/iverilog" "-B$ivl_lib")
    runtime=("$toolchain_root/bin/vvp" "-M$ivl_lib")
else
    echo "Integrated RV32I simulation requires Icarus Verilog (iverilog and vvp)." >&2
    exit 127
fi

if [[ $# -ne 0 && !( $# -eq 2 && $1 == --vcd ) ]]; then
    echo "Usage: scripts/run_integrated.sh [--vcd path/to/waveform.vcd]" >&2
    exit 2
fi

simulation_dir="$(mktemp -d)"
trap 'rm -rf -- "$simulation_dir"' EXIT

cd "$project_root"
"${compiler[@]}" -g2012 -s tb_integrated_rv32i -o "$simulation_dir/integrated.vvp" \
    rtl/alu.sv rtl/control_unit.sv rtl/regfile.sv rtl/hazard_unit.sv \
    rtl/pipeline_core.sv tb/tb_integrated_rv32i.sv

if [[ $# -eq 2 ]]; then
    "${runtime[@]}" "$simulation_dir/integrated.vvp" "+vcd=$2"
else
    "${runtime[@]}" "$simulation_dir/integrated.vvp"
fi
