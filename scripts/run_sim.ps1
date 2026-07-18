# Run Verilog simulation (Windows PowerShell helper)
param(
    [string]$iverilog = "iverilog",
    [string]$vvp = "vvp"
)

Write-Host "Compiling..."
& $iverilog -g2012 -o tb_cpu.vvp tb/tb_cpu.sv src\*.sv
if ($LASTEXITCODE -ne 0) { Write-Error "iverilog failed"; exit $LASTEXITCODE }

Write-Host "Running simulation..."
& $vvp tb_cpu.vvp
