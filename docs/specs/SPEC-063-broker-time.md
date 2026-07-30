# SPEC-063 — BrokerTime: แหล่งความจริงเดียวเรื่องเวลา

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-001 · **Blocks:** SPEC-010, SPEC-019, SPEC-021, SPEC-033
**ปิดช่องว่าง:** [G6](../06-gap-audit.md#g6) · **แก้ finding:** [SPEC-003 handoff ❸](../reviews/SPEC-003-schema-handoff.md)

> ## rev.2 — 2026-07-30 · แก้ข้อผิดพลาดของ spec เอง 7 จุด
>
> หลัง [review รอบ 1](../reviews/SPEC-063.md) พบว่า **7 จุดในฉบับ rev.1 เป็นความผิดของ spec
> ไม่ใช่ของ implementation** — บางข้อ *บังคับ* ให้เขียนโค้ดที่แย่ลง
>
> | # | แก้อะไร | อยู่ที่ | finding |
> |---|---------|--------|---------|
> | 1 | acceptance `grep` เวลาเหมารวมเกินไป จนต้องถอย ULID seed + ทิ้ง `started_at` | **§6 เขียนใหม่ทั้งข้อ** | B11 · B12 |
> | 2 | §4.5 ไม่ได้ห้าม caller แต่งเวลาปลอมขึ้นมาเอง | **§4.7 ใหม่** | B1 |
> | 3 | §4.3 แถว 90 วินาที ไม่มี test คุมเลย | **test 16 ใหม่** | B5 · B7 |
> | 4 | test 14 เขียนสั้นจน implement เป็น test ที่ไม่พิสูจน์อะไรได้ | **§7.1 ใหม่** | B6 |
> | 5 | ไม่ได้บอกว่า optional field ที่ไม่มีค่าต้อง **ละ key** ไม่ใช่ส่ง `null` | **§4.8 ใหม่** | B3 |
> | 6 | §4.2 retry loop 3 วินาที **ไม่มี seam ให้ test เดินได้** จึงกลายเป็น dead path | **§3.2 `SleepMs()`** + test 17 | B8 |
> | 7 | `CBrokerTime` ไม่มีทางให้ caller ขอเวลา local อย่างถูกกฎ → บังคับให้ถอยไป `GetTickCount64()` | **§3.2 `LocalTime()`** | B11 |
>
> **Codex: อ่าน rev.2 ให้ครบก่อนเริ่มรอบแก้** — โดยเฉพาะ §4.7 ซึ่งเป็น finding ที่ร้ายที่สุด
> · ลำดับการแก้อยู่ท้าย [review](../reviews/SPEC-063.md) — ข้อ 1–4 ต้องเสร็จก่อนรัน gate

> ## rev.2a — 2026-07-30 · หลัง [review รอบ 2](../reviews/SPEC-063-02.md)
>
> **3 ข้อแรกคือผมถอน/ผ่อนข้อบังคับของตัวเอง** เพราะโค้ดที่ Codex ส่งมาถูกกว่าที่ผมเขียน
> · ข้อ 4–5 คือช่องว่างที่ review รอบ 2 เปิดโปงว่า spec ไม่ได้เขียนไว้เลย
>
> | # | แก้อะไร | อยู่ที่ | finding |
> |---|---------|--------|---------|
> | 1 | deadline ของ `Init()` วัดด้วย **ตัวนับ `elapsed_ms`** ไม่ใช่ `GmtTime()` — เอา deadline ไปผูกกับนาฬิกาที่กำลังสงสัยว่าพังคือความคิดที่ผิด | §4.2 | B8 |
> | 2 | **ถอน**ข้อบังคับ ULID seed ต้องผ่าน `LocalTime()` — seed เดิมมี `ChartID()` + `ACCOUNT_LOGIN` อยู่แล้ว ผมตรวจไม่ครบเอง | §6.2 c | B11 |
> | 3 | WARN throttle **ผ่อนเป็น 2 แบบ** แต่**บังคับให้ reset counter** เมื่อกลับมาส่งได้ | §6.3 | B17 |
> | 4 | §4.3 ไม่เคยเขียนว่า **กลับมาจาก `IsValid()==false` ต้องทำอะไร** → offset เปลี่ยนได้แบบเงียบ | **§4.3.2 ใหม่** | **B15** |
> | 5 | §4.3 ไม่ระบุว่า 90 วินาทีต้องวัดด้วยนาฬิกาไหน → implement ใช้ `LocalTime()` ซึ่งพังตอน DST | **§4.3.1 ใหม่** | **B16** |
>
> ⚠️ **B4 (throttle 20s ใน `Refresh()`) ยังไม่ถูกแก้มาตั้งแต่รอบ 1** — spec §4.3 แถวแรกถูกต้องอยู่แล้ว
> ไม่ต้องแก้ spec แต่ **โค้ดยังไม่มี** · ดูลำดับการแก้ใน [review รอบ 2](../reviews/SPEC-063-02.md)

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
| `tools/run-mql5-tests.ps1` | **แก้** — เพิ่ม suite `TestBrokerTime` · **rev.2:** เป็นคนประทับ `started_at` ลง result JSON ตอนอ่านผล (§6.2 ข้อ d) แทนที่จะให้ MQL5 ทำ |

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

   // ★ rev.2 — seam ที่ทำให้ retry loop ของ §4.2 ทดสอบได้ (finding B8)
   // production: Sleep(ms) · fake: เลื่อนนาฬิกาปลอมไปข้างหน้าโดยไม่หยุดจริง
   virtual void     SleepMs(const int ms) { Sleep(ms); }
};

class CBrokerTime
{
public:
   // src = NULL → ใช้ API จริง · test ส่ง fake source เข้ามา
   // คืน false ถ้าหา offset ที่เชื่อถือได้ไม่ได้ → OnInit ต้อง INIT_FAILED
   // ★ rev.2: ทั้งสองกรณีต้องเดิน **code path เดียวกัน** (§4.2 · finding B8)
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

   // ---- entropy / diagnostic เท่านั้น · ★ rev.2 (finding B11) ----
   // ผ่านต่อจาก m_src.LocalTime() ตรงๆ — ไม่แปลงอะไร
   // มีไว้ให้ caller ที่ต้องการ entropy ต่างต่อเครื่อง (ULID seed) ขอได้**โดยไม่ผิดกฎแหล่งเดียว**
   // ❌ ห้ามใช้ค่านี้ตัดสินใจอะไรทั้งสิ้น — เวลาที่ใช้ตัดสินใจมีแค่ NowBroker()/NowUtc()
   datetime LocalTime() const;

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

#### ★ rev.2 — retry loop ต้องเป็น path เดียวกันทั้ง production และ test (finding B8)

rev.1 ไม่ได้บอกว่า `src != NULL` แปลว่าอะไร → implement ออกมาเป็น

```mql5
if(src != NULL) { …ลองครั้งเดียวแล้วคืนผล… }   // ทุก test เดินทางนี้
…retry loop 3 วินาที…                          // production เท่านั้น — ไม่มี test แตะเลย
```

`src != NULL` กลายเป็นความหมาย *"นี่คือ test"* แทนที่จะเป็น *"นาฬิกามาจากไหน"*
**seam ที่แยก path คือ seam ที่ทดสอบผิดตัว** — loop ที่ต้องทำงานตอน VPS บูตช้าไม่เคยถูกรัน

**ข้อบังคับ rev.2:**

| | |
|---|---|
| `Init()` มี **loop เดียว** เดินเหมือนกันทุกกรณี | `src == NULL` แค่แปลว่า "ใช้ `CBrokerClockSource` ตัวจริง" |
| หน่วงระหว่างรอบ | เรียก `m_src.SleepMs(200)` **ห้ามเรียก `Sleep()` ตรงๆ** |
| วัด deadline 3 วินาที | **ตัวนับ `elapsed_ms += 200` ทุกรอบ** — ห้ามใช้ `GetTickCount64()` และ**ไม่ต้อง**ใช้ `GmtTime()` |

> **rev.2a (2026-07-30) — ผมแก้ข้อนี้ตามโค้ดที่ Codex ส่งมา ไม่ใช่ทางกลับกัน**
> rev.2 ผมเขียนว่าให้วัด deadline จาก `GmtTime()` · Codex implement เป็นตัวนับแทน
> ([`BrokerTime.mqh:127-138`](../../mt5-ea/Include/Farm/BrokerTime.mqh)) ซึ่ง **ถูกกว่าที่ผมเขียน**:
> `Init()` คือจังหวะที่เรากำลังสงสัยนาฬิกาอยู่พอดี — เอา deadline ไปผูกกับนาฬิกาที่อาจพัง
> ทำให้ loop วนไม่รู้จบได้ถ้า `GmtTime()` ค้าง · ตัวนับ deterministic และไม่พึ่งอะไรเลย
>
> ⚠️ **§4.3 throttle 20 วินาที ยังต้องใช้ `GmtTime()` เหมือนเดิม** — คนละเรื่องกัน
> ตรงนั้นวัด*ระยะห่างจริงระหว่าง sample* ซึ่งตัวนับรอบแทนไม่ได้
| fake `SleepMs(ms)` ใน test | ต้องเลื่อน **ทั้ง `ServerTime()` และ `GmtTime()` ไปพร้อมกัน** เท่ากับ `ms` — ถ้าเลื่อนข้างเดียว offset จะขยับเองโดยไม่ตั้งใจ แล้ว test จะพิสูจน์คนละเรื่อง |

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
| sample ไม่ใช้ได้ **ติดกัน > 90 วินาที** | `IsValid()=false` → EA ต้องเข้า SafeMode · **วัดเวลาด้วย `GmtTime()` ห้ามใช้ `LocalTime()`** (rev.2a — ดู §4.3.1) |
| **`IsValid()==false` อยู่ แล้วได้ sample ที่ใช้ได้** | **rev.2a ใหม่ — ดู §4.3.2** · กลับเป็น valid ทันทีโดยไม่ต้อง debounce **แต่ถ้า offset ต่างจากเดิมต้องคืน `true`** |

#### 4.3.1 ทำไมต้องวัด 90 วินาทีด้วย `GmtTime()` (rev.2a · finding B16)

`LocalTime()` = เวลาเครื่องหลังบวก timezone + DST ของ VPS ซึ่ง**กระโดดปีละ 2 ครั้ง**:

| | ผลถ้าใช้ `LocalTime()` |
|---|---|
| DST เดินหน้า (+1 ชม.) | ผลต่างกระโดดเป็น 3600 → **invalidate ทันทีทั้งที่ทุกอย่างปกติ** |
| DST ถอยหลัง (−1 ชม.) | ผลต่าง**ติดลบ** → `> 90` ไม่มีวันเป็นจริง → **ไม่ invalidate เลยตลอดชั่วโมงนั้น** ★ |

ข้อล่างอันตรายกว่า เพราะเป็นชั่วโมงที่ระบบตาบอดโดยไม่มีใครรู้
· `GmtTime()` ไม่มีปัญหาทั้งสองข้อ · สอดคล้องกับ [§5 edge 4](#5-edge-cases-ที่ต้องจัดการ) ที่ห้ามใช้
DST ของเครื่อง local มาตัดสินอะไรเกี่ยวกับ broker

ถ้า `GmtTime()` เองคืน `<= 0` → เข้าเงื่อนไข sample ไม่ใช้ได้อยู่แล้ว (§4.1) จึงไม่ต้องมี path แยก

#### ★★ rev.2b — `datetime` เป็น unsigned · **cast เป็น `long` ก่อนลบเสมอ**

rev.2a บอกให้ใช้ `GmtTime()` แต่**ไม่ได้บอกเรื่องชนิดข้อมูล** ซึ่งเป็นอีกครึ่งของบั๊กเดียวกัน

`datetime` ใน MQL5 เป็นจำนวนเต็ม**ไม่มีเครื่องหมาย** → เมื่อนาฬิกาถอยหลัง
`a - b` จะ **underflow เป็นค่าบวกมหาศาล** ไม่ใช่ค่าลบที่คาดไว้

```mql5
// ❌ ห้าม — ผลลัพธ์ตอนนาฬิกาถอยหลังเดาไม่ได้
if(now - m_last_sample < 20) …
if(now - m_bad_started > 90) …

// ✅ ต้องเป็น
const long now_gmt = (long)m_src.GmtTime();
if(m_last_sample_gmt > 0 && now_gmt - m_last_sample_gmt < 20) …
```

**กฎทั่วไปของ ticket นี้:** ทุกจุดที่หา *ระยะเวลา* ต้อง cast เป็น `long` ก่อน
· เก็บฟิลด์เวลาที่ใช้วัดระยะเป็น `long` ไปเลย ไม่ใช่ `datetime`
· ชื่อฟิลด์ต้องลงท้าย `_gmt` เพื่อให้เห็นแหล่งเวลาโดยไม่ต้องไล่โค้ด

**ตรรกะ 90 วินาทีต้องมีสำเนาเดียว** — ถ้า throttle ต้องเช็คด้วย ให้เรียกฟังก์ชันเดียวกัน
ห้ามเขียนซ้ำสองที่ (state machine สองสำเนาจะค่อยๆ ต่างกัน)

#### 4.3.2 ★★ กลับมาจาก invalid — **ห้ามเงียบ** (rev.2a · finding B15)

> **ช่องว่างของ spec ที่ผมเขียนตกไปเอง:** rev.2 บังคับให้ `IsValid()` เป็น `false` ได้ (§4.3)
> แต่ **ไม่เคยเขียนว่าตอนกลับมาต้องทำอะไร** → implement ออกมาเป็น "รับ offset ใหม่แล้ว `return false`"
> ซึ่งเปิดทางให้ offset ของทั้งระบบเปลี่ยนโดยไม่มีใครรู้

สถานการณ์ที่ต้องรอด: broker หยุดตอบเวลา → ครบ 90s → `IsValid()=false` →
**ระหว่างที่ตาบอดอยู่นั้น DST เปลี่ยน** → broker กลับมาที่ offset ใหม่ → sample ดีตัวแรกเข้ามา

| | ต้องทำ | ห้ามทำ |
|---|--------|--------|
| `IsValid()` | กลับเป็น `true` **ทันที ไม่ต้องรอ debounce** — เรากำลังฟื้นจากสถานะที่ห้ามเทรดอยู่แล้ว การรออีก 60 วินาทีไม่ได้ปลอดภัยขึ้น | รอ 3 sample |
| `offset` เท่าเดิม | คืน **`false`** (ไม่มีอะไรเปลี่ยน) | — |
| **`offset` ต่างจากเดิม** | ★ คืน **`true`** → caller log + ส่ง `ERROR` ตาม §4.4 | คืน `false` |
| `PreviousOffsetSeconds()` | = offset **ก่อนหน้า** ที่แท้จริง | ทับด้วยค่าใหม่ |
| `LastChangeUtc()` | อัปเดตเป็นเวลาที่เปลี่ยน | ปล่อยค้างค่าเก่า |

**ข้อบังคับเพิ่มเติมกับ `AcceptOffset()`:** ห้ามตั้ง `m_previous_offset_sec = detected`
· ตอน `Init()` ให้เป็น **`0`** = *"ไม่เคยมีค่าก่อนหน้า"* · ตอน re-accept ให้เป็น offset เดิมจริง
— ไม่งั้น `context.old_offset_sec` ของ §4.4 จะรายงานค่าใหม่ทั้งสองช่อง

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

### 4.7 ★★ ห้ามมี fallback timestamp ที่ใดในระบบ — **เพิ่มใน rev.2**

`CBrokerTime` คืน `0` เพื่อบอกว่า *"ไม่รู้"* (§4.5) · **ห้ามให้ผู้เรียกแปลง "ไม่รู้" กลับเป็นตัวเลข**

```mql5
// ❌ ห้ามเด็ดขาด — ทุกรูปแบบ
if(utc <= 0) utc = (datetime)(1700000000 + GetTickCount64()/1000);
if(utc <= 0) utc = TimeGMT();
if(utc <= 0) utc = m_last_known_utc;
```

**ทำไมข้อนี้ถึงสำคัญกว่าที่ดู:** timestamp ปลอมจะ**ผ่าน `common.json#/$defs/ts_utc` ทุกประการ**
gateway รับเข้าไปโดยไม่มีอะไรฟ้อง · ฝังลง ULID → ลำดับ message ของทั้ง session ผิดที่
· latency ที่ brain คำนวณกลายเป็นค่าติดลบหลายปี · และ **ไม่มี log บรรทัดไหนบอกว่าเกิดอะไรขึ้น**

| สถานการณ์ | ต้องทำ |
|-----------|--------|
| `IsValid() == false` ตอนจะส่ง message | **ไม่ส่ง** · `messages_dropped_no_time++` · log WARN ครั้งแรกของช่วง |
| `m_broker_time == NULL` (ยังไม่ได้เสียบ) | **ถือว่าเป็น bug ของ caller** — log FATAL ไม่ใช่ทำงานต่อแบบเงียบ |
| test ที่ต้องการเวลาแน่นอน | **ฉีด `CBrokerTime` ที่ Init ด้วย fake clock** ห้ามให้ production path มีทางลัดสำหรับ test |

EA ที่ส่งอะไรไม่ได้เพราะไม่รู้เวลา **คืออาการที่ถูกต้อง** — gateway จะเห็น heartbeat หาย
แล้วตัด session ซึ่งเป็นสิ่งที่ควรเกิด · ดีกว่าส่งข้อมูลที่ดูดีแต่ผิดเข้า audit trail

> 📌 นี่คือ bug class เดียวกับ **G1 / [SPEC-061](SPEC-061-stale-data-guard.md)**:
> ข้อมูลหาย → ใส่ค่าที่ดูปลอดภัย → ระบบทำงานต่อโดยไม่มีใครรู้ว่าตาบอดอยู่
> ครั้งนั้นคือ `correlation = 0` · ครั้งนี้คือ timestamp ปลอม
> **หลักการเดียวกัน: "ไม่รู้" ต้องเห็นชัดว่าไม่รู้ ห้ามแปลงเป็นค่าที่หน้าตาปกติ**

### 4.8 optional field ที่ไม่มีค่า — **ละ key ห้ามส่ง `null`** (เพิ่มใน rev.2)

| field | เมื่อ `IsValid()==false` | เหตุผล |
|-------|-------------------------|--------|
| `HELLO.broker_time` | **ไม่ใส่ key เลย** | `$ref` ชี้ไป `broker_time_info` ซึ่งเป็น `"type":"object"` → `null` = **validation FAIL** → gateway ปฏิเสธ HELLO ทั้งใบ |
| `HEARTBEAT.wire.broker_utc_offset_sec` | **`null`** | schema เป็น `["integer","null"]` และเขียนไว้ชัดว่า `null` = `IsValid()=false` · **ห้ามส่ง `0`** เพราะ 0 เป็น offset ที่ถูกต้องได้จริง (โบรกเกอร์ที่ตั้งเวลาเป็น UTC) → brain แยกไม่ออกระหว่าง "broker อยู่ที่ UTC" กับ "EA ไม่รู้เวลาตัวเอง" |

**กฎทั่วไปที่ใช้กับทุก optional field:** ถ้า schema ไม่ได้ระบุ `"null"` ไว้ใน `type`
→ ไม่มีค่า = **ละ key** · ถ้าระบุ `"null"` ไว้ → ส่ง `null` และ**ห้ามใช้ค่า sentinel
ที่ทับกับค่าจริงได้** (`0`, `-1`, `""`)

> 📌 **กฎนี้ถูกยกขึ้นเป็นกฎกลางของทั้งโปรเจกต์แล้ว** → [`02-contracts.md §8`](../02-contracts.md#8--กฎการส่งค่าเมื่อ-ไม่รู้--ใช้กับทุก-message-ทุก-field)
> ใช้กับทุก message ไม่ใช่แค่ ticket นี้ · ถ้าสองที่ขัดกัน **ให้ยึด 02-contracts §8**

`detected_at` ต้องเป็น**เวลาที่ยอมรับ offset นั้นจริง** ไม่ใช่ `NowUtc()` ตอนสร้าง payload
— ไม่งั้นดูไม่ออกว่า offset ถูกตรวจเมื่อ 3 วินาทีก่อนหรือ 3 ชั่วโมงก่อน

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

### 6.1 พื้นฐาน

- [ ] `TestBrokerTime.mq5` compile 0 error 0 warning ด้วย `tools/compile-gate.ps1`
- [ ] `tools/run-mql5-tests.ps1` รัน suite `TestBrokerTime` แล้ว `status: PASS`
      พร้อม `ran_names` **อย่างน้อย 17 ชื่อ** ตาม §7 (rev.2 เพิ่ม test 16 + 17)
      · **เกินได้ ไม่ใช่ปัญหา** — §7 คือพื้นขั้นต่ำ ไม่ใช่เพดาน
- [ ] `grep -rn "FarmIsoUtcFromBrokerTime" .` **ไม่เจออะไรเลย**
- [ ] `grep -n "TimeCurrent" mt5-ea/Include/Farm/BrokerTime.mqh` **ไม่เจอ**
- [ ] log ตอน `Init()` มี `DiagnosticLine()` ครบ 8 ค่า (รวม `LocalTime()` และ `rounded` แยกจาก `offset`)
- [ ] `Init()` คืน false → `FarmExecutor.OnInit` คืน `INIT_FAILED` (ทดสอบด้วย fake source)

### 6.2 ★ "แหล่งเดียว" — วัดที่ **เจตนา** ไม่ใช่ที่ชื่อฟังก์ชัน (เขียนใหม่ใน rev.2)

> **ที่ rev.1 เขียนผิด:** acceptance เดิมคือ *"`grep TimeLocal()` ห้ามเจอนอก `BrokerTime.mqh`"*
> ซึ่ง **ไม่ใช่กฎที่ผมตั้งใจ** และมีราคาจริง — Codex ต้องถอย ULID seed ไปใช้
> `GetTickCount64()` (กลับคำตัดสิน [work-order §1.2](../work-order.md)) และทิ้ง `started_at`
> ของ test result เป็น literal `"tester"` เพียงเพื่อ**หนี grep** ทั้งสองอย่างทำให้ระบบแย่ลง
>
> **กฎที่บังคับจริงคือ: ห้ามมี "การตัดสินใจที่ใช้เวลา" เกิดขึ้นนอก `BrokerTime.mqh`**
> — ไม่ใช่ "ห้ามพิมพ์ชื่อฟังก์ชันนั้น"

**นิยามที่ใช้ตัดสิน:** "การตัดสินใจที่ใช้เวลา" = ค่าที่ไปโผล่ใน **message บนสาย** ·
**เส้นแบ่งวัน/ชั่วโมงเทรด** · หรือ **เงื่อนไข timeout/expiry** ใดๆ
ค่าที่ใช้เป็น **entropy** หรือ **metadata สำหรับมนุษย์อ่าน** ไม่นับ

| # | ตรวจ | เกณฑ์ |
|---|------|-------|
| a | `grep -rn "TimeGMT()\|TimeTradeServer()\|TimeCurrent()\|TimeLocal()\|TimeGMTOffset()\|TimeDaylightSavings()" mt5-ea/` | เจอได้**เฉพาะใน `BrokerTime.mqh`** |
| b | `grep -rn "TimeGMT()\|TimeTradeServer()\|TimeLocal()" tests/mql5/` | เจอได้**เฉพาะในคลาส fake `CBrokerClockSource`** ของ test — ที่อื่นในไฟล์ test ห้ามเจอ |
| c | ULID seed ใน `Wire.mqh` | ✅ **ผ่านแล้ว ไม่ต้องแก้** — ดูกล่องด้านล่าง |
| d | `started_at` ใน result JSON ของ test suite | **`run-mql5-tests.ps1` เป็นคนประทับตอนอ่านผล** — PowerShell มีนาฬิกาที่เชื่อถือได้และไม่อยู่ใต้กฎนี้ · ค่า literal `"tester"` **ไม่ผ่าน** (ทิ้งข้อมูล forensic ไปเปล่าๆ) |

> #### rev.2a — ผมถอนข้อ c ที่เคยบังคับไว้ (finding B11 ที่ผมตรวจผิดเอง)
>
> rev.2 ผมสั่งให้ ULID seed ขอผ่าน `m_broker_time.LocalTime()` โดยอ้างว่า `GetTickCount64()`
> ทำให้ EA 2 ตัวบน VPS เดียวกันได้ seed ใกล้กัน — **ผมดูโค้ดไม่ครบ** seed จริงคือ
>
> ```mql5
> GetMicrosecondCount() ^ GetTickCount64() ^ ChartID() ^ AccountInfoInteger(ACCOUNT_LOGIN)
> ```
>
> `ChartID()` ต่างต่อ chart · `ACCOUNT_LOGIN` ต่างต่อบัญชี → **คุณสมบัติที่ผมต้องการมีอยู่แล้ว**
> · seed ไม่ใช่ "การตัดสินใจที่ใช้เวลา" ตามนิยามข้างบนด้วยซ้ำ จึงไม่เคยอยู่ใต้กฎนี้ตั้งแต่แรก
>
> **`CBrokerTime::LocalTime()` (§3.2) ยังคงไว้** แต่เปลี่ยนผู้ใช้เป็น `DiagnosticLine()`
> (§4.2 ต้องมีเวลา local ให้คนเทียบเพื่อจับนาฬิกา VPS ผิด — edge 2) ·
> ตอนนี้ accessor นั้น**ยังไม่มีใครเรียกเลย** ซึ่งต้องแก้

### 6.3 ★★ ห้ามมี fallback timestamp — บังคับตาม §4.7 (ใหม่ใน rev.2)

- [ ] `grep -rnE "\b1[5-9][0-9]{8}\b" mt5-ea/ tests/mql5/` **ไม่เจออะไรเลย**
      (ดักตัวเลข epoch คงที่ช่วงปี 2017–2033 เช่น `1700000000` ที่พบใน `Wire.mqh:219`)
- [ ] `grep -rn "if(utc" mt5-ea/Include/Farm/Wire.mqh` — **ไม่มีบรรทัดไหนที่กำหนดค่าเวลาให้ตัวแปร
      เมื่อค่าเดิม `<= 0`** ทุกรูปแบบ (`TimeGMT()`, `m_last_known_utc`, ค่าคงที่)
- [ ] เมื่อ `IsValid()==false`: `SendHello` / `SendHeartbeat` / `SendErrorReport` **คืน false และไม่เขียนอะไรลง socket**
      · `m_dropped_no_time` เพิ่มขึ้น
- [ ] log WARN แบบ throttle — **เลือกได้ 2 แบบ** (rev.2a ผ่อนจาก rev.2 ที่บังคับแบบเดียว):
      **(ก)** ครั้งแรกของช่วงเท่านั้น · **(ข)** ครั้งแรกแล้วทุก N ครั้งหลังจากนั้น
      · ห้าม log ทุกครั้งที่ drop (ทุก 1 วินาที = log ท่วม)
- [ ] ★★ **counter ต้องรีเซ็ตเมื่อกลับมาส่งได้** (rev.2b — ยกเป็น acceptance ที่ตรวจได้)
      **ทดสอบแบบนี้:** ทำให้ส่งไม่ได้ 15 ครั้ง → กลับมาส่งได้ 1 ครั้ง → ทำให้ส่งไม่ได้อีก
      **ต้องมี WARN ออกมาที่ drop แรกของช่วงที่สอง** · ถ้า counter ไม่ reset จะนับต่อเป็น 16
      แล้ว `% 10` ไม่ตรงเงื่อนไข → **ช่วงพังรอบสองเงียบสนิท**
      · ค่าสะสมทั้ง session เก็บแยกเป็นตัวที่สอง (`m_dropped_no_time_total`) สำหรับรายงานขึ้นสาย
- [ ] `m_broker_time == NULL` → log **FATAL** (bug ของ caller) แยกจากเคส `IsValid()==false`

### 6.4 ค่าบนสาย

- [ ] `ts_server` ที่ `Wire.mqh` ส่งออก = `FarmFormatIsoUtc(BrokerToUtc(NowBroker()))`
      และผ่าน pattern `common.json#/$defs/ts_utc`
- [ ] `ts_sent` = `FarmFormatIsoUtc(NowUtc())` · **`ts_sent ≥ ts_server` เสมอ**
      (rev.1 กลับกันเพราะ bug — latency ที่คำนวณได้เป็นลบ)
- [ ] `HELLO.broker_time` ส่งค่าจริงครบ 5 field เมื่อ `IsValid()` ·
      **ไม่ใส่ key เลย** เมื่อ `!IsValid()` (§4.8 · ส่ง `null` = HELLO ถูก reject ทั้งใบ)
- [ ] `HELLO.broker_time.detected_at` = เวลาที่**ยอมรับ offset นั้นจริง** ไม่ใช่ `NowUtc()` ตอนสร้าง payload
- [ ] `HEARTBEAT.wire.broker_utc_offset_sec` = ค่าจริงเมื่อ `IsValid()` · **`null`** เมื่อไม่ ·
      **ห้ามส่ง `0`** (0 เป็น offset ที่ถูกต้องได้จริงสำหรับโบรกเกอร์ที่ตั้งเวลาเป็น UTC)
- [ ] `ERROR` ตอน offset เปลี่ยน ใช้ code **`BROKER_TIME_OFFSET_CHANGED`** เป๊ะ (§4.4)
      พร้อม `context: {"old_offset_sec": …, "new_offset_sec": …}` — **ห้ามยัดลง `message` แล้วปล่อย `context` ว่าง**

### 6.5 บนเทอร์มินัลจริง

- [ ] รัน EA บน demo ตอนตลาดปิด (เสาร์/อาทิตย์) — `NowBroker()` ยังเดินหน้า
      และ heartbeat ไม่ขาด (พิสูจน์ว่าไม่ได้ใช้ `TimeCurrent()`)
- [ ] รายงานตัวเลข drift ของ `TimeTradeServer()` ตลอดสุดสัปดาห์ใน handoff (Q2 §9)

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
| 14 | `test_broker_day_start_across_dst_23h_and_25h` | **ดู §7.1 — เขียนใหม่ทั้งข้อใน rev.2** | **R6** |
| 15 | `test_is_same_broker_day_across_utc_midnight` | UTC ข้ามวันแต่ broker ยังวันเดิม | **R6** |
| **16** | `test_invalid_after_90s_of_bad_samples` | **ใหม่ rev.2** — ดู §7.2 | §4.3 · SafeMode |
| **17** | `test_init_retries_until_deadline` | **ใหม่ rev.2** — ดู §7.3 | §4.2 |

**test 14 · 15 · 16 สำคัญที่สุด** — 14/15 คือจุดที่ R6 จะ HALT ผิดวันถ้าทำผิด ·
16 คือ trigger เดียวที่ SPEC-023 (SafeMode) จะพึ่งได้เมื่อ broker หยุดตอบเวลา

---

### 7.1 test 14 — สิ่งที่ต้องพิสูจน์เป๊ะๆ (เขียนใหม่ใน rev.2 · finding B6)

> **ที่ rev.1 เขียนผิด:** ผมเขียนแค่ *"วัน DST ยาว 23 และ 25 ชม."* ซึ่งสั้นเกินจะ implement ถูก
> ผลคือได้ test ที่ `offset` **คงที่ 7200 ตลอด** แล้วเรียก `BrokerDayStart()` สองครั้ง
> ด้วยวันที่ต่างกัน — เหมือน `test_broker_day_start_normal` ทุกประการ
> **ลบ `BrokerDayStart` ทิ้งแล้วเขียน `t - (t % 86400)` ตรงๆ ก็ยังผ่าน**
>
> test ที่ผ่านโดยไม่พิสูจน์อะไร **อันตรายกว่า test แดง** ([CLAUDE.md](../../CLAUDE.md))
> เพราะทำให้ gate เขียวทั้งที่กฎ R6 ยังไม่ถูกคุ้มครอง

**หัวใจ:** สิ่งที่ต้องวัดคือ **ระยะห่างใน UTC ระหว่างเส้นแบ่งวัน broker สองวันติดกัน**
ไม่ใช่ค่า `BrokerDayStart()` ทีละตัว — 23/25 ชม. เกิดขึ้นได้ก็ต่อเมื่อ **offset เปลี่ยนระหว่างสองวันนั้น**
ดังนั้น test **ต้องมี offset change อยู่ในนั้น** ไม่งั้นไม่มีทางเป็นอย่างอื่นนอกจาก 24 ชม.

โครงบังคับ — ทั้งสองครึ่งต้องมี:

```mql5
// ---------- ครึ่ง spring forward: +02:00 → +03:00 → ต้องได้ 23 ชม. ----------
InitClock(clock, src, 7200);
const datetime d1_broker = clock.BrokerDayStart(MakeTime(2026,3,29,12,0,0));
const datetime d1_utc    = clock.BrokerToUtc(d1_broker);

ShiftOffsetTo(clock, src, 10800);        // ★ ต้องเดินครบ debounce 3 sample × 20s ตาม §4.3
                                          //   ห้าม set m_offset_sec ตรงๆ — จะข้ามตรรกะที่กำลังทดสอบ
AssertEqualInt(clock.OffsetSeconds(), 10800, "offset_shifted");   // กันไม่ให้ครึ่งบนเงียบๆ ไม่มีผล

const datetime d2_broker = clock.BrokerDayStart(MakeTime(2026,3,30,12,0,0));
const datetime d2_utc    = clock.BrokerToUtc(d2_broker);
AssertEqualInt((int)(d2_utc - d1_utc), 23*3600, "spring_day_is_23h");   // ★ ข้อพิสูจน์จริง

// ---------- ครึ่ง autumn back: +03:00 → +02:00 → ต้องได้ 25 ชม. ----------
//   ทำซ้ำแบบเดียวกันด้วย clock ตัวใหม่ · assert 25*3600
```

| ข้อบังคับ | เหตุผล |
|-----------|--------|
| `ShiftOffsetTo` ต้องเดินผ่าน `Refresh()` ครบ debounce จริง | ถ้า set ค่าตรงๆ จะข้าม §4.3 ทั้งหมด — test จะไม่จับ regression ของ B4/B5 |
| ต้อง `Assert` ว่า `OffsetSeconds()` เปลี่ยนแล้ว **ก่อน** วัด 23 ชม. | ถ้า debounce พังเงียบๆ ผลจะเป็น 24 ชม. แล้ว assert ถัดไปจะ fail โดยไม่บอกสาเหตุ |
| ต้องมี**ทั้ง** 23 และ 25 | ทิศทางเดียวจับ bug ที่กลับเครื่องหมายไม่ได้ |
| ห้ามใช้ `BrokerDayStart` ผลลัพธ์เปล่าๆ เป็น assertion เดียว | นั่นคือสิ่งที่ทำให้ rev.1 พลาด |

### 7.2 test 16 — `test_invalid_after_90s_of_bad_samples` (ใหม่ · finding B5 + B7)

> **ที่ rev.1 ขาด:** §4.3 แถวสุดท้ายบังคับว่า *"sample ไม่ใช้ได้ติดกัน > 90 วินาที → `IsValid()=false`"*
> แต่ §7 ไม่มี test ตัวไหนแตะเลย — **behaviour ที่ไม่มี test คือ behaviour ที่จะไม่ถูกทำ**
> และจริงตามนั้น: `Refresh()` ที่ส่งมาไม่เคยตั้ง `m_valid = false` หลัง `Init()` สำเร็จเลย
> แปลว่า broker หยุดตอบเวลา = EA ใช้ offset เก่าไป **ตลอดกาล** ไม่มีทางเข้า SafeMode

| ขั้น | ทำ | ต้องได้ |
|------|-----|---------|
| 1 | `Init()` สำเร็จด้วย offset 10800 | `IsValid()==true` · `BrokerToUtc(t) == t - 10800` |
| 2 | ป้อน sample ที่ **ไม่ผ่านเกณฑ์ §4.1** (เช่น `raw = 10500`) ติดกัน เดินนาฬิกาไปรวม **80 วินาที** | ยัง `IsValid()==true` — **ยังไม่ถึง 90s ห้าม invalidate เร็วเกิน** |
| 3 | เดินต่อจนรวม **> 90 วินาที** | `IsValid()==false` · log FATAL |
| 4 | เรียก `BrokerToUtc(t)` · `UtcToBroker(t)` · `NowUtc()` · `BrokerDayStart(t)` | **คืน `0` ทุกตัว** — ห้ามคืนค่าที่คำนวณจาก offset 10800 เดิม |
| 5 | ป้อน sample ที่ใช้ได้อีกครั้ง | กลับมา `IsValid()==true` (ต้องเดินครบ debounce §4.3 ตามปกติ) |

**ขั้น 4 คือหัวใจ** — นี่คือเคสที่ test 9 (`test_invalid_returns_zero_not_stale`) *ตั้งใจ*จะจับ
แต่ rev.1 implement เป็น `CBrokerTime` ที่ไม่เคย `Init()` เลย ซึ่งเป็นคนละเคสกัน (finding B7):

| | `IsValid()==false` เพราะ | อันตรายไหม |
|---|---|---|
| test 9 ที่ส่งมา | ไม่เคย `Init()` → ไม่เคยมี offset | ไม่ — ไม่มี offset เก่าให้รั่ว |
| **สิ่งที่ต้องจับ** | **เคยมี offset แล้วเสียไป** | ★ ใช่ — นี่คือเคสเดียวที่ค่า stale รั่วออกไปได้ |

→ **test 9 ให้คงไว้** (เคส "เกิดมาก็ invalid แล้ว" ก็ยังต้องคืน 0) แต่ **test 16 คือตัวที่จับ stale จริง**

### 7.3 test 17 — `test_init_retries_until_deadline` (ใหม่ · finding B8)

พิสูจน์ว่า retry loop ของ §4.2 ทำงาน และ **test เดิน path เดียวกับ production**

| ขั้น | ทำ | ต้องได้ |
|------|-----|---------|
| 1 | fake source คืน `ServerTime()==0` ตลอด | `Init()` คืน **false** · นับจำนวนครั้งที่ `SleepMs` ถูกเรียก ≥ 10 (3000ms / 200ms − ขอบ) · เวลารวมที่ fake clock เดินไป ≈ 3000ms **ไม่เกิน** |
| 2 | fake source คืน sample เสียใน 4 รอบแรก แล้วคืน `raw=10800` รอบที่ 5 | `Init()` คืน **true** · `OffsetSeconds()==10800` · `SleepMs` ถูกเรียก **4 ครั้ง** (ไม่ใช่ 15 — ต้องออกจาก loop ทันทีที่ได้ค่า) |
| 3 | fake source คืน sample ดีตั้งแต่รอบแรก | `SleepMs` ถูกเรียก **0 ครั้ง** |

**ข้อบังคับ:** fake source ต้องนับ `SleepMs` เอง และ **เลื่อนทั้ง `ServerTime()` และ `GmtTime()`**
เท่ากับ `ms` ที่รับมา (§4.2) — ถ้าเลื่อนข้างเดียว offset จะขยับเองแล้ว test จะพิสูจน์คนละเรื่อง

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
