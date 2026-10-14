# Supported instruction and hazard coverage — October 2026

This table reports **tested behaviour**, not exhaustive formal coverage or an official ISA compliance-suite result.

| Feature | Status | Test evidence |
| --- | --- | --- |
| ADD/SUB, AND/OR/XOR, SLL/SRL/SRA, SLT/SLTU | Directed + randomized | `tb_integrated_rv32i.sv`, Python sequential oracle |
| ADDI/ANDI/ORI/XORI, SLLI/SRLI/SRAI, SLTI/SLTIU | Directed; mixed random subset | Integrated program 1, randomized oracle generator |
| LB/LBU/LH/LHU/LW | Directed + randomized | Signed/unsigned lanes, repeated and consecutive loads, response delays |
| SB/SH/SW | Directed + randomized | Byte enables, read-after-store, repeated stores, exact request/response/store counts |
| BEQ/BNE/BLT/BGE/BLTU/BGEU | Directed; selected random | Six branch conditions and negative offsets, wrong-path stores |
| JAL/JALR | Directed JAL/JALR; randomized JAL | Separate link/align/redirect program; random forward JAL |
| LUI/AUIPC | Directed | Separate control-flow program |
| Load-use, load-to-store, load-to-branch, nonzero memory base | Directed + randomized | Six memory scenarios; random accesses include positive/negative offsets from x25 |
| EX/MEM before MEM/WB, WB/ID and held-ID/EX refresh | Directed; exercised randomly | Baseline forwarding program, latency stress |
| Memory latency, single outstanding and store exactly once | Directed + deterministic variation | `DATA_LATENCY=1,2,4`, `DATA_MAX_EXTRA=0,3`; cardinality assertions |
| Reset cancels pending store | Directed | Reset during a pending store and fresh post-reset program |
| Invalid data alignment or addresses outside 0..4095 (default `FAULT_HALT=0`) | Explicitly rejected in simulation | Four negative expected-$fatal cases |
| CSR, privileged ISA, exceptions, interrupts, `ECALL`, `EBREAK`, `FENCE` | **Unsupported** | No trap/CSR pipeline |
| Unsupported/illegal encoding detection | Opt-in `FAULT_HALT=1` for implemented RV32I subset | Legacy fault suite checks reserved shift upper bits/load width; separate priority suite tests reserved R-type `funct7`, branch/JALR controls and other encodings; not full ISA compliance |
| Instruction stalls in internal mode / cache misses | **Unsupported in `EXTERNAL_PORTS=0`** | Internal instruction array is zero-wait; independent external I-channel stalls are covered below |
| Multiple outstanding or reordered responses | **Unsupported in either mode** | At most one outstanding transaction per external I/D channel |
| Response backpressure in internal mode / AXI | **Unsupported in `EXTERNAL_PORTS=0`** | Internal D response is consumed immediately; external I/D `rsp_ready` and held responses are covered below; AXI is not implemented |
| Formal verification, timing closure, area/power, FPGA | **Not measured** | No synthesis or physical implementation claim |

The directed architectural testbench checks all 32 registers and 1,024 memory words **per case**: 36 runs × 1,056 checks = 38,016. The randomized, separately interpreted benchmark runs 3 seeded instruction programs across four latency configurations: 12 × 1,056 = 12,672. The pre-existing four-program integration regression contributes another 4,224 state comparisons, with separate control-flow and standalone tests. Counts describe executed test comparisons, **not code or ISA coverage percentages**.

## Independent external instruction/data interfaces

`pipeline_core #(.EXTERNAL_PORTS(1))` is additionally verified with
`tb/dual_port_bus_adapter.sv` and `tb/tb_external_bus_rv32i.sv` using
`bash scripts/run_external_regression.sh`.

| Scenario | Evidence |
| --- | --- |
| Independent I and D accepted requests, delayed responses | Six I/D timing/throttle and CPU-response-hold configurations |
| Independent request backpressure and response backpressure | Separate valid/ready stable-payload monitors; observed I and D waiting/holding counters |
| Branch redirect with obsolete instruction fetch | Taken branches, wrong-path stores/loads and register-write checks; explicit stale response discard |
| Tag identity on I and D | I response PC/tag checking, D tag checking; 2 intentionally corrupted-tag tests **must** fail |
| 8-bit fetch epoch rollover | A 300-iteration backward branch loop and 301-instruction sequential program |
| Instruction vs data tag semantics | I tag is a redirect/fault **fetch epoch** and may repeat across consecutive PCs; D tag increments per accepted D transaction |
| Reset during outstanding external memory store | Cancel adapter's pending request with synchronous reset; restart and assert RAM contents |
| Reset during unaccepted, pending and held external I transactions | Separate `tb_external_i_reset.sv`: three actually observed pre-reset I-channel states, coordinated core/adapter reset and fresh-program contamination checks, in `FAULT_HALT=0/1` |
| Byte/halfword/word semantics with external RAM | Mixed access, sign extension and masked store programs |
| Independent architectural interpreter | Three seeded Python programs × four I/D timing configs = 12 runs |
| Request/response cardinality and stores | Asserted per-program transaction counts; bounded outstanding transactions |

The new external directed suite executes **7 scenarios × 6 timing configurations = 42 program runs**, checking all 32 integer registers and 1,024 data-memory words per run (**44,352 state comparisons**). The external independently interpreted suite executes **3 seeds × 4 configurations = 12 runs** with **12,672 comparisons**, plus two expected identity-fault rejections. These are *additional* to the previous 38,016 directed internal-latency comparisons and 12,672 internal-reference comparisons. These counts are not formal coverage metrics.

The independent `scripts/run_external_i_reset_regression.sh` adds **3 I-channel cancellation states × 2 external bus timing configurations × 2 fault modes = 12 targeted reset runs**. It checks concrete held/queued/accepted states before reset, absence of outstanding transfers after shared reset, fresh program register results and an unaffected data-memory sentinel. This targeted suite is **not** counted as 1,056 complete-state comparisons per run and does not change the historical 42/12 external or 90/72/72 fault-suite totals.

Not verified: zero-cycle external response, independent reset domains, response reordering, multiple outstanding requests on a channel, external instruction/data coherence under self-modifying code, ISA exception/trap recovery, privileged/system instructions, hardware synthesis or physical timing.

## Precise fault-stop diagnostics (new opt-in suite)

`pipeline_core #(.FAULT_HALT(1))` exposes sticky `fault_valid/fault_cause/fault_pc/fault_tval` and halts after synchronously detecting a supported fault in EX. The core does **not** implement trap handlers, CSRs or privilege. See [`docs/fault_halt.md`](fault_halt.md).

| Scenario | Test evidence |
| --- | --- |
| Illegal opcode, reserved shift-immediate upper bits and load-width encodings | Historical `tb_fault_halt.sv`: cause `2`, exact PC/instruction word, no younger commits; reserved R-type encodings are independently exercised below |
| Misaligned LH/LW/SH/SW | Causes `4` / `6` and exact effective address; invalid D request never issued |
| Modeled 4 KiB load/store out-of-range | Causes `5` / `7`; these are local range rejections, **not** external bus response errors |
| Misaligned taken BEQ, JAL and JALR targets | Cause `0`, exact target PC; faulting jump link write suppressed |
| Wrong-path invalid instructions and control transfers | Fault is suppressed after an older taken redirect |
| Older store and older load/writeback preceding illegal instruction | Exact one-time older effects, faulting/younger effects suppressed |
| Reset and sticky outputs | Cleared by reset, stable during halt; subsequent program starts normally |
| Legacy default compatibility | Four existing invalid memory accesses still terminate by expected `$fatal` |

The new runner executes **15 scenarios × 6 configurations = 90 programs**, including 72 deliberately faulting programs and 18 no-fault programs, comparing **32 registers + 1,024 modeled memory words per case = 95,040 state comparisons**. The six configurations include three internal data-memory latency modes and three externally timed dual-port modes with request acceptance/backpressure and CPU response holds. Four default-mode expected rejection tests are separate. These are repeated complete-state comparisons, **not** unique instruction coverage or formal proof.

## Additional adversarial fault priority and retirement

`tb/tb_fault_priority.sv` and `scripts/run_fault_priority_regression.sh` execute **18 scenarios × 4 timing configurations = 72 separately counted cases**, with **76,032 register/memory state comparisons**. Fifteen cases challenge negative effective addresses, simultaneous alignment/range violations, 4 KiB data-memory boundaries, unsupported R-type `funct7` (including M-extension MUL), reserved branch/JALR encodings and reserved load/store widths. Three further cases exercise older delayed store completion, delayed load plus dependent ALU retirement, and final older ALU writeback after `fault_valid` first becomes visible in the internal pipeline. Every case checks precise cause/PC/tval, sticky status, all 32 registers, all 1,024 data words, transaction counts, and no younger effects. External variants use independent delayed I/D channels, enforce held D-response stability and require **observed** response holds when configured to force them. These checks add no cases to the preceding 90-case fault suite or the 72-case fetch suite.

## Modeled instruction-fetch boundary and redirect ordering

With `FAULT_HALT=1`, an instruction PC beyond the local 4 KiB instruction store is reported as cause `1` with `fault_pc=fault_tval` set to the rejected byte PC, **without aliasing the internal ROM or sending an out-of-range external request**. A fetch-fault token propagates in instruction age order; an older taken redirect can squash it. The new independent `tb/tb_fetch_fault.sv` and `scripts/run_fetch_fault_regression.sh` check sequential crossing, redirected speculative crossing, jump-link retirement, prior data effects, reset and both internal/external timing modes.

The separate fetch-boundary suite has **12 scenarios × 6 timing modes = 72 runs**: 48 fault outcomes and 24 valid/after-reset results, each checking 32 registers and 1,024 modeled data-memory words (**76,032 complete-state comparisons**). Its negative I-request monitor checks *offered* rather than only accepted invalid external fetches; protocol monitors enforce held I/D request and response payload stability. The runner also requires actually observed external I/D response holds, captures a real waveform and repeats four legacy `$fatal` negative cases and the older four-program integration test separately. No scenario or state checks from this new suite are added to historical 95,040 fault-stop, 57,024 external-port, or 50,688 internal-memory evidence totals. This is *local bounds checking only*, not support for physical bus-error responses or a privileged trap handler.
