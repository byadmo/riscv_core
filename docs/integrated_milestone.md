# Integrated RV32I pipeline: what is verified

**Milestone:** functional 5-stage educational RV32I-subset simulation using `rtl/pipeline_core.sv`, now with bounded variable-latency data-memory requests, byte masks and an independent sequential architectural oracle. This is a statement about observed architectural results under the tested cases, **not** a fully verified RV32I-compliant processor or FPGA implementation. The original zero-wait baseline tests are preserved.

## Pipeline and data flow

```text
   PC/IMEM -> IF/ID -> decode + RF -> ID/EX -> ALU/branch -> EX/MEM -> request/response RAM -> MEM/WB -> RF
      ^                      |               ^                  |                 |
      |<-- EX redirect -------|               |                  |                 |
      |<--- hold on load-use stall or memory backpressure <---- forwarding from EX/MEM & MEM/WB
                            WB-to-ID bypass <-----------------------------------|
```

The program counter and IF/ID register **hold** when the instruction in EX is a load whose destination is used by the instruction in ID. ID/EX receives one invalid bubble, allowing the load to advance toward WB. EX selects bypassed source data from EX/MEM first (newest), otherwise MEM/WB, otherwise the ID/EX operand. EX/MEM **does not** forward unfinished load data. A separate MEM/WB-to-ID bypass accounts for a register-file write occurring on the same edge ID captures its operands.

Branch comparisons use **both forwarded register operands** rather than comparing against a branch immediate. B-type and J-type immediates already represent byte offsets; there is no extra shift. A taken branch or jump redirects PC in EX and kills both younger instructions in IF/ID and ID/EX. No branch prediction is implemented.

Load/read data is captured into MEM/WB on the **response-acceptance rising edge with its matching destination and load control**, preventing previously stale read data from being attributed to a new load. EX/MEM retains an outstanding request; the front stages hold until completion, including the response edge. The pipeline deliberately adds one bubble after each memory operation so dependent EX can forward from MEM/WB on resumption. A frozen ID/EX operand is refreshed if an older instruction retires during the hold. The memory model accepts requests via `req_valid/req_ready` and responds after `DATA_LATENCY + bounded deterministic extra` cycles; see [memory protocol](memory_protocol.md) for timing, store commit and exact assumptions.

## Supported instruction subset

| Class | Confirmed operations |
| --- | --- |
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| I-type ALU | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| Memory | LB, LBU, LH, LHU, LW, SB, SH, SW — supported alignment only |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Control | JAL, JALR |
| Upper immediate | LUI, AUIPC |

Unsupported encodings are **not guaranteed** to trap or behave as a complete ISA requires. Memory is initialized by testbenches. Invalid data address bounds or alignment now abort simulation explicitly, but no architectural trap path exists. Instruction fetch still has no full address-bound verification.

## Tests and reproducibility

```sh
bash scripts/run_regression.sh /tmp/rv32i-evidence
```

`tb/tb_integrated_rv32i.sv` exercises four separately reset, self-checking programs:

1. Arithmetic, R/I operations, sign extension, immediate zero, EX/MEM-vs-MEM/WB forwarding priority, x0 behaviour.
2. LW/SW and RAW: immediate load-use stall, load→store, store forwarding, distinct word addresses, negative S-type offset and load data pairing.
3. All six signed/unsigned branch conditions, backward loop, taken/not-taken paths, flush that prevents wrong-path register writes and stores.
4. Load immediately followed by a taken branch and a subsequent dependent load/store sequence.

After each program, the bench compares all 32 architectural registers and all 1,024 data-memory words against independently specified expected values, exits nonzero on mismatch, bounds execution time, and records actual stall/redirect events. The additional `tb/tb_controlflow_rv32i.sv` checks LUI, AUIPC, JAL/JALR link/target, offset/align handling and wrong-path suppression. It ends at a known self-loop and checks PC plus registers.

The three pre-existing standalone benches continue to run against their respective `rtl/alu.sv`, `rtl/register_file.sv`, and `rtl/control_unit.sv`. They are not a substitute for architectural integration tests. The older print-only `tb/branch_tb.sv` and `tb/full_pipeline_tb.sv` are not included in the claimed regression.

The expanded [coverage matrix](coverage_matrix.md) documents six new memory/hazard programs across six fixed/variable-latency configurations (36 runs × 1,056 state comparisons), twelve deterministically seeded random-program runs interpreted independently by Python (12 × 1,056 comparisons), and four negative tests that must fail on invalid data accesses. Exact accepted-request, response and store cardinalities are asserted; a real request/response VCD is generated by the runner.

## Remaining engineering work

- Byte/halfword accesses are supported for correct alignments. No architectural misalignment or access-fault trap/recovery; invalid requests terminate simulation, not hardware.
- No external instruction/data bus or independent response backpressure. The internal memory model controls bounded wait states, but is not an SRAM macro or cache interface.
- No CSR, exceptions, interrupts, privilege modes, atomics, `FENCE`, `ECALL`, `EBREAK` or full illegal-instruction validation.
- No reference ISA compliance suite, exhaustive formal proof, synthesis or FPGA experiment.
- Other legacy tops in this repository have different/incomplete interfaces and are not included in this build.

Passing directed simulations demonstrates **tested architectural behaviour**, not production-ready hardware or exhaustive correctness.
