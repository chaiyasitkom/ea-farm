# ADR-002 — โบรกเกอร์ · ชุด Symbol/Timeframe · ทุนต่อบัญชี · Friday Close

**สถานะ:** ACCEPTED (พร้อม 1 ข้อค้างที่ต้องตัดสินซ้ำ) · **วันที่:** 2026-07-27 · **ตัดสินโดย:** เจ้าของโปรเจกต์
**ปิดหนี้เทคนิค:** D2 · D4 · D5 (บางส่วน) · **ตอบ:** [gap-audit](../06-gap-audit.md) Q2, Q3
**กระทบ:** R1, R5, R10, R11, R12 · P3, P4 · SPEC-007, SPEC-008, SPEC-020, SPEC-025, SPEC-060, SPEC-063, SPEC-064

---

## 1. การตัดสิน

| # | หัวข้อ | ค่าที่ตัดสิน |
|---|--------|-------------|
| D2 | โบรกเกอร์ | **IUX Markets** (ยืนยันแล้ว — บัญชี `IUXMarkets-Demo`) |
| D4 | Symbol | **`EURUSD.iux` · `XAUUSD.iux` · `BTCUSD.iux`** |
| D4 | Timeframe | **M1 · M5 · M10 · M15 · M30 · H1 · H4** (7 ชั้น) |
| D5 | จำนวนบัญชี | **≥ 2** |
| D5 | ทุนต่อบัญชี | ≥ 10 USD → 🔴 **ดู §3 — ค่านี้ใช้ไม่ได้ ต้องตัดสินใหม่** |
| Q2 | R12 friday close | **เปิดใช้ — ยกเว้น `BTCUSD.iux`** |

### หลักฐาน D2 (ตรวจจาก terminal บนเครื่องนี้ 2026-07-27)

`%APPDATA%\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3\bases\IUXMarkets-Demo\`
มี 15 symbol ทั้งหมดลงท้าย `.iux` — ยืนยันว่า suffix เป็นของจริงไม่ใช่ค่าที่ตั้งเอง

### หลักฐาน history (สำคัญ — แก้ข้อมูลเดิมที่บันทึกผิด)

| symbol | ปีที่มี M1 base (`.hcc`) |
|--------|--------------------------|
| `EURUSD.iux` | **2016 – 2026** |
| `XAUUSD.iux` | **2016 – 2026** |
| `BTCUSD.iux` | **2018 – 2026** |

> ⚠️ [review compile-gate-02](../reviews/SPEC-001-compile-gate-02.md) §4 กับดัก #3 เขียนว่า
> "history มีแค่ 2025.01.01 – 2026.06.19" — **ผิด** นั่นคือช่วงที่ Strategy Tester
> มี cache พร้อมใช้ ณ ตอนนั้น ไม่ใช่ช่วงที่มีข้อมูลจริง
> ข้อกำหนด "ย้อนหลัง ≥ 5 ปี" ใน [roadmap](../04-roadmap.md) Phase 0 **ทำได้ครบทั้ง 3 symbol**

---

## 2. ผลที่ตามมาจาก D4 — 3 asset class ทำให้ค่า risk ตัวเดียวใช้ไม่ได้อีกต่อไป

เดิม `03-risk-spec.md` ตั้งค่า R5/R10/R11 เป็น**ค่าเดียวทั้งระบบ** ซึ่งสมเหตุสมผลตอนมีแต่ FX majors
พอเพิ่มทองกับ BTC ค่าเดียวกันกลายเป็นทั้งหลวมเกินและเข้มเกินพร้อมกัน

| กฎ | ปัญหาเมื่อใช้ค่าเดียว | ต้องเป็น |
|----|----------------------|---------|
| R5 `max_spread_points` = 25 | spread ทอง/BTC ปกติกว้างกว่า FX หลายเท่า → block ทุกไม้ | **ตารางต่อ symbol** |
| R10 `max_sl_distance_pct` = 3.0% | EURUSD 3% = ~330 pip → ไม่มีวันทริกเกอร์ = กฎตายแล้ว | **ตารางต่อ symbol** |
| R11 `trading_hours` Mon 01:00–Fri 20:00 | BTC เทรด 24/7 · ทองมีพักรายวัน | **ตารางต่อ symbol** |
| R12 `friday_close_before` | BTC ไม่มี "ตลาดปิดศุกร์" | **ยกเว้น BTC** (ตัดสินแล้ว) |

**→ เพิ่มงาน:** SPEC-064 SymbolRegistry ต้องถือ risk profile ต่อ symbol ไม่ใช่แค่ canonical name

### กฎเหล็กที่ตามมา: ห้าม hardcode contract spec

ค่าที่ต่างกันคนละ order of magnitude ระหว่าง 3 symbol นี้ (`volume_min`, `tick_value`,
`tick_size`, `point`, `contract_size`) **ต้องอ่านจาก `SymbolInfoDouble()` ตอน runtime เท่านั้น**
ห้ามเขียนค่าคงที่ในโค้ดหรือใน config — โบรกเกอร์เปลี่ยนสเปกได้โดยไม่บอก

### BTC เทรดเสาร์-อาทิตย์ → พังสมมติฐานอย่างน้อย 3 จุด

1. **SPEC-008 data quality gate** — "weekend bar detection" ที่ถือว่า bar เสาร์-อาทิตย์ = ข้อมูลเสีย
   จะ flag ข้อมูล BTC ที่**ถูกต้อง**ว่าเป็น error → gate ต้องรู้ trading calendar ต่อ symbol
2. **R6 daily loss / R7 HWM** — บัญชีที่ถือ BTC ข้ามสุดสัปดาห์มี equity ขยับตอนที่ FX ปิด
   HWM ต้องอัปเดตต่อเนื่อง ไม่ใช่หยุดตามปฏิทิน FX
3. **R16 brain timeout / P11 session health** — brain ต้องรันเสาร์-อาทิตย์ด้วย
   ถ้าตั้ง schedule ให้ปิดสุดสัปดาห์ EA จะเข้า SafeMode ค้าง 2 วัน

> ❗ **ต้องยืนยันก่อนเขียน SPEC-008:** IUX เปิด `BTCUSD.iux` เสาร์-อาทิตย์จริงไหม
> โบรกเกอร์หลายรายปิด crypto สุดสัปดาห์ ตรวจได้จาก M1 bar ในไฟล์ `.hcc` ปี 2025

### Timeframe: MT5 เก็บแค่ M1 — ที่เหลือ derive

`M5/M10/M15/M30/H1/H4` **ไม่ได้ถูกเก็บแยก** MT5 สร้างจาก M1 base ให้อัตโนมัติ

→ **SPEC-007 ingest ต้องดึง M1 อย่างเดียวแล้ว resample เอง** ไม่ใช่ดึง 7 ชุด
เหตุผล: ดึง 7 ชุดแยกกันจะได้ข้อมูลที่ **ไม่ consistent กันเอง** ถ้าโบรกเกอร์แก้ประวัติย้อนหลัง
(ปัญหา G12) และ resample เองทำให้ backtest กับ live ใช้ตรรกะเดียวกัน (จำเป็นสำหรับ SPEC-033 parity)

### P3/P4 ต้องรองรับสินทรัพย์ที่ไม่ใช่สกุลเงิน

- P3 currency exposure: `XAU` และ `BTC` ต้องนับเป็น "สกุล" ในการ decompose
  (`XAUUSD long 0.10` → `+10 XAU / −10×price USD` มีตัวอย่างใน risk-spec แล้ว ใช้กับ BTC แบบเดียวกัน)
- P4 correlation: ตอนนี้ correlation ข้าม asset class (ทอง↔BTC↔USD) ซึ่ง**ไม่เสถียร**
  ค่า 20 วันของคู่ต่างประเภทกระโดดแรงกว่า FX มาก → SPEC-026 ต้องมี minimum sample
  และ fallback เมื่อ correlation ยังไม่น่าเชื่อถือ (fail-closed = ถือว่า correlated เต็ม 1.0)

---

## 3. 🔴 D5 — ทุน 10 USD ทำให้ระบบ **ไม่เปิดไม้ได้เลยแม้แต่ไม้เดียว**

นี่ไม่ใช่ความเห็น เป็นผลจากสูตร R1 ที่เขียนไว้ใน `03-risk-spec.md` เอง

```
risk_money = equity × 0.35 / 100 = 10 × 0.0035 = $0.035
raw_lot    = risk_money / (sl_distance_pts × value_per_point)
เปิดไม้ได้ก็ต่อเมื่อ raw_lot ≥ volume_min (0.01)
```

จัดรูปใหม่: **SL ที่กว้างที่สุดที่ยังเปิดไม้ได้** = `risk_money / (volume_min × value_per_point)`

| symbol | contract | value/point (1 lot) | SL กว้างสุดที่ยังเปิดได้ | ความจริง |
|--------|----------|--------------------|--------------------------|----------|
| `EURUSD.iux` | 100,000 | $1.00 | **3.5 point = 0.35 pip** | แคบกว่า spread เอง |
| `XAUUSD.iux` | 100 oz | $1.00 | **3.5 point = $0.035** | ทองขยับเท่านี้ในเสี้ยววินาที |
| `BTCUSD.iux` | 1 BTC | $0.01 | **350 point = $3.50** | BTC ขยับเป็นพัน |

**ทั้ง 3 symbol → `raw_lot` ปัดลงเป็น 0 → reject ทุก intent → ระบบไม่เทรดอะไรเลยตลอดกาล**

### ทุนขั้นต่ำจริงที่ต้องใช้

`equity_min = (sl_pts × value_per_point × volume_min) / 0.0035`

| symbol | SL สมมติที่สมเหตุสมผล | ทุนขั้นต่ำ/บัญชี |
|--------|----------------------|-----------------|
| `EURUSD.iux` | 20 pip | **~$571** |
| `XAUUSD.iux` | $5.00 | **~$1,429** |
| `BTCUSD.iux` | $1,500 | **~$4,286** |

ตัวเลขนี้คือขั้นต่ำเพื่อเปิด **ไม้เดียว ขนาดเล็กสุด** ยังไม่รวม headroom สำหรับ
R4 (8 ticket พร้อมกัน) · R6 (2% daily) · R7 (10% max DD) · margin

### ทางเลือก

| # | ทางเลือก | ผล | ท่าที |
|---|----------|-----|------|
| A | **บัญชี Cent** (ถ้า IUX มี) — 1 lot = 1/100 ของ standard | $10 จริง = 1,000 หน่วยบัญชี → EURUSD ผ่าน ($5.71) · ทองต้อง ~$15 · BTC ต้อง ~$43 | ✅ **แนะนำ** ถ้าต้องการเงินจริงจำนวนน้อย |
| B | เพิ่มทุนเป็น standard account | ต้อง ~$600 (EURUSD) / ~$1,500 (+ทอง) / ~$4,300 (+BTC) ต่อบัญชี | ✅ ตรงไปตรงมา |
| C | คงทุน $10 = **demo เท่านั้น** ใช้พิสูจน์ท่อ Phase 1 | ไม่ขึ้นเงินจริง ไม่ต้องแก้อะไร | ✅ ยอมรับได้ ถ้าเลื่อน live ออกไป |
| D | เพิ่ม `risk_per_trade_pct` ให้ lot ผ่าน | ต้องขึ้นเป็น ~20% ต่อไม้ → 5 ไม้เสียติดกันบัญชีหมด | ❌ **ปฏิเสธ** — ทำลาย risk layer ทั้งชั้น ผิดหลัก "อย่าลดเกณฑ์เพราะอยากให้ผ่าน" |
| E | ปล่อยให้ clamp ขึ้นเป็น `volume_min` แล้วเทรดเลย | เท่ากับ D แต่เงียบกว่า — เสี่ยงจริง 20%/ไม้ โดยไม่มีใครรู้ | ❌ **ปฏิเสธ** และนี่คือสิ่งที่ bug ใน §4 จะทำถ้าไม่แก้ |

**คำแนะนำ:** A ถ้าอยากลงเงินจริงตอนนี้ · C ถ้ายังไม่รีบ
ถ้าเลือก A ต้องยืนยันก่อนว่า IUX มีบัญชี cent ที่เทรด `XAUUSD` และ `BTCUSD` ได้ และเป็น hedging mode

> **ค้างตัดสิน:** D5 ยังไม่ปิด รอเลือก A / B / C
> จนกว่าจะเลือก — **SPEC-020 (lot sizing) และ SPEC-025 (P1–P11 threshold) เริ่มไม่ได้**
> เพราะ threshold ทั้งชุดขึ้นกับขนาดทุน

---

## 4. 🔴 Bug ที่เจอในสูตร R1 ระหว่างคำนวณ §3 — ต้องแก้ไม่ว่าจะเลือกทางไหน

`03-risk-spec.md:75-77` ลำดับผิด ทำให้ guard เป็น dead code:

```
lot = floor(raw_lot / volume_step) × volume_step
lot = clamp(lot, volume_min, min(volume_max, max_lot_per_order))   ← ดันขึ้นเป็น volume_min
if lot < volume_min → reject intent                                ← ไม่มีวันเป็นจริงอีกแล้ว
```

`clamp()` ยก `lot` ขึ้นถึง `volume_min` เสมอ → บรรทัดถัดมาเช็คเงื่อนไขที่**เป็นไปไม่ได้**
→ intent ที่ควรถูก reject จะถูกเปิดที่ `volume_min` แทน **โดยเสี่ยงเกินที่ R1 กำหนดเท่าไรก็ได้**

ที่ทุน $10 ช่องโหว่นี้แปลว่า: แทนที่จะ reject ระบบจะเปิด 0.01 lot เสี่ยงจริง ~20%/ไม้ (57 เท่าของ R1)
**เงียบสนิท ไม่มี log ไม่มี alert** เพราะในมุมของโค้ดคือ "clamp ตามปกติ"

### สูตรที่ถูก

```
risk_money      = equity × risk_per_trade_pct / 100
sl_distance_pts = |entry_price − sl_price| / point
value_per_point = tick_value × (point / tick_size)          // ต่อ 1 lot
raw_lot         = risk_money / (sl_distance_pts × value_per_point)
lot             = floor(raw_lot / volume_step) × volume_step

if lot < volume_min → reject intent                          ← ★ ต้องอยู่ก่อน clamp
      reason = "RISK_TOO_SMALL_FOR_MIN_LOT"
      รายงาน equity, risk_money, raw_lot, volume_min ใน EXEC_REPORT

lot = min(lot, volume_max, max_lot_per_order)                ← clamp ลงเท่านั้น ห้ามยกขึ้น
```

**หลักการ:** clamp **ลง**ได้เสมอ (ปลอดภัยขึ้น) · clamp **ขึ้น**ห้ามเด็ดขาด (เสี่ยงเกินที่สั่ง)

**Test บังคับ (เพิ่มใน SPEC-020):**
`test_reject_when_min_lot_exceeds_risk_budget` — equity ต่ำจน `raw_lot < volume_min`
ต้องได้ `reject` **ห้ามได้ `volume_min`** · ต้องมีครบทั้ง 3 symbol

---

## 5. สิ่งที่ต้องแก้ตามมา

- [ ] `03-risk-spec.md` — แก้สูตร R1 (§4) · R5/R10/R11 เป็นตารางต่อ symbol · R12 ยกเว้น BTC
- [ ] `backlog.md` — ปิด D2, D4 · D5 เปลี่ยนเป็น "รอเลือก A/B/C" · Environment เพิ่ม symbol/TF
- [ ] `06-gap-audit.md` — Q2 ตอบแล้ว · Q3 ปิดบางส่วน
- [ ] `SPEC-064` (ยังไม่เขียน) — เพิ่มขอบเขต: risk profile + trading calendar ต่อ symbol
- [ ] `SPEC-007` (ยังไม่เขียน) — ดึง M1 อย่างเดียวแล้ว resample ห้ามดึง 7 TF แยก
- [ ] `SPEC-008` (ยังไม่เขียน) — weekend bar ต้องดูตาม calendar ต่อ symbol ไม่ใช่กฎเดียว
- [ ] `SPEC-020` (ยังไม่เขียน) — สูตร R1 ที่แก้แล้ว + test 3 symbol
- [ ] ยืนยัน: BTCUSD.iux เปิดเสาร์-อาทิตย์ไหม
- [ ] ยืนยัน: IUX มีบัญชี cent ที่เทรดทอง/BTC ได้ไหม (ถ้าเลือกทาง A)
