# SPEC-019 — LocalRiskGuard: กรอบ + R2·R3·R4·R5·R9·R10·R11·R12·R15·R17

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-011, SPEC-012, SPEC-063, SPEC-064
**Blocks:** SPEC-020, SPEC-021, SPEC-022, SPEC-023, SPEC-030
**อ้าง:** [03-risk-spec L1](../03-risk-spec.md)

> **นี่คือชั้นที่เงินหาย** — [CLAUDE.md](../../CLAUDE.md) กำหนดให้ review เข้มที่สุดตรงนี้
> ตกข้อเดียวก็ `CHANGES_REQUIRED`

---

## 1. Goal

ด่านสุดท้ายฝั่ง EA ที่ทุกคำสั่งต้องผ่าน · ทำงานได้**แม้ brain ตาย** ·
และเมื่อประเมินไม่ได้ **ให้ปฏิเสธ ไม่ใช่ปล่อยผ่าน**

## 2. Non-goals

- ❌ ห้าม implement R1 lot sizing (**SPEC-020**) — guard เรียกใช้ ไม่ได้เขียนเอง
- ❌ ห้าม implement R6/R7 (SPEC-021) · R8/R14 (SPEC-022) · R13/R16 (SPEC-023)
      — แต่ **ต้องออกแบบกรอบให้เสียบเข้ามาได้** (§3.3)
- ❌ ห้าม implement P1–P11 (SPEC-025) — คนละชั้น
- ❌ ห้ามให้ brain แก้ค่า limit ใดๆ ได้ — ค่ามาจาก **EA input เท่านั้น**
- ❌ ห้ามแตะ `contracts/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `mt5-ea/Include/Farm/RiskGuard.mqh` | **สร้าง** — กรอบ + 10 กฎ |
| `mt5-ea/Include/Farm/MarketSnapshot.mqh` | **สร้าง** — รวบข้อมูลตลาด/บัญชี ณ จุดตัดสิน (§3.4) |
| `mt5-ea/Experts/FarmExecutor.mq5` | **แก้** — เพิ่ม input ครบทุกกฎ (§3.5) |
| `mt5-ea/Include/Farm/OrderRouter.mqh` | **แก้** — เรียก guard ก่อน reconcile |
| `tests/mql5/TestRiskGuard.mq5` | EA test |

### 3.2 ★★ กฎมี 2 ชนิด — ต้องแยกให้ขาดตั้งแต่ออกแบบ

| ชนิด | ประเมินเมื่อไร | ทำอะไรได้ | กฎ |
|------|----------------|-----------|-----|
| **Gate** | ตอนมี `INTENT` เข้ามา | reject / clamp | R1 R2 R3a R3b R4 R5 R9 R10 R11 R15 |
| **Continuous** | **ทุก `Pump()` (1 วินาที)** | HALT · flatten · REDUCE_ONLY | R6 R7 R8 R12 R13 R14 R16 R17 |

**Continuous สำคัญกว่าที่ดู** — ถ้าประเมินเฉพาะตอนมี intent:
- ตลาดวิ่งจนชน max DD แต่ brain ไม่ส่ง intent → **ไม่มีใคร halt**
- ถึงเวลาศุกร์ 20:00 แต่ไม่มี intent → **ไม่มีใคร flatten**
- kill file ถูกวาง แต่ไม่มี intent → **ไม่มีใครหยุด**

R17 (order storm) อยู่ทั้งสองฝั่ง: นับตอนส่ง · ตัดสินตอน gate

### 3.3 API

```mql5
enum ENUM_FARM_GUARD_MODE { FARM_GUARD_NORMAL, FARM_GUARD_SCALED,
                            FARM_GUARD_REDUCE_ONLY, FARM_GUARD_FLATTEN,
                            FARM_GUARD_HALT };

struct FarmGuardVerdict
{
   bool    allow;
   double  clamped_volume;      // ค่าที่อนุญาต (อาจน้อยกว่าที่ขอ)
   bool    was_clamped;
   string  rule_id;             // "R5" ฯลฯ -- ว่างถ้า allow
   string  reason;              // ใส่ลง INTENT_ACK.reason
};

class CRiskGuard
{
public:
   bool Init(const FarmGuardLimits &limits, CBrokerTime *clock,
             CMarketSnapshot *market);

   // ---- Gate: เรียกตอนได้ INTENT ----
   FarmGuardVerdict CheckIntent(const string symbol,
                                const double target_volume,
                                const double sl_price,
                                const double tp_price,
                                const int    max_slippage_points);

   // ---- Continuous: เรียกทุก Pump() ----
   // คืน true ถ้าสถานะเปลี่ยน (caller ต้อง log + ส่ง ERROR/STATE)
   bool Evaluate();

   ENUM_FARM_GUARD_MODE Mode() const;
   bool   IsHalted() const;
   string HaltReason() const;      // rule id
   long   RuleBlockCount(const string rule_id) const;

   // จุดเสียบของ ticket ถัดไป -- ห้ามลบ
   void   AttachDrawdownGuard(CDrawdownGuard *g);   // SPEC-021
   void   AttachMarginGuard(CMarginGuard *g);       // SPEC-022
   void   AttachSafeMode(CSafeMode *s);             // SPEC-023
};
```

### 3.4 ★ `MarketSnapshot` — จุดที่ทำให้ทดสอบได้จริง

guard **ห้ามเรียก `SymbolInfoDouble` / `AccountInfoDouble` ตรงๆ**
→ ต้องผ่าน `CMarketSnapshot` ที่เป็น virtual class

```mql5
class CMarketSnapshot
{
public:
   virtual double Bid(const string symbol);
   virtual double Ask(const string symbol);
   virtual int    SpreadPoints(const string symbol);
   virtual double Equity();
   virtual double Balance();
   virtual double MarginLevelPct();     // -1 = ไม่มี position
   virtual int    OwnedTickets(const string symbol);
   virtual int    TotalOwnedTickets();
   virtual double OwnedNet(const string symbol);
   virtual bool   IsMarketOpen(const string symbol);
};
```

**เหตุผลเดียวกับ `CBrokerClockSource` ใน [SPEC-063](SPEC-063-broker-time.md)** —
ถ้าไม่มี seam นี้ จะทดสอบ *"spread 30 point ตอนเพดาน 25"* ไม่ได้เลย
เพราะควบคุมตลาดจริงไม่ได้ · **test ที่ mock guard เองไม่นับ** แต่ mock ตลาดคือรอยต่อที่ถูก

### 3.5 EA input ที่ต้องเพิ่ม

```mql5
input double InpRiskPerTradePct        = 0.35;   // R1 (SPEC-020 ใช้)
input double InpMaxLotPerOrder         = 0.50;   // R2
input double InpMaxNetVolumePerSymbol  = 0.50;   // R3a
input int    InpMaxTicketsPerSymbol    = 4;      // R3b
input int    InpMaxTotalTickets        = 8;      // R4
input int    InpMaxSpreadPoints        = 0;      // R5 · 0 = ยังไม่ calibrate (§4.6)
input bool   InpRequireSL              = true;   // R9
input double InpMaxSlDistancePct       = 0.5;    // R10
input string InpTradingHours           = "MON_0100_FRI_2000";  // R11
input bool   InpFridayCloseEnabled     = true;   // R12
input int    InpFridayCloseHour        = 20;     // R12
input int    InpMaxSlippagePoints      = 15;     // R15
input int    InpMaxOrdersPerMinute     = 6;      // R17
```

★ **ค่าเหล่านี้ต้องถูกส่งขึ้น `HELLO.local_limits`** — ปิดหนี้จาก
[work-order รอบ 6](../work-order.md) ที่ตอนนี้ยัง hardcode อยู่

---

## 4. Behaviour

### 4.1 ★★ ลำดับ Gate — เรียงจากเด็ดขาดไปหายืดหยุ่น

```
1. HALT อยู่?               → reject R6/R7/R8/R13/R14 (แล้วแต่ตัวที่ halt)
2. mode = REDUCE_ONLY?      → อนุญาตเฉพาะที่ทำให้ |target| < |owned_net|
3. R11 นอกเวลาเทรด          → reject (แต่ยอมให้ "ลด" เสมอ)
4. R9  ไม่มี SL             → reject
5. R10 SL กว้างเกิน         → reject
6. R5  spread เกิน          → reject
7. R1  คำนวณ lot (SPEC-020) → lot < volume_min → reject
8. R2  clamp lot            → clamp ลง
9. R3a clamp net volume     → clamp ลง
10. R3b tickets/symbol เกิน → **block + ERROR** (เป็น bug ไม่ใช่กฎ risk)
11. R4  total tickets เกิน  → reject
12. R17 order rate เกิน     → block + FATAL
→ allow
```

**หลักการ: ทุกกฎที่ "ลดความเสี่ยง" ต้องผ่านได้เสมอ**
คำสั่งที่ทำให้ position เล็กลงหรือปิด **ห้ามถูก block ด้วย R5/R11/R17**
ไม่งั้นเราจะติดอยู่ในไม้ที่ปิดไม่ได้ตอนที่อยากปิดที่สุด

### 4.2 ★★ Clamp ได้เฉพาะทาง "ลง"

```
clamped = sign(target) × min(|target|, limit)
```

**ห้ามยกขึ้นเด็ดขาด** — เป็น bug ที่เคยอยู่ใน risk-spec เอง
([ADR-002 §4](../decisions/ADR-002-symbols-capital-hours.md))

| ต้องได้ | |
|---------|---|
| `target = 0.80` `R2 = 0.50` | → `0.50` · `was_clamped = true` · **ยัง `allow`** |
| `target = -0.80` `R2 = 0.50` | → `-0.50` (รักษาทิศ) |
| `target = 0.005` `volume_min = 0.01` | → **reject** ไม่ใช่ยกเป็น 0.01 ★ |

### 4.3 ★ fail-closed ทุกจุดที่ประเมินไม่ได้

| ประเมินไม่ได้เพราะ | ต้องทำ |
|-------------------|--------|
| `CBrokerTime.IsValid() == false` | reject ทุก intent (R11/R12 ตัดสินไม่ได้) |
| อ่าน spread ไม่ได้ | reject (R5) |
| `symbol` ไม่อยู่ใน registry | reject ([SPEC-064](SPEC-064-symbol-registry.md)) |
| `equity` อ่านไม่ได้ | reject (R1 คำนวณไม่ได้) |
| `MarginLevelPct() == -1` **และ** มี position | reject (ผิดปกติ) |

**เหตุผล:** ทุกกรณีข้างบนแปลว่า *"เราไม่รู้ว่าปลอดภัยไหม"*
· การเทรดตอนไม่รู้ ต่างจากการเทรดตอนรู้ว่าปลอดภัย

### 4.4 R5 spread — วัดตอนตัดสิน ไม่ใช่ค่าเฉลี่ย

```
SpreadPoints(symbol) > InpMaxSpreadPoints  → reject
```

ต้องอ่าน**สดตอนตัดสินใจ** ไม่ใช่ค่าจาก `BAR` (ซึ่งเป็นอดีต)
· **แต่ห้าม block คำสั่งที่ลดขนาด** (§4.1)

### 4.5 R9 / R10 — SL

| กฎ | ตรวจอะไร |
|----|----------|
| R9 | `target_volume ≠ 0` แล้วต้องมี `sl_price` ที่ไม่ใช่ 0/null |
| R9b | **SL ต้องอยู่ฝั่งถูก** — long: `sl < entry` · short: `sl > entry` |
| R9c | ระยะ SL ต้อง ≥ `stops_level` ของ symbol (ไม่งั้นโบรกเกอร์ปฏิเสธ) |
| R10 | `|entry − sl| / entry × 100 > InpMaxSlDistancePct` → reject |

**R9b เป็นข้อที่ risk-spec ไม่ได้เขียนไว้ชัด แต่จำเป็น** — SL ผิดฝั่งคือ
คำสั่งที่โบรกเกอร์จะปฏิเสธ หรือแย่กว่านั้นคือปิดไม้ทันทีที่เปิด

### 4.6 🔴 R5 ตอนที่ยังไม่ calibrate — `InpMaxSpreadPoints = 0`

[ADR-002](../decisions/ADR-002-symbols-capital-hours.md) บอกว่า R5 ต้องมาจากสถิติจริง ≥ 1 สัปดาห์
· [SPEC-064](SPEC-064-symbol-registry.md) เก็บเป็น `null` ไว้ก่อน

| ค่า | พฤติกรรม |
|-----|----------|
| `> 0` | ตรวจปกติ |
| **`0`** | **ข้าม R5 + log WARN ทุกครั้ง** + `production_ready = false` |

**ยอมข้ามได้เฉพาะ demo** — [SPEC-057](../backlog.md) ต้อง block การขึ้น live
ถ้ายังมี symbol ไหน `= 0`

> ทำไมไม่ fail-closed ตรงนี้: ถ้า block ตั้งแต่วันแรกจะเก็บสถิติ spread มา calibrate
> ไม่ได้เลย — **เป็นวงกลม** · จึงบล็อกที่ประตูเงินจริงแทน

### 4.7 R11 / R12 — เวลาต้องมาจาก `CBrokerTime` เท่านั้น

| กฎ | |
|----|---|
| R11 | นอกช่วง `InpTradingHours` → **ไม่เข้าใหม่** แต่ยอมให้ลด/ปิด |
| R12 | ศุกร์ ≥ `InpFridayCloseHour` → **flatten ทุก symbol** (continuous) |

- ต้อง intersect กับ session จริงจาก `SymbolInfoSessionTrade()` ([SPEC-064 §4.5](SPEC-064-symbol-registry.md))
- **ห้าม hardcode ช่วงพักของทอง**
- `grep TimeCurrent|TimeGMT|TimeLocal` ใน `RiskGuard.mqh` ต้อง**ไม่เจอ**

### 4.8 R17 — นับ order ที่ **ส่ง** ไม่ใช่ที่สำเร็จ

```
หน้าต่างเลื่อน 60 วินาที · นับทุกครั้งที่เรียก OrderSend
เกิน InpMaxOrdersPerMinute → block + ERROR severity:FATAL + alert
```

**bug ที่ reject แล้ว retry รัวคือเคสที่กฎนี้มีไว้กัน** — ถ้านับเฉพาะที่สำเร็จ
ลูป retry ที่ล้มเหลวทุกครั้งจะไม่ถูกจับเลย

### 4.9 ทุกครั้งที่ block ต้องบอกได้ว่ากฎไหน

`FarmGuardVerdict.rule_id` = `"R5"` · `reason` = `"R5_SPREAD_TOO_WIDE current=31 max=25"`
→ ใส่ลง `INTENT_ACK.reason` ([intent_ack.json](../../contracts/schema/intent_ack.json))

**reason ต้องมีตัวเลขจริง** — `"spread too wide"` เปล่าๆ debug ไม่ได้

`RuleBlockCount(rule_id)` ขึ้น `STATE`/`HEARTBEAT` → dashboard เห็นว่ากฎไหนทำงานบ่อย

---

## 5. Edge cases

1. **`target_volume = 0` (flatten)** → ข้าม R1/R2/R3a/R5/R9/R10/R11 · **ต้องผ่านเสมอ**
   ยกเว้น R17 · การปิดต้องทำได้ตลอด ★
2. **REDUCE_ONLY + target ที่ลดขนาด** → ผ่าน
3. **REDUCE_ONLY + target ที่กลับทิศ** (`+0.2 → −0.1`) → **reject** — เป็นการเปิดใหม่
4. **HALT + target = 0** → **ผ่าน** (ปิดได้เสมอ) ★
5. **spread กระโดดชั่วขณะ** → reject รอบนั้น · brain ส่งใหม่ได้ · **ห้าม retry เอง**
6. **ตลาดปิด** → `IsMarketOpen = false` → reject การเปิด · การปิดจะล้มเหลวที่โบรกเกอร์เอง
7. **`stops_level = 0`** (โบรกเกอร์ไม่จำกัด) → ข้าม R9c
8. **หลาย symbol ในบัญชีเดียว** → R4 นับรวมทุก symbol ที่ magic ตรง · R3a/R3b นับต่อ symbol
9. **`InpMaxSpreadPoints < 0`** → `Init()` fail
10. **guard ยังไม่ `Init()`** → `CheckIntent` ต้อง reject ไม่ใช่ allow ★

---

## 6. Acceptance criteria

- [ ] ทุกกฎใน §3.2 คอลัมน์ Gate มี test อย่างน้อย 1 ตัว **ที่บล็อกจริง**
- [ ] **`target_volume = 0` ผ่านทุกสถานะ รวม HALT** ★★
- [ ] clamp **ลงเท่านั้น** — `target 0.005` → reject ไม่ใช่ยกเป็น `volume_min` ★★
- [ ] `CBrokerTime.IsValid() == false` → reject ทุก intent ★
- [ ] guard ยังไม่ `Init()` → reject ★
- [ ] `InpMaxSpreadPoints = 0` → ข้าม R5 + WARN (ไม่ใช่ block ทุกอย่าง)
- [ ] SL ผิดฝั่ง → reject (R9b)
- [ ] `reason` มีตัวเลขจริงทุกครั้งที่ block
- [ ] `grep -n "SymbolInfoDouble\|AccountInfoDouble" mt5-ea/Include/Farm/RiskGuard.mqh`
      — **ไม่เจอ** (ต้องผ่าน `MarketSnapshot`) ★
- [ ] `grep -n "TimeCurrent\|TimeGMT\|TimeLocal" mt5-ea/Include/Farm/RiskGuard.mqh`
      — **ไม่เจอ** ★
- [ ] `HELLO.local_limits` ส่งค่าจาก **EA input จริง** ไม่ใช่ค่าคงที่ ★
      (ปิดหนี้ [work-order รอบ 6](../work-order.md))
- [ ] R17 นับ order ที่ **ส่ง** — test ด้วยลูป reject 10 ครั้งใน 10 วินาที
- [ ] compile 0 error 0 warning · gate เขียว

## 7. Test list — `tests/mql5/TestRiskGuard.mq5`

**ใช้ `CMarketSnapshot` ปลอมทั้งหมด** — ห้าม mock `CRiskGuard` เอง

| # | test | กฎ |
|---|------|-----|
| 1 | `test_flatten_always_allowed_even_when_halted` | ★★ edge 1/4 |
| 2 | `test_reduce_allowed_in_reduce_only` | |
| 3 | `test_flip_rejected_in_reduce_only` | edge 3 |
| 4 | `test_clamp_reduces_never_raises` | ★★ R2 |
| 5 | `test_below_volume_min_rejects_not_clamps` | ★★ R1 |
| 6 | `test_clamp_preserves_sign` | R2 |
| 7 | `test_net_volume_clamped` | R3a |
| 8 | `test_tickets_per_symbol_blocks_with_error` | R3b |
| 9 | `test_total_tickets_rejects` | R4 |
| 10 | `test_spread_over_limit_rejects` | R5 |
| 11 | `test_spread_limit_zero_skips_with_warning` | ★ R5 §4.6 |
| 12 | `test_spread_does_not_block_reduction` | ★ §4.1 |
| 13 | `test_missing_sl_rejects` | R9 |
| 14 | `test_sl_wrong_side_rejects` | ★ R9b |
| 15 | `test_sl_inside_stops_level_rejects` | R9c |
| 16 | `test_sl_distance_over_pct_rejects` | R10 |
| 17 | `test_outside_trading_hours_rejects_open` | R11 |
| 18 | `test_outside_trading_hours_allows_close` | ★ R11 |
| 19 | `test_friday_close_triggers_flatten` | R12 continuous |
| 20 | `test_order_rate_counts_sent_not_filled` | ★★ R17 |
| 21 | `test_invalid_clock_rejects_everything` | ★★ §4.3 |
| 22 | `test_uninitialised_guard_rejects` | ★ edge 10 |
| 23 | `test_reason_contains_numbers` | §4.9 |
| 24 | `test_rule_block_counts_accurate` | |

**test 1 · 4 · 5 · 21 คือสี่ตัวที่ห้ามพลาด** — 1 คือความสามารถในการปิดไม้
· 4/5 คือ bug เดิมของ risk-spec · 21 คือ fail-closed

## 8. Files

**Touch:** `mt5-ea/Include/Farm/{RiskGuard,MarketSnapshot}.mqh`
· `mt5-ea/Include/Farm/OrderRouter.mqh` · `mt5-ea/Experts/FarmExecutor.mq5`
· `tests/mql5/TestRiskGuard.mq5` · `tools/mql5-suites.json`

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/{Wire,BrokerTime}.mqh`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `InpTradingHours` เป็น string แบบ `MON_0100_FRI_2000` — parse เองหรือใช้รูปแบบอื่น | **ไม่บล็อก** — ใช้รูปแบบนี้ตาม [SPEC-064](SPEC-064-symbol-registry.md) · ถ้าต้องการรูปแบบซับซ้อนกว่า → implementation note |
| Q2 | R3b เกินแล้ว "block + ERROR" ควรถึงขั้น halt ไหม | **ไม่บล็อก — ตอบแล้ว: ไม่ halt** · เป็น anti-bug guard ไม่ใช่กฎ risk · block + `ERROR severity:ERROR` + alert พอ |

> **ไม่มีคำถามที่บล็อก**

---

## ภาคผนวก — ทำไม "ปิดได้เสมอ" ถึงเป็นกฎที่สำคัญที่สุด

กฎ risk ทุกข้อออกแบบมาเพื่อ**จำกัดการเปิด** — แต่ถ้าเขียนไม่ระวัง มันจะจำกัด**การปิด**ไปด้วย

ลองนึกภาพ: spread กระโดดเพราะข่าว → R5 block ทุกคำสั่ง → รวมทั้งคำสั่งปิดไม้ที่กำลังขาดทุน
→ เราติดอยู่ในไม้นั้นจนกว่า spread จะกลับมาปกติ ซึ่งอาจเป็นตอนที่ราคาไปไกลแล้ว

หรือ: ชน max DD → HALT → แต่ HALT ดันบล็อก `target_volume = 0` ด้วย
→ **halt แล้วปิดไม้ไม่ได้** ซึ่งตรงข้ามกับเจตนาของ HALT ทั้งหมด

`test 1` มีไว้เพื่อกันเรื่องนี้โดยเฉพาะ · และเป็นเหตุผลที่ §4.1 เขียนหลักการ
*"ทุกกฎที่ลดความเสี่ยงต้องผ่านได้เสมอ"* ไว้เป็นข้อความชัดๆ ไม่ใช่ปล่อยให้อนุมานเอง
