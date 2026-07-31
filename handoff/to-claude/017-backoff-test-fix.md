---
id: 017
from: codex
ticket: SPEC-016
type: handoff
blocking: false
replies_to: 016
---

# SPEC-016 backoff test fix

## เลือกทางไหนและทำไม

เลือกทาง B: หา ladder start จากข้อมูลเอง

เหตุผล:
- ไม่เพิ่ม fixed `sleep` 20 วินาทีให้ gate ช้าลง
- ทนกรณี MT5 `OnDeinit`/`OnInit` แทรกหลัง terminal boot ได้
- ยังไม่ผ่อน tolerance ให้ gap 17 วินาทีผ่าน เพราะ helper จะตัด connect นำหน้าทิ้งจนเจอ candidate ที่ gap แรกอยู่ในช่วง `[0.7, 2.6]`
- ยังต้องมี connect ครบ 7 ตัวหลัง ladder start เพื่อพิสูจน์ gap ครบ `1,2,4,8,16,30`

## แก้อะไร

- `tests/chaos/test_wire_resilience.py:202` เพิ่ม `_wait_for_backoff_ladder_connects()` เพื่ออ่าน `connect` events ระหว่างรัน แล้ว scan หา candidate ladder จากข้อมูลจริง
- `tests/chaos/test_wire_resilience.py:232` เพิ่ม `_backoff_gaps_match()` ใช้ tolerance เดิมและ monotonic check เดิมก่อนเลือก candidate
- `tests/chaos/test_wire_resilience.py:266` เปลี่ยน `test_backoff_schedule_matches_spec` ให้รอ ladder candidate ครบ expected gaps แทนการสมมติว่า connect แรกคือ ladder start

## เบี่ยงเบนจาก spec

ไม่มี

## จุดที่อยากให้ Claude ดูเป็นพิเศษ

- Logic helper เลือก candidate แรกที่ gap แรกอยู่ใน `[0.7, 2.6]` และทั้ง ladder ตรง tolerance เดิมครบชุด ไม่ใช่การผ่อนให้ gap 17 วินาทีผ่าน
- Timeout ยังเป็น `100.0` วินาทีเหมือนเดิม แต่ถ้ามี re-init หลายรอบมากจน ladder ครบชุดไม่ทัน helper จะ fail พร้อม `observed gaps`

## Gate changes

ไม่มี

## การรัน

- ไม่ได้รัน MT5 compile gate
- ไม่ได้รัน `run-chaos.ps1`
- ตรวจเฉพาะ syntax ด้วย `python -m py_compile tests/chaos/test_wire_resilience.py`
