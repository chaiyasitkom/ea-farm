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
#   * Compiling needs no account, but the STRATEGY TESTER does. Keep terminal
#     data folders explicit because each broker install has separate accounts,
#     symbols, and history.
#   * IUX symbols carry a ".iux" suffix (EURUSD.iux, XAUUSD.iux). XM symbols do
#     not in this local terminal data folder (EURUSD, GOLD).
#   * Tester date ranges must sit inside locally available history or the run
#     aborts.
#   * .set string values must be plain "Name=value". The "||||N" optimization
#     suffix used for numeric params becomes PART OF THE STRING and produced
#     FileOpen error 5004 (invalid filename).
#   * An EA that calls ExpertRemove() inside OnInit makes the tester log
#     "tester stopped because OnInit failed" and terminal exit code stays 0.
#     => NEVER judge success by exit code. Only the result JSON counts.
#   * MQL5 has no FILE_UTF8 flag. Real UTF-8 requires
#     FILE_BIN + StringToCharArray(..., CP_UTF8). See tools\probe\TesterProbe.mq5.

param(
    [string]$RoundTripManifest = "ea-farm-rt-manifest.json"
)

$ErrorActionPreference = 'Stop'

$roundTripManifestFile = Split-Path -Leaf $RoundTripManifest
if ([string]::IsNullOrWhiteSpace($roundTripManifestFile) -or $roundTripManifestFile -ne $RoundTripManifest) {
    Write-Output "FATAL: RoundTripManifest must be a filename only, not a path: $RoundTripManifest"
    exit 2
}

$Repo       = "D:\ea-farm"
$Common     = "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
$WorkDir    = Join-Path $env:TEMP "ea-farm-compile"
$FixtureDst = Join-Path $Common "ea-farm-fixtures"

$Targets = @(
    @{
        Name = "IUX"
        Enabled = $true
        SkipReason = ""
        Data = "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3"
        Terminal = "C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe"
        MetaEditor = "C:\Program Files\IUX Markets MT5 Terminal3\metaeditor64.exe"
        Symbol = "EURUSD.iux"
        From = "2026.06.02"
        To = "2026.06.19"
    },
    @{
        Name = "XM"
        Enabled = $false
        SkipReason = "D11 login invalid and local EURUSD history is not usable for tester gate yet"
        Data = "C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\BB16F565FAAA6B23A20C26C49416FF05"
        Terminal = "C:\Program Files\XM Global MT5\terminal64.exe"
        MetaEditor = "C:\Program Files\XM Global MT5\MetaEditor64.exe"
        Symbol = "EURUSD"
    }
)

# suite name -> source path (relative to repo)
$Suites = @(
    @{ Name = "TestWire"; Source = "tests\mql5\TestWire.mq5" },
    @{ Name = "TestBrokerTime"; Source = "tests\mql5\TestBrokerTime.mq5" },
    @{ Name = "TestFarmMessages"; Source = "tests\mql5\TestFarmMessages.mq5" },
    @{ Name = "TestFarmSymbols"; Source = "tests\mql5\TestFarmSymbols.mq5" },
    @{ Name = "TestRoundTrip"; Source = "tests\mql5\TestRoundTrip.mq5" }
)

$RequiredSuiteNames = @{
    TestWire = @(
        "test_framing_multiple_in_one_read",
        "test_framing_split_across_reads",
        "test_framing_crlf_tolerance",
        "test_framing_empty_line_skipped",
        "test_framing_oversize_frame_rejected",
        "test_json_parse_malformed_skips_line",
        "test_json_unknown_field_ignored",
        "test_json_unknown_type_ignored",
        "test_queue_full_drops_oldest",
        "test_partial_send_resumes",
        "test_utf8_multibyte_not_split",
        "test_msg_id_empty_without_broker_time",
        "test_msg_id_monotonic_across_1000_calls",
        "test_msg_id_monotonic_when_clock_frozen",
        "test_msg_id_unique_across_10000_calls"
    )
    TestBrokerTime = @(
        "test_offset_detect_whole_hour",
        "test_offset_detect_half_hour",
        "test_offset_detect_negative",
        "test_offset_reject_non_quantized",
        "test_offset_reject_out_of_bounds",
        "test_init_fails_when_server_time_zero",
        "test_init_retries_until_deadline",
        "test_init_retries_then_accepts_good_sample",
        "test_roundtrip_broker_utc_identity",
        "test_format_iso_utc_matches_schema",
        "test_invalid_returns_zero_not_stale",
        "test_invalid_after_90s_of_bad_samples",
        "test_recovery_from_invalid_changed_offset_reports_change",
        "test_dst_change_needs_three_samples",
        "test_refresh_throttles_samples_20s",
        "test_dst_change_accepted_on_third",
        "test_dst_flap_does_not_change_offset",
        "test_broker_day_start_normal",
        "test_broker_day_start_across_dst_23h_and_25h",
        "test_is_same_broker_day_across_utc_midnight",
        "test_local_time_comes_from_source"
    )
    TestFarmMessages = @(
        "test_roundtrip_all_valid_fixtures",
        "test_parse_state_with_nested_positions",
        "test_parse_duplicate_key_in_nested_object",
        "test_parse_string_containing_key_like_text",
        "test_parse_ignores_unknown_field",
        "test_parse_fails_on_missing_required_names_field",
        "test_unknown_envelope_type_yields_UNKNOWN_not_error",
        "test_null_vs_value_vs_absent",
        "test_serialize_null_emits_null_not_zero",
        "test_serialize_no_scientific_notation",
        "test_serialize_escapes_and_utf8_thai_roundtrip",
        "test_depth_limit_rejected_at_33"
    )
    TestFarmSymbols = @(
        "test_canonical_gold_to_xauusd",
        "test_canonical_unknown_returns_empty",
        "test_risk_profile_returns_false_for_unknown",
        "test_spread_null_encoded_as_minus_one",
        "test_all_canonicals_have_base_and_quote",
        "test_production_ready_false_for_uncalibrated",
        "test_correlation_groups_available"
    )
    TestRoundTrip = @(
        "test_manifest_roundtrip_cases"
    )
}

foreach ($t in $Targets) {
    if (-not $t.Enabled) { continue }
    foreach ($p in @($t.Terminal, $t.MetaEditor, $t.Data)) {
        if (-not (Test-Path $p)) { Write-Output "FATAL: not found -> $($t.Name): $p"; exit 2 }
    }
}
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

Push-Location $Repo
$sha = (& git rev-parse HEAD).Trim()
$dirty = (& git status --porcelain -- mt5-ea tests tools | Measure-Object).Count
Pop-Location

Write-Output "MQL5 TEST RUN -- HEAD=$($sha.Substring(0,7))"
if ($dirty -gt 0) { Write-Output "WARNING: $dirty uncommitted change(s) under mt5-ea/, tests/, or tools/ -- git_sha will not describe what actually ran" }
Write-Output ""

$anyFail = $false
$ranTargets = @()
$skippedTargets = @()

foreach ($t in $Targets) {
    $targetName = $t.Name
    if (-not $t.Enabled) {
        $reason = $t.SkipReason
        Write-Output "[SKIP] $targetName -- reason: $reason"
        $skippedTargets += "$targetName ($reason)"
        continue
    }

    $ranTargets += $targetName
    $Data = $t.Data
    $Terminal = $t.Terminal
    $MetaEditor = $t.MetaEditor
    $TesterSymbol = $t.Symbol
    $TesterFrom = $t.From
    $TesterTo = $t.To

    Write-Output "=== target: $targetName symbol=$TesterSymbol data=$Data"

    # ---- 1. deploy includes ---------------------------------------------
    $incDst = Join-Path $Data "MQL5\Include\Farm"
    if (-not (Test-Path $incDst)) { New-Item -ItemType Directory -Path $incDst -Force | Out-Null }
    Copy-Item (Join-Path $Repo "mt5-ea\Include\Farm\*.mqh") $incDst -Force
    Copy-Item (Join-Path $Repo "contracts\gen\mql5\*.mqh") $incDst -Force
    Write-Output "[deploy] Include\Farm -> $incDst"

    # ---- fixture deploy --------------------------------------------------
    # MQL5 has no FILE_UTF8 flag. Test EAs read these with FILE_BIN + CP_UTF8.
    if (Test-Path $FixtureDst) { Remove-Item $FixtureDst -Recurse -Force }
    New-Item -ItemType Directory -Path $FixtureDst -Force | Out-Null
    Get-ChildItem (Join-Path $Repo "contracts\fixtures") -File -Filter "*.json" |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $FixtureDst $_.Name) -Force }
    Get-ChildItem (Join-Path $Repo "contracts\fixtures\invalid") -File -Filter "*.json" |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $FixtureDst ("invalid__" + $_.Name)) -Force }
    $fixtureCount = (Get-ChildItem $FixtureDst -File -Filter "*.json").Count
    if ($fixtureCount -eq 0) {
        Write-Output "  [FAIL] fixture deploy produced an empty folder: $FixtureDst"
        $anyFail = $true
        continue
    }
    Write-Output "[deploy] fixtures -> $FixtureDst ($fixtureCount json files)"

    $gateManifestPath = Join-Path $Common "ea-farm-rt-manifest.json"
    $rtCases = @()
    $rtId = 1
    Get-ChildItem $FixtureDst -File -Filter "*.json" |
        Where-Object { $_.Name -match '\.valid(\.min)?\.json$' } |
        Sort-Object Name |
        ForEach-Object {
            $rtCases += [ordered]@{
                id = $rtId
                type = ($_.Name -replace '\.valid(\.min)?\.json$', '').ToUpper()
                in = "ea-farm-fixtures\$($_.Name)"
                out = "ea-farm-rt-out-gate-$rtId.json"
            }
            $rtId++
        }
    $roundTripExpectedCases = $rtCases.Count
    [IO.File]::WriteAllText(
        $gateManifestPath,
        (@{ cases = $rtCases } | ConvertTo-Json -Depth 8 -Compress),
        [Text.UTF8Encoding]::new($false)
    )
    Write-Output "[deploy] default round-trip manifest -> $gateManifestPath ($roundTripExpectedCases cases)"

    if ($roundTripManifestFile -ne "ea-farm-rt-manifest.json") {
        $callerManifestPath = Join-Path $Common $roundTripManifestFile
        if (-not (Test-Path $callerManifestPath)) {
            Write-Output "  [FAIL] requested round-trip manifest not found: $callerManifestPath"
            $anyFail = $true
            continue
        }
        try {
            $callerManifestJson = Get-Content $callerManifestPath -Raw | ConvertFrom-Json
        } catch {
            Write-Output "  [FAIL] requested round-trip manifest is not valid JSON: $callerManifestPath"
            $anyFail = $true
            continue
        }
        if (-not ($callerManifestJson.PSObject.Properties.Name -contains "cases")) {
            Write-Output "  [FAIL] requested round-trip manifest has no cases: $callerManifestPath"
            $anyFail = $true
            continue
        }
        $roundTripExpectedCases = @($callerManifestJson.cases).Count
        Write-Output "[deploy] caller round-trip manifest -> $callerManifestPath ($roundTripExpectedCases cases)"
    }

    $expDst = Join-Path $Data "MQL5\Experts\FarmTests"
    if (-not (Test-Path $expDst)) { New-Item -ItemType Directory -Path $expDst -Force | Out-Null }

    $setDir = Join-Path $Data "MQL5\Profiles\Tester"
    if (-not (Test-Path $setDir)) { New-Item -ItemType Directory -Path $setDir -Force | Out-Null }

foreach ($s in $Suites) {
    $name = $s.Name
    $src  = Join-Path $Repo $s.Source
    Write-Output ""
    Write-Output "--- $targetName / $name"

    if (-not (Test-Path $src)) { Write-Output "  [FAIL] source not found: $src"; $anyFail = $true; continue }

    Copy-Item $src (Join-Path $expDst "$name.mq5") -Force

    # ---- 2. compile in the data folder ---------------------------------
    $clog = Join-Path $WorkDir "$targetName-$name-tester.log"
    $ex5 = Join-Path $expDst "$name.ex5"
    Remove-Item $clog -ErrorAction SilentlyContinue
    Remove-Item $ex5 -ErrorAction SilentlyContinue
    $a = @("/compile:$expDst\$name.mq5", "/inc:$Data\MQL5", "/log:$clog")
    Start-Process -FilePath $MetaEditor -ArgumentList $a -Wait -NoNewWindow | Out-Null

    $result = $null
    if (Test-Path $clog) {
        $lines  = Get-Content $clog -Encoding Unicode
        $result = $lines | Where-Object { $_ -match '^Result:' } | Select-Object -Last 1
        foreach ($d in ($lines | Where-Object { $_ -match ':\s*(error|warning)\s' })) { Write-Output "  $d" }
    }
    Write-Output "  compile: $result"

    if ($result -notmatch 'Result:\s*(\d+)\s*error') {
        Write-Output "  [FAIL] cannot parse compile result line"
        $anyFail = $true
        continue
    }
    $compileErrors = [int]$Matches[1]
    if ($compileErrors -gt 0) {
        Write-Output "  [FAIL] compile reported $compileErrors error(s)"
        $anyFail = $true
        continue
    }

    if (-not (Test-Path $ex5)) {
        Write-Output "  [FAIL] no .ex5 -- compile failed, cannot run tests"
        $anyFail = $true
        continue
    }

    # ---- 3. inject inputs ----------------------------------------------
    $resultFile = "ea-farm-$targetName-$name-result.json"
    $setName    = "farm-$targetName-$name.set"
    # plain Name=value -- see header note about the ||||N trap
    @(
        "InpTestGitSha=$sha",
        "InpTestResultFile=$resultFile",
        "InpFixtureDir=ea-farm-fixtures",
        "InpRoundTripManifest=$roundTripManifestFile"
    ) -join "`r`n" | Out-File -FilePath (Join-Path $setDir $setName) -Encoding ascii

    # ---- 4. run the tester ---------------------------------------------
    $ini = Join-Path $WorkDir "tester-$targetName-$name.ini"
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
    $runningTerminal = Get-Process terminal64 -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $Terminal } |
        Select-Object -First 1
    if ($runningTerminal) {
        Write-Output "  [FAIL] $targetName terminal is already running (pid=$($runningTerminal.Id)); close it before headless tester run"
        $anyFail = $true
        continue
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $Terminal -ArgumentList "/config:$ini" -Wait | Out-Null
    $sw.Stop()
    Write-Output "  tester ran $([int]$sw.Elapsed.TotalSeconds)s (exit code deliberately ignored)"

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
    $observedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $observedPath = Join-Path $Common ($resultFile -replace '\.json$', '-observed.json')
    $observed = [ordered]@{
        suite = $name
        target = $targetName
        git_sha = $sha
        observed_at = $observedAt
        result_file = $resultFile
        status = $j.status
        total = $j.total
        passed = $j.passed
        failed = $j.failed
        cases_processed = $j.cases_processed
    }
    [IO.File]::WriteAllText(
        $observedPath,
        ($observed | ConvertTo-Json -Depth 8 -Compress),
        [Text.UTF8Encoding]::new($false)
    )

    if ($j.git_sha -ne $sha) {
        Write-Output "  [FAIL] git_sha mismatch: result=$($j.git_sha) HEAD=$sha"
        $anyFail = $true
        continue
    }

    if ($name -eq "TestRoundTrip") {
        if (-not ($j.PSObject.Properties.Name -contains "cases_processed")) {
            Write-Output "  [FAIL] result JSON has no cases_processed"
            $anyFail = $true
        } elseif ([int]$j.cases_processed -lt $roundTripExpectedCases) {
            Write-Output "  [FAIL] cases_processed=$($j.cases_processed) expected_at_least=$roundTripExpectedCases"
            $anyFail = $true
        }
    }

    Write-Output "  status=$($j.status) total=$($j.total) passed=$($j.passed) failed=$($j.failed)"
    $requiredNames = $RequiredSuiteNames[$name]
    if (-not $requiredNames -or $requiredNames.Count -eq 0) {
        Write-Output "  [FAIL] no required test names registered for suite $name"
        $anyFail = $true
        continue
    }
    if (-not ($j.PSObject.Properties.Name -contains "ran_names")) {
        Write-Output "  [FAIL] result JSON has no ran_names"
        $anyFail = $true
    } else {
        foreach ($required in $requiredNames) {
            if ($j.ran_names -notcontains $required) {
                Write-Output "  [FAIL] required test did not run: $required"
                $anyFail = $true
            }
        }
    }
    if ($j.failed -gt 0) {
        foreach ($f in $j.failed_names) { Write-Output "    FAILED: $f" }
        $anyFail = $true
    }
    if ($j.status -ne "PASS") { $anyFail = $true }
}

    Write-Output ""
}

Write-Output ""
Write-Output "Targets run: $($ranTargets -join ', ')"
Write-Output "Targets skipped: $($skippedTargets -join ', ')"
if ($anyFail) { Write-Output "MQL5 TESTS: FAILED"; exit 1 }
Write-Output "MQL5 TESTS: PASSED"
exit 0
