---
id: 037
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: "036"
---

## SPEC-001 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### ทำอะไรไปแล้ว
- `tests/chaos/test_wire_resilience.py`: เพิ่ม `TIMER_PERIOD_SLOP_SEC = 1.5` พร้อม comment ว่าเป็นหนึ่งคาบ `EventSetTimer(1)` บวก Windows scheduling slop.
- `tests/chaos/test_wire_resilience.py`: เปลี่ยน backoff upper bound จาก `nominal * 1.2 + 1.0` เป็น `nominal * 1.2 + TIMER_PERIOD_SLOP_SEC`.
- Lower bound ยังเป็น `nominal * 0.8` ตามเดิม.

### เบี่ยงเบนจาก spec
ไม่มี

### Test
- ไม่ได้รัน gate ตามคำสั่งรอบนี้.
- ไม่ได้รัน churn ตามคำสั่งรอบนี้.
- ไม่ได้รัน chaos test เพราะผู้ใช้ห้ามรัน gate และงานนี้เป็นการปรับ tolerance เล็กใน chaos suite.

### Gate changes
ไม่มี

### ตรวจค่าคงที่เวลาอื่นในไฟล์เดียวกัน
- `test_bad_token_waits_60s`: มี threshold `59.0` sec สำหรับ retry delay.
- `test_ea_handles_duplicate_session_rejection`: มี threshold `55.0` sec สำหรับ retry delay.
- `test_heartbeat_gap_triggers_reconnect`: มีช่วง `4.0` ถึง `12.0` sec.
- heartbeat progress watchdog ใช้ `10.0` sec สองจุด.
- heartbeat interval/soak ใช้ tolerance `0.95` และ `1.05`.
- ยังไม่ได้แก้ตามคำสั่งรอบนี้.

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`.
- ใน `handoff/to-codex/` local ไม่มีไฟล์ `036`; อาจเป็นผลจาก pull ไม่สำเร็จ แต่ handoff นี้ตั้ง `replies_to: "036"` ตามคำสั่ง.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- ค่า `TIMER_PERIOD_SLOP_SEC = 1.5` ถูกตั้งจากกลไก timer cadence + Windows scheduling slop ไม่ได้ fit จาก waits ที่วัดได้.
- ค่าคงที่เวลาอื่นที่รายงานด้านบนควรถูกตั้งชื่อหรือไม่ในรอบถัดไป.

### คำถามค้าง
ไม่มี
