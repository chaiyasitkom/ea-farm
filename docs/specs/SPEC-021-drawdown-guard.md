# SPEC-021 — R6 daily loss + R7 max DD + HWM persistence

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-019, SPEC-063
**อ้าง:** [risk-spec R6/R7](../03-risk-spec.md) · [SPEC-063 §4.6](SPEC-063-broker-time.md)

---

## 1. Goal

หยุดบัญชีก่อนที่ขาดทุนจะลึกเกินรับได้ — และ**หยุดต่อไปแม้ EA ถูกรีสตาร์ต**

## 2. Non-goals

- ❌ ห้าม implement กฎอื่น
- ❌ ห้ามคำนวณเวลาเอง — ต้องผ่าน `CBrokerTime` ([SPEC-063](SPEC-063-broker-time.md))
- ❌ ห้าม flatten เอง — สั่งผ่าน `CRiskGuard` mode เท่านั้น (§4.5)

---

## 3. Interface

```mql5
class CDrawdownGuard
{
public:
   bool Init(CBrokerTime *clock, CMarketSnapshot *market,
             const int magic, const string symbol,
             const double daily_loss_pct,     // R6  2.0
             const double dd_soft_pct,        // R7  6.0
             const double dd_hard_pct);       // R7 10.0

   // เรียกทุก Pump() -- คืน true ถ้าสถานะเปลี่ยน
   bool Evaluate();

   ENUM_FARM_GUARD_MODE Mode() const;   // NORMAL / REDUCE_ONLY / HALT
   bool   IsHalted() const;
   string HaltRule() const;             // "R6" | "R7"
   double EquityHwm() const;
   double DayStartEquity() const;
   double DayPlPct() const;
   double DrawdownPct() const;
};
```

ไฟล์: `mt5-ea/Include/Farm/DrawdownGuard.mqh` · `tests/mql5/TestDrawdownGuard.mq5`

---

## 4. Behaviour

### 4.1 ★★ วัดจาก **equity** ไม่ใช่ closed P/L

```
day_pl_pct = (equity − day_start_equity) / day_start_equity × 100
dd_pct     = (equity_hwm − equity) / equity_hwm × 100
```

ถ้าวัดจาก closed P/L จะ**ทะลุ limit โดยไม่รู้ตัว** เพราะไม้ที่ยังไม่ปิด
ขาดทุนอยู่แต่ไม่ถูกนับ — นี่คือข้อ 1 ใน *"จุดที่ Codex พลาดบ่อย"* ของ risk-spec

`equity` ต้องเป็น `ACCOUNT_EQUITY` ของ**ทั้งบัญชี** รวมไม้ foreign
· **ห้ามใช้ผลรวม `POSITION_PROFIT` ของไม้ที่เป็นเจ้าของ** (ตกไม้ foreign + swap + commission)

### 4.2 ★★ เส้นแบ่งวัน = 00:00 **broker time** ผ่าน `CBrokerTime`

```
วันใหม่  ⟺  BrokerDayStart(now) != BrokerDayStart(last_check)
เมื่อวันใหม่ → day_start_equity = equity ปัจจุบัน · ปลด halt ที่เกิดจาก R6
```

**วันที่ DST เปลี่ยน หน้าต่างวันจะยาว 23 หรือ 25 ชม. — ถูกต้องแล้ว ห้าม "แก้"**
([SPEC-063 §4.6](SPEC-063-broker-time.md)) · ตรงกับที่โบรกเกอร์คิด swap และ rollover

`CBrokerTime.IsValid() == false` → **ห้ามตัดสินว่าวันใหม่** · คงสถานะเดิม + WARN
· ตัดสินผิดจะรีเซ็ต `day_start_equity` กลางวัน = **ล้างขาดทุนที่สะสมมาทั้งวัน**

### 4.3 ★★ ต้อง persist 3 ค่า และต้องรอดการรีสตาร์ต

| ค่า | ถ้าหาย |
|-----|--------|
| `equity_hwm` | DD ดูดีเกินจริง → **ไม่ halt ตอนที่ควร** |
| `day_start_equity` | day P/L รีเซ็ต → ขาดทุนทั้งวันหายไป |
| `halt state` + `halt rule` + `halted_day` | **รีสตาร์ตแล้วเทรดต่อได้ทั้งที่ควร halt** ★ |

เก็บด้วย `GlobalVariableSet()` ชื่อ `farm_<key>_<magic>_<symbol>`
· `GlobalVariable` ของ MT5 **อยู่รอดการรีสตาร์ต terminal** และเก็บได้ 1 `double` ต่อชื่อ

| key | เก็บอะไร |
|-----|----------|
| `hwm` | `double` |
| `daystart` | `double` |
| `daystart_day` | `BrokerDayStart()` เป็น `datetime` (cast เป็น double) |
| `halt_rule` | `0` = ไม่ halt · `6` = R6 · `7` = R7 |
| `halt_day` | วันที่ halt (สำหรับ R6 ที่ปลดตอนขึ้นวันใหม่) |

**อ่านคืนไม่ได้ตอน `Init()`** → ตั้งจากค่าปัจจุบัน + **log WARN** (ไม่ใช่เงียบ)
· `hwm` ที่หายแล้วตั้งใหม่จาก equity ปัจจุบันจะทำให้ DD เริ่มนับใหม่ — ต้องเห็น

### 4.4 R6 daily loss

```
day_pl_pct <= −daily_loss_pct   →  HALT ถึงสิ้นวัน + FLATTEN ทุก position
```

- ปลดเมื่อขึ้นวันใหม่ตาม §4.2 **เท่านั้น** — ห้ามปลดเพราะ equity กลับมา
- `halt_day` ต้อง persist → รีสตาร์ตกลางวันเดิมยัง halt อยู่ ★

### 4.5 R7 max DD — 2 ระดับ

| ระดับ | เกณฑ์ | ทำอะไร | ปลดเมื่อไร |
|-------|-------|--------|-----------|
| soft | `dd_pct ≥ 6.0` | **REDUCE_ONLY** | `dd_pct` กลับต่ำกว่า 6.0 → กลับ NORMAL |
| hard | `dd_pct ≥ 10.0` | **HALT + FLATTEN** | **ปลดด้วยมือเท่านั้น** ★ |

**hard DD ปลดเองไม่ได้** — ถ้าปลดเองตอน equity เด้งกลับ ระบบจะกลับไปเทรดด้วย
กลยุทธ์ที่เพิ่งพิสูจน์ว่าขาดทุน 10% · ต้องมีคนดูก่อน

`equity_hwm` **อัปเดตเฉพาะตอนขึ้น** — `hwm = max(hwm, equity)` ทุก `Evaluate()`

### 4.6 ★ สั่ง flatten อย่างไร — ห้ามส่ง order เอง

`CDrawdownGuard` **ไม่ส่ง order** · มันเปลี่ยน `Mode()` เป็น `FLATTEN`
แล้ว `CRiskGuard`/`OrderRouter` เป็นคนวนปิดทุก ticket

**flatten = วนปิดทุก ticket ไม่ใช่ส่ง order สวน 1 ไม้** —
ส่งสวนจะกลายเป็น internal hedge ละเมิด R18 ทันที
([risk-spec จุดที่พลาดบ่อย ข้อ 8](../03-risk-spec.md))

### 4.7 ลำดับเมื่อชนหลายกฎพร้อมกัน

`HALT` ชนะ `REDUCE_ONLY` ชนะ `NORMAL` · `HaltRule()` รายงานกฎที่**เข้มที่สุด**
· ถ้าชนพร้อมกัน R7-hard ชนะ R6

---

## 5. Edge cases

1. **`Init()` ตอนไม่มี position และ equity = balance** → `hwm = equity` ปกติ
2. **ฝากเงินเพิ่มระหว่างวัน** → equity กระโดดขึ้น → `hwm` ขึ้นตาม · `day_pl` ดูดีเกินจริง
   → **ตรวจไม่ได้จาก equity อย่างเดียว** · log ถ้า `balance` เปลี่ยนโดยไม่มี deal ★
3. **ถอนเงินระหว่างวัน** → เหมือนข้อ 2 แต่จะดู**เหมือนขาดทุน** → อาจ halt ผิด
   → เคสเดียวกัน ต้อง log · **ยอมรับว่า Phase 2 ยังจับไม่ได้** เขียนเป็นหนี้
4. **DST เปลี่ยน** → §4.2 ครอบแล้ว
5. **`equity_hwm` ที่อ่านคืนมาสูงกว่า equity ปัจจุบันมาก** (ผ่านสุดสัปดาห์) → ปกติ
6. **หลาย EA บนบัญชีเดียว** → แต่ละตัวมี `GlobalVariable` ของตัวเอง (key มี magic+symbol)
   แต่ `equity` เป็นของทั้งบัญชี → **ทุกตัวจะ halt พร้อมกัน** ซึ่งถูกต้อง
7. **`GlobalVariable` เต็ม** (MT5 จำกัดจำนวน) → `Init()` fail + FATAL
8. **`daily_loss_pct` หรือ `dd_*_pct` ≤ 0** → `Init()` fail

---

## 6. Acceptance criteria

- [ ] วัดจาก `ACCOUNT_EQUITY` — `grep` ไม่เจอการรวม `POSITION_PROFIT` ★
- [ ] **รีสตาร์ต EA ตอน halt → ยัง halt อยู่** ★★
- [ ] รีสตาร์ต EA → `equity_hwm` ไม่รีเซ็ต ★★
- [ ] ขึ้นวันใหม่ (broker time) → `day_start_equity` รีเซ็ต · R6 halt ปลด
- [ ] **R7 hard halt ไม่ปลดเองแม้ equity กลับมา** ★★
- [ ] R7 soft → `REDUCE_ONLY` · กลับต่ำกว่าเกณฑ์ → กลับ `NORMAL`
- [ ] `CBrokerTime.IsValid() == false` → **ไม่ตัดสินว่าวันใหม่** ★
- [ ] วัน DST 23/25 ชม. ทำงานถูก — มี test
- [ ] อ่าน `GlobalVariable` คืนไม่ได้ → ตั้งใหม่ + **WARN** ไม่ใช่เงียบ
- [ ] `Mode() = FLATTEN` → guard **ไม่ส่ง order เอง** ★
- [ ] `grep -n "TimeCurrent\|TimeGMT\|TimeLocal" mt5-ea/Include/Farm/DrawdownGuard.mqh`
      — ไม่เจอ
- [ ] compile 0 error 0 warning · gate เขียว

## 7. Test list — `tests/mql5/TestDrawdownGuard.mq5`

ใช้ `CMarketSnapshot` + `CBrokerClockSource` ปลอม — **ห้ามรอเวลาจริง**

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_day_pl_from_equity_not_closed_pl` | ★★ §4.1 |
| 2 | `test_r6_halts_at_threshold` | |
| 3 | `test_r6_halt_persists_across_restart` | ★★ §4.3 |
| 4 | `test_r6_releases_on_new_broker_day` | |
| 5 | `test_r6_does_not_release_when_equity_recovers` | ★ |
| 6 | `test_r7_soft_sets_reduce_only` | |
| 7 | `test_r7_soft_releases_when_dd_recovers` | |
| 8 | `test_r7_hard_halts_and_does_not_auto_release` | ★★ §4.5 |
| 9 | `test_hwm_only_increases` | |
| 10 | `test_hwm_persists_across_restart` | ★★ |
| 11 | `test_hwm_read_failure_warns` | §4.3 |
| 12 | `test_new_day_across_dst_23h` | ★ |
| 13 | `test_new_day_across_dst_25h` | ★ |
| 14 | `test_invalid_clock_does_not_roll_day` | ★★ §4.2 |
| 15 | `test_guard_never_sends_orders` | ★ §4.6 |
| 16 | `test_hard_dd_wins_over_r6` | §4.7 |

**test 3 · 8 · 14 คือสามตัวที่ห้ามพลาด** — 3 คือ halt ที่หายตอนรีสตาร์ต
· 8 คือกลับไปเทรดหลังขาดทุน 10% · 14 คือล้างขาดทุนทั้งวันเพราะนาฬิกาเพี้ยน

## 8. Files

**Touch:** `mt5-ea/Include/Farm/DrawdownGuard.mqh` · `tests/mql5/TestDrawdownGuard.mq5`
· `mt5-ea/Include/Farm/RiskGuard.mqh` (เสียบผ่าน `AttachDrawdownGuard`)
· `tools/mql5-suites.json`

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/BrokerTime.mqh`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | ฝาก/ถอนเงินระหว่างวันทำให้ R6/R7 เพี้ยน (edge 2–3) | **ไม่บล็อก** — Phase 2 ยอมรับข้อจำกัดนี้ · **ต้อง log เมื่อ `balance` เปลี่ยนโดยไม่มี deal** และเขียนเป็นหนี้ส่งต่อ · การแก้จริงต้องอ่าน deal history (SPEC-018 มีเครื่องมือแล้ว) |
| Q2 | R7 hard ปลดด้วยมืออย่างไร | **ไม่บล็อก** — ลบ `GlobalVariable` `farm_halt_rule_*` · **ต้องเขียนขั้นตอนใน handoff** เพื่อไปลง runbook SPEC-030b |
