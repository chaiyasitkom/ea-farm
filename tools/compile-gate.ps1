# compile-gate.ps1 -- MQL5 compile gate for ea-farm
#
# Usage: powershell -ExecutionPolicy Bypass -File compile-gate.ps1
#
# Compiles every MQL5 target in the project and prints a short summary that can
# be pasted straight back to Codex.
#
# NOTE: ASCII-only on purpose. Windows PowerShell 5.1 reads .ps1 as ANSI unless
# the file has a UTF-8 BOM, so non-ASCII comments corrupt the parser.
#
# Why it also checks .mqh coverage: MetaEditor cannot compile a .mqh on its own.
# Any .mqh that no compiled target includes has never been through the compiler
# at all, so it silently escapes the gate.

$ErrorActionPreference = 'Stop'

$MetaEditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$Repo       = "D:\ea-farm"
$IncRoot    = "$Repo\mt5-ea"
$LogDir     = Join-Path $env:TEMP "ea-farm-compile"

$Targets = @(
    "$Repo\mt5-ea\Experts\FarmExecutor.mq5",
    "$Repo\tests\mql5\TestWire.mq5",
    "$Repo\tests\mql5\TestBrokerTime.mq5"
)

if (-not (Test-Path $MetaEditor)) { Write-Output "FATAL: MetaEditor not found at $MetaEditor"; exit 2 }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$stamp    = (Get-Date).ToString("yyyyMMdd-HHmmss")
$totalErr = 0
$totalWarn = 0
$report   = New-Object System.Collections.Generic.List[string]

$report.Add("MQL5 COMPILE GATE -- $stamp")
$report.Add("")

foreach ($t in $Targets) {
    $name = Split-Path $t -Leaf
    if (-not (Test-Path $t)) {
        $report.Add("[SKIP] $name -- file not found")
        continue
    }

    $log = Join-Path $LogDir (($name -replace '\.mq5$','') + ".log")
    $ex5 = $t -replace '\.mq5$', '.ex5'
    Remove-Item $log -ErrorAction SilentlyContinue
    Remove-Item $ex5 -ErrorAction SilentlyContinue
    $a   = @("/compile:$t", "/inc:$IncRoot", "/log:$log")
    $p   = Start-Process -FilePath $MetaEditor -ArgumentList $a -Wait -PassThru -NoNewWindow

    if (-not (Test-Path $log)) {
        $report.Add("[FAIL] $name -- no log produced (exit $($p.ExitCode))")
        $totalErr++
        continue
    }

    $lines  = Get-Content $log -Encoding Unicode
    $result = $lines | Where-Object { $_ -match '^Result:' } | Select-Object -Last 1
    $diags  = $lines | Where-Object { $_ -match ':\s*(error|warning)\s' }

    if ($result -match 'Result:\s*(\d+)\s*error') {
        $e = [int]$Matches[1]
        $w = 0
        if ($result -match '(\d+)\s*warning') { $w = [int]$Matches[1] }
        $totalErr  += $e
        $totalWarn += $w
        if ($e -gt 0)      { $tag = "FAIL" }
        elseif ($w -gt 0)  { $tag = "WARN" }
        else               { $tag = " OK " }
        $report.Add("[$tag] $name -- $e errors, $w warnings")
        foreach ($d in $diags) { $report.Add("       $d") }
        if ($e -gt 0) {
            continue
        }
    } else {
        $report.Add("[FAIL] $name -- cannot parse result line: $result")
        $totalErr++
        foreach ($d in $diags) { $report.Add("       $d") }
        continue
    }

    if (Test-Path $ex5) {
        $report.Add("       -> " + (Split-Path $ex5 -Leaf) + " " + (Get-Item $ex5).Length + " bytes")
    } else {
        $report.Add("       -> no .ex5 produced")
        $totalErr++
    }
}

# --- coverage: is every .mqh reached by at least one compiled target? ---
$report.Add("")
$covered = @()
foreach ($t in $Targets) {
    $log = Join-Path $LogDir (((Split-Path $t -Leaf) -replace '\.mq5$','') + ".log")
    if (Test-Path $log) {
        foreach ($line in (Get-Content $log -Encoding Unicode)) {
            if ($line -match 'including\s+(.+\.mqh)\s*$') { $covered += $Matches[1].Trim() }
        }
    }
}
$allInc = @()
if (Test-Path "$IncRoot\Include") {
    $allInc = Get-ChildItem "$IncRoot\Include" -Recurse -Filter *.mqh
}
$uncovered = $allInc | Where-Object { $covered -notcontains $_.FullName }
if ($uncovered) {
    $report.Add("[FAIL] .mqh never seen by the compiler (no target includes them):")
    $totalErr += $uncovered.Count
    foreach ($u in $uncovered) { $report.Add("       $($u.FullName)") }
} else {
    $report.Add("[ OK ] all $($allInc.Count) .mqh files covered by a compiled target")
}

$report.Add("")
if ($totalErr -gt 0)       { $verdict = "GATE FAILED" }
elseif ($totalWarn -gt 0)  { $verdict = "GATE PASSED WITH WARNINGS" }
else                       { $verdict = "GATE PASSED" }
$report.Add("$verdict -- $totalErr errors, $totalWarn warnings total")

$out = $report -join "`n"
Write-Output $out
$out | Out-File -FilePath (Join-Path $LogDir "gate-$stamp.txt") -Encoding utf8

if ($totalErr -gt 0) { exit 1 } else { exit 0 }
