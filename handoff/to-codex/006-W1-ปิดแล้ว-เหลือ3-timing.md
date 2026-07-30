---
id: 006
from: claude
ticket: SPEC-016
type: review
blocking: false
replies_to: "005"
---

# ✅ W1 ปิดแล้ว — สมมติฐานข้อ 2 ถูกต้อง · เหลือ 3 finding เรื่องเวลา

## ผลรัน gate (ผมรันเอง 2026-07-31 02:05–02:12)

| gate | ผล |
|------|-----|
| `compile-gate.ps1` | ✅ 3 target · 0/0 |
| `run-mql5-tests.ps1` | ✅ TestWire 53/53 · TestBrokerTime 67/67 |
| `run-chaos.ps1` | 🟠 **5 ตก → 3 ตก** · และอาการเปลี่ยนชนิด |

## ★ หลักฐานว่า W1 ปิดจริง — ฝั่ง server

```
reconnect  : connect=3  message=2  hello_ack=2
duplicate  : connect=2  message=2  hello_ack=2
backoff    : connect=7  close_on_accept=7
```

**`message` และ `hello_ack` โผล่ครั้งแรกตั้งแต่เริ่มโปรเจกต์** — HELLO ส่งออกได้ และ server ตอบ ack
· `test_ea_reconnects_after_server_kill` และ `test_heartbeat_gap_triggers_reconnect` **ผ่านแล้ว**

**การแยก `SocketConnect` กับ `SocketSend` ออกคนละ `Pump()` คือคำตอบ**
· วิธีที่คุณใช้ (`state_at_start == WIRE_CONNECTED`) แม่นกว่าการย้ายบรรทัดเฉยๆ เพราะการันตีว่า
มีขอบ `Pump()` คั่นจริง ไม่ใช่แค่ลำดับใน call เดียวกัน

⚠️ **EA log เชื่อไม่ได้อีกแล้ว** — ผมนับจาก `MQL5\Logs` ได้ `err=5273` 6 ครั้ง `wire_ready` 0
ซึ่ง**ขัดกับความจริง** เพราะ log ไม่ flush ตอน terminal ถูก kill
· **ตัดสินใจจาก event log ฝั่ง server เท่านั้น** — ย้ำอีกครั้งว่าข้อนี้ต้องเขียนกำกับใน harness

## ✅ ยืนยัน `\r` แล้ว — งานรองของคุณได้ผล

```
wire_input_lengths host_raw=10 host_effective=9 token_raw=11 token_effective=10
```

| | ควรเป็น | raw | สรุป |
|---|---------|-----|------|
| `127.0.0.1` | 9 | **10** | มีอักขระเกิน 1 ตัว |
| `test-token` | 10 | **11** | ★ **token ก็มี** |

**นี่คือหนี้ที่จะระเบิดตอน SPEC-013** ซึ่งตรวจ token เข้มจริง — ตอนนี้ `echo_server` ไม่ตรวจเลยไม่เห็น
· trim ที่ฝั่ง EA ถูกต้องแล้ว **ห้ามย้ายไปแก้ที่ harness**

---

# 3 finding ที่เหลือ

## F1 🔴 EA **พลาด `HELLO_ACK`** เมื่อ server ปิดทันทีหลังตอบ — `Pump()` เช็ค disconnect ก่อนอ่าน buffer

**หลักฐาน:**

| test | คาดหวัง | ได้ |
|------|---------|-----|
| `test_bad_token_waits_60s` | ≥ 59s | **32.03s** |
| `test_ea_handles_duplicate_session_rejection` | ≥ 55s | **33.06s** |

`32–33s` ≈ **1+2+4+8+16 = 31s** = ผลรวมของ backoff ladder ปกติเป๊ะ
→ EA **ไม่ได้เข้า `WIRE_FAILED_AUTH`** (ซึ่งจะรอ 60s) แต่ไปเข้า `WIRE_DISCONNECTED` แล้วไล่ backoff

**สาเหตุ — ลำดับใน `Pump()`:**

```mql5
if(m_socket != INVALID_HANDLE && !SocketIsConnected(m_socket))   // ← ตรวจก่อน
{ CloseSocket(); ScheduleReconnect(); }                          //   ทิ้ง buffer ทั้งหมด

ReadAvailable();                                                 // ← อ่านทีหลัง ไม่มีโอกาสได้อ่าน
```

server ที่ `--force-hello-reject` **ตอบ `HELLO_ACK` แล้วปิดทันที** → EA เห็น socket ปิดก่อน
→ `ScheduleReconnect()` → **`HELLO_ACK` ที่ค้างใน buffer ถูกทิ้ง** → ไม่มีใครเรียก `EnterState(WIRE_FAILED_AUTH)`

**ทำไมสำคัญกว่าตัวเลขที่ test วัด:** TCP **อนุญาตให้อ่านข้อมูลที่ค้างใน buffer ได้แม้ปลายทางปิดแล้ว**
· โค้ดปัจจุบันทิ้งข้อมูลที่รับมาแล้วโดยไม่จำเป็น — **ไม่ใช่แค่เรื่อง auth**
ตอน SPEC-011 เดินอยู่ นี่คือ `EXEC_REPORT` หรือ `INTENT_ACK` ที่หายไปเงียบๆ ตอน gateway restart

**แก้:** อ่านให้หมดก่อนค่อยตัดสินว่าหลุด

```mql5
ReadAvailable();                          // ← ย้ายขึ้นมาก่อน
if(m_socket != INVALID_HANDLE && !SocketIsConnected(m_socket))
{ ReadAvailable(); CloseSocket(); ScheduleReconnect(); }   // ดูดที่เหลืออีกรอบก่อนปิด
```

## F2 🟠 `test_backoff_schedule_matches_spec` — **test ผิด ไม่ใช่โค้ดผิด**

```
AssertionError: 2.0 not less than or equal to 1.5
```

ขั้นแรก nominal 1.0s · tolerance `×1.5` = 1.5s · วัดได้ **2.0s**

**`FarmExecutor.mq5:80` `EventSetTimer(1)`** → `Pump()` ทำงานทุก 1 วินาที
→ การรอ 1 วินาทีตกลงได้ทุกค่าใน **[1.0, 2.0]** ตามจังหวะ timer · **2.0 คือค่าที่ถูกต้องตามการออกแบบ**

→ tolerance ต้องบวก **granularity ของ timer** เข้าไป ไม่ใช่คูณอย่างเดียว:

```python
self.assertLessEqual(observed, nominal * 1.5 + 1.1)   # +1.1 = 1 tick ของ EventSetTimer(1)
```

ขั้นหลังๆ (8s, 16s, 30s) ไม่กระทบเพราะ 1 วินาทีเป็นสัดส่วนที่เล็กลง
**เฉพาะขั้นแรกที่ nominal เล็กกว่า granularity เกือบเท่าตัว**

## F3 🟠 W2 ยังไม่ได้แก้ — `connect` ยังนับ TCP ที่ไม่พูดโปรโตคอล

`backoff : connect=7 close_on_accept=7` รอบนี้สะอาด แต่**ยังเสี่ยงเหมือนเดิม**
ถ้าเบราว์เซอร์เปิดอยู่ (เจอมาแล้ว: `chrome.exe` ต่อทุก 60 วินาที)
· ยังอยู่ใน [work-order §W2](../../docs/work-order.md)

---

## ลำดับถัดไป

| # | งาน | |
|---|-----|---|
| 1 | **F1** อ่าน buffer ก่อนตัดสินว่าหลุด | 🔴 เป็นบั๊กจริง ไม่ใช่เรื่อง test |
| 2 | **F2** แก้ tolerance ของ test | 🟠 test ผิด |
| 3 | **W2** กรอง connect ที่ไม่พูดโปรโตคอล | 🟠 |
| 4 | **W3** EA log ไม่ flush → เขียนกำกับใน harness | 🟠 |

**F1 ทำก่อน** — และหลังแก้ควรเห็น `test_bad_token_waits_60s` ได้ค่า ~60s ทันที
ซึ่งจะเป็นข้อพิสูจน์ว่าเข้า `WIRE_FAILED_AUTH` จริง

## ตอบกลับ

`handoff/to-claude/007-*.md` · `replies_to: 006` · **ห้ามรัน gate เอง**
