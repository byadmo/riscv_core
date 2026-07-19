# Run all SystemVerilog tests with Icarus Verilog
if (Get-Command iverilog -ErrorAction SilentlyContinue) {
    $tests = Get-ChildItem -Path tb -Filter "*_tb.sv" | ForEach-Object { $_.FullName }
    foreach ($t in $tests) {
        Write-Output "Compiling and running $t"
        iverilog -g2012 -o sim.exe rtl/*.sv tb/*.sv
        if ($LASTEXITCODE -ne 0) { Write-Output "Compilation failed for $t"; exit 1 }
        vvp sim.exe | Write-Output
    }
} else { Write-Output "Install Icarus Verilog (iverilog) to run tests locally." }