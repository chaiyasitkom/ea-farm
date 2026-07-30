# ADR-004 — หน่วยของ exposure ใน P3/P4 (ปิด D9)

**สถานะ:** ACCEPTED · **วันที่:** 2026-07-30 · **ตัดสินโดย:** เจ้าของโปรเจกต์
**ปิด:** [D9](../backlog.md) · **กระทบ:** SPEC-024 · SPEC-025 · SPEC-026 · [03-risk-spec §L2](../03-risk-spec.md)
**ต่อยอดจาก:** [ADR-002](ADR-002-symbols-capital-hours.md) (ชุด symbol) · [ADR-003](ADR-003-multi-broker.md) (canonical symbol)

---

## 1. การตัดสิน

**P3 และ P4 วัด exposure เป็น `risk-normalized` ไม่ใช่ notional**

> **นิยามที่ผูกพัน:** exposure ของสกุลเงิน X = *"ถ้า SL ของทุก position ที่มี X อยู่ขาหนึ่ง
> ถูกชนพร้อมกันในทิศเดียวกัน จะเสียกี่เปอร์เซ็นต์ของ farm equity"*

และ **USD ได้เพดานแยกที่สูงกว่าสกุลอื่น**

| | เพดาน (default) | เหตุผล |
|---|---|---|
| P3 สกุลที่ **ไม่ใช่** สกุลบัญชี (EUR·GBP·AUD·CAD·JPY·XAU) | **2.0%** ของ farm equity | ตัวเลขเดิมใน risk-spec ใช้ได้ทันทีเมื่อหน่วยเป็น risk-normalized |
| P3 **USD** (= account currency, §3) | **5.0%** ของ farm equity | ทั้ง 6 คู่มี USD อยู่ขาหนึ่ง — 2.0% จะ block ทั้งฟาร์มที่ไม้ที่ ~6 |
| P4 ต่อกลุ่ม correlated | **1.0%** ของ farm equity | หน่วยเดียวกับ P3 · เข้มกว่าเพราะเป็นเดิมพันก้อนเดียว |

ทั้งสามค่าเป็น **config** ปรับได้ แต่ **ห้าม implement โดยไม่มีเพดาน** และห้ามให้ค่า default
มาจากที่อื่นนอกจากไฟล์ config ที่ตรวจ diff ได้

---

## 2. สูตรที่ผูกพัน — ห้าม implement ต่างจากนี้

### 2.1 risk ต่อ 1 position (หน่วย = สกุลบัญชี)

```
risk_money(pos) = |price_open − sl| / point × value_per_point(symbol) × volume
```

`value_per_point` **ห้ามใช้ `tick_value` ที่ติดมากับ `HELLO`** — ค่านั้นถูกอ่านครั้งเดียวตอน
`OnInit` และสำหรับคู่ที่ quote ≠ สกุลบัญชี มันเคลื่อนตามอัตราแลกเปลี่ยนตลอดเวลา
brain ต้องคำนวณเองจาก `contract_size` (คงที่) + ราคาปัจจุบัน:

| กรณี | `value_per_point` (บัญชี USD) | symbol ในชุด |
|------|-------------------------------|--------------|
| quote = สกุลบัญชี | `contract_size × point` | `EURUSD` `GBPUSD` `AUDUSD` `XAUUSD` |
| base = สกุลบัญชี | `contract_size × point / price_current` | `USDJPY` `USDCAD` |
| ไม่มีสกุลบัญชีทั้งสองขา | **คำนวณไม่ได้ → fail-closed (§4.3)** | ไม่มีในชุดตอนนี้ |

`price_current` มาจาก MarketDataCollector ([SPEC-060](../specs/SPEC-060-market-data-collector.md))
และอยู่ใต้ stale guard ของ [SPEC-061](../specs/SPEC-061-stale-data-guard.md) — ราคาเก่า = fail-closed
ไม่ใช่ใช้ค่าเดิมต่อไปเงียบๆ

### 2.2 exposure ต่อ canonical symbol

```
risk_pct(pos) = risk_money(pos) / farm_equity × 100

symbol_exposure(c) = Σ risk_pct(pos)   ของทุก position ที่ canonical = c ทั้งฟาร์ม
                     ★ ถ้าในกลุ่มนี้มีทั้งขา long และ short (ละเมิด P12 ที่หลุดมาได้)
                       ต้องรวมแบบ gross (บวกค่าสัมบูรณ์) ห้าม net หักกัน — [ADR-005](ADR-005-cross-account-hedge.md)
```

### 2.3 exposure ต่อสกุลเงิน (P3)

แต่ละ position ให้ผลกับ **สองสกุล** ตาม base/quote ของ canonical symbol
([SPEC-064](../specs/SPEC-064-symbol-registry.md) เป็นคนบอก base/quote — ห้ามแยกจากชื่อเอง):

```
BUY  c(base B, quote Q)  →  +risk_pct ให้ B   ·   −risk_pct ให้ Q
SELL c(base B, quote Q)  →  −risk_pct ให้ B   ·   +risk_pct ให้ Q

currency_exposure(X) = | Σ signed risk_pct ทุก position ที่มี X ขาใดขาหนึ่ง |
```

ตรงข้ามกับ §2.2 ระดับสกุลเงิน**รวมแบบ signed** โดยตั้งใจ — long `EURUSD` + short `EURGBP`
คือการหักล้าง EUR จริงในเชิงเศรษฐกิจ ไม่ใช่การหลอกตัวเลขแบบ hedge symbol เดียวกัน 2 บัญชี

### 2.4 ตัวอย่างตรวจสอบ — ต้องออกมาตรงนี้เป๊ะ

farm equity $10,000 · ทุกไม้เสี่ยงตาม R1 = 0.35% ของบัญชีตัวเอง (สมมติบัญชีเท่ากัน 2 บัญชี × $5,000)

| position | risk_money | risk_pct (ของฟาร์ม) | EUR | USD | JPY |
|---|---|---|---|---|---|
| A1 BUY `EURUSD` | $17.50 | 0.175% | +0.175 | −0.175 | |
| A2 BUY `EURUSD` | $17.50 | 0.175% | +0.175 | −0.175 | |
| B1 SELL `USDJPY` | $17.50 | 0.175% | | −0.175 | +0.175 |
| **รวม** | | | **0.350%** | **0.525%** | **0.175%** |

- USD สะสมเร็วที่สุดเสมอ (อยู่ทุกไม้ ทิศเดียวกัน) → **นี่คือเหตุผลของเพดานแยกใน §3**
- ตัวเลขบวกกันเป็น % ได้ตรงกับตัวอย่างที่ risk-spec ใช้มาตั้งแต่ต้น
  (*"5 บัญชี แต่ละบัญชี long EURUSD 0.4% = รวม 2.0% ต่อ EUR"*) — นิยามนี้จึงไม่ได้เปลี่ยนเจตนาเดิม แค่ทำให้วัดได้

---

## 3. ทำไม USD ต้องมีเพดานแยก และทำไมเป็น 5.0%

ชุด symbol ตาม [ADR-002](ADR-002-symbols-capital-hours.md) มี USD **ทั้ง 6 คู่** →
ทุก position มี USD ขาหนึ่งโดยนิยาม

| ทางเลือก | ผล |
|----------|-----|
| USD ใช้ 2.0% เท่าสกุลอื่น | ฟาร์มถือได้ ~6 ไม้ **รวมทุก symbol** แล้วหยุด — กฎกลายเป็นเพดานจำนวนไม้ ไม่ใช่กฎ concentration |
| ยกเว้น USD ไม่คุมเลย | ทิ้ง USD-directional risk ที่เป็นเดิมพันจริง (`long EURUSD` + `short USDJPY` = short USD สองเท่า) ไว้กับ P4 อย่างเดียว · ถ้า SPEC-026 ยังไม่เสร็จ = ไม่มีอะไรคุมเลย |
| ✅ **USD 5.0% แยกจากสกุลอื่น 2.0%** | คุม USD จริงแต่ไม่กลายเป็นเพดานจำนวนไม้ |

**ทำไม 5.0% ไม่ใช่ตัวเลขสุ่ม** — วางให้อยู่ระหว่างเพดานที่มีอยู่แล้ว:

```
P1 farm_daily_loss breach = 3.0%   <   P3(USD) = 5.0%   <   P2 farm_max_dd warn = 8.0%
```

ความหมาย: สถานการณ์ "SL โดนพร้อมกันหมดทั้งฝั่ง USD" จะ**ทริกเกอร์ P1 ก่อน**ที่ P3(USD) จะเต็ม
→ P3(USD) ทำหน้าที่เป็นเพดาน tail-risk ไม่ใช่ด่านแรก · และยังต่ำกว่าจุดที่ P2 เริ่มเตือน

**สกุลบัญชีตัดสินจาก `HELLO.account.currency` ไม่ใช่ hardcode `"USD"`** —
ถ้าวันหนึ่งมีบัญชีสกุลอื่นในฟาร์ม กฎนี้ต้องยังทำงานถูก (§4.5)

---

## 4. ข้อผูกพันที่ต้องเข้าไปอยู่ใน SPEC-024/025/026

### 4.1 ★ farm equity ต้อง dedupe ตามบัญชี ไม่ใช่บวกทุก session

`session_id = acct-{login}-{symbol}-{timeframe}` → **บัญชีเดียวมีได้หลาย session**
และทุก session รายงาน `STATE.equity` ของบัญชี**เดียวกัน**

```
farm_equity = Σ equity ของ (broker, login) ที่ไม่ซ้ำ    ← ถูก
farm_equity = Σ equity ของทุก session                   ← ผิด · เงินเฟ้อตามจำนวน EA ที่รัน
```

ถ้าบวกทุก session: 3 EA บนบัญชีเดียว → farm equity ดูใหญ่ 3 เท่า → **ทุกเพดาน % หลวมลง 3 เท่าเงียบๆ**

`broker` มาจาก `HELLO.account.server` ([ADR-003 §3](ADR-003-multi-broker.md))

### 4.2 ★ position ต้อง dedupe ตาม ticket

`STATE.positions[]` กรองด้วย `(magic, symbol)` ไม่ได้กรองด้วย timeframe →
session `EURUSD-H1` กับ `EURUSD-M15` ที่ใช้ magic เดียวกันจะ**รายงานไม้เดียวกันทั้งคู่**

```
key ของ position = (broker, login, ticket)      ← ห้ามใช้ session_id เป็นส่วนของ key
```

### 4.3 fail-closed ทุกจุดที่คำนวณไม่ได้

| สถานการณ์ | ต้องทำ |
|-----------|--------|
| canonical symbol แปลงไม่ได้ (SPEC-064) | **reject intent** + `ERROR` · ห้ามข้ามไม้นั้นแล้วคำนวณต่อ |
| ราคาที่ใช้แปลงสกุลเก่าเกิน (SPEC-061) | reject intent ที่เกี่ยวกับสกุลนั้น |
| `contract_size` ของ symbol ยังไม่รู้ (ยังไม่มี `HELLO` ของ session นั้น) | reject intent |
| ไม่มีสกุลบัญชีทั้ง base และ quote | reject intent + `ERROR` (ตอนนี้เกิดไม่ได้ แต่ต้องไม่เงียบวันที่เพิ่ม cross pair) |

**ห้ามมีเส้นทางไหนที่ "คำนวณไม่ได้" แล้วผลออกมาเป็น exposure ต่ำ**

### 4.4 position ที่ไม่มี SL — ใช้ค่าที่แย่ที่สุดที่กฎอนุญาต

R9 บังคับทุกไม้มี SL แต่ SL อาจถูกลบด้วยมือ / โบรกเกอร์ถอด / ไม้ค้างจาก bug

```
sl หายไป (0 / null)  →  ใช้ SL สมมติ = max_sl_distance_pct ของ symbol นั้น (R10, จาก SPEC-064)
                      →  นับ exposure ตามนั้น + alert `P3_POSITION_WITHOUT_SL` severity ERROR
```

ห้ามข้ามไม้นั้น (= exposure ต่ำเกินจริง) และห้ามถือว่า risk เป็น ∞ (= ฟาร์มหยุดทั้งระบบเพราะไม้เดียว)

### 4.5 blind spot ที่ยอมรับไว้อย่างเปิดเผย — `foreign_positions`

`STATE.foreign_positions` มีแค่ `count` / `symbols` / `total_volume` / `margin_estimate`
**ไม่มี SL ต่อไม้** → คำนวณ risk-normalized ไม่ได้

**การตัดสิน:** P3/P4 นับเฉพาะไม้ที่ฟาร์มเป็นเจ้าของ · `foreign_positions.count > 0`
ยัง alert ตาม R19 เหมือนเดิม และต้องขึ้น dashboard ว่า **"ตัวเลข exposure ไม่รวมไม้แปลกปลอม"**
— บัญชีในฟาร์มไม่ควรมีไม้แปลกปลอมอยู่แล้ว ถ้ามีคือปัญหาที่ต้องแก้ที่ต้นเหตุ ไม่ใช่แก้ที่สูตร

---

## 5. ทางเลือกที่พิจารณาแล้วไม่เอา

| ทางเลือก | ทำไมไม่เอา |
|----------|-----------|
| **notional + เพดานใหม่เป็น multiple ของ equity** | ต้องตั้งค่าใหม่ทั้ง P3/P4 โดยไม่มีฐานอ้างอิง · และ notional ไม่ได้บอกความเสี่ยงที่แท้จริงเลย — `XAUUSD` 0.01 lot กับ `EURUSD` 0.01 lot notional ใกล้กัน แต่ risk ต่างกันหลายเท่าเพราะ SL คนละระยะ |
| **คุมสองชั้น (risk-normalized + notional cap)** | ปลอดภัยกว่าจริง แต่เพิ่มพารามิเตอร์ที่ยังไม่มีใครรู้ค่าที่ถูก · leverage cap ที่แท้จริงถูกคุมด้วย R8 margin level + P2 อยู่แล้ว · **เปิดเป็น ticket แยกได้ถ้าวันหนึ่งมีข้อมูลจริง** ไม่ใช่เดาค่าตอนนี้ |
| **ยกเว้น USD ไม่คุม** | §3 |
| **ใช้ `tick_value` จาก `HELLO` ตรงๆ** | stale สำหรับ `USDJPY`/`USDCAD` และผิดทิศทางความปลอดภัย — ค่าที่ค้างจากวันก่อนอาจทำให้ exposure **ต่ำ**กว่าจริง |
| **ให้ EA คำนวณ risk แล้วส่งขึ้นมาใน `STATE`** | ต้องแก้ schema + codegen + SPEC-010 ที่ยังไม่ implement · และย้ายตรรกะ risk ระดับฟาร์มไปอยู่ฝั่งที่มองเห็นแค่บัญชีเดียว · brain มีข้อมูลครบอยู่แล้ว (§2.1) |

---

## 6. สิ่งที่ต้องแก้ตามมา

- [x] `03-risk-spec.md` — เขียนหน่วยของ P3/P4 ให้ชัด + เพิ่มแถว P3 USD
- [x] `backlog.md` — ปิด D9 · ปลด SPEC-024/026 จาก BLOCKED
- [x] `08-status-and-plan.md` — spec ที่เขียนได้เพิ่มขึ้น
- [x] `SPEC-024` — decomposition + P3 ตามสูตร §2 ([spec](../specs/SPEC-024-currency-exposure.md))
- [x] `SPEC-026` — P4 ใช้หน่วยเดียวกัน ([spec](../specs/SPEC-026-correlation-engine.md))
- [x] `SPEC-025` — เรียก exposure engine ของ SPEC-024 ห้ามคำนวณเอง ([spec](../specs/SPEC-025-brain-risk-portfolio.md))
- [ ] ค่า `max_sl_distance_pct` ใน `contracts/symbols.json` กลายเป็น input ของ P3 ด้วย (§4.4)
      → เวลาปรับค่านั้นต้องรู้ว่ากระทบ 2 กฎ ไม่ใช่กฎเดียว
