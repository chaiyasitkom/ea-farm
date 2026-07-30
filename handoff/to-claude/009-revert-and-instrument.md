---
id: 009
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 008
---

# SPEC-016: revert F1 + pump diagnostics

## สิ่งที่ revert

- Revert เฉพาะ F1 ใน `mt5-ea/Include/Farm/Wire.mqh` จาก commit `dd68613`:
  - `ReadAvailable()` กลับมา guard `m_socket == INVALID_HANDLE || !SocketIsConnected(m_socket)`
  - `Pump()` กลับไปเช็ค `!SocketIsConnected()` ก่อน `ReadAvailable()`
  - เอา `ReadAvailable()` รอบ drain-before-disconnect ออก
  - เอา guard หลัง `HandleInboundLine(line)` ที่เพิ่มใน F1 ออก
- ไม่แตะ deferred hello จาก `262c28d`
- ไม่แตะ `SocketTimeouts()` จาก `e04b9ba`

Commit: `2715ba9 SPEC-016: revert drain-before-disconnect`

## log วินิจฉัยที่เพิ่ม

- เพิ่ม counter ใน `ReadAvailable(int &read_loops, int &bytes_read)`:
  - `read_loops` นับจำนวนรอบที่เข้า `while(SocketIsReadable(...))`
  - `bytes_read` สะสมจำนวน byte จาก `SocketRead()` ที่อ่านได้จริง (`n > 0`)
- เพิ่ม `INFO` log ทุก `Pump()` เฉพาะเมื่อ `m_verbose == true`:

```text
pump_diag state_start=<state> state_end=<state> read_loops=<n> bytes_read=<n> pump_elapsed_us=<n>
```

- เพิ่ม overload `WireStateText(const ENUM_WIRE_STATE state)` เพื่อ log state snapshot ตอนเริ่ม Pump โดยคง `WireStateText()` เดิมไว้

Commit: `6486cb2 SPEC-016: instrument wire pump diagnostics`

## ยืนยันขอบเขต

- ไม่เปลี่ยนพฤติกรรม state machine เพิ่มเติมหลัง revert F1
- ไม่แก้ docs, contracts/schema, AGENTS.md, CLAUDE.md, README.md, หรือ handoff/to-codex
- ไม่เพิ่ม dependency
- ไม่รัน MT5 compile gate
- ไม่รัน `run-chaos.ps1`

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- รูปแบบ log `pump_diag` เพียงพอกับ chaos analysis หรือควรเปลี่ยนชื่อ field ก่อนรัน gate
- ยืนยันว่า compile ฝั่ง MQL5 รับ overload `WireStateText(const ENUM_WIRE_STATE state)` และ reference params ใน `ReadAvailable(int &, int &)` ตามที่คาด
