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

function Fail-Env {
    param([string]$Message)
    Write-Output "CHAOS GATE: FAILED (ENV) -- $Message"
    exit 3
}

function Assert-PathExists {
    param([string]$Label, [string]$Path)
    if (-not (Test-Path $Path)) {
        Fail-Env "$Label not found: $Path"
    }
}

function Get-PortOwners {
    param([int]$Port)
    $owners = @()
    $pattern = "127.0.0.1:$Port"
    $lines = (& netstat -ano -p tcp) | Where-Object { $_ -match [regex]::Escape($pattern) }
    foreach ($line in $lines) {
        $parts = $line -split '\s+' | Where-Object { $_ }
        if ($parts.Count -ge 5) { $owners += $parts[-1] }
    }
    return ($owners | Select-Object -Unique)
}

function Assert-PortAvailable {
    param([int]$Port)
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse("127.0.0.1"), $Port)
        $listener.Start()
    } catch {
        $owners = @(Get-PortOwners $Port)
        $ownerText = if ($owners.Count -gt 0) { " pid=$($owners -join ',')" } else { " pid=unknown" }
        Fail-Env "port 127.0.0.1:$Port is not available;$ownerText"
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Assert-NoMt5Processes {
    $running = @(Get-Process terminal64, metaeditor64 -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        $details = ($running | ForEach-Object {
            $path = try { $_.Path } catch { "" }
            "name=$($_.ProcessName) pid=$($_.Id) path=$path"
        }) -join "; "
        Fail-Env "MT5 process already running: $details"
    }
}

function Stop-ProcessTree {
    param([int]$RootPid)
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$RootPid" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -RootPid ([int]$child.ProcessId)
    }
    Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
}

function Stop-GateChildren {
    param([int]$RootPid)
    Stop-ProcessTree -RootPid $RootPid
    foreach ($name in @("terminal64", "metaeditor64")) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-StreamingProcess {
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutMs
    )
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) "ea-farm-chaos-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $stdoutPath = Join-Path $tempDir "stdout.log"
    $stderrPath = Join-Path $tempDir "stderr.log"
    New-Item -ItemType File -Path $stdoutPath | Out-Null
    New-Item -ItemType File -Path $stderrPath | Out-Null
    $script:stdoutOffset = 0L
    $script:stderrOffset = 0L
    $proc = $null

    function Read-NewFileText {
        param([string]$Path, [long]$Offset)
        $fs = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            [void]$fs.Seek($Offset, [IO.SeekOrigin]::Begin)
            $reader = New-Object IO.StreamReader($fs)
            $text = $reader.ReadToEnd()
            return @{ Text = $text; Offset = $fs.Position }
        } finally {
            $fs.Dispose()
        }
    }

    function Write-NewOutput {
        $outChunk = Read-NewFileText -Path $stdoutPath -Offset $script:stdoutOffset
        $script:stdoutOffset = [long]$outChunk.Offset
        if ($outChunk.Text.Length -gt 0) {
            [Console]::Out.Write($outChunk.Text)
        }

        $errChunk = Read-NewFileText -Path $stderrPath -Offset $script:stderrOffset
        $script:stderrOffset = [long]$errChunk.Offset
        if ($errChunk.Text.Length -gt 0) {
            [Console]::Error.Write($errChunk.Text)
        }
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
        $command = "`"$FileName`" $Arguments 1> `"$stdoutPath`" 2> `"$stderrPath`""
        $psi.Arguments = "/d /s /c `"$command`""
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            Write-NewOutput
            if ($sw.ElapsedMilliseconds -ge $TimeoutMs) {
                Write-Output "CHAOS GATE: FAILED -- timeout after $([int]($TimeoutMs / 60000))m; killing child process tree"
                Stop-GateChildren -RootPid $proc.Id
                $proc.WaitForExit(10000) | Out-Null
                Write-NewOutput
                $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
                $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
                return @{ Code = 1; Text = "$stdout`n$stderr"; TimedOut = $true }
            }
            Start-Sleep -Milliseconds 200
        }
        $proc.WaitForExit()
        Write-NewOutput
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        return @{ Code = $proc.ExitCode; Text = "$stdout`n$stderr"; TimedOut = $false }
    } finally {
        if ($proc -and -not $proc.HasExited) { Stop-GateChildren -RootPid $proc.Id }
        if ($proc) { $proc.Dispose() }
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$DefaultRepo = "D:\ea-farm"
if ($env:EA_FARM_REPO) { $Repo = $env:EA_FARM_REPO } else { $Repo = $DefaultRepo }
Import-DotEnv (Join-Path $Repo ".env")
$Repo = Get-EnvOrDefault "EA_FARM_REPO" $DefaultRepo
Push-Location $Repo
try {
    $env:EA_FARM_LIVE_MT5 = "1"
    Import-DotEnv (Join-Path $Repo ".env")
    if (-not $env:EA_FARM_CHAOS_PORT) {
        $env:EA_FARM_CHAOS_PORT = "45001"
    }
    if ($Slow) {
        $env:EA_FARM_LIVE_MT5_SLOW = "1"
    } else {
        Remove-Item Env:\EA_FARM_LIVE_MT5_SLOW -ErrorAction SilentlyContinue
    }

    $terminal = Get-EnvOrDefault "EA_FARM_MT5_TERMINAL" "C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe"
    $metaeditor = Get-EnvOrDefault "EA_FARM_MT5_METAEDITOR" "C:\Program Files\IUX Markets MT5 Terminal3\metaeditor64.exe"
    $dataDir = Get-EnvOrDefault "EA_FARM_MT5_DATA_DIR" "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3"
    $port = [int]$env:EA_FARM_CHAOS_PORT
    Assert-PortAvailable $port
    Assert-NoMt5Processes
    Assert-PathExists "terminal64.exe" $terminal
    Assert-PathExists "metaeditor64.exe" $metaeditor
    Assert-PathExists "MT5 data dir" $dataDir

    $suite = "tests.chaos.test_wire_resilience.LiveChartChaosTests"
    $timeoutMs = if ($Slow) { 75 * 60 * 1000 } else { 15 * 60 * 1000 }
    Write-Output "CHAOS GATE -- suite=$suite slow=$($Slow.IsPresent) port=$env:EA_FARM_CHAOS_PORT timeout_min=$([int]($timeoutMs / 60000))"
    $result = Invoke-StreamingProcess -FileName "python" -Arguments "-m unittest -v $suite" -WorkingDirectory $Repo -TimeoutMs $timeoutMs
    $code = [int]$result.Code
    $text = [string]$result.Text

    if ($text -match "skipped=(\d+)") {
        $skipped = [int]$Matches[1]
    } else {
        Write-Output "CHAOS GATE: FAILED -- unittest summary missing skipped= count; output may be incomplete"
        exit 1
    }

    if ($code -ne 0) {
        Write-Output "CHAOS GATE: FAILED -- unittest exit=$code skipped=$skipped"
        exit $code
    }

    $requiredFast = @(
        "test_ea_reconnects_after_server_kill",
        "test_backoff_schedule_matches_spec",
        "test_bad_token_waits_60s",
        "test_ea_handles_duplicate_session_rejection",
        "test_heartbeat_gap_triggers_reconnect",
        "test_heartbeat_interval_within_5pct_over_5min"
    )
    $requiredSlow = @($requiredFast + "test_no_heartbeat_loss_over_1h")
    $required = if ($Slow) { $requiredSlow } else { $requiredFast }
    foreach ($name in $required) {
        if ($text -notmatch "(?m)^$([regex]::Escape($name))\s+\(") {
            Write-Output "CHAOS GATE: FAILED -- required test did not run: $name"
            exit 1
        }
    }

    if (-not $Slow -and $text -notmatch "(?m)^test_no_heartbeat_loss_over_1h\s+\(.*\)\s+\.\.\.\s+skipped") {
        Write-Output "CHAOS GATE: FAILED -- fast gate expected slow test to be reported as skipped"
        exit 1
    }

    if (-not $Slow -and $skipped -ne 1) {
        Write-Output "CHAOS GATE: FAILED -- fast gate expected exactly 1 slow-test skip, got skipped=$skipped"
        exit 1
    }

    if ($Slow -and $text -match "(?m)^\S+\s+\(.*\)\s+\.\.\.\s+skipped") {
        Write-Output "CHAOS GATE: FAILED -- slow gate expected no skipped tests"
        exit 1
    }

    Write-Output "CHAOS GATE: PASSED -- skipped=$skipped"
    exit 0
}
finally {
    Pop-Location
}
