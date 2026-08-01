# SPEC-001 A2 — S1 · S3 · S4 · S5 + R2 · review

**วันที่:** 2026-08-01 · **handoff:** [`027`](../../handoff/to-claude/027-a2-cadence.md) · **ผล:** ✅ **APPROVED_WITH_NOTES** (รอผล soak รอบ 3 ยืนยัน)

```
MQL5 gate: compile 0 errors 0 warnings · TestWire 53/53 · TestBrokerTime 67/67 · PASSED
```

---

## 1. S1 — แก้ตรงต้นเหตุ ไม่ใช่ตรงอาการ

```mql5
void AdvanceHeartbeatSchedule(const uint now, const uint interval_ms)
{
   if(interval_ms == 0) return;
   do { m_next_heartbeat_tick += interval_ms; }
   while((int)(now - m_next_heartbeat_tick) >= 0);
}
...
const uint now = NowTick();                              // :988
if((int)(now - m_next_heartbeat_tick) >= 0)
{
   SendHeartbeat();
   AdvanceHeartbeatSchedule(now, heartbeat_interval_ms);
}
```

| ข้อ | ทำถูกไหม | หลักฐาน |
|-----|----------|---------|
| **a** เทียบด้วย ms | ✅ | `ElapsedMs()` + `heartbeat_interval_ms = m_heartbeat_sec * 1000` |
| **b** `next_due += interval` | ✅ | `m_next_heartbeat_tick += interval_ms` — **ไม่มี `= NowTick()` เหลืออยู่เลย** |
| **c** ตามทันไม่ยิงรัว | ✅ | ส่ง **1 ครั้ง** ต่อ `Pump()` แล้วเลื่อน due ข้าม backlog ทั้งหมดใน `do-while` |
| **d** cast signed | ✅ | `(int)(now - m_next_heartbeat_tick)` ทั้งจุดเทียบและในลูป |

### ★ จุดที่ตัดสินความสำเร็จ — `now` ถูกจับ **ก่อน** `SendHeartbeat()`

```mql5
const uint now = NowTick();     // จับก่อน
SendHeartbeat();                // ใช้เวลาไปเท่าไรไม่สำคัญ
AdvanceHeartbeatSchedule(now, ...);
```

**นี่คือหัวใจของการแก้** — ตารางเวลาถูกยึดกับ *เวลาที่ถึงกำหนด* ไม่ใช่ *เวลาที่ส่งจริง*
ความหน่วงของคอลแบ็กจึงไม่ถูกบวกกลับเข้าฐานอีก ซึ่งเป็นสาเหตุที่ histogram มีแค่ `{2, 3}`

### ไล่เลขว่ามันหายจริง

```
next = T · tick ทุก 1000 ms (EventSetTimer(1))
T+5    (int)(T+5 - T) = 5 >= 0      → ส่ง · next = T+2000
T+1005 -995 < 0                      → ไม่ส่ง
T+2005 5 >= 0                        → ส่ง · next = T+4000      gap = 2000 ✅
```

**และถ้าพลาดไปหนึ่ง tick ก็ไม่สะสม:**
```
due T+2000 แต่ tick มาที่ T+2999 → ส่ง · next = T+4000  (ไม่ใช่ T+4999)
tick T+3999 → -1 < 0 ไม่ส่ง · tick T+4999 → ส่ง        gap = 2000 ✅
```

ต่างจากของเดิมที่ฐานเลื่อนเป็น T+2999 แล้วผลักทุกอย่างถัดไปให้เพี้ยนตาม

---

## 2. ★★ S5 — **Codex จับความผิดในคำแนะนำของผมเอง**

[audit](SPEC-001-timing-audit.md) §4 ผมเสนอไว้ตรงๆ ว่า:

```mql5
if((int)(NowTick() - m_next_connect_tick) < 0) return;      // ← ข้อเสนอของ Claude
```

**Codex ไม่ทำตาม และเพิ่ม guard:**

```mql5
if(m_state == WIRE_DISCONNECTED && m_next_connect_tick != 0
   && (int)(NowTick() - m_next_connect_tick) < 0)
   return;                                                  // :803
```

### ทำไม guard นั้นจำเป็น — ข้อเสนอของผมมีบั๊ก

ตอน EA เพิ่งเริ่ม `m_next_connect_tick = 0` และ state = `DISCONNECTED`

```
(int)(NowTick() - 0)  =  (int)GetTickCount()  =  ms ตั้งแต่บูต
uptime > 2³¹ ms = 24.855 วัน  →  cast เป็น int ได้ค่า "ติดลบ"
→ (int)(...) < 0 เป็นจริง  →  return  →  EA ไม่เชื่อมต่อเลย
```

**หน้าต่างพัง: uptime 24.9 – 49.7 วัน** — เครื่องที่เปิดค้างเดือนนึงจะรัน EA ไม่ได้เลย
และเงียบสนิทเพราะ `TryConnect()` แค่ `return`

> ผมเขียน audit ทั้งฉบับเตือนเรื่องกับดัก unsigned แล้ว **ยังวางกับดักตัวใหม่ในคำแนะนำของตัวเอง**
> · ที่ถูกจับได้เพราะ Codex ไม่ได้ลอกไปตรงๆ — **นี่คือสิ่งที่การ review สองทางควรได้**

**ข้อสังเกตเดียว:** ถ้า `NowTick() + wait_ms` ล้นแล้วได้ `0` พอดี guard จะข้ามการรอหนึ่งครั้ง
· โอกาส ~1 ใน 4.29 พันล้าน · **ยอมรับได้** ไม่ต้องแก้

---

## 3. S4 — brain timeout ตรงเวลาแล้ว

```mql5
const uint brain_timeout_ms = (uint)(InpBrainTimeoutSec > 0 ? InpBrainTimeoutSec : 0) * 1000;
if(g_wire.IsAuthenticated() && g_wire.MsSinceLastInbound() >= brain_timeout_ms)
```

`10 * 1000 = 10000` · `>= 10000 ms` → ยิงที่ **10.000 วินาทีพอดี** (เดิม 11.000)
→ เกณฑ์ **Phase 1 exit "kill brain → SafeMode ≤ 10s"** วัดผ่านได้แล้ว

## 4. S3 · R2

| # | ผล |
|---|-----|
| **S3** | ✅ `int(SOAK_SECONDS / HEARTBEAT_SEC * 0.95)` = **1710** · `SOAK_SECONDS` ถูกใช้กับ `deadline` ด้วย ไม่ใช่แค่ประกาศทิ้งไว้ |
| **R2** | ✅ อ่านเป็นก้อน → `rfind("\n")` → เก็บส่วนที่เหลือใน `self.partial` · **ไม่มี `try/except: pass`** ที่จะกลืน event หาย |

---

## 5. 🟡 บันทึกไว้ ไม่บล็อก

| # | เรื่อง |
|---|-------|
| **A2-1** | `HEARTBEAT_SEC = 2` เป็นค่าคงที่ฝั่ง Python — **ไม่ได้ผูกกับ `InpHeartbeatSec` จริงของ EA** · ถ้าใครเปลี่ยนค่าใน `.set` เกณฑ์จะไม่ขยับตาม · **spec ของผมสั่งแค่ให้ derive จากค่าคงที่ ซึ่ง Codex ทำถูกแล้ว** — ทางที่ดีกว่าคืออ่านจาก `farm-chaos.set` ที่ harness เขียนเอง |
| **A2-2** | `AdvanceHeartbeatSchedule` เป็น `do-while` — ถ้า `m_next_heartbeat_tick` ค้างเก่ามาก (ไม่เกิดในทางปฏิบัติเพราะถูกตั้งใหม่ทุกครั้งที่เข้า `WIRE_READY`) ลูปจะวนนาน · คำนวณจำนวนช่วงตรงๆ จะทนกว่า |
| **A2-3** | `InpBrainTimeoutSec <= 0` → `brain_timeout_ms = 0` → `>= 0` จริงเสมอ → **เตือนทุก tick** · ค่าที่ตั้งแบบนั้นไม่สมเหตุสมผลอยู่แล้ว แต่ควร log ครั้งเดียวว่า config ผิด |

---

## 6. เกณฑ์ตัดสินที่ soak รอบ 3 ต้องผ่าน

| | ค่า |
|---|-----|
| `len(heartbeats)` | **≥ 1710** (คาด ~1799) |
| `mean_gap` | **≈ 2.00s** |
| **histogram** | **ต้องไม่เหลือค่า 3 เลย** ← ตัวชี้ขาด |
| `max(gaps)` | ≤ 3.5s · **`:427` จะได้เดินถึงเป็นครั้งแรก** |

**ถ้าผ่านครบ = SPEC-001 ฝั่ง wire ปิด** เหลือ W2 + ย้าย test cadence เข้า fast gate (A3)
