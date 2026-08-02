---
id: 063
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "062"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none (per instruction: no commit)

### What changed
- `tools/run-mql5-tests.ps1:38-42`
  - Added a filename-only guard for `-RoundTripManifest`.
  - Full paths now fail before tester execution, so `InpRoundTripManifest` cannot receive an absolute path.
- `tools/run-mql5-tests.ps1:213-256`
  - Renamed the internal default manifest path variable to `$gateManifestPath`.
  - Renamed caller path variable to `$callerManifestPath`.
  - Kept the caller-selected manifest count as the expected `cases_processed` count.
- `tools/run-mql5-tests.ps1:317`
  - `.set` now writes `InpRoundTripManifest=$roundTripManifestFile`, which is filename-only.

### Gate changes
- Fixed PowerShell case-insensitive variable collision between parameter `$RoundTripManifest` and local `$roundTripManifest`.
- Scanned `tools/run-mql5-tests.ps1` for case-only variable-name collisions with:
  - `rg -o '\$[A-Za-z_][A-Za-z0-9_]*' tools/run-mql5-tests.ps1`
  - grouped by `.ToLowerInvariant()`
- Result: no remaining case-only variable-name collision pairs found.
- Explicitly checked likely pairs (`$Repo/$repo`, `$Common/$common`, `$WorkDir/$workDir`, `$Data/$data`, `$Terminal/$terminal`, `$MetaEditor/$metaEditor`, `$RoundTripManifest/$roundTripManifest`); only the intended public parameter remains, with internal names not differing only by case.

### Spec deviations
| Point | Spec/request said | Actual | Reason |
|-----|-----|-----|-----|
| pytest command | `pytest tests/test_roundtrip.py` should be `17 passed` | Could not complete in this sandbox | Global `pytest` uses unsupported Python 3.14 and cannot import editable package; `.venv` reaches tests but Python write to MT5 `Common\Files` is denied by environment permission. This is not a round-trip code failure. |

### Test
- `git pull`
  - Failed before work: `error: cannot open '.git/FETCH_HEAD': Permission denied`
- `powershell -ExecutionPolicy Bypass -File tools\run-mql5-tests.ps1`
  - PASSED.
  - Key lines:
    - `[deploy] default round-trip manifest -> ...\ea-farm-rt-manifest.json (24 cases)`
    - `TestRoundTrip ... status=PASS total=1 passed=1 failed=0`
    - `MQL5 TESTS: PASSED`
- `powershell -ExecutionPolicy Bypass -File tools\run-mql5-tests.ps1 -RoundTripManifest "ea-farm-rt-manifest-pytest.json"`
  - PASSED.
  - Key lines:
    - `[deploy] caller round-trip manifest -> ...\ea-farm-rt-manifest-pytest.json (31 cases)`
    - `TestRoundTrip ... status=PASS total=1 passed=1 failed=0`
    - `MQL5 TESTS: PASSED`
- `powershell -ExecutionPolicy Bypass -File tools\run-mql5-tests.ps1 -RoundTripManifest "<full path>"`
  - Expected fail:
    - `FATAL: RoundTripManifest must be a filename only, not a path: ...`
- `pytest tests/test_roundtrip.py`
  - Failed during collection under global Python 3.14:
    - `ModuleNotFoundError: No module named 'farm_contracts'`
    - `pyproject.toml` requires Python `<3.14`.
- `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py`
  - Collected 17 tests, but failed before round-trip execution:
    - `PermissionError: [Errno 13] Permission denied: 'C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\ea-farm-rt-in-run1-1.json'`
    - Summary: `1 failed, 16 errors`
  - Separate write probe with `.venv` Python to `Common\Files\codex-write-probe.txt` also fails with `PermissionError`.

### Cases processed assertion
- Default gate path still checks `cases_processed` against the generated gate manifest count: 24.
- Caller manifest path checks `cases_processed` against the caller manifest count: 31.
- Both MQL5 gate runs passed with the assertion active.

### Not done / technical debt
- Did not make pytest report `17 passed` because current Codex sandbox denies Python writes to MT5 `Common\Files`.
- Did not touch tests or round-trip MQL5/Python implementation to mask this environment failure.

### Please review
- The `tools/run-mql5-tests.ps1` diff, especially the manifest variable naming and filename-only guard.
- Whether `pytest tests/test_roundtrip.py` should be documented to run through `.venv\Scripts\python.exe -m pytest` or whether the local shell PATH should be fixed outside this ticket.
- The Python permission failure to MT5 `Common\Files`; direct MQL5 gate execution passes, but pytest cannot prepare its manifest/input files in this sandbox.

### Open questions
- None.
