# ADR-003 — รองรับหลายโบรกเกอร์ (IUX + XM)

**สถานะ:** ACCEPTED (พร้อม 2 ข้อที่บล็อกการใช้งานจริง) · **วันที่:** 2026-07-27 · **ตัดสินโดย:** เจ้าของโปรเจกต์
**กระทบ:** SPEC-064 (SymbolRegistry) · SPEC-007 · SPEC-024 · SPEC-025 · SPEC-063 · R18 · P3/P4
**ต่อยอดจาก:** [ADR-002](ADR-002-symbols-capital-hours.md) ซึ่งเขียนบนสมมติฐาน **โบรกเกอร์เดียว**

---

## 1. การตัดสิน

เพิ่ม **XM Global** เป็นโบรกเกอร์ที่สอง ควบคู่กับ IUX Markets

| | IUX Markets | XM Global |
|---|---|---|
| Terminal path | `…\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3` | `…\Terminal\BB16F565FAAA6B23A20C26C49416FF05` |
| Server | `IUXMarkets-Demo` | `XMGlobal-MT5 6` |
| Build | — | **6063** |
| Suffix | `.iux` **บังคับ** | **ไม่มี suffix** |
| ชื่อทอง | `XAUUSD.iux` | **`GOLD`** |
| สถานะบัญชี | ✅ ใช้งานได้ | 🔴 **login ไม่ผ่าน** ดู §2 |

---

## 2. 🔴 สถานะจริงของ XM terminal — ยังใช้งานไม่ได้ตอนนี้

ตรวจจากดิสก์ 2026-07-27 (ไม่ได้เชื่อคำบอกเล่า):

### ❶ บัญชี login ไม่ผ่าน

```
logs/20260727.log  22:13:38
'1301856021': authorization on XMGlobal-MT5 6 failed (Invalid account)
```

และทุก server `XMGlobal-MT5 2…18` ตอบ `no demo/preliminary groups on server side`
= **สร้าง demo จากในเทอร์มินัลไม่ได้** ต้องสมัครผ่านเว็บ XM แล้วเอา credential มาใส่

### ❷ ไม่มี history ให้ใช้เลย

| symbol | ไฟล์ | ขนาด | ใช้ได้ไหม |
|--------|------|------|-----------|
| `EURUSD` | `2026.hcc` | 15 KB | ❌ stub เปล่า |
| `GBPUSD` | `2026.hcc` | 15 KB | ❌ stub เปล่า |
| `GOLD` | `2026.hcc` | 15 KB | ❌ stub เปล่า |
| `USDJPY` | `2026.hcc` | 15 KB | ❌ stub เปล่า |
| `USDCHF` | `2023.hcc` | 9.9 MB | 🟡 มีของ แต่ปี 2023 ปีเดียว และ **ไม่อยู่ในชุด 6 คู่** |

เทียบ IUX ที่มี M1 ตั้งแต่ 2016 → **XM ยังให้ข้อมูล backtest ไม่ได้เลย**

> **สรุป: XM เป็น "เพิ่มเข้าแผน" ไม่ใช่ "เพิ่มเข้าใช้งาน"**
> ทำ SPEC ต่อได้ แต่ยังรัน EA บน XM ไม่ได้จนกว่าจะแก้ ❶

---

## 3. ★ ผลกระทบที่ใหญ่ที่สุด: ชื่อ symbol ไม่ตรงกันเลย

```
EUR/USD  →  IUX: "EURUSD.iux"   XM: "EURUSD"
ทองคำ    →  IUX: "XAUUSD.iux"   XM: "GOLD"        ← ไม่ใช่แค่ suffix ต่าง ชื่อคนละตัว
```

นี่คือช่องว่าง **[G7](../06-gap-audit.md)** ที่เคยเป็นแค่ความเสี่ยงทางทฤษฎี — **ตอนนี้เกิดขึ้นจริงแล้ว**

### ผลต่อ SPEC-064 SymbolRegistry — เปลี่ยนจาก "ควรมี" เป็น "ขาดไม่ได้"

ต้อง map `(broker, raw_symbol)` → canonical:

| broker | raw | canonical | base | quote |
|--------|-----|-----------|------|-------|
| IUX | `EURUSD.iux` | `EURUSD` | EUR | USD |
| XM | `EURUSD` | `EURUSD` | EUR | USD |
| IUX | `XAUUSD.iux` | `XAUUSD` | XAU | USD |
| XM | `GOLD` | `XAUUSD` | XAU | USD |

**ห้ามใช้การตัด suffix แบบ string manipulation** — `GOLD` → `XAUUSD` ไม่มีทางเดาได้
ต้องเป็น **ตารางที่คนกรอก** และ **ต้อง fail-closed**: เจอ raw symbol ที่ไม่มีในตาราง
→ ปฏิเสธการเทรด symbol นั้น ไม่ใช่เดาเอง

### ผลต่อ contract ที่ตกลงไว้แล้ว — ✅ ไม่ต้องแก้

| ของเดิม | ทนได้ไหม |
|---------|----------|
| `bars` PK = `(broker, symbol, timeframe, bar_time)` | ✅ มี `broker` อยู่แล้ว |
| `common.json#/$defs/symbol` เป็น pattern ไม่ใช่ enum | ✅ `GOLD` ผ่าน pattern ได้ — **นี่คือผลของ[การตัดสินใจข้อ 1 ใน SPEC-003](../reviews/SPEC-003-schema-handoff.md)** ถ้าตอนนั้นทำเป็น enum ต้องแก้ schema + bump `v` ตอนนี้ |
| `session_id` = `acct-{login}-{symbol}-{tf}` | ✅ login ต่างกันข้ามโบรกเกอร์อยู่แล้ว |
| `CBrokerTime` แยกต่อ EA instance (SPEC-063) | ✅ แต่ละเทอร์มินัลตรวจ offset ของตัวเอง |

**`HELLO.account.server` เป็นตัวระบุ broker** — ไม่ต้องเพิ่ม field ใหม่

---

## 4. ~~🔴~~ ✅ ช่องว่างใหม่ที่หลายโบรกเกอร์เปิดขึ้น: hedge ข้ามโบรกเกอร์ (D10 — **ปิดแล้ว**)

> **ตัดสินแล้ว 2026-07-30 → [ADR-005](ADR-005-cross-account-hedge.md):** ห้ามสวนกันทั้งฟาร์ม ·
> P12 `no_cross_account_hedge` reject intent ที่จะทำให้เกิด · P3/P4 รวม gross ที่ระดับ canonical symbol
> · หัวข้อด้านล่างเก็บไว้เป็นบันทึกว่าเจอปัญหานี้ได้อย่างไร

[ADR-001 §2](ADR-001-hedging-account.md) ห้าม internal hedge ไว้ที่ระดับ **(magic, symbol) ในบัญชีเดียว** (R18)

แต่ตอนนี้เป็นไปได้ที่จะ:
```
บัญชี A (XM)  : long  EURUSD     0.05
บัญชี B (IUX) : short EURUSD.iux 0.05
```

- R18 **ไม่จับ** — คนละบัญชี คนละ symbol string
- P3 currency exposure จะ net เป็น **≈ 0** → มองว่า "ปลอดภัย"
- ความจริง: จ่าย spread 2 ขา + swap 2 ขา เพื่อ exposure สุทธิ = 0 = **เผาเงินเงียบๆ**

นี่คือ failure mode เดียวกับที่ ADR-001 §2 ปฏิเสธไว้ที่ระดับบัญชี **แต่ยังไม่มีใครกันที่ระดับฟาร์ม**

**→ ต้องเพิ่มกฎระดับ P** (เสนอ `P12 no_cross_account_hedge`): ถ้า canonical symbol เดียวกัน
มี exposure สวนทางกันข้ามบัญชี → **alert + reject intent ที่จะทำให้เกิด** ไม่ใช่ปล่อยให้ net กันเอง
· ติดตามที่ **D10** · ต้องปิดก่อน SPEC-025

> ✅ **คำถามนี้ตอบแล้ว: "ห้ามสวนกันทั้งฟาร์ม"** — แยกบัญชีไม่ทำให้สวนกันได้
> เหตุผลเต็มและนิยามที่ผูกพันอยู่ใน [ADR-005](ADR-005-cross-account-hedge.md)

---

## 5. ผลต่อ D5 (ทุน) — อาจพลิกได้ถ้า XM เป็นบัญชี **Micro**

[ADR-002 rev.5](ADR-002-symbols-capital-hours.md) ปิด D5 เป็น demo-first เพราะ IUX ไม่มีบัญชี cent
และ $30 standard เทรดไม่ได้

**XM มีบัญชี Micro ที่ contract size เล็กกว่า standard** — ถ้าบัญชีนี้เป็น Micro
ทุนที่ต้องใช้จะลดลงตามสัดส่วน `contract_size` โดยตรง

⚠️ **ยืนยันไม่ได้ตอนนี้เพราะบัญชี login ไม่ผ่าน** — `volume_min` / `contract_size` จริง
อ่านได้จาก MT5 เท่านั้น (Market Watch → คลิกขวา symbol → Specification)

**สิ่งที่ต้องอ่านมา 3 ค่า ต่อ 1 symbol:**
`SYMBOL_TRADE_CONTRACT_SIZE` · `SYMBOL_VOLUME_MIN` · `SYMBOL_VOLUME_STEP`

จากนั้นแทนในสูตรเดิม — **ไม่ต้องแก้โค้ดหรือ spec อะไรเลย** เพราะ
[ADR-002 §2.6](ADR-002-symbols-capital-hours.md) บังคับให้อ่านค่าพวกนี้ตอน runtime อยู่แล้ว:

```
equity_min = (sl_pts × value_per_point × volume_min) / (risk_per_trade_pct / 100)
value_per_point = contract_size × point        // เมื่อ quote currency = สกุลบัญชี
```

**ยังไม่แก้ D5** จนกว่าจะได้ตัวเลขจริง — การเดาว่า "XM Micro น่าจะพอ" แล้ววางแผนบนนั้น
คือความผิดพลาดแบบเดียวกับที่ทำให้ต้องเขียน ADR-002 ถึง 5 rev

---

## 6. ผลต่อ symbol set — XM ยังไม่ครบชุด 6 คู่

symbol ที่เทอร์มินัล XM เคยแตะ: `EURUSD` `GBPUSD` `GOLD` `USDCHF` `USDJPY`

| ชุด 6 คู่ ([ADR-002](ADR-002-symbols-capital-hours.md)) | XM มีร่องรอย |
|---|---|
| `EURUSD` `GBPUSD` `USDJPY` | ✅ |
| ทอง (`GOLD`) | ✅ ชื่อต่าง |
| `AUDUSD` `USDCAD` | ❌ ยังไม่เคยเปิด |

> เหมือนกรณี IUX: **ไม่ได้แปลว่าโบรกเกอร์ไม่มี** แค่ยังไม่เคยเปิดใน Market Watch
> XM ขาย FX majors ครบอยู่แล้ว — ยืนยันตอน login ได้

`USDCHF` มีใน XM แต่**ไม่อยู่ในชุด** → ห้ามเพิ่มเข้ามาเงียบๆ ถ้าอยากได้ต้องแก้ ADR-002

---

## 7. ทางเลือกที่พิจารณาแล้วไม่เอา

| ทางเลือก | ทำไมไม่เอา |
|----------|-----------|
| normalize ชื่อ symbol ตั้งแต่ชั้น wire (EA ส่ง `XAUUSD` ขึ้นมาแทน `GOLD`) | EA จะเดาแทนโบรกเกอร์ · debug ยากเพราะ log ไม่ตรงกับที่เห็นใน MT5 · ผิดหลัก "ส่งของจริงขึ้นมา แปลงที่ชั้นเดียว" |
| ตัด suffix ด้วย string rule (`.iux` → ตัด) | ใช้ไม่ได้กับ `GOLD` → `XAUUSD` และจะพังเงียบๆ กับโบรกเกอร์ที่ 3 |
| ให้ brain เดา broker จาก symbol name | `EURUSD` (XM) กับ `EURUSD` (โบรกอื่นในอนาคต) ชนกัน — ต้องใช้ `account.server` |
| ใช้ XM แทน IUX ไปเลย | XM ไม่มี history ให้ backtest · IUX มีถึง 2016 · **เก็บทั้งคู่ดีกว่า** |
| รอให้ XM login ได้ก่อนค่อยเขียน spec | SPEC-064/007/025 ต้องรู้ว่ามี 2 broker ตั้งแต่ตอนออกแบบ ไม่ใช่มาแก้ทีหลัง |

## 8. สิ่งที่ต้องแก้ตามมา

- [x] `backlog.md` — Environment เพิ่ม XM · เพิ่ม D10 · D11
- [x] `06-gap-audit.md` — G7 เปลี่ยนสถานะเป็น "เกิดขึ้นจริงแล้ว"
- [ ] **`SPEC-064`** (ยังไม่เขียน) — ต้องเขียนใหม่ให้รองรับ `(broker, raw)` → canonical
      พร้อมตาราง mapping ที่คนกรอก + fail-closed
- [ ] **`SPEC-007`** (ยังไม่เขียน) — ingest ต้องวนต่อ broker · `broker` เป็นส่วนของ PK อยู่แล้ว
- [x] **`SPEC-025`** — เพิ่ม P12 no_cross_account_hedge (D10) → [spec](../specs/SPEC-025-brain-risk-portfolio.md)
- [x] **`SPEC-024`** — P3 ต้อง aggregate ด้วย **canonical** symbol ไม่ใช่ raw → [spec](../specs/SPEC-024-currency-exposure.md)
- [ ] 🔴 **XM login ให้ผ่าน** (D11) — ตอนนี้ `Invalid account`
- [ ] 🔴 **อ่าน contract spec ของ XM** — อาจพลิก D5 (§5)
- [ ] ยืนยันว่า XM มี `AUDUSD` / `USDCAD` (§6)
