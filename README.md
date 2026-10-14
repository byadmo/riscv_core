# RV32I pipelined processor — external memory and fault diagnostics

This repository contains an experimental 32-bit RISC-V processor project. **The verified integration target is `rtl/pipeline_core.sv`, a five-stage in-order RV32I-subset core.** The original integrated and variable-latency *internal* data-memory regressions remain supported. A newer `EXTERNAL_PORTS=1` configuration decouples both instruction and data paths through independent ready/valid request/response channels with per-transaction 8-bit tags and explicit response backpressure. An additional opt-in `FAULT_HALT=1` mode captures precise, ordered fault diagnostics and stops execution without corrupting older architectural state, including a newer modeled instruction-fetch boundary check. This is an educational simulation milestone, not full ISA compliance, a privileged trap handler, synthesis or FPGA hardware.

## Run the tests

Install Icarus Verilog 12 or compatible. From the repository root:

```sh
bash scripts/run_regression.sh
```

The script preserves three standalone benches (ALU, register-file, control-unit), four existing architectural instruction programs and an independent control-flow program. It additionally runs **36 latency-controlled directed cases**, **12 deterministic reference-interpreted random-program executions**, and **four expected-failure memory access tests**, followed by independent I/D-interface and opt-in fault-stop regressions. All passing program benches assert architectural results and exit nonzero on mismatch. They compile the exact verified pipeline modules, not legacy incompatible top-level experiments.

Pass an explicit output directory to preserve VCDs and per-test logs:

```sh
bash scripts/run_regression.sh /tmp/rv32i-evidence
# Inspect: /tmp/rv32i-evidence/integrated.log
# Inspect: /tmp/rv32i-evidence/rv32i_integrated.vcd
```

The same commands run in GitHub Actions whenever relevant RTL, tests or the runner change. All word memories in the testbenches are initialized by the tests; the CPU's data and instruction memories are currently internal simulation arrays.

## Explicit instruction/data ports

```sh
bash scripts/run_external_regression.sh /tmp/rv32i-external-evidence
```

The `EXTERNAL_PORTS=1` mode exposes **two independent single-outstanding memory channels**, with explicit address/tag request acceptance and tagged response validity/readiness. Instruction tags identify the current **fetch epoch** (advancing on redirects/faults); data tags increment per accepted data request. The external test environment `tb/dual_port_bus_adapter.sv` independently delays instruction fetches and data operations, throttles accepted requests and holds responses until the CPU is ready. Its architectural program tests verify registers, memory state, branch redirects, byte lanes, and request/response/store cardinalities. A real two-channel handshake VCD is captured. See [docs/external_ports.md](docs/external_ports.md) for full port names, timing and reset contract.

The separately counted `scripts/run_external_i_reset_regression.sh` specifically verifies the shared-reset contract for three distinct I-channel states: an offered but unaccepted request, an accepted but unanswered request, and an I response backpressured by an older load. Each is interrupted by reset and followed by a different program whose register results and memory sentinel are checked for contamination, in both legacy and opt-in fault modes under two timing configurations. **12 targeted reset runs**, not additional full architectural comparisons or additions to the existing fault/fetch case counts.

The expanded external regression executes **42 directed program cases (44,352 complete register/data-memory comparisons)**, **12 independently interpreted Python-reference executions (12,672 comparisons)** and **two intentionally corrupted response-tag cases that must terminate with an identity error**. A 300-redirect loop and an additional 301-instruction sequence exercise fetch epoch/tag rollover. The six timing configurations independently vary I and D response latency, request acceptance and CPU response readiness. Captured `external_bus.vcd` is sampled into a source-backed waveform illustration with `scripts/vcd_external_to_svg.py`.

External mode is **not** an AXI controller, physical SRAM interface, a cache, a fault-recovery engine or full RV32I implementation. The educational default mode remains available for regression compatibility; its internal memory arrays do not supply the external core's instruction/data reads.

## Precise fault-stop diagnostic mode (opt-in)

Set `FAULT_HALT=1` in `pipeline_core` to enable latched `fault_valid`, `fault_cause`, `fault_pc` and `fault_tval` outputs. The core detects illegal or unsupported instruction encodings, misaligned taken control-flow targets, misaligned load/store addresses, data accesses outside its modeled 4 KiB RAM, and **instruction fetches outside the modeled 4 KiB instruction space**. The latter are represented as squashable IF-to-EX tokens rather than speculative immediate halt: an older taken branch may discard them, while an aligned out-of-range jump can retire its link before the later fetch fault. Invalid data requests and invalid-range external I fetches are never issued in this mode. Older data-memory transactions finish before a younger fault is reported. An older non-memory instruction in EX/MEM may complete its register write **one clock edge after `fault_valid` first asserts**; consumers must allow that final writeback before sampling completed architectural state. Default `FAULT_HALT=0` retains the original behaviour and expected `$fatal` negative tests.

**This is fault containment/diagnostics, not a privileged RISC-V exception/trap implementation.** There is no `mtvec`, `mepc`, `mcause`, `MRET`, exception handler, `ECALL` support, privilege model or asynchronous interrupt handling. Numeric cause codes are borrowed from the RISC-V exception list only to identify fault types; local 4 KiB modeled address-range errors are not external bus faults. See [docs/fault_halt.md](docs/fault_halt.md) for exact semantics, limitations, test cases and replay commands.

```sh
bash scripts/run_fault_halt_regression.sh /tmp/rv32i-fault-halt
```

Six simulated timing configurations (three internal and three independent external I/D) each execute **12 fault and 3 non-fault programs**, giving **90 passing scenarios and 95,040 complete architectural register/memory checks**. Every program checks all 32 registers and all 1,024 modeled data-memory words; 4 additional legacy expected-fatal rejection tests preserve default-mode compatibility. The new suite checks precise cause/PC/value, older store/writeback completion, wrong-path rejection, no invalid data transaction, sticky reporting and reset. These checks are not formal verification or full ISA compliance.

An additional, separately counted `scripts/run_fault_priority_regression.sh` suite checks reserved R-type encodings, negative and simultaneously misaligned/out-of-range addresses, fault-priority selection and older instruction retirement under both internal and delayed external memory. Its **18 scenarios × 4 timing configurations = 72 additional runs (76,032 architectural register/memory comparisons)** do not alter the 90-scenario fault-stop or 72-scenario fetch-boundary totals.

### Instruction fetch range and speculative wrong-path checks

The modeled 4 KiB instruction address boundary is distinct from the earlier data-memory fault cases. `FAULT_HALT=1` emits a local numeric cause `1` when an attempted instruction PC is outside `0x00000000`–`0x00000fff`, with `fault_pc=fault_tval=the rejected PC`. IF does not send that invalid request to external memory or alias `pc[11:2]` in the internal instruction store. Instead, it injects an age-ordered fault token that can be invalidated by an older control redirect; accepted older memory stores and jump-link writes still retire correctly.

```sh
bash scripts/run_fetch_fault_regression.sh /tmp/rv32i-fetch-fault
```

The independent instruction-boundary runner executes **12 cases × 6 timing configurations = 72 runs and 76,032 full register/data-memory comparisons**, comprising 48 sticky fetch-boundary cases and 24 no-fault or reset/restart checks. Each run checks 32 integer registers and 1,024 data-memory words. Its cases cover full 1,024-word sequential fetch, last-word fall-through, load/store retirement, load-use dependencies, taken versus not-taken redirection at `0xFFC`, JAL/JALR link behavior, and a fresh program after resetting a sticky fault. External variants assert valid/ready request and response stability, forbid even *offering* a bad I address under backpressure and capture an authentic I/D/fault waveform. A four-test default-mode memory rejection gate and historical integrated program run are separate compatibility checks, **not part of the 76,032**.

This extension checks the **local teaching-model bounds** only, not a real instruction-bus error response or privileged RISC-V instruction access-fault handler. The external I/D interface has no `rsp_error` or trap delivery/recovery mechanism; all reported faults remain sticky until reset. The new suite and original 95,040 prior fault-stop checks remain separately counted; neither is formal proof.

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

This is a **simulation-stage milestone**, not an RV32I compliance claim. The default mode uses internal behavioural memory with a single outstanding data request; external mode adds separately driven **I and D** ready/valid channels with response-ready backpressure and explicit tags. Neither mode implements AXI, an external SRAM macro, architectural privilege/trap recovery, CSR/interrupts, MMIO or `FENCE`. The optional diagnostic mode checks encodings for the supported subset and simulated instruction-memory bounds, not the entire ISA or physical instruction fetch faults. External bus simulations use 4 KiB memories; invalid data accesses are rejected via historical `$fatal` in default mode or stopped before issuance in `FAULT_HALT=1`. The processor has no formal-compliance proof, synthesis, STA, FPGA results or power/performance measurements.

Other historical experiments including `rtl/core_top.sv`, `rtl/riscv_top.sv` and `src/cpu.sv` remain in the repository for reference but are **not** included in the validated integrated build; their old benches and scripts must not be mistaken for passing CPU regressions.

Future work: upgrade opt-in fail-stop reporting to an actual architectural trap handler with readable CSRs and `MRET`, model bus-reported instruction/data access errors instead of only local range checks, test ISA compliance and formal properties, then investigate synthesis and eventual FPGA deployment.
