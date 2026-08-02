---
id: 057
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "056"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** not committed

### ทำอะไรไปแล้ว
- เพิ่ม `tests/mql5/TestRoundTrip.mq5`
  - EA harness อ่าน `ea-farm-rt-manifest.json` จาก `Common\Files` ด้วย `FILE_BIN | FILE_COMMON`
  - อ่าน input UTF-8 raw bytes, parse envelope, dispatch เข้า generated `FarmParseX/FarmSerializeX` จริงทุก message type, เขียน output UTF-8 no BOM
  - result JSON มี `cases_processed`, `case_failures`, `ran_names`, `git_sha`
  - malformed input ถูกบันทึกเป็น case failure ไม่ crash suite
- เพิ่ม `tests/test_roundtrip.py`
  - 17 pytest ตาม list ของ SPEC-005 ครบ
  - สร้าง canonical JSON ด้วย generated Python models (`FarmEnvelope` + `PAYLOAD_MODELS`) และ `exclude_unset=True` เพื่อรักษา absent/null/value
  - เขียน manifest/input/output ผ่าน `Common\Files`
  - รัน MQL5 ของจริงผ่าน `tools/run-mql5-tests.ps1` ใน fixture session
  - เทียบ canonical A2 == A และรายงาน diff เป็น path + before/after
  - ตรวจ no scientific notation, large int64, Thai UTF-8, negative zero, stale output cleanup, git_sha, deterministic two runs
  - ทำ invariant จาก comment ของ SPEC-004 ใน Python helper: BAR OHLC/spread, STATE owned_net/ticket_count/internal hedge, EXEC_REPORT result-volume-ticket, RISK_DIRECTIVE mode/expires, ERROR severity/fatal

### gate changes
- แก้ `tools/run-mql5-tests.ps1`
  - เพิ่ม suite `TestRoundTrip`
  - เพิ่ม required MQL test name `test_manifest_roundtrip_cases`
  - เพิ่ม set input `InpRoundTripManifest=ea-farm-rt-manifest.json`
  - ถ้าไม่มี pytest manifest อยู่ก่อน จะสร้าง default manifest จาก 24 fixture valid/min เพื่อให้ gate ที่เรียกตรงไม่ fail เพราะ manifest หาย
- ไม่ได้ลด/ข้าม check เดิม และไม่ได้นับ `[SKIP]` เป็น pass

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| business invariant | SPEC-005 non-goal บอกไม่ทดสอบ invariant | ทำ invariant ใน pytest helper | คำสั่ง ticket รอบนี้ override ชัดว่า comment จาก SPEC-004 ต้องทำจริง |
| direct gate run | Python ต้องเขียน manifest ก่อน Strategy Tester | runner สร้าง default manifest ถ้าไม่มี | เพื่อไม่ให้ `mql5-gate` ที่เรียกตรงพังเพราะไม่มี manifest; pytest manifest ยังไม่ถูก overwrite |

### Test
- `python -m py_compile tests/test_roundtrip.py` -> pass
- `.venv\Scripts\python.exe -m ruff check tests/test_roundtrip.py` -> `All checks passed!`
- `.venv\Scripts\python.exe -m mypy` -> `Success: no issues found in 29 source files`
- `.venv\Scripts\python.exe -m pytest --collect-only -q tests/test_roundtrip.py` -> `17 tests collected`
- non-MQL pytest:
  - command: `.venv\Scripts\python.exe -m pytest -m "not slow and not live_terminal and not mql5" -o cache_dir=D:\ea-farm\.tmp-pytest-cache`
  - result: `67 passed, 8 skipped, 17 deselected`
- initial non-MQL pytest without temp override failed with `PermissionError: C:\Users\User\AppData\Local\Temp\pytest-of-User`; reran with `TMP/TEMP=D:\ea-farm\.tmp-pytest` and it passed
- ไม่ได้รัน `tools/run-mql5-tests.ps1` / mql5 gate ตามคำสั่ง "ห้ามรัน gate เอง"
- ยังไม่ได้เห็น MetaEditor compiler output; รอ compile gate

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้รัน MQL5 compile/test จริง เพราะถูกสั่งห้ามรัน gate
- `git pull` ตอนเริ่ม session ล้มเหลว: `error: cannot open '.git/FETCH_HEAD': Permission denied`
- มี working tree/staging เดิมจากงานก่อนอยู่แล้ว ผมไม่ revert/แตะไฟล์เหล่านั้น

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- Unknown field tests: generated MQL5 ปัจจุบัน `FarmParsePayloadJson()` serialize จาก JSON tree (`doc.Root().ToJson()`) จึงมีโอกาส preserve unknown payload/nested fields แทน drop ตาม SPEC-005 §4.4. Test ใหม่จะจับและรายงาน path ชัดเจนถ้าเกิดขึ้น
- `TestRoundTrip.mq5` compile syntax โดยเฉพาะ pointer/class access และ dynamic string arrays
- `tools/run-mql5-tests.ps1` default manifest block ว่าควรอยู่ใน gate หรือให้ pytest เป็นผู้สร้าง manifest เท่านั้น
- Invariant helper ใน `tests/test_roundtrip.py` ครอบคลุม comment หลัก แต่ยังไม่ได้ implement invariant ที่ต้องอาศัย external context เช่น INTENT SL อยู่ฝั่งถูกของราคาปัจจุบัน/stops_level

### คำถามค้าง
- ถ้า MQL5 preserve unknown payload/nested field ตามที่คาดไว้ ให้แก้ใน SPEC-005 รอบนี้โดยแตะ `tools/codegen.py` เพื่อ generate strip-known-fields serializer หรือแยกเป็น ticket แก้ SPEC-004 generator?
