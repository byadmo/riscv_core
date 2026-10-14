# RV32I pipelined processor — verified educational milestone

This repository contains an experimental 32-bit RISC-V processor project. **The specifically supported integration target is `rtl/pipeline_core.sv`, a five-stage in-order RV32I-subset core.** It executes real instructions in a self-checking simulation; it is not yet a fully compliant or FPGA-deployed CPU.

## Run the tests

Install Icarus Verilog 12 or compatible. From the repository root:

```sh
bash scripts/run_regression.sh
```

The script runs three existing standalone benches (ALU, register-file, control-unit), then **four architectural instruction programs** and an independent control-flow program. It compiles the exact modules needed for the verified pipeline, since the repository also contains older, alternative top-level experiments that are not claimed to work. All the instruction-program benches use `$fatal` on errors, exit nonzero on failure, and check register/memory outcomes, not just completion messages.

Pass an explicit output directory to preserve VCDs and per-test logs:

```sh
bash scripts/run_regression.sh /tmp/rv32i-evidence
# Inspect: /tmp/rv32i-evidence/integrated.log
# Inspect: /tmp/rv32i-evidence/rv32i_integrated.vcd
```

The same commands run in GitHub Actions whenever relevant RTL, tests or the runner change. All word memories in the testbenches are initialized by the tests; the CPU's data and instruction memories are currently internal simulation arrays.

## Verified features and evidence

See [docs/integrated_milestone.md](docs/integrated_milestone.md) for the diagram, exact ISA subset, hazards, memory assumptions, test provenance, and known boundaries.

- 5-stage IF → ID → EX → MEM → WB integration.
- RV32I integer register-register and immediate arithmetic/logical/shift/compare operations, with correct signed and unsigned comparisons.
- **LW and SW** on word-aligned addresses, one-cycle modeled MEM access.
- BEQ, BNE, BLT, BGE, BLTU, BGEU with byte offsets and redirect/flush.
- LUI, AUIPC, JAL, JALR with link register and target alignment.
- Load-use interlock (freeze PC and IF/ID, inject ID/EX bubble), EX/MEM and MEM/WB forwarding, and WB/ID bypass.
- x0 write suppression.

The four main self-checking programs compare **all 32 registers and all 1024 modeled data-memory words** after each case (4,224 architectural comparisons). They exercise ALU dependencies, zero/negative immediates, forward priority, load-use stalls, store/load data, taken/not-taken and backward branches, and wrong-path store suppression. The separate control-flow test checks JAL/JALR and upper-immediate behaviour.

## Important limitations

This is a **simulation-stage milestone**, not an RV32I compliance claim. There is no CSR/trap/interrupt implementation, MMIO or external memory bus, byte/halfword loads/stores, fence/system instruction support, exhaustive instruction-encoding legality validation, pipeline timing closure, FPGA synthesis, power/area report or hardware measurements. The internal memories are fixed 1,024×32-bit word arrays indexed by address bits; out-of-range addresses alias instead of trapping, and unaligned memory accesses are unsupported. Do not use these omissions as if they were proven correct behaviour.

Other historical experiments including `rtl/core_top.sv`, `rtl/riscv_top.sv` and `src/cpu.sv` remain in the repository for reference but are **not** included in the validated integrated build; their old benches and scripts must not be mistaken for passing CPU regressions.

Future work: strengthen illegal-instruction detection, add memory interface/latency variation and traps, run ISA compliance tests and formal properties, then perform synthesis and eventual FPGA deployment.
