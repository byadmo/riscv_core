#!/usr/bin/env bash
# Expanded independent memory/pipeline verification. Requires Python 3 and Icarus.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(realpath -m "${1:-${TMPDIR:-/tmp}/rv32i-memory-regression}")"
mkdir -p "$output"
cd "$output"
ivl=(iverilog)
if [[ -n "${IVERILOG_BACKEND:-}" ]]; then ivl+=("-B${IVERILOG_BACKEND}"); fi
core=("$root/rtl/pipeline_core.sv" "$root/rtl/latency_data_memory.sv"
      "$root/rtl/alu.sv" "$root/rtl/control_unit.sv" "$root/rtl/regfile.sv")
directed_count=0
random_count=0
for cfg in "1 0" "1 3" "2 0" "2 3" "4 0" "4 3"; do
  read -r latency extra <<< "$cfg"
  label="${latency}_${extra}"
  echo "--- Directed memory latency $latency extra $extra ---"
  "${ivl[@]}" -g2012 -s tb_memory_latency_rv32i \
    -Ptb_memory_latency_rv32i.DATA_LATENCY="$latency" \
    -Ptb_memory_latency_rv32i.DATA_MAX_EXTRA="$extra" \
    -o "directed_${label}.vvp" "${core[@]}" "$root/tb/tb_memory_latency_rv32i.sv"
  vvp "directed_${label}.vvp" | tee "directed_${label}.log"
  grep -q "^PASS latency-controlled memory RV32I: DATA_LATENCY=$latency DATA_MAX_EXTRA=$extra cases=6 checks=6336" "directed_${label}.log"
  directed_count=$((directed_count+6))
done
for seed in 31415 27182 16180; do
  work="$output/seed_$seed"
  mkdir -p "$work"
  python3 "$root/scripts/generate_memory_stress.py" "$work" "$seed" | tee "$work/oracle.log"
  for cfg in "1 0" "1 3" "2 3" "4 3"; do
    read -r latency extra <<< "$cfg"
    label="${latency}_${extra}"
    echo "--- Reference seed $seed latency $latency extra $extra ---"
    "${ivl[@]}" -g2012 -s tb_random_reference_rv32i \
      -Ptb_random_reference_rv32i.DATA_LATENCY="$latency" \
      -Ptb_random_reference_rv32i.DATA_MAX_EXTRA="$extra" \
      -o "$work/reference_${label}.vvp" "${core[@]}" "$root/tb/tb_random_reference_rv32i.sv"
    (cd "$work"; if [[ "$seed" == "31415" && "$label" == "4_3" ]]; then
        vvp "reference_${label}.vvp" "+vcd=$output/memory_handshake.vcd" | tee "reference_${label}.log"
      else
        vvp "reference_${label}.vvp" | tee "reference_${label}.log"
      fi)
    grep -q "^PASS random reference latency=$latency extra=$extra " "$work/reference_${label}.log"
    random_count=$((random_count+1))
  done
done
# Negative gates prove that invalid requests are caught, not silently aliased.
for fault in 0 1 2 3; do
  echo "--- Expected simulation rejection: memory fault $fault ---"
  "${ivl[@]}" -g2012 -s tb_memory_fault -Ptb_memory_fault.FAULT_CASE="$fault" \
    -o "fault_${fault}.vvp" "${core[@]}" "$root/tb/tb_memory_fault.sv"
  if vvp "fault_${fault}.vvp" >"fault_${fault}.log" 2>&1; then
    echo "FAIL: memory fault $fault was accepted" >&2; exit 1
  fi
  grep -q 'Unsupported memory access:' "fault_${fault}.log"
  echo "PASS expected rejection fault $fault"
done
echo "PASS memory regression: $directed_count directed scenario runs (38016 state checks), $random_count reference-program runs (12672 state checks), 4 expected fault rejections"
echo "Actual logs and VCD: $output"
