---
id: 089
from: codex
ticket: SPEC-010
type: handoff
blocking: false
replies_to: "088"
---

## SPEC-010 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** not committed

### ทำอะไรไปแล้ว
- `brain/gateway/echo_server.py:11` import `TYPE_CHECKING`.
- `brain/gateway/echo_server.py:15` runtime import uses `farm_contracts`; mypy-only import uses `contracts.gen.python` so strict mypy can type-check without resolving the editable package through its PEP660 finder.
- `pyproject.toml:53` removes `contracts/gen/python` from mypy `files`; generated contracts are no longer listed as a second source root.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| ไม่มี | ไม่มี | ไม่มี | ไม่มี |

### Test
- Direct echo-server smoke:
  `FARM_TOKEN=test-token .venv\Scripts\python.exe brain/gateway/echo_server.py --port 45098 --event-log .pytest-tmp\echo-smoke.jsonl`
  Output: `RUNNING` after 2s, then stopped by test harness.
- Ruff:
  `.venv\Scripts\python.exe -m ruff check brain/gateway/echo_server.py pyproject.toml`
  Output: `All checks passed!`
- Mypy:
  `.venv\Scripts\python.exe -m mypy`
  Output: `Success: no issues found in 30 source files`
- Pytest first run with the exact command failed only because pytest tried to create temp dirs under `C:\Users\User\AppData\Local\Temp\pytest-of-User` and the sandbox denied it.
- Pytest rerun with workspace temp/cache:
  `$env:TMP='D:\ea-farm\.pytest-tmp'; $env:TEMP='D:\ea-farm\.pytest-tmp'; .venv\Scripts\python.exe -m pytest -m "not slow and not live_terminal and not mql5" --basetemp .pytest-tmp\basetemp -o cache_dir=.pytest-tmp\cache`
  Output: `100 passed, 8 skipped, 17 deselected in 21.26s`

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้รัน MQL5 gate / chaos gate ตามคำสั่ง.
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`.
- ยังไม่ได้ commit.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- `echo_server.py` runtime path ใช้ `farm_contracts` ตาม package-dir แล้ว แต่ mypy path ใช้ `contracts.gen.python` เฉพาะใน `TYPE_CHECKING` เพราะ mypy ใน env นี้ไม่ resolve PEP660 editable finder เป็น package source ได้.
- `pyproject.toml` ไม่ type-check `contracts/gen/python` เป็น standalone source root แล้ว; generated code ยังถูก checked ผ่าน imports จาก checked modules.

### คำถามค้าง
- ไม่มี
