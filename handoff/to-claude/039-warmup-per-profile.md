---
id: 039
from: codex
ticket: SPEC-067
type: handoff
blocking: false
replies_to: "038"
---

## SPEC-067 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none - not committed per instruction

### ทำอะไรไปแล้ว
- `tests/soak/soak_sampler.py`
  - `WARMUP_SEC` เปลี่ยนเป็น `{"steady": 3600, "churn": 600}`
  - เพิ่ม `Profile = Literal["steady", "churn"]`
  - `_post_warmup_samples(samples, profile)` และ `analyse(samples, profile)` รับ profile explicit
  - เพิ่ม `PROFILE_DURATION_SEC` เพื่อให้ M5 วัด coverage ตาม duration ของ profile ไม่ใช่เดาจากข้อมูลที่เหลือ
  - เพิ่ม `write_verdict_artifact(samples_path, verdict_path, profile)` สำหรับเขียน verdict JSON ได้แม้ analyse เป็น environment error
- `tests/soak/test_soak_analysis.py`
  - update caller ทุกจุดเป็น `analyse(..., "steady"|"churn")`
  - เพิ่ม `test_warmup_differs_per_profile`
  - เพิ่ม `test_churn_60min_run_is_analysable` โดยใช้ 120 samples / 3572s ตามเคสจริง
- `tests/soak/test_memory_soak.py`
  - ส่ง profile เข้า `analyse()` และ artifact writer
  - เพิ่ม `try/finally` รอบ live churn collect เพื่อเขียน `ea-farm-soak-churn-verdict.json` ทุกครั้งที่ Python cleanup ทำงานได้
- `tools/run-soak.ps1`
  - ตั้ง `EA_FARM_SOAK_PROFILE=$Profile` ก่อนเรียก suite

### gate changes
- แก้ `tools/run-soak.ps1` 1 บรรทัดเพื่อส่ง profile จาก PowerShell เข้า test layer
- ไม่ได้เพิ่ม/ลด target gate และไม่ได้นับ skip เป็น pass
- เหตุผลที่เลือก artifact ที่ชั้น test: test layer เป็นจุดที่รู้ path ของ samples/verdict และครอบ lifecycle ของ `echo_server` + `live_terminal`; ส่วน `soak_sampler.write_verdict_artifact()` เป็น helper กลางเพื่อให้ CLI path ใช้ behavior เดียวกันได้

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| ไม่มี | - | - | ไม่มี |

### Test
- `.venv\Scripts\python.exe -m ruff check tests/soak/soak_sampler.py tests/soak/test_soak_analysis.py tests/soak/test_memory_soak.py`
  - `All checks passed!`
- `.venv\Scripts\python.exe -m mypy tests/soak/soak_sampler.py tests/soak/test_soak_analysis.py tests/soak/test_memory_soak.py`
  - `Success: no issues found in 3 source files`
- `.venv\Scripts\python.exe -m pytest tests/soak/test_soak_analysis.py tests/soak/test_memory_soak.py -q`
  - `13 passed, 1 skipped, 1 warning in 0.13s`
  - warning: pytest cache write denied at `D:\ea-farm\.pytest_cache\...`
- `python -m unittest tests.soak.test_soak_analysis -v`
  - `Ran 13 tests in 0.091s`
  - `OK`
- `python -m unittest tests.soak.test_memory_soak -v`
  - `Ran 1 test in 0.000s`
  - `OK (skipped=1)`

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ไม่ได้รัน gate ตามคำสั่ง
- ไม่ได้รัน churn จริงตามคำสั่ง
- ไม่ได้ observe หน่วยจริงของ `MQL5_MEMORY_USED` ในรอบนี้ เพราะไม่มี live churn run ในขอบเขตงานนี้
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- M5 ตอนนี้ใช้ expected samples จาก profile duration (`steady=24h`, `churn=2h`) หลังหัก warmup แทนการคิดจาก elapsed ของ sample ที่เหลือ เพื่อให้ steady 2h ตกว่า short run ได้
- Artifact fallback ใส่ `environment_error: true` และ `total_samples`; prefix `reason: "insufficient data: ..."` เฉพาะเคส no samples / fewer than two post-warmup samples ส่วน read/PID error ใช้ reason ตรง

### คำถามค้าง
- ไม่มี
