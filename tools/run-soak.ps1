# run-soak.ps1 -- MT5 memory/handle soak harness for SPEC-067
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\run-soak.ps1 -Profile churn
#   powershell -ExecutionPolicy Bypass -File tools\run-soak.ps1 -Profile steady

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("churn", "steady")]
    [string]$Profile
)

$ErrorActionPreference = 'Stop'

$Repo = "D:\ea-farm"
Push-Location $Repo
try {
    python -c "import psutil" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "SOAK: ENVIRONMENT NOT READY -- psutil is required. Install with: python -m pip install -e .[dev]"
        exit 3
    }

    $env:EA_FARM_LIVE_MT5 = "1"
    $env:EA_FARM_LIVE_MT5_SLOW = "1"

    if ($Profile -eq "churn") {
        $suite = "tests.soak.test_memory_soak.MemorySoakTests.test_soak_churn_2h_no_handle_leak"
        Write-Output "SOAK -- profile=churn duration=2h"
        python -m unittest $suite
        exit $LASTEXITCODE
    }

    Write-Output "SOAK: ENVIRONMENT NOT READY -- steady 24h profile is intentionally not wired in this round"
    exit 3
}
finally {
    Pop-Location
}
