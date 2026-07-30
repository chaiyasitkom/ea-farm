---
id: 001
from: claude
ticket: SPEC-016
type: task
blocking: false
replies_to: "-"
---

# W1 · `SocketSend` ล้มเหลว 100% หลัง connect สำเร็จ — บล็อก chaos ทั้งชุด

รายละเอียดเต็มอยู่ที่ [`work-order.md` §W1](../../docs/work-order.md)
· review: [`SPEC-016-chaos-02.md`](../../docs/reviews/SPEC-016-chaos-02.md)

## หลักฐาน (ผมรันเอง 2026-07-31 00:25–00:35)

```
00:30:43.323  INFO  broker_time valid=true offset=3600
00:30:44.329  WARN  socket_send_failed err=5273     ← 1 วินาทีหลัง OnInit
00:30:50.330  WARN  hello_ack_timeout
```

| นับทั้งรอบ | |
|---|---|
| `err=5273` (`ERR_NETSOCKET_IO_ERROR`) | **20** |
| `hello_ack_timeout` | **13** |
| `wire_ready` | **0** |
| `err=4014` | **0** ✅ whitelist ใช้ได้แล้ว |

เกิดที่ `mt5-ea/Include/Farm/Wire.mqh:294` — `SocketSend(m_socket, data, (uint)total)` คืน < 0

## ทำข้อนี้ก่อน แล้วค่อยไล่สาเหตุ

`Wire.mqh` ตอนนี้**ไม่มี log เมื่อ `SocketConnect` สำเร็จ** → อ่าน log แล้วแยกไม่ออกว่า
*"ต่อไม่ติด"* กับ *"ต่อติดแล้วส่งไม่ได้"* · ผมไล่ผิดทางหลายรอบเพราะข้อนี้

```mql5
EnterState(WIRE_CONNECTED);
m_log.Info(StringFormat("socket_connected host=%s port=%d", m_host, m_port));
```

## ข้อสงสัย เรียงตามความน่าจะเป็น — **แก้ทีละข้อ รันดู**

1. **ส่งเร็วเกินไป** — `SendHello()` ถูกเรียกใน `TryConnect()` ซึ่งอยู่ใน `Pump()` รอบเดียว
   กับที่เพิ่ง `SocketConnect` → ลองเลื่อนไปส่งใน `Pump()` รอบถัดไป (state `WIRE_CONNECTED` มีอยู่แล้ว)
2. ไม่ได้ตรวจ `SocketIsWritable()` ก่อนส่ง
3. ขนาด/รูปแบบ array ที่ส่งเข้า `SocketSend` → log `total` + `ArraySize(data)` ตอนล้ม
4. whitelist อนุญาต connect แต่ไม่อนุญาต I/O — ไม่น่าใช่ ตัดออกด้วยข้อ 1–3 ก่อน

**ห้ามแก้หลายข้อพร้อมกัน** — คืนนี้พิสูจน์แล้วว่าเปลี่ยนสองตัวแปรพร้อมกันแล้วเขียว
เราจะไม่มีวันรู้ว่าอะไรคือสาเหตุ แล้วต้องไล่ใหม่ทั้งหมดตอนขึ้น VPS

## สภาพแวดล้อมพร้อมแล้ว

whitelist MT5 ตั้งเสร็จและ**ยืนยันด้วยไฟล์**แล้ว (`common.ini` → `WebRequest=1` · `WebRequestUrl` ไม่ว่าง)
· พอร์ตมาตรฐาน `45001` (`EA_FARM_CHAOS_PORT`)
· ขั้นตอนตั้งค่าเต็มอยู่ใน [review chaos รอบ 2](../../docs/reviews/SPEC-016-chaos-02.md)

⚠️ **ก่อนวัดผลใดๆ ให้ทำ W3 ก่อน** (ลบ `chart*.chr`) ไม่งั้นจะเจอ false pass
แบบเดียวกับที่ผมเจอ — EA หลายตัวตอบสลับกันแล้วดูเหมือนผ่าน

## เสร็จแล้วตอบกลับ

สร้าง `handoff/to-claude/002-<slug>.md` · `type: handoff` · `replies_to: 001`
พร้อม **output จริงของ `run-chaos.ps1`** ไม่ใช่คำบรรยาย
