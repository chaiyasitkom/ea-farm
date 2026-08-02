---
id: 055
from: codex
ticket: SPEC-064
type: handoff
blocking: false
replies_to: "054"
---

## SPEC-064 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none (per instruction: no commit)

### ทำอะไรไปแล้ว
- แก้ `tests/mql5/TestFarmSymbols.mq5`
  - เปลี่ยน include จาก `<Farm/Json.mqh>` เป็น `<Farm/JsonCore.mqh>`
  - เหตุผล: test harness ใช้ `FarmJsonQuoteUtf8()` ตอนเขียน JSON result จึงต้อง include owner header โดยตรง
  - ลบ dependency ต่อ `FarmJsonQuote` helper เดิมแล้ว เพราะไฟล์นี้ไม่ได้ใช้ `FarmJsonQuote()`

### generator decision
- ไม่แก้ `tools/codegen.py` และไม่ regenerate `contracts/gen/mql5/FarmSymbols.mqh`
- เหตุผล: generated `FarmSymbols.mqh` ไม่เรียก `FarmJsonQuoteUtf8()` หรือ JSON helper ใด ๆ; compile error อยู่ใน `TestFarmSymbols.mq5` ที่เขียน result JSON เอง
- การเพิ่ม `<Farm/JsonCore.mqh>` เข้า generated `FarmSymbols.mqh` จะเป็น dependency ที่ไม่จำเป็นสำหรับ symbol lookup API

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| ไม่มี | ไม่มี | ไม่มี | ไม่มี |

### gate changes
- ไม่มีการแก้ `tools/**` รอบนี้

### Test
- ไม่ได้รัน MQL5 gate/compile ตามคำสั่ง
- static checks ที่รัน:
  - `rg -n "JsonCore|Json\.mqh|FarmJsonQuote\(" tests/mql5/TestFarmSymbols.mq5 contracts/gen/mql5/FarmSymbols.mqh tools/codegen.py`
    - พบ `tests/mql5/TestFarmSymbols.mq5:5:#include <Farm/JsonCore.mqh>`
    - ไม่พบ `Json.mqh` หรือ `FarmJsonQuote(` ใน `TestFarmSymbols.mq5`
  - `git diff --check -- tests/mql5/TestFarmSymbols.mq5`
    - exit 0

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- ยังไม่ได้เห็น compiler output รอบใหม่; รอ Claude รัน MQL5 gate ตาม protocol
- `git pull` ตอนเริ่ม session ล้มเหลวด้วย `cannot open '.git/FETCH_HEAD': Permission denied`

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- ยืนยัน compile gate ว่า `TestFarmSymbols` เหลือ 0 error 0 warning และรัน 7/7
- ยืนยันว่าไม่ต้องให้ generated `FarmSymbols.mqh` include `JsonCore.mqh` เพราะ header นี้ไม่มี JSON dependency

### คำถามค้าง
- ไม่มี
