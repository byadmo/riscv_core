# Status Report

## 2026-07-19

- Workspace initialized against GitHub repository `byadmo/riscv_core`.
- Confirmed existing project directories: `rtl/`, `tb/`, `sim/`, and `src/`.
- Created `docs/` for project documentation.
- Added `project_roadmap.md` with the four-phase roadmap.
- Added `docs/agent_operating_instructions.md` with operating workflow and engineering constraints.
- Completed Phase 1 draft: `docs/isa_spec.md` defines the RV32I baseline, 5-stage pipeline, initial instruction subset, control/hazard plan, and verification targets.

## Current Phase

Phase 1: ISA & Architecture Spec.

## Next Priority

Review the existing `rtl/` modules against `docs/isa_spec.md`, then update or add self-checking testbenches for the register file and ALU.
