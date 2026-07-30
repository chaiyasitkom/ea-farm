---
id: 013
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 012
---

# SocketRead fix

## แก้อะไร

- `mt5-ea/Include/Farm/Wire.mqh:693` เปลี่ยน `ReadAvailable()` จาก `while(SocketIsReadable(m_socket))` เป็น `while(true)` แล้วอ่าน `avail` เป็นจำนวน byte ที่พร้อมอ่านจริง
- `mt5-ea/Include/Farm/Wire.mqh:695-704` เพิ่ม `const uint avail = SocketIsReadable(m_socket)`, `break` เมื่อ `avail == 0`, คำนวณ `want = MathMin(FARM_WIRE_READ_CHUNK_BYTES, avail)`, `ArrayResize(buf, want)`, และเรียก `SocketRead(..., want, 0)`
- `mt5-ea/Include/Farm/Wire.mqh:983-1002` คง diag `ev:"pump"` ที่มี `read_loops`, `bytes_read`, `pump_us` ไว้ และเพิ่ม diag แยก `ev:"pump_slow"` เมื่อ `pump_us > 20000`

## เหตุผล

`SocketIsReadable()` คืนจำนวน byte ที่อ่านได้ ไม่ใช่ boolean readiness flag แบบทั่วไป ดังนั้นการใช้เป็นเงื่อนไข bool แล้วขอ `SocketRead` 4096 byte เสมอทำให้ `SocketRead` รอ byte ที่ไม่มีจริงจน timeout/ปิด socket ได้ การจำกัด `SocketRead` ไม่เกิน `avail` ทำให้ read path เป็น non-blocking ตาม intent ของ SPEC-001 §1.7

## สิ่งที่ยังไม่ได้ทำ

- ไม่ได้รัน MT5 compile gate
- ไม่ได้รัน `run-chaos.ps1`
- `git pull` ล้มเหลวก่อนแก้ เพราะเปิด `.git/FETCH_HEAD` ไม่ได้: `Permission denied`

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- ขอให้ตรวจ compile จริงว่า MQL5 รับ `MathMin((uint)FARM_WIRE_READ_CHUNK_BYTES, avail)` และ cast เป็น `int` ตามที่คาด
- ขอให้ดู diag หลัง gate ว่า `pump_slow` ไม่เกิดใน happy path และถ้าเกิดจะมี `read_loops`, `bytes_read`, `pump_us` ครบ

## เบี่ยงเบนจาก spec

ไม่มี
