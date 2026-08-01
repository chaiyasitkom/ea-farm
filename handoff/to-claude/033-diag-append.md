---
id: 033
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: "032"
---

## SPEC-001 Handoff: diag append and success evidence

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none this round (per instruction)

### What changed
- `mt5-ea/Include/Farm/Wire.mqh`
  - `OpenDiagFile()` now opens `ea-farm-wire-diag.jsonl` with `FILE_READ | FILE_WRITE` and seeks to `SEEK_END`, so EA init appends instead of truncating previous test evidence.
  - Added `FARM_WIRE_DIAG_ROTATE_BYTES = 33554432` and rotate-on-open when the existing diag file is over 32 MiB.
  - On rotation, the EA truncates the diag file, logs `wire_diag_file_rotated` via logger, and writes `{"ev":"diag_rotate", ...}` to the new diag file.
  - Added `m_diag_session_id`; `DiagClockJson()` now includes `session_id` on every diag event.
  - `OpenDiagFile()` writes `{"ev":"session_start", ...}` at init, including `tick_ms` and `session_id`.
  - Kept `FileFlush()` in `WriteDiagLine()` and `CloseDiagFile()`.
- `tests/chaos/test_wire_resilience.py`
  - Added success evidence prints for measured live chaos values:
    - `test_backoff_schedule_matches_spec`: prints observed `backoff_sec` ladder and measured `gaps_sec`.
    - `test_bad_token_waits_60s`: prints retry delay.
    - `test_ea_handles_duplicate_session_rejection`: prints retry delay.
    - `test_heartbeat_gap_triggers_reconnect`: prints reconnect gap.
    - `test_heartbeat_interval_within_5pct_over_5min`: prints heartbeat count, mean/min/max gap.
    - `test_no_heartbeat_loss_over_1h`: prints heartbeat count and max gap.

### gate changes
- Did not edit `tools/**`.
- Changed live chaos test output only; no assertions were relaxed or skipped.

### Deviations from spec
| Point | Spec/request said | Actual | Reason |
|-----|-----|-----|-----|
| none | n/a | none | n/a |

### Test
Did not run fast chaos gate, live gate, or MQL5 compile gate per instruction.

Local/static checks only:
```text
> python -m py_compile tests/chaos/test_wire_resilience.py
exit 0

> git diff --check -- mt5-ea/Include/Farm/Wire.mqh tests/chaos/test_wire_resilience.py
exit 0
```

MQL5 not compiled here; waiting for Claude/user compile gate.

### Not done / technical debt
- `git pull` at session start failed in this environment: `error: cannot open '.git/FETCH_HEAD': Permission denied`.
- No commit created, per instruction.

### Please review especially
- `Wire.mqh` MQL5 compile around `FileSize`, `FileSeek(..., SEEK_END)`, and `%I64u` formatting in the new rotate path.
- Whether adding `session_id` to every diag line is acceptable. It is intentionally extra context so old appended sessions can be separated without relying only on the `session_start` delimiter.

### Open questions
None.
