# Review — SPEC-016 chaos ชั้น A (รอบ 2) + บันทึกการปลดล็อกสิ่งแวดล้อม

**วันที่:** 2026-07-31 · **ผู้ตรวจ:** Claude
**สถานะ:** สิ่งแวดล้อม **ปลดล็อกแล้ว** · เจอบั๊กจริงตัวใหม่ที่ถูกบังไว้มาตลอด

## ผลตัดสิน: 🔴 `CHANGES_REQUIRED` — **แต่เป็นครั้งแรกที่ตกด้วยเหตุผลที่ถูกต้อง**

`err=4014` หายแล้ว · EA เชื่อมต่อได้ · และทันทีที่เชื่อมได้ ก็เจอ
**`socket_send_failed err=5273` ทุกครั้งที่ส่ง HELLO — ไม่เคยสำเร็จเลยสักครั้ง**

---

## 🔴 W1 · `SocketSend` ล้มเหลว 100% หลัง connect สำเร็จ

**หลักฐาน** (`MQL5\Logs\20260731.log` · รอบ 00:25–00:35):

```
00:30:43.323  INFO  broker_time valid=true offset=3600 …
00:30:44.329  WARN  socket_send_failed err=5273        ← 1 วินาทีหลัง OnInit
00:30:50.330  WARN  hello_ack_timeout
00:30:52.316  WARN  socket_send_failed err=5273
00:30:57.330  WARN  hello_ack_timeout
```

| นับจากรอบล่าสุด | |
|---|---|
| `err=5273` | **20 ครั้ง** |
| `hello_ack_timeout` | **13 ครั้ง** |
| `wire_ready` | **0 ครั้ง** |
| `err=4014` | **0 ครั้ง** ✅ |

`5273` = `ERR_NETSOCKET_IO_ERROR` · เกิดที่ `Wire.mqh:294` `SocketSend(m_socket, data, (uint)total)`

**ลำดับที่เกิด:** `TryConnect()` → `SocketConnect` **สำเร็จ** (ไม่มี log error) →
`EnterState(WIRE_CONNECTED)` → `SendHello()` → `SendBytes()` → **`SocketSend` คืน < 0**
→ `CloseSocket()` + `ScheduleReconnect()` → วนใหม่ไม่รู้จบ

**สิ่งที่ต้องตรวจ (เรียงตามความน่าจะเป็น):**

1. **ส่งเร็วเกินไปหลัง connect** — `SendHello()` ถูกเรียกใน `TryConnect()` ทันทีในรอบ `Pump()`
   เดียวกับที่เพิ่ง `SocketConnect` · ถ้า MT5 ยังไม่พร้อมจริง send จะล้ม
   → ลองย้าย `SendHello()` ไปรอบ `Pump()` ถัดไป (เพิ่ม state `WIRE_CONNECTED` → ส่งใน Pump)
2. **`SocketIsWritable()`** — ตรวจก่อนส่ง แทนที่จะส่งทันที
3. ขนาด/รูปแบบ array ที่ส่งเข้า `SocketSend`
4. รายการ whitelist อนุญาต connect แต่ไม่อนุญาต I/O (ไม่น่าใช่ แต่ตัดออกให้ชัด)

**ต้อง log ให้มากกว่านี้:** ตอนนี้ไม่มี log เมื่อ `SocketConnect` **สำเร็จ**
→ อ่าน log แล้วแยกไม่ออกว่า "ต่อไม่ติด" กับ "ต่อติดแล้วส่งไม่ได้"
· เพิ่ม `INFO socket_connected host=… port=…` — จะประหยัดเวลาการไล่บั๊กครั้งหน้ามาก

---

## 🟠 W2 · `echo_server` นับ TCP connection ที่ไม่ใช่ EA

**เจอจริงคืนนี้:** ระหว่างทดสอบด้วยมือ มี `connect` event เข้ามาทุก 60 วินาทีเป๊ะ
ตรวจด้วย `netstat -ano` แล้วพบว่าเป็น **`chrome.exe` (PID 3648)** ต่อ `127.0.0.1:45001`
แล้วค้างไม่ส่งอะไรจนโดน read timeout 30 วินาที

```
PID=3648  process=chrome   TCP  127.0.0.1:60974 -> 127.0.0.1:45001  ESTABLISHED
```

**ทำไมเป็นปัญหาจริง:** `test_backoff_schedule_matches_spec` **นับ `connect` event เพื่อวัดจังหวะ backoff**
→ connection ขยะคั่นกลางทำให้ตัวเลขเพี้ยน → test แดง/เขียวแบบสุ่มโดยหาสาเหตุไม่เจอ
· นี่คือ flaky test ที่ **หาสาเหตุยากที่สุด** เพราะขึ้นกับว่าเบราว์เซอร์เปิดอยู่ไหม

**แก้:** `log_event("connect")` ต้องเกิดเมื่อ connection **พูดโปรโตคอลจริง** เท่านั้น
→ ย้ายการ log ไปหลังอ่าน frame แรกที่ parse เป็น JSON ได้ (หรือเพิ่ม field `authenticated`
แล้วให้ test นับเฉพาะตัวนั้น) · connection ที่ไม่ส่งอะไรใน N วินาที = ทิ้งเงียบๆ ไม่ต้องนับ

---

## 🟠 W3 · chart profile ปนเปื้อนข้ามการรัน — ต้องแยก profile ของ harness

**เจอจริงคืนนี้:** หลังลาก EA ใส่กราฟด้วยมือเพื่อ debug MT5 **บันทึกลง profile `Default`**
→ รอบถัดมา harness สั่งเปิด terminal แล้วกราฟเหล่านั้น**เปิดกลับมาพร้อม EA**
บวกกับตัวที่ `[StartUp]` เพิ่มอีก = **EA 3 ตัวส่ง HELLO สลับกัน**

ผลคือ test วัดช่องว่างระหว่าง `hello_ack` **ข้าม instance** ไม่ใช่การ retry ของตัวเดียว:

| test | คาดหวัง | ได้ | สาเหตุจริง |
|------|---------|-----|-----------|
| `test_bad_token_waits_60s` | ≥ 59s | **32.0s** | คนละ EA instance |
| `test_ea_handles_duplicate_session_rejection` | ≥ 55s | **31.0s** | เดียวกัน |
| `test_backoff_schedule_matches_spec` | ≤ 1.5× | **2.0** | connect ปนกัน |

**สังเกตว่ารอบนั้น 3 test "ผ่าน"** — แต่ผ่านเพราะ EA ที่ลากด้วยมือเป็นคนตอบ
**ไม่ใช่ตัวที่ `[StartUp]` สร้าง** · เป็น false pass ที่อันตรายกว่าตกด้วยซ้ำ

**แก้ (บังคับ):** harness ต้องใช้ **profile แยกของตัวเอง** ไม่ใช่ `Default`
· `[StartUp]` มี key `Profile=` อยู่แล้ว (ตอนนี้ตั้ง `Profile=0`)
· หรืออย่างน้อย **ลบ `MQL5\Profiles\Charts\<profile>\chart*.chr` ก่อนทุกรัน**
· ต้องยืนยันได้ว่า **มี EA ทำงานอยู่ตัวเดียว** ก่อนเริ่มวัดอะไรก็ตาม

> เรื่องนี้กว้างกว่า chaos — เป็นหลักการเดียวกับ **T1** (`.ex5` ค้าง):
> *state ที่เหลือจากรอบก่อนทำให้ผลรันเชื่อไม่ได้* · ต่างกันแค่ที่นี่เป็น state ของ MT5 ไม่ใช่ของ compiler

---

## ✅ บันทึกการปลดล็อกสิ่งแวดล้อม — ต้องเข้า runbook (SPEC-030b)

`err=4014` ตัวเดียวกัน มี **สาเหตุซ้อนกัน 3 ชั้น** ซึ่งกว่าจะแยกออกใช้เวลาหลายชั่วโมง

| ชั้น | อาการที่เห็น | วิธีแยก |
|------|-------------|---------|
| 1 · **Algo Trading ปิด** | EA **ไม่ log อะไรเลย** แม้ terminal บอก `loaded successfully` | ดู `common.ini` → `[Experts] Enabled=` |
| 2 · **whitelist ไม่ถูกบันทึก** | EA log `err=4014` ทุก retry | `common.ini` → `WebRequest=` และ `WebRequestUrl=` |
| 3 · **connection ขยะ** | มี `connect` แต่ไม่มี `hello_ack` | `netstat -ano` หา PID เจ้าของ |

**สองอาการแรกต่างกันชัดเจน** — *"ไม่ log เลย"* กับ *"log 4014"* ชี้ไปคนละที่
· §P1 ชั้น B ต้องแยกสองเคสนี้ ไม่งั้นจะบอกให้คนไปแก้ผิดจุด

### วิธีตั้งค่าที่ได้ผลจริง (ยืนยันแล้ว)

| ขั้น | ทำ | ทำไม |
|------|-----|------|
| 1 | `Tools → Options → Expert Advisors` | |
| 2 | ✅ **Allow Algo Trading** | ไม่งั้น EA โหลดแต่ไม่รัน `OnInit` |
| 3 | ✅ **Allow WebRequest for listed URL** | ★ ถ้าไม่ติ๊ก ตารางเป็นสีเทา พิมพ์ไม่ได้ |
| 4 | พิมพ์ URL แล้ว **กด `Enter` ทุกบรรทัด** | ★★ กด OK ขณะ cursor ยังอยู่ในช่อง = **บรรทัดนั้นถูกทิ้ง** |
| 5 | ตรวจด้วยตาว่าเห็นครบ**ก่อน**กด OK | |
| 6 | **`File → Exit`** ปิดสนิท | MT5 เขียน config ตอนปิดสะอาดเท่านั้น · harness `kill` เสมอ จึงไม่เคยเขียน |

### ★ วิธีตรวจว่าตั้งค่าเข้าจริง — ไม่ต้องเดา

หลังปิดสนิท อ่าน `<TERMINAL_DATA>\config\common.ini` (UTF-16LE):

```ini
[Experts]
Enabled=1                     ← Algo Trading
WebRequest=1                  ← checkbox
WebRequestUrl=B0A81B2EEA63…   ← รายการ URL (เข้ารหัส — ตรวจได้แค่ว่าง/ไม่ว่าง)
```

| อ่านได้ | ตรวจได้แค่ไหน |
|---------|---------------|
| `Enabled` · `WebRequest` | **ค่าจริง** 0/1 |
| `WebRequestUrl` | **ว่าง / ไม่ว่าง เท่านั้น** — เนื้อในถูกเข้ารหัส |

⚠️ **สะท้อนสภาพ ณ "ครั้งล่าสุดที่ปิดสะอาด"** — ใช้เป็นเครื่องมือ debug ได้ดี
**แต่ห้ามใช้เป็นด่านของ gate** (§P1 ชั้น A) เพราะ harness kill ตลอดจึงค้างได้เป็นวัน

---

## สรุปสิ่งที่ต้องทำ

| ลำดับ | # | ทำ |
|-------|---|-----|
| **1** | **W1** | `SocketSend` ล้ม 100% — เพิ่ม log ตอน connect สำเร็จก่อน แล้วไล่ตาม 4 ข้อสงสัย |
| **2** | **W3** | harness ใช้ profile แยก + ยืนยันว่ามี EA ตัวเดียวก่อนวัด |
| **3** | **W2** | `echo_server` นับเฉพาะ connection ที่พูดโปรโตคอลจริง |
| **4** | — | งานเดิมใน [work-order แก้ 5](../work-order.md) (P1 · ⑤ · T6 · T7 · T8 · T9 · N1) |

**W1 ต้องมาก่อน** — ตราบใดที่ HELLO ส่งไม่ออก ไม่มี test ไหนในชุดนี้ผ่านได้เลย
