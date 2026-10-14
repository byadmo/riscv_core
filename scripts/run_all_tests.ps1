# Fail-closed PowerShell entry point for the verified RTL regression matrix.
# Run from any working directory; requires Icarus, Python 3 and a Bash shell
# (Git Bash on Windows or an equivalent shell with the same toolchain on PATH).
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Use a fresh output folder on each run. Concurrent invocations must not
# overwrite each other's binaries, and a failed log write must never leave
# a stale PASS summary available from an earlier successful run.
$output = Join-Path ([System.IO.Path]::GetTempPath()) (
    'rv32i-windows-regression-' + [guid]::NewGuid().ToString('N'))

foreach ($tool in @('iverilog', 'vvp', 'python3', 'bash')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' not found. Install Icarus Verilog, Python 3 and Git Bash before running RTL tests."
    }
}

New-Item -ItemType Directory -Path $output | Out-Null

# Bash accepts POSIX paths. Git Bash ships cygpath for translating native
# PowerShell Windows paths; fail if a reliable conversion is unavailable.
$bashScript = Join-Path $root 'scripts/run_regression.sh'
$bashOutput = Join-Path $output 'full'
if ($env:OS -eq 'Windows_NT') {
    # Git Bash may provide cygpath inside its own PATH, even when native
    # PowerShell cannot resolve cygpath directly. Its single-quoted string
    # passes the inner Bash double quotes as-is; do not backslash-escape them.
    $bashScript = (& bash -c 'cygpath -u "$1"' -- $bashScript).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashScript)) {
        throw "Git Bash cygpath could not convert the regression script path."
    }
    $bashOutput = (& bash -c 'cygpath -u "$1"' -- $bashOutput).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bashOutput)) {
        throw "Git Bash cygpath could not convert the regression output path."
    }
    # Check both paths *inside Bash* before starting simulations. This also
    # catches accidental literal quote characters from incorrect -c quoting,
    # including when the repository or temporary directory contains spaces.
    & bash -c 'test -f "$1" && test -d "$(dirname "$2")"' -- $bashScript $bashOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Converted regression paths are not accessible to Git Bash."
    }
}

# Explicit top selection ensures no unrelated historical testbench can run
# instead of the architectural integration test. The full Bash runner below
# also uses -s for every standalone/integrated/fault test it compiles.
$top = 'tb_integrated_rv32i'
$sources = @(
    'rtl/pipeline_core.sv', 'rtl/latency_data_memory.sv',
    'rtl/alu.sv', 'rtl/control_unit.sv', 'rtl/regfile.sv',
    'tb/tb_integrated_rv32i.sv'
) | ForEach-Object { Join-Path $root $_ }
$smokeBinary = Join-Path $output 'windows_integrated.vvp'
$backendArgs = @()
if (-not [string]::IsNullOrWhiteSpace($env:IVERILOG_BACKEND)) {
    # Match the maintained Bash regression scripts when Icarus is supplied
    # from an isolated toolchain instead of a system-wide installation.
    $backendArgs = @('-B' + $env:IVERILOG_BACKEND)
}
# Windows PowerShell 5 reports native stderr as an ErrorRecord when preference
# is Stop. Use explicit process exit codes and PASS markers as the gate.
$ErrorActionPreference = 'Continue'
& iverilog @backendArgs -g2012 -s $top -o $smokeBinary @sources
if ($LASTEXITCODE -ne 0) {
    throw "Icarus compilation failed for top $top (exit $LASTEXITCODE)."
}

$smokeLog = Join-Path $output 'windows_integrated.log'
& vvp $smokeBinary 2>&1 | Tee-Object -ErrorAction Stop -FilePath $smokeLog
if ($LASTEXITCODE -ne 0) {
    throw "Icarus simulation failed for top $top (exit $LASTEXITCODE)."
}
if (-not (Select-String -Path $smokeLog -Pattern '^PASS ALL: 4 integrated RV32I programs, 4224 architectural state checks$' -Quiet)) {
    throw "Architectural PASS summary missing from $smokeLog."
}

# The maintained Bash entry point contains the full directed, memory, Python
# oracle, external-port, fault-halt, fetch-boundary and priority matrices.
# Never accept a zero exit alone as evidence: require the end-of-run marker.
$fullLog = Join-Path $output 'windows_full.log'
& bash $bashScript $bashOutput 2>&1 |
    Tee-Object -ErrorAction Stop -FilePath $fullLog
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    throw "Full RTL regression failed (exit $LASTEXITCODE); inspect $fullLog."
}
$required = @(
    '^PASS FAULT_HALT matrix: 6 configurations, 90 scenarios',
    '^PASS fetch-range FAULT_HALT=1 matrix: 6 configurations, 72 cases',
    '^PASS fault-priority regression:',
    '^Evidence and logs:'
)
foreach ($marker in $required) {
    if (-not (Select-String -Path $fullLog -Pattern $marker -Quiet)) {
        throw "Full RTL regression summary missing ($marker); inspect $fullLog."
    }
}
Write-Output "PASS Windows RTL entrypoint: explicit $top and complete regression matrix. Logs: $output"
