---
id: 081
from: codex
ticket: SPEC-010
type: handoff
blocking: false
replies_to: "080"
---

## SPEC-010 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** not committed per instruction

### ทำอะไรไปแล้ว
- Added `mt5-ea/Include/Farm/StateReporter.mqh`
  - Builds HELLO/HEARTBEAT/BAR/STATE payloads above Wire.
  - Uses `CBrokerTime` for BAR/STATE timestamps; invalid broker time drops BAR/STATE and logs.
  - Backfill is paced after `wire.IsAuthenticated()` and only while `SendQueueDepth() < SendQueueMax()/2`.
  - STATE reports owned positions by `(magic, symbol)`, foreign counts, owned net/ticket maps, margin null when margin is zero, HWM via GlobalVariable.
- Updated `mt5-ea/Include/Farm/Wire.mqh`
  - Removed HELLO payload builder from Wire.
  - Added `SetHelloPayload()`, `SetPayloadProvider()`, `MakeApplicationEnvelope()`, `SendQueueMax()`.
  - Heartbeat cadence/backoff/reconnect scheduling in `Pump()` is unchanged; only payload source changed.
  - Inbound parsing now uses generated `FarmParseEnvelope` instead of `FarmJsonGetString`.
- Updated `mt5-ea/Experts/FarmExecutor.mq5`
  - Adds `CStateReporter`, `InpBackfillBars=300`, `InpStateIntervalSec=5`.
  - Calls `wire.Pump()` then `state_reporter.Pump()` in `OnTimer`.
  - `OnTick()` only samples spread.
- Updated `brain/gateway/echo_server.py`
  - Validates payloads via generated Python `PAYLOAD_MODELS`.
  - Logs BAR/STATE events and counts bars per session.
- Added tests:
  - `tests/mql5/TestStateReporter.mq5` with the 19 MQL test names from SPEC-010.
  - `tests/chaos/test_state_reporter.py` with the 5 Python chaos test names from SPEC-010.
  - Updated `tests/mql5/TestWire.mq5` for full generated-envelope inbound parsing.
  - Updated `tests/chaos/test_wire_resilience.py` HELLO helper to send schema-valid HELLO.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| MQL payload construction | ห้ามเขียน JSON serializer เอง ใช้ FarmMessages | StateReporter builds raw payload strings, then validates/canonicalizes through generated `FarmParse*`/`FarmSerialize*` before send | Current generated MQL serializers are raw-json wrappers, not field-to-json builders. This is the narrowest usable path without editing generator/contracts in this ticket. |
| MQL tests | ห้าม mock `CWire`; prove pacing via real queue | `TestStateReporter` uses real `CWire` queue objects, but does not open a live socket/authenticated session | Strategy Tester unit EA cannot host the gateway. Authenticated pacing is left to chaos/live gate. |
| Python chaos tests | Verify live EA backfill/STATE against MT5 | Added TCP echo/gateway tests with valid BAR/STATE payloads; live MT5 proof still depends on Claude chaos gate | User explicitly said not to run chaos/soak. I avoided starting terminal/gate. |
| Backfill unavailable bar after 30s | Send as much as possible + WARN | Current code skips an unavailable shift after 30s and continues | This avoids permanent stall on sparse history, but Claude should confirm whether skip is acceptable or should abort remaining backfill. |

### gate changes
- `tools/run-mql5-tests.ps1`
  - Added `TestStateReporter` suite.
  - Added all 19 required `ran_names`.
  - No target enablement changed; XM remains `[SKIP]`/disabled as before.

### Test
Not run per instruction: `tools/run-mql5-tests.ps1`, compile gate, chaos gate, soak.

Ran only non-gate static/syntax checks:
```text
python -m py_compile brain/gateway/echo_server.py tests/chaos/test_state_reporter.py tests/chaos/test_wire_resilience.py tests/chaos/live_mt5_harness.py
exit 0

rg -n "FarmJsonGetString\(|TimeCurrent\(\)|TimeGMT\(|OrderSend|PositionModify|PositionClose|<<<<<<<|>>>>>>>" <touched files>
exit 1 (no matches)

git diff --check -- <touched files>
exit 0
warning: tools/run-mql5-tests.ps1 LF will be replaced by CRLF next time Git touches it
```

Also attempted required session start `git pull`, but sandbox returned:
```text
error: cannot open '.git/FETCH_HEAD': Permission denied
```

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้เห็น MetaEditor compiler output. ต้องรอ compile gate.
- ยังไม่ได้พิสูจน์ backfill 300 ผ่าน live authenticated Wire ว่า `BarsSkippedQueueFull()==0` และ heartbeat ไม่ขาด.
- `StateReporter.mqh` likely needs one compile-fix pass after Claude gate because this is new MQL surface area.
- Generated MQL payload serializers do not provide field builders; StateReporter currently relies on raw JSON + generated parse/serialize validation.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- `Wire.mqh`: confirm cadence/backoff state machine diff is limited to payload source and envelope parser.
- `StateReporter.mqh`: backfill behavior when individual historical bars remain unavailable after 30s.
- `StateReporter.mqh`: STATE ownership/foreign position semantics and whether `foreign_positions.symbols` should be populated now or can remain empty in Phase 1.
- `TestStateReporter.mq5`: several tests are smoke/invariant checks because real authenticated queue pacing requires live chaos.

### คำถามค้าง
- ไม่มี blocking question. Main uncertainty is whether generator should grow real MQL field serializers in a later ticket so StateReporter stops constructing raw payload JSON.
