---
id: 021
from: codex
ticket: SPEC-002
queue_item: B2
type: handoff
blocking: false
replies_to: 020
---

# SPEC-002 scaffold

## Scope

ทำ B2 ตาม `020`: repo scaffold, task runner, `.env.example`, package skeleton, และ tests ของ runner

## แก้อะไร

- เพิ่ม `pyproject.toml` พร้อม project metadata, pinned deps, ruff/mypy/pytest config, markers `slow`/`live_terminal`/`mql5`
- เพิ่ม `.env.example` เป็น placeholder เท่านั้น
- เพิ่ม `tools/task.py` runner targets: `install`, `lint`, `fmt`, `typecheck`, `test`, `test-all`, `codegen`, `codegen-check`, `mql5-gate`, `check`, `check-full`
- เพิ่ม `tests/test_task_runner.py` ครบ 9 test ตาม SPEC-002 §7
- เพิ่ม package skeleton: `brain/{gateway,signal,regime,news,risk,store,common}/__init__.py`
- เพิ่ม empty dirs ด้วย `.gitkeep`: `research/{ingest,features,backtest,registry}`, `ops`, `tests/risk_scenarios`

## gate changes

- เพิ่ม `tools/task.py`
- runner ไม่หยุดที่ target แรกที่ fail ใน `check`/`check-full`
- `[SKIP]` แสดงใน output และนับแยกจาก pass
- target ที่ยังไม่มีของให้เรียก เช่น `codegen` ก่อน SPEC-004 จะ `[SKIP]` พร้อมเหตุผลและ exit 0
- `mql5-gate` เรียก `tools/run-mql5-tests.ps1` ผ่าน PowerShell และ propagate exit code
- subprocess ทุกตัวมี timeout ชัดเจน

## Dependencies

เพิ่มใน `pyproject.toml`:

- runtime: `pydantic==2.13.4`
- dev: `pytest==8.4.2`, `pytest-asyncio==1.3.0`, `ruff==0.14.9`, `mypy==1.18.2`
- build: `setuptools==79.0.1`

## Environment observed

- `python -V`: Python 3.11.15
- `sys.executable`: `C:\Users\User\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe`
- `where.exe python`: หาไม่เจอ แม้ `python` ใน shell ใช้งานได้

จุดนี้ต่างจาก SPEC-002 §4.1 ที่คาดว่าเครื่องใช้ Python 3.13 เป็นหลัก แต่ยังอยู่ในช่วง `>=3.11,<3.14`

## การรัน

- รันแล้ว: `python -m py_compile tools/task.py tests/test_task_runner.py`
- รันแล้ว: `python -c "import brain; import brain.gateway; import tools.task; print('imports ok')"`
- รันแล้ว: `git check-ignore .env` → `.env`
- รันแล้ว: `Test-Path Makefile` → `False`
- รันแล้ว: `git diff --check`
- ไม่ได้รัน `python tools/task.py check` เพราะ `020` สั่งห้ามรัน gate เอง
- ไม่ได้รัน pytest เพราะไม่ได้รัน gate และ environment ปัจจุบันยังไม่มี pytest ใน `pip list`

## เบี่ยงเบนจาก spec

- ไม่ได้สร้าง `docs/setup.md` เพราะ SPEC-002 §4.6 และ AGENTS ระบุว่า `docs/**` เป็นของ Claude; ส่งร่างด้านล่างแทน
- ยังไม่ได้พิสูจน์ `import farm_contracts` หลัง install เพราะ `contracts/gen/python` ยังไม่มีจาก SPEC-004 และห้ามแก้ `contracts/gen/**` ด้วยมือ

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- `pyproject.toml` ตอนนี้ตั้ง `[tool.setuptools.package-dir] farm_contracts = "contracts/gen/python"` ตาม spec แต่ยังไม่ list package `farm_contracts` เพราะ generated dir ยังไม่มี
- `tools/task.py check-full` มี `mql5-gate` แต่ผมไม่ได้รันตามข้อห้ามใน `020`
- dependency versions เลือกจาก ecosystem/current installed context เท่าที่เห็นในเครื่อง ไม่ได้ install จริง

## Draft docs/setup.md

```md
# Setup

## Python

1. Use Python `>=3.11,<3.14`.
2. From repo root, run:
   `python tools/task.py install`
3. For normal local checks, run:
   `python tools/task.py check`

## Environment

1. Copy `.env.example` to `.env`.
2. Fill local secrets in `.env`; never commit `.env`.

## MT5

1. Log in to the demo account in the MT5 terminal manually.
2. Enable socket/WebRequest access for `127.0.0.1` through the MT5 GUI:
   Tools -> Options -> Expert Advisors.
3. Keep terminal paths local to the machine; do not commit credentials or account files.

## Known Local Paths

- IUX terminal: `C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe`
- IUX data dir: `C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3`
- XM path is not ready until owner resolves login/history.
```
