# SPEC-017 — Position reconciliation ตอน `OnInit`

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-010, SPEC-011, SPEC-063 · **Blocks:** Phase 1 exit criteria
**อ้าง:** [ADR-001](../decisions/ADR-001-hedging-account.md) · [roadmap Phase 1](../04-roadmap.md) exit

---

## 1. Goal

EA ที่กลับมาหลังตาย/รีสตาร์ต ต้องรู้ว่าตัวเองถืออะไรอยู่จริง **รายงานความจริงขึ้นไป**
และตรวจเจอความผิดปกติที่เกิดขึ้นตอนที่มันไม่อยู่

## 2. Non-goals

- ❌ **ห้าม EA ตัดสินใจปิด/เปิด position เอง** — ยกเว้นกรณีเดียวใน §4.3
- ❌ ห้าม EA พยายาม "กู้ target เดิม" — มันไม่รู้ว่า target คืออะไรและตลาดเดินไปแล้ว
- ❌ ห้าม implement dedupe cache (SPEC-012) — แต่ต้องอ่าน §4.5 ให้เข้าใจก่อน
- ❌ ห้าม implement R9 บังคับ SL (SPEC-019) — ticket นี้แค่**ตรวจเจอและรายงาน** (§4.4)
- ❌ ห้ามแตะ `contracts/schema/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `mt5-ea/Include/Farm/Reconciler.mqh` | **สร้าง** |
| `mt5-ea/Experts/FarmExecutor.mq5` | **แก้** — เรียกใน `OnInit` |
| `mt5-ea/Include/Farm/StateReporter.mqh` | **แก้** — ส่ง STATE ทันทีตอน READY (§4.2) |
| `tests/mql5/TestReconciler.mq5` | EA test |
| `tests/chaos/test_reconcile.py` | ใช้ harness ของ [SPEC-016](SPEC-016-chaos-harness.md) ชั้น B |

### 3.2 API

```mql5
struct FarmReconcileResult
{
   int    owned_tickets;          // ไม้ที่เป็นเจ้าของ (magic + symbol ตรง)
   double owned_net;              // + = long, − = short
   int    foreign_tickets;        // ไม้ที่ไม่ใช่ของเรา
   bool   internal_hedge;         // ★ long+short พร้อมกัน = ANOMALY
   int    positions_without_sl;   // ★ R9 จะบังคับตอน SPEC-019
   bool   exceeds_ticket_limits;  // เกิน R3b/R4
   bool   mt5_sync_incomplete;    // ★ ดู §4.1
};

class CReconciler
{
public:
   // เรียกใน OnInit หลัง CBrokerTime แต่ก่อน wire.Init()
   // คืน false เฉพาะกรณีที่ไม่ควรเริ่มทำงานเลย (§4.1)
   bool Reconcile(const int magic, const string symbol,
                  CBrokerTime *clock, FarmReconcileResult &out);

   string LastError() const;
};
```

---

## 4. Behaviour

### 4.1 ★ MT5 ยังไม่ sync position ตอน `OnInit` — กับดักที่ทำให้รายงานผิด

ตอน terminal เพิ่งเปิด `PositionsTotal()` อาจคืน **0 ทั้งที่มี position อยู่จริง**
เพราะยังไม่ได้ sync กับเซิร์ฟเวอร์

**ถ้าเชื่อค่านั้น EA จะรายงานว่า "ไม่มีอะไรเลย" → brain คิดว่า flat →
ส่ง intent เปิดใหม่ → กลายเป็นสองเท่าของที่ตั้งใจ**

**ต้องทำ:**

| ขั้น | |
|------|---|
| 1 | รอจนกว่า `TerminalInfoInteger(TERMINAL_CONNECTED)` เป็น true |
| 2 | อ่าน `PositionsTotal()` **ซ้ำ 3 ครั้ง ห่างกัน 500 ms** — ต้องได้ค่าเท่ากันทั้ง 3 ครั้ง |
| 3 | ไม่นิ่งภายใน **10 วินาที** → `mt5_sync_incomplete = true` |
| 4 | `mt5_sync_incomplete` → **`OnInit` คืน `INIT_FAILED`** + log FATAL |

**ยอมไม่สตาร์ท ดีกว่าสตาร์ทแล้วรายงานภาพที่ไม่จริง**

### 4.2 ★ ลำดับตอนกลับมา — STATE ต้องมาก่อนทุกอย่าง

```
OnInit
  ├─ CBrokerTime.Init()
  ├─ CReconciler.Reconcile()        ← ต้องผ่านก่อนถึงจะต่อ wire
  └─ wire.Init()
        │
   READY (ได้ HELLO_ACK)
        │
        ├─ 1. ส่ง STATE ทันที        ← ★ ก่อน backfill ก่อนทุกอย่าง
        ├─ 2. ส่ง ERROR ถ้ามี anomaly (§4.3/§4.4)
        ├─ 3. backfill 300 bar       (SPEC-010 §4.1)
        └─ 4. เข้าจังหวะปกติ
```

**เหตุผล:** ระหว่างที่ EA ตาย brain อาจส่ง INTENT ที่ไม่มีใครรับ → ภาพในหัว brain เก่าแล้ว
· STATE ตัวแรกคือสิ่งเดียวที่แก้ภาพนั้นได้

**กฎที่ผูกไปถึง brain (บันทึกให้ SPEC-013/025):**
**ห้ามส่ง INTENT ให้ session ที่ยังไม่เคยส่ง STATE มาเลย** — ต้องรอ STATE ตัวแรกก่อนเสมอ

### 4.3 ★★ Internal hedge — **กรณีเดียวที่ EA ลงมือเอง**

พบไม้ long และ short ของ symbol เดียวกันใต้ magic เดียวกัน = ละเมิด R18

| | |
|---|---|
| ทำอะไร | **net ออกทันที** — ใช้ `CLOSE_BY` ถ้า `order_mode_closeby` รองรับ ไม่งั้นปิดฝั่งที่เล็กกว่าด้วย market order |
| ส่งอะไร | `ERROR severity:ERROR code:ANOMALY_INTERNAL_HEDGE` + `STATE.guard.internal_hedge_detected = true` |
| ทำก่อนหรือหลัง READY | **หลัง READY** — ต้องรายงานให้ brain รู้ก่อนลงมือ |

**ทำไมกรณีนี้ EA ลงมือได้ แต่กรณีอื่นห้าม:**
internal hedge **ไม่มีทางถูกต้องเลยไม่ว่ากลยุทธ์ไหน** — exposure สุทธิเท่าเดิม
แต่จ่าย spread 2 ขา + swap 2 ขา · การ net ออกจึงลดต้นทุนโดยไม่เปลี่ยน exposure
= **การกระทำที่ปลอดภัยเสมอ** ต่างจากการปิด/เปิด position ที่เปลี่ยน exposure จริง

### 4.4 Position ที่ไม่มี SL — ตรวจเจอ รายงาน **ยังไม่แก้**

R9 บังคับว่าทุก position ต้องมี SL แต่ EA ที่ตายกลางคันอาจทิ้งไม้ที่ยังไม่ได้ตั้ง SL

**ticket นี้: นับ + รายงาน + `ERROR severity:ERROR code:POSITION_WITHOUT_SL`**
พร้อม ticket number ทุกใบ

**ยังไม่ตั้ง SL ให้เอง** เพราะ EA ไม่รู้ว่า brain ต้องการ SL ที่ไหน
· การตั้ง SL มั่วอาจปิดไม้ที่กลยุทธ์ยังต้องการ

> 🔴 **ช่องว่างที่ยอมรับชั่วคราว:** ระหว่างรีสตาร์ตถึงตอนที่ brain ตอบ position นั้นไม่มีการป้องกัน
> **ยอมได้เฉพาะ Phase 1 ที่เป็น demo ล้วน** ([D5](../backlog.md))
> **เส้นตาย: ต้องปิดก่อนเงินจริง** — SPEC-019/023 ตัดสินว่าจะตั้ง emergency SL
> ที่ระยะ R10 หรือ flatten · **ห้ามขึ้น live โดยที่ข้อนี้ยังค้าง**

### 4.5 ★★ ทำไม dedupe cache **ไม่ต้อง** รอดข้ามรีสตาร์ต

สถานการณ์ที่ดูน่ากลัว:
```
brain ส่ง INTENT id=X  →  EA ทำสำเร็จ  →  EA ตายก่อนส่ง INTENT_ACK
brain ไม่ได้ ack  →  ส่ง X ซ้ำ  →  EA กลับมาโดยไม่มี cache  →  ทำซ้ำ → position สองเท่า?
```

**ไม่เกิด — เพราะ `INTENT` เป็น target-state ไม่ใช่คำสั่ง**

รอบสอง reconciler จะเห็น `N = 0.20` และ `T = 0.20` → **NOOP ไม่ส่ง order**
([contract §4.5.1](../02-contracts.md) แถวแรก)

**นี่คือผลตอบแทนของการเลือก target-state ตั้งแต่ต้น** — และเป็นเหตุผลที่
[AGENTS ข้อ 12](../../AGENTS.md) ห้ามเปลี่ยนเป็น imperative order command

| สิ่งที่ยังต้องมี | สิ่งที่ **ไม่** ต้องมี |
|-----------------|----------------------|
| dedupe cache ในหน่วยความจำ (SPEC-012) เพื่อตอบ `DUPLICATE` และไม่ทำงานซ้ำโดยเปล่าประโยชน์ | **การ persist cache ลงดิสก์** — ไม่ได้ให้ความปลอดภัยเพิ่ม |

⚠️ **ข้อยกเว้นเล็กที่ต้องรู้:** ถ้ารอบแรก fill ได้ 0.19 จาก 0.20 (partial/slippage)
รอบสองจะเติมอีก 0.01 — **นั่นคือพฤติกรรมที่ถูกต้อง** (แก้ให้ตรง target)
ไม่ใช่ order ซ้ำ · **ห้ามไป "แก้" ให้มันไม่ทำ**

### 4.6 สิ่งที่ต้อง persist จริงๆ (ไม่ใช่ position)

| ค่า | เจ้าของ ticket | ทำไมต้อง persist |
|-----|----------------|------------------|
| `equity_hwm` | SPEC-010 §4.6 | R7 max DD วัดจาก HWM · รีเซ็ต = DD ดูดีเกินจริง |
| `day_start_equity` | SPEC-010 §4.6 | R6 daily loss |
| halt state | SPEC-022 | รีสตาร์ตแล้วต้องยัง halt อยู่ถ้ายังในวันเดียวกัน |
| **position** | — | ❌ **ห้าม persist** — MT5 คือแหล่งความจริง อ่านสดทุกครั้ง |

การเก็บ position ไว้ในไฟล์แล้วเชื่อมันตอนรีสตาร์ต = **สร้างแหล่งความจริงที่สอง**
ซึ่งจะไม่ตรงกับ MT5 วันใดวันหนึ่งแน่นอน

### 4.7 Ownership — ต้องตรงทั้งสองเงื่อนไข

```
เป็นของเรา  ⟺  POSITION_MAGIC == magic  &&  POSITION_SYMBOL == symbol
```
ขาดข้อใดข้อหนึ่ง = **ไม่ใช่ของเรา** → นับเป็น `foreign` ([ADR-001](../decisions/ADR-001-hedging-account.md))

magic ตรงแต่ symbol ไม่ตรง = EA ตัวอื่นในฟาร์มที่ใช้ magic เดียวกันคนละ symbol — **ห้ามแตะ**

---

## 5. Edge cases

1. **ไม่มี position เลย** → ปกติ ไม่ใช่ anomaly · `owned_net = 0`
2. **มีแต่ไม้ foreign** → รายงานใน `STATE.foreign_positions` + WARN · ทำงานต่อได้
3. **`PositionsTotal()` เปลี่ยนระหว่างวนอ่าน** (มีไม้ปิดพอดี) → อ่านใหม่ทั้งรอบ ไม่ใช่ใช้ข้อมูลผสม
4. **ticket เดียวกันปรากฏสองครั้ง** → ไม่ควรเกิด · ถ้าเกิด = FATAL
5. **`PositionSelectByTicket` ล้มเหลวกลางทาง** → ไม้นั้นเพิ่งถูกปิด → อ่านรอบใหม่
6. **EA re-init เพราะเปลี่ยน timeframe** → เหมือน restart ทุกประการ · `equity_hwm` ต้องอ่านคืน **ไม่ใช่รีเซ็ต**
7. **internal hedge ที่ปริมาณเท่ากันเป๊ะ** → net ออกแล้วเหลือ 0 · ถูกต้อง
8. **internal hedge ที่ `CLOSE_BY` ไม่รองรับ** → ปิดฝั่งเล็กกว่าด้วย market · ถ้าล้มเหลว → `ERROR FATAL` + ไม่เทรดต่อ
9. **position ที่ `comment` มี `i:<ulid ย่อ>`** → ใช้เป็นเบาะแสใน log เท่านั้น
   **ห้ามใช้ระบุตัวตน** — 12 ตัวแรกไม่การันตี unique ([SPEC-003 handoff](../reviews/SPEC-003-schema-handoff.md))
10. **ตลาดปิดตอน reconcile** → อ่าน position ได้ปกติ · แต่ถ้าต้อง net internal hedge จะส่ง order ไม่ได้
    → **เลื่อนไปทำตอนตลาดเปิด** + คง `internal_hedge_detected = true` ไว้ + alert ต่อเนื่อง

---

## 6. Acceptance criteria

- [ ] restart EA ตอนถือ 1 position → `STATE` ตัวแรกรายงาน `owned_net` **ตรงกับ MT5**
- [ ] restart EA ตอนถือ 3 ไม้ hedging → `owned_ticket_count` ถูกต้อง
- [ ] **STATE ถูกส่งก่อน backfill** — พิสูจน์จากลำดับ message ฝั่ง server ★
- [ ] **EA ไม่ส่ง order ใดๆ ตอน reconcile** ยกเว้นกรณี internal hedge ★★
      — `grep` ฝั่ง server: ไม่มี `EXEC_REPORT` ก่อนได้ `INTENT` ตัวแรก
- [ ] internal hedge → net ออก + `ERROR ANOMALY_INTERNAL_HEDGE` + flag ใน STATE
- [ ] position ไม่มี SL → `ERROR POSITION_WITHOUT_SL` พร้อม ticket ทุกใบ · **ไม่ตั้ง SL เอง**
- [ ] ไม้ที่ magic ตรงแต่ symbol ไม่ตรง → นับเป็น **foreign ไม่ใช่ owned** ★
- [ ] `mt5_sync_incomplete` → `OnInit` คืน `INIT_FAILED` **ไม่ใช่รายงานว่าไม่มี position**
- [ ] `equity_hwm` อ่านคืนได้หลัง re-init (ไม่รีเซ็ต)
- [ ] **ส่ง INTENT เดิมซ้ำหลัง EA restart → ไม่มี order ใหม่** (NOOP) ★★ §4.5
- [ ] `grep -rn "GlobalVariable\|FileWrite" mt5-ea/Include/Farm/Reconciler.mqh`
      — **ไม่เจอการ persist position** ★ §4.6
- [ ] compile 0 error 0 warning · `run-mql5-tests.ps1` เขียว

## 7. Test list

### MQL5 — `tests/mql5/TestReconciler.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_ownership_requires_magic_and_symbol` | ★ §4.7 |
| 2 | `test_owned_net_sums_signed_volume` | |
| 3 | `test_detects_internal_hedge` | R18 |
| 4 | `test_counts_positions_without_sl` | §4.4 |
| 5 | `test_foreign_positions_counted_separately` | |
| 6 | `test_exceeds_ticket_limits_flag` | R3b/R4 |
| 7 | `test_sync_incomplete_when_count_unstable` | ★ §4.1 |
| 8 | `test_no_positions_is_not_anomaly` | edge 1 |
| 9 | `test_reconciler_never_writes_position_state` | ★ §4.6 |

### Chaos (ชั้น B ของ SPEC-016) — `tests/chaos/test_reconcile.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 10 | `test_restart_reports_actual_position` | ★★ roadmap Phase 1 exit |
| 11 | `test_state_sent_before_backfill_after_restart` | ★ §4.2 |
| 12 | `test_no_order_sent_during_reconcile` | ★★ §2 |
| 13 | `test_duplicate_intent_after_restart_is_noop` | ★★ §4.5 |
| 14 | `test_internal_hedge_netted_and_reported` | §4.3 |
| 15 | `test_hwm_survives_restart` | §4.6 |

**test 12 กับ 13 คือสองตัวที่เงินหายถ้าผิด** —
12 คือ EA ลงมือเองตอนที่ไม่ควร · 13 คือ order ซ้ำหลังรีสตาร์ต

## 8. Files

**Touch:** `mt5-ea/Include/Farm/Reconciler.mqh` · `mt5-ea/Experts/FarmExecutor.mq5`
· `mt5-ea/Include/Farm/StateReporter.mqh` · `tests/mql5/TestReconciler.mq5`
· `tests/chaos/test_reconcile.py` · `tools/run-mql5-tests.ps1` (ลง `gate changes`)

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/Wire.mqh`
· `mt5-ea/Include/Farm/BrokerTime.mqh` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | รออ่านซ้ำ 3 ครั้ง × 500 ms เพียงพอไหมสำหรับ MT5 sync | **ไม่บล็อก** — เริ่มที่ค่านี้ · **วัดเวลาจริงตอน restart แล้วรายงาน** ถ้าบางครั้งเกิน 10 วินาที ให้บอกตัวเลข อย่าปรับเอง |
| Q2 | ควรใส่ position snapshot ลงใน `HELLO` เลยไหม แทนที่จะรอ STATE | **ไม่บล็อก — ตอบแล้ว: ไม่** · `HELLO` มีหน้าที่ auth + capability · การใส่ position ซ้ำกับ `STATE` = สองแหล่งที่ต้องตรงกัน · §4.2 แก้ปัญหา race ด้วยการบังคับลำดับแทน |
| Q3 | ถ้าตลาดปิดตอนเจอ internal hedge จะรออีกนานแค่ไหน | **ไม่บล็อก** — คง flag + alert ต่อเนื่องจนกว่าจะ net ได้ (edge 10) · ถ้าค้างข้ามสุดสัปดาห์เป็นเรื่องที่ต้องเห็นอยู่แล้ว |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ 010 + 011 + 063 merge**

---

## ภาคผนวก — ทำไม "รายงานความจริง อย่าลงมือ" ถึงเป็นกฎที่ถูก

สัญชาตญาณตอนเห็น position ค้างหลังรีสตาร์ตคือ *"ต้องจัดการมัน"* — ปิดทิ้งให้สะอาด
หรือเปิดเพิ่มให้ตรงกับที่เคยตั้งใจ

ทั้งสองทางผิดด้วยเหตุผลเดียวกัน: **EA ไม่มีข้อมูลพอที่จะตัดสิน**
มันไม่รู้ว่า target ล่าสุดคืออะไร · ไม่รู้ว่า regime เปลี่ยนไปหรือยัง ·
ไม่รู้ว่าบัญชีอื่นในฟาร์มถืออะไรอยู่ · และไม่รู้ว่าเวลาที่หายไปนั้นเกิดอะไรขึ้นในตลาด

การปิดทิ้งอัตโนมัติคือการ**รับรู้ขาดทุนในจังหวะที่เลือกโดยความบังเอิญ**
(จังหวะที่ EA รีสตาร์ตพอดี) ซึ่งไม่มีเหตุผลทางกลยุทธ์รองรับเลย

brain มีข้อมูลครบทั้งฟาร์ม — ให้มันเป็นคนตัดสิน · หน้าที่ของ EA คือทำให้ brain
**เห็นภาพที่ตรงกับความจริงเร็วที่สุด** ซึ่งคือเหตุผลทั้งหมดของ §4.1 และ §4.2
