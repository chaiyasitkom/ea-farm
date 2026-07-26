# SPEC-001 — Compile Gate #1

**วันที่:** 2026-07-26 23:47 · **รันโดย:** Claude · **branch:** `feat/SPEC-001-mt5-executor`
**สถานะโค้ด:** uncommitted (untracked) — Codex ยังทำงานอยู่ ยังไม่ได้ส่ง handoff report

> นี่คือ **compile gate ไม่ใช่ code review** — ตรวจแค่ว่าคอมไพล์ผ่านและครบตาม test list
> review เต็มจะทำหลัง Codex ส่ง handoff report

---

## ✅ ผล: GATE PASSED

```
MQL5 COMPILE GATE -- 20260726-234718

[ OK ] FarmExecutor.mq5 -- 0 errors, 0 warnings
       -> FarmExecutor.ex5 39372 bytes
[ OK ] TestWire.mq5 -- 0 errors, 0 warnings
       -> TestWire.ex5 16306 bytes

[ OK ] all 3 .mqh files covered by a compiled target

GATE PASSED -- 0 errors, 0 warnings total
```

ไฟล์ที่ผ่าน compiler แล้ว: `FarmExecutor.mq5` · `Wire.mqh` (669 บรรทัด) · `Json.mqh` · `Logger.mqh` · `TestWire.mq5`

**0 warnings ด้วย** ซึ่งดีกว่าที่คาด — MQL5 มักบ่นเรื่อง implicit conversion และ
`datetime`/`long` ในโค้ดที่ไม่เคยคอมไพล์ ไม่มีเลยแม้แต่ตัวเดียว

---

## 🔴 ต้องแก้: test 4 ตัวจาก SPEC-001 §7 ยังไม่มี

| test ตาม spec | สถานะ |
|---------------|-------|
| `test_framing_multiple_in_one_read` | ✅ มี |
| `test_framing_split_across_reads` | ✅ มี |
| `test_framing_crlf_tolerance` | ✅ มี |
| `test_framing_empty_line_skipped` | ✅ มี |
| `test_framing_oversize_frame_rejected` | ❌ **ขาด** — กฎ 64KB (contract §1) |
| `test_json_parse_malformed_skips_line` | ❌ **ขาด** — ต้องไม่ปิด connection |
| `test_json_unknown_field_ignored` | ✅ มี |
| `test_json_unknown_type_ignored` | ✅ มี |
| `test_queue_full_drops_oldest` | ✅ มี |
| `test_partial_send_resumes` | ❌ **ขาด** — ห้ามส่งซ้ำทั้ง frame |
| `test_utf8_multibyte_not_split` | ❌ **ขาด** — edge case 6 |

7/11 · ขาด 4 ตัว **ทั้ง 4 ตัวเป็นเคสที่ทำให้ข้อมูลเสียหายหรือ order ซ้ำ ไม่ใช่เคสสวยงาม**
`test_partial_send_resumes` สำคัญสุด — ถ้า partial send แล้วส่งซ้ำทั้ง frame
ปลายทางจะได้ message ซ้ำ ซึ่งใน Phase 1 ยังไม่มี order แต่ Phase 2 จะกลายเป็น order ซ้ำ

หมายเหตุ: Codex ยังทำงานอยู่ อาจกำลังเขียนอยู่ — ไม่ใช่คำตัดสินว่าไม่ทำ

---

## 🟠 ต้องแก้: test เป็น Script รันอัตโนมัติไม่ได้

`TestWire.mq5` ใช้ `void OnStart()` = **Script** ซึ่ง MT5 รันจาก command line ไม่ได้เลย
ต้องลากลงชาร์ตด้วยมือ → **gate ยืนยันได้แค่ "คอมไพล์ผ่าน" ยังยืนยันไม่ได้ว่า "test ผ่าน"**

**ต้องเปลี่ยนเป็น EA:**
```mql5
int OnInit() {
   int failed = run_all_tests();
   WriteJsonResult(failed);   // เขียนผลลง Common\Files\ พร้อม git sha
   ExpertRemove();
   return INIT_SUCCEEDED;
}
```
แล้วรันผ่าน Strategy Tester ได้ (`terminal64.exe /config:...`)
รายละเอียดใน [07-compile-gate.md](../07-compile-gate.md)

---

## ✅ ตรวจแล้วไม่ใช่ปัญหา

**`test_framing_empty_line_skipped` ดูขัด spec แต่ไม่ขัด**

test assert ว่า `PopFrame` ปล่อย frame ว่างออกมา ซึ่งตอนแรกดูเหมือนขัดกับ
SPEC-001 edge case 5 ที่เขียนว่า *"บรรทัดว่าง → ข้ามเงียบๆ"*

แต่อ่าน `Wire.mqh:420-426` แล้วพบว่าชั้น `Pump` ข้ามให้:
```mql5
while(PopFrame(line)) {
   if(StringLen(line) == 0) continue;    // ← ข้ามที่นี่
   m_messages_recv++;
   HandleInboundLine(line);
}
```
`PopFrame` = framer ระดับล่าง (ปล่อยทุก frame) · การข้ามอยู่ชั้นบน
พฤติกรรมที่สังเกตได้จากภายนอกตรง spec **ไม่ต้องแก้**

---

## สิ่งที่ Codex ต้องทำต่อ

1. เพิ่ม test 4 ตัวที่ขาด (§7 ของ SPEC-001)
2. เปลี่ยน `TestWire.mq5` จาก Script → EA (`OnInit` + `ExpertRemove`) + เขียนผลเป็น JSON
3. commit งานตัวเองลง `feat/SPEC-001-mt5-executor` (อย่าใช้ `git add -A` — ดู AGENTS.md ข้อ 13)
4. ส่ง handoff report → Claude จะ review เต็มรูปแบบ

**ยังไม่ต้องแก้:** ไม่มี error/warning ให้แก้จาก compiler เลย
