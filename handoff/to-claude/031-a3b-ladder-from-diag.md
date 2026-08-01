---
id: 031
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: "030"
---

## SPEC-001 Handoff: A3b ladder from EA diag

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none this round (per instruction)

### ทำอะไรไปแล้ว
- `brain/gateway/echo_server.py`
  - คืน semantics ของ `--close-on-accept` ให้ปิด socket ทันทีหลัง TCP accept ก่อนอ่าน frame.
  - คง W2: `connect` / `disconnect` / `client_closed` / `read_timeout` log เฉพาะหลัง parse JSON protocol frame แรกได้แล้ว ดังนั้น close-on-accept ไม่มี `connect` event.
- `mt5-ea/Include/Farm/Wire.mqh`
  - เพิ่ม `DiagClockJson()` และเพิ่ม field `"tick_ms": <GetTickCount64()>` ใน diag ทุกบรรทัดที่ `WriteDiagLine()` เขียนอยู่ตอนนี้.
  - ไม่แทนที่ `ts`; ยังเก็บ `ts` เดิมไว้.
- `tests/chaos/test_wire_resilience.py`
  - `EventTail` รองรับ `from_end=True` และ reset offset ถ้าไฟล์ถูก truncate ตอน EA เปิด diag ใหม่.
  - เขียน `test_backoff_schedule_matches_spec` ใหม่ให้อ่าน `ev=reconnect` จาก diag EA.
  - 3a: assert `backoff_sec == [1,2,4,8,16,30,30]` แบบเป๊ะ เพื่อเห็น ladder และ cap 30 ค้าง.
  - 3b: วัด gap จริงจาก `tick_ms` ระหว่าง reconnect diag ต่อเนื่อง เทียบ nominal `[1,2,4,8,16,30]` ด้วย jitter +-20% + EventSetTimer granularity 1.1s.
  - ลบ helper เก่าที่วัด ladder จาก server `connect` events.

### gate changes
- ไม่ได้แก้ `tools/**`.
- แก้ chaos test behavior ใน `tests/chaos/test_wire_resilience.py`: backoff ladder ไม่ใช้ server-side connect timestamps แล้ว ใช้ EA diag `backoff_sec` + `tick_ms`.
- Fast gate duration ที่ user วัดตอนนี้: 604s จากเดิม 264s เพราะมี `test_heartbeat_interval_within_5pct_over_5min` 300s. บันทึกไว้ชัดเจนตามคำสั่ง.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| HELLO timing | SPEC-001 เขียนว่า connect สำเร็จแล้วส่ง HELLO ทันที | โค้ดปัจจุบันยังส่ง HELLO ใน Pump ถัดไปเมื่อ `state_at_start == WIRE_CONNECTED` | เป็น behavior จาก W1 เพื่อเลี่ยง `SocketSend` ล้มหลัง connect; A3b ไม่ได้แก้ตามคำสั่ง และ test ใหม่เลิกวัด ladder จาก server side |

### Test
ไม่ได้รัน fast chaos gate/live gate ตามคำสั่ง.

รันเฉพาะ local/static checks:
```text
> python -m py_compile tests/chaos/test_wire_resilience.py brain/gateway/echo_server.py
exit 0

> python -m unittest tests.chaos.test_wire_resilience.WireResilienceTests.test_non_protocol_tcp_connection_is_not_logged_as_connect
.
----------------------------------------------------------------------
Ran 1 test in 0.535s

OK

> git diff --check -- brain/gateway/echo_server.py mt5-ea/Include/Farm/Wire.mqh tests/chaos/test_wire_resilience.py
exit 0
```

ยังไม่ได้ compile MQL5; รอ compile gate / fast chaos gate จาก Claude.

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`. ไม่ retry ด้วยสิทธิ์พิเศษเพราะ policy รอบนี้ไม่อนุญาต.
- ไม่ได้ commit.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- `Wire.mqh` string concat รอบ `DiagClockJson()` ว่า MetaEditor รับ syntax ได้จริงหรือไม่.
- เกณฑ์ 3b: ผมใช้ upper bound `nominal * 1.2 + 1.1` เพื่อรวม jitter + EventSetTimer(1) granularity; lower bound `nominal * 0.8`.
- `test_backoff_schedule_matches_spec` รอ 7 reconnect diag events เพื่อพิสูจน์ว่า 30 ค้างที่ cap แล้วใช้ 6 gaps แรกพิสูจน์ว่ารอจริง.

### คำถามค้าง
ไม่มี
