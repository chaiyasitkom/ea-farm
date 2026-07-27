# SPEC-063 — BrokerTime: แหล่งความจริงเดียวเรื่องเวลา

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-001 · **Blocks:** SPEC-010, SPEC-019, SPEC-021, SPEC-033
**ปิดช่องว่าง:** [G6](../06-gap-audit.md#g6) · **แก้ finding:** [SPEC-003 handoff ❸](../reviews/SPEC-003-schema-handoff.md)

> ⚠️ **แก้ dependency จาก backlog เดิม:** เดิมเขียนว่า depends on SPEC-002 (repo scaffold)
> — **ไม่จริง** module นี้เป็น MQL5 ล้วน ไม่ต้องรอ scaffold
> ที่ต้องรอคือ SPEC-001 เพราะต้องเสียบเข้า `Wire.mqh`/`FarmExecutor.mq5`

---

## 1. Goal

รวมการคำนวณเวลาทุกอย่างไว้ที่ module เดียว แปลงเวลา broker ↔ UTC ได้ถูกต้องข้าม DST
และหาเส้นแบ่ง "วันใหม่" ตามเวลา broker ได้ เพื่อให้ `ts_server` บนสาย · `bar_time` ใน DB ·
และเส้นแบ่งวันของ R6 ตรงกันทั้งระบบ

**ตอนนี้ยังผิดอยู่จริง** — `Json.mqh:64-70` `FarmIsoUtcFromBrokerTime()` ไม่แปลงเวลาเลย
แค่ฟอร์แมต `datetime` ที่รับมาแล้วเติม `Z` ต่อท้าย ทั้งที่ชื่อฟังก์ชันบอกว่าแปลงจากเวลา broker
→ `ts_server` เพี้ยนเท่ากับ offset ของโบรกเกอร์ (ปกติ 2–3 ชม.) **ตลอดเวลา**

## 2. Non-goals (ห้ามทำใน ticket นี้)

- ❌ ห้าม implement R11 `trading_hours` / R12 friday close — นี่แค่ให้เครื่องมือ กฎอยู่ SPEC-019
- ❌ ห้าม implement R6 daily loss — SPEC-021 เป็นคนใช้ `BrokerDayStart()`
- ❌ ห้ามแตะ economic calendar timezone (SPEC-043)
- ❌ ห้ามเขียนฝั่ง Python ให้เดา offset เอง — ดู §3.3 (นี่คือหัวใจของ G6)
- ❌ ห้ามใช้ NTP / HTTP / DLL เพื่อหาเวลาจริง — ใช้ได้แต่ API ของ MQL5
- ❌ ห้ามแก้ไฟล์ใน `contracts/schema/` (Claude เพิ่ม field ให้แล้ว — ดู §3.4)

---

## 3. Interface

### 3.1 ไฟล์ที่ต้องสร้าง / แก้

| ไฟล์ | ทำอะไร |
|------|--------|
| `mt5-ea/Include/Farm/BrokerTime.mqh` | **สร้าง** — `CBrokerClockSource` + `CBrokerTime` |
| `tests/mql5/TestBrokerTime.mq5` | **สร้าง** — EA test (`OnInit` + `ExpertRemove`) เขียนผล JSON |
| `mt5-ea/Include/Farm/Json.mqh` | **แก้** — ลบ `FarmIsoUtcFromBrokerTime()` เพิ่ม `FarmFormatIsoUtc()` |
| `mt5-ea/Include/Farm/Wire.mqh` | **แก้** — ใช้ `CBrokerTime` แทนการฟอร์แมตเอง + ส่ง field ใหม่ |
| `mt5-ea/Experts/FarmExecutor.mq5` | **แก้** — `Init()` ก่อน Wire · `Refresh()` ใน `OnTimer` |
| `tools/run-mql5-tests.ps1` | **แก้** — เพิ่ม suite `TestBrokerTime` |

### 3.2 `BrokerTime.mqh` — API ที่ต้องมีเป๊ะนี้

```mql5
// ---- test seam: ให้ test ป้อนเวลาปลอมได้ ----
class CBrokerClockSource
{
public:
   virtual datetime ServerTime() { return TimeTradeServer(); }
   virtual datetime GmtTime()    { return TimeGMT(); }
   virtual datetime LocalTime()  { return TimeLocal(); }
   virtual int      GmtOffsetLocal() { return (int)TimeGMTOffset(); }
   virtual int      DstLocal()       { return (int)TimeDaylightSavings(); }
};

class CBrokerTime
{
public:
   // src = NULL → ใช้ API จริง · test ส่ง fake source เข้ามา
   // คืน false ถ้าหา offset ที่เชื่อถือได้ไม่ได้ → OnInit ต้อง INIT_FAILED
   bool     Init(CBrokerClockSource *src = NULL);

   // เรียกจาก OnTimer ทุก 1 วินาที — เก็บ sample และตรวจ DST เปลี่ยน
   // คืน true ถ้า offset เพิ่งเปลี่ยนในรอบนี้ (caller ต้อง log + ส่ง ERROR)
   bool     Refresh();

   // ---- เวลาปัจจุบัน ----
   datetime NowBroker() const;          // จาก ServerTime() ห้ามใช้ TimeCurrent()
   datetime NowUtc() const;             // = BrokerToUtc(NowBroker())

   // ---- แปลง ----
   datetime BrokerToUtc(const datetime broker_time) const;
   datetime UtcToBroker(const datetime utc_time) const;

   // ---- สถานะ ----
   int      OffsetSeconds() const;      // broker − UTC · บวก = broker เร็วกว่า UTC
   bool     IsValid() const;            // false = ห้ามเทรด ต้องเข้า SafeMode
   datetime LastChangeUtc() const;      // 0 ถ้ายังไม่เคยเปลี่ยน
   int      PreviousOffsetSeconds() const;

   // ---- เส้นแบ่งวันตามเวลา broker ----
   datetime BrokerDayStart(const datetime broker_time) const;   // 00:00 broker ของวันนั้น
   int      BrokerDayOfWeek(const datetime broker_time) const;  // 0=Sun … 6=Sat
   bool     IsSameBrokerDay(const datetime a, const datetime b) const;

   // ---- diagnostic (บังคับเรียกใน Init) ----
   string   DiagnosticLine() const;
};

// ฟอร์แมตเท่านั้น **ไม่แปลงอะไร** — ชื่อบอกชัดว่ารับ UTC เข้า ได้ UTC ออก
// อยู่ใน Json.mqh
string FarmFormatIsoUtc(const datetime utc_time);
```

**★ `FarmIsoUtcFromBrokerTime()` ต้องถูกลบทิ้ง** ไม่ใช่แก้ข้างใน —
ชื่อที่บอกว่า "แปลงจากเวลา broker" แต่ไม่แปลง คือต้นเหตุของ bug นี้
ถ้าปล่อยไว้จะมีคนเรียกซ้ำอีก · `grep FarmIsoUtcFromBrokerTime` ต้องไม่เจออะไรเลย

### 3.3 ★ ฝั่ง Python ห้ามเดา offset เอง — นี่คือหัวใจของ G6

```
EA (มี CBrokerTime ตัวเดียว) ──► ตรวจ offset ──► ส่งขึ้นสาย
                                                    │
                          brain **อ่านค่าจากสาย** ◄──┘   ห้ามคำนวณเอง
```

ถ้า brain เดา offset เองจะมี **สองแหล่งความจริง** ที่ไม่ตรงกันได้ — ซึ่งคือช่องว่าง G6 เป๊ะๆ
brain ต้องใช้ `broker_time.utc_offset_sec` จาก `HELLO` และ
`wire.broker_utc_offset_sec` จาก `HEARTBEAT` เท่านั้น

**บันทึกเป็นข้อบังคับสำหรับ SPEC-013 (gateway) และ SPEC-021 (daily loss)** —
ticket นี้ไม่ต้องเขียนโค้ด Python

### 3.4 Field ใหม่บนสาย — Claude เพิ่มใน schema ให้แล้ว

เป็น **optional field** จึงไม่ breaking ไม่ต้อง bump `v` ([§7](../02-contracts.md))

`HELLO.broker_time`:
```json
"broker_time": {
  "utc_offset_sec": 10800,
  "detected_at": "2026-07-27T09:15:02Z",
  "source": "INFERRED_SERVER_MINUS_GMT",
  "local_gmt_offset_sec": 25200,
  "local_dst_sec": 0
}
```

`HEARTBEAT.wire.broker_utc_offset_sec`: `10800`
ส่งทุก heartbeat (2s) → brain เห็น DST เปลี่ยนทันทีโดยไม่ต้องรอ HELLO ใหม่

---

## 4. Behaviour

### 4.1 การหา offset

```
raw      = ServerTime() − GmtTime()                 // เป็นวินาที
rounded  = round(raw / 900) × 900                   // ปัดเป็นทวีคูณของ 15 นาที
sample ใช้ได้เมื่อ:  |raw − rounded| ≤ 120
                 และ −43200 ≤ rounded ≤ 50400       // −12:00 … +14:00
```

| สถานการณ์ | ผลที่ต้องได้ |
|-----------|-------------|
| `raw = 10802` | `rounded = 10800` (+03:00) · sample ใช้ได้ |
| `raw = 9000` | `rounded = 9000` (+02:30) · ใช้ได้ — โบรกเกอร์ครึ่งชั่วโมงมีจริง |
| `raw = 10500` (ห่าง 300s) | ❌ sample **ไม่ใช้ได้** — ไม่ใกล้ทวีคูณ 15 นาที |
| `raw = 200000` | ❌ เกินขอบเขต |
| `ServerTime() == 0` | ❌ ยังไม่ต่อ server |

### 4.2 `Init()`

| สถานการณ์ | พฤติกรรม |
|-----------|----------|
| ได้ sample ใช้ได้ทันที | เก็บ offset · `IsValid()=true` · **log `DiagnosticLine()`** · คืน true |
| sample ไม่ใช้ได้ | ลองใหม่ทุก 200 ms รวม **ไม่เกิน 3 วินาที** |
| ครบ 3 วินาทีแล้วยังไม่ได้ | `IsValid()=false` · log `FATAL` พร้อมค่าดิบทุกตัว · **คืน false → `OnInit` ต้อง `INIT_FAILED`** |

`DiagnosticLine()` ต้องมีครบ 8 ค่า เพื่อให้คนดู log แล้วจับ VPS clock ผิดได้:
```
broker_time_init server=2026.07.27 12:15:02 gmt=2026.07.27 09:15:02
  local=2026.07.27 16:15:02 current=2026.07.27 12:15:02
  raw=10800 rounded=10800 local_gmt_offset=25200 local_dst=0
```

### 4.3 `Refresh()` — ตรวจ DST เปลี่ยน แบบมี debounce

| สถานการณ์ | พฤติกรรม |
|-----------|----------|
| ยังไม่ครบ 20 วินาทีจาก sample ล่าสุด | ไม่ทำอะไร คืน false (กัน `Refresh()` ราคาแพงทุก 1s) |
| sample ใหม่ = offset เดิม | รีเซ็ตตัวนับ candidate คืน false |
| sample ใหม่ ≠ offset เดิม ครั้งที่ 1–2 | **เก็บเป็น candidate ยังไม่เปลี่ยน** คืน false |
| sample ใหม่ ≠ offset เดิม **ครบ 3 ครั้งติด** (ค่าเดียวกันทั้ง 3) | ✅ เปลี่ยน offset · `LastChangeUtc()` · คืน **true** |
| candidate เปลี่ยนค่าไปมา | รีเซ็ตตัวนับ **ห้ามเปลี่ยน offset** |
| sample ไม่ใช้ได้ | ข้าม ไม่นับเป็น candidate และ**ไม่ทำให้ `IsValid()` เป็น false** |
| sample ไม่ใช้ได้ **ติดกัน > 90 วินาที** | `IsValid()=false` → EA ต้องเข้า SafeMode |

**ทำไมต้อง debounce 3 ครั้ง:** sample เดียวที่เพี้ยน (ServerTime กระตุกตอน reconnect)
จะเลื่อน offset ทั้งระบบ → เส้นแบ่งวันของ R6 ขยับ → `day_start_equity` ผิดวัน
3 sample × 20 วินาที = **ตรวจ DST ได้ช้าสุด 60 วินาที** ปีละ 4 ครั้ง — ยอมรับได้

### 4.4 เมื่อ offset เปลี่ยน (`Refresh()` คืน true) — caller ต้องทำ

1. log `WARN` พร้อม offset เก่า → ใหม่
2. ส่ง `ERROR` `severity: WARN` `code: BROKER_TIME_OFFSET_CHANGED` `fatal: false`
   `context: { "old_offset_sec": 7200, "new_offset_sec": 10800 }`
3. **ห้าม** ปิด session · **ห้าม** เข้า SafeMode — offset ที่เปลี่ยนถูกต้องคือเรื่องปกติปีละ 4 ครั้ง

### 4.5 การแปลงเวลา

```
BrokerToUtc(t) = t − OffsetSeconds()
UtcToBroker(t) = t + OffsetSeconds()
```

| ฟังก์ชัน | input | offset | output |
|---------|-------|--------|--------|
| `BrokerToUtc` | `2026.07.27 12:00:00` | +10800 | `2026.07.27 09:00:00` |
| `UtcToBroker` | `2026.07.27 09:00:00` | +10800 | `2026.07.27 12:00:00` |
| `FarmFormatIsoUtc` | `2026.07.27 09:00:00` | — | `"2026-07-27T09:00:00Z"` |

**เมื่อ `IsValid()==false`:** `BrokerToUtc`/`UtcToBroker`/`NowUtc` ต้อง**คืน 0**
ไม่ใช่คืนค่าที่คำนวณด้วย offset เก่า — และ caller ต้องเช็ค `IsValid()` ก่อนใช้
(ค่าที่ดูเหมือนถูกแต่ผิด อันตรายกว่าค่าที่เห็นชัดว่าพัง)

### 4.6 เส้นแบ่งวันตามเวลา broker

```
BrokerDayStart(t) = t − (t mod 86400)     // คำนวณบน datetime ที่เป็นเวลา broker แล้ว
```

| วัน | ช่วง 00:00→00:00 broker | ความยาวจริงใน UTC |
|-----|------------------------|-------------------|
| ปกติ | 24 ชม. | 24 ชม. |
| วันที่ DST เดินหน้า (spring) | 24 ชม.ตามนาฬิกา broker | **23 ชม.** |
| วันที่ DST ถอยหลัง (autumn) | 24 ชม.ตามนาฬิกา broker | **25 ชม.** |

**★ 23/25 ชม. คือพฤติกรรมที่ถูกต้อง ห้าม "แก้"** — ตรงกับที่โบรกเกอร์คิด swap
และ rollover จริง R6 ต้องวัดจาก 00:00 broker เท่านั้น

---

## 5. Edge cases ที่ต้องจัดการ

1. **ตลาดปิด (เสาร์-อาทิตย์)** — `TimeCurrent()` ค้างเพราะไม่มี tick
   ต้องใช้ `TimeTradeServer()` เท่านั้น · **`grep TimeCurrent` ใน BrokerTime.mqh ต้องไม่เจอ**
2. **นาฬิกา VPS ผิดเป็นชั่วโมงเต็ม** — ตรวจไม่ได้ด้วยวิธีนี้ (ปัดแล้วผ่านพอดี)
   → บังคับ: log `DiagnosticLine()` ทุกครั้งที่ `Init()` เพื่อให้คนตรวจย้อนได้
   → เป็นข้อกำหนดฝั่ง ops: **VPS ต้องเปิด NTP sync** ส่งต่อให้ runbook SPEC-030b
   **ห้ามแกล้งทำว่าโค้ดกันได้** — เขียนข้อจำกัดนี้ไว้ใน comment หัวไฟล์
3. **นาฬิกา VPS ผิด DST setting** — `TimeGMT()` เพี้ยน 1 ชม. เข้าเคสเดียวกับข้อ 2
4. `TimeDaylightSavings()` คืน DST ของ **เครื่อง local ไม่ใช่ของโบรกเกอร์** —
   ห้ามใช้ตัดสิน offset ของ broker ใช้ได้แต่ใส่ใน diagnostic
5. **DST เปลี่ยนตอน EA กำลังรัน** — `Refresh()` จับได้ใน ≤ 60s · bar/message ที่ส่งไปแล้ว
   ด้วย offset เก่ายังถูก เพราะตอนนั้น offset เก่าคือค่าที่ถูกจริง
6. **DST เปลี่ยนตอน EA ปิดอยู่** — `Init()` ตรวจใหม่ทุกครั้ง ไม่มี cache ข้าม session
7. **reconnect แล้ว `TimeTradeServer()` กระตุก** — sample ไม่ผ่านเกณฑ์ §4.1 ก็ข้ามไป
   ไม่ทำให้ `IsValid()` พังทันที (ต้องพลาดติดกัน > 90s)
8. **EA 2 ตัวบน terminal เดียว** — แต่ละตัวมี `CBrokerTime` ของตัวเอง แต่อ่านจาก
   API เดียวกันจึงได้ค่าเดียวกัน · ไม่ต้องแชร์ state ห้ามใช้ `GlobalVariable` มาซิงก์
9. **`BrokerDayStart` ตอน `IsValid()==false`** — คืน 0
10. **โบรกเกอร์ย้าย timezone ถาวร** (เกิดขึ้นจริงได้) — เข้ากลไกเดียวกับ DST
    debounce + log + `ERROR WARN` ไม่ต้องมี code path แยก
11. **offset ติดลบ** (โบรกเกอร์ฝั่งอเมริกา) — ต้องทำงานถูก `t mod 86400` ใน MQL5
    กับ `datetime` ที่เป็นค่าบวกเสมอไม่มีปัญหา แต่ต้องมี test
12. **`Init()` ถูกเรียกซ้ำ** (EA re-init ตอนเปลี่ยน timeframe) — ต้อง reset state
    ทั้งหมดก่อนตรวจใหม่ ห้ามค้าง candidate เดิม

---

## 6. Acceptance criteria

- [ ] `TestBrokerTime.mq5` compile 0 error 0 warning ด้วย `tools/compile-gate.ps1`
- [ ] `tools/run-mql5-tests.ps1` รัน suite `TestBrokerTime` แล้ว `status: PASS`
      พร้อม `ran_names` ครบ 15 ชื่อตาม §7
- [ ] `grep -rn "FarmIsoUtcFromBrokerTime" .` **ไม่เจออะไรเลย**
- [ ] `grep -n "TimeCurrent" mt5-ea/Include/Farm/BrokerTime.mqh` **ไม่เจอ**
- [ ] `grep -rn "TimeGMT()\|TimeTradeServer()\|TimeLocal()" mt5-ea/` เจอได้**เฉพาะใน
      `BrokerTime.mqh`** เท่านั้น — ที่อื่นห้ามเรียกเวลาเอง (นี่คือข้อพิสูจน์ "แหล่งเดียว")
- [ ] `ts_server` ที่ `Wire.mqh` ส่งออก = `FarmFormatIsoUtc(BrokerToUtc(NowBroker()))`
      และผ่าน pattern `common.json#/$defs/ts_utc`
- [ ] `ts_sent` = `FarmFormatIsoUtc(NowUtc())` · **`ts_sent ≥ ts_server` เสมอ**
      (ตอนนี้กลับกันเพราะ bug — latency ที่คำนวณได้เป็นลบ)
- [ ] `HELLO.broker_time` ส่งค่าจริงครบ 5 field · `HEARTBEAT.wire.broker_utc_offset_sec` ส่งค่าจริง
- [ ] รัน EA บน demo ตอนตลาดปิด (เสาร์/อาทิตย์) — `NowBroker()` ยังเดินหน้า
      และ heartbeat ไม่ขาด (พิสูจน์ว่าไม่ได้ใช้ `TimeCurrent()`)
- [ ] log ตอน `Init()` มี `DiagnosticLine()` ครบ 8 ค่า
- [ ] `Init()` คืน false → `FarmExecutor.OnInit` คืน `INIT_FAILED` (ทดสอบด้วย fake source)

## 7. Test list

`tests/mql5/TestBrokerTime.mq5` — **ทุก test ต้องใช้ `CBrokerClockSource` ปลอม**
เพื่อควบคุมเวลาได้ · ห้าม mock ตัว `CBrokerTime` เอง (จะไม่ได้ทดสอบตรรกะจริง)

| # | test | ตรวจอะไร | เกี่ยว rule |
|---|------|----------|-------------|
| 1 | `test_offset_detect_whole_hour` | raw 10802 → 10800 | §4.1 |
| 2 | `test_offset_detect_half_hour` | raw 9000 → 9000 | §4.1 |
| 3 | `test_offset_detect_negative` | offset ติดลบทำงานถูก | edge 11 |
| 4 | `test_offset_reject_non_quantized` | raw 10500 → sample ไม่ใช้ได้ | §4.1 |
| 5 | `test_offset_reject_out_of_bounds` | raw 200000 → reject | §4.1 |
| 6 | `test_init_fails_when_server_time_zero` | `ServerTime()=0` → `Init()` false | §4.2 |
| 7 | `test_roundtrip_broker_utc_identity` | `UtcToBroker(BrokerToUtc(t)) == t` ≥ 1000 ค่า | §4.5 |
| 8 | `test_format_iso_utc_matches_schema` | output ตรง pattern `ts_utc` ลงท้าย `Z` | schema |
| 9 | `test_invalid_returns_zero_not_stale` | `IsValid()=false` → แปลงคืน 0 | §4.5 |
| 10 | `test_dst_change_needs_three_samples` | 1–2 sample ไม่เปลี่ยน offset | §4.3 |
| 11 | `test_dst_change_accepted_on_third` | ครบ 3 → เปลี่ยน + คืน true | §4.3 |
| 12 | `test_dst_flap_does_not_change_offset` | candidate สลับค่า → ไม่เปลี่ยน | §4.3 |
| 13 | `test_broker_day_start_normal` | 00:00 broker ถูก | R6 |
| 14 | `test_broker_day_start_across_dst_23h_and_25h` | วัน DST ยาว 23 และ 25 ชม. | **R6** |
| 15 | `test_is_same_broker_day_across_utc_midnight` | UTC ข้ามวันแต่ broker ยังวันเดิม | **R6** |

**test 14 กับ 15 สำคัญที่สุด** — สองข้อนี้คือจุดที่ R6 จะ HALT ผิดวันถ้าทำผิด

## 8. Files

**Touch:** ตามตาราง §3.1

**ห้ามแตะ:**
- `contracts/schema/**` — Claude เพิ่ม field ให้แล้ว ถ้าคิดว่าต้องเพิ่มอีก → implementation note
- `docs/**` · `AGENTS.md` · `CLAUDE.md`
- `tests/mql5/TestWire.mq5` — เป็นของ SPEC-001 ที่ยังค้าง 4 ข้อ **อย่าแก้ทับ**

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | MetaEditor build ที่คุณใช้ มี API ที่ให้ offset ของ server ตรงๆ ไหม (ไม่ใช่ `TimeGMTOffset()` ที่เป็นของเครื่อง local)? | **ไม่บล็อก** — ทำวิธี infer ตาม §4.1 ไปเลย ถ้าเจอ API ตรงๆ ให้**รายงานใน implementation note ห้ามเปลี่ยนเอง** เพราะต้องตรวจก่อนว่าค่านั้นเชื่อถือได้ตอนตลาดปิดด้วยไหม |
| Q2 | `TimeTradeServer()` ตอนตลาดปิดยาว (สุดสัปดาห์ 2 วัน) drift ไปเท่าไร? | **ไม่บล็อก** — วัดแล้วรายงานตัวเลขจริงใน handoff · ถ้า drift > 60s ต้องเปิด ticket ใหม่ ไม่ใช่แก้ในนี้ |

> **ไม่มีคำถามที่บล็อก ticket นี้ — Codex เริ่มได้เลย**

---

## ภาคผนวก — ทำไม ticket นี้อยู่ก่อน SPEC-021

| ถ้าเวลา broker ผิด 3 ชม. | ผลที่ตามมา |
|--------------------------|-----------|
| R6 daily loss | เส้นแบ่งวันเลื่อน 3 ชม. → `day_start_equity` มาจากวันผิด → HALT ตอนไม่ควร หรือ**ไม่ HALT ตอนที่ควร** |
| R11 / R12 | flatten ผิดเวลา 3 ชม. → ถือ position ข้ามสุดสัปดาห์โดยไม่ตั้งใจ = รับ gap ที่ SL ไม่ช่วย |
| `bars` PK `(broker,symbol,timeframe,bar_time)` | **ทุกแถวติดป้ายเวลาผิด** แก้ย้อนหลังต้อง migrate ทั้งตาราง |
| SPEC-033 parity | backtest กับ live ไม่ตรงและ**หาสาเหตุไม่เจอ** เพราะทั้งสองฝั่ง "ดูถูก" ในมุมของตัวเอง |

ข้อ 3 กับ 4 คือเหตุผลที่ต้องทำ **ก่อน** เก็บข้อมูลจริง — ไม่ใช่หลังจากมีข้อมูลแล้ว
