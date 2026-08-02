---
id: 071
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "070"
---

## SPEC-005 Handoff

**Branch:** not committed (per instruction)
**Commits:** none

### What changed
- `tests/test_roundtrip.py`
  - `_assert_case_output()` now rejects callers that request output from `expect_output=False` cases, and first asserts that no output was recorded for that case.
  - `test_null_value_absent_three_states_survive` now builds its output map only from `expect_output=True` cases.
  - `test_malformed_input_fails_case_not_suite` still keeps `malformed-input` and now also asserts the malformed output file does not exist.

### Why this shape
- I used the explicit filter in the test that parses JSON because a no-output case cannot produce a usable string for `json.loads`.
- I also hardened `_assert_case_output()` so future accidental callers get a clear harness error and the malformed/no-output invariant is checked at the helper boundary.
- This keeps `malformed-input` as the SPEC-004 4.7 proof case instead of deleting or weakening it.

### Deviations from spec
| Point | Spec says | Actual | Reason |
|---|---|---|---|
| pytest proof in Codex env | `pytest tests/test_roundtrip.py` should show 17 passed | Could not complete in this Codex session | The session cannot write new files under `C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files`; pytest fails before reaching roundtrip assertions. |

### Test
- `powershell -ExecutionPolicy Bypass -File tools/run-mql5-tests.ps1`
  - `MQL5 TESTS: PASSED`
  - IUX targets:
    - `TestWire`: compile `0 errors, 0 warnings`; `status=PASS total=53 passed=53 failed=0`
    - `TestBrokerTime`: compile `0 errors, 0 warnings`; `status=PASS total=67 passed=67 failed=0`
    - `TestFarmMessages`: compile `0 errors, 0 warnings`; `status=PASS total=12 passed=12 failed=0`
    - `TestFarmSymbols`: compile `0 errors, 0 warnings`; `status=PASS total=11 passed=11 failed=0`
    - `TestRoundTrip`: compile `0 errors, 0 warnings`; `status=PASS total=1 passed=1 failed=0`
  - XM skipped: `D11 login invalid and local EURUSD history is not usable for tester gate yet`

- `.\.venv\Scripts\python.exe tools/codegen.py` with before/after SHA256 over `contracts/fixtures/**`
  - exit 0
  - fixture hashes unchanged

- Targeted Python harness check:
  - command imported `tests.test_roundtrip`, built a fake `RoundTripRun` with state full/min plus `malformed-input`, called `test_null_value_absent_three_states_survive`, then verified `_assert_case_output()` fails when output is requested from `malformed-input`.
  - result: `targeted roundtrip harness checks passed`

- `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py`
  - collected 17 items
  - failed before product assertions due environment write permission:
  - representative error:
    - `PermissionError: [Errno 13] Permission denied: 'C:\\Users\\User\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\ea-farm-rt-in-run1-1.json'`
  - `test_stale_output_detected_when_ea_missing` also failed on the same permission class writing `stale-out.json`.

- `pytest tests/test_roundtrip.py` without `.venv`
  - collection failed because global Python 3.14 environment does not have editable package path:
  - `ModuleNotFoundError: No module named 'farm_contracts'`

### Gate changes
- None. I did not edit `tools/**`.

### Not done / technical debt
- I could not personally produce the requested `17 passed` pytest output in this sandbox because direct writes to `Common\Files` are denied from the Codex shell/Python process.
- `git pull` at session start failed with `error: cannot open '.git/FETCH_HEAD': Permission denied`.

### Special review requests
- Please check the helper behavior in `_assert_case_output()`: it intentionally fails if a no-output case is passed to an output-consuming assertion, after first verifying no output is present.
- Please re-run `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py` from a normal user shell. The previous 16 passed / 1 failed should become 17 passed with this harness change.

### Open questions
- None.
