---
id: 085
from: codex
ticket: SPEC-010
type: handoff
blocking: false
replies_to: "084"
---

## SPEC-010 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** ไม่ได้ commit ตามคำสั่ง

### ทำอะไรไปแล้ว

- แก้ `tests/chaos/live_mt5_harness.py`
  - `.set` และ `.ini` ยังประกอบด้วย CRLF ตามเดิม แต่ `Path.write_text(..., newline="")` เพื่อไม่ให้ Windows text mode แปลง `\n` ซ้ำเป็น `\r\r\n`
  - ไล่ทั้งไฟล์แล้ว จุดที่เขียน startup `.set`/`.ini` อยู่ใน `write_startup_files()` จุดเดียว
- เพิ่ม sanitize/validate ฝั่ง EA
  - `mt5-ea/Include/Farm/Json.mqh`: เพิ่ม `FarmSanitizeInputString()` และ `FarmIsValidStrategyId()`
  - `mt5-ea/Experts/FarmExecutor.mq5`: trim `InpBrainHost`, `InpBrainToken`, `InpStrategyId` ใน `OnInit` ก่อนใช้ทั้งหมด; host/token ว่างหลัง trim = `INIT_FAILED`; strategy_id ไม่ตรง `^[a-z0-9_]{1,32}$` หลัง trim = log fatal + `INIT_FAILED`
  - `mt5-ea/Include/Farm/Wire.mqh`: `ConfigureRuntime()` เก็บ strategy_id ที่ sanitize แล้ว
  - `mt5-ea/Include/Farm/StateReporter.mqh`: `Init()` sanitize strategy_id ซ้ำที่จุดสร้าง HELLO payload และ fail ถ้ายัง invalid
- เพิ่ม regression tests
  - `tests/chaos/test_state_reporter.py::test_live_harness_set_file_does_not_double_crlf` ตรวจ bytes จริงของ `.set` ว่าไม่มี `\r\r`
  - `tests/mql5/TestStateReporter.mq5::test_input_control_chars_trimmed_before_use` ตรวจ input ที่มี `\r\n\t ` ถูก trim ก่อนใช้และ strategy_id ผ่าน validator
- ตรวจ event log ที่อ่านได้ใน `%TEMP%`
  - พบ `payload_invalid` เฉพาะ `type=HELLO`
  - error เป็น `strategy_id` pattern mismatch จาก `input_value='trend_v1\\r'`
  - ไม่พบ `payload_invalid` ของ BAR/STATE/HEARTBEAT/อื่น ๆ ในไฟล์ `ea-farm*.jsonl` ที่อ่านได้

### gate changes

- แก้ `tools/run-mql5-tests.ps1`
  - จุดเขียน test `.set` เปลี่ยนจาก `-join "\`r\`n" | Out-File -Encoding ascii` เป็น `[IO.File]::WriteAllText(..., [Text.Encoding]::ASCII)` เพื่อคุม newline bytes ไม่ผ่าน text pipeline
  - จุดเขียน tester `.ini` เปลี่ยนเป็น `[IO.File]::WriteAllText(..., [Text.Encoding]::ASCII)` เช่นกัน
  - เพิ่ม `test_input_control_chars_trimmed_before_use` เข้า required `ran_names` ของ `TestStateReporter`

### เบี่ยงเบนจาก spec

| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| gate/compile | เป้าหมายสุดท้ายต้อง fast chaos/MQL5/check เขียว | ไม่ได้รัน gate และไม่ได้ compile | คำสั่งรอบนี้ห้าม Codex รัน gate; ยังไม่เห็น compiler output จริง |

### Test

- `python -m pytest tests/chaos/test_state_reporter.py::test_live_harness_set_file_does_not_double_crlf -q`
  - รอบแรกใช้ `python` default: fail เพราะ `No module named pytest`
  - รอบสองใช้ `Get-GatePython` แต่ pytest default temp/cache ติด permission ที่ `C:\Users\User\AppData\Local\Temp\pytest-of-User`
  - รอบที่ผ่าน:
    ```text
    .                                                                        [100%]
    1 passed in 0.04s
    ```
  - command ที่ผ่าน: `. .\tools\python-gate-env.ps1; $py = Get-GatePython -Repo (Get-Location).Path; & $py -m pytest tests/chaos/test_state_reporter.py::test_live_harness_set_file_does_not_double_crlf -q -p no:cacheprovider --basetemp .pytest-tmp\crlf-set`
- `git diff --check -- <touched files>`:
  ```text
  warning: in the working copy of 'tools/run-mql5-tests.ps1', LF will be replaced by CRLF the next time Git touches it
  ```
  exit code 0
- ไม่ได้รัน fast chaos / MQL5 gate / check ตามคำสั่ง
- ยังไม่ได้คอมไพล์ MQL5 — รอ compile gate

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค

- ยังไม่ได้พิสูจน์ด้วย live fast chaos หลังแก้ เพราะห้ามรัน gate
- ยังไม่ได้เห็น MQL5 compiler output จริง
- `.pytest-tmp/` เป็น untracked อยู่ก่อนแล้ว; ผมสร้าง basetemp ย่อย `.pytest-tmp\crlf-set` ระหว่าง test และพยายามลบเฉพาะ subdir นั้น แต่ command recursive delete ถูก policy block จึงไม่ได้ทำ cleanup ต่อ

### จุดที่อยากให้ Claude ดูเป็นพิเศษ

- `FarmStringTrim()` ตัดทุก char `<= ' '` อยู่แล้ว จึงครอบคลุม `\r`, `\n`, `\t`, space; helper ใหม่เป็น wrapper เพื่อสื่อ intent ว่านี่คือ input sanitization ไม่ใช่ JSON parsing
- `StateReporter.Init()` guard ซ้ำเป็น defense-in-depth ที่จุดสร้าง HELLO payload; ถ้า caller อื่นข้าม `FarmExecutor.OnInit` จะไม่ส่ง strategy_id ผิด schema ออกไปเงียบ ๆ
- `tools/run-mql5-tests.ps1` gate diff: เปลี่ยน writer เป็น `.NET WriteAllText` เพื่อคุม newline bytes โดยตรง

### คำถามค้าง

ไม่มี
