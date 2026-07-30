# Review — SPEC-063 BrokerTime (รอบ 1)

**วันที่:** 2026-07-29 · **ผู้ตรวจ:** Claude · **สถานะ working tree:** uncommitted บน `feat/SPEC-001-mt5-executor`
**ตรวจจาก:** โค้ดจริง ไม่ใช่ handoff report (ยังไม่มี handoff)

## ผลตัดสิน: 🔴 `CHANGES_REQUIRED`

**เหตุผลหลักข้อเดียว:** ticket นี้มีเป้าหมายคือ *"ไม่รู้เวลา = ต้องเห็นชัดว่าไม่รู้"*
แต่โค้ดที่ส่งมา **ปลอมเวลาขึ้นมาเมื่อไม่รู้** (B1) — เป็นการกลับด้านของสิ่งที่ ticket นี้มีอยู่เพื่อทำ

---

## ✅ สิ่งที่ทำถูกและครบ — ไม่ต้องทำซ้ำ

| | หลักฐาน |
|---|---|
| `CBrokerClockSource` เป็น virtual seam จริง · test ใช้ fake source ทุกตัว | `TestBrokerTime.mq5:15-39` · ไม่มี mock `CBrokerTime` เอง ✅ |
| **acceptance "แหล่งเดียว" ผ่าน** | `grep "TimeGMT()\|TimeTradeServer()\|TimeLocal()\|TimeCurrent()" mt5-ea/ tests/mql5/` → **ไม่เจอนอก `BrokerTime.mqh`** ✅ |
| `FarmIsoUtcFromBrokerTime` ถูกลบจริง | `grep` เหลือแต่ใน `docs/` ✅ |
| `FarmMakeEnvelope` แยก `server_utc` / `sent_utc` เป็นสองพารามิเตอร์ | `Json.mqh:145-152` — ดีกว่าที่ spec ขอ เพราะทำให้ `ts_sent < ts_server` เขียนผิดยากขึ้น ✅ |
| quantize 900s + tolerance 120s + ขอบเขต −43200/50400 | `BrokerTime.mqh:67-72` ตรง §4.1 เป๊ะ ✅ |
| `Init()` ล้มเหลว → `INIT_FAILED` | `FarmExecutor.mq5:68-73` ✅ |
| `BrokerToUtc`/`UtcToBroker` คืน 0 เมื่อ `!IsValid()` | `BrokerTime.mqh:174-184` ✅ **(แต่ดู B1 — caller ทำลายคุณสมบัตินี้)** |
| `RoundToNearest` รองรับค่าติดลบถูก | `BrokerTime.mqh:47-52` ✅ |

---

## 🔴 ต้องแก้ก่อนผ่าน

### B1 · `Wire.mqh:219` และ `Wire.mqh:227` — **ปลอมเวลาเมื่อ `IsValid()==false`**

```mql5
if(utc_now <= 0)
   utc_now = (datetime)(1700000000 + (long)(GetTickCount64() / 1000ULL));
```

`1700000000` = **2023-11-14 UTC** · บวกวินาทีตั้งแต่เครื่องบูต

**ทำไมนี่คือ finding ที่ร้ายที่สุดของ ticket นี้:**

`CBrokerTime` ทำถูกแล้ว — คืน `0` เพื่อบอกว่า *"ไม่รู้"* ตาม §4.5
แล้ว `Wire` **แปลง "ไม่รู้" กลับเป็นตัวเลขที่หน้าตาถูกต้อง** ที่ปลายทาง

ผลที่เกิดจริงเมื่อ broker time ใช้ไม่ได้:

| | |
|---|---|
| `ts_server` / `ts_sent` | `"2023-11-14T…Z"` — **ผ่าน pattern `ts_utc` ทุกประการ** gateway รับเข้าไปโดยไม่มีอะไรฟ้อง |
| latency ที่ brain คำนวณ | ติดลบ ~3 ปี |
| `msg_id` (ULID) | ฝัง timestamp ปลอม → **ULID ของ session นี้เรียงมาก่อนทุก session ที่ถูกต้อง** → dedupe/ordering ของ gateway พัง (SPEC-013 §4.2 ใช้ `msg_id` เรียง) |
| log / audit trail | บอกว่าเหตุการณ์เกิดปี 2023 |
| ใครรู้บ้าง | **ไม่มีใครรู้** — ไม่มี WARN ไม่มี counter ไม่มี field ที่ต่างไป |

[SPEC-063 §4.5](../specs/SPEC-063-broker-time.md) เขียนไว้ตรงตัวว่า
*"ค่าที่ดูเหมือนถูกแต่ผิด อันตรายกว่าค่าที่เห็นชัดว่าพัง"* — บรรทัดนี้คือค่าที่ดูเหมือนถูกแต่ผิด

**ที่ต้องทำแทน:**

```mql5
// ไม่มี fallback — ไม่รู้เวลา = ไม่ส่ง
if(m_broker_time == NULL || !m_broker_time.IsValid())
   return false;   // ผู้เรียกต้องจัดการ ห้ามแต่งค่าขึ้นมา
```

- `SendHeartbeat` / `SendHello` / `SendErrorReport` → **ไม่ส่ง** + นับ `m_dropped_no_time++` + log WARN ครั้งแรก
- EA ที่ส่งอะไรไม่ได้เพราะไม่รู้เวลา **คืออาการที่ถูกต้อง** — gateway จะเห็น heartbeat หายแล้วตัด session ซึ่งเป็นสิ่งที่ควรเกิด
- `m_broker_time == NULL` (เช่นใน `TestWire`) ต้องแยกออกจาก `IsValid()==false` ให้ชัด — ถ้า TestWire ต้องการเวลาปลอม ให้**ฉีด fake `CBrokerTime` เข้าไป** ไม่ใช่ให้ production path มีทางลัด

> ⚠️ **นี่คือรูปแบบเดียวกับ G1 เป๊ะๆ** ([SPEC-061](../specs/SPEC-061-stale-data-guard.md)):
> ข้อมูลหาย → ใส่ค่าที่ดูปลอดภัย → ระบบทำงานต่อโดยไม่มีใครรู้ว่าตาบอดอยู่
> ครั้งนั้นคือ `correlation = 0` ครั้งนี้คือ `timestamp = 1700000000`

### B2 · `Wire.mqh:494` — `broker_utc_offset_sec` ส่ง `0` แทน `null`

```mql5
IntegerToString((… IsValid()) ? OffsetSeconds() : 0)
```

`heartbeat.json:34-38` เขียนไว้ชัด: **`null` = IsValid()=false ซึ่งแปลว่า EA ห้ามเทรด**

`0` เป็น offset ที่**ถูกต้องได้จริง** (โบรกเกอร์ที่ตั้งเวลาเป็น UTC) → brain แยกไม่ออกระหว่าง
*"broker อยู่ที่ UTC"* กับ *"EA ไม่รู้เวลาตัวเอง"* · schema type เป็น `["integer","null"]` อยู่แล้ว
→ ส่ง `null` ได้เลย ไม่ต้องแก้ schema

**เป็น bug class เดียวกับ B1** — ค่า sentinel ที่ทับกับค่าจริง

### B3 · `Wire.mqh` (BuildHelloPayload) — `"broker_time":null` จะทำให้ HELLO ถูก reject

`hello.json:35` เป็น `$ref` ไป `common.json#/$defs/broker_time_info` ซึ่งเป็น `"type": "object"`
→ ส่ง `null` = **validation FAIL**

field นี้ **optional** (ไม่อยู่ใน `required`) → เมื่อไม่มีค่าต้อง **ไม่ใส่ key เลย**

ตอนนี้ยังไม่ระเบิดเพราะ `echo_server.py` ไม่ validate — **จะระเบิดตอน SPEC-013 merge**
และอาการจะเป็น *"EA ต่อไม่ติดเลย"* ซึ่งไล่หาสาเหตุยากกว่าที่ควร

### B4 · `BrokerTime.mqh:121-158` — `Refresh()` ไม่มี throttle 20 วินาที

[§4.3](../specs/SPEC-063-broker-time.md) บรรทัดแรกของตาราง:
*"ยังไม่ครบ 20 วินาทีจาก sample ล่าสุด → ไม่ทำอะไร คืน false"* — **ไม่มีในโค้ดเลย**

`FarmExecutor.mq5:92` เรียก `Refresh()` ทุก `OnTimer` = ทุก 1 วินาที
→ debounce กลายเป็น **3 วินาที ไม่ใช่ 60 วินาที**

**ทำไมถึงสำคัญ:** ที่ต้องการไม่ใช่ "3 ครั้ง" แต่คือ "**3 ครั้งที่ห่างกันพอ**"
`TimeTradeServer()` กระตุกตอน reconnect ได้นานหลายวินาทีติดกัน — 3 sample ห่าง 1 วิ
อยู่ในช่วงกระตุกเดียวกันได้ทั้งหมด แล้ว offset ทั้งระบบเลื่อน → เส้นแบ่งวันของ R6 ขยับ
→ `day_start_equity` มาจากวันผิด ([§ภาคผนวก](../specs/SPEC-063-broker-time.md))

**ต้องวัดเวลาจาก clock source ไม่ใช่ `GetTickCount64()`** ไม่งั้นจะ test ไม่ได้ —
เก็บ `m_last_sample_gmt` แล้วเทียบ `GmtTime() - m_last_sample_gmt >= 20`

### B5 · `BrokerTime.mqh` — ไม่มีกลไก "sample ไม่ผ่านติดกัน > 90 วินาที → `IsValid()=false`"

[§4.3](../specs/SPEC-063-broker-time.md) แถวสุดท้ายบังคับไว้ · `Refresh()` ตอนนี้แค่ `return false`
เมื่อ `DetectOffset` ล้มเหลว **และไม่เคยตั้ง `m_valid = false` เลยหลัง `Init()` สำเร็จ**

แปลว่า: broker หยุดตอบเวลา → EA ใช้ offset เก่าไปเรื่อยๆ **ตลอดไป** โดยไม่มีทางเข้า SafeMode
— นี่คือ trigger ที่ SPEC-023 (R16/SafeMode) จะต้องพึ่ง

ต้องเพิ่ม `m_last_good_sample_gmt` + เมื่อพลาดติดกัน > 90s → `m_valid = false` + log FATAL

> 📌 **ความผิดของ spec ผมเอง:** [§7](../specs/SPEC-063-broker-time.md) ให้ test list 15 ตัว
> **แต่ไม่มีตัวไหนคุมข้อ B5 เลย** — behaviour ที่ไม่มี test คือ behaviour ที่จะไม่ถูกทำ
> ผมเพิ่ม **test 16** ให้แล้วใน §"spec ที่ผมต้องแก้" ด้านล่าง

### B6 · `TestBrokerTime.mq5:232-243` — `test_broker_day_start_across_dst_23h_and_25h` **ไม่ได้ทดสอบ DST เลย**

```mql5
AssertTrue(InitClock(clock, src, 7200), …);          // offset คงที่ 7200 ตลอด test
AssertEqualDatetime(clock.BrokerDayStart(MakeTime(2026,3,29,23,30,0)),
                    MakeTime(2026,3,29,0,0,0), …);
```

test นี้ **เหมือน `test_broker_day_start_normal` ทุกประการ** ยกเว้นวันที่ที่ใส่เข้าไป
· offset ไม่เคยเปลี่ยน · ไม่มีการวัดความยาว 23/25 ชม. ที่ไหนเลย
· ลบ `BrokerDayStart` ทิ้งแล้วเขียน `t - (t % 86400)` ตรงๆ ก็ยังผ่าน

[SPEC-063 §7](../specs/SPEC-063-broker-time.md) เขียนว่า **"test 14 กับ 15 สำคัญที่สุด — สองข้อนี้คือจุดที่ R6 จะ HALT ผิดวันถ้าทำผิด"**
ตอนนี้ test 14 คือ test ที่ผ่านโดยไม่พิสูจน์อะไร ซึ่ง [CLAUDE.md](../../CLAUDE.md) ระบุว่า
**อันตรายกว่า test แดง**

**ต้องเขียนใหม่ให้วัดของจริง:**

```mql5
// spring forward: offset 7200 → 10800 ระหว่างสองวัน
InitClock(clock, src, 7200);
const datetime day1_broker = clock.BrokerDayStart(MakeTime(2026,3,29,12,0,0));
const datetime day1_utc    = clock.BrokerToUtc(day1_broker);
ShiftOffsetTo(clock, src, 10800);                      // 3 sample ให้ครบ debounce
const datetime day2_broker = clock.BrokerDayStart(MakeTime(2026,3,30,12,0,0));
const datetime day2_utc    = clock.BrokerToUtc(day2_broker);
AssertEqualInt((int)(day2_utc - day1_utc), 23*3600, "…_23h");   // ★ นี่คือของจริง
// autumn: 10800 → 7200 ต้องได้ 25*3600
```

### B7 · `TestBrokerTime.mq5:172-177` — `test_invalid_returns_zero_not_stale` ทดสอบผิดเคส

ใช้ `CBrokerTime clock;` ที่**ไม่เคย `Init()`** → `m_valid=false` ตั้งแต่เกิด

แต่ชื่อ test คือ `not_stale` — เคสที่อันตรายจริงคือ **เคยมี offset แล้วกลายเป็น invalid**
แล้วยังคืนค่าที่คำนวณด้วย offset เก่า · test ปัจจุบันจับ regression นั้นไม่ได้เลย
(และตอนนี้ยัง**สร้างเคสนั้นไม่ได้ด้วยซ้ำ** เพราะ B5 ทำให้ไม่มีทางเข้าสถานะนั้น)

→ แก้พร้อม B5: ทำ sample พลาด > 90s → `IsValid()==false` → `BrokerToUtc(t)` ต้องเป็น 0

### B8 · `BrokerTime.mqh:84-119` — path ของ `Init()` ที่ test เดินไม่ใช่ path ที่ production เดิน

```mql5
if(src != NULL) { …ลองครั้งเดียว คืนผล… }     // ← ทุก test เดินทางนี้
const ulong started = GetTickCount64();        // ← production เท่านั้น
while(GetTickCount64() - started <= 3000ULL) { …retry 200ms… }
```

**loop retry 3 วินาทีตาม §4.2 ไม่มี test แตะเลยสักตัว** และ seam ถูกใช้ผิดจุดประสงค์ —
`src != NULL` กลายเป็น *"นี่คือ test"* แทนที่จะเป็น *"นาฬิกามาจากไหน"*

แก้: ให้ retry loop เดินทางเดียวกันทั้งสองกรณี แล้วทำ `Sleep`/deadline ผ่าน seam
(`virtual void SleepMs(int)` หรือรับ `max_wait_ms` เป็นพารามิเตอร์ให้ test ส่ง 0)

### B9 · `FarmExecutor.mq5:96` — error code + context ไม่ตรง spec

| | spec §4.4 | โค้ด |
|---|---|---|
| code | `BROKER_TIME_OFFSET_CHANGED` | `BROKER_UTC_OFFSET_CHANGED` |
| context | `{"old_offset_sec":7200,"new_offset_sec":10800}` | `{}` — ยัด diagnostic ทั้งก้อนลง `message` |

`error.json` ยังไม่ได้ล็อก `code` เป็น enum → **จะไม่ fail validation** แต่ brain จะ
match code ไม่เจอ และ **context ที่อ่านด้วยเครื่องได้หายไป** — alert/dashboard ต้อง regex ข้อความ

ใช้ชื่อตาม spec · ใส่ `context` ให้ครบ (`PreviousOffsetSeconds()` มีอยู่แล้ว)

### B10 · `BrokerTime.mqh:244-256` — `DiagnosticLine()` ไม่ครบตาม §4.2

| | |
|---|---|
| ขาด `LocalTime()` | `CBrokerClockSource::LocalTime()` **ถูกประกาศไว้แต่ไม่เคยถูกเรียกที่ไหนเลย** — dead virtual |
| ค่าเวลาเป็น epoch (`%I64d`) | §4.2 ตัวอย่างเป็น `2026.07.27 12:15:02` · จุดประสงค์ของบรรทัดนี้คือ**ให้คนอ่านแล้วจับนาฬิกา VPS ผิดได้** (edge 2) — epoch ทำหน้าที่นั้นไม่ได้ |
| ขาด `rounded` แยกจาก `offset` | ตอน `Init()` ล้มเหลว `m_offset_sec` ยังเป็น 0 → ไม่รู้ว่า sample ที่ปัดแล้วได้เท่าไร |

---

## 🟠 ควรแก้ — ไม่บล็อกแต่ต้องมีคำตอบใน handoff

### B11 · `Wire.mqh:32` — ULID seed ถอย `TimeLocal()` → `GetTickCount64()` โดยไม่แจ้ง

นี่คือการ **กลับคำตัดสินที่ผมอนุมัติไปแล้ว** ใน [work-order §1.2](../work-order.md)
`GetTickCount64()` = ms ตั้งแต่**เครื่องบูต** → EA 2 ตัวบน VPS เดียวกันได้ค่าใกล้กันมาก
ซึ่งเป็นข้อบกพร่องเดียวกับที่ §1.2 บอกให้แก้ตอนแรก

**แต่ผมเข้าใจว่าทำไม** — acceptance `grep TimeLocal()` ของผมบังคับให้ต้องเอาออก
**นี่เป็นความผิดของ spec ผม ไม่ใช่ของคุณ** (ดู §"spec ที่ผมต้องแก้")

ทางแก้: `CBrokerTime::LocalTime()` เปิด accessor แล้ว `Wire` ขอผ่าน `m_broker_time`
· ยังคง "แหล่งเดียว" · ได้ entropy ที่ต่างจริงต่อเครื่องกลับมา

### B12 · `TestWire.mq5:406` — `started_at` กลายเป็น literal `"tester"`

เหตุผลเดียวกับ B11 (หนี grep) แต่ **แลกด้วยข้อมูล forensic** — result JSON ไม่บอกอีกแล้วว่ารันเมื่อไร

ทางแก้ที่ถูกกว่า: **ให้ `run-mql5-tests.ps1` เป็นคนประทับเวลา** ตอนอ่านผล —
PowerShell มีนาฬิกาที่เชื่อถือได้และไม่อยู่ใต้กฎ "แหล่งเดียว" ของ MQL5

### B13 · `Wire.mqh` — `detected_at` ใน HELLO ส่ง `NowUtc()` ไม่ใช่เวลาที่ตรวจได้จริง

field ชื่อ `detected_at` แต่ค่าคือ "ตอนนี้" → ดูไม่ออกว่า offset ถูกตรวจเมื่อ 3 วินาทีก่อน
หรือ 3 ชั่วโมงก่อน · เก็บ `m_detected_at_utc` ตอนที่ยอมรับ offset แล้วส่งค่านั้น

---

## 📌 spec ที่ผมต้องแก้ (ความผิดของผม ไม่ใช่ของ Codex)

| # | สิ่งที่ผมเขียนผิด/ขาด | แก้เป็น |
|---|----------------------|---------|
| 1 | acceptance `grep TimeLocal()` เหมารวมเกินไป → บังคับให้ Codex ทำ B11/B12 | ยกเว้น: (ก) ULID seed ที่ขอผ่าน `CBrokerTime` (ข) metadata ของ test harness · **กฎที่ตั้งใจจริงคือ "ห้ามใช้เวลาตัดสินใจนอก BrokerTime" ไม่ใช่ "ห้ามพิมพ์ชื่อฟังก์ชัน"** |
| 2 | §7 ไม่มี test คุม §4.3 แถว 90 วินาที (B5) | เพิ่ม **test 16 `test_invalid_after_90s_of_bad_samples`** |
| 3 | §7 test 14 เขียนสั้นจน implement เป็น test ที่ไม่พิสูจน์อะไรได้ (B6) | ระบุให้ชัดว่าต้อง **วัด `BrokerToUtc(dayStart)` สองวันคร่อม offset change แล้วต่างกัน 23/25 ชม.** |
| 4 | §4.5 พูดถึงพฤติกรรมของ `CBrokerTime` แต่ไม่ได้ห้าม caller แต่งค่าเอง (B1) | เพิ่มข้อบังคับ: **"ห้ามมี fallback timestamp ที่ไหนในระบบ · ไม่รู้เวลา = ไม่ส่ง message"** + acceptance `grep` ห้ามเจอตัวเลข epoch คงที่ในโค้ด |
| 5 | ไม่ได้บอกว่า optional field ที่ไม่มีค่าต้อง **ละ key** ไม่ใช่ส่ง `null` (B3) | เขียนเป็นกฎทั่วไปใน [02-contracts](../02-contracts.md) — ใช้กับทุก optional field ที่เป็น object |

**ผมจะแก้ SPEC-063 ให้ครบ 5 ข้อนี้ก่อน Codex เริ่มรอบแก้** — อย่าเพิ่งลงมือจนกว่า spec rev.2 จะออก

---

## สรุปสิ่งที่ต้องทำ เรียงตามลำดับ

1. **B1** ลบ fallback timestamp ทั้งสองจุด → ไม่รู้เวลา = ไม่ส่ง (สำคัญที่สุด)
2. **B5 + B4** เพิ่ม throttle 20s และ invalidate ที่ 90s (สองข้อนี้ผูกกัน)
3. **B6 + B7** เขียน test 14 กับ 9 ใหม่ให้พิสูจน์ของจริง + เพิ่ม test 16
4. **B2 + B3** `null` เมื่อไม่รู้ · ละ key เมื่อไม่มีค่า
5. **B8** ให้ test เดิน path เดียวกับ production
6. **B9 + B10** code/context/diagnostic ตาม spec
7. **B11 + B12 + B13** หลัง spec rev.2 ออก

**ห้ามรัน gate แล้วรายงาน PASS จนกว่าข้อ 1–4 จะเสร็จ** — gate ปัจจุบันจะเขียวทั้งที่ B1 ยังอยู่
เพราะไม่มี test ตัวไหนแตะ path นั้นเลย
