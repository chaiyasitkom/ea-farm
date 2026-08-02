---
id: 077
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: "076"
---

## SPEC-016 Handoff

**Branch:** current working tree (no commit per instruction)
**Commits:** none

### What changed
- `tools/run-chaos.ps1`
  - Replaced the event/job-based `Invoke-StreamingProcess` implementation with temp-file redirection plus live tailing.
  - Child stdout/stderr are now written to the console while the process runs.
  - After process exit, the helper tails once more and then rereads full stdout/stderr files before returning `Text`, so unittest's final summary is available to the parser.
  - `skipped=` parsing is now fail-closed: if the count is missing, the gate prints `CHAOS GATE: FAILED -- unittest summary missing skipped= count; output may be incomplete` and exits 1.
  - Restored explicit fast count enforcement: fast gate must end with exactly `skipped=1`.

### gate changes
- `run-chaos.ps1` gate behavior changed intentionally:
  - Output collection no longer depends on `Register-ObjectEvent -Action` or `Receive-Job`.
  - Missing unittest skip summary is a gate failure, not `skipped=0`.
  - Fast gate now requires both evidence that `test_no_heartbeat_loss_over_1h` was reported as skipped and `skipped=1` in the parsed summary.

### Deviations from spec
| Point | Spec says | Actual | Why |
|---|---|---|---|
| none | - | - | none |

### Test
- PowerShell parser check for `tools/run-chaos.ps1`
  - Output: `parse-ok`
- Helper smoke test for `Invoke-StreamingProcess`
  - Child printed to stdout and stderr with a delayed final summary.
  - Live output observed: `stdout-one`, `stderr-one`, `OK (skipped=1)`.
  - Captured text observed: `stdout-one||stderr-one|OK (skipped=1)|`.

### Not done / technical debt
- Did not run the real fast chaos gate because it launches MT5; user said they will run it after this fix.
- `git pull` at session start failed: `error: cannot open '.git/FETCH_HEAD': Permission denied`.

### Please review closely
- `tools/run-chaos.ps1` command launch now goes through `cmd.exe` only to get file redirection without `Start-Process`; `Start-Process` failed locally with duplicate `Path`/`PATH` environment keys.
- The final reread of stdout/stderr before parsing is the critical part for preserving unittest's `OK (skipped=1)` line.
