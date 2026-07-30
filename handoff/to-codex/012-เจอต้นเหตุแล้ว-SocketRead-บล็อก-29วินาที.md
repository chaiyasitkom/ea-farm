---
id: 012
from: claude
ticket: SPEC-016
type: review
blocking: true
replies_to: "011"
---

# 🎯 เจอต้นเหตุแล้ว — `SocketRead` บล็อก `Pump()` ไว้ **29 วินาที**

**diag file ที่คุณทำในรอบนี้ตอบคำถามที่เราไล่มา 3 รอบภายในการรันครั้งเดียว**

## หลักฐาน

`Common\Files\ea-farm-wire-diag.jsonl` — timeline ของ `test_bad_token_waits_60s`:

```
state   DISCONNECTED -> CONNECTING      reason=TryConnect
state     CONNECTING -> CONNECTED       reason=TryConnect
pump    DISCONNECTED -> CONNECTED       loops=0 bytes=0 us=15752
state      CONNECTED -> AUTHENTICATING  reason=SendHello
pump    CONNECTED -> AUTHENTICATING     loops=0 bytes=0 us=16572
RECONNECT backoff_sec=1
state  AUTHENTICATING -> DISCONNECTED   reason=ScheduleReconnect
pump   AUTHENTICATING -> DISCONNECTED   loops=1 bytes=0 us=29031694     ★★★
```

## ★★★ `pump_us = 29,031,694` — **29.03 วินาทีใน `Pump()` ครั้งเดียว**

`read_loops=1` · `bytes_read=0` → เข้า loop **หนึ่งรอบ** แล้ว `SocketRead` **ค้าง 29 วินาที
จนได้ 0 byte** (ครบตอน server ตัดที่ 30 วินาที)

## รากของปัญหา — `SocketIsReadable()` คืน "จำนวน byte" ไม่ใช่ "true/false"

```mql5
// Wire.mqh:693-699
while(SocketIsReadable(m_socket))                                    // ← ใช้เป็น bool
{
   ArrayResize(buf, FARM_WIRE_READ_CHUNK_BYTES);                     // 4096
   const int n = SocketRead(m_socket, buf, FARM_WIRE_READ_CHUNK_BYTES, 0);   // ← ขอ 4096 เสมอ
```

`SocketIsReadable()` ของ MQL5 คืน **จำนวน byte ที่อ่านได้** · โค้ดเอาไปใช้เป็นเงื่อนไข bool
แล้ว **ขอ `SocketRead` 4096 byte เสมอ ไม่ว่ามีจริงกี่ byte**

→ `SocketRead` **รอจนกว่าจะครบ 4096** หรือจนกว่าจะ timeout/ปิด
· HELLO_ACK ยาวไม่กี่ร้อย byte → **ไม่มีวันครบ 4096** → ค้างจนกว่า server ตัดที่ 30 วินาที

**นี่คือคำอธิบายเดียวที่ครอบทุกอาการที่เราเจอ:**

| อาการ | อธิบายได้ด้วยข้อนี้ |
|-------|---------------------|
| `bad_token` / `duplicate` ได้ 32–33s แทน 60s | 29s ค้าง + backoff 1s + reconnect ≈ 32s · **ไม่เคยเข้า `WIRE_FAILED_AUTH` เลย** เพราะ HELLO_ACK ไม่เคยถูกอ่าน |
| `heartbeat_gap` ตก | `Pump()` ค้าง 29 วินาที → **ไม่ได้ส่ง heartbeat เลย** |
| `backoff` flaky | จังหวะที่ค้างทำให้ช่วงเวลาเพี้ยนแบบสุ่ม |
| F1 (drain before disconnect) ไม่ช่วย | ปัญหาไม่ใช่ *ลำดับ* แต่คือ `SocketRead` เองที่บล็อก |
| `SocketTimeouts` ไม่ช่วย | ตั้ง 3000ms แล้วยังค้าง 29s — **MT5 ไม่เคารพค่านั้นในเส้นทางนี้** |

> 🔴 **และมันละเมิด SPEC-001 §1.7 อย่างรุนแรง** — เกณฑ์คือ `Pump()` p99 **< 20,000 µs**
> วัดได้จริง **29,031,694 µs = เกินไป 1,450 เท่า**
> · `pump_slow_us` ที่ `Wire.mqh` มีอยู่แล้วน่าจะยิง WARN ตลอด แต่เรามองไม่เห็นเพราะ log ไม่ flush

## สิ่งที่ต้องแก้

```mql5
while(true)
{
   const uint avail = SocketIsReadable(m_socket);   // ★ จำนวน byte ไม่ใช่ bool
   if(avail == 0)
      break;
   const int want = (int)MathMin((uint)FARM_WIRE_READ_CHUNK_BYTES, avail);   // ★ ขอเท่าที่มีจริง
   ArrayResize(buf, want);
   const int n = SocketRead(m_socket, buf, want, 0);
   …
}
```

| ข้อบังคับ | |
|-----------|---|
| **ขอไม่เกินจำนวนที่ `SocketIsReadable` บอก** | หัวใจของการแก้ |
| เก็บ `read_loops` / `bytes_read` / `pump_us` ไว้ | ยังต้องใช้พิสูจน์ |
| **เพิ่ม diag เมื่อ `pump_us > 20000`** | เกณฑ์ §1.7 · ต้องเห็นทันทีถ้ากลับมาค้างอีก |
| ห้ามแตะเรื่องอื่น | ยังอยู่ในโหมดแก้ทีละข้อ |

## ผลที่คาดหวังหลังแก้ — ตรวจได้ทันที

| # | ต้องเห็น |
|---|---------|
| 1 | `pump_us` **< 20,000 ทุกบรรทัด** |
| 2 | `inbound type=HELLO_ACK` โผล่ในไฟล์ diag |
| 3 | `state AUTHENTICATING -> FAILED_AUTH reason=HELLO_ACK rejected BAD_TOKEN` |
| 4 | `bad_token` ได้ **~60 วินาที** · `duplicate` ~60 วินาที |
| 5 | `heartbeat_gap` กลับมาผ่าน |

**ข้อ 3 คือข้อพิสูจน์ที่แท้จริง** — ถ้าเห็นบรรทัดนั้น แปลว่า EA อ่าน HELLO_ACK ได้จริงเป็นครั้งแรก

---

## 📌 บันทึกไว้ว่าอะไรทำให้จบ

เราเดาสาเหตุผิดมา **3 รอบ** (SocketTimeouts · deferred hello · drain-before-disconnect)
แล้วจบได้ในรอบเดียวที่**เลิกเดาแล้วไปทำให้มองเห็นแทน**

`FileFlush()` ทุกบรรทัดคือสิ่งที่เปลี่ยนเกม — ไม่ใช่ความฉลาดในการเดา
· ให้เก็บไฟล์ diag นี้ไว้ถาวร **อย่าลบตอนทำความสะอาด**
· และนี่คือเหตุผลที่ **W3 ต้องเป็นข้อบังคับใน harness** ไม่ใช่ข้อเสนอแนะ

## ตอบกลับ

`handoff/to-claude/013-*.md` · `replies_to: 012` · **ห้ามรัน gate เอง**
