---
id: 029
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: "028"
---

# SPEC-001 A3 W2 + Fast Heartbeat Gate

## SPEC-001 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** not committed per instruction

### ทำอะไรไปแล้ว
- `brain/gateway/echo_server.py:86` เพิ่ม `protocol_seen` และย้าย `log_event("connect")` ไปหลัง `json.loads()` สำเร็จที่ `:121-126`.
- `brain/gateway/echo_server.py:92-101` connection ที่ไม่ส่ง protocol จน timeout/ปิด socket จะ return โดยไม่ log `connect`, `client_closed`, หรือ `disconnect`.
- `brain/gateway/echo_server.py:124-126` คง semantics สำหรับ chaos `--close-on-accept` ให้ปิดหลังเห็น frame protocol แรก เพื่อให้ test backoff ยังใช้ `connect` event วัด ladder ได้.
- `tests/chaos/test_wire_resilience.py:253` เพิ่ม unit test ว่า TCP connection ที่ไม่ส่ง protocol ไม่ถูกนับเป็น `connect`, แต่ HELLO จริงยังถูกนับ.
- `tests/chaos/test_wire_resilience.py:33,422` เพิ่ม `test_heartbeat_interval_within_5pct_over_5min` เข้า `LiveChartChaosTests` โดยไม่มี slow marker.

### วิธีที่ทำให้ ladder ยังวัดได้ถูกหลังแก้ W2
- `test_backoff_schedule_matches_spec` ใช้ `--close-on-accept` และอ่าน event `connect`.
- หลัง A3 `connect` ไม่ใช่ TCP accept แล้ว แต่เป็น "connection แรกที่ส่ง JSON frame ได้"; EA ส่ง HELLO ทันทีหลัง TCP connect ตาม SPEC-001, ดังนั้น timestamp ที่ใช้วัด ladder คือเวลาที่ HELLO แรกมาถึง server ในแต่ละ attempt.
- `--close-on-accept` ถูกเลื่อนมาปิดหลัง log `connect` ของ frame แรก ไม่ใช่ปิดก่อนอ่าน frame; ทำให้ backoff server ยังสร้างหนึ่ง `connect` event ต่อหนึ่ง EA attempt และไม่ถูก chrome/noise TCP แทรก.

### gate changes
- ไม่ได้แก้ `tools/**`.
- ตรวจ `tools/run-chaos.ps1` แล้ว fast gate ยังตรวจเฉพาะ `skipped=1`; การเพิ่ม fast live test ทำให้จำนวน test เพิ่ม แต่ slow skip ยังมีตัวเดียวคือ `test_no_heartbeat_loss_over_1h`.
- ไม่พบ required list ของชื่อ test ใน `run-chaos.ps1`; จึงไม่ต้องอัปเดต tools.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|---|---|---|---|
| ไม่มี | - | - | ไม่มี |

### Test
ไม่ได้รัน chaos gate ตามคำสั่ง.

รันเฉพาะ unittest ที่ไม่ใช้ live MT5:

```text
python -m unittest tests.chaos.test_wire_resilience.WireResilienceTests
........
----------------------------------------------------------------------
Ran 8 tests in 2.047s

OK
```

```text
python -m unittest tests.chaos.test_wire_resilience
sssssss........
----------------------------------------------------------------------
Ran 15 tests in 2.056s

OK (skipped=7)
```

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้รัน live fast gate หรือ slow gate ตามคำสั่ง.
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`; ไม่ได้แก้ `.git`.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- `--close-on-accept` ตอนนี้ปิดหลัง frame JSON แรก ไม่ใช่หลัง TCP accept ดิบ เพื่อให้ W2 กับ backoff ladder อยู่ร่วมกันได้.
- fast heartbeat test วัด `mean_gap` ในช่วง 5 นาทีด้วยเกณฑ์ `HEARTBEAT_SEC * 0.95..1.05` และยังมี progress timeout 10s เหมือน soak.

### คำถามค้าง
- ไม่มี
