Status Report - initial

Phase 1: ISA & Architecture Spec - Complete (baseline RV32I subset documented in docs/isa_spec.md)
Phase 2: Core RTL Implementation - Implemented: regfile, ALU, control_unit, pipeline registers, core_top (baseline)
Phase 3: Verification - Testbenches added (regfile_tb, alu_tb, pipeline_tb). Run simulations using scripts/simulate.ps1
Phase 4: Synthesis & FPGA Deployment - Constraints placeholder added in fpga/constraints.xdc. XDC must be updated for target board.

Notes:
- All modules include simple self-checking tests where feasible. More directed tests and corner-case coverage recommended.
