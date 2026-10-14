# RV32I pipelined processor — latency-aware memory milestone

This repository contains an experimental 32-bit RISC-V processor project. **The verified integration target is `rtl/pipeline_core.sv`, a five-stage in-order RV32I-subset core**, now coupled to a single-outstanding, latency-controlled request/response data-memory module. The result runs real instruction programs in self-checking simulation. It is not fully RV32I-compliant, synthesized or FPGA-deployed.

## Run the tests

Install Icarus Verilog 12 or compatible. From the repository root:

```sh
bash scripts/run_regression.sh
```

The script preserves three standalone benches (ALU, register-file, control-unit), four existing architectural instruction programs and an independent control-flow program. It additionally runs **36 latency-controlled directed cases**, **12 deterministic reference-interpreted random-program executions**, and **four expected-failure memory access tests**. All passing program benches assert architectural results and exit nonzero on mismatch. They compile the exact verified pipeline modules, not legacy incompatible top-level experiments.

Pass an explicit output directory to preserve VCDs and per-test logs:

```sh
bash scripts/run_regression.sh /tmp/rv32i-evidence
# Inspect: /tmp/rv32i-evidence/integrated.log
# Inspect: /tmp/rv32i-evidence/rv32i_integrated.vcd
```

The same commands run in GitHub Actions whenever relevant RTL, tests or the runner change. All word memories in the testbenches are initialized by the tests; the CPU's data and instruction memories are currently internal simulation arrays.

For memory-only verification:

```sh
bash scripts/run_memory_regression.sh /tmp/rv32i-memory-evidence
python3 scripts/vcd_memory_to_svg.py \
  /tmp/rv32i-memory-evidence/memory_handshake.vcd \
  /tmp/rv32i-memory-evidence/memory_handshake.svg
```

The memory-only runner uses Python 3 as an **independent sequential instruction interpreter** to generate golden register and byte-addressed memory images from three reproducible random seeds, then compares every register and RAM word across four fixed/variable-latency configurations. It also checks requests against responses and ensures invalid/misaligned requests terminate simulation with a nonzero exit rather than silently aliasing.

## Verified features and evidence

See [docs/integrated_milestone.md](docs/integrated_milestone.md) for the diagram, exact ISA subset, hazards, memory assumptions, test provenance, and known boundaries.
See [docs/memory_protocol.md](docs/memory_protocol.md) for timing, backpressure, response pairing and subword lane handling. See [docs/coverage_matrix.md](docs/coverage_matrix.md) for an honest instruction and scenario verification matrix.

- 5-stage IF → ID → EX → MEM → WB integration.
- RV32I integer register-register and immediate arithmetic/logical/shift/compare operations, with correct signed and unsigned comparisons.
- **LB/LBU/LH/LHU/LW and SB/SH/SW**, correctly aligned, little-endian and byte-masked, under modeled memory latency.
- BEQ, BNE, BLT, BGE, BLTU, BGEU with byte offsets and redirect/flush.
- LUI, AUIPC, JAL, JALR with link register and target alignment.
- Load-use interlock, EX/MEM and MEM/WB forwarding, WB/ID bypass and held-ID/EX operand shadow refresh during memory backpressure.
- x0 write suppression.

The four main self-checking programs compare **all 32 registers and all 1024 modeled data-memory words** after each case (4,224 architectural comparisons). They exercise ALU dependencies, zero/negative immediates, forward priority, load-use stalls, store/load data, taken/not-taken and backward branches, and wrong-path store suppression. The separate control-flow test checks JAL/JALR and upper-immediate behaviour.

New directed memory tests check **38,016 state values** (six independently reset scenarios at each of six latency configurations). Twelve additional runs check **12,672 state values** against the Python sequential reference interpreter. Store/request/response counters detect repeated or missing transfers beyond final-state comparison; four invalid-access tests are required to fail in simulation. The latency model covers 1, 2 and 4 cycles, and optional deterministic extra delay of up to three cycles. Both original and expanded regressions run in CI.

## Important limitations

This is a **simulation-stage milestone**, not an RV32I compliance claim. Memory requests and responses use an internal behavioural handshake adapter, **not an external memory controller or AXI bus**. The response is always consumed when valid; there is only one outstanding access and no independent response backpressure. Instruction fetch still uses zero-wait-state array reads. Data accesses outside the modeled 4 KiB or with unsupported alignment explicitly `$fatal` in simulation; **architectural traps or recovery are not implemented**. Illegal instruction encodings, CSRs, interrupts, MMIO, `FENCE` and system instructions remain unsupported. The design has no formal-compliance proof, synthesis, STA, FPGA results or power/performance measurements.

Other historical experiments including `rtl/core_top.sv`, `rtl/riscv_top.sv` and `src/cpu.sv` remain in the repository for reference but are **not** included in the validated integrated build; their old benches and scripts must not be mistaken for passing CPU regressions.

Future work: make the data port an independently supplied external ready/valid bus with variable request-ready and response-ready behavior, introduce a proper fault/trap path, add instruction-memory stalls, strengthen instruction legality checks, run ISA compliance and formal properties, then investigate synthesis and eventual FPGA deployment.
