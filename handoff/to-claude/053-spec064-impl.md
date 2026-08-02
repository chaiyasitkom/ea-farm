---
id: 053
from: codex
ticket: SPEC-064
type: handoff
blocking: false
replies_to: "052"
---

## SPEC-064 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none (per instruction: no commit)

### ทำอะไรไปแล้ว
- เพิ่ม `brain/common/registry.py`
  - `SymbolRegistry.load()` อ่าน `contracts/symbols.json`
  - `to_canonical()` / `to_raw()` fail-closed ด้วย `UnknownSymbolError`
  - validator ตรวจ schema-shaped constraints + invariants:
    base != quote, mapping อ้าง canonical ที่มี definition, canonical ที่ไม่ถูก map ถึงเตือนด้วย `UserWarning`
  - duplicate raw key ตรวจตอน parse ด้วย `object_pairs_hook`
- ต่อ `tools/codegen.py`
  - generate `contracts/gen/python/symbols.py`
  - generate `contracts/gen/mql5/FarmSymbols.mqh`
  - include symbols exports ใน `contracts/gen/python/__init__.py`
  - ใช้ validator เดียวกับ runtime ก่อน generate
- เพิ่ม `tests/test_symbol_registry.py`
  - Python tests 19 tests ครอบ test list หลัก + generated stale/determinism + static Python/MQL mapping agreement
- เพิ่ม `tests/mql5/TestFarmSymbols.mq5`
  - MQL tests 7 tests สำหรับ GOLD->XAUUSD, unknown->"", risk unknown false, null spread -> -1, base/quote, production_ready false, correlation groups
- gate changes:
  - แก้ `tools/run-mql5-tests.ps1` เพิ่ม suite `TestFarmSymbols` และ required test names เท่านั้น

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| duplicate raw ใน JSON object | validator จับ duplicate raw | จับได้เฉพาะผ่าน loader ที่ใช้ `object_pairs_hook`; หลัง `json.loads` ปกติจะจับไม่ได้ | JSON object duplicate key ถูก parser ทับก่อนถึง validator |
| MQL cross-check | รัน MQL5 dump แล้ว Python เทียบ | เพิ่ม static cross-check จาก generated MQL lookup แทน | ห้ามรัน gate เอง และไม่มี compile output จริงในรอบนี้ |

### Test
- `.venv\Scripts\python.exe -m pytest -p no:cacheprovider tests/test_symbol_registry.py`
  - `19 passed in 2.36s`
- `.venv\Scripts\python.exe tools\task.py lint`
  - `All checks passed!`
  - `[ OK ] lint`
- `.venv\Scripts\python.exe tools\task.py typecheck`
  - `Success: no issues found in 28 source files`
  - `[ OK ] typecheck`
- `.venv\Scripts\python.exe tools\task.py test`
  - `75 items`
  - `67 passed, 8 skipped, 1 warning in 5.74s`
  - warning: pytest cache write denied at `D:\ea-farm\.pytest_cache\...`
- `python tools/codegen.py`
  - exit 0
- `git diff --check`
  - exit 0
  - warning only: `tools/run-mql5-tests.ps1` LF will be replaced by CRLF next time Git touches it
- `python tools/task.py codegen-check`
  - **FAIL in current uncommitted working tree**
  - output shows diff under `contracts/gen/python/__init__.py` because generated symbols exports are intended new generated output not yet baseline/committed
  - stale detection for `symbols.json` is covered by `test_codegen_check_detects_stale_symbols_gen`
- MQL5 gate / compile:
  - not run per instruction; ยังไม่ได้ compile, รอ compile gate

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- MQL5 compile/test gate ยังไม่ได้รันตามคำสั่งของเจ้าของงาน
- `codegen-check` จะเขียวหลัง generated diff นี้ถูก commit เป็น baseline; รอบนี้แดงเพราะห้าม commit

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- Review `tools/run-mql5-tests.ps1` gate change ก่อนเชื่อผล gate รอบถัดไป
- Review `FarmSymbols.mqh` generated style ว่า MQL5 compiler รับ signature by-reference และ function layout นี้หรือไม่
- Review policy: unused canonical เป็น warning ไม่ใช่ error ตรงกับข้อความ "ควรเตือน" แล้วหรือยัง

### คำถามค้าง
- ไม่มี
