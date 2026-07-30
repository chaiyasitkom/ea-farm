---
id: 003
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 002
---

# W1 handoff - SocketSend fails after successful connect

## แก้อะไรบ้าง

- `mt5-ea/Include/Farm/Wire.mqh:722` คง `EnterState(WIRE_CONNECTED)` หลัง `SocketConnect()` สำเร็จ
- `mt5-ea/Include/Farm/Wire.mqh:723-725` เพิ่ม `SocketTimeouts(m_socket, m_connect_timeout_ms, m_connect_timeout_ms)` พร้อม WARN `socket_timeouts_failed err=...` ถ้าตั้ง timeout ไม่สำเร็จ
- `mt5-ea/Include/Farm/Wire.mqh:726` เพิ่ม INFO `socket_connected host=... port=...` ก่อน `SendHello()`

## เหตุผล

- ทำตามหลักฐานใน 002 ก่อน: `SocketTimeouts()` ไม่เคยถูกเรียก และอาจทำให้ `SocketSend()` fail ทันทีถ้า socket ยังไม่พร้อมเขียน
- ใช้ค่า timeout เดียวกับ connect timeout ที่มีอยู่แล้ว (`m_connect_timeout_ms`, default 3000ms) เพื่อไม่เพิ่ม config surface ใหม่ในรอบวินิจฉัย
- ยังไม่แตะสมมติฐานอื่น เพื่อให้รอบ chaos ถัดไปบอกได้ว่าการตั้ง send/receive timeout แก้ W1 หรือไม่

## สิ่งที่ยังไม่ได้ทำ

- ไม่ได้เลื่อน `SendHello()` ไป `Pump()` รอบถัดไป
- ไม่ได้เพิ่ม `SocketIsWritable()` ก่อน `SocketSend()`
- ไม่ได้แก้ logic buffer / `StringToCharArray()` / `SocketSend()` payload size
- ไม่ได้รัน MT5 compile gate และไม่ได้รัน `run-chaos.ps1` ตามข้อห้าม

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- ดูว่า MQL5 build ที่ใช้รองรับ signature `SocketTimeouts(m_socket, int, int)` แบบนี้หรือ compiler ต้องการ cast เป็น `uint`
- ดู event log ฝั่ง server หลังรัน chaos ว่า connection ยัง `client_closed` ภายใน ~15ms หรือเปลี่ยนเป็นรับ `HELLO` ได้แล้ว
- ถ้ายัง fail หลัง timeout ถูกตั้งสำเร็จ ค่อยไปสมมติฐานถัดไปเรื่องเลื่อน `SendHello()` ออกจากรอบ connect

## เบี่ยงเบนจาก spec

- มีการแตะ `mt5-ea/**` แม้ SPEC-016 §8 ระบุห้าม แต่ทำตาม W1 handoff 001/002 ที่สั่งแก้ `Wire.mqh` เพื่อวินิจฉัย socket send path โดยตรง
