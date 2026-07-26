# 06 — Gap Audit

**วันที่ตรวจ:** 2026-07-26 · **ตรวจโดย:** Claude · **ขอบเขต:** เอกสารแผนทั้งหมด ณ commit `236b58b`
**วิธีตรวจ:** grep หาหัวข้อที่ควรมีแต่ไม่มี + ไล่ dependency ของแต่ละ component ว่าได้ input จากไหน

สรุป: เจอ **12 ช่องว่าง** · แก้ในเอกสารแล้ว 6 · ต้องมี spec ใหม่ 5 · ต้องให้เจ้าของโปรเจกต์ตัดสิน 3

---

## 🔴 ระดับ BLOCKER — ต้องจัดการก่อนเริ่มเขียนโค้ด

### G1 — ไม่มีใครป้อนราคาให้ brain สำหรับ symbol ที่ไม่มี EA เทรด ★ ช่องว่างสถาปัตยกรรม

**เจอจาก:** ไล่ dependency ของ P4 (correlation cap) ว่าเอาราคามาจากไหน → ไม่มีที่มา

EA ส่ง `BAR` มาแค่ symbol ที่ตัวเองเทรด แต่ P4 ต้องคำนวณ correlation matrix ของ
**ทุก** symbol และ RegimeService ต้องดูภาพรวมตลาด ถ้าฟาร์มเทรดแค่ EURUSD วันนี้
brain จะไม่มีข้อมูล GBPUSD เลย → P4 คำนวณไม่ได้ แต่ระบบจะไม่รู้ตัวว่าคำนวณไม่ได้
มันจะแค่ได้ correlation = 0 แล้วปล่อยผ่านทุก intent — **fail-open ในชั้น risk**

| | |
|---|---|
| **แก้แล้ว** | เพิ่ม component `collector` ใน `01-architecture.md` (MT5 read-only 1 ตัว + `MetaTrader5` pkg) |
| **ต้องทำ** | SPEC-060 MarketDataCollector · SPEC-061 stale-data guard (P10) ให้ fail-closed |
| **Phase** | ต้องเสร็จก่อน SPEC-026 (correlation) และ SPEC-041 (regime) |

### G2 — brain ตายแล้วไม่มีใครแจ้ง (alerting อยู่ใน brain เอง)

**เจอจาก:** grep `heartbeat` → เจอแต่ "brain ตรวจ EA" ไม่มี "ใครตรวจ brain"

Failure mode table เขียนว่า *"EA ตาย → brain alert"* แต่ทางกลับกันไม่มี
Telegram alerting เป็นโมดูลใน brain ถ้า brain ตาย = เงียบสนิท
นี่คือ failure mode ที่แย่ที่สุดเพราะเจ้าของนอนหลับคิดว่าปกติ

| | |
|---|---|
| **แก้แล้ว** | เพิ่ม `watchdog` ใน `01-architecture.md` + failure mode table |
| **ต้องทำ** | SPEC-062 Watchdog (process แยก **ห้าม** import brain / ต่อ DB / ใช้ venv เดียวกัน) |
| **Phase** | ต้องเสร็จก่อนจบ Phase 2 (ก่อนเงินจริง) |

### G3 — ใครคอมไพล์และรัน MQL5 test? CI ทำไม่ได้ ⚠️ **ต้องให้เจ้าของตัดสิน**

**เจอจาก:** CI spec = `ruff, mypy, pytest, codegen-diff` — ไม่มี MQL5 เลย
แต่ `AGENTS.md` เขียนว่า *"ห้ามรายงานเสร็จถ้า test แดง"*

MQL5 ต้องมี MetaEditor + MT5 terminal บน Windows ถึงจะ compile และรันได้
GitHub Actions รันไม่ได้ (ไม่มี MT5) และ **Codex ก็อาจไม่มี MT5 ให้ใช้**

ถ้า Codex ไม่มี → MQL5 ทั้งหมด (ซึ่งคือ EA, risk guard, order router = ส่วนที่สำคัญที่สุด)
จะถูกเขียนแบบไม่เคยคอมไพล์เลย และไม่มีใครจับ regression ได้อัตโนมัติ
**นี่เปลี่ยน workflow ที่วางไว้ใน `05-collab-protocol.md` อย่างมีนัยสำคัญ**

| | |
|---|---|
| **ต้องตัดสิน** | ดูคำถาม Q1 ท้ายเอกสาร |
| **ผลถ้าต้องพึ่งคน** | เพิ่มขั้น "human compile & test gate" ใน flow · Codex ต้องเขียน test ที่ output อ่านง่ายและ copy กลับมาได้ |

---

## 🟠 ระดับ HIGH — แก้ก่อนเงินจริง (จบ Phase 2)

### G4 — Runbook อยู่ Phase 6 แต่เงินจริงเริ่มปลาย Phase 2 ← ลำดับผิดในแผนของผมเอง

Roadmap เขียนว่า *"ผ่าน Phase 2 = พร้อมขึ้น live ด้วยทุนเล็ก"* (สัปดาห์ที่ 5)
แต่ Runbook (SPEC-056) อยู่ Phase 6 (สัปดาห์ที่ 14) → มีเงินจริงเดินอยู่ 9 สัปดาห์
โดยไม่มีเอกสารบอกว่าต้องทำอะไรเมื่ออะไรพัง

| | |
|---|---|
| **แก้แล้ว** | ย้าย runbook ขั้นต้นเข้า Phase 2 (SPEC-030b) — ฉบับเต็มยังอยู่ Phase 6 |

### G5 — กฎ "SL ต้องอยู่ที่ broker" เคยเป็นแค่นัย ไม่เคยเขียนชัด

R9 เขียนว่า `require_sl` แต่ไม่ได้ระบุว่า SL ต้องเป็น **broker-side**
ถ้า Codex ตีความว่า "EA เฝ้าราคาแล้วปิดเองเมื่อถึงจุด" (virtual SL) ก็ผ่าน R9 ได้
แต่ virtual SL ทำงานเฉพาะเมื่อ EA รันอยู่ — VPS ดับ = position เปลือย ขาดทุนไม่จำกัด

| | |
|---|---|
| **แก้แล้ว** | เพิ่มกฎชัดใน `01-architecture.md` §Failure Mode + เคส "VPS ตายทั้งเครื่อง" |
| **เพิ่ม** | ถ้าเปิดสำเร็จแต่ตั้ง SL ไม่สำเร็จ 3 ครั้ง → **ปิด position ทิ้ง** ไม่ปล่อยเปลือย |

### G6 — เวลา broker / DST ไม่มีแหล่งความจริงเดียว

**เจอจาก:** grep `DST` → เจอ 2 ที่ เป็นแค่คำเตือน ไม่มี spec

โบรกเกอร์ส่วนใหญ่ใช้ GMT+2/+3 และ **เลื่อนตาม DST ของยุโรป/อเมริกา ไม่ตรงกัน**
กระทบ: R6 (เส้นแบ่งวันใหม่), R11 (trading hours), R12 (Friday close),
bar timestamp alignment, และ **backtest/live parity** (SPEC-033) ซึ่งจะเพี้ยนเงียบๆ
ปีละ 4 ครั้งถ้าไม่จัดการ

| | |
|---|---|
| **ต้องทำ** | SPEC-063 BrokerTime — เขียนเป็น module เดียวที่ทุกที่ต้องเรียก ห้ามคำนวณเวลาเอง |
| **Phase** | ต้องเสร็จก่อน SPEC-021 (daily loss) |

---

## 🟡 ระดับ MEDIUM — แก้ก่อน Phase 3

### G7 — ชื่อ symbol ต่างกันข้ามโบรกเกอร์ ไม่มี canonical mapping

**เจอจาก:** grep หา suffix handling → ไม่มีเลย

โบรกเกอร์ตั้งชื่อไม่เหมือนกัน: `EURUSD` / `EURUSD.a` / `EURUSDm` / `EURUSD_raw`
ตาราง `bars` มี PK `(broker, symbol, timeframe, bar_time)` ซึ่งแยกตามโบรกเกอร์ถูกแล้ว
แต่ **correlation (P4) และ currency exposure (P3) ต้อง join ข้ามโบรกเกอร์**
ถ้าไม่มี canonical name จะมองว่า `EURUSD.a` กับ `EURUSDm` เป็นสองสินทรัพย์
→ exposure ต่อ EUR ถูกนับแยก → **ทะลุ limit จริงโดยที่ตัวเลขดูปลอดภัย**

| | |
|---|---|
| **ต้องทำ** | SPEC-064 SymbolRegistry — map `(broker, raw_symbol) → canonical` + base/quote currency + asset class |
| **Phase** | ต้องเสร็จก่อน SPEC-024 (currency decomposition) |

### G8 — Swap / triple-swap วันพุธ ไม่ได้พูดถึง

Backtest spec บอกว่าจำลอง swap แต่ไม่ระบุว่า FX คิด swap 3 เท่าในวันพุธ
(เพราะ settlement T+2 ข้ามสุดสัปดาห์) ถ้ากลยุทธ์ถือข้ามคืน ต้นทุนนี้เปลี่ยนผลลัพธ์จริง
และถ้า backtest ไม่คิด live จะแย่กว่า backtest แบบหาสาเหตุไม่เจอ

| | |
|---|---|
| **ต้องทำ** | เพิ่มใน SPEC-032 acceptance: triple-swap Wednesday + swap จริงจากโบรกเกอร์ ไม่ใช่ค่าคงที่ |

### G9 — MQL5 ไม่มี test framework จริง → ไม่มี regression net

`tests/mql5/TestWire.mq5` เป็น script ที่ print assertion — ใช้ได้ แต่รันด้วยมือ
ถ้าไม่มีใครรันทุกครั้ง regression จะหลุด เกี่ยวกับ G3 โดยตรง

| | |
|---|---|
| **ต้องทำ** | SPEC-065 MQL5 test harness — script ตัวเดียวรันทุก test suite แล้ว **เขียนผลเป็น JSON ลงไฟล์** ให้ Python อ่านและ fail CI ได้ (CI ตรวจไฟล์ผลลัพธ์ ไม่ได้รัน MT5 เอง) |

---

## 🟢 ระดับ LOW — จดไว้ ไม่ต้องรีบ

| # | เรื่อง | ทำอะไร |
|---|-------|--------|
| G10 | `.env` ไม่เหมาะกับ multi-VPS (Phase 6) | จดใน SPEC-054 ค่อยตัดสินทีหลัง |
| G11 | ไม่มี `docs/reviews/` และยังไม่มีใคร review spec ของ Claude เอง | สร้าง dir ตอน review แรก · spec ของผมให้ Codex ตั้งคำถามผ่าน implementation note (มีในโปรโตคอลแล้ว) |
| G12 | MT5 history ถูกโบรกเกอร์แก้ย้อนหลังได้ → backtest data ไม่ immutable | SPEC-033 parity test จับได้บางส่วน · เพิ่ม data snapshot hash ใน SPEC-007 |

---

## ❓ คำถามที่ต้องให้เจ้าของโปรเจกต์ตัดสิน

### Q1 — Codex มี MT5 + MetaEditor ให้ใช้ไหม? (G3) ⚠️ **บล็อกการวางแผน workflow**

- **ถ้ามี** → workflow เดิมใช้ได้ Codex compile + รัน test เองแล้วแปะผล
- **ถ้าไม่มี** → ต้องเพิ่มขั้น human gate: Codex เขียน → เจ้าของ (หรือ Claude Code ในเครื่องนี้)
  compile + รัน + ส่งผลกลับ → Codex แก้ ต้องปรับ `05-collab-protocol.md` และคาดว่ารอบ
  แก้ MQL5 จะช้ากว่า Python 2–3 เท่า

### Q2 — R12 `friday_close_before` = ปิดทุกอย่างก่อนตลาดปิดศุกร์ เอาไหม?

default ที่ผมตั้งไว้คือปิดหมด ซึ่ง**ฆ่ากลยุทธ์ swing ที่ถือหลายวันทิ้งทั้งหมด**
- ปิด = ไม่มี weekend gap risk แต่จ่าย spread เข้า-ออกทุกสัปดาห์ และตัดกำไรที่วิ่งอยู่
- ไม่ปิด = ถือข้ามได้ แต่รับ gap ที่ SL ไม่ช่วย (ราคาเปิดกระโดดข้าม SL)

ถ้ายังไม่แน่ใจ: เก็บ default = ปิด (conservative) แล้วทำเป็น per-strategy config ใน Phase 5

### Q3 — D2 โบรกเกอร์ · D4 symbol/timeframe · D5 จำนวนบัญชี/ทุน

ยังค้างจากรอบก่อน ไม่บล็อก 3 ticket แรก แต่:
- **D4 ต้องรู้ก่อน SPEC-007** (ingest ต้องรู้ว่าดึงคู่ไหน) — ใกล้ที่สุด
- **D2 ต้องรู้ก่อน SPEC-032** (spread/swap model)
- **D5 ต้องรู้ก่อน SPEC-025** (threshold P1–P6)
