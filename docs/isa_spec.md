# RV32I ISA Specification

## Scope

This core targets the RV32I base integer instruction set for a 32-bit single-clock-domain pipelined implementation. The initial implementation focus is a practical subset needed to bring up the existing datapath and verification loop, then expand toward full RV32I compliance.

## Architectural State

- Integer registers: 32 registers, `x0` through `x31`.
- Register width: 32 bits.
- `x0`: hardwired to zero; writes to `x0` are ignored.
- Program counter: 32-bit byte address.
- Memory model: instruction and data memories are modeled separately for FPGA-friendly bring-up.

## Instruction Formats

RV32I uses six base instruction encodings:

| Format | Primary Use | Fields |
| --- | --- | --- |
| R-type | register-register ALU operations | `funct7`, `rs2`, `rs1`, `funct3`, `rd`, `opcode` |
| I-type | immediates, loads, `JALR` | `imm[11:0]`, `rs1`, `funct3`, `rd`, `opcode` |
| S-type | stores | `imm[11:5]`, `rs2`, `rs1`, `funct3`, `imm[4:0]`, `opcode` |
| B-type | conditional branches | `imm[12|10:5]`, `rs2`, `rs1`, `funct3`, `imm[4:1|11]`, `opcode` |
| U-type | upper immediates | `imm[31:12]`, `rd`, `opcode` |
| J-type | `JAL` | `imm[20|10:1|11|19:12]`, `rd`, `opcode` |

## Initial Bring-Up Instruction Subset

The first verification target is:

| Instruction | Type | Operation |
| --- | --- | --- |
| `ADD` | R | `rd = rs1 + rs2` |
| `SUB` | R | `rd = rs1 - rs2` |
| `XOR` | R | `rd = rs1 ^ rs2` |
| `SLL` | R | `rd = rs1 << rs2[4:0]` |
| `ADDI` | I | `rd = rs1 + imm` |
| `LW` | I | `rd = mem[rs1 + imm]` |
| `SW` | S | `mem[rs1 + imm] = rs2` |
| `BEQ` | B | branch when `rs1 == rs2` |

## Pipeline Architecture

The baseline core uses a standard 5-stage in-order pipeline:

```text
        +-----+     +-----+     +-----+     +-----+     +-----+
PC ---> | IF  | --> | ID  | --> | EX  | --> | MEM | --> | WB  |
        +-----+     +-----+     +-----+     +-----+     +-----+
           |           |           |           |           |
           v           v           v           v           v
        imem      regfile/      ALU/       data mem    regfile
                  decode      branch calc              writeback
```

Pipeline registers:

- `IF/ID`: program counter and fetched instruction.
- `ID/EX`: decoded controls, register operands, immediates, source/destination register IDs.
- `EX/MEM`: ALU result, store data, branch decision, destination register ID, memory controls.
- `MEM/WB`: memory read data, ALU result, destination register ID, writeback controls.

## Control And Hazards

The initial control unit decodes opcode, `funct3`, and `funct7` into ALU, memory, branch, and writeback controls. Hazard support should include:

- Data forwarding from EX/MEM and MEM/WB to EX-stage operands.
- Load-use stall when a dependent instruction immediately follows a load.
- Control hazard handling by flushing younger instructions on a taken branch.

Branch prediction is not part of the baseline. Any move to prediction requires a proposal in `design_proposals.md` and explicit go-ahead.

## Verification Plan

Each synthesizable module should have a self-checking testbench. Phase 1 verification smoke targets are:

- ALU operation checks for `ADD`, `XOR`, and `SLL`.
- Register file checks for write/read behavior and `x0` hardwire behavior.
- Decode checks for R-type, I-type, load/store, and branch controls.
- Pipeline-level directed tests for stalls, forwarding, and branch flushes.


## Implementation status
Implemented subset: ADD,SUB,XOR,SLL,ADDI,LW,SW,BEQ. RTL and basic testbenches added.

