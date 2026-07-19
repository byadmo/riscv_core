# Status Report

## 2026-07-19

- Workspace initialized against GitHub repository `byadmo/riscv_core`.
- Confirmed existing project directories: `rtl/`, `tb/`, `sim/`, and `src/`.
- Created `docs/` for project documentation.
- Added `project_roadmap.md` with the four-phase roadmap.
- Added `docs/agent_operating_instructions.md` with operating workflow and engineering constraints.
- Completed Phase 1 draft: `docs/isa_spec.md` defines the RV32I baseline, 5-stage pipeline, initial instruction subset, control/hazard plan, and verification targets.
- Completed ALU verification update: `tb/tb_alu.sv` is now self-checking for ADD, SUB, XOR, SLL, AND, OR, SRL, SRA, SLT, SLTU, and zero flag behavior.
- Completed Register File verification update: `tb/tb_register_file.sv` checks reset behavior, basic writes/reads, disabled writes, and hardwired `x0`.
- Completed Control Unit verification update: `tb/tb_control_unit.sv` checks decode controls for ADD, SUB, XOR, SLL, ADDI, LW, SW, BEQ, and default illegal opcode handling.

## Current Phase

Phase 2: Core RTL Implementation and module-level verification.

## Next Priority

Install or configure a SystemVerilog simulator, then run the ALU, register-file, and control-unit testbenches. After simulation passes, review the top-level pipeline integration and add explicit pipeline register modules.
