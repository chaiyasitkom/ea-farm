# SPEC-001 — Compile Gate #2 + คำตอบ 3 คำถาม

**วันที่:** 2026-07-27 00:10 · **commit:** `154be25` · **branch:** `feat/SPEC-001-mt5-executor`
**ผล:** 🔴 **GATE FAILED** — 1 compile error (แก้บรรทัดเดียว)

---

## 1. ผล compile gate

```
[ OK ] FarmExecutor.mq5 -- 0 errors, 0 warnings   -> FarmExecutor.ex5 39440 bytes
[FAIL] TestWire.mq5     -- 1 errors, 0 warnings   -> no .ex5
       TestWire.mq5(225,89) : error 256: undeclared identifier 'FILE_UTF8'
```

### แก้อย่างไร — `FILE_UTF8` ไม่มีใน MQL5

MQL5 มีแค่ 3 ทางเลือกสำหรับ encoding ของไฟล์:

| flag | ได้อะไร | ใช้ได้ไหม |
|------|---------|-----------|
| `FILE_TXT\|FILE_UNICODE` | UTF-16LE + BOM | ❌ Python/CI ต้องรู้ล่วงหน้า |
| `FILE_TXT\|FILE_ANSI` | system codepage (เครื่องนี้ CP874) | ❌ ภาษาไทยเพี้ยน ขึ้นกับเครื่อง |
| `FILE_BIN` + `StringToCharArray(..., CP_UTF8)` | **UTF-8 จริง** | ✅ ทางเดียวที่ไม่ขึ้นกับ codepage |

แทน `WriteJsonResult()` ด้วยรูปแบบนี้ (มีตัวอย่างรันได้จริงที่ [`tools/probe/TesterProbe.mq5`](../../tools/probe/TesterProbe.mq5)):

```mql5
bool WriteUtf8File(const string filename, const string content)
{
   uchar bytes[];
   int n = StringToCharArray(content, bytes, 0, -1, CP_UTF8);
   if(n > 0 && bytes[n - 1] == 0)   // ตัด NUL terminator ออก JSON ต้องไม่มี
      n--;
   const int h = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("FileOpen err=", GetLastError()); return false; }
   const uint written = FileWriteArray(h, bytes, 0, n);
   FileClose(h);
   return (written == (uint)n);
}
```

**สร้าง JSON เป็น string เดียวก่อน แล้วเขียนครั้งเดียว** — ไม่ใช่ `FileWriteString` ทีละชิ้นแบบเดิม
(`FileWriteString` บนไฟล์ `FILE_BIN` เขียน raw ได้ แต่จะไม่ผ่าน CP_UTF8 conversion)

---

## 2. ✅ Test list ครบตาม SPEC-001 §7 แล้ว

11/11 ครบ + เพิ่มมาเอง 5 ตัว (`receive_application_message_queued`, `hello_ack_accepted_sets_ready`,
`hello_ack_rejected_sets_failed_auth`, `send_before_ready_queues`, `utf8_multibyte_drop_counts_bytes`)
5 ตัวที่เพิ่มมาตรงกับ behaviour table §4 — **รับ ดีกว่าที่ spec ขอ**

✅ เปลี่ยนเป็น EA (`OnInit` + `ExpertRemove`) แล้วตามที่ขอใน gate #1

---

## 3. คำตอบ 3 คำถามที่ฝากมา

### ❶ inbound framing เป็น byte buffer — ✅ ถูกต้อง รับได้

ตรวจ `Wire.mqh` แล้วทำถูกทุกจุดสำคัญ:

| จุด | สถานะ |
|-----|-------|
| `m_inbound_bytes[]` เป็น `uchar[]` ไม่ใช่ string | ✅ |
| หา newline ที่ระดับ byte (`== 10`) | ✅ **ปลอดภัยกับ UTF-8 โดยธรรมชาติ** — continuation byte คือ 0x80–0xBF, lead byte 0xC0+ ดังนั้น 0x0A เป็น newline จริงเสมอ ไม่มีทางเป็นส่วนของตัวอักษร |
| trim CR ที่ระดับ byte (`== 13`) | ✅ |
| `CharArrayToString(..., CP_UTF8)` เฉพาะเมื่อได้ frame ครบ | ✅ |
| เช็ค 64KB นับ **byte** (บรรทัด 432) | ✅ ตรง contract §1 — ถ้านับ `StringLen` จะผิด เพราะไทย 64K ตัว = 192KB |

**2 ข้อสังเกตเล็ก (ไม่บล็อก):**

1. `TestPartialSendBuffer()` (บรรทัด 762) เรียก `CharArrayToString` บน buffer ที่**ยังไม่ครบ**
   → ถ้าตัดกลางตัวอักษร string ที่ได้จะเป็นขยะ เป็น test accessor ไม่ใช่ production path
   แต่ขอให้ **assert แค่ความยาว ห้าม assert เนื้อหา** ของค่าที่ได้จากฟังก์ชันนี้
   ไม่งั้น test จะพังแบบงงๆ เมื่อ frame มีอักษรไทย
2. `StringToCharArray(frame, data, 0, WHOLE_ARRAY, CP_UTF8) - 1` สมมติว่ามี NUL ต่อท้ายเสมอ
   ซึ่งจริงเมื่อ count = `WHOLE_ARRAY` แต่จะพังเงียบๆ ถ้าอนาคตมีใครส่ง count มาชัดเจน
   → ใส่ guard `if(total < 0) return false;` กันไว้

### ❷ `test_partial_send_resumes` ใช้ test hook ไม่ใช่ socket จริง — ⚠️ รับชั่วคราว แต่ยังไม่ปิดข้อนี้

**เหตุผลที่รับ:** unit test พิสูจน์ *การจดบัญชี resume* ได้ถูก (ไม่ส่งซ้ำทั้ง frame) ซึ่งเป็นตรรกะหลัก

**เหตุผลที่ยังไม่ปิด:** มันไม่พิสูจน์ว่า **ค่าที่ `SocketSend` คืนมาตอน short write ถูกต่อเข้ากับตรรกะนั้นจริง**
สองอย่างนี้เป็น failure mode ที่ต่างกัน และตัวที่สองคือตัวที่ทำเงินหาย —
Phase 1 ส่งซ้ำแค่ได้ message ซ้ำ แต่ **Phase 2 message ซ้ำ = order ซ้ำ**

**วิธีบังคับให้เกิด partial send จริง:** ให้ `echo_server.py` accept connection แล้ว **ไม่อ่าน**
(หรือตั้ง `SO_RCVBUF` เล็กๆ) แล้วให้ EA ส่ง frame ใหญ่กว่า send buffer → `SocketSend`
จะคืนค่าน้อยกว่าที่ขอ

| | |
|---|---|
| **ตอนนี้** | ยอมรับเป็นหนี้เทคนิคที่บันทึกไว้ ไม่บล็อก SPEC-001 |
| **เส้นตาย** | ต้องมี `test_partial_send_resumes_real_socket` ใน chaos suite **ก่อน merge SPEC-011** (จุดที่ message ซ้ำกลายเป็น order ซ้ำ) |

### ❸ JSON result format/path เพียงพอไหม — ✅ path ใช้ได้ · 🔴 format มีช่องโหว่ 1 จุดที่ต้องแก้

**path:** `FILE_COMMON` → `Common\Files\` ถูกต้อง ผมตรวจแล้วว่า runner อ่านได้จริง
และเช็ค staleness (mtime) + `git_sha` ตรงกับ HEAD ได้

**🔴 ช่องโหว่: test ที่ไม่ได้รันจะแยกจาก test ที่ผ่านไม่ออก**

`g_total` นับจากจำนวน assertion ที่ *ถูกเรียก* ถ้ามีใครลืมเพิ่มบรรทัดใน `RunAllTests()`
(หรือลบออก) → `total` แค่ลดลง แต่ `status` ยังเป็น `PASS`
→ **CI จะรายงานเขียวทั้งที่ test หายไป** นี่คือความต่างระหว่าง *"test ผ่าน"* กับ *"test ที่ spec สั่งไว้ผ่าน"*

**ต้องเพิ่ม:** ให้แต่ละ test ลงทะเบียนชื่อตัวเอง แล้วใส่ `ran_names` ลง JSON
runner จะเทียบกับรายชื่อ 11 ตัวใน SPEC-001 §7 ถ้าขาดตัวไหน = FAIL

```json
{
  "suite": "TestWire",
  "git_sha": "154be25…",
  "status": "PASS",
  "started_at": "2026.06.02 00:00:00",
  "total": 42, "passed": 42, "failed": 0,
  "ran_names": ["test_framing_multiple_in_one_read", "..."],
  "failed_names": []
}
```

**เพิ่มด้วย (ไม่บังคับแต่ช่วยมาก):** `started_at` จาก `TimeCurrent()` —
ตอนนี้ผมใช้ file mtime เช็ค staleness ซึ่งใช้ได้ แต่ timestamp ในไฟล์ทนกว่า

---

## 4. Harness พร้อมแล้ว — รอบหน้ารันคำสั่งเดียว

```powershell
powershell -ExecutionPolicy Bypass -File D:\ea-farm\tools\run-mql5-tests.ps1
```

deploy → compile → รัน Strategy Tester → parse JSON → เทียบ git_sha ทั้งหมดในคำสั่งเดียว
ผมพิสูจน์ทุกขั้นด้วย `tools/probe/TesterProbe.mq5` แล้ว (รันจบใน 8 วินาที)

### 5 กับดักที่เจอตอนตั้ง harness — Codex ต้องรู้

| # | กับดัก | ผลถ้าไม่รู้ |
|---|--------|-------------|
| 1 | **ต้องรันบน `IUX Markets MT5 Terminal3`** เท่านั้น — `C:\Program Files\MetaTrader 5` ไม่มีบัญชีและไม่มี history เลย Strategy Tester รันไม่ได้ | tester ไม่ start |
| 2 | **symbol มี suffix `.iux`** — `EURUSD.iux` ไม่ใช่ `EURUSD` | tester abort |
| 3 | **history มีแค่ 2025.01.01 – 2026.06.19** (EURUSD.iux H1) ช่วงวันที่ต้องอยู่ในนี้ | tester abort |
| 4 | **`.set` ค่า string ต้องเป็น `Name=value` เปล่าๆ** — suffix `\|\|\|\|N` (ที่ใช้กับ numeric param) จะกลายเป็น**ส่วนของ string** ผมเจอ `FileOpen err=5004` เพราะชื่อไฟล์เป็น `result.json\|\|\|\|N` | input ที่ฉีดเข้าไปเพี้ยนแบบเงียบๆ |
| 5 | **★ EA ที่เรียก `ExpertRemove()` ใน `OnInit` ทำให้ tester log ว่า `tester stopped because OnInit failed`** และ terminal exit code = 0 ทั้งที่ test รันสำเร็จ | ถ้าตัดสินด้วย exit code จะได้ทั้ง false pass และ false fail — **ตัดสินจากไฟล์ JSON เท่านั้น** |

---

## 5. หนี้เทคนิคที่รายงานมา — รับทราบ ตรงกับที่ผมประเมิน

| หนี้ | ท่าที |
|------|-------|
| ยังไม่ได้รัน EA test ผ่าน Strategy Tester | ✅ ถูกต้อง — บล็อกเพราะ compile error แก้แล้วผมรันให้ทันที |
| ยังไม่ได้พิสูจน์ demo/soak/reconnect 24 ชม. | รับทราบ เป็น acceptance criteria ข้อสุดท้ายของ SPEC-001 ทำหลัง test เขียว |
| Python chaos suite ยังไม่ EA-driven | รับทราบ — ต้องเสร็จก่อนปิด SPEC-001 เพราะ chaos test ที่ไม่มี EA จริงพิสูจน์ reconnect/backoff ไม่ได้ |

---

## สรุป: `CHANGES_REQUIRED`

**ต้องแก้ก่อนถือว่าเสร็จ**
1. 🔴 `FILE_UTF8` → `FILE_BIN` + `StringToCharArray(CP_UTF8)` (§1)
2. 🔴 เพิ่ม `ran_names` ลง JSON เพื่อกัน test หายแบบเงียบๆ (§3❸)
3. 🟠 `if(total < 0) return false;` guard หลัง `StringToCharArray` (§3❶)
4. 🟠 chaos suite เป็น EA-driven จริง + พิสูจน์ soak/reconnect

**หนี้ที่ยอมรับ มีเส้นตาย**
- `test_partial_send_resumes` ด้วย socket จริง — ก่อน merge SPEC-011

**ที่ทำดีแล้ว** byte buffer framing · test ครบ 11/11 + เกิน 5 · เปลี่ยนเป็น EA ·
`FarmExecutor.mq5` 0 error 0 warning · รายงานหนี้เทคนิคตรงไปตรงมาไม่กลบ
