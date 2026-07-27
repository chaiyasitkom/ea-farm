# SPEC-061 — P10 stale-data guard: fail-closed ทั้งชั้น risk

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-060 · **Blocks:** SPEC-024, SPEC-025, SPEC-026
**ปิดช่องว่าง:** [G1](../06-gap-audit.md) · **อ้าง:** [risk-spec P10](../03-risk-spec.md)

---

## 1. Goal

ทำให้ **ข้อมูลที่หายไปกลายเป็นการปฏิเสธ ไม่ใช่การปล่อยผ่าน**

G1 อธิบายไว้ตรงๆ: ถ้า P4 ไม่มีราคาของ `GBPUSD` มันจะได้ `correlation = 0`
แล้ว**ปล่อยผ่านทุก intent** — *"fail-open ในชั้น risk"*

## 2. Non-goals

- ❌ ห้ามเก็บข้อมูลเอง (SPEC-060) — ที่นี่แค่**ตัดสินว่าข้อมูลที่มีใช้ได้ไหม**
- ❌ ห้าม implement P3/P4 (SPEC-024/026) — แต่**กำหนดว่ามันต้องถามอะไรก่อนคำนวณ**
- ❌ ห้ามเดาค่าแทนข้อมูลที่หาย — ดู §4.2 ★
- ❌ ห้ามแตะ `mt5-ea/**` (P10 เป็นกฎฝั่ง brain)

---

## 3. Interface

```python
class Staleness(Enum):
    FRESH        = "FRESH"
    STALE        = "STALE"          # เก่าเกินเกณฑ์
    MISSING      = "MISSING"        # ไม่เคยมีเลย
    MARKET_CLOSED = "MARKET_CLOSED" # ★ ไม่ใช่ปัญหา ดู §4.3

@dataclass(frozen=True)
class DataVerdict:
    state: Staleness
    age_sec: float | None
    reason: str

class StaleDataGuard:
    def __init__(self, collector: MarketDataCollector, clock: Clock,
                 quote_max_age_sec: float = 30.0,
                 bar_max_age_bars: int = 2): ...      # P10: "เก่ากว่า 2 bar"

    def check_quote(self, canonical: str) -> DataVerdict: ...
    def check_bars(self, canonical: str, timeframe: str) -> DataVerdict: ...

    # ★ ตัวที่ risk rule ต้องเรียกก่อนคำนวณ
    def require(self, canonicals: Sequence[str], need: DataNeed) -> RequireResult: ...
```

ไฟล์: `brain/risk/staleness.py` · `tests/test_staleness.py`

---

## 4. Behaviour

### 4.1 ★★ ตารางบังคับ: ข้อมูลหาย → กฎต้องตีความแบบไหน

**นี่คือเนื้อหาทั้งหมดของ ticket นี้**

| กฎ | ข้อมูลที่ต้องใช้ | ถ้า `STALE`/`MISSING` → ต้องทำ | ❌ ห้ามทำ |
|----|------------------|-------------------------------|-----------|
| **P3** currency exposure | quote ของทุก symbol ที่ถืออยู่ | **reject intent** — แปลง exposure ไม่ได้ = ไม่รู้ว่าเกินเพดานไหม | ใช้ rate เก่า · ข้าม symbol นั้น |
| **P4** correlated risk | bar ของ **ทุก** symbol ในกลุ่ม | **ถือว่า correlation = 1.0** (correlated เต็ม) → กลุ่มนั้นนับเป็นก้อนเดียว | ★ **ถือว่า = 0** |
| **P7** regime scale | regime ล่าสุด | **ใช้ scale ที่เข้มที่สุด** ที่ regime ไหนก็ตามให้ | ใช้ `1.0` |
| **P8** news block | สถานะข่าว | **block** (fail-closed ตาม roadmap 4.5) | ปล่อยผ่าน |
| **R1** lot sizing | equity จาก `STATE` | reject ([SPEC-019 §4.3](SPEC-019-local-risk-guard.md)) | ใช้ equity เก่า |

**แถว P4 คือ G1 เป๊ะๆ** — `correlation = 0` แปลว่า *"ไม่เกี่ยวกันเลย"* ซึ่งเป็น
**สมมติฐานที่หลวมที่สุดเท่าที่เป็นไปได้** · ข้อมูลที่หายไปไม่ควรทำให้กฎอ่อนลง

### 4.2 ★ หลักการเดียว: "ไม่รู้" ต้องถูกปฏิบัติเหมือน "แย่ที่สุดที่เป็นไปได้"

```
ค่าที่ใช้แทนข้อมูลที่หาย = ค่าที่ทำให้กฎ "เข้มที่สุด"
```

**ห้ามใช้:** ค่าเริ่มต้น · ค่าเฉลี่ย · ค่าล่าสุดที่รู้ · `0` · `None` ที่ถูกตีความเป็น 0

เหตุผล: ข้อมูลหายมักเกิดพร้อมกับเหตุการณ์ผิดปกติ (เน็ตมีปัญหา · โหลดหนัก ·
โบรกเกอร์มีปัญหา) — **ซึ่งเป็นเวลาที่ควรระวังที่สุด ไม่ใช่ผ่อนที่สุด**

### 4.3 ★★ "ตลาดปิด" ≠ "ข้อมูลหาย" — แยกให้ขาด

ทั้ง 6 คู่ปิดสุดสัปดาห์ ([ADR-002](../decisions/ADR-002-symbols-capital-hours.md))
· ถ้าไม่แยก **ทุกสุดสัปดาห์ระบบจะรายงานว่าข้อมูลหายทั้งหมด** แล้วคนจะเลิกสนใจ alert

| สภาพ | `broker_available` | quote ค้าง | ผล |
|------|-------------------|-----------|-----|
| ตลาดปิด | ✅ true | ✅ | **`MARKET_CLOSED`** — ไม่ใช่ปัญหา · ไม่ alert |
| collector ตาย | ❌ false | ✅ | **`STALE`** — 🔴 alert |
| broker ต่อไม่ได้ | ❌ false | ✅ | **`STALE`** — 🔴 alert |
| ไม่มี offset (ไม่มี EA) | — | — | **`MISSING`** — 🟠 alert |

ใช้ `FreshnessInfo.broker_available` จาก [SPEC-060 §4.5](SPEC-060-market-data-collector.md)
+ session ของ symbol จาก [SPEC-064](SPEC-064-symbol-registry.md)

**`MARKET_CLOSED` ยังต้อง reject intent อยู่** (จะเปิดไม้ตอนตลาดปิดไม่ได้อยู่แล้ว)
— แต่**ไม่ alert** เพราะไม่ใช่ความผิดปกติ

### 4.4 เกณฑ์อายุ

| ข้อมูล | เกณฑ์ | เหตุผล |
|--------|-------|--------|
| quote | **30 วินาที** | collector poll ทุก 5 วิ → 30 วิ = พลาด 6 รอบ = มีปัญหาแน่ |
| bar | **2 bar ของ timeframe นั้น** | ตรงกับ risk-spec P10 |

`bar_max_age` เป็น**จำนวน bar ไม่ใช่วินาที** — M1 กับ H4 ต่างกัน 240 เท่า

### 4.5 ★ `require()` — จุดเดียวที่กฎ risk เรียก

```python
result = guard.require(["EURUSD", "GBPUSD"], DataNeed.BARS_H1)
if not result.ok:
    reject_intent(reason=f"P10_STALE_DATA {result.detail}")
```

| กฎ | |
|----|---|
| ต้องเรียก **ก่อน** คำนวณเสมอ | ไม่ใช่คำนวณแล้วค่อยเช็ค |
| `result.detail` ต้องบอก **symbol ไหน · เก่าแค่ไหน** | `"GBPUSD bars stale age=3h"` ไม่ใช่ `"stale data"` |
| ตรวจ **ทุก symbol ในกลุ่ม** ไม่ใช่แค่ตัวที่จะเทรด | ★ P4 ต้องการทั้งกลุ่มถึงจะคำนวณได้ |

**ข้อสุดท้ายคือจุดที่พลาดง่ายที่สุด** — จะเทรด `EURUSD` แต่ถ้า `GBPUSD` (อยู่กลุ่ม
`EUROPE` เดียวกัน) ไม่มีข้อมูล **P4 ก็คำนวณไม่ได้อยู่ดี**

### 4.6 ต้องเห็นได้จากภายนอก

| ต้องมี | ใช้ที่ไหน |
|--------|-----------|
| `staleness_by_symbol` | dashboard (SPEC-028) |
| `rejects_due_to_stale_data` (นับ) | 🔴 alert (SPEC-029) |
| เวลาที่ `STALE` ครั้งล่าสุด/ต่อเนื่องนานเท่าไร | |

**ถ้าเกิด `STALE` ต่อเนื่องเกิน 5 นาที ต้อง alert** — ระบบที่ปฏิเสธทุก intent
เงียบๆ ดูเหมือนระบบที่ไม่มีสัญญาณ ซึ่งแยกไม่ออกจากตลาดเงียบ

---

## 5. Edge cases

1. **สุดสัปดาห์** → `MARKET_CLOSED` ทุก symbol · **ห้าม alert** · §4.3
2. **ทองพักรายวัน** → `MARKET_CLOSED` เฉพาะทอง · FX ยัง `FRESH`
3. **symbol ไม่มีใน registry** → `MISSING` + ERROR (ไม่ควรถูกถามตั้งแต่แรก)
4. **collector เพิ่งสตาร์ต ยังไม่มีข้อมูล** → `MISSING` · **reject** จนกว่าจะมี
   · ไม่ใช่ปล่อยผ่านช่วง warm-up ★
5. **นาฬิกา brain เพี้ยนทำให้ age ติดลบ** → ถือว่า `FRESH` + WARN (ไม่ใช่ `STALE`)
6. **quote สดแต่ bar เก่า** → กฎที่ใช้ quote ผ่าน · กฎที่ใช้ bar ไม่ผ่าน · **แยกกัน**
7. **ทุก symbol `STALE` พร้อมกัน** → น่าจะ collector ตาย → alert ระดับสูงกว่าปกติ
8. **1 symbol `STALE` ตัวเดียว** → น่าจะ symbol นั้นมีปัญหา → alert คนละแบบ

---

## 6. Acceptance criteria

- [ ] **ข้อมูล P4 หาย → correlation ถูกถือว่า `1.0` ไม่ใช่ `0`** ★★ (ปิด G1)
- [ ] quote หาย → **P3 reject intent** ไม่ใช่ใช้ rate เก่า ★★
- [ ] **`MARKET_CLOSED` ไม่ alert แต่ยัง reject** ★★ §4.3
- [ ] collector ตาย → `STALE` + alert (ไม่ใช่ `MARKET_CLOSED`)
- [ ] `require()` ตรวจ **ทุก symbol ในกลุ่ม** ไม่ใช่แค่ตัวที่จะเทรด ★
- [ ] `detail` บอก symbol + อายุจริง — `grep` หา `"stale data"` เปล่าๆ **ต้องไม่เจอ**
- [ ] collector เพิ่งสตาร์ต → `MISSING` → **reject** ไม่ใช่ปล่อยผ่าน warm-up ★
- [ ] `bar_max_age` เป็น**จำนวน bar** — M1 กับ H4 ให้ผลต่างกัน (มี test)
- [ ] `STALE` ต่อเนื่อง > 5 นาที → นับและเปิดเผยให้ alert ใช้
- [ ] **`grep -rniE "or 0|default=0|fillna\(0\)|correlation = 0" brain/risk/staleness.py`
      — ไม่เจอ** ★★ (ห้ามเดาค่าแทนข้อมูลที่หาย)
- [ ] `python tools/task.py check` ผ่าน (unit test ทั้งหมดใช้ fake collector)
- [ ] `grep -rn "except:" brain/risk/` — ไม่เจอ bare except

## 7. Test list — `tests/test_staleness.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_missing_bars_yields_correlation_one_not_zero` | ★★ **ปิด G1** |
| 2 | `test_stale_quote_rejects_p3` | ★★ |
| 3 | `test_market_closed_rejects_but_does_not_alert` | ★★ §4.3 |
| 4 | `test_collector_dead_is_stale_not_market_closed` | ★★ |
| 5 | `test_missing_offset_is_missing_state` | §4.3 |
| 6 | `test_require_checks_all_symbols_in_group` | ★ §4.5 |
| 7 | `test_require_fails_when_one_group_member_stale` | ★ |
| 8 | `test_detail_contains_symbol_and_age` | §4.5 |
| 9 | `test_cold_start_is_missing_not_fresh` | ★ edge 4 |
| 10 | `test_bar_age_measured_in_bars_not_seconds` | §4.4 |
| 11 | `test_m1_and_h4_thresholds_differ` | |
| 12 | `test_negative_age_treated_as_fresh_with_warning` | edge 5 |
| 13 | `test_fresh_quote_stale_bar_independent` | edge 6 |
| 14 | `test_all_symbols_stale_flags_collector_failure` | edge 7 |
| 15 | `test_gold_daily_break_is_market_closed` | edge 2 |

**test 1 คือเหตุผลทั้งหมดที่ ticket นี้มีอยู่** — ถ้าข้อนี้ผ่าน G1 ถูกปิดจริง

## 8. Files

**Touch:** `brain/risk/staleness.py` · `tests/test_staleness.py`

**ห้ามแตะ:** `brain/collector/**` (อ่าน `freshness()` ได้ ห้ามแก้) · `mt5-ea/**`
· `contracts/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | quote 30 วินาที เหมาะไหม | **ไม่บล็อก** — เริ่มที่นี่ · **นับ `rejects_due_to_stale_data` ตอน soak แล้วรายงาน** ถ้า reject บ่อยผิดปกติแปลว่าเกณฑ์แน่นไป **อย่าปรับเอง** |
| Q2 | `STALE` เกิน 5 นาที ควรถึงขั้น HALT ไหม | **ไม่บล็อก — ตอบแล้ว: ยังไม่ต้อง** · reject ทุก intent มีผลเท่ากับหยุดเทรดอยู่แล้ว · การ HALT เพิ่มจะทำให้ต้องปลดมือโดยไม่จำเป็น · แต่ **ต้อง alert** |
| Q3 | P7/P8 ยังไม่มี (Phase 4) จะเขียนตารางไว้เลยไหม | **เขียนไว้เลย** (§4.1) — ให้ SPEC-042/044 มาต่อได้โดยไม่ต้องออกแบบใหม่ · **แต่ห้าม implement** |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ SPEC-060 merge**

---

## ภาคผนวก — ทำไม `correlation = 0` ถึงเป็น bug ที่มองไม่เห็น

`0` เป็นค่าที่ดู "ว่างเปล่า" และเป็นค่าเริ่มต้นตามธรรมชาติของตัวแปรตัวเลข
· โค้ดที่เขียนว่า `corr = data.get(pair, 0)` ดูสะอาดและไม่มีใครทักท้วง

แต่ในบริบทของ P4 `0` **ไม่ใช่ "ไม่มีข้อมูล"** — มันแปลว่า
***"ยืนยันแล้วว่าสองตัวนี้ไม่เกี่ยวข้องกันเลย"*** ซึ่งเป็นข้อความที่หนักแน่นมาก
และเป็นข้ออ้างที่ทำให้ P4 ยอมให้ถือทั้งสองตัวเต็มขนาดพร้อมกัน

ความเสียหายจึงเกิดตอนที่ข้อมูลหาย **แล้วระบบเทรดหนักขึ้นกว่าปกติ** —
ตรงข้ามกับที่ควรเป็น และไม่มี log บรรทัดไหนบอกว่าเกิดอะไรขึ้น

`1.0` ในทางกลับกันแปลว่า *"สมมติว่าแย่ที่สุด"* ซึ่งทำให้ P4 จำกัดกลุ่มนั้นเป็นก้อนเดียว
· ระบบจะเทรดน้อยลงตอนที่ตาบอด ซึ่งคือสิ่งที่ควรเกิด
