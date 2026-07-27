# ADR-002 — โบรกเกอร์ · ชุด Symbol/Timeframe · ทุนต่อบัญชี · Friday Close

**สถานะ:** ACCEPTED (พร้อม 2 ข้อค้างที่ต้องตัดสินซ้ำ) · **ตัดสินโดย:** เจ้าของโปรเจกต์
**ปิดหนี้เทคนิค:** D2 · D4 · D5 (บางส่วน) · **ตอบ:** [gap-audit](../06-gap-audit.md) Q2, Q3
**กระทบ:** R1, R5, R10, R11, R12 · P3, P4, P5 · SPEC-007, SPEC-008, SPEC-020, SPEC-024, SPEC-025, SPEC-026, SPEC-064

| แก้ไข | วันที่ | อะไรเปลี่ยน |
|-------|--------|-------------|
| rev.1 | 2026-07-27 | ฉบับแรก — 3 symbol (`EURUSD` `XAUUSD` `BTCUSD`) |
| rev.2 | 2026-07-27 | เปลี่ยนชุด symbol เป็น 8 คู่ · ตัด BTCUSD · เพิ่ม FX majors + XAGUSD |
| rev.3 | 2026-07-27 | ตัด `XAGUSD` ออก (เจ้าของเลือกทาง D) → เพดานทุนลงจาก ~$4,300 เป็น ~$1,430 · ปิด D8 |
| **rev.4** | **2026-07-27** | **ตัด `USDCNY` ทิ้ง → ชุด symbol ปิดสนิทที่ 6 คู่ · ทุนต่อบัญชี = $30 → ใช้ได้ครบถ้าเป็น cent account (§3) · ปิด D4** |

---

## 1. การตัดสิน

| # | หัวข้อ | ค่าที่ตัดสิน |
|---|--------|-------------|
| D2 | โบรกเกอร์ | **IUX Markets** (ยืนยันแล้ว — บัญชี `IUXMarkets-Demo`) |
| D4 | Symbol | ✅ **ปิดแล้ว rev.4 — 6 คู่** `EURUSD` `USDJPY` `GBPUSD` `AUDUSD` `USDCAD` `XAUUSD` (`USDCNY` ตัดทิ้ง rev.4 · `XAGUSD` ตัดออก rev.3) |
| D4 | Timeframe | **M1 · M5 · M10 · M15 · M30 · H1 · H4** (7 ชั้น) |
| D5 | จำนวนบัญชี | **≥ 2** |
| D5 | ทุนต่อบัญชี | **$30** → ✅ **ใช้ได้ครบ 6 คู่ถ้าเป็นบัญชี cent** · ❌ ใช้ไม่ได้เลยถ้าเป็น standard — ดู §3 |
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
| ~~6~~ | ~~`USDCNY.iux`~~ | 🔴 ไม่พบ | — | 🚫 **ตัดทิ้ง rev.4** — ดู §1.3 |
| 7 | `XAUUSD.iux` | ✅ | ✅ 2016–2026 | |
| ~~8~~ | ~~`XAGUSD.iux`~~ | ✅ | ✅ | 🚫 **ตัดออก rev.3** — บังคับทุน ~$4,300 (contract 5,000 oz) สูงสุดในชุด |

> ข้อกำหนด "M1 ย้อนหลัง ≥ 5 ปี" ของ [roadmap](../04-roadmap.md) Phase 0 **ผ่านทุกตัวที่ดาวน์โหลดแล้ว**
> ⚠️ [review compile-gate-02](../reviews/SPEC-001-compile-gate-02.md) §4 กับดัก #3 เขียนว่า history
> มีแค่ 2025.01.01–2026.06.19 — **ผิด** นั่นคือช่วงที่ tester มี cache ณ ตอนนั้น ไม่ใช่ข้อมูลที่มีจริง

### 1.3 ✅ `USDCNY.iux` — ตัดทิ้งแล้ว (rev.4)

**เจ้าของตัดสิน 2026-07-27: ตัดทิ้ง** → ชุด symbol ปิดสนิทที่ **6 คู่** ไม่มีอะไรค้างอีก

บันทึกเหตุผลเดิมไว้ด้านล่างเพื่อให้ย้อนดูได้ว่าทำไมถึงตัด — และถ้าอนาคตอยากได้ exposure
ฝั่ง CNY กลับมา ให้เปิด ticket ใหม่ **อย่ารื้อ ADR นี้**

<details><summary>บริบทเดิม (rev.2–rev.3)</summary>

ค้นทั้ง `history/` และ `ticks/` (19 symbol) **ไม่พบ `CN` / `CNY` / `CNH` เลยแม้แต่ตัวเดียว**
ทั้งที่ IUX มี USD exotic อื่นครบ (`USDHKD` `USDSGD` `USDTHB`)

> ⚠️ นี่พิสูจน์ว่า**ไม่เคยถูกเปิดใน Market Watch บนเครื่องนี้** ไม่ใช่พิสูจน์ว่าโบรกเกอร์ไม่มีขาย
> **ยืนยันเอง:** MT5 → Market Watch → คลิกขวา → Symbols → ค้น `CN`

**ถ้าไม่มีจริง — 2 ทางเลือก:**

| | ทางเลือก | หมายเหตุ |
|---|----------|----------|
| ก | ใช้ **`USDCNH`** แทน (ถ้ามี) | โบรกเกอร์ retail แทบทุกรายขาย **CNH offshore** ไม่ใช่ CNY onshore เพราะ CNY ควบคุมโดย PBoC เทรดนอกจีนไม่ได้จริง |
| ข | **ตัดทิ้ง** ← **เลือกทางนี้** | ทางที่ง่ายที่สุด |

**ข้อควรรู้ถ้าจะเอา CNH:** PBoC ตั้ง daily fix + คุมกรอบ → ความผันผวนต่ำผิดปกติเป็นช่วงยาว
แล้วกระโดดแรงตอนเปลี่ยนนโยบาย · swap มักแพงกว่า majors มาก
สำหรับ ML แปลว่า **ตัวอย่าง signal จริงน้อย + fat tail จาก policy risk** — ไม่ใช่คู่ที่ดีสำหรับ model แรก

</details>

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

## 3. D5 — ทุน $30 · ✅ ใช้ได้ครบ 6 คู่ถ้าเป็น **cent** · ❌ ใช้ไม่ได้เลยถ้าเป็น **standard**

`risk_money = equity × 0.35 / 100`
เปิดไม้ได้ก็ต่อเมื่อ `raw_lot = risk_money / (sl_pts × value_per_point) ≥ volume_min`

### 3.1 ❌ Standard account ที่ $30 — ยังเปิดไม้ไม่ได้เลย

`risk_money = 30 × 0.0035 = $0.105`
`SL กว้างสุดที่ยังเปิดได้ = risk_money / (volume_min × value_per_point)`

| symbol | contract | point | value/point (1 lot) | SL กว้างสุดที่เปิดได้ |
|--------|----------|-------|--------------------|----------------------|
| `EURUSD.iux` | 100,000 | 0.00001 | $1.00 | 10.5 pt = **1.05 pip** |
| `GBPUSD.iux` | 100,000 | 0.00001 | $1.00 | 10.5 pt = **1.05 pip** |
| `AUDUSD.iux` | 100,000 | 0.00001 | $1.00 | 10.5 pt = **1.05 pip** |
| `USDJPY.iux` | 100,000 | 0.001 | ~$0.67¹ | ~15.7 pt = **~1.57 pip** |
| `USDCAD.iux` | 100,000 | 0.00001 | ~$0.72¹ | ~14.6 pt = **~1.46 pip** |
| `XAUUSD.iux` | 100 oz | 0.01 | $1.00 | 10.5 pt = **$0.105** |

¹ ขึ้นกับ conversion rate ขณะนั้น ตัวเลขนี้ประกอบการอธิบายเท่านั้น

**ทุกค่ายังอยู่ในระดับเดียวกับ spread ของตัวเอง** (R5 อนุญาต spread ถึง 25 pt = 2.5 pip)
→ SL ที่แคบกว่า spread เป็นไปไม่ได้ → `raw_lot` ปัดลงเป็น 0 → **reject ทุก intent**

ทุนขั้นต่ำจริงบน standard — `equity_min = (sl_pts × value_per_point × volume_min) / 0.0035`

| symbol | SL สมมติ | ทุนขั้นต่ำ | $30 ขาดอีก |
|--------|---------|-----------|-----------|
| `USDJPY.iux` | 20 pip | ~$383 | 13× |
| `USDCAD.iux` | 20 pip | ~$411 | 14× |
| `EURUSD.iux` | 20 pip | ~$571 | 19× |
| `AUDUSD.iux` | 20 pip | ~$571 | 19× |
| `GBPUSD.iux` | 25 pip | ~$714 | 24× |
| `XAUUSD.iux` | $5.00 | **~$1,429** | **48×** |

### 3.2 ✅ Cent account ที่ $30 — ผ่านครบทั้ง 6 คู่ และ R1 ทำงานได้จริง

บัญชี cent: **1 lot = 1/100 ของ standard** และยอดเงินคิดเป็นหน่วย cent
→ `$30 = 3,000 หน่วยบัญชี` และ `value_per_point = 1.0 หน่วย/lot` (ทุกคู่ในชุด)

การคำนวณในหน่วยบัญชีเหมือน standard เป๊ะ **แต่ equity มากขึ้น 100 เท่าในเชิงหน่วย**
→ เทียบเท่า standard account ที่ **$3,000**

| symbol | SL สมมติ | ต้องมี (หน่วย) | มี 3,000 | **lot ที่ R1 คำนวณได้** |
|--------|---------|---------------|----------|------------------------|
| `USDJPY.iux` | 20 pip | 383 | ✅ | ~0.07 |
| `USDCAD.iux` | 20 pip | 411 | ✅ | ~0.07 |
| `EURUSD.iux` | 20 pip | 571 | ✅ | **0.05** |
| `AUDUSD.iux` | 20 pip | 571 | ✅ | **0.05** |
| `GBPUSD.iux` | 25 pip | 714 | ✅ | **0.04** |
| `XAUUSD.iux` | $5.00 | 1,429 | ✅ (2.1× headroom) | **0.02** |

**★ จุดที่สำคัญกว่า "ผ่าน/ไม่ผ่าน": lot ที่ได้ไม่ติดพื้น `volume_min`**

`raw_lot` ออกมาที่ 0.02–0.07 ซึ่งอยู่เหนือ `volume_min` (0.01) **2–7 ขั้น**
แปลว่า R1 ปรับขนาดตามระยะ SL ได้จริง ไม่ใช่ได้ `volume_min` ทุกครั้งแล้วเสี่ยงเกินโดยบังคับ

ตรวจ headroom ที่เหลือด้วย:

| กฎ | ที่ทุน 3,000 หน่วย | ประเมิน |
|----|-------------------|---------|
| R1 0.35%/ไม้ | 10.5 หน่วย/ไม้ | ✅ |
| R4 8 ticket พร้อมกัน | 8 × 0.35% = 2.8% | ✅ R6 (2%) จะ trigger ก่อน — ตามที่ออกแบบไว้ |
| R6 daily loss 2% | 60 หน่วย ≈ 6 ไม้เต็มขนาด | ✅ |
| R7 max DD 10% | 300 หน่วย ≈ 29 ไม้ | ✅ |
| R8 margin level 300% | notional จิ๋วมาก (EURUSD 0.05 lot cent = 50 EUR) | ✅ ไม่เป็นข้อจำกัด |

### 3.3 สรุปทางเลือก

| # | ทางเลือก | ผลที่ทุน $30 | ท่าที |
|---|----------|--------------|------|
| **A** | **บัญชี Cent** | ✅ **ผ่านครบ 6 คู่ · lot มี granularity จริง 0.02–0.07** | ✅ **แนะนำ — $30 พอดีใช้งานได้** |
| **B** | Standard account | ❌ ต้อง ~$1,430 ขาดอีก 48× · ถ้าเอาแต่ FX 5 คู่ ต้อง ~$714 ขาด 24× | ❌ ไม่พอ |
| **C** | demo เท่านั้น | ✅ พิสูจน์ท่อได้ครบ ไม่ต้องแก้อะไร | ✅ ยังเป็นทางที่ปลอดภัยสุดสำหรับ Phase 1 |
| ~~**D**~~ | ~~ตัด `XAGUSD`~~ | ✅ ทำแล้ว rev.3 — เพดานลง $4,300 → $1,430 | ✅ |
| **E** | เพิ่ม `risk_per_trade_pct` ให้ lot ผ่าน | ต้องขึ้นเป็น ~6.7% (EURUSD) / ~17% (ทอง) ต่อไม้ | ❌ **ปฏิเสธ** — ทำลาย risk layer ทั้งชั้น |
| **F** | ปล่อยให้ clamp ขึ้นเป็น `volume_min` | เท่ากับ E แต่เงียบกว่า — ดู §4 | ❌ **ปฏิเสธ** |

> ### ✅ D5 ปิดเรื่องจำนวนเงินแล้ว: **$30/บัญชี × ≥2 บัญชี**
> **เหลือยืนยันข้อเดียว: บัญชีเป็น cent จริงไหม**
> ทาง A ใช้ได้ · ทาง B ที่ $30 ใช้ไม่ได้เลย — ความต่างคือ "เทรดได้" กับ "reject ทุกไม้"
>
> **ต้องยืนยัน 3 อย่างก่อนขึ้นเงินจริง:**
> 1. IUX มีบัญชี cent ที่เทรด `XAUUSD.iux` ได้
> 2. บัญชี cent เป็น `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING` ([ADR-001](ADR-001-hedging-account.md))
> 3. `volume_min` / `volume_max` / `contract_size` จริงของบัญชี cent —
>    **อ่านตอน runtime ตาม §2.6 ห้าม hardcode** ตัวเลขใน §3.2 ใช้สมมติฐาน `volume_min = 0.01`
>
> **SPEC-020 / SPEC-025 เขียนได้แล้ว** — ไม่บล็อกอีก เพราะ equity เป็น **พารามิเตอร์ของ test**
> ไม่ใช่ค่าคงที่ในโค้ด · SPEC-020 ต้องทดสอบทั้งเคสที่ทุนพอ (สร้าง lot ถูก)
> และเคสที่ทุนไม่พอ (**reject ไม่ใช่ปัด `volume_min`**)

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

ที่ทุน **$30 บน standard account** ช่องโหว่นี้แปลว่า แทนที่จะ reject ระบบจะเปิด 0.01 lot โดยเสี่ยงจริง:

| symbol | เสี่ยงจริงที่ 0.01 lot (SL ปกติ) | เทียบ R1 (0.35% = $0.105) |
|--------|----------------------------------|---------------------------|
| `EURUSD` SL 20 pip | $2.00 = **6.7% ของบัญชี** | **19 เท่า** |
| `XAUUSD` SL $5 | $5.00 = **16.7% ของบัญชี** | **48 เท่า** |

**บน cent account ที่ $30 bug นี้ไม่ทริกเกอร์** เพราะ `raw_lot` ออกมา 0.02–0.07
อยู่เหนือ `volume_min` อยู่แล้ว — แต่ **ยังต้องแก้** เพราะจะทริกเกอร์ทันทีเมื่อ:
SL กว้างผิดปกติ · equity ตกจาก drawdown · หรือเปลี่ยนไปใช้ standard account

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
- [x] **ตัด `USDCNY` ทิ้ง** (rev.4) — ชุด symbol ปิดสนิทที่ 6 คู่
- [x] **D5 จำนวนเงิน = $30/บัญชี × ≥2 บัญชี** (rev.4)
- [ ] **ยืนยันว่าเป็นบัญชี cent** — $30 cent ใช้ได้ครบ · $30 standard ใช้ไม่ได้เลย (§3.3)
- [ ] ยืนยันบัญชี cent เทรด `XAUUSD.iux` ได้ และเป็น `RETAIL_HEDGING`
- [ ] `SPEC-064` — SymbolRegistry ถือ risk profile + trading session ต่อ symbol
- [ ] `SPEC-007` — ดึง M1 อย่างเดียวแล้ว resample · **ดาวน์โหลด `USDJPY.iux` ก่อน** (ยังไม่มี bar)
- [ ] `SPEC-020` — สูตร R1 ที่แก้แล้ว + test conversion 3 เคส (`USDJPY` `USDCAD` `XAUUSD`)
- [ ] `SPEC-025` — ตัดสินเพดาน P3 ของ USD (ทุกคู่มี USD → USD เป็นคอขวด §2.2)
- [ ] `SPEC-026` — correlation ต้อง fail-closed + ทบทวน P5 = 3 ว่าหลวมไปไหม (§2.3)
