# AGENTS.md — คำสั่งสำหรับ Codex

> ไฟล์นี้คือกฎที่ Codex ต้องทำตามในทุก session ของโปรเจกต์นี้
> Claude เป็นคนดูแลไฟล์นี้ — Codex ห้ามแก้

## บทบาทของคุณ

คุณคือ **implementer เพียงคนเดียว** ของโปรเจกต์นี้ Claude ออกแบบและ review
โค้ดทุกบรรทัดในระบบมาจากคุณ ดังนั้นคุณภาพโค้ดคือความรับผิดชอบของคุณเต็มๆ

## ก่อนเขียนโค้ดทุกครั้ง

1. อ่าน `docs/02-contracts.md` — นี่คือกฎหมาย
2. อ่าน `docs/03-risk-spec.md` — ถ้างานเกี่ยว risk
3. อ่าน spec ของ ticket ใน `docs/specs/SPEC-NNN-*.md`
4. โพสต์ **Implementation note** (≤15 บรรทัด) ก่อน — ระบุจุดที่ spec กำกวมหรือทำไม่ได้
   ถ้าเจอจุดกำกวมสำคัญ → **หยุด รอ Claude แก้ spec**

## ห้ามทำเด็ดขาด

| # | ห้าม | เพราะ |
|---|------|-------|
| 1 | แก้ไฟล์ใน `contracts/schema/` | Claude เป็นเจ้าของแต่คนเดียว กัน drift |
| 2 | แก้ไฟล์ใน `contracts/gen/` ด้วยมือ | เป็น generated — แก้ generator แทน |
| 3 | ต่อกับ live account | demo เท่านั้นจนถึง Phase 7 |
| 4 | commit credential (MT5 login, API key, DB password) | ใช้ `.env` เท่านั้น |
| 5 | ปิด/ลด/comment out risk check เพื่อให้ test ผ่าน | test ผิด → แก้ test |
| 6 | รายงานว่าเสร็จถ้า test แดง | แปะ output จริงมาเสมอ |
| 7 | เพิ่ม dependency ใหม่โดยไม่บอกใน handoff report | |
| 8 | ใส่ trading logic ลงใน EA (นอกจาก SafeMode fallback) | logic อยู่ Python 100% |
| 9 | implement martingale / grid / averaging down / ไม่มี SL | non-goal ตัดสินแล้ว |
| 10 | `except:` เปล่า หรือกลืน error | risk path ต้อง fail-closed |
| 11 | merge เข้า `main` เอง | ต้องผ่าน Claude review |
| 12 | เปลี่ยน target-state protocol เป็น imperative order command | ข้อตัดสินใจสถาปัตยกรรมหลัก |
| 13 | `git add -A` หรือ `git add .` | Claude ทำงานใน working tree เดียวกัน จะกวาดไฟล์ของอีกฝ่ายเข้า commit — เกิดขึ้นจริงแล้ว ดู `05-collab-protocol.md` |
| 14 | commit/แก้ไฟล์ใน `docs/` `contracts/schema/` `AGENTS.md` `CLAUDE.md` `README.md` | Claude เป็นเจ้าของ — เห็นค้างใน `git status` ก็ปล่อยไว้ |
| 17 | แก้ `tools/**` **โดยไม่รายงาน** | `tools/**` แก้ได้ (ต้องเพิ่ม suite ทุก ticket) **แต่ต้องลงหัวข้อ "gate changes" ใน handoff แยกจากงานหลัก** — คุณแก้ gate แล้วรัน gate เอง Claude ต้องอ่าน diff ก่อนถึงจะเชื่อผลได้ |
| 18 | เพิ่มเป้าหมายใหม่เข้า gate ทั้งที่ยังรันไม่ได้ | เป้าที่ login ไม่ได้/ไม่มี history ทำให้ **gate แดงถาวร** → คนเลิกอ่าน gate · ต้องใส่ `Enabled = $false` + พิมพ์ `[SKIP]` ดังๆ และ **`[SKIP]` ห้ามนับเป็น pass** |
| 15 | commit ลง `main` | ใช้ `feat/SPEC-NNN-*` เท่านั้น |
| 16 | เขียนว่า "compile ผ่าน" ถ้าไม่ได้เห็น compiler output จริง | ไม่มี MetaEditor ในสภาพแวดล้อมของคุณ — เขียนว่า "รอ compile gate" |

**git ที่ใช้ได้:**
```bash
git add mt5-ea brain tests research ops contracts/gen   # ระบุ path เสมอ
git branch --show-current                                # เช็คก่อน commit ทุกครั้ง
```

## กฎการเขียนโค้ด

### MQL5
- ห้าม block ใน `OnTick` เกิน 50ms — socket read ต้อง non-blocking (`SocketIsReadable()` ก่อน)
- ⚠️ **แก้ 2026-07-27:** เดิมเขียนว่า "ใช้ `TimeCurrent()` ตัดสินใจ" — **ใช้ไม่ได้แล้ว**
  `TimeCurrent()` ค้างตอนตลาดปิด (ไม่มี tick) และเป็นเวลา **broker-local ไม่ใช่ UTC**
  → เรียกเวลาผ่าน `CBrokerTime` ตัวเดียวเท่านั้น ([SPEC-063](docs/specs/SPEC-063-broker-time.md))
  · `grep TimeGMT()\|TimeTradeServer()\|TimeLocal()\|TimeCurrent()` ต้องเจอเฉพาะใน `BrokerTime.mqh`
- `iClose(sym,tf,0)` = bar ปัจจุบัน **ยังไม่ปิด** — ใช้ index 1 ขึ้นไปสำหรับ signal
- เทียบราคา/lot ด้วย tolerance เสมอ: `MathAbs(a-b) < point/2` ห้าม `==`
- ปัด lot ด้วย `volume_step` เสมอ: `MathFloor(lot/step)*step`
- ตรวจ `retcode` ทุกครั้งหลัง `OrderSend` — ห้ามสมมติว่าสำเร็จ
- `OnTimer` ทุก 1s สำหรับงานที่ต้องรันแม้ตลาดปิด (kill file, heartbeat, halt check)
- ทุก order ต้องมี `magic` ประจำ strategy และ `comment` ที่มี `intent_id` ย่อ

### Python
- Python 3.12, type hints ครบ, `mypy --strict` ผ่าน
- pydantic v2 สำหรับ validate ทุก message ที่เข้าจากภายนอก
- asyncio — ห้าม blocking call ใน event loop (DB ใช้ asyncpg, HTTP ใช้ httpx)
- ทุก I/O ต้องมี timeout ชัดเจน
- Structured logging (JSON) ทุก log ที่เกี่ยว decision ต้องมี `intent_id`
- ห้าม `float` เปรียบเทียบตรงๆ กับเงิน/lot
- Risk path: error → block ไม่ใช่ผ่าน (fail-closed)

### Test
- ทุก risk rule (R1–R17, P1–P11) ต้องมี test เฉพาะของตัวเอง อ้าง rule id ในชื่อ test
- ทดสอบ *พฤติกรรม* ไม่ใช่ internal — test ที่ mock ทุกอย่างไม่นับ
- ต้องมี test เคสร้าย: เน็ตหลุด, ส่งซ้ำ, ข้อมูลเพี้ยน, NaN, ค่าติดลบ, timeout
- Round-trip test สำหรับทุก message type (py→mql5→py)
- Property test สำหรับ lot sizing และ reconciliation logic

## Handoff Report

จบทุก ticket ต้องส่งตามแบบฟอร์มใน `docs/05-collab-protocol.md`
สำคัญที่สุด 2 ช่อง: **"เบี่ยงเบนจาก spec"** และ **"จุดที่อยากให้ Claude ดูเป็นพิเศษ"**
ห้ามเว้นว่าง — ถ้าไม่มีให้เขียนว่า "ไม่มี"

## เมื่อไม่เห็นด้วยกับ Claude

- อธิบายเหตุผลเชิงเทคนิค เสนอทางเลือกที่ทำได้
- **วิธีชนะข้อโต้แย้ง = เขียน failing test ที่แสดงปัญหา** ไม่ใช่เถียงด้วยคำพูด
- เรื่อง risk: ฝ่าย conservative ชนะโดยปริยาย จนมีหลักฐานตรงกันข้าม

## Commit / Branch

```
branch:  feat/SPEC-NNN-<slug>   หรือ  fix/SPEC-NNN-<slug>
commit:  SPEC-NNN: <what changed in one line>

           <why, ถ้าไม่ชัดจาก diff>
```
