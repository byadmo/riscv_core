riscv_core — Single-cycle RV32I baseline

This repository contains a Phase-1 single-cycle RV32I CPU skeleton for educational and verification purposes.

Quickstart (Icarus Verilog)
- Install iverilog/vvp and GTKWave (on Windows, use Chocolatey or WSL)

Build & run simulation:

    iverilog -g2012 -o tb_cpu.vvp tb/tb_cpu.sv src/*.sv
    vvp tb_cpu.vvp
    gtkwave wave.vcd

Files added in this phase
- src/cpu.sv: top-level single-cycle CPU wiring
- src/pc.sv, src/imem.sv, src/regfile.sv, src/branch_adder.sv, src/dmem.sv
- tb/tb_cpu.sv: simple testbench (produces wave.vcd)
- imem.hex: small instruction image used by imem.sv

Notes
- The testbench writes wave.vcd for use with GTKWave.
- The code is intentionally minimal for clarity. Next steps: expand instruction tests, add pipeline registers, hazard unit, forwarding, and a richer test suite.
