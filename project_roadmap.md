Phase 1: ISA & Architecture Spec

Define the RV32I base integer instruction set.

Draft the block diagram for the 5-stage pipeline (IF, ID, EX, MEM, WB).

Phase 2: Core RTL Implementation

Implement the Register File and ALU.

Develop the Control Unit to handle instruction decoding and hazard detection.

Integrate pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB).

Phase 3: Verification

Build a self-checking testbench for each module.

Run behavioral simulations to verify instructions (ADD, XOR, SLL).

Debug pipeline stalls and data hazards.

Phase 4: Synthesis & FPGA Deployment

Create XDC constraints for your target FPGA.

Run synthesis and analyze timing reports to identify critical paths.
