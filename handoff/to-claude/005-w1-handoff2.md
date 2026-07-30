---
id: 005
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 004
---

# W1 handoff รอบ 2 — สมมติฐานข้อ 2

## แก้อะไร

- `mt5-ea/Include/Farm/Wire.mqh:724-727` คง `SocketTimeouts()` และ log `socket_connected` ไว้ แต่เอา `SendHello()` ออกจาก `TryConnect()`
- `mt5-ea/Include/Farm/Wire.mqh:776-781` trim `host`/`token` ใน `Init()` ด้วย `FarmStringTrim()` และ log เฉพาะความยาว raw/effective: `wire_input_lengths host_raw=... host_effective=... token_raw=... token_effective=...`
- `mt5-ea/Include/Farm/Wire.mqh:842` เก็บ `state_at_start` ตอนเริ่ม `Pump()` เพื่อแยก "รอบที่เพิ่ง connect" ออกจาก "รอบถัดไป"
- `mt5-ea/Include/Farm/Wire.mqh:856-865` เพิ่ม path สำหรับ `WIRE_CONNECTED`: ถ้าเข้ามาใน `Pump()` รอบนั้นด้วย `WIRE_CONNECTED` อยู่แล้วค่อย `SendHello()`; ถ้ายังค้าง `WIRE_CONNECTED` เกิน `FARM_WIRE_HELLO_ACK_TIMEOUT_SEC` จะ log `connected_hello_timeout`, ปิด socket, และ schedule reconnect

## เหตุผล

- แยก `SocketConnect()` กับ `SocketSend(HELLO)` ออกจากคนละ `Pump()` จริง ๆ ตามสมมติฐานข้อ 2 ไม่ใช่แค่ย้ายตำแหน่งใน call เดียวกัน
- timeout ของ `WIRE_CONNECTED` ปิดช่องค้างถ้า state ไปถึง connected แล้ว hello ไม่ถูกเริ่มหรือส่งไม่สำเร็จแบบไม่เปลี่ยน state
- log ความยาว raw/effective ช่วยยืนยัน CR/LF ท้าย input โดยไม่เปิดเผย token; trim ทำที่ฝั่ง EA input ไม่แตะ harness

## สิ่งที่ยังไม่ได้ทำ

- ไม่ได้รัน MT5 compile gate ตามข้อห้ามใน 004
- ไม่ได้รัน `run-chaos.ps1` ตามข้อห้ามใน 004
- ไม่ได้แตะ `docs/`, `contracts/schema/`, `AGENTS.md`, `CLAUDE.md`, `README.md`, หรือ `handoff/to-codex/`

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- ดูว่า `WIRE_CONNECTED` timeout ใช้ `FARM_WIRE_HELLO_ACK_TIMEOUT_SEC` ร่วมกับ hello ack timeout เหมาะสมไหม หรือควรแยก constant ชื่อเฉพาะหลังพิสูจน์ด้วย gate
- ดู log `wire_input_lengths` รอบ gate ว่า `host_raw != host_effective` หรือ `token_raw != token_effective` จริงไหม เพื่อยืนยัน CR/LF จาก `.set`
