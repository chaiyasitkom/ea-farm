# SPEC-020 — R1 Lot sizing + currency conversion

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-019, SPEC-064
**อ้าง:** [risk-spec §สูตรคำนวณ lot](../03-risk-spec.md) · [ADR-002 §4](../decisions/ADR-002-symbols-capital-hours.md)

---

## 1. Goal

คำนวณ lot จาก **ความเสี่ยงที่ยอมรับได้** ไม่ใช่จากตัวเลขที่ brain ส่งมา
· และแปลงสกุลเงินให้ถูกสำหรับคู่ที่ quote ≠ สกุลบัญชี

## 2. Non-goals

- ❌ ห้าม implement กฎอื่น (SPEC-019/021/022/023)
- ❌ ห้ามตัดสินใจทิศทาง — รับ `target_volume` มาแล้วบอกว่า**อนุญาตเท่าไร**
- ❌ ห้าม hardcode contract spec ใดๆ ([ADR-002 §2.6](../decisions/ADR-002-symbols-capital-hours.md))

---

## 3. Interface

```mql5
struct FarmLotResult
{
   bool   ok;              // false = ต้อง reject intent
   double lot;
   double risk_money;      // ที่คำนวณได้ -- ใส่ลง EXEC_REPORT ตอน reject
   double raw_lot;         // ก่อนปัด -- ใส่ลง reason
   string reject_reason;   // "R1_RISK_TOO_SMALL_FOR_MIN_LOT" ฯลฯ
};

class CLotSizer
{
public:
   bool Init(CMarketSnapshot *market);

   FarmLotResult Compute(const string symbol,
                         const double equity,
                         const double risk_pct,
                         const double entry_price,
                         const double sl_price,
                         const double max_lot_per_order);

   // แปลง tick_value เป็นสกุลบัญชี -- แยกออกมาเพื่อทดสอบได้เดี่ยว
   double ValuePerPointAccountCcy(const string symbol, bool &ok);
};
```

ไฟล์: `mt5-ea/Include/Farm/LotSizer.mqh` · `tests/mql5/TestLotSizer.mq5`

---

## 4. Behaviour

### 4.1 ★★ สูตร — ลำดับ 2 บรรทัดสุดท้ายห้ามสลับ

```
risk_money      = equity × risk_pct / 100
sl_distance_pts = |entry − sl| / point
value_per_point = ValuePerPointAccountCcy(symbol)        // §4.2
raw_lot         = risk_money / (sl_distance_pts × value_per_point)
lot             = floor(raw_lot / volume_step) × volume_step

if lot < volume_min → ok = false                          ← ★ ก่อน clamp
      reject_reason = "R1_RISK_TOO_SMALL_FOR_MIN_LOT"

lot = min(lot, volume_max, max_lot_per_order)             ← clamp ลงเท่านั้น
```

**เป็น bug ที่เคยอยู่ใน risk-spec เอง** — `clamp(lot, volume_min, …)` มาก่อน
ทำให้บรรทัดเช็คเป็น dead code แล้วเปิดไม้เกิน R1 ได้เท่าไรก็ได้ **อย่างเงียบสนิท**
([ADR-002 §4](../decisions/ADR-002-symbols-capital-hours.md))

ที่ทุน $30 บน standard account: bug นี้จะเปิด 0.01 lot เสี่ยงจริง **6.7%** (EURUSD)
ถึง **16.7%** (ทอง) แทนที่จะ reject

### 4.2 ★★ Currency conversion — 2 ใน 6 คู่เข้าเคสนี้

บัญชี USD · `value_per_point` = มูลค่า 1 point ต่อ 1 lot **ในสกุลบัญชี**

| กลุ่ม | symbol | วิธี |
|-------|--------|------|
| quote = สกุลบัญชี | `EURUSD` `GBPUSD` `AUDUSD` `XAUUSD` | `tick_value × (point / tick_size)` ใช้ตรงได้ |
| **quote ≠ สกุลบัญชี** | **`USDJPY`** (→JPY) · **`USDCAD`** (→CAD) | ต้องแปลง |

**⚠️ `SYMBOL_TRADE_TICK_VALUE` ของ MT5 คืนค่าในสกุลบัญชีอยู่แล้ว** —
แต่มัน **เปลี่ยนตามอัตราแลกเปลี่ยนตลอดเวลา**

| กฎ | |
|----|---|
| **อ่านสดทุกครั้งที่คำนวณ** | ★ ห้าม cache · ห้ามอ่านครั้งเดียวตอน `OnInit` |
| `tick_value ≤ 0` | → `ok = false` reason `R1_TICK_VALUE_UNAVAILABLE` **ห้ามเดา** |
| ตรวจความสมเหตุสมผล | คำนวณ `contract_size × point` แล้วเทียบกับ `tick_value` · ต่างกันเกิน 100 เท่า = ผิดปกติ → reject + log |

**ข้อสุดท้ายสำคัญ** — `tick_value` ที่ผิด (โบรกเกอร์ส่งค่าเพี้ยนตอน market ปิด)
จะทำให้คำนวณ lot ผิดเป็นร้อยเท่าโดยไม่มีอะไรฟ้อง

### 4.3 `risk_pct` มาจาก EA input เท่านั้น

`InpRiskPerTradePct` — **brain แก้ไม่ได้** · `CONFIG_UPDATE` ก็แก้ไม่ได้
([config_update.json](../../contracts/schema/config_update.json) กฎเหล็ก)

### 4.4 `equity` ต้องเป็นของทั้งบัญชี

รวมไม้ foreign ด้วย ([ADR-001](../decisions/ADR-001-hedging-account.md)) —
ไม้ของคนอื่นกินมาร์จิ้นและกระทบ equity จริง

### 4.5 `raw_lot < volume_min` คือสถานะปกติที่ทุนน้อย

[ADR-002 §3](../decisions/ADR-002-symbols-capital-hours.md): ที่ทุน $30 standard
**ทุก intent จะถูก reject ด้วยเหตุผลนี้**

→ **ห้ามมองว่าเป็น bug · ห้าม "แก้" ให้มันผ่าน** · แต่ต้อง log ให้ชัดพร้อมตัวเลข
เพื่อให้เห็นว่าต้องเพิ่มทุนเท่าไร:

```
R1_RISK_TOO_SMALL_FOR_MIN_LOT equity=30.00 risk_money=0.105
  raw_lot=0.000525 volume_min=0.01 need_equity≈571
```

---

## 5. Edge cases

1. **`sl_distance_pts = 0`** (SL = entry) → `ok = false` **ห้ามหารศูนย์**
2. **`point = 0`** → reject (spec เพี้ยน)
3. **`volume_step = 0`** → reject
4. **`equity ≤ 0`** → reject
5. **`risk_pct ≤ 0` หรือ `> 5`** → `Init()` fail (5% ต่อไม้เป็นเพดานความสมเหตุสมผล)
6. **`volume_max < volume_min`** → reject (spec เพี้ยน)
7. **`raw_lot` ใหญ่กว่า `volume_max`** → clamp ลง · ไม่ใช่ reject
8. **ตลาดปิด `tick_value` เป็น 0** → reject (§4.2) ไม่ใช่ใช้ค่าเก่า
9. **`floor` แล้วได้ 0 พอดี** → reject (เคสเดียวกับ §4.5)

---

## 6. Acceptance criteria

- [ ] **`raw_lot < volume_min` → reject ไม่ใช่ยกเป็น `volume_min`** ★★
- [ ] clamp **ลงเท่านั้น** — ไม่มี code path ไหนที่ทำให้ lot ใหญ่ขึ้น ★★
- [ ] test conversion ครบ **3 เคส: `USDJPY` · `USDCAD` · `XAUUSD`** ★
      (สองตัวแรก = quote ≠ USD · ตัวหลัง = contract 100 oz ไม่ใช่ 100,000)
- [ ] `tick_value` อ่าน**สด**ทุกครั้ง — `grep` ไม่เจอการ cache ★
- [ ] `tick_value ≤ 0` → reject **ไม่ใช่ใช้ค่าเก่า**
- [ ] `tick_value` ผิดปกติเกิน 100 เท่าของที่คาด → reject + log
- [ ] `sl_distance = 0` → reject ไม่ crash
- [ ] reason มี `equity` `risk_money` `raw_lot` `volume_min` `need_equity` ครบ ★
- [ ] `grep -n "0.01\|100000\|1.0" mt5-ea/Include/Farm/LotSizer.mqh`
      — **ไม่มีค่า contract spec hardcode** ★
- [ ] ผลตรงกับ `brain/strategies/sizing.py` ([SPEC-015](SPEC-015-ema-baseline.md))
      บน fixture ชุดเดียวกัน — **รายงานว่าเทียบแล้วตรงกี่เคส** ★

## 7. Test list — `tests/mql5/TestLotSizer.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_basic_lot_from_risk` | สูตรพื้นฐาน |
| 2 | `test_rejects_below_volume_min` | ★★ ลำดับ |
| 3 | `test_clamp_never_raises_lot` | ★★ |
| 4 | `test_respects_volume_step_floor` | ปัดลง ไม่ใช่ปัดใกล้สุด |
| 5 | `test_usdjpy_conversion` | ★ quote = JPY |
| 6 | `test_usdcad_conversion` | ★ quote = CAD |
| 7 | `test_xauusd_contract_100oz` | ★ contract ไม่ใช่ 100,000 |
| 8 | `test_zero_sl_distance_rejects` | edge 1 |
| 9 | `test_zero_tick_value_rejects` | ★ edge 8 |
| 10 | `test_absurd_tick_value_rejects` | ★ §4.2 |
| 11 | `test_negative_equity_rejects` | edge 4 |
| 12 | `test_risk_pct_out_of_range_fails_init` | edge 5 |
| 13 | `test_reject_reason_contains_need_equity` | §4.5 |
| 14 | `test_lot_at_30usd_equity_rejects_all_six_symbols` | ★ ADR-002 §3 — **ยืนยันว่าสถานะปัจจุบันเป็นแบบนี้จริง** |

**test 14 ไม่ใช่ test ที่คาดหวังให้ "ผ่าน" ในความหมายปกติ** — มันยืนยันว่าที่ทุนปัจจุบัน
ระบบจะปฏิเสธทุกอย่าง ซึ่งคือ**พฤติกรรมที่ถูกต้อง** และเป็นหลักฐานว่า D5 ยังไม่ปิด

## 8. Files

**Touch:** `mt5-ea/Include/Farm/LotSizer.mqh` · `tests/mql5/TestLotSizer.mq5`
· `tools/mql5-suites.json`

**ห้ามแตะ:** `contracts/**` · `docs/**` · `brain/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | เกณฑ์ "ต่างกันเกิน 100 เท่า" ของ `tick_value` เหมาะไหม | **ไม่บล็อก** — เริ่มที่นี่ · รายงานว่าเจอกี่ครั้งตอน soak |
| Q2 | จะเทียบกับ `sizing.py` อย่างไร (fixture ร่วม?) | **ไม่บล็อก** — เสนอมาใน handoff · แนวคิดเดียวกับ cross-check ของ [SPEC-064](SPEC-064-symbol-registry.md) |
