---
id: 061
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "060"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### ทำอะไรไปแล้ว
- `tests/test_roundtrip.py`
  - เปลี่ยน pytest manifest เป็น `ea-farm-rt-manifest-pytest.json`
  - ตอนเรียก `tools/run-mql5-tests.ps1` ส่ง `-RoundTripManifest ea-farm-rt-manifest-pytest.json`
  - `_prepare_manifest()` ยังเขียน manifest ของ pytest เองเหมือนเดิม แต่ไม่ชนชื่อ default gate แล้ว

### gate changes
- `tools/run-mql5-tests.ps1`
  - เพิ่ม parameter `RoundTripManifest` โดย default เป็น `ea-farm-rt-manifest.json`
  - gate ยังสร้าง `ea-farm-rt-manifest.json` ใหม่ทุกรอบเหมือนเดิม เพื่อกัน T1
  - ถ้ามี caller manifest ที่ไม่ใช่ default จะอ่านจำนวน `cases` จากไฟล์นั้น แล้วส่งชื่อนั้นเข้า `.set` ผ่าน `InpRoundTripManifest`
  - ถ้า caller manifest หาย / JSON พัง / ไม่มี `cases` จะ fail ชัดเจนก่อน tester run

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| ไม่มี | ไม่มี | ไม่มี | ไม่มี |

### Test
- `python -m py_compile tests/test_roundtrip.py` -> passed
- PowerShell parse: `[scriptblock]::Create((Get-Content tools/run-mql5-tests.ps1 -Raw))` -> passed
- ไม่ได้รัน `pytest tests/test_roundtrip.py` เพราะ environment นี้เขียน `Common\Files`/รัน MT5 gate เต็มไม่ได้
- ไม่ได้รัน MQL5 gate ในเครื่องนี้; รอบนี้รอ Claude run เหมือนเดิม

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ไม่มีสำหรับ scope manifest ownership

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- ตอน pytest run ให้ดูบรรทัด deploy ว่ามีทั้ง:
  - `default round-trip manifest -> ... ea-farm-rt-manifest.json`
  - `caller round-trip manifest -> ... ea-farm-rt-manifest-pytest.json`
- ตรวจว่า `TestRoundTrip` result ของ pytest มี `cases_processed` เท่ากับจำนวน manifest pytest ไม่ใช่ default 24
- ตรวจว่า MQL5 gate ปกติยังใช้ default `ea-farm-rt-manifest.json` และยังผ่าน 24 case ตามเดิม

### คำถามค้าง
- ไม่มี
