<#
.SYNOPSIS
    Build and run the AXI4 testbenches with Icarus Verilog.

.DESCRIPTION
      slave : the slave on its own, driven channel by channel by the testbench
      top   : master + D flip-flop stages + slave; the master runs by itself
    Logs and waveforms go to .\build.  Exits with 1 if anything fails.

.EXAMPLE
    .\run_tests.ps1
    .\run_tests.ps1 -Suite top -Wave
#>

[CmdletBinding()]
param(
    [ValidateSet('slave', 'top', 'all')]
    [string]$Suite = 'all',
    [switch]$Wave
)

$ErrorActionPreference = 'Stop'
$root  = $PSScriptRoot
$rtl   = Join-Path $root 'rtl'
$sim   = Join-Path $root 'sim'
$build = Join-Path $root 'build'
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Path $build | Out-Null }

$suites = @{
    'slave' = @{
        Sources = @((Join-Path $rtl 'axi4_slave.v'), (Join-Path $sim 'tb_axi4_slave.v'))
        Out     = 'tb_axi4_slave'
        Label   = 'the slave on its own'
    }
    'top' = @{
        Sources = @((Join-Path $rtl 'axi4_reg_stage.v'), (Join-Path $rtl 'axi4_slave.v'),
                    (Join-Path $rtl 'axi4_master.v'),    (Join-Path $rtl 'axi4_top.v'),
                    (Join-Path $sim 'tb_axi4_top.v'))
        Out     = 'tb_axi4_top'
        Label   = 'master + D flip-flop stages + slave'
    }
}

if ($Suite -eq 'all') { $order = @('slave', 'top') } else { $order = @($Suite) }
$results = @()

foreach ($name in $order) {
    $s   = $suites[$name]
    $vvp = Join-Path $build "$($s.Out).vvp"

    Write-Host ""
    Write-Host "=== $name : $($s.Label) ===" -ForegroundColor Cyan

    $ivArgs = @('-g2005', '-Wall', '-o', $vvp) + $s.Sources
    & iverilog @ivArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  COMPILE FAILED" -ForegroundColor Red
        $results += [pscustomobject]@{ Suite = $name; Result = 'COMPILE FAILED' }
        continue
    }

    Push-Location $build
    try   { $out = & vvp $vvp 2>&1 }
    finally { Pop-Location }

    $out | Out-File -FilePath (Join-Path $build "$($s.Out).log") -Encoding utf8
    $out | ForEach-Object { Write-Host $_ }

    $text = $out -join "`n"
    if     ($text -match 'TEST PASSED') { $verdict = 'PASSED' }
    elseif ($text -match 'TEST FAILED') { $verdict = 'FAILED' }
    else                                { $verdict = 'NO VERDICT' }
    $results += [pscustomobject]@{ Suite = $name; Result = $verdict }
}

Write-Host ""
Write-Host "================ summary ================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Result -eq 'PASSED') { 'Green' } else { 'Red' }
    Write-Host ("  {0,-8} {1}" -f $r.Suite, $r.Result) -ForegroundColor $color
}

if ($Wave) {
    $vcd = Join-Path $build "$($suites[$order[-1]].Out).vcd"
    if (Test-Path $vcd) { Start-Process gtkwave -ArgumentList $vcd }
}

if ($results | Where-Object { $_.Result -ne 'PASSED' }) { exit 1 }
exit 0
