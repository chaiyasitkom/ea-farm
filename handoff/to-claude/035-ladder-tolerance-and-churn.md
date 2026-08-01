---
id: 035
from: codex
ticket: SPEC-067
type: handoff
blocking: false
replies_to: "034"
---

## SPEC-067 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none (per instruction)

### ข้อ 1: backoff ladder tolerance

- แก้ `tests/chaos/test_wire_resilience.py:305` ให้ `_wait_for_backoff_ladder_diag()` เก็บ timeline diag ทั้ง `reconnect` และ `state` ไม่ใช่เฉพาะ `reconnect`
- แก้ `tests/chaos/test_wire_resilience.py:354` ให้ `_assert_backoff_waits_match_diag()` วัดเวลารอจริงจาก `ev=reconnect` ถึง `ev=state,to=CONNECTING` ถัดไป
- คง assert ลำดับ `backoff_sec == [1, 2, 4, 8, 16, 30, 30]` ที่ `tests/chaos/test_wire_resilience.py:431`
- ยังพิมพ์หลักฐานตอนผ่านที่ `tests/chaos/test_wire_resilience.py:439` โดยเพิ่ม `waits_sec=...` และคง `reconnect_gaps_sec=...` ไว้ดู diagnostic แต่ไม่ใช้ตัดสิน

### ข้อ 2: SPEC-067 churn soak harness

- เพิ่ม `tests/soak/soak_sampler.py:30` `Sample`, `tests/soak/soak_sampler.py:42` `Verdict`
- เพิ่ม `tests/soak/soak_sampler.py:117` `analyse()` เป็น pure function ตัดสินด้วย slope/growth/gap หลัง warmup
- เพิ่ม `tests/soak/soak_sampler.py:188` `collect()` ใช้ `psutil`; ถ้าไม่มี psutil หรือไม่มี private bytes/handle metrics จะ raise env failure และ CLI ออก exit 3
- เพิ่ม `tests/soak/test_soak_analysis.py:61` ถึง `:148` ครอบคลุม 10 เคสตาม SPEC-067 ยง7.1 + เพิ่ม loader JSONL 1 เคส
- เพิ่ม `tests/soak/test_memory_soak.py:23` profile churn 2h แบบ `EA_FARM_LIVE_MT5` + `EA_FARM_LIVE_MT5_SLOW` gated; default skip จึงไม่เริ่ม churn เอง
- เพิ่ม `brain/gateway/echo_server.py:55` / `:226` option `--close-every-sec` สำหรับ server churn ตัด connection ทุก 30s
- แก้ `tests/chaos/live_mt5_harness.py:136` ให้ EA log reader อ่านข้าม midnight rollover ได้

### gate changes

- เพิ่ม `tools/run-soak.ps1` สำหรับ `-Profile churn` และ `-Profile steady`
- `-Profile churn` ตั้ง `EA_FARM_LIVE_MT5=1`, `EA_FARM_LIVE_MT5_SLOW=1` แล้วเรียก `tests.soak.test_memory_soak.MemorySoakTests.test_soak_churn_2h_no_handle_leak`
- preflight `psutil` ไม่พร้อม -> exit 3 พร้อมข้อความติดตั้ง
- `-Profile steady` ยัง exit 3 โดยตั้งใจในรอบนี้ เพื่อไม่เริ่ม/เปิดทาง steady 24 ชม. ก่อนคำสั่งแยก

### เบี่ยงเบนจาก spec

| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| `Wire.mqh` mem diag | เพิ่ม `{"ev":"mem"...}` ทุก 60s | ยังไม่ได้แตะ EA | คำสั่งรอบนี้ให้ทำเฉพาะส่วนที่ไม่ต้องรัน 24 ชม. และระบุไฟล์ soak/tests/tool เป็นหลัก |
| steady 24h | `tools/run-soak.ps1 -Profile steady` รัน steady | exit 3 พร้อมข้อความว่ายังไม่ wired | ผู้สั่งห้ามเริ่ม profile steady 24 ชม. ในรอบนี้ |
| MQL5_MEMORY_USED unit | handoff ต้องบันทึกหน่วยจริงที่สังเกตได้ | ยังไม่ได้วัดจริง | ไม่ได้รัน MT5 soak/churn ในรอบนี้ตามคำสั่ง |

### Test

- `.venv\Scripts\python.exe -m unittest tests.soak.test_soak_analysis tests.soak.test_memory_soak tests.chaos.test_wire_resilience.WireResilienceTests`

```text
...........s........
----------------------------------------------------------------------
Ran 20 tests in 1.882s

OK (skipped=1)
```

- `.venv\Scripts\python.exe -m mypy tests/soak tests/chaos/live_mt5_harness.py brain/gateway/echo_server.py`

```text
Success: no issues found in 6 source files
```

- `.venv\Scripts\python.exe -m ruff check tests/soak tests/chaos/live_mt5_harness.py brain/gateway/echo_server.py tests/chaos/test_wire_resilience.py`

```text
All checks passed!
```

- PowerShell parse-only:

```text
run-soak.ps1 parse ok
```

ไม่ได้รัน gate, ไม่ได้รัน churn 2 ชม., ไม่ได้รัน steady 24 ชม.

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค

- ยังไม่ได้เพิ่ม `ev=mem` ฝั่ง EA จนกว่าจะมีคำสั่งให้แตะ `Wire.mqh`
- ยังไม่ได้เก็บ artifact/verdict จาก churn จริง เพราะผู้สั่งจะรันเอง
- `git pull` ตอนเริ่ม session ล้มด้วย `error: cannot open '.git/FETCH_HEAD': Permission denied`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ

- สูตร M5 ใน `analyse()` ใช้ sample coverage จาก post-warmup span และ flag gap เมื่อ interval เกิน `SAMPLE_INTERVAL_SEC * 1.5`; conservative ต่อ sleep gap และไม่ interpolate
- ข้อ 1 เปลี่ยนตัววัดเป็น reconnect->CONNECTING แล้ว แต่ยังแสดง reconnect-to-reconnect gap เพื่อช่วย diagnosis
- `tools/run-soak.ps1 -Profile steady` ถูกปิดด้วย exit 3 ชั่วคราวตามคำสั่งรอบนี้ ไม่ให้นับเป็น pass

### คำถามค้าง

- ไม่มี
