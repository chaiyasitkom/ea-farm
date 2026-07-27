# SPEC-012 — Intent dedupe cache + expiry

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-011, SPEC-063 · **Blocks:** SPEC-027
**อ้าง:** [02-contracts §4.5](../02-contracts.md) · [`intent_ack.json`](../../contracts/schema/intent_ack.json)

---

## 1. Goal

ตอบ `INTENT` ที่ซ้ำหรือหมดอายุให้ถูกต้องและ**สม่ำเสมอ** — คำตอบเดิมสำหรับคำถามเดิม
โดยไม่ต้องทำงานซ้ำ

## 2. Non-goals

- ❌ **ห้าม persist cache ลงดิสก์** — [SPEC-017 §4.5](SPEC-017-reconciliation.md) พิสูจน์แล้วว่า
      ไม่ได้ให้ความปลอดภัยเพิ่ม (target-state ทำให้ทำซ้ำแล้วปลอดภัยอยู่แล้ว) ★
- ❌ ห้าม implement reconciler (SPEC-011)
- ❌ ห้าม implement risk guard (SPEC-019)
- ❌ ห้ามจัดการ `expires_at` ของ `RISK_DIRECTIVE` — คนละความหมาย ดู §4.6 (SPEC-027)
- ❌ ห้ามแตะ `contracts/schema/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `mt5-ea/Include/Farm/IntentCache.mqh` | **สร้าง** |
| `mt5-ea/Include/Farm/OrderRouter.mqh` | **แก้** — เรียก cache ก่อน reconcile |
| `tests/mql5/TestIntentCache.mq5` | EA test |

### 3.2 API

```mql5
enum ENUM_FARM_INTENT_GATE
{
   FARM_GATE_PROCEED,      // ผ่าน -> ให้ reconciler ทำต่อ
   FARM_GATE_DUPLICATE,    // เคยตอบไปแล้ว
   FARM_GATE_EXPIRED,      // valid_until เลยแล้ว
   FARM_GATE_NO_CLOCK      // ★ CBrokerTime ใช้ไม่ได้ -> ตัดสินไม่ได้ (§4.4)
};

class CIntentCache
{
public:
   bool Init(CBrokerTime *clock, const int capacity = 4096,
             const int ttl_sec = 3600);

   // เรียกทันทีที่ได้ INTENT ก่อนทำอะไรทั้งสิ้น
   ENUM_FARM_INTENT_GATE Check(const string intent_id,
                               const string valid_until_iso,
                               string &out_reason);

   // เรียก "หลัง" ตัดสินผลแล้วเสมอ ไม่ว่าผลจะเป็นอะไร (§4.3)
   void Record(const string intent_id, const string final_status);

   // metric
   int  Size() const;
   long DuplicateCount() const;
   long ExpiredCount() const;
   long EvictedCount() const;

#ifdef FARM_TEST
   void TestSetNow(const datetime utc);
#endif
};
```

---

## 4. Behaviour

### 4.1 ★ ลำดับการเช็ค — เปลี่ยนคำตอบที่ brain เห็น

```
INTENT เข้ามา
  1. dedupe        → DUPLICATE
  2. expiry        → EXPIRED
  3. risk guard    → REJECTED_BY_GUARD      (SPEC-019)
  4. reconcile     → ACCEPTED / NOOP / …    (SPEC-011)
```

**dedupe ต้องมาก่อน expiry** — ถ้า intent ที่เคยตอบไปแล้วถูกส่งซ้ำหลังหมดอายุ
คำตอบต้องเป็น `DUPLICATE` ไม่ใช่ `EXPIRED`

**เหตุผล:** เราเคยตัดสินเรื่องนี้ไปแล้วครั้งหนึ่ง คำตอบเดิมยังเป็นความจริง
· ถ้าตอบ `EXPIRED` brain จะเข้าใจว่าคำสั่งไม่เคยถูกทำ ทั้งที่มันถูกทำไปแล้ว
→ **brain อาจส่งใหม่แล้วเปิดซ้ำ**

### 4.2 cache เก็บ "คำตอบ" ไม่ใช่แค่ id

```
(intent_id, final_status, recorded_at_utc)
```

ตอบ `DUPLICATE` พร้อม `reason = "original_status=ACCEPTED"` ลงใน
[`intent_ack.json`](../../contracts/schema/intent_ack.json) field `reason`

**ทำไมต้องเก็บสถานะเดิม:** เวลา debug ว่า "ทำไม order ไม่เกิด" ต้องแยกให้ออกว่า
รอบแรกตอบ `ACCEPTED` (ทำไปแล้ว) หรือ `REJECTED_BY_GUARD` (ไม่เคยทำ)
— ถ้าตอบ `DUPLICATE` เปล่าๆ ข้อมูลนั้นหายไป

### 4.3 ★ `Record()` เรียก **หลัง** ตัดสินผล และเรียก**ทุกครั้ง**

| ผล | บันทึกไหม |
|----|-----------|
| `ACCEPTED` · `NOOP` | ✅ |
| `EXPIRED` · `REJECTED_BY_GUARD` · `REJECTED_INVALID` · `ANOMALY_INTERNAL_HEDGE` | ✅ |
| `DUPLICATE` | ❌ (อยู่ใน cache อยู่แล้ว) |

**ทำไมบันทึกแม้ตอนถูกปฏิเสธ:** brain ที่ไม่ได้ ack จะส่งซ้ำ · ถ้าไม่บันทึกไว้
เราจะรัน guard ซ้ำทุกครั้ง และถ้า guard ตัดสินต่างออกไปในรอบสอง
(เพราะ spread เปลี่ยน) จะได้คำตอบไม่คงที่สำหรับ intent เดียวกัน

MQL5 `OnTimer` เป็น single-thread → ไม่มี race ระหว่าง `Check()` กับ `Record()`

### 4.4 ★ Expiry เทียบกับ `CBrokerTime.NowUtc()` เท่านั้น

`valid_until` เป็น UTC ตาม [`intent.json`](../../contracts/schema/intent.json)

| กฎ | |
|----|---|
| เทียบกับ `CBrokerTime.NowUtc()` | **ห้ามใช้ `TimeCurrent()`** (เป็นเวลา broker) และ **ห้ามใช้ `TimeGMT()`** (พึ่งนาฬิกาเครื่อง) |
| `CBrokerTime.IsValid() == false` | → `FARM_GATE_NO_CLOCK` → ตอบ `REJECTED_INVALID` reason `BROKER_TIME_UNAVAILABLE` |

**ตัดสินไม่ได้ = ปฏิเสธ ไม่ใช่ปล่อยผ่าน** — เทรดโดยไม่รู้ว่าคำสั่งหมดอายุหรือยัง
คือการเทรดด้วยข้อมูลที่อาจเก่าหลายนาที

### 4.5 intent ที่มาถึงตอนหมดอายุแล้ว — ตอบ EXPIRED และ**นับ**

เกิดได้จาก: latency สูง · brain ตั้ง `valid_until` สั้นไป · **นาฬิกาสองฝั่งเพี้ยน**

| อัตรา | ตีความ |
|-------|--------|
| นานๆ ครั้ง | ปกติ |
| **สูงผิดปกติ** | 🔴 latency มีปัญหา หรือ clock skew — เป็นสัญญาณ ไม่ใช่ noise |

`ExpiredCount()` ต้องขึ้น `HEARTBEAT` หรือ log ให้ dashboard เห็น
— เกี่ยวโดยตรงกับ invariant `ts_sent >= ts_server` ที่ [SPEC-013 §4.6](SPEC-013-gateway.md) ตรวจ

### 4.6 `RISK_DIRECTIVE` — dedupe ใช้ cache เดียวกัน แต่ **expiry คนละเรื่อง**

`directive_id` เป็น ULID เหมือนกัน → ใช้ cache เดียวกันกัน directive ซ้ำได้

**แต่ `expires_at` มีความหมายต่างจาก `valid_until` โดยสิ้นเชิง:**

| field | หมดอายุแล้วหมายความว่า |
|-------|------------------------|
| `INTENT.valid_until` | **ทิ้งคำสั่ง** — ราคาเปลี่ยนไปแล้ว การตัดสินใจเดิมอาจไม่ valid |
| `RISK_DIRECTIVE.expires_at` | **กลับไปใช้ local guard เพียงลำพัง** — ไม่ใช่กลับเป็น NORMAL |

→ ticket นี้ **ห้ามใช้ตรรกะ expiry เดียวกันกับ directive** · เป็นงานของ SPEC-027
· ที่นี่ทำแค่ dedupe

### 4.7 Eviction

| | |
|---|---|
| ความจุ | 4096 (ค่าเริ่มต้น) — contract ขอ ≥ 1000 |
| TTL | 3600 วินาที |
| นโยบาย | ลบตัวที่เกิน TTL ก่อน · ถ้ายังเต็มลบตัวเก่าสุด (FIFO) · `EvictedCount++` |

4096 รายการครอบ traffic หลายชั่วโมงที่อัตราจริงของเรา
· `EvictedCount` ที่ไต่ขึ้นเร็ว = brain ส่ง intent ถี่ผิดปกติ → เป็นสัญญาณ

**โครงสร้างข้อมูล:** ring buffer + linear scan ก็พอ (4096 × เทียบ string ต่อ intent
ที่อัตราไม่กี่ครั้งต่อนาที = ไม่มีนัยยะ) · **ห้าม over-engineer เป็น hash table**
เว้นแต่วัดแล้วเห็นว่าช้าจริง

---

## 5. Edge cases

1. **`intent_id` ว่างหรือไม่ใช่ ULID** → `REJECTED_INVALID` **ไม่บันทึกลง cache**
   (ไม่งั้น id พังๆ จะกิน cache)
2. **`valid_until` ไม่ใช่รูปแบบ UTC ที่ถูก** → `REJECTED_INVALID` reason ระบุ field
3. **`valid_until` อยู่ในอดีตไกลมาก** (เช่นปี 2020) → `EXPIRED` ตามปกติ ไม่ต้องมีเคสพิเศษ
4. **`valid_until` อยู่ในอนาคตไกลมาก** (เช่น 1 ปี) → ผ่าน · เป็นเรื่องของ brain
   แต่ **log WARN** เพราะน่าจะเป็น bug ฝั่ง brain
5. **cache ว่างตอนเพิ่งสตาร์ต** → ทุก intent เป็นของใหม่ · ถูกต้องแล้ว (§2 ข้อแรก)
6. **`Record()` ถูกเรียกซ้ำด้วย id เดิม** → อัปเดตสถานะ ไม่ใช่เพิ่มรายการใหม่
7. **DST เปลี่ยนระหว่างที่ intent ค้างอยู่** → `NowUtc()` ยังถูกเพราะ `CBrokerTime`
   จัดการ offset ให้แล้ว (SPEC-063) · ไม่ต้องทำอะไรพิเศษ
8. **capacity = 0 หรือติดลบ** → `Init()` คืน false → `OnInit` fail

---

## 6. Acceptance criteria

- [ ] intent เดิมส่งซ้ำ → `DUPLICATE` และ **ไม่มี order ถูกส่ง** ★
- [ ] `reason` ของ `DUPLICATE` มี `original_status=…` ★
- [ ] intent ที่ `valid_until` ผ่านแล้ว → `EXPIRED` และ **ไม่มี order**
- [ ] **intent ที่เคยตอบแล้ว + หมดอายุแล้ว → `DUPLICATE` ไม่ใช่ `EXPIRED`** ★★ §4.1
- [ ] intent ที่ถูก `REJECTED_BY_GUARD` แล้วส่งซ้ำ → `DUPLICATE`
      พร้อม `original_status=REJECTED_BY_GUARD` ★ §4.3
- [ ] `CBrokerTime.IsValid() == false` → `REJECTED_INVALID`
      reason `BROKER_TIME_UNAVAILABLE` **ไม่ใช่ปล่อยผ่าน** ★★ §4.4
- [ ] `grep -n "TimeCurrent()\|TimeGMT()\|TimeLocal()" mt5-ea/Include/Farm/IntentCache.mqh`
      — **ไม่เจอ** (เวลาต้องมาจาก `CBrokerTime` เท่านั้น) ★
- [ ] `grep -rn "FileWrite\|GlobalVariableSet" mt5-ea/Include/Farm/IntentCache.mqh`
      — **ไม่เจอ** (ห้าม persist) ★
- [ ] เก็บได้ ≥ 1000 รายการตาม contract · ทดสอบที่ 4096
- [ ] เกิน capacity → evict ตัวเก่าสุด · `EvictedCount` ถูกต้อง
- [ ] เกิน TTL → evict แม้ยังไม่เต็ม
- [ ] `ExpiredCount` / `DuplicateCount` / `EvictedCount` อ่านได้และขึ้น `HEARTBEAT`
- [ ] compile 0 error 0 warning · `run-mql5-tests.ps1` เขียว

## 7. Test list — `tests/mql5/TestIntentCache.mq5`

**ใช้ `TestSetNow()` ป้อนเวลาแทนการรอจริง** — test ต้องไม่ใช้ `Sleep()`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_new_intent_proceeds` | |
| 2 | `test_repeat_intent_returns_duplicate` | |
| 3 | `test_duplicate_reason_carries_original_status` | ★ §4.2 |
| 4 | `test_expired_intent_returns_expired` | |
| 5 | `test_duplicate_beats_expiry` | ★★ §4.1 — จุดที่ผิดแล้วเปิดซ้ำ |
| 6 | `test_rejected_intent_is_recorded_and_dedupes` | ★ §4.3 |
| 7 | `test_no_clock_returns_no_clock_not_proceed` | ★★ §4.4 fail-closed |
| 8 | `test_invalid_ulid_not_cached` | edge 1 |
| 9 | `test_malformed_valid_until_rejected` | edge 2 |
| 10 | `test_far_future_valid_until_warns_but_passes` | edge 4 |
| 11 | `test_evicts_oldest_when_full` | |
| 12 | `test_evicts_by_ttl_before_capacity` | |
| 13 | `test_record_same_id_updates_not_appends` | edge 6 |
| 14 | `test_capacity_at_least_1000` | contract |
| 15 | `test_counters_are_accurate` | |

**test 5 กับ 7 คือสองตัวที่เงินหายถ้าผิด** — 5 ทำให้ brain เปิดซ้ำ ·
7 ทำให้เทรดด้วยคำสั่งที่อาจหมดอายุไปแล้ว

## 8. Files

**Touch:** `mt5-ea/Include/Farm/IntentCache.mqh` · `mt5-ea/Include/Farm/OrderRouter.mqh`
· `tests/mql5/TestIntentCache.mq5` · `tools/run-mql5-tests.ps1` (ลง `gate changes`)

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/{Wire,BrokerTime,Reconciler}.mqh`
· `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | capacity 4096 / TTL 1 ชม. เหมาะไหม | **ไม่บล็อก** — เริ่มที่ค่านี้ · **รายงาน `EvictedCount` ตอน soak** ถ้า evict บ่อยแปลว่าเล็กไป อย่าปรับเอง |
| Q2 | linear scan ช้าไปไหม | **ไม่บล็อก — ตอบแล้ว: ไม่** ที่อัตราไม่กี่ intent ต่อนาที · ถ้า `Pump()` p99 เกิน 20 ms เพราะตัวนี้ **ให้รายงานตัวเลข** ค่อยเปลี่ยนโครงสร้าง |
| Q3 | ควรใส่ `RISK_DIRECTIVE` ลง cache เดียวกันเลยไหม | **ไม่บล็อก — ตอบแล้ว: ใส่ได้** สำหรับ dedupe · แต่ **ห้ามเอาตรรกะ expiry ไปใช้กับมัน** (§4.6) |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ 011 + 063 merge**

---

## ภาคผนวก — ทำไม cache นี้ไม่ใช่เรื่องความปลอดภัย แต่เป็นเรื่องความสม่ำเสมอ

[SPEC-017 §4.5](SPEC-017-reconciliation.md) พิสูจน์แล้วว่าการทำ intent ซ้ำ**ไม่อันตราย**
เพราะ target-state ทำให้รอบสองเป็น NOOP

แล้วทำไมยังต้องมี cache?

เพราะ **brain ต้องได้คำตอบที่คงที่**: ถ้าส่ง intent เดียวกันสองครั้งแล้วได้
`ACCEPTED` แล้ว `NOOP` brain จะตีความว่ามีสองเหตุการณ์ที่ต่างกัน
ทั้งที่มันคือคำสั่งเดียว — และ audit trail ใน `intents` จะมีสองแถวที่เล่าเรื่องคนละแบบ

cache ทำให้คำถามเดิมได้คำตอบเดิมเสมอ ซึ่งเป็นสิ่งที่ทำให้ log อ่านแล้วเข้าใจตรงกัน
· มันคือเครื่องมือของ **ความชัดเจน** ไม่ใช่ของ **ความปลอดภัย**
และการเข้าใจข้อนี้คือเหตุผลที่ §2 ห้าม persist ลงดิสก์
