# SPEC-011 — OrderRouter (Target-State Reconciler, Hedging)

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-001, SPEC-010
**Blocks:** SPEC-012, SPEC-016, SPEC-017, SPEC-019
**อ่านก่อน:** [ADR-001 hedging](../decisions/ADR-001-hedging-account.md) · [02-contracts §4.5.1](../02-contracts.md)

> ★ **ticket ที่ยากที่สุดใน Phase 1** — เป็นจุดเดียวในระบบที่ส่ง order ได้
> bug ที่นี่ = เงินหายจริง อ่าน ADR-001 ให้จบก่อนเขียนบรรทัดแรก

---

## 1. Goal

แปลง `INTENT` (net position ที่ต้องการ) ให้เป็นชุด order ที่น้อยที่สุดที่ทำให้
position จริงตรงเป้า บนบัญชี **hedging** โดย idempotent, deterministic และปลอดภัยเมื่อล้มกลางทาง

## 2. Non-goals

- ❌ ไม่มี trading logic / ไม่ตัดสินใจว่าควรเข้า-ออก (brain ตัดสิน)
- ❌ ไม่ implement risk guard (SPEC-019) — ticket นี้แค่**เรียก** `IRiskGuard` ผ่าน interface
- ❌ ไม่ implement dedupe cache (SPEC-012) — เรียกผ่าน interface
- ❌ ไม่รองรับ netting account — `OnInit` fail ถ้าไม่ใช่ hedging (ADR-001)
- ❌ ไม่ใช้ limit/pending order (`urgency: PASSIVE` → ตอบ `REJECTED_INVALID` ใน Phase 1)
- ❌ ไม่ทำ smart order routing / iceberg / TWAP

## 3. Interface

```mql5
// mt5-ea/Include/Farm/OrderRouter.mqh

struct SIntent {
   string   intent_id;
   string   symbol;
   double   target_volume;      // signed: + = long, − = short
   int      max_slippage_points;
   double   sl_price;            // 0.0 = ไม่ตั้ง (แต่ R9 จะ reject)
   double   tp_price;            // 0.0 = ไม่ตั้ง (อนุญาต)
   datetime valid_until;         // broker time
   string   urgency;             // NORMAL | IMMEDIATE | PASSIVE
};

struct SAction {
   string op;         // OPEN | CLOSE | CLOSE_PARTIAL | MODIFY_SLTP | CLOSE_BY
   int    side;       // ORDER_TYPE_BUY | ORDER_TYPE_SELL
   double volume;
   ulong  ticket;     // 0 สำหรับ OPEN
   ulong  ticket_by;  // สำหรับ CLOSE_BY เท่านั้น
};

struct SAckResult {
   string  status;              // ACCEPTED | NOOP | EXPIRED | ...
   string  reason;
   double  volume_before;
   double  volume_target;
   double  volume_clamped_to;   // NaN-equivalent: ใช้ -1 แทน null
   double  overshoot_volume;
   SAction actions[];
};

class COrderRouter {
public:
   bool Init(const string symbol, const int magic,
             CRiskGuard *guard, CWire *wire, CIntentCache *cache);

   // ── ขั้นที่ 1: วางแผน (pure function, ไม่ส่ง order, ไม่แก้ state) ──
   // ต้อง unit test ได้โดยไม่ต้องต่อ broker
   SAckResult Plan(const SIntent &intent, const SPositionSnapshot &snap);

   // ── ขั้นที่ 2: ลงมือ (ส่ง order ตามแผน + EXEC_REPORT ทุก action) ──
   bool Execute(const SIntent &intent, const SAckResult &plan);

   // ── reconcile ตอน OnInit / หลัง reconnect ──
   // ตรวจ anomaly (internal hedge, foreign position) ไม่ปรับ position ตามเป้า
   // เพราะยังไม่รู้เป้า — แค่รายงานสถานะจริงขึ้นไปให้ brain
   bool ReconcileOnStart(SPositionSnapshot &out_snap);

   double OwnedNet() const;              // signed net ของไม้ที่เป็นเจ้าของ
   int    OwnedTicketCount() const;
   bool   HasInternalHedge() const;
};
```

**บังคับแยก `Plan()` ออกจาก `Execute()`** — `Plan()` ต้องเป็น pure function
(input = intent + snapshot, output = แผน) เพื่อให้ทดสอบทุกเคสในตาราง §4 ได้
โดยไม่ต้องมีโบรกเกอร์ นี่คือเงื่อนไขที่ทำให้ ticket นี้ทดสอบได้จริง

## 4. Behaviour — ตารางบังคับ

ให้ `step` = `volume_step` · `min` = `volume_min` · tolerance = `step/2`

### 4.1 กรณีพื้นฐาน

| # | N (owned_net) | T (target) | actions ที่ต้องได้ | status |
|---|---------------|------------|-------------------|--------|
| B1 | 0 | 0 | — | `NOOP` |
| B2 | +0.20 | +0.20 | — | `NOOP` |
| B3 | +0.20 | +0.20000001 | — | `NOOP` (ต่างน้อยกว่า tolerance) |
| B4 | 0 | +0.20 | `OPEN BUY 0.20` | `ACCEPTED` |
| B5 | 0 | −0.20 | `OPEN SELL 0.20` | `ACCEPTED` |
| B6 | +0.20 | +0.30 | `OPEN BUY 0.10` | `ACCEPTED` |
| B7 | −0.15 | −0.25 | `OPEN SELL 0.10` | `ACCEPTED` |
| B8 | +0.20 | +0.12 | `CLOSE_PARTIAL 0.08` จากไม้ FIFO | `ACCEPTED` |
| B9 | +0.20 | 0 | `CLOSE` ทุก ticket long | `ACCEPTED` |
| B10 | +0.20 | −0.10 | `CLOSE 0.20` **แล้ว** `OPEN SELL 0.10` (ลำดับนี้เท่านั้น) | `ACCEPTED` |
| B11 | −0.10 | +0.25 | `CLOSE 0.10` **แล้ว** `OPEN BUY 0.25` | `ACCEPTED` |

### 4.2 FIFO + หลาย ticket

สถานะเริ่ม: ticket A (0.10, เปิด 10:00), ticket B (0.10, เปิด 11:00) → N = +0.20

| # | T | actions | หมายเหตุ |
|---|---|---------|----------|
| F1 | +0.15 | `CLOSE_PARTIAL 0.05` จาก **A** | FIFO — A เก่ากว่า |
| F2 | +0.10 | `CLOSE` **A** ทั้งใบ | พอดี ไม่ต้อง partial |
| F3 | +0.05 | `CLOSE` **A** + `CLOSE_PARTIAL 0.05` จาก **B** | ไล่ตามลำดับ |
| F4 | 0 | `CLOSE A` + `CLOSE B` | |
| F5 | −0.05 | `CLOSE A` + `CLOSE B` + `OPEN SELL 0.05` | flip ต้องปิดหมดก่อน |
| F6 | +0.30 | `OPEN BUY 0.10` | ticket ที่ 3 (ถ้า ≤ R3b) |

ถ้า `time_open` เท่ากันเป๊ะ → tie-break ด้วย **ticket น้อยกว่าก่อน** (deterministic)

### 4.3 SL/TP

| # | สถานะ | intent | actions |
|---|-------|--------|---------|
| S1 | A(sl=1.0800) B(sl=1.0800), N=+0.20 | T=+0.20, sl=1.0850 | `MODIFY_SLTP` ทั้ง A และ B |
| S2 | A(sl=1.0850) B(sl=1.0800), N=+0.20 | T=+0.20, sl=1.0850 | `MODIFY_SLTP` **เฉพาะ B** |
| S3 | A(sl=1.0850) B(sl=1.0850), N=+0.20 | T=+0.20, sl=1.0850 | — → `NOOP` |
| S4 | A(sl=1.0800), N=+0.10 | T=+0.20, sl=1.0850 | `MODIFY_SLTP A` + `OPEN BUY 0.10` (ไม้ใหม่เปิดด้วย sl=1.0850 เลย) |
| S5 | N=0 | T=+0.20, sl=0 | `REJECTED_BY_GUARD` reason `R9_SL_REQUIRED` |
| S6 | N=+0.20 long | T=+0.20, sl **สูงกว่า** ราคาปัจจุบัน | `REJECTED_INVALID` reason `SL_WRONG_SIDE` |

เทียบราคาด้วย tolerance = `point/2` **ห้าม `==`** (S2/S3 จะพังทันทีถ้าใช้ `==`)

### 4.4 Leftover guard (ADR-001 §7)

`volume_min = 0.10`, `step = 0.01`, ticket A = 0.20

| # | T | actions | overshoot |
|---|---|---------|-----------|
| L1 | +0.05 | ต้องลด 0.15 → เหลือ 0.05 < min → **`CLOSE A` ทั้งใบ** | 0.05 |
| L2 | +0.10 | ลด 0.10 → เหลือ 0.10 = min → `CLOSE_PARTIAL 0.10` | 0 |
| L3 | +0.12 | ลด 0.08 → เหลือ 0.12 ≥ min → `CLOSE_PARTIAL 0.08` | 0 |

overshoot = ลด**เกิน**ที่สั่ง = ปลอดภัยกว่า ยอมรับได้ → รายงานใน `INTENT_ACK.overshoot_volume`
**undershoot (ลดไม่ถึงเป้า) ไม่ยอมรับ** — ถ้าเกิดต้อง `ERROR`

### 4.5 Anomaly & rejection

| # | เงื่อนไข | ผลลัพธ์ |
|---|---------|---------|
| A1 | พบไม้ long **และ** short ใน symbol เดียวใต้ magic เดียว | `ANOMALY_INTERNAL_HEDGE` · net ออกทันที (`CLOSE_BY` ถ้ารองรับ ไม่รองรับ = ปิดฝั่งเล็ก) · `ERROR severity:ERROR` · **ไม่ทำ intent นี้** |
| A2 | `valid_until` < `TimeCurrent()` | `EXPIRED` — ห้ามส่ง order ใดๆ |
| A3 | `intent_id` เคยรับแล้ว (จาก `CIntentCache`) | `DUPLICATE` — ห้ามส่ง order |
| A4 | `guard.IsHalted()` | `REJECTED_BY_GUARD` + `halt_reason` |
| A5 | \|T\| > `max_net_volume_per_symbol` | clamp เป็น limit (คงเครื่องหมาย) → `ACCEPTED` + `volume_clamped_to` |
| A6 | actions จะทำให้ ticket เกิน `max_tickets_per_symbol` (R3b) | block + `ERROR severity:ERROR` reason `R3B_TICKET_CAP` (ไม่ควรเกิด = bug) |
| A7 | `SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE)` ไม่ใช่ FULL | `REJECTED_MARKET_CLOSED` |
| A8 | spread ปัจจุบัน > `max_spread_points` และ `urgency != IMMEDIATE` | **defer** — เก็บ intent ไว้ retry ทุก 1s จน spread ปกติ หรือ `valid_until` หมด → `EXPIRED` |
| A9 | `urgency == PASSIVE` | `REJECTED_INVALID` reason `PASSIVE_NOT_IMPLEMENTED` |
| A10 | `target_volume` เป็น NaN / inf / \|T\| > volume_max | `REJECTED_INVALID` + alert (model เพี้ยน) |
| A11 | `T` หลังปัด step แล้วได้ 0 แต่ input ≠ 0 | `REJECTED_INVALID` reason `BELOW_VOLUME_MIN` |
| A12 | `account_margin_mode != RETAIL_HEDGING` | `OnInit` fail — ไม่ถึง Router |

### 4.6 Execute — retry & partial fill

| สถานการณ์ | ทำอะไร |
|-----------|--------|
| `retcode == TRADE_RETCODE_DONE` | `EXEC_REPORT result:FILLED` |
| `REQUOTE` / `PRICE_CHANGED` / `PRICE_OFF` | refresh ราคา retry ≤ 3 ครั้ง backoff 200/400/800ms |
| `INVALID_PRICE` / `INVALID_STOPS` | ปรับตาม `SYMBOL_TRADE_STOPS_LEVEL` retry 1 ครั้ง ไม่ได้ → `REJECTED` |
| slippage จริง > `max_slippage_points` | ถ้ายังไม่ fill = ยกเลิก **ไม่ retry** (R15) · ถ้า fill แล้ว = รายงานตามจริง + alert |
| partial fill (`volume_filled < volume_requested`) | `EXEC_REPORT result:PARTIAL` **ห้ามส่งส่วนที่ขาดเองอัตโนมัติ** — ให้ brain ตัดสิน |
| `NO_MONEY` / `NOT_ENOUGH_MONEY` | `REJECTED` + alert (margin ไม่พอ = เรื่องใหญ่) |
| `TRADE_DISABLED` / `MARKET_CLOSED` | `REJECTED` ไม่ retry |
| `CONNECTION` / `TIMEOUT` | ★ **ห้าม retry ทันที** — ตรวจก่อนว่า order เข้าไปแล้วหรือยัง (ดูข้อ 5.3) |
| flip: `CLOSE` สำเร็จ + `OPEN` ล้ม | `PARTIAL` — อยู่ที่ flat = ปลอดภัย **ห้าม retry `OPEN` หลัง `valid_until` หมด** |
| flip: `CLOSE` ล้ม | **ยกเลิกทั้งแผน ห้ามทำขั้น `OPEN`** (จะกลายเป็น internal hedge ละเมิด R18) |

## 5. Edge cases

1. **ปัด volume ทุกครั้ง** — `MathFloor(v/step + 0.5) * step` แล้ว clamp `[min, max]`
   ห้ามปัดขึ้นเกิน `max_net_volume_per_symbol`
2. **Float ทุกจุดใช้ tolerance** — volume: `step/2` · ราคา: `point/2`
   `NormalizeDouble(v, digits)` ก่อนส่งเสมอ
3. **★ Order เข้าแล้วแต่ ack หาย (network timeout)** — retry จะได้ order ซ้ำ
   ต้อง: (ก) ใส่ `intent_id` ย่อใน `comment` (ข) ก่อน retry ให้สแกน position/deal
   ว่ามี comment นั้นแล้วหรือยัง (ค) มีแล้ว = ถือว่าสำเร็จ ไม่ส่งซ้ำ
   **นี่คือจุดที่ระบบเทรดอัตโนมัติพังบ่อยที่สุด**
4. **EA restart กลางแผน flip** (ปิดแล้วยังไม่เปิด) — `ReconcileOnStart` รายงาน N จริง
   ขึ้นไป **ห้ามเดาว่าต้องเปิดต่อ** brain จะส่ง intent ใหม่เอง
5. **Position ถูกปิดโดย SL/TP ระหว่างที่กำลัง `Plan()`** — snapshot เก่า
   → `Execute()` ต้อง re-check ก่อนส่งแต่ละ action ถ้า ticket หายไปแล้ว = ข้าม action นั้น
   ไม่ใช่ error
6. **Ticket ถูกปิดโดยมือระหว่าง `Execute()`** — เหมือนข้อ 5
7. **`CLOSE_BY` ไม่รองรับ** — ตรวจ `SYMBOL_ORDER_MODE & SYMBOL_ORDER_CLOSEBY` ตอน `OnInit`
   เก็บ capability flag ไม่รองรับ = ปิดฝั่งเล็กด้วย market order
8. **โบรกเกอร์บังคับ FIFO close** — `retcode == TRADE_RETCODE_FIFO_CLOSE`
   → เราปิด FIFO อยู่แล้ว ถ้ายังเจอ = log FATAL + alert (สมมติฐานผิด ต้องคุยกัน)
9. **`freeze_level` — ห้ามแก้/ปิด position ที่ราคาใกล้ SL/TP เกินไป**
   → เจอ `TRADE_RETCODE_INVALID_STOPS` ตอน MODIFY = defer ไว้ลองรอบหน้า ไม่ใช่ error
10. **`stops_level` — SL/TP ต้องห่างราคาปัจจุบันขั้นต่ำ** ปรับให้ผ่านแล้วรายงานว่าปรับ
11. **Symbol ไม่มีใน Market Watch** → `SymbolSelect()` ก่อน ไม่ได้ = `REJECTED_INVALID`
12. **สองไม้เปิดวินาทีเดียวกัน `time_open` เท่ากัน** → tie-break ticket น้อยกว่า (§4.2)
13. **T และ N เครื่องหมายเดียวกันแต่ N = 0** → ไม่ใช่ flip เป็น open ปกติ (B4/B5)
14. **`max_orders_per_minute` (R17) หมดโควตากลางแผน flip** → ยกเลิกส่วนที่เหลือ
    รายงาน `PARTIAL` (ยอมอยู่ flat ดีกว่าฝืนส่ง)

## 6. Acceptance criteria

- [ ] `Plan()` เป็น pure function — ทดสอบทุกแถวใน §4.1–4.5 ได้โดยไม่ต่อ broker
- [ ] ทุกแถวใน §4.1 (B1–B11) มี test และผ่าน
- [ ] ทุกแถวใน §4.2 (F1–F6) มี test และผ่าน
- [ ] ทุกแถวใน §4.3 (S1–S6) มี test และผ่าน
- [ ] ทุกแถวใน §4.4 (L1–L3) มี test และผ่าน
- [ ] ทุกแถวใน §4.5 (A1–A12) มี test และผ่าน
- [ ] **Idempotency:** ส่ง intent เดียวกัน 100 ครั้ง → order เกิดครั้งเดียว (test จริงบน demo)
- [ ] **No-internal-hedge:** ไม่มี test เคสไหนที่จบด้วยไม้ long+short พร้อมกัน
      + มี test ที่จำลอง A1 แล้วยืนยันว่า net ออกได้
- [ ] **Flip atomicity:** จำลอง `OPEN` ล้มหลัง `CLOSE` สำเร็จ → จบที่ flat + `PARTIAL` ไม่ใช่ hedge
- [ ] **Flip ordering:** จำลอง `CLOSE` ล้ม → **ไม่มี `OPEN` ถูกส่ง**
- [ ] **Duplicate-on-timeout:** จำลอง ack หาย → ไม่เกิด order ซ้ำ (edge case 3)
- [ ] `grep` ใน `OrderRouter.mqh`: ไม่มี `==` เทียบ `double` เลย
- [ ] รัน demo 5 วันทำการ: `owned_net` ใน `STATE` ตรงกับ MT5 terminal 100% ทุก snapshot
- [ ] `Plan()` p99 < 5ms (มี 4 ticket)

## 7. Test list

### `tests/mql5/TestOrderRouter.mq5` — Plan() ล้วน (ไม่ต่อ broker)
```
test_plan_B1_flat_to_flat_noop
test_plan_B2_same_volume_noop
test_plan_B3_within_tolerance_noop
test_plan_B4_open_long          test_plan_B5_open_short
test_plan_B6_increase_long      test_plan_B7_increase_short
test_plan_B8_reduce_partial
test_plan_B9_flatten_all
test_plan_B10_flip_long_to_short_order_is_close_then_open
test_plan_B11_flip_short_to_long_order_is_close_then_open
test_plan_F1_fifo_picks_oldest      test_plan_F2_exact_close_no_partial
test_plan_F3_fifo_cascade           test_plan_F4_flatten_multi_ticket
test_plan_F5_flip_closes_all_first  test_plan_F6_adds_third_ticket
test_plan_S1_modify_all_tickets     test_plan_S2_modify_only_mismatched
test_plan_S3_sltp_match_is_noop     test_plan_S4_modify_plus_open
test_plan_S5_missing_sl_rejected    test_plan_S6_sl_wrong_side_rejected
test_plan_L1_leftover_below_min_closes_whole_reports_overshoot
test_plan_L2_leftover_exactly_min_ok
test_plan_L3_leftover_above_min_partial
test_plan_A1_internal_hedge_detected_nets_out
test_plan_A2_expired            test_plan_A3_duplicate
test_plan_A4_halted             test_plan_A5_clamped_keeps_sign
test_plan_A6_ticket_cap_errors  test_plan_A7_market_closed
test_plan_A8_wide_spread_defers test_plan_A9_passive_rejected
test_plan_A10_nan_inf_rejected  test_plan_A11_rounds_to_zero_rejected
test_plan_fifo_tiebreak_by_ticket
test_plan_no_double_equality_on_volume   // property test: fuzz N,T แล้วยืนยัน invariant
```

### Property test (บังคับ)
```
test_prop_plan_is_idempotent        // Plan(intent, snap_after_execute) → NOOP
test_prop_never_produces_both_sides // fuzz 10k เคส: ไม่มีแผนไหนจบด้วย long+short
test_prop_result_net_equals_target_or_overshoot  // ไม่มี undershoot
test_prop_flip_always_close_before_open          // ลำดับใน actions[]
```

### `tests/chaos/test_order_router_live.py` — บน demo จริง
```
test_same_intent_100x_creates_one_order
test_ack_lost_does_not_duplicate       // ตัดเน็ตหลังส่ง
test_ea_restart_midflip_reports_flat
test_position_closed_by_sl_during_execute_skips_action
test_owned_net_matches_terminal_over_5_days
```

**Test ที่ mock `OrderSend` ทั้งหมดไม่นับสำหรับ chaos suite** — ต้องยิงเข้า demo จริง

## 8. Files

**Touch:**
```
mt5-ea/Include/Farm/OrderRouter.mqh
mt5-ea/Include/Farm/PositionSnapshot.mqh    (โครง snapshot + FIFO sort)
mt5-ea/Include/Farm/RiskGuardInterface.mqh  (interface เปล่า — impl อยู่ SPEC-019)
mt5-ea/Include/Farm/IntentCacheInterface.mqh (interface เปล่า — impl อยู่ SPEC-012)
tests/mql5/TestOrderRouter.mq5
tests/chaos/test_order_router_live.py
```

**ห้ามแตะ:** `contracts/schema/**` · `docs/**` · `Wire.mqh` (SPEC-001) · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | default ที่ใช้ได้เลย |
|---|-------|---------------------|
| Q1 | บัญชี netting/hedging | ✅ **ตอบแล้ว: hedging** ([ADR-001](../decisions/ADR-001-hedging-account.md)) |
| Q2 | โบรกเกอร์รองรับ `CLOSE_BY` ไหม | ตรวจ runtime ตอน `OnInit` — รองรับทั้ง 2 ทาง (edge case 7) ไม่ต้องรอคำตอบ |
| Q3 | โบรกเกอร์บังคับ FIFO ไหม | เราปิด FIFO อยู่แล้ว ปลอดภัยทั้ง 2 กรณี (edge case 8) |

**ไม่มีคำถามค้างที่บล็อก ticket นี้ — Codex เริ่มได้เลยหลัง SPEC-010 เสร็จ**
