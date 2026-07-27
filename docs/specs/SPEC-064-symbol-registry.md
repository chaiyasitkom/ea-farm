# SPEC-064 — SymbolRegistry: `(broker, raw)` → canonical

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-004 · **Blocks:** SPEC-007, SPEC-019, SPEC-024, SPEC-025, SPEC-026
**ปิดช่องว่าง:** [G7](../06-gap-audit.md) · **ต่อยอดจาก:** [ADR-002](../decisions/ADR-002-symbols-capital-hours.md) · [ADR-003](../decisions/ADR-003-multi-broker.md)

> ⚠️ **แก้ dependency:** backlog เดิมเขียน `006` (DB) — **ไม่ต้อง**
> registry เป็นไฟล์ประกาศในรีโปไม่ใช่ตารางใน DB (เหตุผลใน §3.2)
> ที่ต้องรอจริงคือ **SPEC-004** เพราะใช้ codegen machinery ตัวเดียวกัน

---

## 1. Goal

มีที่เดียวที่ตอบได้ว่า `EURUSD.iux` (IUX) กับ `EURUSD` (XM) คือสินทรัพย์เดียวกัน
และ `GOLD` (XM) คือตัวเดียวกับ `XAUUSD.iux` (IUX) — พร้อมบอก base/quote currency
และ risk profile ต่อ symbol

**ไม่มีตัวนี้ = P3/P4 นับ exposure แยกกันข้ามโบรกเกอร์ → ทะลุ limit จริงโดยตัวเลขดูปลอดภัย**

## 2. Non-goals

- ❌ ห้าม implement P3/P4 (SPEC-024, SPEC-026) — ticket นี้ให้แค่ข้อมูล
- ❌ ห้าม implement R5/R10/R11 enforcement (SPEC-019) — ให้แค่ค่า
- ❌ **ห้ามเก็บ contract spec** (`contract_size` `volume_min` `tick_value` `point`)
      — ต้องอ่านจาก `SymbolInfoDouble()` ตอน runtime ([ADR-002 §2.6](../decisions/ADR-002-symbols-capital-hours.md))
- ❌ ห้าม auto-discover symbol จากโบรกเกอร์ — ตารางต้องเป็นของที่คนกรอก (§4.1)
- ❌ ห้ามเดา canonical จากการตัด suffix — `GOLD` → `XAUUSD` เดาไม่ได้
- ❌ ห้ามแก้ `contracts/symbols.json` เอง — **Claude เป็นเจ้าของ** (§3.2)

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | เจ้าของ | ชนิด |
|------|---------|------|
| `contracts/symbols.json` | **Claude** | ข้อมูล registry — §5 มีเนื้อครบแล้ว |
| `contracts/schema/symbols_registry.json` | **Claude** | JSON Schema ของไฟล์บน |
| `contracts/gen/python/symbols.py` | — | **GENERATED** |
| `contracts/gen/mql5/FarmSymbols.mqh` | — | **GENERATED** |
| `tools/codegen.py` | Codex | **แก้** — เพิ่ม generator ตัวที่ 2 |
| `brain/common/registry.py` | Codex | loader + lookup API ฝั่ง Python |
| `tests/test_symbol_registry.py` | Codex | §7 |
| `tests/mql5/TestFarmSymbols.mq5` | Codex | §7 |

### 3.2 ★ ทำไมเป็นไฟล์ในรีโป ไม่ใช่ตารางใน DB

| ทางเลือก | ทำไมไม่เอา |
|----------|-----------|
| ตารางใน Postgres | EA อ่าน DB ไม่ได้ → ต้องส่งผ่าน wire → เพิ่ม message type + จังหวะ sync + โอกาส drift · และ **EA ต้องรู้ risk profile ตั้งแต่ `OnInit` ก่อนต่อ brain ด้วยซ้ำ** |
| hardcode ทั้งสองฝั่ง | drift แน่นอน |
| **ไฟล์เดียว + codegen 2 ฝั่ง** | ✅ แหล่งเดียว · ตรวจ diff ได้ · ใช้ machinery เดิมจาก SPEC-004 |

**ทำไม Claude เป็นเจ้าของไฟล์:** มันมีค่า risk (R5/R10/R11) อยู่ข้างใน
ถ้า Codex แก้ได้ = แก้เพดาน risk ได้เอง ซึ่งขัด [AGENTS.md ข้อ 5](../../AGENTS.md)
· และการเพิ่ม symbol เป็นการตัดสินใจระดับ ADR อยู่แล้ว ([ADR-002](../decisions/ADR-002-symbols-capital-hours.md) แก้ 5 rev เพราะเรื่องนี้)

### 3.3 API ฝั่ง Python — `brain/common/registry.py`

```python
class SymbolRegistry:
    @classmethod
    def load(cls, path: str = "contracts/symbols.json") -> "SymbolRegistry": ...

    # ---- แปลงชื่อ ----
    def to_canonical(self, broker: str, raw: str) -> str: ...
        # raise UnknownSymbolError ถ้าไม่มีในตาราง -- ห้ามคืน raw กลับไป

    def to_raw(self, broker: str, canonical: str) -> str: ...
        # ใช้ตอน brain ส่ง INTENT -- wire ใช้ชื่อ raw (common.json#/$defs/symbol)

    def is_known(self, broker: str, raw: str) -> bool: ...

    # ---- ข้อมูลของ canonical ----
    def base_quote(self, canonical: str) -> tuple[str, str]: ...   # ("XAU", "USD")
    def risk_profile(self, canonical: str) -> RiskProfile: ...
    def correlation_group(self, canonical: str) -> str: ...
    def is_production_ready(self, canonical: str) -> bool: ...     # §4.4

    # ---- รายการ ----
    def brokers(self) -> list[str]: ...
    def canonicals(self) -> list[str]: ...
    def raws_for_broker(self, broker: str) -> list[str]: ...
```

`broker` มาจาก `HELLO.account.server` (เช่น `IUXMarkets-Demo`) ตาม [ADR-003 §3](../decisions/ADR-003-multi-broker.md)
**ห้ามเดา broker จากรูปแบบชื่อ symbol**

### 3.4 API ฝั่ง MQL5 — `FarmSymbols.mqh` (generated)

```mql5
// คืน "" ถ้าไม่รู้จัก -- caller ต้องเช็คและ OnInit fail
string FarmSymbolCanonical(const string broker, const string raw);
string FarmSymbolBase(const string canonical);
string FarmSymbolQuote(const string canonical);
string FarmSymbolCorrelationGroup(const string canonical);

// risk profile -- คืน false ถ้าไม่รู้จัก
bool   FarmSymbolRisk(const string canonical,
                      int    &out_max_spread_points,   // -1 = ยังไม่ calibrate (§4.4)
                      double &out_max_sl_distance_pct,
                      string &out_session_policy);
bool   FarmSymbolProductionReady(const string canonical);
```

---

## 4. Behaviour

### 4.1 ★ Fail-closed — เจอ symbol ที่ไม่มีในตาราง = หยุด ห้ามเดา

| ที่ไหน | เจอ raw ที่ไม่รู้จัก → ต้องทำ |
|--------|------------------------------|
| EA `OnInit` | **`INIT_FAILED`** + log `FATAL symbol_not_in_registry broker=… raw=…` |
| brain รับ `BAR`/`STATE` | log `ERROR` + **ทิ้ง message นั้น** ไม่เอาเข้า DB |
| brain จะส่ง `INTENT` | **reject ก่อนส่ง** — ไม่มี raw ให้ใช้ |
| brain รวม exposure (P3) | **นับไม่ได้ = ต้อง fail** ห้ามข้ามเงียบ |

**ทำไมต้องเข้มขนาดนี้:** ถ้าเดาโดยตัด suffix แล้วโบรกเกอร์ที่ 3 ใช้ `EURUSDm`
ระบบจะมองเป็นสินทรัพย์คนละตัวกับ `EURUSD` → exposure ต่อ EUR ถูกนับแยก
→ **ทะลุ P3 จริงโดยที่ dashboard แสดงว่าปลอดภัย** นี่คือช่องว่าง G7 เป๊ะๆ

### 4.2 ทิศทางการแปลง — ใครใช้ชื่ออะไร

```
wire (BAR/STATE/INTENT)  ──►  ใช้ raw เสมอ   ("EURUSD.iux" / "GOLD")
DB bars.symbol           ──►  ใช้ raw + คอลัมน์ broker (PK มี broker อยู่แล้ว)
P3/P4 · feature · model  ──►  ใช้ canonical  ("EURUSD" / "XAUUSD")
```

| จังหวะ | แปลงอย่างไร |
|--------|-------------|
| brain รับ BAR/STATE | `to_canonical(broker, raw)` ก่อนเอาไปรวม exposure |
| brain ส่ง INTENT | `to_raw(broker, canonical)` ก่อนใส่ลง payload |
| EA | ใช้ raw ตลอด · ใช้ canonical เฉพาะตอนหา risk profile |

**ห้าม normalize ที่ชั้น wire** — [`common.json#/$defs/symbol`](../../contracts/schema/common.json)
กำหนดว่า wire ส่งชื่อจริงของโบรกเกอร์ · ถ้า EA ส่ง `XAUUSD` ขึ้นมาแทน `GOLD`
log จะไม่ตรงกับที่เห็นใน MT5 แล้ว debug ไม่ได้

### 4.3 การรวม exposure ข้ามโบรกเกอร์ — จุดที่ ticket นี้มีไว้เพื่อ

```
XM  : long  GOLD        0.02   →  canonical XAUUSD  →  +XAU / −USD
IUX : long  XAUUSD.iux  0.02   →  canonical XAUUSD  →  +XAU / −USD
                                   ─────────────────────────────────
                                   XAU exposure รวม = 2 เท่า  ✅ นับถูก
```
ถ้าไม่มี registry จะมองเป็น `GOLD` กับ `XAUUSD.iux` คนละตัว → **XAU ดูเหมือนครึ่งเดียว**

### 4.4 `max_spread_points: null` = ยังไม่ calibrate

[ADR-002 §Per-symbol](../decisions/ADR-002-symbols-capital-hours.md) สั่งว่า R5 ต้องมาจาก
**สถิติจริง ≥ 1 สัปดาห์ ห้ามตั้งจากค่าโฆษณาของโบรกเกอร์** ตอนนี้จึงยังไม่มีค่า

| สถานะ | พฤติกรรม |
|-------|----------|
| `max_spread_points` เป็นตัวเลข | R5 ทำงานปกติ · `production_ready = true` |
| `max_spread_points: null` | **R5 ข้ามการตรวจ + log WARN ทุกครั้ง** · `production_ready = false` |

**`production_ready = false` ห้ามขึ้นเงินจริง** — เป็น gate ของ SPEC-057 (live readiness audit)
· Phase 1 บน demo ใช้ได้ (ยังไม่มีเงินจริง) แต่ต้องเห็น WARN ตลอดว่ายังไม่ครบ

> ทำไมไม่ fail-closed ตรงนี้ด้วย: ถ้า block ทุกอย่างตั้งแต่วันแรก จะไม่มีทางเก็บ
> สถิติ spread มา calibrate ได้เลย — **เป็นวงกลม** · จึงยอมให้ผ่านบน demo
> แล้วบล็อกที่ประตูเงินจริงแทน

### 4.5 R11 `trading_hours` — registry เก็บ **นโยบาย** ไม่ใช่ข้อเท็จจริง

| แหล่ง | ให้อะไร |
|-------|---------|
| `contracts/symbols.json` | **นโยบาย** — ช่วงที่เรา*อนุญาต*ให้เทรด เช่น `MON_0100_FRI_2000` |
| `SymbolInfoSessionTrade()` ตอน runtime | **ข้อเท็จจริง** — ช่วงที่โบรกเกอร์*เปิด* จริง (ทองมีพักรายวัน) |
| **ที่มีผลจริง** | **intersection ของทั้งสอง** |

EA ต้องอ่าน session จริงจาก MT5 แล้ว intersect กับนโยบาย
**ห้าม hardcode ช่วงพักของทอง** — โบรกเกอร์เปลี่ยนได้

### 4.6 `correlation_group` = fallback เท่านั้น

P4 คำนวณ correlation 20 วันจริง (SPEC-026) · ค่านี้ใช้**เฉพาะตอน sample ไม่พอ**
→ ตอนนั้นให้ถือว่า symbol ในกลุ่มเดียวกัน **correlated = 1.0** (fail-closed)
ไม่ใช่ 0 ตามที่ [ADR-002 §2.3](../decisions/ADR-002-symbols-capital-hours.md) กำหนด

---

## 5. เนื้อ `contracts/symbols.json` — Claude กรอกให้แล้ว ห้าม Codex แก้

```jsonc
{
  "version": 1,
  "brokers": {
    "IUXMarkets-Demo": {
      "EURUSD.iux": "EURUSD",
      "USDJPY.iux": "USDJPY",
      "GBPUSD.iux": "GBPUSD",
      "AUDUSD.iux": "AUDUSD",
      "USDCAD.iux": "USDCAD",
      "XAUUSD.iux": "XAUUSD"
    },
    "XMGlobal-MT5 6": {
      "EURUSD": "EURUSD",
      "USDJPY": "USDJPY",
      "GBPUSD": "GBPUSD",
      "GOLD":   "XAUUSD"
    }
  },
  "canonicals": {
    "EURUSD": { "base": "EUR", "quote": "USD", "group": "EUROPE",
                "max_spread_points": null, "max_sl_distance_pct": 0.5,
                "session_policy": "MON_0100_FRI_2000" },
    "GBPUSD": { "base": "GBP", "quote": "USD", "group": "EUROPE",
                "max_spread_points": null, "max_sl_distance_pct": 0.6,
                "session_policy": "MON_0100_FRI_2000" },
    "USDJPY": { "base": "USD", "quote": "JPY", "group": "JPY",
                "max_spread_points": null, "max_sl_distance_pct": 0.6,
                "session_policy": "MON_0100_FRI_2000" },
    "AUDUSD": { "base": "AUD", "quote": "USD", "group": "COMMODITY_FX",
                "max_spread_points": null, "max_sl_distance_pct": 0.6,
                "session_policy": "MON_0100_FRI_2000" },
    "USDCAD": { "base": "USD", "quote": "CAD", "group": "COMMODITY_FX",
                "max_spread_points": null, "max_sl_distance_pct": 0.6,
                "session_policy": "MON_0100_FRI_2000" },
    "XAUUSD": { "base": "XAU", "quote": "USD", "group": "METALS",
                "max_spread_points": null, "max_sl_distance_pct": 1.5,
                "session_policy": "MON_0100_FRI_2000" }
  }
}
```

**หมายเหตุที่ตรวจจากดิสก์จริง 2026-07-28:**
- XM ยังไม่มี `AUDUSD` / `USDCAD` (ยังไม่เคยเปิดใน Market Watch) → **ไม่ใส่ในตาราง**
  · ปกติที่โบรกเกอร์มี symbol ไม่ครบเท่ากัน validator **ต้องไม่บังคับให้ครบทุกโบรก**
- `GOLD` → `XAUUSD` **ยืนยันจากโฟลเดอร์ history จริงของ XM แล้ว**
- `XAU` ไม่ใช่รหัส ISO currency แต่ต้องปฏิบัติเหมือนสกุลเงินใน P3
  ([risk-spec currency decomposition](../03-risk-spec.md))

---

## 6. Acceptance criteria

- [ ] `contracts/symbols.json` ผ่าน `contracts/schema/symbols_registry.json`
- [ ] `python tools/task.py codegen` สร้าง `symbols.py` + `FarmSymbols.mqh` ได้ · **รัน 2 ครั้ง byte-identical**
- [ ] `python tools/task.py codegen-check` แดงเมื่อแก้ `symbols.json` แล้วไม่ regenerate
- [ ] `FarmSymbols.mqh` compile 0 error 0 warning
- [ ] `to_canonical("XMGlobal-MT5 6", "GOLD") == "XAUUSD"` ✅ **ทั้งสองฝั่ง**
- [ ] `to_canonical("IUXMarkets-Demo", "XAUUSD.iux") == "XAUUSD"` ✅
- [ ] `to_raw("XMGlobal-MT5 6", "XAUUSD") == "GOLD"` ✅ (round-trip)
- [ ] `to_canonical(broker, "EURUSDm")` → **raise/คืน `""`** ไม่ใช่เดาเป็น `EURUSD`
- [ ] `grep -rn "\.replace\|StringSubstr\|rstrip\|removesuffix" brain/common/registry.py contracts/gen/`
      — **ต้องไม่มีการตัด suffix ด้วย string operation** (ต้องเป็น table lookup ล้วน)
- [ ] validator จับได้ทั้ง 5 เคสใน §7 ข้อ 8–12
- [ ] `production_ready` = **`false` ทั้ง 6 canonical** ตอนนี้ (`max_spread_points` ยัง null หมด)
      — ถ้าได้ `true` แปลว่า logic ผิด

## 7. Test list

### Python — `tests/test_symbol_registry.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_gold_maps_to_xauusd` | ★ เคสที่เดาด้วย string ไม่ได้ |
| 2 | `test_iux_suffix_maps_to_same_canonical` | `EURUSD.iux` → `EURUSD` |
| 3 | `test_same_canonical_from_two_brokers` | ★ เหตุผลทั้งหมดของ ticket นี้ |
| 4 | `test_to_raw_round_trip_all_entries` | `to_raw(to_canonical(x)) == x` ทุกคู่ |
| 5 | `test_unknown_raw_raises_not_guesses` | ★ fail-closed |
| 6 | `test_unknown_broker_raises` | |
| 7 | `test_base_quote_metals_xau` | `XAUUSD` → `("XAU","USD")` |
| 8 | `test_validator_rejects_duplicate_raw` | raw ซ้ำในโบรกเดียว |
| 9 | `test_validator_rejects_duplicate_canonical_per_broker` | 2 raw → canonical เดียว ในโบรกเดียว = **กำกวม** |
| 10 | `test_validator_rejects_base_equals_quote` | |
| 11 | `test_validator_rejects_canonical_without_definition` | mapping ชี้ไป canonical ที่ไม่มีนิยาม |
| 12 | `test_validator_allows_broker_missing_some_canonicals` | ปกติ ไม่ใช่ error |
| 13 | `test_production_ready_false_when_spread_null` | §4.4 |
| 14 | `test_correlation_group_fallback_values` | 4 กลุ่มตาม ADR-002 |

### MQL5 — `tests/mql5/TestFarmSymbols.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_canonical_gold_to_xauusd` | ตรงกับฝั่ง Python |
| 2 | `test_canonical_unknown_returns_empty` | fail-closed |
| 3 | `test_risk_profile_returns_false_for_unknown` | |
| 4 | `test_spread_null_encoded_as_minus_one` | `null` → `-1` ไม่ใช่ `0` (0 = spread 0 ซึ่งมีความหมายจริง) |
| 5 | `test_all_canonicals_have_base_and_quote` | |

### ★ Cross-check บังคับ

| # | test | ตรวจอะไร |
|---|------|----------|
| 15 | `test_python_and_mql5_agree_on_every_mapping` | รัน MQL5 dump ทุก mapping ลง JSON แล้ว **Python เทียบทีละคู่** — ถ้าสองฝั่งไม่ตรง codegen พัง |

**test นี้สำคัญที่สุดในไฟล์** — ถ้าสองฝั่งไม่ตรงกัน ระบบจะนับ exposure ผิดโดยไม่มีอะไรพัง

## 8. Files

**Touch:** ตาม §3.1 ยกเว้นที่ระบุว่า Claude เป็นเจ้าของ

**ห้ามแตะ:** `contracts/symbols.json` · `contracts/schema/**` · `docs/**` · `AGENTS.md`
· `CLAUDE.md` · `README.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `broker` key ควรใช้ `HELLO.account.server` ตรงๆ หรือ alias สั้นกว่า? | **ไม่บล็อก — ตอบแล้ว: ใช้ `account.server` ตรงๆ** ไม่ต้องมีชั้น alias เพิ่ม · ชื่อ `"XMGlobal-MT5 6"` มีเว้นวรรคและเลข ต้อง quote ให้ถูกทั้งสองภาษา **มี test คลุม** |
| Q2 | ถ้าโบรกเกอร์เปลี่ยนชื่อ server (เช่น `XMGlobal-MT5 7`)? | **ไม่บล็อก** — fail-closed จับได้ทันที (`unknown broker`) แล้วมาเพิ่มใน `symbols.json` · **ห้ามทำ prefix matching** เพราะ server คนละตัวอาจมี symbol คนละชุด |
| Q3 | เก็บ `session_policy` เป็น string enum หรือ struct? | **ไม่บล็อก** — ใช้ string enum ไปก่อน (ตอนนี้มีค่าเดียว) · SPEC-019 เป็นคน parse · ถ้าต้องการรูปแบบซับซ้อนกว่านี้ให้เสนอผ่าน implementation note |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ SPEC-004 merge**

---

## ภาคผนวก — ทำไม fail-closed ถึงสำคัญกว่าความสะดวก

เขียนกฎตัด suffix 3 บรรทัดก็ครอบ IUX ได้ทั้งหมด และดูเหมือนจะพอ
แต่วันที่เพิ่มโบรกเกอร์ที่ 3 ที่ใช้ `EURUSDm` หรือ `EUR/USD` กฎนั้นจะ**เงียบ**
ไม่ error ไม่ warn — แค่มองเป็นสินทรัพย์ใหม่

ผลคือ P3 นับ exposure ต่อ EUR แยกเป็นสองก้อน แต่ละก้อนต่ำกว่าเพดาน
**dashboard เขียว · limit ไม่เคยถูกละเมิดในสายตาระบบ · แต่ความเสี่ยงจริงเป็นสองเท่า**

`GOLD` → `XAUUSD` เป็นโชคดีที่มันเดาไม่ได้เลย จึงบังคับให้เราทำถูกตั้งแต่แรก
