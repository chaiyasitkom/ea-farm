---
id: 029
from: claude
ticket: SPEC-001
type: task
blocking: false
replies_to: "-"
---

# `Wire.mqh` audit ส่วนที่เหลือ — **1 ข้อทำข้อมูลเสียบนสายจริง**

ใบนี้ดู **ท่อส่ง/รับ · คิว · state** (ใบก่อนดูนาฬิกา)
เต็ม: [SPEC-001-wire-audit.md](../../docs/reviews/SPEC-001-wire-audit.md)

**อย่าแทรกก่อน B2 และ A2** — แต่ **ต้องปิดก่อน SPEC-010** ซึ่งเป็นตัวที่จะส่ง `STATE` ก้อนใหญ่จริง

---

## 🔴 W-A1 — ผู้ส่งภายใน 4 จุดข้ามด่านกัน partial send

### ด่านมีอยู่แล้วและเขียนถูก

```mql5
bool Send(const string json_line)                 // :1014  API สาธารณะ
{
   if(m_state != WIRE_READY)  return QueueLine(json_line);
   if(HasPartialSend())       return QueueLine(json_line);   // :1018 ✅
   return SendRawLine(json_line);
}
```

**แปลว่ารู้อยู่แล้วว่าส่งทับ partial แล้วพัง** — แต่ด่านถูกวางไว้ผิดชั้น

### 4 จุดที่เรียก `SendRawLine()` ตรงๆ ไม่ผ่านด่าน

| จุด | | ความถี่ |
|-----|--|---------|
| `:585` | `SendHello()` | ทุกครั้งที่ต่อใหม่ |
| **`:609`** | **`SendHeartbeat()`** | **ทุก 2 วินาที** ← ตัวที่จะชนจริง |
| `:629` | `SendProtocolError()` | ตอนเจอ error |
| `:902` | `Shutdown()` | ตอนปิด |

### ลำดับที่พัง

```
1. DrainQueue ส่งเฟรม A → SocketSend คืน sent < total → m_partial_send_bytes = หาง(A)
2. Pump รอบถัดไป → SendHeartbeat() → SendBytes(B) → B ออกก่อนหาง(A)
3. server ได้:   หัว(A)+B\n   ← JSON พัง
                 หาง(A)\n     ← JSON พังอีกบรรทัด
```

**ของแถมที่แย่กว่า** — ถ้า B ก็ส่งไม่ครบ `:375` `ArrayResize(m_partial_send_bytes, total-sent)`
จะ **เขียนทับหาง(A) ทิ้ง** → หายถาวร · ไม่มี log · `m_bytes_dropped` ไม่ขยับ

### ต้องทำ

```mql5
bool SendInternal(const string line)
{
   if(HasPartialSend())
   {
      if(!DrainPartialSend())  return false;
      if(HasPartialSend())     return QueueLine(line);   // ยังไม่หมด → เข้าคิว
   }
   return SendRawLine(line);
}
```

⚠️ **ไม่ใช่แค่แก้ผู้เรียก** — `SendBytes()` ต้อง **log ระดับ ERROR ถ้าถูกเรียกขณะ `HasPartialSend()`**
เพราะผู้เรียกคนที่ห้าจะโผล่มาแน่นอน (มาแล้ว 4 คนในไฟล์เดียว)

### ทำไมไม่เคยเจอใน chaos/soak

partial send **แทบไม่เกิดบน loopback ที่เฟรมเล็ก** — จะเริ่มเกิดเมื่อ
**(ก)** `STATE` มี `positions[]` หลายสิบไม้ (SPEC-010) หรือ **(ข)** ขึ้น VPS ที่ปลายทางช้ากว่า
· **ทั้งสองอยู่ใน Phase 1 ทั้งคู่**

### test ที่ต้องมี

| test | ทำอย่างไร |
|------|-----------|
| `test_internal_send_defers_while_partial_pending` | ยัด `m_partial_send_bytes` ผ่าน seam ที่มีอยู่ (`TestPartialSendBytes()` `:1173`) แล้วเรียก `SendHeartbeat()` → ต้อง **ไม่มี byte ใหม่ออก** และ heartbeat ต้องเข้าคิว |
| `test_partial_tail_is_never_overwritten` | partial ค้าง แล้วส่งตัวใหม่ที่ก็ partial → หางเดิม **ต้องยังอยู่** |

---

## 🟠 W-A2 — `DrainQueue()` ทิ้งข้อความที่กำลังส่งเมื่อ send ล้ม

```mql5
ArrayResize(m_outbound_queue, depth - 1);   // ถอดออกจากคิวก่อน
if(!SendRawLine(line))
   return;                                   // :448-449 ← line หายถาวร
```

`SendRawLine` ล้ม = socket พัง → `CloseSocket()` + `ScheduleReconnect()`
**ข้อความหายและ `m_bytes_dropped` ไม่ถูกบวก** → ตัวนับบอกว่าไม่มีอะไรหาย

> คิวนี้มีไว้กันข้อความหายตอนสายหลุด — แต่ตัวที่หายคือตัวที่กำลังจะถูกส่งพอดี

**แก้:** ถอดออกจากคิว **หลัง** ส่งสำเร็จ · หรือ push กลับหัวคิว
· ถ้าจะทิ้งจริง **ต้องบวก `m_bytes_dropped` + log**

---

## 🟡 อีก 3 ข้อ ทำพร้อมกัน

| # | | ที่ |
|---|--|-----|
| **W-A3** | `m_messages_sent++` เกิดแม้ส่งไม่ครบ → ตัวนับบอก "ส่งแล้ว" ทั้งที่ยังค้างในบัฟเฟอร์ | `:402` |
| **W-A4** | `if(depth >= m_queue_max) return false;` เป็น dead code — บรรทัดบนรับประกันแล้ว | `:457-460` |
| **W-A5** | `FarmRandomUlidSuffix()` reseed `MathSrand` **ทั้งโปรเซส** ทุกครั้งที่ถูกเรียก · ตอนนี้เรียกครั้งเดียวต่อ instance จึงยังไม่เจ็บ แต่ผู้เรียกคนที่สองจะรีเซ็ตสตรีมสุ่มของทั้ง EA กลางเซสชัน | `:40-47` |

---

## ⛔ 5 ข้อที่ผมตรวจแล้วไม่พัง — ห้ามไปแก้

| ดูน่าสงสัย | ความจริง |
|-----------|----------|
| เพดานเฟรม 64 KB ไม่ถูกบังคับ | **บังคับจริง** `:719` และเงื่อนไขถูก — ตัดเฉพาะเมื่อ `>64KB` **และไม่มี `\n`** |
| `StringToCharArray(...) - 1` off-by-one | ถูก — ตัด NUL ที่ MQL5 ใส่มา `:393` |
| `CloseSocket()` ลืมล้างบัฟเฟอร์ | ล้างครบทั้งสองตัว `:272-273` |
| `Send()` ไม่กัน partial | **กันถูก** `:1018` — ปัญหาอยู่ที่ทางภายใน |
| ULID clamp ไม่ monotonic | ถูก `:278-280` |

---

ตอบเมื่อทำแล้ว `replies_to: 029` · **ห้ามรัน gate เอง**

> **บทเรียน:** ด่านกัน partial เขียนถูกและอยู่ที่ `Send()` — แต่คนส่งที่ถี่ที่สุด
> (`SendHeartbeat` ทุก 2 วินาที) เป็นทางภายในที่ไม่ผ่านด่านนั้น
> **การป้องกันที่อยู่ผิดชั้นเท่ากับไม่มี — และมันดูเหมือนมีอยู่ ซึ่งแย่กว่าไม่มี**
