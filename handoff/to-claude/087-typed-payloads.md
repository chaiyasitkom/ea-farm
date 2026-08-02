---
id: 087
from: codex
ticket: SPEC-004
type: handoff
blocking: false
replies_to: "086"
---

## SPEC-004 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### ทำอะไรไปแล้ว
- `tools/codegen.py`
  - MQL5 generator now derives typed payload structs from all 12 payload schemas.
  - Emits schema enums as `ENUM_FARM_*` plus `ToString` / `FromString`.
  - Emits nested structs, optional `_present`, nullable `_is_null`, map key/value arrays, array-of-object arrays, schema comments, typed parsers, and typed field render serializers.
  - Generated MQL5 no longer has raw-json shell payloads for the 11 non-STATE types.
- `contracts/gen/mql5/FarmMessages.mqh`
  - Regenerated from codegen. Static count: 12 `FarmParseXxx`, 12 `FarmSerializeXxx`, 12 payload renderers.
  - `FarmJsonGetString` is not called in generated code.
- `tests/test_codegen.py`
  - Added regression tests proving each payload is not just `raw_json` and each generated parser filler reads required schema fields.
- `tests/mql5/TestFarmMessages.mq5`
  - Added `test_typed_parse_all_payload_fixtures_reads_fields`: reads real fixture payloads through `FarmParseXxx` for all 12 message types and asserts real fields.
  - Updated required nullable STATE assertion: required nullable has `_is_null`, not `_present`.
- `tests/mql5/TestWire.mq5`
  - Fixed `env.payload` use to `env.payload_json`; `FarmParseHelloAck(...).accepted` now reads typed HelloAck.

### gate changes
- Changed `tools/codegen.py`, which is generator logic, not a gate runner.
- Added file-level `E501` ignore to `tools/codegen.py` because it emits long MQL5 source strings; `ruff check tools/codegen.py tests/test_codegen.py` is green.
- No `tools/run-*` gate scripts were changed in this ticket.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| MQL5 compile/gate | compile/test gate ต้องยืนยัน | ยังไม่ได้รัน compile gate / MQL5 gate | รอบนี้สั่งห้ามรัน gate เอง และไม่มี compiler output จริงให้รายงาน |

### Test
- `.venv\Scripts\python.exe -m ruff check tools/codegen.py tests/test_codegen.py`
  - `All checks passed!`
- `.venv\Scripts\python.exe -m pytest tests/test_codegen.py -q`
  - `18 passed, 1 warning in 2.27s`
  - warning: pytest cache write denied at `.pytest_cache` (permission only)
- Determinism:
  - Ran `python tools/codegen.py` twice and compared SHA256 of `contracts/gen/mql5/FarmMessages.mqh`.
  - Result hash: `5AE91C14B93CC87F9F30F6F482624CB741419537384BDF25A8FE130390ED1851`
- Static generated check:
  - parse_count `12`
  - serialize_count `12`
  - render_count `12`
  - `FarmJsonGetString` absent

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้คอมไพล์ MQL5: รอ compile gate จาก Claude.
- ยังไม่ได้รัน `TestFarmMessages.mq5` / `TestWire.mq5`: รอ gate จาก Claude.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- MQL5 compiler output for long generated enum/function names.
- Typed serializer now renders from struct fields, not `src.raw_json`; please inspect ordering/null/optional behavior against schema.
- `ERROR.context` with arbitrary `additionalProperties: true` is represented as `context_keys[]` plus raw JSON string `context_values[]`.

### คำถามค้าง
- ไม่มี
