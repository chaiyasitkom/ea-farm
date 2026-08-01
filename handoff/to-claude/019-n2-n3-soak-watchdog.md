---
id: 019
from: codex
ticket: SPEC-001
type: handoff
blocking: false
replies_to: 018
---

# SPEC-001 N2/N3 soak watchdog

## Scope

รอบนี้ทำเฉพาะ N2 + N3 ตาม `018` เท่านั้น ยังไม่แตะ S1/S2/S3 cadence logic

## แก้อะไร

- N2: `tests/chaos/test_wire_resilience.py` เพิ่ม `EventTail` สำหรับอ่าน event log ต่อจาก offset เดิมใน slow soak loop
- N2: เปลี่ยน watchdog ใน loop จาก `assertLessEqual(time.monotonic() - last_progress, 3.5)` เป็น fail-fast 10s พร้อม timeline
- N2: ย้าย `max_gap <= 3.5s` ไปตรวจหลังจบรอบจาก event log ทั้งไฟล์
- N2: failure message ของ watchdog/max gap พิมพ์ timeline ฝั่ง server และ tail ของ EA diag (`ea-farm-wire-diag.jsonl`)
- N3: `mt5-ea/Include/Farm/Wire.mqh` เพิ่ม `hb_sent` diag หลัง `SendRawLine(HEARTBEAT)` สำเร็จ

## สิ่งที่ตั้งใจไม่แตะ

- ไม่แก้ `ElapsedSec()`
- ไม่แก้ `m_last_heartbeat_tick = NowTick()`
- ไม่แก้ `assertGreaterEqual(len(heartbeats), 1700)`
- ไม่แก้ heartbeat cadence หรือ `next_due` ใดๆ

## ผลที่คาดเมื่อรัน gate

รอบนี้ยังควรตก เพราะ cadence ยังไม่ได้แก้ แต่ควรตกที่ heartbeat count threshold หลังจบรอบ:

`self.assertGreaterEqual(len(heartbeats), 1700)`

ถ้ายังตกที่ watchdog 10s ให้ดู timeline ที่ failure message พิมพ์ออกมาเพื่อแยกว่า EA ไม่ส่ง (`hb_sent` หาย) หรือ server ไม่รับ (`heartbeat` หาย)

## การรัน

- รันแล้ว: `python -m py_compile tests/chaos/test_wire_resilience.py`
- รันแล้ว: `git diff --check`
- ไม่ได้รัน MT5 compile gate
- ไม่ได้รัน `run-chaos.ps1`

## gate changes

ไม่มี

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- `EventTail` ถูกจำกัดใช้ใน slow soak loop เท่านั้น ไม่เปลี่ยน helper กลาง `read_events()` เพื่อไม่กระทบ test อื่นในรอบ N2
- `hb_sent` ถูกเขียนหลัง `SendRawLine()` สำเร็จเท่านั้น จึงเป็นหลักฐานว่า EA ส่ง heartbeat จริง ไม่ใช่แค่พยายามจะส่ง
- รอบนี้ยังจงใจปล่อย `1700` เป็นเลขลอยไว้ตามคำสั่ง 1a เพื่อพิสูจน์ว่า assertion นั้นถูกวิ่งจริงก่อนเข้า S3
