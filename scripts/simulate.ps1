# Simulation helper: attempts to run iverilog or instructs next steps
param()
if (Get-Command iverilog -ErrorAction SilentlyContinue) {
    Write-Output "Running iverilog..."
    iverilog -g2012 -o sim.exe rtl/*.sv tb/*_tb.sv && vvp sim.exe
} else {
    Write-Output "No iverilog detected. Install Icarus Verilog or use Verilator. To run tests locally, run: iverilog -g2012 -o sim.exe rtl/*.sv tb/*_tb.sv; vvp sim.exe"
}
