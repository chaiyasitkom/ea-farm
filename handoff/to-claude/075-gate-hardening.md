---
id: 075
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: "074"
---

## SPEC-016 Handoff

**Branch:** current working tree (no commit per instruction)
**Commits:** none

### What changed
- `tools/run-chaos.ps1`
  - Replaced sequential `ReadToEnd()` with async stdout/stderr readers and live streaming while unittest runs.
  - Added total timeout: fast 15m, slow 75m. Timeout kills the Python process tree and any `terminal64`/`metaeditor64` left behind, then fails.
  - Added preflight before unittest/MT5 launch: bind-checks `127.0.0.1:$EA_FARM_CHAOS_PORT`, rejects existing `terminal64`/`metaeditor64`, and checks terminal/metaeditor/data-dir paths.
  - Env preflight failures return `exit 3` via `CHAOS GATE: FAILED (ENV)`.
  - Reads `.env`/env for `EA_FARM_REPO`, `EA_FARM_CHAOS_PORT`, `EA_FARM_MT5_TERMINAL`, `EA_FARM_MT5_METAEDITOR`, `EA_FARM_MT5_DATA_DIR`; defaults preserve current local paths.
  - Runs unittest with `-v` and checks required test names, not skip count only.
- `tools/run-soak.ps1`
  - Reads `EA_FARM_REPO` from env/`.env`, defaulting to `D:\ea-farm`.
- `tests/chaos/live_mt5_harness.py`
  - Reads repo and MT5 paths from env/`.env` with the same defaults as before.
- `tools/run-mql5-tests.ps1`
  - Observed JSON now writes `git_sha`/`git_sha_result` from the result file and `git_sha_head` from current HEAD.

### gate changes
- `run-chaos.ps1` gate behavior changed intentionally:
  - Env not ready is now distinct from test failure (`exit 3`).
  - Output streams during the run instead of being printed after completion.
  - Long runs are bounded by timeout and cleanup.
  - Required scenario names are asserted from verbose unittest output.
- `run-mql5-tests.ps1` attestation metadata changed intentionally:
  - stale or mismatched result files no longer produce observed metadata that only names current HEAD.

### Deviations from spec
| Point | Spec says | Actual | Why |
|---|---|---|---|
| none | - | - | none |

### Test
- `python -m unittest tests.chaos.test_wire_resilience.WireResilienceTests`
  - Output: `Ran 8 tests in 2.596s` / `OK`
- PowerShell parse checks:
  - `tools/run-chaos.ps1` parsed via `[scriptblock]::Create(...)`
  - `tools/run-soak.ps1` parsed via `[scriptblock]::Create(...)`
  - `tools/run-mql5-tests.ps1` parsed via `[scriptblock]::Create(...)`
- `python -m py_compile tests/chaos/live_mt5_harness.py`
  - passed
- Preflight exit-code smoke test:
  - ran `tools/run-chaos.ps1` with missing MT5 paths
  - output: `CHAOS GATE: FAILED (ENV) -- terminal64.exe not found: Z:\missing\terminal64.exe`
  - observed `EXIT=3`

### Not done / technical debt
- Did not run live chaos gate because that would launch MT5 and the user/Claude usually owns the final gate run.
- Did not run ruff: current Python environment reports `No module named ruff`.
- `git pull` at session start failed: `cannot open '.git/FETCH_HEAD': Permission denied`.

### Please review closely
- `tools/run-chaos.ps1` async event/job loop and timeout cleanup.
- `tools/run-chaos.ps1` process cleanup scope: it kills the Python child tree and all `terminal64`/`metaeditor64` processes on timeout, matching the requested aggressive gate cleanup.
- Required test name list in `run-chaos.ps1`; I used the current live class method names, including the current duplicate-session method name.
