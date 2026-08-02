---
id: 069
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "068"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** ไม่ได้ commit ตามคำสั่ง

### ทำอะไรไปแล้ว
- `brain/common/canonical_json.py`: normalize float zero ทุกกรณีเป็น `0.0`; `-0.1` ยังรักษาเครื่องหมายไว้
- `mt5-ea/Include/Farm/JsonCore.mqh`: `FarmJsonFormatDouble()` คืน `0.0` เมื่อค่าเป็น zero เพื่อกัน `DoubleToString(-0.0)` หลุดเป็น `-0.0`
- `tests/test_roundtrip.py`: เปลี่ยน negative-zero case ไปใช้ field จริง `EXEC_REPORT.payload.swap` และ assert normalize เป็น `"swap":0.0`
- `tests/test_canonical_json.py`: update expected negative zero เป็น `0.0` ตาม SPEC-004 rev.2c
- fixture fixes ที่เป็นต้นเหตุ 4 failures:
  - `error.valid.json`, `error.valid.min.json`: `severity="WARN"` ต้อง `fatal=false`
  - `exec_report.valid.min.json`: minimal case เดิม `result="FILLED"` แต่ไม่มี `ticket`; เปลี่ยนเป็น `REJECTED`, `volume_filled=0.0`, retcode reject
  - `state.valid.json`: `pending_orders[0].sl` เปลี่ยนจากค่าเป็น `null` เพื่อให้ 3-state test มีเคส null จริง

### รายงาน 4 failures ที่เหลือ
| test | message type | field | Python ก่อนแก้ | MQL5 ก่อนแก้ | สาเหตุ |
|---|---|---|---|---|---|
| `test_roundtrip_all_types_full` | `ERROR` | `payload.fatal` | `true` | `true` | ไม่ใช่ serializer mismatch; fixture ขัด invariant `severity=WARN -> fatal=false` |
| `test_roundtrip_all_types_minimal` | `ERROR` | `payload.fatal` | `true` | `true` | ไม่ใช่ serializer mismatch; fixture min ขัด invariant เดียวกัน |
| `test_roundtrip_all_types_minimal` | `EXEC_REPORT` | `payload.ticket` / `payload.result` | `result="FILLED"`, `ticket` absent | เหมือน Python | ไม่ใช่ serializer mismatch; fixture min ขัด invariant `FILLED -> ticket not null` |
| `test_canonical_json_identical_after_roundtrip` | `ERROR`, `EXEC_REPORT` | fields ด้านบน | เหมือนด้านบน | เหมือนด้านบน | helper `_assert_canonical_match()` เรียก business invariant หลัง canonical match; byte-identical ไม่ใช่จุดที่พัง |
| `test_null_value_absent_three_states_survive` | `STATE` | `payload.pending_orders[0].sl` | `2375.5` | `2375.5` | ไม่ใช่ serializer mismatch; fixture ไม่มี null ตามที่ test ต้องการ |

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|---|---|---|---|
| business invariant ใน SPEC-005 | non-goal ของ roundtrip | แก้ fixture ให้ผ่าน invariant ที่ test มีอยู่แล้ว | ห้ามผ่อน assertion/ห้ามแก้ test; fixture เป็นข้อมูลผิด ไม่ใช่ serializer bug |
| negative zero test | เดิม preserve `-0.0` | normalize เป็น `0.0` | SPEC-004 rev.2c ตัดสินใหม่แล้ว |

### Test
- `git pull`: fail เพราะ `error: cannot open '.git/FETCH_HEAD': Permission denied`
- `.venv\Scripts\python.exe -m pytest tests/test_canonical_json.py tests/test_codegen.py -q`
  - ผล: `18 passed, 1 warning`
- `python tools/codegen.py` หลังแก้
  - ผล: exit 0
  - fixture hash ก่อน/หลัง codegen: ไม่ต่างกัน
- `.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py -q`
  - ใน sandbox Codex fail ก่อนรันจริงเพราะเขียน `C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\...` ไม่ได้: `PermissionError: [Errno 13] Permission denied`
  - ต้องให้ environment ที่มีสิทธิ์ Common\Files rerun เพื่อยืนยัน `17 passed`

### gate changes
ไม่มีการแก้ `tools/**` ในรอบนี้

### สิ่งที่ยังไม่ได้ทำ / หนี้เทคนิค
- ยังไม่ได้เห็นผล `pytest tests/test_roundtrip.py -> 17 passed` หลังแก้ เพราะ sandbox เขียน `Common\Files` ไม่ได้
- ยังไม่ได้เห็น compiler output หลังแก้ `JsonCore.mqh`; รอบก่อนหน้าผู้ใช้รายงาน MQL5 gate PASSED ก่อน patch negative-zero

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- การแก้ fixture 3 จุดด้านบน: เป็นข้อมูลที่ขัด invariant/test ไม่ใช่ปัญหา serializer
- negative-zero case เดิมใช้ `EXEC_REPORT.payload.profit` ซึ่งไม่อยู่ใน schema และถูก drop ถูกต้องแล้ว; ตอนนี้เปลี่ยนเป็น `swap`

### คำถามค้าง
ไม่มี
