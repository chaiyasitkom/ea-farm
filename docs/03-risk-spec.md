# 03 — Risk Management Specification

> ระบบนี้ออกแบบให้ **รอดก่อน กำไรทีหลัง**
> ทุกตัวเลขใน §L1/§L2 คือ default ที่ต้อง implement — ปรับได้ทีหลังผ่าน config
> แต่ห้าม implement โดยไม่มี limit เลย

---

## Risk 4 ชั้น

```
L3  GOVERNANCE   ── model promotion, degradation detection, ปิดกลยุทธ์ที่เสีย
      ▲ (offline, มนุษย์อนุมัติ)
L2  PORTFOLIO    ── Python risk manager: ข้ามบัญชี, correlation, farm-wide DD
      ▲ (soft — brain ตายแล้วชั้นนี้หาย จึงห้ามพึ่งชั้นนี้อย่างเดียว)
L1  ACCOUNT/EA   ── ★ hard limit compile ติดใน EA ทำงานได้แม้ brain ตาย ★
      ▲
L0  BROKER       ── leverage, margin call, stop out (ควบคุมไม่ได้ แต่ต้องรู้)
```

**หลักการ:** ชั้นบนสั่ง**เข้ม**กว่าชั้นล่างได้ แต่**ผ่อน**ไม่ได้
`effective_limit = min(L1, L2)` เสมอ

---

## L1 — EA Local Risk Guard (hard, offline-safe)

ทุกข้อต้องเป็น **EA input** ไม่ใช่ค่าจาก brain และต้องเช็คก่อนส่ง order ทุกครั้ง

| # | กฎ | default | เมื่อละเมิด |
|---|-----|---------|------------|
| R1 | `risk_per_trade_pct` — ความเสี่ยงต่อไม้ (คำนวณ lot จากระยะ SL) | 0.35% | คำนวณ lot ใหม่ให้พอดี |
| R2 | `max_lot_per_order` | 0.50 | clamp ลง + รายงาน |
| R3a | `max_net_volume_per_symbol` — เพดาน \|owned_net\| ต่อ symbol | 0.50 | clamp ลง + รายงาน |
| R3b | `max_tickets_per_symbol` — **anti-bug guard ไม่ใช่กฎ risk** | 4 | block + `ERROR severity:ERROR` (เกินนี้ = logic พัง) |
| R4 | `max_total_tickets` — นับ ticket ที่เป็นเจ้าของทั้งบัญชี | 8 | reject |
| R5 | `max_spread_points` — spread ปัจจุบันเกิน = ไม่เข้าใหม่ | **ต่อ symbol** ดู §Per-symbol | เลื่อนออกไป ถ้าเกิน `valid_until` = expire |
| R6 | `daily_loss_pct` — วัดจาก equity ตอน 00:00 broker time | 2.0% | **HALT บัญชีนี้ถึงสิ้นวัน** + ปิด position ทั้งหมด |
| R7 | `max_dd_pct` — วัดจาก equity high-water mark | 6.0% soft / 10.0% hard | soft → REDUCE_ONLY · hard → HALT + flatten |
| R8 | `min_margin_level_pct` | 300% | REDUCE_ONLY ทันที |
| R9 | `require_sl` — ห้ามเปิด position โดยไม่มี SL | true | reject intent |
| R10 | `max_sl_distance_pct` — SL ห้ามกว้างเกิน (กัน model เพี้ยน) | **ต่อ symbol** ดู §Per-symbol | reject |
| R11 | `trading_hours` — เวลาที่อนุญาต (broker time) | **ต่อ symbol** ดู §Per-symbol | ไม่เข้าใหม่ |
| R12 | `friday_close_before` — ปิดทุกอย่างก่อนปิดตลาด | 20:00 Fri **ทุก symbol** ([ADR-002](decisions/ADR-002-symbols-capital-hours.md)) | flatten |
| R13 | `kill_file` — ถ้าพบไฟล์ `Common\Files\farm_kill.txt` | เปิดใช้ | HALT + flatten ทันที ทุก terminal |
| R14 | `consecutive_loss_halt` — ขาดทุนติดกัน N ไม้ | 5 | HALT 4 ชั่วโมง |
| R15 | `max_slippage_points` — ถ้าเกิน ยกเลิกไม่ retry | 15 | log + alert |
| R16 | `brain_timeout_sec` — brain เงียบเกิน → SafeMode | 10 | SafeMode (`HOLD` default) |
| R17 | `max_orders_per_minute` — กัน order storm จาก bug | 6 | block + FATAL alert |
| R18 | `no_internal_hedge` — ห้ามถือ long+short symbol เดียวกันใต้ magic เดียวกัน ([ADR-001](decisions/ADR-001-hedging-account.md)) | บังคับ | net ออกทันที + `ERROR` + alert (เป็น anomaly ไม่ใช่สถานะปกติ) |
| R19 | `foreign_position_alert` — พบไม้บนบัญชีที่ไม่ใช่ของ EA | alert | ไม่ block การเทรด แต่ต้องแจ้ง (กินมาร์จิ้นจริง) |

### จุดที่ Codex พลาดบ่อย — ต้องทำให้ถูก

1. **R6 daily loss ต้องวัดจาก equity ไม่ใช่ closed P/L** — ถ้าวัดแค่ closed จะทะลุแล้วไม่รู้ตัวเพราะยังไม่ปิดไม้
2. **HWM ต้อง persist ข้าม restart** — เขียนลงไฟล์/global variable ไม่ใช่ตัวแปรใน memory
3. **"วันใหม่" ใช้ broker server time ไม่ใช่ local time** — และต้องรอด timezone/DST เปลี่ยน
4. **R13 kill file ต้องเช็คใน `OnTimer` ทุก 1s** ไม่ใช่แค่ `OnTick` (ตลาดปิด tick ไม่มา)
5. **R17 ต้องนับ order ที่ *ส่ง* ไม่ใช่ที่ *สำเร็จ*** — bug ที่ reject แล้ว retry รัวคือเคสที่ต้องกัน
6. **halt state ต้อง persist** — restart EA แล้วต้องยัง halt อยู่ถ้ายังในวันเดียวกัน
7. **R3a/R4 นับเฉพาะไม้ที่เป็นเจ้าของ (magic ตรง) — แต่ R8 margin level ต้องใช้ค่าทั้งบัญชี**
   ไม้ของ EA อื่น/เทรดมือ กินมาร์จิ้นจริง จะมองข้ามไม่ได้ แต่เราก็ไปปิดของเขาไม่ได้
8. **hedging: flatten หมายถึงวนปิดทุก ticket ไม่ใช่ส่ง order สวน 1 ไม้** —
   ส่งสวนจะกลายเป็น internal hedge ละเมิด R18 ทันที
9. **R7 max DD กับ hedging: ใช้ `AccountInfoDouble(ACCOUNT_EQUITY)`** ไม่ใช่ผลรวม
   `POSITION_PROFIT` ของไม้ที่เป็นเจ้าของ (ตกไม้ foreign + swap + commission ที่ยังไม่ลง)

### สูตรคำนวณ lot (R1) — implement ให้ตรงนี้

```
risk_money      = equity × risk_per_trade_pct / 100
sl_distance_pts = |entry_price − sl_price| / point
value_per_point = tick_value × (point / tick_size)      // ต่อ 1 lot
raw_lot         = risk_money / (sl_distance_pts × value_per_point)
lot             = floor(raw_lot / volume_step) × volume_step

if lot < volume_min → reject intent                      // ★ ต้องอยู่ก่อน clamp
      reason = "RISK_TOO_SMALL_FOR_MIN_LOT"
      รายงาน equity, risk_money, raw_lot, volume_min ใน EXEC_REPORT

lot             = min(lot, volume_max, max_lot_per_order)   // clamp ลงเท่านั้น
```

### ★ ลำดับสองบรรทัดสุดท้ายห้ามสลับ — เคยเป็น bug ในสเปกนี้เอง

เดิมเขียนว่า `clamp(lot, volume_min, …)` **ก่อน** เช็ค `lot < volume_min`
`clamp` ยก `lot` ขึ้นถึง `volume_min` เสมอ → บรรทัดเช็คกลายเป็น dead code
→ intent ที่ควร reject จะถูกเปิดที่ `volume_min` **โดยเสี่ยงเกิน R1 เท่าไรก็ได้ อย่างเงียบสนิท**

> ตัวอย่างจริง: **standard** account equity $30, R1 = 0.35% → risk_money = $0.105
> EURUSD SL 20 pip ควรได้ `raw_lot` = 0.000525 → ต้อง **reject**
> แต่ bug จะเปิด 0.01 lot = เสี่ยงจริง $2.00 = **6.7% ของบัญชี (19 เท่าของ R1)**
> ทอง SL $5 หนักกว่า: $5.00 = **16.7% ของบัญชี (48 เท่า)**
>
> บน **cent** account ที่ $30 (ค่าที่ตัดสินใน [ADR-002](decisions/ADR-002-symbols-capital-hours.md) §3.2)
> `raw_lot` ออกมา 0.02–0.07 อยู่เหนือ `volume_min` จึงยังไม่ทริกเกอร์ bug นี้ —
> **แต่ยังต้องแก้** เพราะจะทริกเกอร์ทันทีเมื่อ SL กว้างผิดปกติ หรือ equity ตกจาก drawdown

**หลักการ:** clamp **ลง**ได้เสมอ (ปลอดภัยขึ้น) · clamp **ขึ้น**ห้ามเด็ดขาด (เสี่ยงเกินที่สั่ง)
ดู [ADR-002](decisions/ADR-002-symbols-capital-hours.md) §4

⚠️ **ห้ามใช้ `tick_value` ตรงๆ กับคู่ที่ quote currency ≠ account currency**
ต้องแปลงผ่าน conversion rate — บัญชี USD มี 2 คู่ในชุดที่เข้าเคสนี้: **`USDJPY` (→JPY) · `USDCAD` (→CAD)**
Codex ต้องเขียน unit test ให้ครบ 3 เคส: **`USDJPY` · `USDCAD` · `XAUUSD`**
(สองตัวแรก = แปลงสกุล · ตัวหลัง = contract size ไม่ใช่ 100,000 แต่เป็น 100 oz)

⚠️ **ห้าม hardcode `volume_min` / `volume_step` / `tick_value` / `tick_size` / `point` / `contract_size`**
ค่าเหล่านี้ต่างกันคนละ order of magnitude ระหว่าง FX / ทอง / เงิน
และโบรกเกอร์เปลี่ยนได้โดยไม่บอก → อ่านจาก `SymbolInfoDouble()` ตอน runtime เท่านั้น

---

## Per-symbol risk profile (R5 · R10 · R11)

ตั้งแต่ [ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.3 ระบบเทรด **6 คู่ 2 asset class**
ค่าเดียวใช้ไม่ได้ — R10 = 3.0% กับ EURUSD คือ ~330 pip = กฎที่ไม่มีวันทริกเกอร์

| symbol | R5 `max_spread_points` | R10 `max_sl_distance_pct` | R11 `trading_hours` (broker time) |
|--------|------------------------|---------------------------|-----------------------------------|
| `EURUSD.iux` | TBD¹ | 0.5% | Mon 01:00 – Fri 20:00 |
| `GBPUSD.iux` | TBD¹ | 0.6% | Mon 01:00 – Fri 20:00 |
| `AUDUSD.iux` | TBD¹ | 0.6% | Mon 01:00 – Fri 20:00 |
| `USDJPY.iux` | TBD¹ | 0.6% | Mon 01:00 – Fri 20:00 |
| `USDCAD.iux` | TBD¹ | 0.6% | Mon 01:00 – Fri 20:00 |
| `XAUUSD.iux` | TBD¹ | 1.5% | Mon 01:00 – Fri 20:00 **หักพักรายวัน**¹ |

**R12 friday flatten: ใช้ทุก symbol** — ทั้ง 6 คู่ปิดสุดสัปดาห์ ไม่มีตัวไหนเทรด 24/7

¹ ค่าที่ยังไม่เติม **ห้ามเดา** — อ่านจากโบรกเกอร์จริงตอน `OnInit` ผ่าน
`SymbolInfoSessionTrade()` / `SYMBOL_SESSION_QUOTE` แล้วเก็บใน SymbolRegistry (SPEC-064)
· R5 spread ต้องเก็บสถิติจริง ≥ 1 สัปดาห์ก่อนตั้งเพดาน ห้ามตั้งจากค่าโฆษณาของโบรกเกอร์

### ★ ทั้ง 6 คู่มี USD อยู่ข้างหนึ่ง — กระทบ P3/P4/P5 โดยตรง

**P3** ยังถูกต้อง (decompose ครบทุกสกุล) แต่ USD อยู่ใน **ทุก** position
→ เพดาน 2.0% จะ block ตั้งแต่ position ที่ 2–3 · **SPEC-025 ต้องตัดสินว่า USD ได้เพดานแยกไหม**

**P4/P5** — 6 คู่ แต่เดิมพันอิสระจริง ~4 ก้อน:
`EURUSD`+`GBPUSD` (ยุโรป) · `USDJPY` · `AUDUSD`+`USDCAD` (commodity FX) · `XAUUSD` (โลหะ)
ข้ามก้อนยังมี `AUDUSD` ↔ `XAUUSD` (AUD เป็น proxy ของทอง)
→ **P4 จะ bind บ่อยกว่า P3** · **P5 = 3 หลวมเกินไป** (3 ไม้ในก้อนเดียว = เดิมพันเดียวคูณ 3)
→ SPEC-026 correlation ต้อง **fail-closed** (ข้อมูลไม่พอ = ถือว่า correlated 1.0 ไม่ใช่ 0)

---

## L2 — Portfolio Risk Manager (Python, cross-account)

รันทุกครั้งที่มี intent เข้ามา และทุก 5 วินาที (scheduled re-evaluate)

| # | กฎ | default | action |
|---|-----|---------|--------|
| P1 | `farm_daily_loss_pct` — รวมทุกบัญชี ถ่วงตาม equity | −1.5% warn / −3.0% breach | warn → `SCALED 0.5` · breach → `FLATTEN` ทั้งฟาร์ม |
| P2 | `farm_max_dd_pct` | 8% warn / 12% breach | warn → `REDUCE_ONLY` · breach → `HALT` |
| P3 | `max_currency_exposure` — net exposure ต่อสกุลเงินเดียว | 2.0% ของ farm equity | reject intent ที่จะเกิน |
| P4 | `max_correlated_risk` — กลุ่มที่ correlation 20d > 0.7 นับเป็นก้อนเดียว | 1.0% ของ farm equity ต่อกลุ่ม | scale intent ลง |
| P5 | `max_concurrent_strategies_same_direction` | 3 | reject ตัวที่ confidence ต่ำสุด |
| P6 | `strategy_allocation` — งบเสี่ยงต่อกลยุทธ์ | เท่ากันตอนเริ่ม | scale |
| P7 | `regime_scale` — จาก RegimeService | ดูตาราง §Regime | คูณ `scale_factor` |
| P8 | `news_block` — จาก NewsService | ดูตาราง §News | reject / reduce |
| P9 | `sanity_check` — confidence ∈ [0,1], target_volume finite, SL ฝั่งถูก | เข้มงวด | reject + alert (บ่งว่า model เพี้ยน) |
| P10 | `stale_data_guard` — feature ที่ใช้เก่ากว่า 2 bar | reject | ห้ามเทรดด้วยข้อมูลเก่า |
| P11 | `session_health` — บัญชีที่ heartbeat หาย > 30s | exclude จากการคำนวณ + alert | |

### สำคัญ: P3/P4 ต้องคำนวณจาก exposure จริง**ทั้งฟาร์ม** ไม่ใช่ต่อบัญชี

ถ้ามี 5 บัญชี แต่ละบัญชี long EURUSD 0.4% = รวม 2.0% ต่อ EUR
ถ้าคิดแยกบัญชีจะดูปลอดภัย แต่จริงๆ คือความเสี่ยงก้อนเดียว 5 เท่า
→ **นี่คือเหตุผลหลักที่ต้องมี L2 ไม่ใช่แค่ L1**

### Currency decomposition ที่ต้องทำ

```
long EURUSD 0.20 lot  →  +20,000 EUR  /  −20,000 USD (× rate)
short USDJPY 0.15 lot →  −15,000 USD  /  +15,000 × rate JPY
XAUUSD long 0.10 lot  →  +10 oz XAU   /  −10 × price USD
```
รวมทุกขาแล้วแปลงเป็น account currency → นี่คือ net exposure จริง

---

## Regime → Scale Factor

| regime | scale | เหตุผล |
|--------|-------|--------|
| `TREND_UP_LOW_VOL` / `TREND_DOWN_LOW_VOL` | 1.0 | สภาพดีที่สุดสำหรับ trend strategy |
| `TREND_*_HIGH_VOL` | 0.6 | ทิศชัดแต่ผันผวน ลดขนาด |
| `RANGE_LOW_VOL` | 0.8 (mean-reversion) / 0.3 (trend) | ขึ้นกับกลยุทธ์ |
| `RANGE_HIGH_VOL` | 0.3 | choppy กินค่าธรรมเนียม |
| `CRISIS` (vol > p95, correlation พุ่ง) | 0.0 | **ไม่เทรด** — pattern ในอดีตใช้ไม่ได้ |
| `UNKNOWN` / classifier ไม่มั่นใจ | 0.5 | conservative default |

**กฎ:** regime `CRISIS` → `REDUCE_ONLY` ทั้งฟาร์มอัตโนมัติ ไม่ต้องรอมนุษย์

---

## News → Action

| ระดับ | เกณฑ์ | ก่อนข่าว | หลังข่าว |
|-------|-------|----------|----------|
| `HIGH` | NFP, CPI, FOMC, rate decision, GDP | block เข้าใหม่ 30 นาที + ตั้ง SL ให้แน่นขึ้น | block 15 นาที |
| `MEDIUM` | PMI, retail sales, unemployment claims | scale 0.5 ก่อน 15 นาที | scale 0.5 หลัง 5 นาที |
| `LOW` | อื่นๆ | ไม่ทำอะไร | — |
| `LLM_RISK_FLAG` | LLM ตรวจพบข่าวไม่ตามปฏิทิน (geopolitical, ธนาคารกลางพูดนอกรอบ) | `REDUCE_ONLY` 60 นาที | ต้องมีมนุษย์ปลด |

**Fallback บังคับ:** ถ้า LLM API ล่ม / ตอบไม่เป็น JSON / timeout > 5s
→ ใช้ economic calendar อย่างเดียว **ห้าม fail-open** (ห้ามแปลว่า "ไม่มีข่าว = เทรดได้เต็มที่")

**คำเตือนเรื่อง LLM:** ห้ามให้ LLM ตัดสินใจ **ขนาด position** หรือ **ทิศทาง** โดยตรง
บทบาทของ LLM คือ **filter/veto และปรับ scale ลงเท่านั้น** — ไม่มีอำนาจเพิ่มความเสี่ยง
เหตุผล: LLM มี hallucination และ non-determinism ที่ backtest ไม่ได้ตรงๆ

---

## L3 — Governance (มนุษย์อยู่ในลูป)

| กฎ | เกณฑ์ |
|-----|-------|
| Model promotion | ต้องผ่าน OOS ≥ 6 เดือน, trades ≥ 100, Sharpe OOS ≥ 0.8, maxDD OOS ≤ 1.5× ของ in-sample |
| Champion/Challenger | challenger รัน demo/micro lot ขนาน ≥ 30 วัน ก่อนแทน champion |
| Degradation detect | rolling 30-day Sharpe < 0 หรือ DD > 1.5× backtest → auto ลดเป็น `SCALED 0.3` + alert |
| Strategy retirement | 60 วันติดกันที่ P/L < 0 และ Sharpe < 0 → ปิดอัตโนมัติ |
| Deploy gate | เปลี่ยนโค้ด risk layer = ต้องมี Claude review + test ผ่านครบ ก่อนขึ้น live |
| Capital ramp | เริ่ม live ด้วย ≤ 10% ของทุนที่ตั้งใจ · เพิ่มได้ทุก 30 วันถ้า live tracking error < 30% ของ backtest |

---

## ตารางที่ต้องมีใน Ops Dashboard ตั้งแต่ Phase 2

1. **Kill switch ปุ่มเดียว** — flatten ทั้งฟาร์ม (ต้องยืนยัน 2 ชั้น)
2. Farm equity curve + drawdown ปัจจุบัน vs limit (แสดงเป็น % ของ limit)
3. ตารางทุก session: สถานะ, heartbeat อายุ, day P/L, guard mode, positions
4. Net currency exposure heatmap
5. Risk events 24 ชม.ล่าสุด
6. Slippage / latency distribution (ตรวจสุขภาพ execution)
7. Champion vs challenger performance เทียบกัน

---

## สิ่งที่ระบบนี้ *ไม่* ทำ (non-goals — ตัดสินแล้ว)

- ❌ Martingale / grid / averaging down ทุกรูปแบบ — ไม่ implement แม้เป็น option
- ❌ ไม่มี SL — ทุก position ต้องมี SL (R9)
- ❌ Hedge ข้ามบัญชีเพื่อเลี่ยง DD limit — เป็นการโกงตัวเลขตัวเอง
- ❌ ให้ LLM สั่งเทรดตรงๆ
- ❌ Optimize บน in-sample แล้วขึ้น live เลย
- ❌ เพิ่ม lot หลังขาดทุนเพื่อ "เอาคืน"
