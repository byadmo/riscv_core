#!/usr/bin/env bash
# Independent instruction/data port regression: behavioural external adapter.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-external}")"
mkdir -p "$output"
cd "$output"
ivl=(iverilog)
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then ivl+=("-B${IVERILOG_BACKEND}"); fi
core=("$root/rtl/pipeline_core.sv" "$root/rtl/latency_data_memory.sv"
      "$root/rtl/alu.sv" "$root/rtl/control_unit.sv" "$root/rtl/regfile.sv")
adapter="$root/tb/dual_port_bus_adapter.sv"
directed=0
random_runs=0
# I-base I-variation D-base D-variation request-ready-throttle core-response-hold
configs=(
  "2 2 3 3 1 0"
  "2 4 1 2 1 3"
  "5 2 4 1 1 5"
  "1 0 6 2 1 2"
  "3 3 3 2 0 4"
  "7 3 2 4 1 6"
)
# Golden register/memory images are computed by a separate sequential Python
# interpreter. Its own instruction decoder never consults RTL pipeline state.
for seed in 31415 27182 16180; do
  python3 "$root/scripts/generate_memory_stress.py" "$output/seed_$seed" "$seed"
done
for cfg in "${configs[@]}"; do
  read -r il ij dl dj ready hold <<< "$cfg"
  label="i${il}x${ij}_d${dl}x${dj}_r${ready}_h${hold}"
  echo "--- independent buses $label ---"
  "${ivl[@]}" -g2012 -s tb_external_bus_rv32i \
    -Ptb_external_bus_rv32i.I_LATENCY="$il" \
    -Ptb_external_bus_rv32i.I_JITTER="$ij" \
    -Ptb_external_bus_rv32i.D_LATENCY="$dl" \
    -Ptb_external_bus_rv32i.D_JITTER="$dj" \
    -Ptb_external_bus_rv32i.READY_MODE="$ready" \
    -Ptb_external_bus_rv32i.DATA_RESPONSE_DELAY="$hold" \
    -o "${label}.vvp" "${core[@]}" "$adapter" "$root/tb/tb_external_bus_rv32i.sv"
  if [[ "$label" == "i2x4_d1x2_r1_h3" ]]; then
    vvp "${label}.vvp" "+vcd=$output/external_bus.vcd" | tee "${label}.log"
  else
    vvp "${label}.vvp" | tee "${label}.log"
  fi
  grep -q "^PASS external-bus RV32I cases=7 state-checks=7392 " "${label}.log"
  directed=$((directed+7))
  # Four independent instruction/data timing pairings for each of 3 seeds.
  if [[ "$label" == "i2x2_d3x3_r1_h0" ||
        "$label" == "i2x4_d1x2_r1_h3" ||
        "$label" == "i5x2_d4x1_r1_h5" ||
        "$label" == "i7x3_d2x4_r1_h6" ]]; then
    for seed in 31415 27182 16180; do
      work="$output/seed_$seed"
      nins="$(sed -n 's/.*instructions=\([0-9]*\).*/\1/p' "$work/manifest.txt")"
      [[ -n "$nins" ]] || { echo "Missing interpreter instruction count" >&2; exit 1; }
      echo "--- independent Python oracle seed $seed $label ---"
      (cd "$work"; vvp "$output/${label}.vvp" +reference \
         +program=program.hex +initial_mem=initial_mem.hex \
         +expected_regs=expected_regs.hex +expected_mem=expected_mem.hex \
         "+nins=$nins" | tee "oracle_${label}.log")
      grep -q "^PASS external Python oracle nins=$nins " "$work/oracle_${label}.log"
      random_runs=$((random_runs+1))
    done
  fi
done
# Wrong identity must be rejected, not merely lead to a mismatched final state.
for fault in i d; do
  echo "--- expected corrupt ${fault^^} response tag rejection ---"
  case "$fault" in
    i) flag="+corrupt_i_tag"; pattern="Instruction response identity mismatch" ;;
    d) flag="+corrupt_d_tag"; pattern="Data response tag mismatch" ;;
  esac
  if vvp "$output/i2x2_d3x3_r1_h0.vvp" "$flag" >"fault_${fault}.log" 2>&1; then
    echo "FAIL: invalid response tag accepted on $fault channel" >&2; exit 1
  fi
  grep -q "$pattern" "fault_${fault}.log" ||
    { cat "fault_${fault}.log"; echo "Unexpected fault result" >&2; exit 1; }
  echo "PASS rejected invalid ${fault^^} response tag"
done
echo "PASS external directed: $directed architectural scenario runs ($((directed*1056)) state comparisons), six independent I/D timing configurations"
echo "PASS external oracle: $random_runs independently interpreted runs ($((random_runs*1056)) state comparisons)"
echo "PASS external protocol faults: 2 expected response identity rejections"
echo "Actual external waveform and test logs: $output"
