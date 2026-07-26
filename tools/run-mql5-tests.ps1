# run-mql5-tests.ps1 -- deploy + compile + run MQL5 test EAs headlessly
#
# Usage: powershell -ExecutionPolicy Bypass -File run-mql5-tests.ps1
#
# ASCII-only on purpose (PowerShell 5.1 reads .ps1 as ANSI without a BOM).
#
# Pipeline:
#   1. read current git HEAD
#   2. copy Include\Farm + the test EA source into the MT5 data folder
#   3. compile there with that terminal's MetaEditor
#   4. write a .set file injecting the git sha and the result filename
#   5. run terminal64.exe /config:<ini>  (Strategy Tester, headless, self-closing)
#   6. parse the JSON the EA wrote into Common\Files and check git_sha == HEAD
#
# HARD-WON FACTS (do not "simplify" these away):
#   * Compiling needs no account, but the STRATEGY TESTER does. Only the IUX
#     Terminal3 install has one (IUXMarkets-Demo). The vanilla
#     "C:\Program Files\MetaTrader 5" data folder has no account and no history,
#     so the tester cannot run there.
#   * Symbols on this broker carry a ".iux" suffix (EURUSD.iux, XAUUSD.iux).
#   * EURUSD.iux H1 history exists 2025.01.01 .. 2026.06.19 -- the tester date
#     range must sit inside that or the run aborts.
#   * .set string values must be plain "Name=value". The "||||N" optimization
#     suffix used for numeric params becomes PART OF THE STRING and produced
#     FileOpen error 5004 (invalid filename).
#   * An EA that calls ExpertRemove() inside OnInit makes the tester log
#     "tester stopped because OnInit failed" and terminal exit code stays 0.
#     => NEVER judge success by exit code. Only the result JSON counts.
#   * MQL5 has no FILE_UTF8 flag. Real UTF-8 requires
#     FILE_BIN + StringToCharArray(..., CP_UTF8). See tools\probe\TesterProbe.mq5.

$ErrorActionPreference = 'Stop'

$Repo       = "D:\ea-farm"
$Data       = "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3"
$Terminal   = "C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe"
$MetaEditor = "C:\Program Files\IUX Markets MT5 Terminal3\metaeditor64.exe"
$Common     = "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
$WorkDir    = Join-Path $env:TEMP "ea-farm-compile"

# suite name -> source path (relative to repo)
$Suites = @(
    @{ Name = "TestWire"; Source = "tests\mql5\TestWire.mq5" }
)

$TesterSymbol = "EURUSD.iux"
$TesterFrom   = "2026.06.02"
$TesterTo     = "2026.06.19"

foreach ($p in @($Terminal, $MetaEditor, $Data)) {
    if (-not (Test-Path $p)) { Write-Output "FATAL: not found -> $p"; exit 2 }
}
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

Push-Location $Repo
$sha = (& git rev-parse HEAD).Trim()
$dirty = (& git status --porcelain -- mt5-ea tests | Measure-Object).Count
Pop-Location

Write-Output "MQL5 TEST RUN -- HEAD=$($sha.Substring(0,7))"
if ($dirty -gt 0) { Write-Output "WARNING: $dirty uncommitted change(s) under mt5-ea/ or tests/ -- git_sha will not describe what actually ran" }
Write-Output ""

# ---- 1. deploy includes -------------------------------------------------
$incDst = Join-Path $Data "MQL5\Include\Farm"
if (-not (Test-Path $incDst)) { New-Item -ItemType Directory -Path $incDst -Force | Out-Null }
Copy-Item (Join-Path $Repo "mt5-ea\Include\Farm\*.mqh") $incDst -Force
Write-Output "[deploy] Include\Farm -> $incDst"

$expDst = Join-Path $Data "MQL5\Experts\FarmTests"
if (-not (Test-Path $expDst)) { New-Item -ItemType Directory -Path $expDst -Force | Out-Null }

$setDir = Join-Path $Data "MQL5\Profiles\Tester"
if (-not (Test-Path $setDir)) { New-Item -ItemType Directory -Path $setDir -Force | Out-Null }

$anyFail = $false

foreach ($s in $Suites) {
    $name = $s.Name
    $src  = Join-Path $Repo $s.Source
    Write-Output ""
    Write-Output "=== $name"

    if (-not (Test-Path $src)) { Write-Output "  [FAIL] source not found: $src"; $anyFail = $true; continue }

    Copy-Item $src (Join-Path $expDst "$name.mq5") -Force

    # ---- 2. compile in the data folder ---------------------------------
    $clog = Join-Path $WorkDir "$name-tester.log"
    $a = @("/compile:$expDst\$name.mq5", "/inc:$Data\MQL5", "/log:$clog")
    Start-Process -FilePath $MetaEditor -ArgumentList $a -Wait -NoNewWindow | Out-Null

    $result = $null
    if (Test-Path $clog) {
        $lines  = Get-Content $clog -Encoding Unicode
        $result = $lines | Where-Object { $_ -match '^Result:' } | Select-Object -Last 1
        foreach ($d in ($lines | Where-Object { $_ -match ':\s*(error|warning)\s' })) { Write-Output "  $d" }
    }
    Write-Output "  compile: $result"

    if (-not (Test-Path (Join-Path $expDst "$name.ex5"))) {
        Write-Output "  [FAIL] no .ex5 -- compile failed, cannot run tests"
        $anyFail = $true
        continue
    }

    # ---- 3. inject inputs ----------------------------------------------
    $resultFile = "ea-farm-$name-result.json"
    $setName    = "farm-$name.set"
    # plain Name=value -- see header note about the ||||N trap
    @(
        "InpTestGitSha=$sha",
        "InpTestResultFile=$resultFile"
    ) -join "`r`n" | Out-File -FilePath (Join-Path $setDir $setName) -Encoding ascii

    # ---- 4. run the tester ---------------------------------------------
    $ini = Join-Path $WorkDir "tester-$name.ini"
    @"
[Tester]
Expert=FarmTests\$name
ExpertParameters=$setName
Symbol=$TesterSymbol
Period=H1
Model=2
FromDate=$TesterFrom
ToDate=$TesterTo
Deposit=10000
Currency=USD
Leverage=1:500
Optimization=0
Visual=0
ShutdownTerminal=1
"@ | Out-File -FilePath $ini -Encoding ascii

    $resPath = Join-Path $Common $resultFile
    $t0 = Get-Date
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $Terminal -ArgumentList "/config:$ini" -Wait | Out-Null
    $sw.Stop()
    Write-Output "  tester ran ${[int]$sw.Elapsed.TotalSeconds}s (exit code deliberately ignored)"

    # ---- 5. parse the result -------------------------------------------
    if (-not (Test-Path $resPath)) {
        Write-Output "  [FAIL] no result file: $resPath"
        Write-Output "         (EA crashed before writing, or FileOpen failed -- check Tester\logs)"
        $anyFail = $true
        continue
    }
    $age = (Get-Item $resPath).LastWriteTime
    if ($age -lt $t0.AddSeconds(-5)) {
        Write-Output "  [FAIL] result file is STALE (mtime=$age, run started $t0) -- EA did not write it this run"
        $anyFail = $true
        continue
    }

    $raw = Get-Content $resPath -Raw
    try { $j = $raw | ConvertFrom-Json } catch { Write-Output "  [FAIL] result is not valid JSON: $raw"; $anyFail = $true; continue }

    if ($j.git_sha -ne $sha) {
        Write-Output "  [FAIL] git_sha mismatch: result=$($j.git_sha) HEAD=$sha"
        $anyFail = $true
        continue
    }

    Write-Output "  status=$($j.status) total=$($j.total) passed=$($j.passed) failed=$($j.failed)"
    if ($j.failed -gt 0) {
        foreach ($f in $j.failed_names) { Write-Output "    FAILED: $f" }
        $anyFail = $true
    }
    if ($j.status -ne "PASS") { $anyFail = $true }
}

Write-Output ""
if ($anyFail) { Write-Output "MQL5 TESTS: FAILED"; exit 1 }
Write-Output "MQL5 TESTS: PASSED"
exit 0
