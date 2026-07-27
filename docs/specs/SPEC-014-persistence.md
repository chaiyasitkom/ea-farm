# SPEC-014 — Persistence: intents · exec_reports · account_state · bars

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-006, SPEC-013 · **Blocks:** SPEC-018, SPEC-028, SPEC-029
**อ้าง:** [02-contracts §5](../02-contracts.md) · [SPEC-006 §5.1](SPEC-006-database.md)

---

## 1. Goal

ต่อ handler ของ gateway เข้ากับ repository ให้ทุกอย่างที่วิ่งผ่านสายถูกบันทึก
โดย**ไม่ทำให้ gateway ช้าลง** และ**ไม่มีทางที่ order จะเกิดโดยไม่มีหลักฐาน**

## 2. Non-goals

- ❌ ห้ามแก้ schema ของ DB (SPEC-006) — ถ้าคิดว่าต้องเพิ่มคอลัมน์ → implementation note
- ❌ ห้ามแก้ `brain/gateway/server.py` (SPEC-013) — ต่อผ่าน `Handlers` protocol เท่านั้น
- ❌ ห้ามตัดสินใจเทรด / risk (SPEC-025)
- ❌ ห้าม alert (SPEC-029) — ให้แค่ตัวนับกับ query ที่ alert จะใช้
- ❌ ห้ามทำ dashboard (SPEC-028)

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `brain/store/persist.py` | `PersistingHandlers` — implement `Handlers` ของ SPEC-013 |
| `brain/store/writer.py` | คิว + task เขียน telemetry แบบ batch |
| `brain/store/dispatch.py` | ★ `IntentDispatcher` — เขียนก่อนส่ง (§4.1) |
| `brain/store/metrics.py` | ตัวนับให้ dashboard/alert |
| `tests/test_persist.py` | marker `db` |

### 3.2 `IntentDispatcher` — ตัวที่บังคับลำดับ

```python
class IntentDispatcher:
    def __init__(self, pool, gateway: FarmGateway) -> None: ...

    async def dispatch(self, session_id: str, intent: IntentPayload) -> None:
        """เขียน intents ลง DB ให้ commit สำเร็จ *ก่อน* ส่งออกสาย
        DB ล้มเหลว -> raise · **ห้ามส่ง INTENT** (§4.2)"""
```

**brain (SPEC-025) ต้องเรียกผ่านตัวนี้เท่านั้น ห้ามเรียก `gateway.send_intent()` ตรงๆ**
· `send_intent` ที่เปิดไว้ใน SPEC-013 คือ primitive ของชั้นล่าง ไม่ใช่ API ที่ใช้จริง

---

## 4. Behaviour

### 4.1 ★★ ต้องเขียน `intents` ให้สำเร็จ **ก่อน** ส่ง INTENT ออกสาย

**เหตุผล 2 ข้อ:**

| # | |
|---|---|
| 1 | `exec_reports.intent_id` มี **FK ไปที่ `intents`** — EA อาจตอบ `EXEC_REPORT` กลับมาเร็วกว่าที่เราเขียน intent เสร็จ → FK พัง ([SPEC-006 edge 6](SPEC-006-database.md)) |
| 2 | ★ **ไม่มีหลักฐาน = ห้ามเทรด** — ถ้าส่งก่อนเขียน แล้วโปรเซสตายระหว่างนั้น จะมี order เกิดขึ้นจริงโดยไม่มีบันทึกว่าใครสั่ง ตอนไหน ด้วยเหตุผลอะไร |

ลำดับที่บังคับ:
```
เขียน intents (commit สำเร็จ)  →  gateway.send_intent()  →  รอ INTENT_ACK
         │
         └─ ล้มเหลว → raise → **ไม่ส่งอะไรออกสายเลย**
```

**ยอมให้ intent ตกหล่นเพราะ DB ล่ม ดีกว่ายอมให้ order ไม่มีหลักฐาน**

### 4.2 ★★ DB ล่ม = ไม่เทรด (fail-closed) — แต่ telemetry ยังไปต่อ

| ข้อมูล | DB ล่มแล้วทำอะไร |
|--------|-------------------|
| `intents` | 🔴 **หยุด** — `dispatch()` raise · brain ต้องไม่ส่ง intent · นับ + alert |
| `exec_reports` | 🟠 buffer ไว้ · **ห้ามทิ้ง** (เป็น audit) — buffer เต็ม = ปัญหาร้ายแรง ดู §4.4 |
| `account_state` · `bars` | 🟡 buffer · เต็มแล้ว **drop ตัวเก่าสุด** + นับ (เป็น telemetry) |

**นี่คือการเลือกที่ตั้งใจ:** ระบบที่เทรดต่อไปทั้งที่บันทึกไม่ได้ = ระบบที่วันหนึ่ง
จะตอบไม่ได้ว่าเกิดอะไรขึ้น · และวันนั้นคือวันที่พอร์ตเสียหาย ไม่ใช่วันปกติ

### 4.3 ★ สองเส้นทางเขียน — durable กับ buffered

| เส้นทาง | ใช้กับ | วิธี |
|---------|--------|------|
| **durable (synchronous)** | `intents` · `intent_ack` | เขียนแล้วรอ commit ก่อนไปต่อ |
| **buffered (async batch)** | `exec_reports` · `account_state` · `bars` | เข้าคิว → task เบื้องหลังเขียนเป็นชุด |

**ทำไมไม่ทำ durable ทั้งหมด:** [SPEC-013 edge 9](SPEC-013-gateway.md) บังคับว่า handler
**ห้ามบล็อกการอ่าน socket** — ถ้า `on_bar` รอ DB commit ทุกแท่ง ตอน backfill 300 แท่ง
(SPEC-010) gateway จะค้างจน EA heartbeat timeout

**ทำไมไม่ buffer ทั้งหมด:** §4.1 ข้อ 2

### 4.4 นโยบายคิว

| | `exec_reports` | `account_state` · `bars` |
|---|----------------|--------------------------|
| ขนาดคิว | 10,000 | 10,000 |
| เต็มแล้ว | 🔴 **หยุดรับ + alert FATAL** — ห้าม drop audit | 🟡 drop ตัวเก่าสุด + นับ |
| flush เมื่อ | 100 แถว **หรือ** 1 วินาที (แล้วแต่อะไรถึงก่อน) | เหมือนกัน |
| ปิดโปรแกรม | **flush ให้หมดก่อนออก** (มี timeout) | flush best-effort |

`exec_reports` คิวเต็ม = DB ล่มนานพอที่จะกลืน 10,000 รายการ
→ ที่จุดนั้นระบบไม่ควรเทรดต่อแล้ว **ต้อง alert ระดับ FATAL** ไม่ใช่เงียบๆ ทิ้ง

### 4.5 `bars` — backfill มาเป็นชุดและซ้ำได้

EA ส่ง backfill 300 แท่งตอนต่อ ([SPEC-010 §4.1](SPEC-010-state-reporter.md))
และจะส่งใหม่ทั้งชุดทุกครั้งที่ reconnect

| กฎ | |
|----|---|
| ใช้ `ON CONFLICT DO NOTHING` | ซ้ำเป็นเรื่องปกติ ไม่ใช่ error ([SPEC-006 edge 3](SPEC-006-database.md)) |
| **นับจำนวนที่ชน** | ชนเยอะผิดปกติ = EA reconnect ถี่ผิดปกติ → เป็นสัญญาณ ไม่ใช่ noise |
| `symbol` เก็บ **raw** คู่กับ `broker` | [SPEC-006 §4.4](SPEC-006-database.md) |
| ใช้ `COPY` เมื่อ batch ≥ 50 แถว | backfill จะเข้าเส้นทางนี้ |

### 4.6 `intent_ack` — เติมได้ครั้งเดียว

trigger ฝั่ง DB บังคับไว้แล้ว ([SPEC-006 §5.1](SPEC-006-database.md))
· ฝั่ง Python ต้องแปลง exception ให้มีความหมาย:

| สาเหตุ | ทำอะไร |
|--------|--------|
| EA ส่ง `INTENT_ACK` ซ้ำ (retry) | log WARN + นับ · **ไม่ raise ขึ้นไป** |
| `intent_id` ไม่มีใน `intents` | 🔴 **ERROR + alert** — แปลว่า EA ตอบ intent ที่เราไม่เคยส่ง หรือ §4.1 พัง |

ข้อสองสำคัญกว่าที่ดู — เป็นสัญญาณว่า **ลำดับใน §4.1 ถูกข้าม** หรือมี intent จากที่อื่น

### 4.7 ตัวนับที่ต้องมี

`brain/store/metrics.py` ต้องเปิดเผยอย่างน้อย:

| ตัวนับ | ทำไมต้องมี |
|--------|-----------|
| `rows_written{table}` | |
| `bar_conflicts` | §4.5 |
| `queue_depth{queue}` · `queue_drops{queue}` | 🔴 `drops > 0` = ข้อมูลหาย |
| `db_errors{table}` | |
| `intent_dispatch_failures` | 🔴 = มี decision ที่ไม่ได้ส่ง |
| `orphan_intent_acks` | 🔴 §4.6 |
| `flush_latency_p95_ms` | |

ตัวที่มี 🔴 คือตัวที่ **SPEC-029 ต้องเอาไป alert** — เขียนไว้ให้ครบตั้งแต่ตอนนี้

### 4.8 latency p95 — ให้ query ได้ ไม่ต้องคำนวณเอง

[roadmap Phase 1 exit](../04-roadmap.md) ต้องการ *"p95 (intent ออกจาก brain → order filled) < 500ms"*

คำนวณได้จากของที่มีอยู่แล้ว: `exec_reports.ts − intents.decided_at`
**ไม่ต้องเพิ่มคอลัมน์** · ticket นี้แค่ต้องเขียนสองค่านี้ให้ถูกต้องและเป็น UTC

---

## 5. Edge cases

1. **DB ล่มตอน `dispatch()`** → raise · **ไม่มี INTENT ออกสาย** · ต้องมี test
2. **DB ล่มแล้วกลับมา** → คิวที่ค้างต้องถูกเขียนต่อ ไม่ใช่ทิ้ง
3. **`EXEC_REPORT` มาก่อน `intents` commit** → ไม่ควรเกิดถ้า §4.1 ถูก · ถ้าเกิด = FK error
   → **log ERROR + alert ไม่ใช่กลืน**
4. **`STATE` ที่ `margin_level_pct` เป็น `null`** → เขียน NULL ไม่ใช่ 0 ([SPEC-010 §4.5](SPEC-010-state-reporter.md))
5. **`STATE` ที่ `positions` ว่าง** → `owned_net = {}` เขียน JSONB ว่าง ไม่ใช่ NULL
6. **session ปิดตอนคิวยังมีของ** → เขียนให้หมด ไม่ใช่ทิ้งพร้อม session
7. **ปิดโปรแกรมตอนคิวเต็ม** → flush มี timeout · **ถ้า timeout ต้อง log ว่าเหลือกี่แถว**
   ไม่ใช่ออกเงียบ
8. **`bars` batch ที่มีแถวเสียปนมา** → `COPY` จะล้มทั้ง batch → ต้อง fallback เป็นรายแถว
   เพื่อไม่ให้แถวดีหายไปด้วย · แล้ว log ว่าแถวไหนเสีย
9. **เขียน `account_state` ถี่มาก** (position เปลี่ยนรัว) → batching รับได้อยู่แล้ว
10. **นาฬิกา: `decided_at` มาจาก brain · `ts` ของ exec_report มาจาก EA** → คนละเครื่อง
    → latency ที่คำนวณได้อาจติดลบถ้านาฬิกาเพี้ยน · **ต้อง log WARN ไม่ใช่เก็บค่าลบเงียบๆ**

---

## 6. Acceptance criteria

- [ ] `intents` ถูกเขียนและ commit **ก่อน** `send_intent()` — พิสูจน์ด้วยการ mock gateway
      แล้วยืนยันลำดับ
- [ ] **DB ล่ม → `dispatch()` raise และ gateway ไม่ได้รับอะไรเลย** ★★
- [ ] DB ล่ม → `on_bar` / `on_state` **ยังไม่ block** · gateway ยังตอบ heartbeat ได้
- [ ] คิว `exec_reports` เต็ม → **หยุดรับ + FATAL** ไม่ใช่ drop
- [ ] คิว `bars` เต็ม → drop ตัวเก่าสุด + `queue_drops` เพิ่ม
- [ ] backfill 300 แท่งเข้า DB ครบ · ส่งซ้ำรอบสอง → `bar_conflicts = 300` **ไม่ error**
- [ ] `INTENT_ACK` ซ้ำ → WARN + นับ · **ไม่ raise**
- [ ] `INTENT_ACK` ของ intent ที่ไม่มีอยู่ → **ERROR + `orphan_intent_acks` เพิ่ม**
- [ ] `margin_level_pct: null` → คอลัมน์เป็น NULL (query ยืนยัน)
- [ ] ปิดโปรแกรม → คิว flush หมด · ถ้า timeout **log จำนวนที่เหลือ**
- [ ] `COPY` ล้ม → fallback รายแถว · แถวดีเข้าครบ · แถวเสียถูก log
- [ ] latency p95 คำนวณได้จาก query เดียว (`exec_reports.ts − intents.decided_at`)
- [ ] latency ติดลบ → WARN (edge 10)
- [ ] ตัวนับใน §4.7 มีครบและอ่านได้จากภายนอก
- [ ] `python tools/task.py check` ผ่านบนเครื่องที่ไม่มี DB (marker `db` ถูก skip)
- [ ] `grep -rn "except:" brain/store/` — ไม่เจอ bare except
- [ ] **`grep -rn "send_intent" brain/` — เจอเฉพาะใน `dispatch.py` และ `gateway/`**
      ★ ข้อพิสูจน์ว่าไม่มีใครข้าม `IntentDispatcher`

## 7. Test list — `tests/test_persist.py` (marker `db`)

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_intent_written_before_send` | ★★ §4.1 |
| 2 | `test_db_failure_blocks_intent_send` | ★★ §4.2 — **ไม่มีอะไรออกสาย** |
| 3 | `test_db_failure_does_not_block_bar_handler` | ★ §4.3 |
| 4 | `test_exec_report_queue_full_alerts_not_drops` | ★★ §4.4 |
| 5 | `test_bar_queue_full_drops_oldest_and_counts` | §4.4 |
| 6 | `test_backfill_300_bars_persisted` | |
| 7 | `test_duplicate_backfill_counts_conflicts_no_error` | ★ §4.5 |
| 8 | `test_batch_uses_copy_above_threshold` | |
| 9 | `test_copy_failure_falls_back_to_row_by_row` | ★ edge 8 |
| 10 | `test_duplicate_intent_ack_warns_not_raises` | §4.6 |
| 11 | `test_orphan_intent_ack_errors_and_counts` | ★ §4.6 |
| 12 | `test_null_margin_level_persisted_as_null` | edge 4 |
| 13 | `test_empty_owned_net_is_empty_jsonb_not_null` | edge 5 |
| 14 | `test_queue_flushed_on_shutdown` | edge 6/7 |
| 15 | `test_shutdown_timeout_logs_remaining_rows` | edge 7 |
| 16 | `test_db_recovers_and_queue_drains` | edge 2 |
| 17 | `test_latency_query_returns_expected_p95` | §4.8 |
| 18 | `test_negative_latency_warns` | edge 10 |

**test 1 · 2 · 4 คือสามตัวที่สำคัญที่สุด** — ทั้งสามคือกฎ *"ไม่มีหลักฐาน = ไม่เทรด"*

## 8. Files

**Touch:** `brain/store/{persist,writer,dispatch,metrics}.py` · `tests/test_persist.py`

**ห้ามแตะ:** `brain/gateway/**` ★ (ต่อผ่าน `Handlers` protocol เท่านั้น)
· `migrations/**` · `contracts/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | คิว 10,000 กับ flush 100/1s เหมาะไหม | **ไม่บล็อก** — เริ่มที่ค่านี้ · **วัด `queue_depth` กับ `flush_latency_p95` ตอน soak แล้วรายงาน** อย่าปรับเอง |
| Q2 | `exec_reports` ควร durable แบบเดียวกับ `intents` ไหม | **ไม่บล็อก — ตอบแล้ว: ไม่** · EA จะ retry `EXEC_REPORT` ไม่ได้ (ไม่ต้อง ack) แต่มันมาหลังเหตุการณ์เกิดแล้ว ต่างจาก `intents` ที่มาก่อน · buffer + ห้าม drop + alert ตอนเต็ม เพียงพอ |
| Q3 | ต้องมี dead-letter สำหรับแถวที่เขียนไม่ได้ไหม | **ยังไม่ต้อง** — edge 8 fallback รายแถวแล้ว log · ถ้าเจอกรณีที่ต้องกู้จริงค่อยเปิด ticket |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ 006 + 013 merge**

---

## ภาคผนวก — ทำไม "DB ล่ม = ไม่เทรด" ถึงเป็นคำตอบที่ถูก

ทางที่ดูยืดหยุ่นกว่าคือ: DB ล่มก็เทรดต่อไป เขียน log ลงไฟล์ไว้ก่อน แล้วค่อยตามเก็บทีหลัง
ระบบยังทำงาน ไม่เสียโอกาส

ปัญหาคือ **DB ล่มไม่ใช่เหตุการณ์สุ่ม** — มันมักเกิดพร้อมกับอย่างอื่น: ดิสก์เต็ม ·
เครื่องโหลดหนัก · เน็ตมีปัญหา · โปรเซสกำลังจะตาย

แปลว่าช่วงที่บันทึกไม่ได้ คือช่วงที่**มีแนวโน้มจะเกิดเรื่องมากที่สุด**
ระบบที่เลือกเทรดต่อในช่วงนั้น กำลังเลือกที่จะ**ไม่มีหลักฐานพอดีตอนที่ต้องการมันที่สุด**

ราคาของ fail-closed คือ intent ที่ตกหล่นไปบ้าง — ซึ่งเป็นต้นทุนที่วัดได้และรับได้
ราคาของ fail-open คือวันที่พอร์ตเสียหายแล้วตอบไม่ได้ว่าเกิดอะไรขึ้น
