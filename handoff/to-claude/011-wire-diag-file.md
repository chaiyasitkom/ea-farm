---
id: 011
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 010
---

# Wire diag file

Diag path ที่ต้องอ่าน:

`C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\ea-farm-wire-diag.jsonl`

MQL5 เปิดด้วย `FILE_COMMON` ชื่อไฟล์ `ea-farm-wire-diag.jsonl`.

## Events

- ทุก `Pump()` เขียน JSONL:
  `ev`, `ts`, `state_start`, `state_end`, `read_loops`, `bytes_read`, `pump_us`
- ทุก `HandleInboundLine()` เขียน JSONL:
  `ev=inbound`, `ts`, `type`
- ทุก `EnterState()` เขียน JSONL:
  `ev=state`, `ts`, `from`, `to`, `reason`
- ทุก `ScheduleReconnect()` เขียน JSONL:
  `ev=reconnect`, `ts`, `backoff_sec`

ทุกบรรทัดเรียก `FileFlush()` ทันทีหลัง `FileWriteString()`.
เปิดไฟล์ครั้งเดียวใน `CWire.Init()` เมื่อ `m_verbose == true`.
ปิดไฟล์ใน `CWire.Shutdown()`.
ถ้าเปิดไฟล์ไม่ได้ log `WARN wire_diag_file_open_failed ...` แล้ว EA เดินต่อ.

## ยืนยันขอบเขต

ไม่ได้แก้ตรรกะ socket.
ไม่ได้แก้ตรรกะ state machine.
ไม่ได้แก้ backoff/reconnect behavior.
ไม่ได้แก้ parsing หรือ target-state protocol.

## pump_elapsed_us

ไม่ได้รัน MT5 compile gate หรือ `run-chaos.ps1` ตามคำสั่ง 010 จึงยังไม่มีตัวเลข runtime ใหม่ให้รายงาน.
ไฟล์ diag มี `pump_us` ทุก pump และ Experts log เดิมยังรายงาน `pump_p99_budget_warning_us` เมื่อ verbose และเกิน 20000 us.

## Gate

ไม่ได้รัน gate.
ไม่ได้รัน chaos.

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

ขอให้ดูว่า `reason` ของ `state` event เพียงพอต่อการแยก `HELLO_ACK rejected BAD_TOKEN/DUPLICATE_SESSION` ออกจาก `ScheduleReconnect` backoff ladder หรือไม่.
