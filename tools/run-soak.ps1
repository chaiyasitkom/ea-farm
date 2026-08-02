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

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $idx = $trimmed.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if (-not [Environment]::GetEnvironmentVariable($key, "Process")) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

function Get-EnvOrDefault {
    param([string]$Name, [string]$Default)
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

$DefaultRepo = "D:\ea-farm"
if ($env:EA_FARM_REPO) { $Repo = $env:EA_FARM_REPO } else { $Repo = $DefaultRepo }
Import-DotEnv (Join-Path $Repo ".env")
$Repo = Get-EnvOrDefault "EA_FARM_REPO" $DefaultRepo
Push-Location $Repo
try {
    Import-DotEnv (Join-Path $Repo ".env")
    python -c "import psutil" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "SOAK: ENVIRONMENT NOT READY -- psutil is required. Install with: python -m pip install -e .[dev]"
        exit 3
    }

    $env:EA_FARM_LIVE_MT5 = "1"
    $env:EA_FARM_LIVE_MT5_SLOW = "1"
    $env:EA_FARM_SOAK_PROFILE = $Profile

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
