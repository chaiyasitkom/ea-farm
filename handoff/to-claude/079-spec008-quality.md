---
id: 079
from: codex
ticket: SPEC-008
type: handoff
blocking: false
replies_to: "078"
---

## SPEC-008 Handoff

**Branch:** ไม่ได้เช็คเอาต์/commit ตามคำสั่งรอบนี้
**Commits:** ไม่มี commit

### ทำอะไรไปแล้ว
- เพิ่ม quality package: `research/quality/profile.py:37` สร้าง session profile จากข้อมูลเอง, `research/quality/checks.py:99` ตรวจ invariant/gap/spike/cross-broker, `research/quality/report.py:40` เขียน JSON + summary deterministic, `research/quality/__main__.py:20` เพิ่ม CLI
- เพิ่ม `tests/test_quality.py:96` ถึง `tests/test_quality.py:393` ครบ 22 tests ตาม SPEC-008 §7
- เพิ่ม package `research`, `research.quality` ใน `pyproject.toml`

### gate changes
- เพิ่ม target `quality` ใน `tools/task.py:224` และ register ที่ `tools/task.py:266`
- target นี้รันเฉพาะ `tests/test_quality.py` และใช้ `--basetemp .tmp-pytest-quality` เพราะ temp default นอก workspace ถูก sandbox ปฏิเสธ
- ไม่ได้แก้ `run-chaos.ps1`, `run-mql5-tests.ps1`, `run-soak.ps1`

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| market-wide threshold ในชุดทดสอบน้อยกว่า 6 symbol | หายพร้อมกัน >=4 ใน 6 symbol | production ยังใช้ 4 เมื่อมี >=4 symbol; ถ้า dataset มี 2-3 symbol ใช้ครบทุก symbol เป็น market-wide | ทำให้ unit test synthetic พิสูจน์ behavior ได้โดยไม่ต้องสร้าง 6 symbol หนักทุกเคส |
| input ว่าง | edge บอก symbol ไม่มีข้อมูลไม่ใช่ FAIL; user ย้ำว่าห้าม gate ผ่านเมื่อไม่มีข้อมูล | `analyze_symbol(..., [])` รายงาน `no_data` ไม่ fail แต่ `DatasetReport.passed_threshold` เป็น false เมื่อไม่มี data เลย และ CLI `--all` ที่หา data ไม่เจอ abort | แยก "symbol ยังไม่มีข้อมูล" ออกจาก "gate ไม่มีอะไรให้ตรวจแต่เขียว" |

### Test
- `python tools/task.py quality`
  - `collected 22 items`
  - `tests\test_quality.py ...................... [100%]`
  - `22 passed in 39.23s`
  - `[ OK ] quality`
  - `quality: OK (1 passed, 0 skipped)`
- `.venv\Scripts\python.exe -m ruff check research/quality tests/test_quality.py tools/task.py pyproject.toml`
  - `All checks passed!`
- `.venv\Scripts\python.exe -m mypy research/quality tests/test_quality.py tools/task.py`
  - `Success: no issues found in 7 source files`
- `rg -n "fillna|interpolate|ffill|bfill|to_parquet|except:" research/quality`
  - no matches

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่รองรับ parquet จริง เพราะ project ยังไม่มี parquet dependency และรอบนี้ห้ามเพิ่ม dependency; CLI ตอนนี้อ่าน synthetic-friendly CSV/JSONL ใต้ layout `data/bars/.../tf=M1`
- ไม่ได้รัน `python tools/task.py check` และไม่ได้รัน gate ใหญ่ ตามคำสั่ง "ห้ามรัน gate เอง"
- `git pull` ตอนเริ่มรันไม่ได้: `error: cannot open '.git/FETCH_HEAD': Permission denied`
- มี artifact `.pytest-tmp/` จาก pytest basetemp รอบแรกที่ untracked; พยายามลบด้วย `Remove-Item` หลัง verify path แล้วแต่ tool policy บล็อก คำสั่งถัดไปเปลี่ยนไปใช้ `.tmp-pytest-quality` ที่ถูก ignore แล้ว

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- วิธี classify gap: `research/quality/checks.py:157` ทำ market-wide ก่อนคำนวณ fail threshold เพื่อไม่ให้ holiday/shared outage กลายเป็น `GAP_SYMBOL_SPECIFIC`
- session profile threshold 0.90/0.10 ที่ `research/quality/profile.py:67`; unit test ต้องใช้ history ยาวพอ ไม่งั้น missing วันเดียวจะตก ambiguous ถูกต้องตามคณิตศาสตร์
- spike detector ที่ `research/quality/checks.py:258` ใช้ rolling median ของ absolute returns ไม่ใช้ stddev และไม่หารเมื่อ MAD เป็น 0
- CLI `--all` ที่ `research/quality/__main__.py:51` fail เมื่อไม่มีไฟล์ให้ตรวจเลย

### คำถามค้าง
- ไม่มี
