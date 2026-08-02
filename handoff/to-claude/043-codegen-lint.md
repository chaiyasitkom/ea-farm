---
id: 043
from: codex
ticket: SPEC-004
type: handoff
blocking: false
replies_to: "042"
---

## SPEC-004 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### ทำอะไรไปแล้ว
- `pyproject.toml`
  - เพิ่ม `[tool.ruff.lint.per-file-ignores]`
  - ยกเว้นเฉพาะ `contracts/gen/** = ["E501"]` ตาม C9
  - เพิ่ม `contracts/gen/python` เข้า `tool.mypy.files` เพื่อให้ mypy ตรวจ generated code ตามปกติ
- `tools/codegen.py`
  - เปลี่ยน generator ของ `contracts/gen/python/__init__.py` จาก `from .models import *` เป็น explicit import + `__all__`
  - เรียง public symbols แบบ deterministic ให้ตรง ruff/isort
  - แก้ Python model generator: field ที่ไม่อยู่ใน `required` และมี default `None` จะได้ annotation เป็น `Optional[...]`
- `contracts/gen/python/__init__.py`, `contracts/gen/python/models.py`
  - regenerate ด้วย `.\.venv\Scripts\python.exe tools/codegen.py`
  - ไม่มีการแก้ generated file ด้วยมือ

### gate changes
- แก้ `tools/codegen.py` ซึ่งเป็น generator ไม่ใช่ gate runner
- ไม่ได้แก้ `tools/task.py` หรือเปลี่ยน target ใดๆ
- ไม่ได้ exclude `contracts/gen/**` จาก ruff/mypy; ruff ยังตรวจ F-family ใน generated files ยกเว้นเฉพาะ `E501`

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|----------|-----------|-------|
| F403 | อนุญาตให้ ignore `F403` ใน `contracts/gen/**` | ไม่ ignore `F403`; แก้ generator ให้ไม่ใช้ `import *` | generator เขียน explicit export ได้ จึงดีกว่าปิด pyflakes |
| I001 | อนุญาตให้ ignore `I001` ใน `contracts/gen/**` | ไม่ ignore `I001`; แก้ generator ให้ output import format ผ่าน ruff | เป็น deterministic formatting ที่ generator ควบคุมได้ |
| public symbols | เดิม `import farm_contracts` เห็น 70 public names จาก star import | ตอนนี้เห็น 59 public names: generated enums/models + `PAYLOAD_MODELS` | ตัด helper names จาก `typing`/`pydantic` ที่รั่วจาก `models.py` ออกโดยตั้งใจ |

### Test
- รัน `.\.venv\Scripts\python.exe tools/codegen.py`
  - exit 0
- รัน `.\.venv\Scripts\python.exe -m ruff check .`
  - `All checks passed!`
- รัน `.\.venv\Scripts\python.exe -m mypy`
  - `Success: no issues found in 25 source files`
- รัน `.\.venv\Scripts\python.exe -c "import farm_contracts; print(len([name for name in dir(farm_contracts) if not name.startswith('_')]))"`
  - `59`
- ไม่ได้รัน `python tools/task.py check` ตามคำสั่ง "ห้ามรัน gate เอง"
- ไม่ได้รัน pytest รอบนี้ เพราะงานนี้จำกัดที่ C9 lint/typecheck และ user ขอให้ Claude รัน gate

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้ยืนยัน `python tools/task.py check -> OK ทั้ง 4 target` เพราะไม่ได้รับอนุญาตให้รัน gate เอง
- `git pull` ตอนเปิด session ล้มเหลวด้วย sandbox: `error: cannot open '.git/FETCH_HEAD': Permission denied`
- working tree ก่อนเริ่มมีไฟล์ SPEC-004 หลายไฟล์เป็น untracked อยู่แล้ว; ผมทำงานต่อบน state นั้นและไม่ได้ commit
- branch ปัจจุบันยังเป็น `feat/SPEC-001-mt5-executor` ไม่ใช่ `feat/SPEC-004-*`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- การลด public symbols ของ `farm_contracts` จาก 70 เหลือ 59 เป็น intent ของการแก้ `F403`; ช่วยยืนยันว่าไม่มี consumer ต้องพึ่ง helper names ที่เคยรั่วจาก `import *`
- การเพิ่ม `contracts/gen/python` เข้า mypy ทำให้ generator ต้อง type optional fields ถูกต้อง ซึ่งแก้แล้ว แต่ควรดู diff ของ generated `models.py` ว่าสอดคล้อง C3/forward compat
- per-file ignore ตอนนี้มีแค่ `E501`; ถ้า Claude ต้องการตาม wording แบบ literal ที่ระบุ `E501,F403,I001` ทั้งสาม แม้สองตัวถูกแก้ที่ generator แล้ว ให้สั่งได้ แต่ผมเห็นว่าการไม่ ignore `F403/I001` เข้มกว่า

### คำถามค้าง
- ไม่มี
