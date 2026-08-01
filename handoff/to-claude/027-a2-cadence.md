---
id: 027
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: "026"
---

# A2 cadence handoff

## Summary

Implemented A2 in the allowed code area only:

- S1: `Wire.mqh` heartbeat cadence now uses a scheduled `m_next_heartbeat_tick` and signed ms delta checks.
- S3: soak heartbeat minimum is now derived as `int(SOAK_SECONDS / HEARTBEAT_SEC * 0.95)`.
- S4: `FarmExecutor.mq5` brain timeout now compares `MsSinceLastInbound() >= InpBrainTimeoutSec * 1000`.
- S5: reconnect wait now uses signed delta compare, with a `m_next_connect_tick != 0` sentinel guard.
- R2: `EventTail.read_new()` now buffers an incomplete trailing line until the next read.

## Files changed

- `mt5-ea/Include/Farm/Wire.mqh`
- `mt5-ea/Experts/FarmExecutor.mq5`
- `tests/chaos/test_wire_resilience.py`

## S1 details

Heartbeat state changed from `m_last_heartbeat_tick = NowTick()` after send to `m_next_heartbeat_tick`.

When entering `WIRE_READY`, `m_next_heartbeat_tick` is set to current tick so the first heartbeat remains immediate. In `Pump()`, due is checked as:

```mql5
(int)(now - m_next_heartbeat_tick) >= 0
```

After one heartbeat attempt, the schedule advances with:

```mql5
m_next_heartbeat_tick += interval_ms
```

inside a loop until the next due is in the future.

### S1(c) rationale

If the EA is behind several intervals, it sends at most one heartbeat in that `Pump()` call, then advances `m_next_heartbeat_tick` past `now`. This catches the schedule up without emitting a backlog burst. That matches the protocol need: heartbeat is a liveness signal, not a replayable event stream, so delayed intervals should not be compensated by multiple immediate heartbeats.

## Expected gap after fix

For a 3598s observed soak window and `HEARTBEAT_SEC = 2`, expected heartbeat count is about `3598 / 2 = 1799`.

Expected metrics:

- `len(heartbeats)`: about 1799, above derived minimum `int(3600 / 2 * 0.95) = 1710`
- `mean_gap`: about 2.00s
- histogram: normal cadence should not leave rounded 3s buckets
- `max(gaps)`: expected <= 3.5s unless the whole MT5 timer/polling loop stalls

## S2 audit response: 11 points

1. `Wire.mqh:128` `ElapsedSec`: confirmed OK. For `>= K` and `< K`, `floor(e/1000)` reaches the threshold at the exact millisecond boundary; no `/1000` bias exists there.
2. Heartbeat check: confirmed broken before this change. The real issue was resetting the base to send time; fixed with scheduled `next_due += interval`.
3. `FAILED_AUTH < 60`: confirmed OK. `floor(e/1000) < 60` remains true until `e >= 60000`, so retry waits at least 60.000s.
4. `WIRE_CONNECTED` HELLO timeout `>= 5`: confirmed OK. Fires at `e >= 5000`.
5. `WIRE_AUTHENTICATING` HELLO timeout `>= 5`: confirmed OK for the same math as point 4.
6. `SecondsSinceLastInbound()` caller in `FarmExecutor`: confirmed bug because caller used `> 10`; `floor(e/1000) > 10` means `e >= 11000`. Fixed via ms compare.
7. `NowTick() < m_next_connect_tick`: confirmed unsigned raw compare bug. Fixed with signed delta compare.
8. `m_next_connect_tick = NowTick() + wait`: confirmed acceptable paired with point 7. I kept the scheduled tick and added the sentinel guard for zero.
9. Backoff jitter from `GetTickCount() % spread`: confirmed not fixed in A2. It is weak randomness but not a current single-EA soak blocker.
10. `GetTickCount64()` for diag `tick_ms`: confirmed OK; 64-bit value avoids the 49.7 day wrap issue.
11. ULID seed: confirmed OK per audit; current seed includes chart/account context and is not part of this timing bug.

Audit section 2 "scary but not broken" items were not changed: unsigned subtraction for elapsed, `(int)` after `/1000`, zero heartbeat tick causing immediate heartbeat, and authenticated guard around inbound timeout.

## R2 behavior

`EventTail.read_new()` now:

- reads the new chunk from the previous offset
- concatenates any saved partial suffix
- parses only through the last `\n`
- keeps the trailing partial line for the next read

No `try/except: pass` was added. A completed but malformed JSON line still raises, so corrupt events are not silently swallowed.

## Verification

Ran only non-gate checks:

- `python -m py_compile tests/chaos/test_wire_resilience.py`
- `git diff --check -- mt5-ea/Include/Farm/Wire.mqh mt5-ea/Experts/FarmExecutor.mq5 tests/chaos/test_wire_resilience.py`
- inline `EventTail` partial-line check: first read returned only the complete event, second read returned the completed partial event and next event

Did not run chaos gate or soak.

MetaEditor compile not run in this environment.

## Deviations from spec

No functional deviation from A2 intent. I added `m_next_connect_tick != 0` around the S5 signed-delta reconnect check because zero is already used as the "connect immediately" sentinel; without the guard, a terminal that starts after high uptime could treat zero as a future target under signed delta math.

## Points for Claude to review

- S1(c): confirm that advancing due past `now` after one heartbeat is the desired no-burst catch-up behavior.
- S5 sentinel guard: confirm this is acceptable with the requested signed-delta compare.
- S4 log field changed from `seconds_since_last_inbound` to `ms_since_last_inbound`; confirm dashboards/tests do not depend on the old warning text.

## Gate changes

No `tools/**` changes.
