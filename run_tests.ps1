<#
.SYNOPSIS
    Build and run the AXI4 test suites with Icarus Verilog on Windows.

.DESCRIPTION
    Windows equivalent of the Makefile (which needs GNU make, tee and grep).
    Compiles each testbench into .\build and runs it, then reports a summary.
    Exits with code 1 if any suite fails, so it can be used in CI.

.PARAMETER Suite
    Which suite to run: slave, master, top, top_direct, or all (default).

.PARAMETER Wave
    After running, open that suite's .vcd in GTKWave.

.EXAMPLE
    .\run_tests.ps1
    .\run_tests.ps1 -Suite slave
    .\run_tests.ps1 -Suite top -Wave
#>

[CmdletBinding()]
param(
    [ValidateSet('slave', 'master', 'top', 'all')]
    [string]$Suite = 'all',

    [switch]$Wave
)

$ErrorActionPreference = 'Stop'

$root  = $PSScriptRoot
$rtl   = Join-Path $root 'rtl'
$sim   = Join-Path $root 'sim'
$build = Join-Path $root 'build'

if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build | Out-Null }

$rtlSrcs = @(
    (Join-Path $rtl 'axi4_slave.v'),
    (Join-Path $rtl 'axi4_master.v'),
    (Join-Path $rtl 'axi4_top.v')
)

# name = { sources, testbench top, extra iverilog args }
$suites = @{
    'slave'      = @{
        Sources = @((Join-Path $rtl 'axi4_slave.v'), (Join-Path $sim 'tb_axi4_slave.v'))
        Out     = 'tb_axi4_slave'
        Extra   = @()
        Label   = 'Level 1 : axi4_slave unit test'
    }
    'master'     = @{
        Sources = @((Join-Path $rtl 'axi4_master.v'), (Join-Path $sim 'tb_axi4_master.v'))
        Out     = 'tb_axi4_master'
        Extra   = @()
        Label   = 'Level 2 : axi4_master unit test (mock subordinate)'
    }
    'top'        = @{
        Sources = $rtlSrcs + @(Join-Path $sim 'tb_axi4_top.v')
        Out     = 'tb_axi4_top'
        Extra   = @()
        Label   = 'Level 3 : integration, manager wired to subordinate'
    }
}

if ($Suite -eq 'all') { $order = @('slave', 'master', 'top') }
else                  { $order = @($Suite) }

$results = @()

foreach ($name in $order) {
    $s   = $suites[$name]
    $vvp = Join-Path $build "$($s.Out).vvp"
    $log = Join-Path $build "$($s.Out).log"

    Write-Host ""
    Write-Host "=== $($s.Label) ===" -ForegroundColor Cyan

    # ---- compile ----------------------------------------------------------
    $ivArgs = @('-g2005', '-Wall') + $s.Extra + @('-o', $vvp) + $s.Sources
    & iverilog @ivArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  COMPILE FAILED" -ForegroundColor Red
        $results += [pscustomobject]@{ Suite = $name; Result = 'COMPILE FAILED' }
        continue
    }

    # ---- run (from $build so the .vcd lands there) ------------------------
    Push-Location $build
    try   { $out = & vvp $vvp 2>&1 }
    finally { Pop-Location }

    $out | Out-File -FilePath $log -Encoding utf8
    $out | ForEach-Object { Write-Host $_ }

    $text = $out -join "`n"
    if     ($text -match 'TEST PASSED') { $verdict = 'PASSED' }
    elseif ($text -match 'TEST FAILED') { $verdict = 'FAILED' }
    else                                { $verdict = 'NO VERDICT' }

    $results += [pscustomobject]@{ Suite = $name; Result = $verdict }
}

# ---- summary --------------------------------------------------------------
Write-Host ""
Write-Host "================ summary ================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Result -eq 'PASSED') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-12} {1}" -f $r.Suite, $r.Result) -ForegroundColor $color
}

if ($Wave) {
    $target = $order[-1]
    $vcd    = Join-Path $build "$(($suites[$target]).Out).vcd"
    if (Test-Path $vcd) {
        Write-Host ""
        Write-Host "opening $vcd in GTKWave" -ForegroundColor Cyan
        Start-Process gtkwave -ArgumentList $vcd
    } else {
        Write-Host "no waveform found at $vcd" -ForegroundColor Yellow
    }
}

if ($results | Where-Object { $_.Result -ne 'PASSED' }) { exit 1 }
exit 0
