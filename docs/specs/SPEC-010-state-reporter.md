# SPEC-010 — StateReporter: BAR · STATE · backfill

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-001, SPEC-004, **SPEC-063** · **Blocks:** SPEC-011, SPEC-013, SPEC-015
**อ้าง:** [02-contracts §4.3/§4.4](../02-contracts.md) · [`bar.json`](../../contracts/schema/bar.json) · [`state.json`](../../contracts/schema/state.json)

> ⚠️ **เพิ่ม dependency จาก backlog เดิม:** เดิมเขียน `001, 004` — **เพิ่ม SPEC-063**
> เพราะ `bar_time` เป็นส่วนของ primary key `bars(broker,symbol,timeframe,bar_time)`
> ถ้าเวลาผิด **ทุกแถวใน DB ติดป้ายผิด** และต้อง migrate ทั้งตารางทีหลัง

---

## 1. Goal

ป้อนข้อมูลให้ brain ครบ: bar ที่ปิดแล้ว · สถานะบัญชี/position · และ backfill ตอนต่อครั้งแรก
เพื่อให้ brain warm feature window ได้และเห็นภาพพอร์ตตรงกับ MT5 ตลอดเวลา

**ยังไม่เทรด** — ticket นี้ส่งข้อมูลขาเดียว ไม่รับ INTENT ไม่ส่ง order

## 2. Non-goals (ห้ามทำใน ticket นี้)

- ❌ ห้ามมี `OrderSend` / `PositionModify` / `PositionClose` — `grep` ต้องไม่เจอ
- ❌ ห้าม implement `LocalRiskGuard` (SPEC-019) — ส่งค่า `guard.*` ได้ แต่**ห้าม block/halt อะไร**
- ❌ ห้าม implement reconciler (SPEC-011)
- ❌ ห้ามคำนวณ indicator / feature — brain ทำเอง EA ส่ง OHLC ดิบ
- ❌ ห้ามแก้ `contracts/schema/**`
- ❌ ห้ามเขียน JSON serializer เอง — **ต้องใช้ของที่ SPEC-004 generate**

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ชนิด |
|------|------|
| `mt5-ea/Include/Farm/StateReporter.mqh` | **สร้าง** |
| `mt5-ea/Include/Farm/Wire.mqh` | **แก้** — ถอด payload builder ออก (ดู §3.2) |
| `mt5-ea/Experts/FarmExecutor.mq5` | **แก้** — สร้าง/เรียก StateReporter |
| `tests/mql5/TestStateReporter.mq5` | **สร้าง** — EA test |
| `brain/gateway/echo_server.py` | **แก้** — รับ BAR/STATE + นับ backfill |
| `tools/run-mql5-tests.ps1` | **แก้** — เพิ่ม suite (ลงหัวข้อ `gate changes`) |

### 3.2 ★ แยกชั้นให้ถูกก่อน — `Wire.mqh` ต้องไม่รู้จัก message type

ตอนนี้ `Wire.mqh` สร้าง payload ของ `HELLO`/`HEARTBEAT` เองใน `BuildHelloPayload()`
= **transport รู้จัก semantics ของ message** ซึ่งผิดชั้น

| ชั้น | หน้าที่ | ห้ามรู้ |
|------|---------|---------|
| `Wire.mqh` | byte · framing · reconnect · queue · ack tracking | **ไม่รู้ว่า BAR/STATE คืออะไร** |
| `StateReporter.mqh` | สร้าง payload · ตัดสินว่าส่งอะไรเมื่อไร | ไม่รู้เรื่อง socket |

**ต้องทำ:** ย้าย `BuildHelloPayload()` และ payload ของ `HEARTBEAT` ออกจาก `Wire.mqh`
ไปที่ `StateReporter` แล้วให้ `Wire` รับ payload เป็น string ผ่าน callback หรือ setter

> `HELLO` มีข้อจำกัดพิเศษ: Wire ต้องส่งเองตอน handshake (ก่อน READY)
> → ให้ StateReporter ลงทะเบียน payload ไว้ล่วงหน้าตอน `Init()` ผ่าน
> `wire.SetHelloPayload(string)` แล้ว Wire แค่หยิบไปใช้ ไม่ต้องรู้ว่าข้างในคืออะไร

### 3.3 `StateReporter.mqh` — API ที่ต้องมีเป๊ะนี้

```mql5
class CStateReporter
{
public:
   // ผูกกับ wire + broker time · เตรียม HELLO payload ให้ wire
   // คืน false ถ้าเตรียมไม่ได้ (symbol select fail ฯลฯ) → OnInit ต้อง INIT_FAILED
   bool Init(CWire *wire, CBrokerTime *clock,
             const int magic, const string strategy_id,
             const int backfill_bars   = 300,
             const int state_interval_sec = 5);

   // เรียกจาก OnTimer ทุก 1 วินาที **หลัง** wire.Pump()
   void Pump();

   // เรียกจาก OnTick — เก็บสถิติ spread เท่านั้น ห้ามทำอย่างอื่น
   void OnTickSample();

   // ---- สถานะ backfill (ให้ log/test อ่าน) ----
   bool BackfillDone() const;
   int  BackfillSent() const;
   int  BackfillTotal() const;      // จำนวนที่ "ตั้งใจจะส่ง" = min(300, ที่มีจริง)

   // ---- metric ----
   long BarsSent() const;
   long StatesSent() const;
   long BarsSkippedQueueFull() const;   // ★ > 0 = ข้อมูลหาย ต้อง alert

#ifdef FARM_TEST
   string TestBuildBarPayload(const int shift);
   string TestBuildStatePayload();
   void   TestForceNewBar();
#endif
};
```

---

## 4. Behaviour

### 4.1 ★ Backfill — ห้าม enqueue ทีเดียว จะทำให้ข้อมูลเก่าหายเงียบ

**ปัญหาที่ต้องแก้ (คำนวณแล้ว ไม่ใช่สมมติ):**

| | ค่า |
|---|---|
| `InpSendQueueMax` (SPEC-001) | **256** |
| backfill ที่ spec สั่ง | **300 bar** |
| นโยบายตอน queue เต็ม (`DropOldestForCapacity`) | **ทิ้งตัวเก่าสุด** |

⇒ ถ้า enqueue 300 ตัวรวดเดียว → **44 bar แรกถูกทิ้ง** ซึ่งคือ bar **เก่าที่สุด**
= ตัวที่ brain ต้องใช้ warm feature window พอดี · และหายไปโดยเห็นแค่ `bytes_dropped` เพิ่ม

**กฎบังคับ:**

| # | กฎ |
|---|-----|
| 1 | เริ่ม backfill **หลัง `IsAuthenticated() == true`** เท่านั้น |
| 2 | ส่งแบบ **paced** — แต่ละ `Pump()` เติมได้เท่าที่ `SendQueueDepth() < m_queue_max / 2` |
| 3 | เรียง **เก่า → ใหม่** (shift สูง → ต่ำ) ตาม [contract §4.3](../02-contracts.md) |
| 4 | ถ้า `Send()` คืน false ระหว่าง backfill → **หยุดรอบนั้น ไม่ข้ามตัว** ค่อยส่งต่อรอบหน้า `BarsSkippedQueueFull++` |
| 5 | ล็อก `bar_index_end` ตอนเริ่ม — bar ที่ปิดใหม่ระหว่าง backfill **ต้องส่งหลัง backfill จบ** ห้ามแทรก |
| 6 | จบแล้ว log `backfill_done sent=N total=M` · **N < M = ต้อง WARN** |

> เหลือครึ่ง queue ไว้ให้ heartbeat/STATE — ถ้า backfill กิน queue หมด heartbeat จะขาด
> → gateway มองว่า session ตาย → reconnect → **backfill เริ่มใหม่ทั้งหมด** = ลูปไม่จบ

### 4.2 BAR — ส่งเมื่อไร

| สถานการณ์ | ทำอะไร |
|-----------|--------|
| `iTime(sym,tf,0)` ต่างจากค่าที่จำไว้ | มี bar ปิดใหม่ → ส่ง **shift 1** (ตัวที่เพิ่งปิด) |
| ยังเป็น bar เดิม | ไม่ทำอะไร |
| ตลาดปิด (ไม่มี bar ใหม่) | ไม่ส่ง BAR — แต่ `Pump()` ยังทำงาน heartbeat/STATE ต้องไม่หยุด |
| ยังไม่ `IsAuthenticated()` | **ไม่ส่ง ไม่คิว** — รอ READY ก่อน (กัน queue เต็มตอนต่อไม่ติด) |
| backfill ยังไม่จบ | เก็บไว้ ส่งหลัง backfill (§4.1 กฎ 5) |

**★ ห้ามส่ง shift 0 เด็ดขาด** — เป็น bar ที่ยัง**ไม่ปิด** · `bar.json` บังคับ `is_final: const true`
ถ้าส่ง bar ที่ยังไม่ปิดเข้า feature pipeline = **look-ahead bias** ซึ่งจะทำให้ backtest
ดูดีเกินจริงและหาสาเหตุไม่เจอ

### 4.3 สถิติ spread — เก็บที่ `OnTick` ที่เดียว

| จุด | ทำอะไร |
|-----|--------|
| `OnTickSample()` (จาก `OnTick`) | อ่าน spread ปัจจุบัน → สะสม `sum`, `count`, `max` |
| `Pump()` ทุก 1 วินาที | **สุ่มเพิ่ม 1 ตัวอย่าง** — กันกรณีตลาดบางไม่มี tick เลยทั้ง bar |
| ตอน bar ปิด | `avg = sum/count` (ปัดลง) · `max` · แล้ว **reset ทั้งสามค่า** |
| `count == 0` ตอน bar ปิด | ใช้ spread ปัจจุบันเป็นทั้ง avg และ max · log DEBUG |

`spread_points_avg ≤ spread_points_max` เสมอ — เป็น invariant ใน `bar.json` `$comment`

### 4.4 STATE — ส่งเมื่อไร

ส่งเมื่อ **อย่างใดอย่างหนึ่ง**:
1. ครบ `state_interval_sec` (default 5) นับจากครั้งล่าสุด
2. **position เปลี่ยน** — signature เปลี่ยน

```
signature = จำนวน ticket ที่เป็นเจ้าของ  +  ผลรวม |volume|  +  ผลรวม ticket id
```
ต้องเช็คทุก `Pump()` (1s) → position ที่เปิด/ปิดจะถูกรายงานภายใน 1 วินาที ไม่ใช่รอครบ 5

### 4.5 การเก็บข้อมูลลง STATE

| field | มาจากไหน | ระวัง |
|-------|----------|-------|
| `balance` `equity` `margin_used` `margin_free` | `AccountInfoDouble()` | **ทั้งบัญชี** รวมไม้ foreign |
| `margin_level_pct` | `ACCOUNT_MARGIN_LEVEL` | **`margin_used == 0` → ส่ง `null` ไม่ใช่ `0`** (MT5 คืน 0 ซึ่งกำกวมกับ "ใกล้ล้างพอร์ต") |
| `positions[]` | วน `PositionsTotal()` | **เฉพาะ `POSITION_MAGIC == magic` && `POSITION_SYMBOL == symbol`** |
| `sl` `tp` | `POSITION_SL/TP` | **`0.0` → ส่ง `null`** — ทำ helper ตัวเดียว ห้ามเช็คกระจาย |
| `time_open` | `POSITION_TIME` | เป็นเวลา broker → **แปลง UTC ผ่าน `CBrokerTime`** |
| `comment` | `POSITION_COMMENT` | MT5 จำกัด 31 ตัว · ยังว่างใน ticket นี้ (ยังไม่มี order) |
| `owned_net` | Σ volume × (BUY? +1 : −1) | คำนวณจาก `positions[]` ต้องตรงกัน |
| `owned_ticket_count` | นับต่อ symbol | |
| `foreign_positions` | ไม้ที่ **ไม่ใช่** ของเรา | `count` · `symbols[]` (unique) · `total_volume` · `margin_estimate` |
| `equity_hwm` | ดู §4.6 | **ต้อง persist** |
| `day_start_equity` | ดู §4.6 | **ต้อง persist** |
| `guard.*` | ดู §4.7 | ยังไม่มี guard จริง |
| `pending_orders` | `OrdersTotal()` | **ว่างเสมอใน Phase 1–5** — ส่ง `[]` |

### 4.6 `equity_hwm` / `day_start_equity` — mechanic เท่านั้น ยังไม่ enforce

ticket นี้ **คำนวณและ persist** ให้ถูก · **ไม่ตัดสินใจ halt อะไรทั้งสิ้น** (นั่นคือ SPEC-021)
แต่ถ้าไม่ทำที่นี่ STATE จะส่ง `0` ขึ้นไป แล้ว brain ได้ข้อมูลขยะ

| | กฎ |
|---|---|
| `equity_hwm` | `max(hwm, equity)` ทุก `Pump()` · **persist ข้าม restart** |
| `day_start_equity` | equity ณ **00:00 broker time** — ใช้ `CBrokerTime.BrokerDayStart()` เทียบ |
| เปลี่ยนวัน | `BrokerDayStart(now) != BrokerDayStart(last_check)` → ตั้ง `day_start_equity = equity` ปัจจุบัน |
| persist ที่ไหน | `GlobalVariableSet()` ชื่อ `farm_hwm_{magic}_{symbol}` และ `farm_daystart_{magic}_{symbol}` |
| restart แล้วอ่านคืนไม่ได้ | ตั้งจาก equity ปัจจุบัน + **log WARN** (ไม่ใช่เงียบ) |

> ⚠️ วันที่ DST เปลี่ยน หน้าต่างวันจะยาว 23 หรือ 25 ชม. — **ถูกต้องแล้ว ห้าม "แก้"**
> ([SPEC-063 §4.6](SPEC-063-broker-time.md))

### 4.7 `guard.*` ใน ticket นี้

| field | ค่าใน SPEC-010 |
|-------|----------------|
| `halted` | `false` เสมอ (ยังไม่มี guard) |
| `halt_reason` | `null` |
| `mode` | จาก `RISK_DIRECTIVE` ล่าสุดที่ได้รับ · ยังไม่มี → `NORMAL` |
| `current_spread_points` | ค่าจริงตอนนี้ |
| `internal_hedge_detected` | ✅ **คำนวณจริง** — `positions[]` มีทั้ง BUY และ SELL ใน symbol เดียว |

`internal_hedge_detected` เป็น **การตรวจจับ ไม่ใช่การบังคับ** — ทำได้เลยและควรทำ
เพราะเป็น anomaly (R18) ที่ต้องเห็นตั้งแต่มีข้อมูลชุดแรก

### 4.8 ลำดับใน `OnTimer`

```
1. brokerTime.Refresh()        // ตรวจ DST · ถ้าเปลี่ยนให้ log + ส่ง ERROR WARN
2. wire.Pump()                 // ต่อ/ส่ง/รับ
3. reporter.Pump()             // ตัดสินว่าจะส่งอะไร
4. อ่าน wire.Receive() วนจนหมด
```

**ห้ามสลับ 2 กับ 3** — reporter ต้องเห็น queue depth ล่าสุดหลัง drain แล้ว
ไม่งั้นจะประเมินที่ว่างผิดแล้ว enqueue เกิน

---

## 5. Edge cases

1. **history ไม่ครบ 300 bar** — `Bars(sym,tf)` < 301 → ส่งเท่าที่มี · `BackfillTotal()` = ที่มีจริง
   · **log WARN** เพราะ brain จะ warm feature ไม่ครบ · **ห้าม `INIT_FAILED`**
2. **`CopyRates` คืนน้อยกว่าที่ขอ** — MT5 ยังโหลด history ไม่เสร็จ → ลองใหม่รอบหน้า
   สูงสุด 30 วินาที แล้วส่งเท่าที่ได้ + WARN
3. **reconnect ระหว่าง backfill** — `IsAuthenticated()` กลับเป็น false → **รีเซ็ต backfill
   แล้วเริ่มใหม่ทั้งหมด** (brain ฝั่งใหม่ไม่มีข้อมูลเดิม) · นับ `reconnect_count` ไว้ดูว่าวนลูปไหม
4. **bar ปิดตอน queue เต็ม** — `BarsSkippedQueueFull++` + WARN · **ห้ามข้าม bar เงียบๆ**
   brain ตรวจ gap ได้จาก `bar_time` แต่ต้องมีสัญญาณฝั่ง EA ด้วย
5. **EA re-init (เปลี่ยน timeframe บนชาร์ต)** — reset ทุก state · backfill ใหม่ ·
   `equity_hwm` **ต้องอ่านคืนจาก GlobalVariable ไม่ใช่รีเซ็ต**
6. **สุดสัปดาห์** — ไม่มี bar ใหม่ · STATE ยังส่งทุก 5s · heartbeat ต้องไม่ขาด
7. **position ของ EA อื่น magic ชนกัน** — ถ้า magic ตรงแต่ symbol ไม่ตรง → **ไม่ใช่ของเรา**
   ownership ต้องเช็ค **ทั้งสองเงื่อนไข** ([ADR-001](../decisions/ADR-001-hedging-account.md))
8. **`positions[]` เกิน 64** — `state.json` จำกัด `maxItems: 64` · R4 = 8 อยู่แล้ว
   เกิน 64 = ผิดปกติร้ายแรง → ส่ง 64 ตัวแรก + `ERROR severity:ERROR` **ห้ามส่งเกินแล้วให้ schema fail**
9. **STATE ใหญ่เกิน 64 KB** — ต้องทดสอบที่ 64 position ว่ายังต่ำกว่า · เกิน = ตัดตาม 8
10. **`CBrokerTime.IsValid() == false`** — ห้ามส่ง BAR/STATE (timestamp เชื่อไม่ได้)
    → log WARN + ส่งเฉพาะ heartbeat จนกว่าจะ valid
11. **DST เปลี่ยนระหว่าง backfill** — `bar_time` ของ bar ที่ส่งไปแล้วยังถูก (offset ตอนนั้นถูกจริง)
    ไม่ต้องส่งซ้ำ
12. **spread เป็น 0** (โบรกเกอร์ไม่ให้ค่า) — ส่ง 0 ได้ แต่ log DEBUG ครั้งแรกที่เจอ

---

## 6. Acceptance criteria

- [ ] `grep -rn "OrderSend\|PositionModify\|PositionClose" mt5-ea/` — **ไม่เจอ**
- [ ] compile 0 error 0 warning ผ่าน `tools/compile-gate.ps1`
- [ ] `TestStateReporter` ผ่าน `tools/run-mql5-tests.ps1` · `ran_names` ครบตาม §7
- [ ] **backfill 300 bar ส่งครบ 300** โดย `BarsSkippedQueueFull() == 0`
      และ `wire.BytesDropped()` **ไม่เพิ่มเลย** ← ข้อพิสูจน์ว่า pacing ทำงาน
- [ ] backfill เรียง `bar_time` **เพิ่มขึ้นทุกตัว** ไม่มีซ้ำ ไม่มีข้าม (ตรวจฝั่ง `echo_server.py`)
- [ ] ระหว่าง backfill **heartbeat ไม่ขาดแม้แต่ครั้งเดียว** ← ข้อพิสูจน์ว่าเหลือ queue ให้ทราฟฟิกสด
- [ ] ทุก BAR ที่ส่งมี `is_final: true` และ `bar_time` **ไม่เท่ากับ** `iTime(sym,tf,0)`
- [ ] STATE ที่ `positions` 64 ตัว serialize แล้ว **< 64 KB นับเป็น byte**
- [ ] `sl`/`tp` ที่ไม่ได้ตั้ง ส่ง `null` — `grep '"sl":0' ` ในผลที่ echo_server รับ **ต้องไม่เจอ**
- [ ] `margin_level_pct` ส่ง `null` เมื่อไม่มี position
- [ ] restart EA ตอนมี position → `equity_hwm` **ไม่รีเซ็ต** (อ่านคืนจาก GlobalVariable)
- [ ] `owned_net` ที่ส่ง ตรงกับที่คำนวณจาก `positions[]` ทุกครั้ง (ตรวจฝั่ง Python)
- [ ] ทุก payload ผ่าน schema validation ฝั่ง `echo_server.py` (ใช้ model จาก SPEC-004)
- [ ] `grep -n "TimeCurrent()\|TimeGMT()" mt5-ea/Include/Farm/StateReporter.mqh` — **ไม่เจอ**
      (เวลาต้องมาจาก `CBrokerTime` เท่านั้น)

## 7. Test list

### MQL5 — `tests/mql5/TestStateReporter.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_backfill_paced_never_exceeds_half_queue` | ★ §4.1 กฎ 2 — จุดที่ข้อมูลจะหาย |
| 2 | `test_backfill_order_oldest_first` | §4.1 กฎ 3 |
| 3 | `test_backfill_resumes_after_queue_pressure` | กฎ 4 — ไม่ข้ามตัว |
| 4 | `test_backfill_defers_live_bar_until_done` | กฎ 5 — ไม่แทรกลำดับ |
| 5 | `test_backfill_short_history_warns_not_fails` | edge 1 |
| 6 | `test_bar_never_sends_shift_zero` | ★ look-ahead |
| 7 | `test_bar_is_final_always_true` | schema `const` |
| 8 | `test_spread_avg_not_greater_than_max` | invariant |
| 9 | `test_spread_no_tick_uses_current` | edge 12 / §4.3 |
| 10 | `test_state_null_sl_not_zero` | ★ `0` → `null` |
| 11 | `test_state_margin_level_null_when_no_position` | §4.5 |
| 12 | `test_state_ownership_requires_magic_and_symbol` | ★ edge 7 |
| 13 | `test_state_owned_net_matches_positions` | invariant |
| 14 | `test_state_internal_hedge_detected` | R18 detection |
| 15 | `test_state_sent_on_position_change_within_1s` | §4.4 |
| 16 | `test_state_size_under_64kb_at_64_positions` | ★ edge 9 |
| 17 | `test_hwm_persists_across_reinit` | §4.6 |
| 18 | `test_day_start_equity_resets_on_broker_day_change` | §4.6 + SPEC-063 |
| 19 | `test_no_send_when_broker_time_invalid` | edge 10 |

### Python — `tests/chaos/test_state_reporter.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_backfill_300_bars_all_received_in_order` | ★ ครบ + เรียง + ไม่ซ้ำ |
| 2 | `test_heartbeat_uninterrupted_during_backfill` | ★ ข้อพิสูจน์ pacing |
| 3 | `test_all_payloads_validate_against_schema` | ใช้ model จาก SPEC-004 |
| 4 | `test_bar_gap_detectable_by_bar_time` | edge 4 |
| 5 | `test_state_matches_mt5_positions` | ตรวจข้าม — เทียบกับ position จริง |

**ห้าม mock `CWire`** — test ต้องผ่าน queue จริงเพื่อพิสูจน์ pacing
mock queue = ไม่ได้ทดสอบสิ่งที่ ticket นี้แก้อยู่

## 8. Files

**Touch:** ตาม §3.1

**ห้ามแตะ:** `contracts/schema/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md` · `README.md`
· `mt5-ea/Include/Farm/BrokerTime.mqh` (SPEC-063 — ใช้ได้ ห้ามแก้)

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `InpSendQueueMax` ควรเพิ่มจาก 256 ไหม ในเมื่อ backfill = 300? | **ไม่บล็อก — ตอบแล้ว: ไม่เพิ่ม** · แก้ด้วย pacing (§4.1) ดีกว่าเพิ่ม queue เพราะ queue ใหญ่ = latency สูงและซ่อนปัญหา · ถ้า pacing ทำแล้วยังไม่พอ **รายงานตัวเลขจริงมา** อย่าเพิ่ม queue เอง |
| Q2 | backfill 300 bar ควรเป็น input ปรับได้ไหม? | **ไม่บล็อก** — ทำเป็น `input int InpBackfillBars = 300` ได้ แต่ค่า default ต้องเป็น 300 ตาม contract |
| Q3 | STATE ทุก 5 วินาที หนักไปไหมถ้ามีหลาย EA ต่อ gateway เดียว? | **ไม่บล็อก** — วัดแล้วรายงานใน handoff · ถ้าหนักจริงเปิด ticket ใหม่ ห้ามลดความถี่เอง |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ SPEC-004 และ SPEC-063 merge แล้ว**

---

## ภาคผนวก — ทำไม pacing สำคัญกว่าที่ดู

ถ้าไม่ทำ pacing สิ่งที่จะเกิดคือ:

```
backfill enqueue 300  →  queue 256 เต็ม  →  drop 44 ตัวเก่าสุด
                      →  heartbeat ที่ต่อคิวก็โดนเบียด
                      →  gateway ไม่ได้ heartbeat 3 ครั้ง → ตัด session
                      →  EA reconnect → backfill เริ่มใหม่ → วนซ้ำไม่จบ
```

และอาการที่เห็นจะเป็น *"EA reconnect ตลอดเวลา"* ซึ่ง**ชี้ไปผิดที่**
คนจะไปไล่หาปัญหาที่ socket/network ทั้งที่ต้นเหตุคือ backfill กิน queue

`BarsSkippedQueueFull()` และ acceptance ข้อ *"heartbeat ไม่ขาดระหว่าง backfill"*
มีไว้เพื่อให้ลูปนี้ **ปรากฏเป็นตัวเลข ไม่ใช่เป็นอาการ**
