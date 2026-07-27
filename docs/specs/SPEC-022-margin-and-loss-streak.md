# SPEC-022 — R8 margin level + R14 consecutive loss + halt persistence

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-019, SPEC-021, SPEC-063
**อ้าง:** [risk-spec R8/R14](../03-risk-spec.md)

---

## 1. Goal

กันสองสถานการณ์ที่ต่างกันสิ้นเชิงแต่จบเหมือนกัน:
**มาร์จิ้นใกล้หมด** (บัญชีกำลังจะถูกบังคับปิด) และ **ขาดทุนติดกันหลายไม้**
(กลยุทธ์กำลังไม่เข้ากับตลาด)

## 2. Non-goals

- ❌ ห้าม implement R6/R7 (SPEC-021) — แต่ต้อง**ใช้กลไก persist เดียวกัน** (§4.4)
- ❌ ห้ามคำนวณ P/L ของไม้เอง — อ่านจาก deal history
- ❌ ห้ามส่ง order เอง — เปลี่ยน `Mode()` เท่านั้น

---

## 3. Interface

```mql5
class CMarginGuard        // R8
{
public:
   bool Init(CMarketSnapshot *market, const double min_margin_level_pct);
   bool Evaluate();
   ENUM_FARM_GUARD_MODE Mode() const;   // NORMAL / REDUCE_ONLY
   double MarginLevelPct() const;
};

class CLossStreakGuard    // R14
{
public:
   bool Init(CBrokerTime *clock, const int magic, const string symbol,
             const int max_consecutive_losses,   // 5
             const int halt_hours);              // 4
   bool Evaluate();
   bool     IsHalted() const;
   int      StreakCount() const;
   datetime HaltedUntilUtc() const;
};
```

ไฟล์: `mt5-ea/Include/Farm/MarginGuard.mqh` · `mt5-ea/Include/Farm/LossStreakGuard.mqh`
· `tests/mql5/TestMarginGuard.mq5` · `tests/mql5/TestLossStreakGuard.mq5`

---

## 4. Behaviour

### 4.1 R8 — margin level

```
MarginLevelPct() < min_margin_level_pct (300)  →  REDUCE_ONLY ทันที
กลับสูงกว่าเกณฑ์                              →  NORMAL
```

**ไม่ HALT** — margin ต่ำหมายความว่า *"เปิดเพิ่มไม่ได้แล้ว"* ไม่ใช่ *"ต้องปิดทุกอย่าง"*
· การ flatten ตอน margin ต่ำจะรับรู้ขาดทุนในจังหวะที่แย่ที่สุด

### 4.2 ★★ `MarginLevelPct() == -1` (ไม่มี position) — ห้ามตีความว่าอันตราย

MT5 คืน **0** เมื่อไม่มี position ซึ่ง**กำกวมกับ "margin level 0% = ใกล้ล้างพอร์ต"**
· [SPEC-010 §4.5](SPEC-010-state-reporter.md) จึงให้ `MarketSnapshot` คืน **−1** แทน

| ค่า | ตีความ |
|-----|--------|
| `-1` | **ไม่มี position** → `NORMAL` ★ |
| `0 < x < 300` | อันตราย → `REDUCE_ONLY` |
| `0` **ทั้งที่มี position** | 🔴 ผิดปกติ → `REDUCE_ONLY` + `ERROR` |

**ถ้าตีความ `-1`/`0` ผิด บัญชีที่ว่างเปล่าจะเข้า REDUCE_ONLY แล้วเปิดไม้แรกไม่ได้เลย**
— ระบบจะไม่เทรดอะไรตลอดกาลโดยไม่มีใครรู้ว่าทำไม

### 4.3 R14 — นับไม้ขาดทุนติดกันจาก **deal history**

```
อ่าน deal ที่ magic ตรง + symbol ตรง + entry = DEAL_ENTRY_OUT
เรียงตามเวลา · นับย้อนจากตัวล่าสุด
profit + swap + commission < 0  →  นับเป็น "ขาดทุน"
เจอไม้กำไร  →  รีเซ็ตตัวนับ
streak >= 5  →  HALT 4 ชั่วโมง
```

| กฎ | |
|----|---|
| **ต้องรวม `swap` + `commission`** | ไม้ที่กำไร 0.5 pip แต่จ่าย commission มากกว่า = **ขาดทุนจริง** |
| นับเฉพาะไม้ที่ **ปิดแล้ว** | `DEAL_ENTRY_OUT` เท่านั้น |
| partial close | หลาย deal ต่อ 1 position → **รวมเป็นไม้เดียว** ตาม `position_id` ★ |
| ไม้ที่ปิดโดย flatten (R6/R7) | นับตามปกติ — ก็ขาดทุนจริง |

### 4.4 ★ halt แบบมีเวลาหมดอายุ — persist ทั้งสถานะและ**เวลา**

R14 ต่างจาก R6/R7 ตรงที่ **ปลดเองเมื่อครบ 4 ชั่วโมง**

```
GlobalVariable: farm_streakhalt_until_<magic>_<symbol>  = HaltedUntilUtc (double)
```

| สถานการณ์ | ต้องได้ |
|-----------|---------|
| รีสตาร์ตระหว่าง halt | **ยัง halt อยู่** จนถึงเวลาเดิม ★ |
| ครบเวลา | ปลด · รีเซ็ต streak เป็น 0 |
| `CBrokerTime.IsValid() == false` | **คง halt ไว้** ห้ามปลด (ตัดสินเวลาไม่ได้) ★ |

**เก็บเป็น UTC** — ถ้าเก็บเป็นเวลา broker แล้ว DST เปลี่ยนระหว่าง halt
จะปลดเร็ว/ช้าไป 1 ชั่วโมง

### 4.5 อ่าน history ไม่ได้ = ประเมินไม่ได้ = **ห้ามปล่อยผ่าน**

`HistorySelect()` ล้มเหลว → **คง mode เดิม + WARN** · ห้ามถือว่า streak = 0

ถ้าตีความว่า *"อ่านไม่ได้ = ไม่มีไม้ขาดทุน"* → กฎนี้จะไม่ทำงานเลยในวันที่ history มีปัญหา
ซึ่งเป็นวันเดียวกับที่อย่างอื่นน่าจะมีปัญหาด้วย

### 4.6 อย่าอ่าน history ทุกวินาที

`HistorySelect()` แพง · ระบบเรียก `Evaluate()` ทุก 1 วินาที

| กฎ | |
|----|---|
| อ่านซ้ำเมื่อ | มี `EXEC_REPORT` ที่เป็นการปิดไม้ **หรือ** ครบ 60 วินาที |
| ช่วงที่อ่าน | 7 วันย้อนหลังก็พอ (streak 5 ไม้ไม่มีทางยาวกว่านั้นในทางปฏิบัติ) |
| ถ้าใน 7 วันมีไม้ปิดน้อยกว่า 5 | streak = จำนวนที่มี · ไม่ halt |

---

## 5. Edge cases

1. **ไม่เคยมีไม้ปิดเลย** → streak = 0 · ไม่ halt
2. **ไม้กำไรแทรกกลาง** → รีเซ็ต streak ★
3. **partial close 3 ครั้งของไม้เดียว** → นับเป็น **1 ไม้** ไม่ใช่ 3 ★
4. **ไม้ที่ profit = 0 พอดี** (หลังรวม swap/commission) → **ไม่นับเป็นขาดทุน**
5. **deal ของ magic อื่น** → ข้าม
6. **นาฬิกาเพี้ยนทำให้ `HaltedUntilUtc` อยู่ในอดีตทันที** → ปลดทันที
   → **ต้อง log** ว่าปลดเพราะเวลา ไม่ใช่เพราะครบจริง
7. **halt ของ R14 ซ้อนกับ halt ของ R6/R7** → เข้มที่สุดชนะ · `HaltRule()` รายงานทั้งสอง
8. **margin level ผันผวนรอบเกณฑ์ 300%** → flapping ระหว่าง NORMAL/REDUCE_ONLY
   → ใส่ **hysteresis**: เข้า REDUCE_ONLY ที่ < 300 · ออกที่ > 350 ★

---

## 6. Acceptance criteria

- [ ] **`MarginLevelPct() == -1` → `NORMAL` ไม่ใช่ `REDUCE_ONLY`** ★★
- [ ] `margin = 0` ทั้งที่มี position → `REDUCE_ONLY` + `ERROR`
- [ ] R8 **ไม่ HALT** — แค่ `REDUCE_ONLY`
- [ ] hysteresis 300/350 ทำงาน — ไม่ flap
- [ ] R14 นับ **รวม swap + commission** ★
- [ ] partial close นับเป็น **1 ไม้** ★
- [ ] ไม้กำไรแทรก → รีเซ็ต streak
- [ ] **รีสตาร์ตระหว่าง R14 halt → ยัง halt อยู่จนถึงเวลาเดิม** ★★
- [ ] `HaltedUntilUtc` เก็บเป็น **UTC** — ทดสอบข้าม DST ★
- [ ] `CBrokerTime.IsValid() == false` → **ไม่ปลด halt** ★
- [ ] `HistorySelect()` ล้มเหลว → คง mode เดิม + WARN **ไม่ใช่ streak = 0** ★★
- [ ] ไม่เรียก `HistorySelect()` ทุกวินาที — วัดแล้วรายงาน
- [ ] guard ทั้งสองตัว **ไม่ส่ง order เอง**
- [ ] compile 0 error 0 warning · gate เขียว

## 7. Test list

### `TestMarginGuard.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_no_position_returns_normal` | ★★ §4.2 |
| 2 | `test_zero_margin_with_position_is_error` | |
| 3 | `test_below_threshold_sets_reduce_only` | |
| 4 | `test_never_halts` | §4.1 |
| 5 | `test_hysteresis_prevents_flapping` | ★ edge 8 |

### `TestLossStreakGuard.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 6 | `test_five_losses_halts` | |
| 7 | `test_profit_resets_streak` | ★ edge 2 |
| 8 | `test_commission_makes_small_win_a_loss` | ★★ §4.3 |
| 9 | `test_partial_closes_count_as_one_trade` | ★★ edge 3 |
| 10 | `test_zero_profit_not_counted_as_loss` | edge 4 |
| 11 | `test_other_magic_ignored` | |
| 12 | `test_halt_persists_across_restart` | ★★ §4.4 |
| 13 | `test_halt_releases_after_four_hours` | |
| 14 | `test_halt_until_stored_as_utc_survives_dst` | ★ |
| 15 | `test_invalid_clock_keeps_halt` | ★★ |
| 16 | `test_history_failure_keeps_mode_not_reset` | ★★ §4.5 |

**test 1 · 12 · 16 คือสามตัวที่ห้ามพลาด** — 1 ทำให้ระบบไม่เทรดเลยตลอดกาล
· 12 คือ halt ที่หายตอนรีสตาร์ต · 16 คือกฎที่เงียบไปในวันที่ต้องการมันที่สุด

## 8. Files

**Touch:** `mt5-ea/Include/Farm/{MarginGuard,LossStreakGuard}.mqh`
· `tests/mql5/{TestMarginGuard,TestLossStreakGuard}.mq5`
· `mt5-ea/Include/Farm/RiskGuard.mqh` (`AttachMarginGuard`) · `tools/mql5-suites.json`

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/{BrokerTime,DrawdownGuard}.mqh`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | hysteresis 300/350 เหมาะไหม | **ไม่บล็อก** — เริ่มที่นี่ · รายงานว่า flap กี่ครั้งตอน soak |
| Q2 | ช่วง 7 วันสำหรับอ่าน history พอไหม | **ไม่บล็อก** — ถ้าเทรดถี่กว่านี้มาก 7 วันเหลือเฟือ · ถ้าเทรดน้อยมากจนไม่ถึง 5 ไม้ใน 7 วัน → streak ไม่ครบ ไม่ halt **ซึ่งถูกต้อง** |
