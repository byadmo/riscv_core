# Opt-in precise fault-stop diagnostics

`pipeline_core #(.FAULT_HALT(1))` enables **architecturally ordered, sticky fault reporting and a halted pipeline**. This is a deliberately bounded verification feature for the educational RV32I subset, **not** a RISC-V machine-mode trap implementation. There are no trap-vector CSRs, privilege states, trap handler, `MRET`, interrupts or recovery path.

The following output ports report the first detected fault and retain their values until `rst_n` is asserted low:

| Output | Meaning |
| --- | --- |
| `fault_valid` | Sticky fault indicator; remains high until reset |
| `fault_cause[31:0]` | Numeric cause code drawn from the RISC-V synchronous exception cause list |
| `fault_pc[31:0]` | Byte PC of the **faulting** instruction, not the target or next PC |
| `fault_tval[31:0]` | Illegal instruction bits, bad control-flow target, invalid fetch PC or effective memory address |

**Supported diagnostics (`FAULT_HALT=1` only):**

| Cause | Condition | `fault_tval` |
| --- | --- | --- |
| `0` | Taken branch/JAL/JALR target not aligned to 4 bytes (IALIGN=32) | Masked control-flow target (JALR clears bit 0) |
| `1` | Instruction fetch beyond the **local modeled 4 KiB instruction address range** | Invalid instruction byte PC |
| `2` | Unsupported/illegal instruction encoding, including unsupported SYSTEM and FENCE instructions | Full 32-bit instruction word |
| `4` / `6` | Misaligned load / store | Effective byte address |
| `5` / `7` | Load / store outside the modeled local 4 KiB RAM | Effective byte address |

Illegal encoding checks validate supported opcodes, branch/load/store function bits, R-type `funct7` and shift-immediate upper bits. Fault causes `1`, `5` and `7` are specifically **modeled local memory address-range errors**, not feedback from an external bus. Both ports lack bus-error response bits. An aligned JAL/JALR targeting `0x00001000` may complete its link-register write, followed by a *separate younger* fetch-fault event at PC `0x00001000`; an unaligned taken target instead faults at the branch/jump instruction with cause `0`, without a link write.

## Ordering and containment

- Detection occurs when the faulting instruction reaches **EX**, after any older EX/MEM data transaction has completed. An earlier MEM/WB write may retire on the detection edge; an older non-memory EX/MEM write may retire on the subsequent edge.
- An out-of-range instruction fetch is **never issued on the external I port**. Instead, IF inserts a squashable synthetic fault token carrying the offending fetch PC through ID to EX; an older taken branch can discard the speculative token before it becomes architectural. A single pending token is injected, and no internal fetch uses aliased `pc[11:2]` for that fault. Older memory and register writes still retire once.
- A misaligned or out-of-range load/store is rejected **before** entering EX/MEM, so no faulting memory request or store side effect is issued in either internal or external mode.
- The faulting instruction and all younger pipeline work are discarded. JAL/JALR link-register writes are suppressed if their taken target is misaligned.
- PC advancement and new instruction decoding stop. An already-asserted but unaccepted external instruction request must **remain stable** until accepted, and its stale response may still be drained, because this interface has no cancellation handshake. No drained word is executed.
- `fault_valid`, `fault_cause`, `fault_pc` and `fault_tval` remain stable until reset. Reset restarts execution at PC 0 and clears these diagnostics. The existing external adapter's **shared reset** requirement still applies.

## Compatibility and exclusions

The default `FAULT_HALT=0` preserves the old pipeline behavior, including its expected simulation `$fatal` on misaligned/out-of-range **accepted** data requests. Existing regression programs and their historical counts remain independent from fault-halt testing.

There is **no** full ISA compliance, ECALL-from-M trap, breakpoint handler, CSR exception state (`mepc`/`mcause`/`mtvec`/`mtval`), externally reported instruction access fault, memory protection, privilege checking, independent reset domain, asynchronous external bus error, or guarantee of self-modifying-code coherence. Fetch fault `1` rejects only addresses outside the local 4 KiB teaching model; a peripheral or memory controller cannot report a physical fetch/bus fault to this CPU. Assertion `$fatal` for corrupted I/D transaction identity is an integration-protocol failure, **not** a CPU exception.

Run the dedicated self-checking regression with:

```sh
bash scripts/run_fault_halt_regression.sh /tmp/rv32i-fault-halt
```

The top-level `scripts/run_regression.sh` also runs this suite when enabled. Test results are repeatable simulation checks, not formal proof or silicon measurements.

For the separate instruction-boundary/age-order regression, use `bash scripts/run_fetch_fault_regression.sh /tmp/rv32i-fetch-fault`. This specifically verifies sequential fall-through out of the model, aligned jump links followed by younger fetch faults, and speculative invalid fetches squashed by older control transfers. Run both suites from `scripts/run_regression.sh` in CI.
