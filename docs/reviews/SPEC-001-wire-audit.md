# `Wire.mqh` — audit ส่วนที่เหลือ (ไม่ใช่เรื่องเวลา)

**วันที่:** 2026-08-01 · **โดย:** Claude
**คู่กับ:** [audit เวลา 11 จุด](SPEC-001-timing-audit.md) — ใบนั้นดูนาฬิกา · ใบนี้ดู **ท่อส่ง/รับ · คิว · state**

---

## 1. 🔴 W-A1 — partial send ถูกข้ามโดยผู้ส่งภายใน 4 จุด → **byte สลับบนสาย**

### หลักฐานว่าอันตรายข้อนี้ "รู้อยู่แล้ว"

```mql5
bool Send(const string json_line)          // :1014  ← API สาธารณะ
{
   if(m_state != WIRE_READY)  return QueueLine(json_line);
   if(HasPartialSend())       return QueueLine(json_line);   // :1018 ✅ ป้องกันถูกต้อง
   return SendRawLine(json_line);
}
```

**ด่านนี้มีอยู่แล้วและถูกต้อง** — แปลว่าคนเขียนรู้ว่าถ้ามี partial ค้างแล้วส่งทับจะพัง

### แต่ผู้ส่งภายในทั้ง 4 จุด **ไม่ผ่านด่านนี้เลย**

| จุด | ฟังก์ชัน | ความถี่ |
|-----|---------|---------|
| `:585` | `SendHello()` | ทุกครั้งที่ต่อใหม่ |
| **`:609`** | **`SendHeartbeat()`** | **ทุก 2 วินาที** ← ตัวที่จะชนจริง |
| `:629` | `SendProtocolError()` | ตอนเจอ error |
| `:902` | `Shutdown()` | ตอนปิด |

ทั้งสี่เรียก `SendRawLine()` → `SendBytes()` **ตรงๆ**

### ลำดับที่ทำให้พัง

```
1. DrainQueue ส่งเฟรม A ขนาดใหญ่ → SocketSend คืน sent < total
   → m_partial_send_bytes = หาง(A)                          :373-378

2. Pump รอบถัดไป → SendHeartbeat() → SendRawLine(B) → SendBytes(B)
   → B ถูกส่ง "ก่อน" หาง(A)

3. สิ่งที่ server ได้รับ:
      หัว(A) + B\n     ← JSON พังหนึ่งบรรทัด
      หาง(A)\n         ← JSON พังอีกหนึ่งบรรทัด
```

### และมีของแถมที่แย่กว่า

```mql5
if(sent < total)
{
   ArrayResize(m_partial_send_bytes, total - sent);   // :375 ← เขียนทับ หาง(A) ทิ้ง
   for(int i = sent; i < total; i++)
      m_partial_send_bytes[i - sent] = data[i];
}
```

ถ้า **B ก็ส่งไม่ครบ** → `m_partial_send_bytes` ถูกเขียนทับด้วยหางของ B
→ **หาง(A) หายถาวร ไม่มี log ไม่มีตัวนับ** · `m_bytes_dropped` ไม่ขยับ

### แก้

ให้ทั้ง 4 จุดผ่านด่านเดียวกับ `Send()`:

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

⚠️ **`SendBytes()` ต้อง `Assert`/log ถ้าถูกเรียกขณะ `HasPartialSend()`** — ไม่ใช่แค่แก้ผู้เรียก
เพราะผู้เรียกคนที่ห้าจะโผล่มาในอนาคตแน่นอน (มาแล้ว 4 คนในไฟล์เดียว)

### ความน่าจะเป็นจริง

บน loopback ที่เฟรมเล็ก partial send **แทบไม่เกิด** — จึงไม่เคยโผล่ใน chaos/soak
แต่จะเริ่มเกิดเมื่อ **(ก)** `STATE` มี `positions[]` หลายสิบไม้ (SPEC-010) หรือ
**(ข)** ย้ายขึ้น VPS ที่ปลายทางช้ากว่า · **ทั้งสองอย่างอยู่ใน Phase 1 ทั้งคู่**

---

## 2. 🟠 W-A2 — `DrainQueue()` ทิ้งข้อความที่กำลังส่งเมื่อ send ล้ม

```mql5
const string line = m_outbound_queue[0];
for(int i = 1; i < depth; i++)  m_outbound_queue[i-1] = m_outbound_queue[i];
ArrayResize(m_outbound_queue, depth - 1);        // ← ถอดออกจากคิวแล้ว
if(!SendRawLine(line))
   return;                                        // :448-449 ← line หายไปเลย
```

`SendRawLine` ล้ม = `SocketSend` คืนค่าลบ → `CloseSocket()` + `ScheduleReconnect()`
**ข้อความที่เพิ่งถอดออกมาหายถาวร** และ **`m_bytes_dropped` ไม่ถูกบวก**

> คิวนี้มีไว้กันข้อความหายตอนสายหลุด — **แต่ตัวที่หลุดคือตัวที่กำลังจะถูกส่งพอดี**
> ซึ่งเป็นตัวที่สำคัญที่สุดในคิว

**แก้:** ถอดออกจากคิว **หลัง** ส่งสำเร็จ · หรือ push กลับหัวคิวเมื่อล้ม
· ถ้าตัดสินใจทิ้งจริง **ต้องบวก `m_bytes_dropped` และ log**

---

## 3. 🟡 บันทึกไว้

| # | เรื่อง | ที่ |
|---|-------|-----|
| **W-A3** | `m_messages_sent++` เกิดแม้ส่งไม่ครบ → ตัวนับบอกว่า "ส่งแล้ว" ทั้งที่ยังค้างอยู่ในบัฟเฟอร์ · ควรนับเมื่อ byte สุดท้ายออกจริง | `:402` |
| **W-A4** | `if(depth >= m_queue_max) return false;` เป็น dead code — `DropOldestForCapacity()` บรรทัดบนรับประกันแล้วว่า `depth < m_queue_max` (ยกเว้น `m_queue_max <= 0` ซึ่งถูกดักไปแล้วที่ `:455`) | `:457-460` |
| **W-A5** | `FarmRandomUlidSuffix()` เรียก `FarmSeedUlidRandom()` ทุกครั้ง = **reseed `MathSrand` ทั้งโปรเซส** · ตอนนี้ถูกเรียกครั้งเดียวต่อ instance จึงยังไม่เจ็บ แต่ผู้เรียกคนที่สองจะรีเซ็ตสตรีมสุ่มของทั้ง EA กลางเซสชัน | `:40-47` |

---

## 4. 🟢 ตรวจแล้ว **ไม่พัง** — ห้ามไปแก้

| ข้อกังวล | ความจริง |
|---------|----------|
| เพดานเฟรม 64 KB ไม่ถูกบังคับ | **บังคับจริง** `:719` และเงื่อนไข **ถูกต้อง** — ตัดเฉพาะเมื่อ `> 64KB` **และไม่มี `\n`** (ถ้ามี `\n` แปลว่าเป็นเฟรมสมบูรณ์ที่ยาว ไม่ใช่ desync) |
| `StringToCharArray(...) - 1` คือ off-by-one | **ถูกต้อง** — ตัด NUL terminator ที่ MQL5 ใส่มา · `:393` |
| `CloseSocket()` ลืมล้างบัฟเฟอร์ | **ล้างครบ** ทั้ง `m_partial_send_bytes` และ `m_inbound_bytes` · `:272-273` |
| `Send()` ไม่กัน partial | **กันถูกต้อง** `:1018` — ปัญหาอยู่ที่ผู้ส่ง**ภายใน**ที่ไม่ผ่านทางนี้ (W-A1) |
| ULID clamp ไม่ monotonic | **ถูกต้อง** `:278-280` `ts <= last → last+1` |

---

## 5. สรุป

| # | ระดับ | ต้องทำ |
|---|-------|--------|
| **W-A1** | 🔴 | ผู้ส่งภายใน 4 จุดต้องผ่านด่าน `HasPartialSend()` + ให้ `SendBytes` ร้องถ้าถูกเรียกผิดจังหวะ |
| **W-A2** | 🟠 | ถอดออกจากคิวหลังส่งสำเร็จ หรือนับ+log เมื่อทิ้ง |
| **W-A3** · **W-A4** · **W-A5** | 🟡 | เก็บไว้ทำพร้อมกัน |

**ยังไม่กระทบ soak หรือ A2** — partial send ไม่เกิดบน loopback ที่เฟรมเล็ก
**แต่ต้องปิดก่อน SPEC-010** ซึ่งเป็นตัวที่จะเริ่มส่ง `STATE` ก้อนใหญ่จริง

> **บทเรียน:** ด่านกัน partial มีอยู่แล้วและเขียนถูก — แต่ถูกวางไว้ที่ **API สาธารณะ**
> ขณะที่คนส่งจริงที่ถี่ที่สุด (`SendHeartbeat` ทุก 2 วินาที) เป็น **ทางภายใน**
> · การป้องกันที่อยู่ผิดชั้นเท่ากับไม่มี — และมันดูเหมือนมีอยู่ ซึ่งแย่กว่า
