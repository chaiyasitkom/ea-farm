# run-chaos.ps1 -- live-chart MT5 chaos gate for SPEC-016 layer A
#
# Usage: powershell -ExecutionPolicy Bypass -File tools\run-chaos.ps1 [-Slow]
#
# This intentionally runs the live-chart tests with EA_FARM_LIVE_MT5=1 so the
# default unittest skip marker cannot turn the suite green without exercising MT5.

param(
    [switch]$Slow
)

$ErrorActionPreference = 'Stop'

$Repo = "D:\ea-farm"
Push-Location $Repo
try {
    $env:EA_FARM_LIVE_MT5 = "1"
    if (-not $env:EA_FARM_CHAOS_PORT) {
        $env:EA_FARM_CHAOS_PORT = "45001"
    }
    if ($Slow) {
        $env:EA_FARM_LIVE_MT5_SLOW = "1"
    } else {
        Remove-Item Env:\EA_FARM_LIVE_MT5_SLOW -ErrorAction SilentlyContinue
    }

    $suite = "tests.chaos.test_wire_resilience.LiveChartChaosTests"
    Write-Output "CHAOS GATE -- suite=$suite slow=$($Slow.IsPresent) port=$env:EA_FARM_CHAOS_PORT"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "python"
    $psi.Arguments = "-m unittest $suite"
    $psi.WorkingDirectory = $Repo
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $text = $stdout + $stderr
    Write-Output $text

    if ($text -match "skipped=(\d+)") {
        $skipped = [int]$Matches[1]
    } else {
        $skipped = 0
    }

    if ($code -ne 0) {
        Write-Output "CHAOS GATE: FAILED -- unittest exit=$code skipped=$skipped"
        exit $code
    }

    if (-not $Slow -and $skipped -ne 1) {
        Write-Output "CHAOS GATE: FAILED -- fast gate expected exactly 1 slow-test skip, got skipped=$skipped"
        exit 1
    }

    if ($Slow -and $skipped -ne 0) {
        Write-Output "CHAOS GATE: FAILED -- slow gate expected no skips, got skipped=$skipped"
        exit 1
    }

    Write-Output "CHAOS GATE: PASSED -- skipped=$skipped"
    exit 0
}
finally {
    Pop-Location
}
