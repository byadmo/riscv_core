# Opt-in precise fault-stop diagnostics

`pipeline_core #(.FAULT_HALT(1))` enables **architecturally ordered, sticky fault reporting and a halted pipeline**. This is a deliberately bounded verification feature for the educational RV32I subset, **not** a RISC-V machine-mode trap implementation. There are no trap-vector CSRs, privilege states, trap handler, `MRET`, interrupts or recovery path.

The following output ports report the first detected fault and retain their values until `rst_n` is asserted low:

| Output | Meaning |
| --- | --- |
| `fault_valid` | Sticky fault indicator; remains high until reset |
| `fault_cause[31:0]` | Numeric cause code drawn from the RISC-V synchronous exception cause list |
| `fault_pc[31:0]` | Byte PC of the **faulting** instruction, not the target or next PC |
| `fault_tval[31:0]` | Illegal instruction bits, bad control-flow target or effective memory address |

**Supported diagnostics (`FAULT_HALT=1` only):**

| Cause | Condition | `fault_tval` |
| --- | --- | --- |
| `0` | Taken branch/JAL/JALR target not aligned to 4 bytes (IALIGN=32) | Masked control-flow target (JALR clears bit 0) |
| `2` | Unsupported/illegal instruction encoding, including unsupported SYSTEM and FENCE instructions | Full 32-bit instruction word |
| `4` / `6` | Misaligned load / store | Effective byte address |
| `5` / `7` | Load / store outside the modeled local 4 KiB RAM | Effective byte address |

Illegal encoding checks validate supported opcodes, branch/load/store function bits, R-type `funct7` and shift-immediate upper bits. Fault causes `5` and `7` are specifically **modeled address-range errors**, not feedback from an external bus. The instruction/data interface has no bus error response bit.

## Ordering and containment

- Detection occurs when the faulting instruction reaches **EX**, after any older EX/MEM data transaction has completed. An earlier MEM/WB write may retire on the detection edge; an older non-memory EX/MEM write may retire on the subsequent edge.
- A misaligned or out-of-range load/store is rejected **before** entering EX/MEM, so no faulting memory request or store side effect is issued in either internal or external mode.
- The faulting instruction and all younger pipeline work are discarded. JAL/JALR link-register writes are suppressed if their taken target is misaligned.
- PC advancement and new instruction decoding stop. An already-asserted but unaccepted external instruction request must **remain stable** until accepted, and its stale response may still be drained, because this interface has no cancellation handshake. No drained word is executed.
- `fault_valid`, `fault_cause`, `fault_pc` and `fault_tval` remain stable until reset. Reset restarts execution at PC 0 and clears these diagnostics. The existing external adapter's **shared reset** requirement still applies.

## Compatibility and exclusions

The default `FAULT_HALT=0` preserves the old pipeline behavior, including its expected simulation `$fatal` on misaligned/out-of-range **accepted** data requests. Existing regression programs and their historical counts remain independent from fault-halt testing.

There is **no** full ISA compliance, ECALL-from-M trap, breakpoint handler, CSR exception state (`mepc`/`mcause`/`mtvec`/`mtval`), instruction access fault, memory protection, privilege checking, independent reset domain, asynchronous external bus error, or guarantee of self-modifying-code coherence. An instruction can also run past the fixed internal instruction array's modeled address space; this initial milestone does not provide complete instruction-fetch bounds/error reporting. Assertion `$fatal` for corrupted I/D transaction identity is an integration-protocol failure, **not** a CPU exception.

Run the dedicated self-checking regression with:

```sh
bash scripts/run_fault_halt_regression.sh /tmp/rv32i-fault-halt
```

The top-level `scripts/run_regression.sh` also runs this suite when enabled. Test results are repeatable simulation checks, not formal proof or silicon measurements.
