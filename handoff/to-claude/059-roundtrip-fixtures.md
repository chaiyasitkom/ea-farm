---
id: 059
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "058"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** ไม่มี commit ตามคำสั่ง

### ทำอะไรไปแล้ว
- แก้ `contracts/fixtures/hello.valid*.json`
  - EURUSD 5 หลัก: `point=0.00001`, `tick_size=0.00001`, `digits=5`
  - ค่า symbol/account/local_limits เป็นค่าจริงขึ้น: `contract_size=100000.0`, `volume_min=0.01`, `volume_step=0.01`, `balance=10000.0`, `equity=10123.45`, `daily_loss_pct=2.0`
  - schema เดิมรับค่าทั้งหมดได้ ไม่มีชน pattern/min/max
- แก้ fixture ที่ทำให้ test helper fail จากข้อมูลผิด:
  - `error.valid*.json`: `severity=WARN` ต้อง `fatal=false`
  - `state.valid*.json`: `owned_net`, `owned_ticket_count`, `internal_hedge_detected`, `pending_orders[0].sl=null` ให้ตรงกับข้อมูล
  - `exec_report.valid.min.json`: minimal case เปลี่ยนเป็น `REJECTED` + `volume_filled=0.0` เพราะ `FILLED` โดยไม่มี `ticket` ขัด invariant

### diagnosis 7 tests
| test | สาเหตุ |
|---|---|
| `test_roundtrip_all_types_full` | fixture ผิด: ERROR fatal/severity และ STATE owned_net/hedge/sl ทำ invariant helper fail |
| `test_roundtrip_all_types_minimal` | fixture ผิด: EXEC_REPORT minimal เป็น FILLED แต่ไม่มี ticket; STATE minimal ticket_count/hedge ผิด |
| `test_canonical_json_identical_after_roundtrip` | fixture ผิดชุดเดียวกับ full/min; ยังไม่พบหลักฐานว่า round-trip code ผิด |
| `test_null_value_absent_three_states_survive` | fixture ผิด: `pending_orders[0].sl` เป็น `1.0` ทั้งที่ test ต้องการ `null`; `halt_reason` full ปรับเป็น explicit null |
| `test_unknown_field_dropped_in_payload` | ยังวินิจฉัย code จริงไม่ได้ใน sandbox เพราะ pytest เขียน Common Files ไม่ได้; test logic ใช้ injected unknown หลัง canonical แล้วถูกทาง |
| `test_unknown_field_dropped_in_nested_object` | ยังวินิจฉัย code จริงไม่ได้ใน sandbox ด้วยเหตุเดียวกัน; test logic ถูกทาง |
| `test_small_float_point_not_sci_notation` | fixture ผิด: `hello.valid.json` เดิม `point=1.0`; ตอนนี้เป็น `0.00001` แล้ว |

### gate changes
- `tools/run-mql5-tests.ps1`
  - สร้าง `ea-farm-rt-manifest.json` ใหม่ทุก run เสมอหลัง deploy fixtures ไม่พึ่ง manifest เก่า
  - manifest default นับเฉพาะ `*.valid.json` และ `*.valid.min.json` ที่ deploy จริง
  - `TestRoundTrip` gate assert ว่า `cases_processed` มีอยู่และ `>=` จำนวน valid/min fixtures ที่ deploy
  - เพิ่ม `cases_processed` เข้า observed result JSON เพื่อให้ audit เห็นจำนวน case จริง

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|---|---|---|---|
| fixture reuse | SPEC-005 บอกใช้ fixture เดิม ห้ามสร้างชุดใหม่ | แก้ fixture เดิม ไม่สร้างชุดใหม่ | คำสั่งรอบนี้ระบุชัดว่า fixture เป็นของ Codex ตาม SPEC-004 และต้องแก้ placeholder |
| XAUUSD | คำสั่งบอก XAUUSD ควรมี `point=0.01`, `contract_size=100.0` | ยังไม่ได้แก้ | repo ไม่มี XAUUSD/GOLD fixture ปัจจุบัน และ SPEC-005 ห้ามสร้างชุดใหม่ |

### Test
- `git pull` ตอนเริ่ม session:
  - failed: `error: cannot open '.git/FETCH_HEAD': Permission denied`
- `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py -q -o cache_dir=D:\ea-farm\.tmp-pytest-cache`
  - failed before MQL5: `PermissionError: [Errno 13] Permission denied: 'C:\\Users\\User\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\ea-farm-rt-in-run1-1.json'`
  - sandbox นี้เขียนนอก workspace ไม่ได้ จึงยังไม่ได้ผล 17 tests จริงหลังแก้ fixture
- `.\.venv\Scripts\python.exe -m pytest tests/test_codegen.py::test_all_valid_fixtures_pass tests/test_codegen.py::test_all_invalid_fixtures_fail -q -o cache_dir=D:\ea-farm\.tmp-pytest-cache`
  - `2 passed in 0.16s`
- PowerShell parser:
  - `PowerShell parse OK`
- `.\.venv\Scripts\python.exe -m ruff check tests/test_roundtrip.py`
  - `All checks passed!`
- fixture sanity ผ่าน:
  - canonicalize valid/min fixtures แล้วเรียก `_assert_business_invariants(...)` ได้ครบ

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้รัน MQL5 gate เองตามคำสั่งห้าม
- ยังไม่ได้ยืนยัน 17 round-trip tests หลังแก้ในเครื่องที่เขียน `Common\Files` ได้
- ยังไม่ได้แตะ `contracts/schema/**`, `contracts/gen/**`, `contracts/symbols.json`, `Wire.mqh`, `FarmExecutor.mq5`, `TestWire.mq5`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- ช่วยรัน `pytest tests/test_roundtrip.py` ใน environment ที่เขียน `Common\Files` ได้ เพื่อแยก unknown-field payload/nested ว่าเป็น code bug หรือผ่านแล้ว
- ดู diff `tools/run-mql5-tests.ps1` ก่อนเชื่อผล gate ตามกฎ gate self-certification
- ตัดสินใจว่าจะต้องมี XAUUSD fixture ใน SPEC-004/005 หรือไม่ เพราะตอนนี้ไม่มี fixture ให้ปรับ

### คำถามค้าง
- ไม่มี
