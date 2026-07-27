# SPEC-003 — Schema เสร็จแล้ว + 5 จุดที่โค้ด SPEC-001 ไม่ตรง schema

**วันที่:** 2026-07-27 · **ผู้ทำ:** Claude (เจ้าของ `contracts/schema/`)
**สถานะ SPEC-003:** ✅ **DONE** — 13 schema + README · ปลดล็อก SPEC-004 (codegen)

---

## 1. ส่งมอบอะไร

```
contracts/schema/
  README.md              ← อ่านก่อนเขียน codegen
  common.json            ← $defs ร่วม (enum, id, ts, symbol_spec, account_info, local_limits)
  envelope.json          ← ห่อทุก message + type enum 12 ค่า
  hello.json  hello_ack.json
  heartbeat.json  heartbeat_ack.json
  bar.json  state.json
  intent.json  intent_ack.json
  exec_report.json
  risk_directive.json
  error.json
  config_update.json     ← RESERVED
```

ตรวจแล้ว: **13 ไฟล์ parse ได้ · `$ref` 105 จุด resolve ได้ครบ · ทุกค่าใน `envelope.type`
มีไฟล์ payload ครบ · ไม่มี payload ไหนตั้ง top-level `additionalProperties: false`**

### สิ่งที่นิยามเพิ่มจาก `02-contracts.md` เดิม (เดิมเป็นช่องว่าง)

| # | เรื่อง | เดิม | ตอนนี้ |
|---|-------|------|--------|
| 1 | `HEARTBEAT` / `HEARTBEAT_ACK` payload | อยู่ใน type enum แต่**ไม่มีนิยาม** | นิยามครบ + พา wire metric ขึ้น dashboard |
| 2 | `CONFIG_UPDATE` payload | อยู่ใน type enum แต่**ไม่มีนิยาม** | RESERVED + กฎเหล็กห้ามมี risk param |
| 3 | `local_limits` | `max_positions: 3` (ขัด ADR-001) | แยกเป็น R3a/R3b/R4 |
| 4 | `HELLO.magic` | ไม่มี ทั้งที่ ownership ต้องใช้ | เพิ่มแล้ว |
| 5 | `guard.halt_reason` | free string | enum ผูกกับ rule id (R6/R7/R8/R13/R14/R16/R17/MANUAL) |
| 6 | `margin_level_pct` | number | **nullable** — MT5 คืน 0 เมื่อไม่มี margin ซึ่งกำกวมกับ "ใกล้ล้างพอร์ต" |
| 7 | `slippage_points` | ไม่ระบุเครื่องหมาย | **มีเครื่องหมายได้** — ลบ = ได้ราคาดีกว่า ถ้าเก็บ abs จะมองไม่เห็นว่าโบรกเกอร์ให้ slippage ข้างเดียว |
| 8 | `scale_factor` | number | **เพดาน 1.0 บังคับที่ schema** — เกิน 1 = "ผ่อน" ซึ่งผิดกฎเหล็ก |
| 9 | `flatten_symbols: []` | กำกวม | ระบุชัด: **ว่าง = ทุก symbol** |

---

## 2. 🔴 5 จุดที่ `Wire.mqh` / `Json.mqh` ปัจจุบันไม่ตรง schema

ผมอ่านโค้ดจริงแล้ว (ไม่ใช่เชื่อ handoff) — ทั้ง 5 ข้อนี้จะทำให้ validation **fail** ทันที
ที่ SPEC-004 เริ่มบังคับ schema

### ❶ `msg_id` ไม่ใช่ ULID และ **ซ้ำได้ข้าม restart** ← ร้ายแรงสุด

`Wire.mqh:97-102`
```mql5
string NextMsgId()
{
   static ulong seq = 0;
   seq++;
   return StringFormat("%I64u%08u", (ulong)TimeCurrent(), (uint)(seq % 100000000));
}
```

ได้ 18 ตัวอักษร (unix ts 10 + seq 8) — schema ต้องการ **26 ตัว Crockford base32**

**แต่ปัญหาจริงหนักกว่าเรื่องความยาว:** `seq` เป็น `static` เริ่มที่ 0 ใหม่ทุกครั้งที่ EA
โหลด → **restart EA ภายในวินาทีเดียวกันจะได้ `msg_id` ซ้ำของเดิมเป๊ะ**
`msg_id` เป็น dedupe key ของ gateway → message ที่ถูกต้องจะถูกทิ้งเงียบๆ

ยังไม่เสียหายตอนนี้เพราะ Phase 1 ยังไม่มี order แต่ **Phase 2 message ที่หายไป = STATE
หรือ EXEC_REPORT หาย = risk layer ตัดสินใจบนข้อมูลไม่ครบ**

**ต้องทำ:** ULID จริง = 48-bit ms timestamp + 80-bit random แล้ว encode Crockford base32
(`0123456789ABCDEFGHJKMNPQRSTVWXYZ` — ไม่มี I L O U) · seed `MathSrand()` ด้วย
`GetMicrosecondCount()` ไม่ใช่ `TimeCurrent()` (สองอินสแตนซ์ที่เริ่มวินาทีเดียวกันจะได้ random ชุดเดียวกัน)

### ❷ `session_id` ใส่ `PERIOD_H1` ไม่ใช่ `H1`

`Wire.mqh:274`
```mql5
StringFormat("acct-%I64d-%s-%s", login, symbol, EnumToString((ENUM_TIMEFRAMES)Period()))
```

`EnumToString(PERIOD_H1)` คืน `"PERIOD_H1"` → ได้ `acct-8123456-EURUSD.iux-PERIOD_H1`
schema pattern ต้องการ `acct-8123456-EURUSD.iux-H1` → **fail**

**ต้องทำ:** ฟังก์ชันแปลง `ENUM_TIMEFRAMES` → `"M1"|"M5"|"M10"|"M15"|"M30"|"H1"|"H4"`
ใช้ที่เดียวทั้ง `session_id` และ field `timeframe` · timeframe นอกชุดนี้ → `OnInit` fail
ไม่ใช่ส่งค่าที่ schema ไม่รับขึ้นไป

### ❸ ★ `ts_server` ติดป้าย `Z` แต่เป็นเวลา broker-local

`Json.mqh:148-149`
```mql5
const string ts_server = FarmIsoUtcFromBrokerTime(broker_time);   // broker_time = TimeCurrent()
const string ts_sent   = FarmIsoUtcFromBrokerTime(TimeGMT());
```

`TimeCurrent()` = เวลา **broker server** ซึ่งไม่ใช่ UTC (โบรกเกอร์ทั่วไป GMT+2/+3)
แต่ถูกฟอร์แมตเป็น `...Z` เหมือนเป็น UTC → **`ts_server` เพี้ยนไป 2–3 ชั่วโมงตลอดเวลา**

`ts_sent` ถูก (ใช้ `TimeGMT()`) → ผลข้างเคียงคือ `ts_sent` จะดู **เก่ากว่า** `ts_server`
2–3 ชม. ทำให้ latency ที่คำนวณได้เป็นค่าลบ

นี่คือ field ที่ contract §2 ระบุว่า **"ใช้ตัดสินใจ"** และเป็นส่วนของ primary key
`bars(broker, symbol, timeframe, bar_time)` → ผิดตรงนี้แปลว่า **bar ทุกแถวใน DB
ติดป้ายเวลาผิด** และ backtest/live parity (SPEC-033) จะไม่ตรงโดยไม่มีใครรู้สาเหตุ

ตรงกับช่องว่าง **G6** ที่ audit เจอไว้แล้ว

**ต้องทำ:** อย่าเดา offset เอง — คำนวณจาก `TimeGMT() - TimeCurrent()` ปัดเป็นครึ่งชั่วโมง
แล้ว**บันทึก offset ที่ตรวจได้ลง log ตอน `OnInit`** เพื่อให้ตรวจย้อนได้
เรื่องนี้ควรรวมไว้ที่เดียวใน SPEC-063 BrokerTime ไม่ใช่กระจายในแต่ละ caller

### ❹ `local_limits` hardcode และใช้ field ที่เลิกใช้แล้ว

`Wire.mqh` (ใน `BuildHelloPayload`)
```mql5
const string limits = "{"
   "\"max_lot_per_order\":0.50,"
   "\"max_positions\":3,"        // ← field นี้ไม่มีใน schema แล้ว
   ...
```

สองปัญหา: (ก) `max_positions` ถูกแทนด้วย R3a/R3b/R4 ตั้งแต่ ADR-001
(ข) **ค่าคงที่ในโค้ด** ทั้งที่ contract §4.1 บอกว่า "ค่ามาจาก EA input เท่านั้น"
ตอนนี้ถ้าเปลี่ยน EA input จริง ค่าที่ส่งขึ้น brain จะไม่เปลี่ยนตาม → brain เข้าใจผิดว่า
EA จำกัดอะไรอยู่ แล้วส่ง intent ที่ EA จะ reject

**ต้องทำ:** เพิ่ม EA input ให้ครบ 7 ตัวตาม `common.json#/$defs/local_limits`
แล้วส่งค่าจริงผ่าน `ConfigureRuntime()`

### ❺ SL/TP ที่ไม่ได้ตั้งต้องเป็น `null` ไม่ใช่ `0`

ยังไม่เกิดใน SPEC-001 (ไม่มี position) แต่ **จะเกิดทันทีใน SPEC-010 `STATE`**

MQL5 `PositionGetDouble(POSITION_SL)` คืน `0.0` เมื่อไม่ได้ตั้ง SL
schema กำหนด `exclusiveMinimum: 0` → ส่ง `0` **fail validation**

**ต้องทำ:** serializer ต้องแปลง `0.0` → `null` สำหรับ `sl`/`tp`/`price_filled`/
`price_requested` ทุกจุด · ทำเป็น helper ตัวเดียว (`FarmPriceOrNull()`) ไม่ใช่เช็คกระจาย
เพราะพลาดจุดเดียวก็ fail

---

## 3. ลำดับที่แนะนำให้ Codex ทำ

1. **ปิด SPEC-001 ให้จบก่อน** — 4 ข้อจาก [compile-gate-02](SPEC-001-compile-gate-02.md)
   ยังไม่ได้แก้สักข้อ (`FILE_UTF8` ยังอยู่ที่ `tests/mql5/TestWire.mq5:225` → test ยังรันไม่ได้เลย)
2. **แก้ ❶–❹ ข้างบน** — ขอบเขตเล็ก แก้ตอนนี้ถูกกว่าแก้หลัง codegen มาก
3. **SPEC-004 codegen** — schema พร้อมแล้ว · อ่าน `contracts/schema/README.md` ก่อน
   โดยเฉพาะข้อ 2 (`additionalProperties`) และข้อ 3 (`null` ≠ `0`)

**❸ (`ts_server`)** ถ้าจะทำให้ถูกจริงต้องรอ SPEC-063 BrokerTime — ระหว่างนี้อย่างน้อย
ให้ log offset ที่ตรวจได้ตอน `OnInit` เพื่อรู้ขนาดของความคลาดเคลื่อน

---

## 4. คำถามที่ผมตัดสินใจแทนไปแล้ว — แย้งได้ถ้าไม่เห็นด้วย

| # | ตัดสินว่า | ทางเลือกที่ไม่เอา | เหตุผล |
|---|-----------|-------------------|--------|
| 1 | `symbol` เป็น string มี pattern **ไม่ใช่ enum 6 ค่า** | enum รายชื่อ symbol ที่อนุญาต | เปลี่ยนชุด symbol ไม่ควรต้องแก้ schema + bump `v` · รายชื่อที่อนุญาตเป็น config → SymbolRegistry (SPEC-064) |
| 2 | `margin_mode` เป็น enum 4 ค่า **ไม่ใช่ `const: RETAIL_HEDGING`** | บังคับค่าเดียวที่ schema | ปล่อยให้ค่าผิดส่งขึ้นมาได้ → gateway reject พร้อม **log ค่าจริง** ดีกว่า schema parse error ที่ไม่บอกว่าเจออะไร |
| 3 | `is_final` เป็น `const: true` | boolean ธรรมดา | กันการส่ง bar ที่ยังไม่ปิดเข้า feature pipeline ซึ่งเป็นต้นเหตุ look-ahead bias · จะรองรับ `false` ต้อง bump `v` โดยเจตนา |
| 4 | `scale_factor` เพดาน 1.0 ที่ schema | ปล่อยให้เกิน 1 แล้วเช็คในโค้ด | กฎเหล็ก "ผ่อนไม่ได้" ควรบังคับที่ชั้นที่ลืมไม่ได้ |
| 5 | `config_update.settings` เป็น `additionalProperties: false` | true เหมือน message อื่น | ที่นั่น unknown field = ความพยายามเปลี่ยนค่าที่ไม่อนุญาต ต้อง reject ไม่ใช่ข้าม |
| 6 | ULID เต็ม 26 ตัว | ยอมรับ id สั้นแบบที่โค้ดทำอยู่ | dedupe key ต้องไม่ซ้ำข้าม restart (เหตุผลใน ❶) |

---

## 5. หนี้ที่ยังค้าง (ไม่บล็อก SPEC-004)

| เรื่อง | สถานะ |
|-------|-------|
| `USDCNY.iux` ไม่มีในโบรกเกอร์ | รอเจ้าของเลือก `USDCNH` หรือตัดทิ้ง — **ไม่กระทบ schema** เพราะ symbol ไม่ใช่ enum |
| **D5 ทุนต่อบัญชี** | 🔴 BLOCKER ของ SPEC-020/025 · **ไม่บล็อก SPEC-004** |
| `order comment` ยาวได้ 31 ตัวอักษร | ULID 26 ตัว + prefix ใส่ไม่พอ → schema กำหนดให้ใช้ `i:<12 ตัวแรก>` · 12 ตัวแรกของ ULID เป็น timestamp+random บางส่วน **ไม่การันตี unique** ใช้เป็นเบาะแสตอน debug เท่านั้น การผูก trade↔intent ที่เชื่อถือได้ต้องมาจาก `exec_reports.intent_id` ใน DB |
| validator สำหรับ invariant ข้ามฟิลด์ | เขียนไว้ใน `$comment` ทุกไฟล์แล้ว · **SPEC-004/005 ต้อง implement เป็นโค้ด + test** schema จับให้ไม่ได้ |
