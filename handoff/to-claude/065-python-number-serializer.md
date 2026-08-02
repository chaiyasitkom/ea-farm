---
id: 065
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "064"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none (per instruction: no commit)

### ทำอะไรไปแล้ว
- เพิ่ม `brain/common/canonical_json.py`
  - `dumps_canonical_json()` เป็น serializer จุดเดียวของฝั่ง Python สำหรับ wire/canonical JSON
  - float ใช้รูปแบบเดียวกับ MQL5 ปัจจุบัน: fixed 10 decimals แล้ว trim zero, เก็บทศนิยมอย่างน้อย 1 ตำแหน่ง, ไม่มี `e/E`
  - int แยกจาก float: `100000` คงเป็น int, `100000.0` คงเป็น double
  - reject non-finite float
- แก้ `tests/test_roundtrip.py`
  - `_canonical_json()`, special-case injection, manifest writer ใช้ `dumps_canonical_json()` แทน `json.dumps()` ในเส้นทางที่ปล่อย JSON เข้า wire/harness
  - แก้ต้นเหตุ `0.00001 -> 1e-05` จาก Python driver
- เพิ่ม `tests/test_canonical_json.py`
  - lock regression สำหรับ `0.00001`, `100000.0`, int ไม่มี `.0`, large float, `-0.0`, และ NaN
- แก้ `mt5-ea/Include/Farm/JsonCore.mqh`
  - เพิ่ม `FarmJsonCanonicalNumber`, `FarmJsonCanonicalValue`, `FarmJsonAppendFieldPrefix`
  - canonical number ไม่ใช้ raw token, preserve `-0.0`
- แก้ `tools/codegen.py` แล้ว regenerate `contracts/gen/mql5/FarmMessages.mqh`
  - generated MQL5 payload parse path ใช้ `FarmCanonicalizePayloadJson()` แทน `doc.Root().ToJson()`
  - canonicalizer เดินเฉพาะ schema `properties` จึง drop unknown field ทั้ง payload/nested object
  - dynamic maps เช่น `owned_net` ยังเก็บ key ตาม data เพราะ schema เป็น `additionalProperties`
  - `STATE` เปลี่ยนจาก `root.ToJson()` เป็น `FarmCanonicalState(root)` ด้วย

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| ไม่มี | - | ไม่มี | - |

### gate changes
- แก้ `tools/codegen.py` เพื่อสร้าง MQL5 canonical payload serializer และให้ fixture writer ใช้ Python serializer จุดเดียว
- ไม่ได้แก้ `tools/run-mql5-tests.ps1` ในรอบนี้ (ไฟล์นี้ dirty อยู่ก่อนแล้ว)

### Test
- `.\.venv\Scripts\python.exe -m ruff check brain/common/canonical_json.py tests/test_canonical_json.py tests/test_roundtrip.py tools/codegen.py contracts/gen/python`
  - `All checks passed!`
- `.\.venv\Scripts\python.exe -m mypy brain/common/canonical_json.py tests/test_canonical_json.py tests/test_roundtrip.py tools/codegen.py contracts/gen/python`
  - `Success: no issues found in 7 source files`
- `.\.venv\Scripts\python.exe -m pytest tests/test_canonical_json.py tests/test_codegen.py -q`
  - `17 passed, 1 warning in 2.62s`
- `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py -q`
  - ยังรันเต็มไม่ได้ใน Codex sandbox: `PermissionError: [Errno 13] Permission denied: 'C:\\Users\\User\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\ea-farm-rt-in-run1-1.json'`
  - output สรุป: `1 failed, 16 errors` ทั้งหมดเกิดก่อน MQL5 run จาก permission เขียน Common Files
- `git pull`
  - รันตาม protocol แต่ fail: `error: cannot open '.git/FETCH_HEAD': Permission denied`

### ไล่ 5 failures เดิม
- `test_no_scientific_notation_in_mql5_output`: แก้ด้วย Python serializer + MQL5 canonical number; ควรหายถ้า compile gate ผ่าน
- `test_small_float_point_not_sci_notation`: แก้ต้นเหตุ Python `json.dumps(0.00001) -> 1e-05`; input ตอนนี้เป็น `0.00001`
- `test_null_value_absent_three_states_survive`: ไม่ได้ผ่อน assertion; MQL5 canonicalizer เดิน schema และ skip absent optional, emit `null` เมื่อ input เป็น null
- `test_unknown_field_dropped_in_payload`: แก้ที่ MQL5 generated canonicalizer; unknown payload key ไม่ถูก emit
- `test_unknown_field_dropped_in_nested_object`: แก้ที่ MQL5 generated canonicalizer; nested known object emit เฉพาะ schema properties

### ตรวจข้อ 3: MQL5 รับ `1e-05` แล้วส่งผ่านไหม
- พบว่าเป็นบั๊กจริงก่อนแก้: `FarmParsePayloadJson()` เดิม parse แล้ว `out_json = doc.Root().ToJson()`, และ `ToJson()` ของ number คืน `number_raw`
- ผลคือ MQL5 ไม่ได้ทดสอบ serialization number จริงสำหรับ payload ส่วนใหญ่ และ unknown field รอดออกมาได้
- หลังแก้ generated path ใช้ schema canonicalizer + `FarmJsonCanonicalNumber()` แทน raw token

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้เห็น compiler output จริงของ MQL5 ใน environment นี้
- ยังไม่ได้รัน `pytest tests/test_roundtrip.py -> 17 passed` ใน environment นี้ เพราะ sandbox ไม่มีสิทธิ์เขียน `Common\Files`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- Review generated canonicalizer volume ใน `contracts/gen/mql5/FarmMessages.mqh`: logic ถูก generate จาก schema แต่ diff ใหญ่
- ยืนยันว่าการ mirror `DoubleToString(value, 10)` บน Python เป็น precision policy ที่ต้องการสำหรับ rev.2b
- ตรวจ compile gate เพราะมี helper ใหม่ใน `JsonCore.mqh` และ generated code ใช้ forward declarations

### คำถามค้าง
- ไม่มี
