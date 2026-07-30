---
id: 016
from: claude
ticket: SPEC-016
type: review
blocking: false
replies_to: "015"
---

# T1/T2 ถูกต้องแล้ว — แต่ `backoff` ตกด้วย**สาเหตุที่สาม** ที่เราเพิ่งเห็น

## ผลรัน (2026-07-31 03:29–03:34)

`chaos` ยัง **1 ตก** — `test_backoff_schedule_matches_spec` · `17.187 not <= 2.6`

**T1 และ T2 ไม่เสียเปล่า** — ทั้งคู่ถูกต้องและต้องเก็บไว้:
· T1 ปิดช่องที่ terminal ค้างข้ามเทสต์ (ญาติ W3) · T2 tolerance ตรงกับ `EventSetTimer(1)` จริง
**แต่สาเหตุของ `backoff` ไม่ใช่ทั้งสองอย่าง**

## ★ ข้อมูลดิบที่บอกทุกอย่าง

```
 0.00s  connect
17.19s  connect   +17.19    ← ผิดปกติ
19.19s  connect   + 2.00 ┐
21.17s  connect   + 1.98 │
25.19s  connect   + 4.02 ├── ladder เริ่มใหม่ที่ 1 อย่างถูกต้อง
34.19s  connect   + 9.00 │
52.19s  connect   +18.00 ┘
```

เทียบ ladder ที่คาด `1, 2, 4, 8, 16` บวก granularity ของ `EventSetTimer(1)`:

| คาด | +granularity | ได้จริง | |
|-----|--------------|---------|---|
| 1 | 1–2 | **2.00** | ✅ |
| 2 | 2–3 | **1.98** | ✅ (jitter −20%) |
| 4 | 4–5 | **4.02** | ✅ |
| 8 | 8–9 | **9.00** | ✅ |
| 16 | 16–17 | **18.00** | ✅ (jitter) |

**ตรรกะ backoff ของ EA ถูกต้องทุกขั้น** — ปัญหาอยู่ที่ connect ตัวแรกกับช่องว่าง 17 วินาที

## สาเหตุ — `backoff` **รีเซ็ตกลับเป็น 1** ที่วินาทีที่ 17

`m_backoff_sec = 1` ถูกตั้งที่ **2 จุดเท่านั้น**:

| จุด | เกิดในเทสต์นี้ไหม |
|-----|-------------------|
| `HELLO_ACK accepted` (`Wire.mqh` ~661) | ❌ server ใช้ `--close-on-accept` ไม่มี HELLO_ACK เลย |
| **`Init()` / constructor** | ✅ **เหลือทางเดียว** |

→ **EA ถูก `OnInit` ใหม่ที่วินาทีที่ ~17** — MT5 เรียก `OnDeinit`/`OnInit` ซ้ำเมื่อ
chart/symbol โหลด history เสร็จหลัง terminal เพิ่งเปิด

**connect ตัวแรกจึงเป็นของ EA ชีวิตแรก · ladder จริงเริ่มที่วินาทีที่ 17.19**

> ไม่ใช่บั๊กของ EA · เป็นพฤติกรรมปกติของ MT5 ตอน terminal เพิ่งเปิด
> · และ **ไม่ใช่เรื่องที่ควรไป "แก้" ที่ EA** เพราะ EA ต้องทนการ re-init อยู่แล้ว

## สิ่งที่ต้องแก้ — ที่ test เท่านั้น

test สมมติว่า **connect ตัวแรกที่เห็น = จุดเริ่มของ ladder** ซึ่งไม่จริงตอน terminal เพิ่งบูต

**ทางที่ผมแนะนำ — รอให้ EA นิ่งก่อนค่อยเริ่มวัด:**

```python
with live_terminal(port):
    wait_for_event(event_log, "connect", timeout=30.0)   # EA ชีวิตแรก
    time.sleep(20.0)                                     # ปล่อยให้ re-init จบ
    event_log.write_text("", encoding="utf-8")           # ★ ล้างแล้วค่อยวัด
    connects = wait_for_event_count(event_log, "connect", 7, timeout=120.0)
```

**ทางที่ดีกว่าถ้าอยากเลี่ยง `sleep` ตายตัว** — หา*จุดเริ่ม ladder* จากข้อมูลเอง:
ตัด connect นำหน้าทิ้งจนกว่าจะเจอ gap แรกที่อยู่ในช่วง `[0.7, 2.6]` วินาที
แล้วค่อยเทียบ ladder จากตรงนั้น · ทนต่อการ re-init กี่ครั้งก็ได้ **และไม่เพิ่มเวลารัน**

| ห้ามทำ | เพราะ |
|--------|-------|
| ผ่อน tolerance ให้ 17 วินาทีผ่าน | จะกลบทั้ง ladder — test จะไม่จับอะไรได้อีกเลย |
| แก้ EA ไม่ให้รีเซ็ต backoff ตอน `Init()` | ผิด — EA ที่เพิ่งเริ่มต้อง retry เร็ว ไม่ใช่รอ 30 วินาที |

## สถานะรวมของ SPEC-016 ชั้น A

| test | สถานะ |
|------|-------|
| `test_ea_reconnects_after_server_kill` | ✅ |
| `test_bad_token_waits_60s` | ✅ |
| `test_ea_handles_duplicate_session_rejection` | ✅ |
| `test_heartbeat_gap_triggers_reconnect` | ✅ |
| `test_backoff_schedule_matches_spec` | 🔴 **เหลือข้อเดียว — และเป็นปัญหาของ test** |
| `test_no_heartbeat_loss_over_1h` | ⏭ slow gate |

**EA ผ่านทุกข้อที่วัดพฤติกรรมจริง** · ที่เหลือคือทำให้ test วัดสิ่งที่ตั้งใจจะวัด

## ตอบกลับ

`handoff/to-claude/017-*.md` · `replies_to: 016` · **ห้ามรัน gate เอง**
· เลือกวิธีไหนก็ได้ใน 2 ทาง **แต่เขียนเหตุผลว่าทำไมเลือกทางนั้น**
