---
id: 007
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 006
---

# F1 handoff - drain socket before disconnect decision

## แก้อะไร

- `mt5-ea/Include/Farm/Wire.mqh:615` ปรับ `ReadAvailable()` ให้ return เฉพาะเมื่อ socket handle invalid ไม่ return เพียงเพราะ `SocketIsConnected()` เป็น false
- `mt5-ea/Include/Farm/Wire.mqh:653` เพิ่ม guard หลัง `HandleInboundLine()` เพื่อออกจาก read loop ทันทีถ้า handler ปิด socket แล้ว เช่น `HELLO_ACK accepted=false`
- `mt5-ea/Include/Farm/Wire.mqh:849` ย้าย `ReadAvailable()` มาอยู่ก่อนการตัดสิน disconnect ใน `Pump()`
- `mt5-ea/Include/Farm/Wire.mqh:851` ถ้าเห็น peer disconnected จะ drain อีกหนึ่งรอบก่อน `CloseSocket()` + `ScheduleReconnect()`

## เหตุผล

- TCP อนุญาตให้อ่าน bytes ที่รับเข้ามาแล้วได้แม้ peer ปิด connection แล้ว
- ลำดับเดิมปิด socket ก่อนอ่าน buffer ทำให้ `HELLO_ACK` ที่ server ส่งแล้วถูกทิ้ง และ EA เข้า backoff ladder แทน `WIRE_FAILED_AUTH`
- ลำดับใหม่ให้ `HELLO_ACK` ที่ค้างอยู่ถูก parse ก่อน ถ้า reject จะ `CloseSocket()` และ `EnterState(WIRE_FAILED_AUTH)` จาก handler โดยไม่ schedule reconnect ทับ
- ไม่เพิ่ม loop ใหม่: ยังใช้ loop เดิมที่หยุดเมื่อ `SocketIsReadable()` false หรือ `SocketRead()` ได้ 0 และรอบ drain เพิ่มเกิดเฉพาะตอนตรวจพบ disconnect

## สิ่งที่ยังไม่ได้ทำ

- ไม่ได้แก้ F2 tolerance
- ไม่ได้แก้ F3/W2 เรื่องนับ TCP connect ที่ไม่พูด protocol
- ไม่ได้แก้ harness, docs, contracts/schema, AGENTS.md, CLAUDE.md, README.md หรือ handoff/to-codex
- ไม่ได้รัน MT5 compile gate และไม่ได้รัน `run-chaos.ps1` ตามข้อห้าม

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดู

- ช่วยดูว่า MQL5 runtime ของ `SocketIsReadable(m_socket)` ยัง report readable ได้ถูกต้องในเคส peer ปิดแล้วแต่ receive buffer มีข้อมูลค้าง
- ช่วยยืนยันจาก chaos ว่า `test_bad_token_waits_60s` ขยับจาก ~32s ไปเป็น ~60s และ event log เห็น reject path เข้า `WIRE_FAILED_AUTH`
- ช่วยดู p99 pump metric รอบ chaos ว่าการ drain เพิ่มเฉพาะ disconnect path ไม่ดันเกินงบ 20ms

## คำถามค้าง

ไม่มี
