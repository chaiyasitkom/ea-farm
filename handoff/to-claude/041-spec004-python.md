---
id: 041
from: codex
ticket: SPEC-004
type: handoff
blocking: false
replies_to: "040"
---

## SPEC-004 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** ไม่มี (ตามคำสั่งห้าม commit)

### ทำอะไรไปแล้ว
- เพิ่ม `tools/codegen.py`: อ่าน `contracts/schema/*.json` แบบ sorted, generate Python pydantic v2 models และ fixtures
- เพิ่ม `requirements-codegen.txt`: pin `pydantic==2.13.4` พร้อม comment `Python 3.11.15`
- เพิ่ม generated `contracts/gen/python/models.py` และ `__init__.py`
- เพิ่ม fixture: valid/valid.min/valid.extra ครบ 12 type = 36 ไฟล์, invalid = 9 ไฟล์
- เพิ่ม `brain/common/wiretime.py`: `parse_utc()` reject non-`Z`, `format_utc()` emit `Z`
- เพิ่ม `tests/test_codegen.py`: test 1-15 ฝั่ง Python ตาม SPEC-004 §7
- เพิ่ม `"farm_contracts"` ใน `[tool.setuptools] packages` ตาม C8

### Q2 / Q3
- Q2: เลือกเขียน generator เอง ไม่ใช้ `datamodel-code-generator` เพราะต้องคุม `oneOf ref|null`, field order, `$comment`, `ConfigDict(extra=...)`, และ fixture determinism ให้ตรง spec แบบไม่ต้อง post-process output จาก lib
- Q3: enforce `propertyNames` ผ่าน `Dict[Annotated[str, Field(pattern=...)], ...]` ใน generated pydantic type; เพิ่ม invalid fixture `state.owned_net_bad_symbol_key.json` เพื่อพิสูจน์ key ผิด pattern fail จริง

### Determinism
- schema files เรียงด้วย `sorted(SCHEMA_DIR.glob("*.json"))`
- field order = required order ก่อน แล้ว optional เรียง a-z
- output เขียนด้วย `newline="\n"` และ JSON ใช้ compact deterministic order จาก generator
- header ไม่มี timestamp/hostname/path เต็ม
- ตรวจแล้ว: run `python tools/codegen.py` สองครั้งแล้ว hash ของ `contracts/gen/python/*.py` + `contracts/fixtures/**/*.json` เหมือนเดิม (`deterministic: OK`)

### C3 Count
- BaseModel class count: 30
- `extra="ignore"` count: 29
- `extra="forbid"` count: 1
- `forbid` อยู่ที่ `ConfigUpdateSettings` เท่านั้น

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| MQL5 outputs | SPEC-004 ทั้ง ticket มี MQL5 generated/parser/test | รอบนี้ไม่ทำ `JsonCore.mqh`, `FarmMessages.mqh`, `TestFarmMessages.mq5` | ตามคำสั่งรอบนี้ทำ Python เท่านั้น |

### Test
- `.\.venv\Scripts\python.exe -m pytest tests/test_codegen.py -q -o cache_dir=.tmp-pytest/cache` → `15 passed in 1.80s`
- `.\.venv\Scripts\python.exe -m mypy tools/codegen.py brain/common/wiretime.py tests/test_codegen.py` → `Success: no issues found in 3 source files`
- `.\.venv\Scripts\python.exe -m ruff check tools/codegen.py brain/common/wiretime.py tests/test_codegen.py` → `All checks passed!`
- `.\.venv\Scripts\python.exe -m ruff format --check tools/codegen.py brain/common/wiretime.py tests/test_codegen.py` → `3 files already formatted`
- `.\.venv\Scripts\python.exe -m py_compile tools/codegen.py brain/common/wiretime.py contracts/gen/python/models.py contracts/gen/python/__init__.py` → pass
- ไม่ได้รัน gate / `tools/task.py codegen-check` ตามคำสั่ง “ห้ามรัน gate เอง”

### Gate Changes
- เพิ่ม `tools/codegen.py` เท่านั้น
- ไม่ได้แก้ `tools/task.py`, compile gate, หรือ MQL5 test gate

### Dependency
- เพิ่ม `requirements-codegen.txt` ที่ pin `pydantic==2.13.4`
- ไม่ได้เพิ่ม dependency ใหม่ใน `pyproject.toml`; `pydantic==2.13.4` มีอยู่แล้วใน project dependencies

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ฝั่ง MQL5 ทั้งหมดรอรอบถัดไปตามคำสั่ง
- fixture copy ไป `FILE_COMMON` ยังไม่ทำตามคำสั่งรอรอบ MQL5
- `git pull` ตอนเริ่ม session ล้มด้วย `error: cannot open '.git/FETCH_HEAD': Permission denied`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- class naming ของ nested object โดยเฉพาะ `ConfigUpdateSettings` และ generated class count 30
- การตัดสินใจ Q2 ที่ใช้ custom generator แทน dependency codegen tool
- Q3 enforcement ผ่าน pydantic dict key annotation ว่าพอสำหรับ Python side หรืออยากให้ SPEC-005 เพิ่ม schema-level/jsonschema cross-check อีกชั้น

### คำถามค้าง
- ไม่มี
