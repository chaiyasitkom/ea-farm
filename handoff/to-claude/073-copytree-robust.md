---
id: 073
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "072"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### ทำอะไรไปแล้ว
- `tests/test_codegen.py:22` เพิ่ม `copy_codegen_workspace()` ที่ copy เฉพาะ `contracts/schema`, `contracts/gen`, `contracts/symbols.json`, `tools/{codegen.py,task.py,__init__.py}`, `brain/**` และ `contracts/fixtures` เฉพาะ test ที่ต้องตรวจ fixture ownership
- `tests/test_codegen.py` เปลี่ยน 2 test ที่เคย `copytree(ROOT, ...)` ให้ใช้ workspace เฉพาะส่วน แล้ว `git init` ใน temp repo เองตามเดิม
- `tests/test_symbol_registry.py:25` เพิ่ม helper แบบเดียวกันสำหรับ symbol codegen stale check
- `.gitignore:79` เพิ่ม `.tmp-pytest-cache/`
- ตรวจแล้วไม่มี `copytree(ROOT, ...)` เหลือใน `tests/**` หรือ `tools/**`

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| Full check | `python tools/task.py check -> OK 4/4` | ยังได้ `3 passed, 1 failed` | `codegen-check` เห็น `contracts/gen/mql5/FarmMessages.mqh` stale จาก local working tree ที่ `tools/codegen.py` modified อยู่แล้ว ไม่ใช่ copytree ACL failure |
| Roundtrip | `pytest tests/test_roundtrip.py -> 17 passed` | รันใน session นี้ไม่ได้ | `Common\Files` ของ MT5 ติด `PermissionError` ตอนเขียน `ea-farm-rt-in-run1-1.json`; ผู้ใช้รันก่อนหน้าแล้วได้ `17 passed` |
| Temp cleanup | ไม่ควรเหลือ temp ใหม่ | `.tmp-pytest-run/` อาจยังอยู่ | ผมสร้างเพื่อเลี่ยง ACL ของ system temp; recursive delete ถูก tool policy block แม้ตรวจ path แล้ว |

### Test
- `.\.venv\Scripts\python.exe -m pytest tests/test_codegen.py::test_codegen_does_not_modify_handwritten_fixtures tests/test_codegen.py::test_codegen_check_detects_stale_gen tests/test_symbol_registry.py::test_codegen_check_detects_stale_symbols_gen`
  - `3 passed`
- `TMP/TEMP=D:\ea-farm\.tmp-pytest-run .\.venv\Scripts\python.exe -m pytest tests/test_task_runner.py::test_tool_lookup_uses_selected_python tests/test_task_runner.py::test_existing_venv_with_wrong_python_version_warns_without_recreating`
  - `2 passed`
- `TMP/TEMP=D:\ea-farm\.tmp-pytest-run .\.venv\Scripts\python.exe tools/task.py check`
  - lint OK
  - typecheck OK
  - test OK: `70 passed, 8 skipped, 17 deselected`
  - codegen-check FAIL: `contracts/gen/mql5/FarmMessages.mqh` diff
- `.\.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py`
  - failed locally before MQL5 run with `PermissionError` writing `C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\ea-farm-rt-in-run1-1.json`

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ไม่ได้ commit ตามคำสั่ง
- ไม่ได้แก้ `contracts/gen/mql5/FarmMessages.mqh` เอง แต่การรัน root tests/codegen-check ทำให้ generator เขียนไฟล์นี้ตาม `tools/codegen.py`; ตอนนี้ `git diff -- contracts/gen` ยังเห็น diff
- `git pull` ตอนเริ่ม session ล้มด้วย `error: cannot open '.git/FETCH_HEAD': Permission denied`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- ตรวจว่า local `tools/codegen.py` กับ `contracts/gen/mql5/FarmMessages.mqh` ตั้งใจให้ stale อยู่หรือควรรับ generated diff จาก codegen รอบ SPEC-005
- ตรวจว่า helper copy minimal workspace พอสำหรับ codegen tests ใน CI หรือควรดึง `pyproject.toml` เข้าไปด้วยเพื่อ future-proof
- ตรวจ working tree ก่อน commit เพราะมี SPEC-005 changes เดิมจำนวนมากอยู่ก่อน patch นี้

### คำถามค้าง
- ไม่มีสำหรับ copytree robustness; failure ที่เหลือเป็น generated diff / local ACL ไม่ใช่ ambiguity ของ patch นี้
