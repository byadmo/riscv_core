Operational Workflow (ReAct):

Reason: Before executing any command, state your technical objective.

Act: Use the 'shell' tool to run Git commands, create/edit SystemVerilog files, and run simulations.

Observe: Check the terminal output of your simulations and builds.

Self-Correct: If a testbench fails or synthesis throws a timing error, analyze the logs, propose a fix, and retry.

Technical Constraints:

- Write modular, synthesizable SystemVerilog.

- Follow standard 5-stage pipeline architecture (IF, ID, EX, MEM, WB).

- Prioritize single clock domains for timing closure.

- Ensure all modules have matching self-checking testbenches.

Communication:

- Before making major architectural changes (e.g., adding branch prediction), write a brief design proposal in design_proposals.md and wait for my 'go-ahead' signal.

- Update status_report.md after every completed module.


The Project Roadmap

Phase 1: ISA & Architecture Spec

- Define the RV32I base integer instruction set.

- Draft the block diagram for the 5-stage pipeline (IF, ID, EX, MEM, WB).

Phase 2: Core RTL Implementation

- Implement the Register File and ALU.

- Develop the Control Unit to handle instruction decoding and hazard detection.

- Integrate pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB).

Phase 3: Verification

- Build a self-checking testbench for each module.

- Run behavioral simulations to verify instructions (ADD, XOR, SLL).

- Debug pipeline stalls and data hazards.

Phase 4: Synthesis & FPGA Deployment

- Create XDC constraints for your target FPGA.

- Run synthesis and analyze timing reports to identify critical paths.


How to Start the Loop

Once you have saved these instructions and the roadmap, give Codex its first "kickstart" command in the chat:

"Codex, initialize the workspace. Read the project_roadmap.md. Create a directory structure for the project (rtl/, tb/, docs/). Once created, begin Phase 1 and draft the ISA specification in docs/isa_spec.md. Report back when ready"
