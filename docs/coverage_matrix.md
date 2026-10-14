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
| Invalid alignment or address >4 KiB | Explicitly rejected in simulation | Four negative expected-$fatal cases |
| CSR, privileged ISA, exceptions, interrupts, `ECALL`, `EBREAK`, `FENCE` | **Unsupported** | No trap/CSR pipeline |
| Complete instruction-encoding legality validation | **Unsupported** | Some illegal variants may be ignored; no compliance claim |
| Instruction bus stalls / cache misses | **Unsupported** | Instruction memory remains zero-wait |
| Multiple outstanding or reordered responses | **Unsupported** | Single-outstanding RAM model only |
| Independent response backpressure (`rsp_ready`), external AXI | **Unsupported** | Response consumed immediately |
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
| Reset during outstanding external memory store | Cancel adapter's pending request with synchronous reset; restart and assert RAM contents |
| Byte/halfword/word semantics with external RAM | Mixed access, sign extension and masked store programs |
| Independent architectural interpreter | Three seeded Python programs × four I/D timing configs = 12 runs |
| Request/response cardinality and stores | Asserted per-program transaction counts; bounded outstanding transactions |

The new external directed suite executes **7 scenarios × 6 timing configurations = 42 program runs**, checking all 32 integer registers and 1,024 data-memory words per run (**44,352 state comparisons**). The external independently interpreted suite executes **3 seeds × 4 configurations = 12 runs** with **12,672 comparisons**, plus two expected identity-fault rejections. These are *additional* to the previous 38,016 directed internal-latency comparisons and 12,672 internal-reference comparisons. These counts are not formal coverage metrics.

Not verified: zero-cycle external response, independent reset domains, response reordering, multiple outstanding requests on a channel, external instruction/data coherence under self-modifying code, ISA exception/trap recovery, privileged/system instructions, hardware synthesis or physical timing.
