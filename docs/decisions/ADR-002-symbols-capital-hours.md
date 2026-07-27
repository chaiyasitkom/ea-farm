# ADR-002 — โบรกเกอร์ · ชุด Symbol/Timeframe · ทุนต่อบัญชี · Friday Close

**สถานะ:** ACCEPTED (พร้อม 2 ข้อค้างที่ต้องตัดสินซ้ำ) · **ตัดสินโดย:** เจ้าของโปรเจกต์
**ปิดหนี้เทคนิค:** D2 · D4 · D5 (บางส่วน) · **ตอบ:** [gap-audit](../06-gap-audit.md) Q2, Q3
**กระทบ:** R1, R5, R10, R11, R12 · P3, P4, P5 · SPEC-007, SPEC-008, SPEC-020, SPEC-024, SPEC-025, SPEC-026, SPEC-064

| แก้ไข | วันที่ | อะไรเปลี่ยน |
|-------|--------|-------------|
| rev.1 | 2026-07-27 | ฉบับแรก — 3 symbol (`EURUSD` `XAUUSD` `BTCUSD`) |
| rev.2 | 2026-07-27 | เปลี่ยนชุด symbol เป็น 8 คู่ · ตัด BTCUSD · เพิ่ม FX majors + XAGUSD |
| **rev.3** | **2026-07-27** | **ตัด `XAGUSD` ออก (เจ้าของเลือกทาง D) → เพดานทุนลงจาก ~$4,300 เป็น ~$1,430 · ปิด D8** |

---

## 1. การตัดสิน

| # | หัวข้อ | ค่าที่ตัดสิน |
|---|--------|-------------|
| D2 | โบรกเกอร์ | **IUX Markets** (ยืนยันแล้ว — บัญชี `IUXMarkets-Demo`) |
| D4 | Symbol | **6 คู่** `EURUSD` `USDJPY` `GBPUSD` `AUDUSD` `USDCAD` `XAUUSD` — 🟠 **`USDCNY.iux` ยังค้าง** (§1.3) · `XAGUSD` ตัดออก rev.3 |
| D4 | Timeframe | **M1 · M5 · M10 · M15 · M30 · H1 · H4** (7 ชั้น) |
| D5 | จำนวนบัญชี | **≥ 2** |
| D5 | ทุนต่อบัญชี | ≥ 10 USD → 🔴 **ดู §3 — ค่านี้ใช้ไม่ได้ ต้องตัดสินใหม่** |
| Q2 | R12 friday close | **เปิดใช้ทุก symbol** (ข้อยกเว้น BTC หมดความหมายเมื่อตัด BTC ออก) |

### 1.1 หลักฐาน D2 (ตรวจจาก terminal จริง 2026-07-27)

`%APPDATA%\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3\bases\IUXMarkets-Demo\`
symbol ที่ terminal เคยแตะ (`history/` ∪ `ticks/`) = **19 ตัว ทั้งหมดลงท้าย `.iux`**

```
AUDJPY AUDUSD BTCUSD EURGBP EURJPY EURUSD GBPJPY GBPUSD NZDJPY NZDUSD
USDCAD USDCHF USDHKD USDJPY USDSGD USDTHB XAGUSD XAUEUR XAUUSD
```

### 1.2 ชุด symbol ที่ตัดสิน — ตรวจความพร้อมทีละตัว

| # | symbol | มีในโบรกเกอร์ | M1 history | หมายเหตุ |
|---|--------|--------------|------------|----------|
| 1 | `EURUSD.iux` | ✅ | ✅ 2016–2026 | |
| 2 | `USDJPY.iux` | ✅ | ⚠️ **ยังไม่ได้ดาวน์โหลด** | มี tick stream แต่ไม่มี bar — SPEC-007 ต้องดึงก่อน |
| 3 | `GBPUSD.iux` | ✅ | ✅ | |
| 4 | `AUDUSD.iux` | ✅ | ✅ | |
| 5 | `USDCAD.iux` | ✅ | ✅ | |
| 6 | `USDCNY.iux` | 🔴 **ไม่พบ** | — | ดู §1.3 |
| 7 | `XAUUSD.iux` | ✅ | ✅ 2016–2026 | |
| ~~8~~ | ~~`XAGUSD.iux`~~ | ✅ | ✅ | 🚫 **ตัดออก rev.3** — บังคับทุน ~$4,300 (contract 5,000 oz) สูงสุดในชุด |

> ข้อกำหนด "M1 ย้อนหลัง ≥ 5 ปี" ของ [roadmap](../04-roadmap.md) Phase 0 **ผ่านทุกตัวที่ดาวน์โหลดแล้ว**
> ⚠️ [review compile-gate-02](../reviews/SPEC-001-compile-gate-02.md) §4 กับดัก #3 เขียนว่า history
> มีแค่ 2025.01.01–2026.06.19 — **ผิด** นั่นคือช่วงที่ tester มี cache ณ ตอนนั้น ไม่ใช่ข้อมูลที่มีจริง

### 1.3 🟠 `USDCNY.iux` — ไม่มีในโบรกเกอร์ ต้องตัดสินใหม่

ค้นทั้ง `history/` และ `ticks/` (19 symbol) **ไม่พบ `CN` / `CNY` / `CNH` เลยแม้แต่ตัวเดียว**
ทั้งที่ IUX มี USD exotic อื่นครบ (`USDHKD` `USDSGD` `USDTHB`)

> ⚠️ นี่พิสูจน์ว่า**ไม่เคยถูกเปิดใน Market Watch บนเครื่องนี้** ไม่ใช่พิสูจน์ว่าโบรกเกอร์ไม่มีขาย
> **ยืนยันเอง:** MT5 → Market Watch → คลิกขวา → Symbols → ค้น `CN`

**ถ้าไม่มีจริง — 2 ทางเลือก:**

| | ทางเลือก | หมายเหตุ |
|---|----------|----------|
| ก | ใช้ **`USDCNH`** แทน (ถ้ามี) | โบรกเกอร์ retail แทบทุกรายขาย **CNH offshore** ไม่ใช่ CNY onshore เพราะ CNY ควบคุมโดย PBoC เทรดนอกจีนไม่ได้จริง |
| ข | **ตัดทิ้ง** เหลือ 5 คู่ | ทางที่ง่ายที่สุด |

**ข้อควรรู้ถ้าจะเอา CNH:** PBoC ตั้ง daily fix + คุมกรอบ → ความผันผวนต่ำผิดปกติเป็นช่วงยาว
แล้วกระโดดแรงตอนเปลี่ยนนโยบาย · swap มักแพงกว่า majors มาก
สำหรับ ML แปลว่า **ตัวอย่าง signal จริงน้อย + fat tail จาก policy risk** — ไม่ใช่คู่ที่ดีสำหรับ model แรก

---

## 2. ผลที่ตามมาจากชุด symbol ใหม่

### 2.1 ✅ ตัด BTCUSD ออก = ยกเลิกภาระที่เพิ่มมาใน rev.1 ทั้งหมด

| เรื่องที่ rev.1 เพิ่มเพราะ BTC | สถานะ rev.2 |
|-------------------------------|-------------|
| R12 ต้องมีข้อยกเว้นต่อ symbol | ✅ **ยกเลิก** — R12 ใช้ทุก symbol เหมือนกัน |
| R6/R7 HWM ต้องเดินต่อเสาร์-อาทิตย์ | ✅ **ยกเลิก** — ทั้ง 6 คู่ปิดสุดสัปดาห์ |
| R16/P11 brain ต้องรัน 24/7 | ✅ **ยกเลิก** — หยุดสุดสัปดาห์ได้ |
| SPEC-008 weekend bar ต้องดู calendar ต่อ symbol | ✅ **ยกเลิก** — bar เสาร์-อาทิตย์ = ข้อมูลเสีย กฎเดียวใช้ได้ทุกตัว |
| D6 "BTC เปิดเสาร์-อาทิตย์ไหม" | ✅ **ปิด** — ไม่เกี่ยวแล้ว |

**แต่ R11 `trading_hours` ยังต้องต่อ symbol อยู่** — ทองกับเงินมีพักรายวัน (daily break) ที่ FX ไม่มี

### 2.2 ★ ทั้ง 6 คู่มี USD อยู่ข้างหนึ่งทุกตัว

```
EURUSD  USDJPY  GBPUSD  AUDUSD  USDCAD  XAUUSD
   └────────── USD อยู่ในทุกคู่ 100% ──────────┘
```

P3 (`max_currency_exposure` 2.0% ต่อสกุล) **ยังทำงานถูกต้อง** เพราะ decompose ครบทุกสกุล
ไม่ใช่แค่ USD (long EURUSD + long USDJPY → USD สุทธิ ≈ 0 แต่ยังเห็น EUR ขาหนึ่ง JPY อีกขา)

**แต่ผลในทางปฏิบัติคือ USD กลายเป็นคอขวดของทั้งพอร์ต** — ทุก position กินโควตา USD เสมอ
เพดาน 2.0% ที่ตั้งไว้สำหรับสกุลทั่วไปจะ block ตั้งแต่ position ที่ 2–3

**→ ต้องตัดสินใน SPEC-025:** ให้ USD มีเพดานแยก (สูงกว่า) หรือรับว่า 2.0% คือเบรกที่ตั้งใจ
**ห้ามปล่อยให้ค่าเดียวกันโดยไม่ตัดสิน** — จะกลายเป็นว่าระบบเทรดได้แค่ 2 ไม้แล้วตันโดยไม่มีใครรู้ว่าทำไม

### 2.3 ★ 6 คู่ แต่เดิมพันอิสระจริงประมาณ 4 ก้อน

| ก้อน | symbol | เหตุผล |
|------|--------|--------|
| ยุโรป | `EURUSD` `GBPUSD` | correlation ระหว่างกันสูงมากตามปกติ |
| เยน | `USDJPY` | ค่อนข้างอิสระ |
| commodity FX | `AUDUSD` `USDCAD` | ผูกกับราคาสินค้าโภคภัณฑ์ |
| โลหะ | `XAUUSD` | เหลือตัวเดียวหลังตัด `XAGUSD` (rev.3) — ลด cluster ที่แน่นสุดในชุดออกไป |

ข้ามก้อนยังมีอีก: `AUDUSD` ↔ `XAUUSD` (AUD เป็น proxy ของทอง)

**ผลกระทบ:**
- **P4** (`max_correlated_risk` 1.0% ต่อกลุ่ม) จะเป็นกฎที่ **bind บ่อยกว่า P3** — กลับกันกับที่ออกแบบไว้ตอนคิดว่ามีแต่ majors กระจายตัว
- **P5** (`max_concurrent_strategies_same_direction` = 3) **หลวมเกินไปสำหรับชุดนี้** — 3 ไม้ในก้อนเดียวกัน = เดิมพันเดียวคูณ 3 ไม่ใช่ 3 เดิมพัน
- **SPEC-026** correlation engine ต้องมี minimum sample + fallback fail-closed (ถือว่า correlated = 1.0 เมื่อข้อมูลไม่พอ) ไม่ใช่ correlation 0

### 2.4 2 คู่ต้องแปลงสกุลเงิน — เปลี่ยนรายการ test บังคับ

บัญชี USD · `value_per_point` คำนวณตรงได้เฉพาะคู่ที่ **quote currency = USD**

| กลุ่ม | symbol | tick_value |
|-------|--------|-----------|
| quote = USD → ใช้ตรงได้ | `EURUSD` `GBPUSD` `AUDUSD` `XAUUSD` | ตรงไปตรงมา |
| quote ≠ USD → **ต้องแปลง** | `USDJPY` (→JPY) · `USDCAD` (→CAD) | ต้องผ่าน conversion rate |

`03-risk-spec.md` เดิมสั่งให้ test `XAUUSD, USDJPY, EURGBP` — **`EURGBP` ไม่อยู่ในชุดแล้ว**

→ **เปลี่ยนเป็น: `USDJPY` · `USDCAD` · `XAUUSD`** (สองตัวแรกคือเคสแปลงสกุล ตัวหลังคือเคส contract size ไม่ใช่ 100,000)

### 2.5 Timeframe: MT5 เก็บแค่ M1 — ที่เหลือ derive

`M5/M10/M15/M30/H1/H4` ไม่ได้ถูกเก็บแยก MT5 สร้างจาก M1 base ให้อัตโนมัติ

→ **SPEC-007 ต้องดึง M1 อย่างเดียวแล้ว resample เอง** ไม่ใช่ดึง 7 ชุด
เหตุผล: ดึงแยกจะได้ข้อมูล**ไม่ consistent กันเอง**ถ้าโบรกเกอร์แก้ประวัติย้อนหลัง (G12)
และ resample เองทำให้ backtest กับ live ใช้ตรรกะเดียวกัน (จำเป็นสำหรับ SPEC-033 parity)

**6 symbol × 1 TF (M1) × ~10 ปี** — ไม่ใช่ 6 × 7

### 2.6 กฎเหล็ก: ห้าม hardcode contract spec

`volume_min` `volume_step` `tick_value` `tick_size` `point` `contract_size`
ต่างกันคนละ order of magnitude ระหว่าง FX / ทอง / เงิน และโบรกเกอร์เปลี่ยนได้โดยไม่บอก
→ **อ่านจาก `SymbolInfoDouble()` ตอน runtime เท่านั้น** เก็บใน SymbolRegistry (SPEC-064)

---

## 3. 🔴 D5 — ทุน 10 USD ยังทำให้ระบบ **ไม่เปิดไม้ได้เลยแม้แต่ไม้เดียว**

ตัด BTC และ XAGUSD ออกแล้วเพดานทุนลงมาเหลือ ~$1,430 (ทองคุม) — **แต่ยังห่างจาก $10 อยู่ 143 เท่า**

คำนวณจากสูตร R1 ใน `03-risk-spec.md` เอง:

```
risk_money = equity × 0.35 / 100 = 10 × 0.0035 = $0.035
เปิดไม้ได้ก็ต่อเมื่อ raw_lot ≥ volume_min (0.01)
→ SL กว้างสุดที่ยังเปิดได้ = risk_money / (volume_min × value_per_point)
```

| symbol | contract | point | value/point (1 lot) | SL กว้างสุดที่เปิดได้ที่ทุน $10 |
|--------|----------|-------|--------------------|--------------------------------|
| `EURUSD.iux` | 100,000 | 0.00001 | $1.00 | 3.5 pt = **0.35 pip** |
| `GBPUSD.iux` | 100,000 | 0.00001 | $1.00 | 3.5 pt = **0.35 pip** |
| `AUDUSD.iux` | 100,000 | 0.00001 | $1.00 | 3.5 pt = **0.35 pip** |
| `USDJPY.iux` | 100,000 | 0.001 | ~$0.67¹ | ~5.2 pt = **0.52 pip** |
| `USDCAD.iux` | 100,000 | 0.00001 | ~$0.72¹ | ~4.9 pt = **0.49 pip** |
| `XAUUSD.iux` | 100 oz | 0.01 | $1.00 | 3.5 pt = **$0.035** |

¹ ขึ้นกับ conversion rate ขณะนั้น ตัวเลขนี้ประกอบการอธิบายเท่านั้น

**ทุกค่าแคบกว่า spread ของตัวเอง → `raw_lot` ปัดลงเป็น 0 → reject ทุก intent ทั้ง 6 คู่ ตลอดกาล**

### ทุนขั้นต่ำจริงที่ต้องใช้

`equity_min = (sl_pts × value_per_point × volume_min) / 0.0035`

| symbol | SL สมมติที่สมเหตุสมผล | ทุนขั้นต่ำ/บัญชี |
|--------|----------------------|-----------------|
| `USDJPY.iux` | 20 pip | ~$383 |
| `USDCAD.iux` | 20 pip | ~$411 |
| `EURUSD.iux` | 20 pip | ~$571 |
| `AUDUSD.iux` | 20 pip | ~$571 |
| `GBPUSD.iux` | 25 pip | ~$714 |
| `XAUUSD.iux` | $5.00 | **~$1,429** |

**ตัวที่บังคับทุนทั้งชุด = `XAUUSD`** → ~$1,430/บัญชี (ลงจาก ~$4,300 หลังตัด `XAGUSD` ใน rev.3)

ตัวเลขนี้คือขั้นต่ำเพื่อเปิด **ไม้เดียว ขนาดเล็กสุด** ยังไม่รวม headroom สำหรับ
R4 (8 ticket พร้อมกัน) · R6 (2% daily) · R7 (10% max DD) · margin

### ทางเลือก

| # | ทางเลือก | ผลที่ทุน $10 | ท่าที |
|---|----------|--------------|------|
| **A** | **บัญชี Cent** (ถ้า IUX มี) — 1 lot = 1/100 standard | $10 = 1,000 หน่วยบัญชี → **FX majors 5 คู่ผ่านหมด** · ทองต้อง ~$15 | ✅ **แนะนำ** ถ้าจะลงเงินจริงตอนนี้ · ครบ 6 คู่ควรมี **$20–50** จริง |
| **B** | เพิ่มทุน standard account | ต้อง ~$600 (FX เท่านั้น) / **~$1,430 (ครบ 6 คู่)** ต่อบัญชี × ≥2 บัญชี | ✅ ตรงไปตรงมา |
| **C** | คงทุน $10 = **demo เท่านั้น** | พิสูจน์ท่อ Phase 1 ได้ครบ ไม่ต้องแก้อะไร | ✅ ยอมรับได้ ถ้ายังไม่รีบขึ้น live |
| ~~**D**~~ | ~~ตัด `XAGUSD` ออก~~ | ✅ **เลือกแล้ว rev.3** — เพดานลง $4,300 → $1,430 · **แต่ยังไม่พอ ต้องเลือก A/B/C เพิ่ม** | ✅ ทำแล้ว |
| **E** | เพิ่ม `risk_per_trade_pct` ให้ lot ผ่าน | ต้องขึ้นเป็น ~20%/ไม้ → 5 ไม้เสียติดกันบัญชีหมด | ❌ **ปฏิเสธ** — ทำลาย risk layer ทั้งชั้น |
| **F** | ปล่อยให้ clamp ขึ้นเป็น `volume_min` แล้วเทรดเลย | เท่ากับ E แต่เงียบกว่า — เสี่ยงจริงเกิน R1 โดยไม่มีใครรู้ | ❌ **ปฏิเสธ** — และนี่คือสิ่งที่ bug ใน §4 จะทำถ้าไม่แก้ |

**คำแนะนำ:** A (+ B ถ้าอยากได้โลหะครบ) ถ้าจะลงเงินจริง · C ถ้ายังไม่รีบ

> **ค้างตัดสิน:** D5 ยังไม่ปิด รอเลือก A / B / C / D
> จนกว่าจะเลือก — **SPEC-020 (lot sizing) และ SPEC-025 (P1–P11 threshold) เริ่มไม่ได้**

---

## 4. 🔴 Bug ที่เจอในสูตร R1 ระหว่างคำนวณ §3 — ต้องแก้ไม่ว่าจะเลือกทางไหน

`03-risk-spec.md` เดิมลำดับผิด ทำให้ guard เป็น dead code:

```
lot = floor(raw_lot / volume_step) × volume_step
lot = clamp(lot, volume_min, min(volume_max, max_lot_per_order))   ← ดันขึ้นเป็น volume_min
if lot < volume_min → reject intent                                ← ไม่มีวันเป็นจริงอีกแล้ว
```

`clamp()` ยก `lot` ขึ้นถึง `volume_min` เสมอ → บรรทัดถัดมาเช็คเงื่อนไขที่**เป็นไปไม่ได้**
→ intent ที่ควรถูก reject จะถูกเปิดที่ `volume_min` **โดยเสี่ยงเกินที่ R1 กำหนดเท่าไรก็ได้**

ที่ทุน $10 ช่องโหว่นี้แปลว่า แทนที่จะ reject ระบบจะเปิด 0.01 lot โดยเสี่ยงจริง:

| symbol | เสี่ยงจริงที่ 0.01 lot (SL ปกติ) | เทียบ R1 (0.35% = $0.035) |
|--------|----------------------------------|---------------------------|
| `EURUSD` SL 20 pip | $2.00 = **20% ของบัญชี** | **57 เท่า** |
| `XAUUSD` SL $5 | $5.00 = **50% ของบัญชี** | **143 เท่า** |

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
ต้องได้ `reject` **ห้ามได้ `volume_min`** · ต้องครอบคลุม `XAUUSD` ด้วย (เคสรุนแรงที่สุดในชุด)

---

## 5. สิ่งที่ต้องแก้ตามมา

- [x] `03-risk-spec.md` — แก้สูตร R1 (§4) · R5/R10/R11 ตารางต่อ symbol · R12 ใช้ทุก symbol
- [x] `backlog.md` — ปิด D2, D6 · D4 มีเงื่อนไข (USDCNY) · D5 เป็น blocker
- [x] `06-gap-audit.md` — Q2 ตอบแล้ว · Q3 ปิด 2 ใน 3
- [x] **ตัด `XAGUSD`** — ทางเลือก D (rev.3)
- [ ] **ยืนยัน `USDCNY.iux` มีขายไหม** — ถ้าไม่มีเลือก `USDCNH` หรือตัดทิ้ง (§1.3)
- [ ] **ตัดสิน D5** — A / B / C (ทาง D ทำแล้วแต่ยังไม่พอ — $10 ยังห่างทอง 143 เท่า)
- [ ] `SPEC-064` — SymbolRegistry ถือ risk profile + trading session ต่อ symbol
- [ ] `SPEC-007` — ดึง M1 อย่างเดียวแล้ว resample · **ดาวน์โหลด `USDJPY.iux` ก่อน** (ยังไม่มี bar)
- [ ] `SPEC-020` — สูตร R1 ที่แก้แล้ว + test conversion 3 เคส (`USDJPY` `USDCAD` `XAUUSD`)
- [ ] `SPEC-025` — ตัดสินเพดาน P3 ของ USD (ทุกคู่มี USD → USD เป็นคอขวด §2.2)
- [ ] `SPEC-026` — correlation ต้อง fail-closed + ทบทวน P5 = 3 ว่าหลวมไปไหม (§2.3)
