# SPEC-006 — Database: schema · migration · repository

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-002, SPEC-004 · **Blocks:** SPEC-013, SPEC-014, SPEC-018, SPEC-028
**อ้าง:** [02-contracts §5](../02-contracts.md)

---

## 1. Goal

มีฐานข้อมูลที่ gateway เขียนได้จริง: schema ครบ 6 ตาราง · migration รันซ้ำได้ ·
repository layer แบบ async · และ **audit trail ที่แก้ย้อนหลังไม่ได้แม้แต่โดยโค้ดเราเอง**

## 2. Non-goals

- ❌ ห้ามเขียน gateway (SPEC-013) — ticket นี้ให้แค่ชั้นเก็บข้อมูล
- ❌ ห้าม ingest ข้อมูลย้อนหลัง (SPEC-007) — **ข้อมูลประวัติศาสตร์ไปอยู่ Parquet ไม่ใช่ DB**
- ❌ ห้ามทำ dashboard / query API (SPEC-028)
- ❌ ห้ามแตะ `contracts/schema/**`
- ❌ ห้ามติดตั้งซอฟต์แวร์ลงเครื่องเจ้าของเอง — §9 Q1 เป็นการตัดสินใจของเจ้าของ

---

## 3. 🔴 สภาพเครื่องจริง — ตรวจแล้ว 2026-07-28

| | สถานะ |
|---|---|
| Docker / Docker Compose | ❌ **ไม่มี** |
| PostgreSQL | ❌ **ไม่มี** (`psql` ไม่มี · ไม่มีใน Program Files) |
| WSL2 | ✅ **มี** (Ubuntu เป็น default distro) |

> [roadmap 0.4](../04-roadmap.md) เขียนว่า *"Postgres + TimescaleDB ขึ้น (Docker Compose สำหรับ dev)"*
> — **ทำตามนั้นตรงๆ ไม่ได้เพราะไม่มี Docker** เป็นบทเรียนเดียวกับ `make` ใน SPEC-002

### 3.1 ★ ตัดสิน: **ยังไม่ใช้ TimescaleDB** — ใช้ PostgreSQL เปล่าก่อน

**เหตุผลที่ TimescaleDB ไม่จำเป็นที่ปริมาณของเรา:**

| ข้อมูล | เดิมคิดว่าเยอะ | ความจริง |
|--------|----------------|----------|
| ข้อมูลราคาย้อนหลัง 10 ปี × 6 คู่ M1 (~22M แถว) | น่าจะต้องใช้ hypertable | ❌ **ไม่เข้า DB เลย** — [SPEC-007](../backlog.md) เก็บลง **Parquet** |
| `bars` ใน DB | — | เฉพาะ bar **สด**จาก EA · 6 session × 1 bar/ชม. = **หลักพันแถว/เดือน** |
| `account_state` | 5 วินาที × 6 session = 103k แถว/วัน | จริง แต่เป็น **telemetry** เก็บ 90 วันพอ → ~9M แถว · PG เปล่ารับไหวสบาย |
| `intents` / `exec_reports` | — | ปริมาณต่ำมาก (จำกัดด้วย R17 = 6 order/นาที) |

**ประโยชน์ที่ TimescaleDB ให้** (auto-partition · compression · continuous aggregate)
ยังไม่มีอะไรที่เราต้องการ ณ ปริมาณนี้ แต่**ต้นทุนติดตั้งสูง**: ต้องใช้ Docker (ไม่มี)
หรือ Windows build ที่การรองรับไม่ชัดเจน

**นี่เป็นประตูที่เปิดกลับได้** — `create_hypertable(..., migrate_data => true)`
แปลงตารางที่มีข้อมูลแล้วได้ · จึงเลื่อนไปตัดสินตอนมีตัวเลขจริงดีกว่าเดาตอนนี้

**สิ่งที่ต้องทำเพื่อไม่ปิดประตู:**
- ทุกตาราง time-series ต้องมี index บน `(…, ts DESC)` ตั้งแต่แรก
- **ห้ามใช้ฟีเจอร์ที่ผูกกับ Timescale** ใน query ของ repository layer
- เขียน migration ให้เพิ่ม extension ทีหลังได้โดยไม่ต้องรื้อ schema

> **เจ้าของยืนยันได้ถ้าไม่เห็นด้วย** — ดู §9 Q1 · จนกว่าจะยืนยัน ให้ทำตาม PG เปล่า

---

## 4. Interface

### 4.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `migrations/versions/*.py` | alembic revision — **ใช้ `op.execute()` กับ SQL ดิบ ไม่ต้องมี ORM model** |
| `migrations/env.py` · `alembic.ini` | ตั้งค่า อ่าน URL จาก `FARM_DB_URL` |
| `brain/store/__init__.py` | |
| `brain/store/pool.py` | asyncpg connection pool |
| `brain/store/repositories.py` | ฟังก์ชัน async ต่อ 1 ตาราง |
| `tools/task.py` | **แก้** — เพิ่ม `db-up` · `db-migrate` · `db-reset` |
| `tests/test_store.py` | marker `db` (ดู §4.5) |

### 4.2 Stack

| ชั้น | เลือก | เหตุผล |
|------|-------|--------|
| driver | **asyncpg** | gateway (SPEC-013) เป็น asyncio · `psycopg` sync จะบล็อก event loop |
| ORM | **ไม่ใช้** | schema นิ่งแล้วใน [02-contracts §5](../02-contracts.md) · ORM เพิ่มชั้นแปลโดยไม่ได้อะไร และทำให้ควบคุม SQL ยาก |
| migration | **alembic** (SQL ดิบใน revision) | ได้ versioning + downgrade โดยไม่ต้องมี ORM model |

### 4.3 Repository API — บาง ไม่ฉลาด

```python
# brain/store/repositories.py
async def insert_bar(conn, *, broker: str, bar: BarPayload) -> None: ...
async def insert_bars_batch(conn, rows: Sequence[...]) -> int: ...   # ใช้ COPY

async def insert_intent(conn, *, session_id: str, intent: IntentPayload) -> None: ...
async def set_intent_ack(conn, *, intent_id: str, status: str, reason: str | None) -> None: ...
    # ★ เติมได้ครั้งเดียว -- ครั้งที่สองต้อง raise (บังคับที่ DB ดู §5.1)

async def insert_exec_report(conn, *, intent_id: str, report: ExecReportPayload) -> None: ...
async def insert_account_state(conn, *, session_id: str, state: StatePayload) -> None: ...
async def insert_risk_event(conn, **kw) -> None: ...

# query ที่ต้องมีตั้งแต่แรก
async def latest_account_state(conn, session_id: str) -> dict | None: ...
async def sessions_with_anomaly(conn, since_minutes: int = 5) -> list[dict]: ...
    # foreign_position_count > 0 OR internal_hedge_detected -- query ที่ 02-contracts §5 สั่งให้ alert
```

**ห้ามใส่ business logic ใน repository** — แปลง/ตัดสินใจอยู่ชั้นบน ที่นี่แค่อ่าน-เขียน

### 4.4 `symbol` ในตาราง = **raw ไม่ใช่ canonical**

`bars.symbol` เก็บ `"EURUSD.iux"` / `"GOLD"` ตามที่โบรกเกอร์ใช้ คู่กับคอลัมน์ `broker`
→ ตรงกับ PK `(broker, symbol, timeframe, bar_time)` ที่มีอยู่แล้ว
และตรงกับ [SPEC-064 §4.2](SPEC-064-symbol-registry.md)

การแปลงเป็น canonical เกิดที่ชั้น query/analysis **ไม่ใช่ตอนเขียน** — เพราะถ้าเก็บ canonical
แล้ววันหนึ่ง mapping เปลี่ยน ข้อมูลเก่าจะตีความไม่ได้อีก

### 4.5 pytest marker ใหม่: `db`

SPEC-002 ประกาศไว้ 3 ตัว (`slow` · `live_terminal` · `mql5`) — **ticket นี้เพิ่มตัวที่ 4**

`db` = ต้องมี PostgreSQL ที่ต่อได้จริง · **ไม่อยู่ใน `test` ปกติ**
เพราะเครื่องที่ยังไม่ได้ติดตั้ง DB ต้องรัน `check` ผ่านได้

---

## 5. Behaviour

### 5.1 ★★ Append-only ต้องบังคับที่ DB ไม่ใช่ที่ Python

[02-contracts §5](../02-contracts.md) เขียนว่า *"`intents` + `exec_reports` เป็น append-only
ห้าม UPDATE/DELETE (ยกเว้น `ack_status` ที่เติมทีหลังครั้งเดียว)"*

**ถ้าบังคับใน Python มันไม่ใช่การบังคับ** — เป็นแค่ข้อตกลง · เขียน query ตรงๆ ก็ข้ามได้
และจุดประสงค์ทั้งหมดของ audit trail คือ**แอปเราเองก็ต้องแก้ไม่ได้**

ต้องเป็น **trigger**:

```sql
CREATE OR REPLACE FUNCTION farm_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'append-only table: DELETE not allowed on %', TG_TABLE_NAME;
  END IF;

  -- UPDATE: อนุญาตเฉพาะเติม ack_status/ack_reason ที่ยังว่าง ครั้งเดียว
  IF OLD.ack_status IS NOT NULL THEN
    RAISE EXCEPTION 'ack_status already set for %', OLD.intent_id;
  END IF;
  IF (to_jsonb(NEW) - 'ack_status' - 'ack_reason')
     IS DISTINCT FROM
     (to_jsonb(OLD) - 'ack_status' - 'ack_reason') THEN
    RAISE EXCEPTION 'only ack_status/ack_reason may be updated';
  END IF;

  RETURN NEW;
END $$ LANGUAGE plpgsql;
```

- `intents` → trigger ครบทั้ง UPDATE และ DELETE
- `exec_reports` → **บล็อกทั้ง UPDATE และ DELETE** (ไม่มีข้อยกเว้น ไม่มี ack ให้เติม)
- **ต้องมี test ที่พยายามแก้แล้วต้องโดนปฏิเสธ** ไม่ใช่แค่มี trigger อยู่

### 5.2 เวลาเป็น UTC เท่านั้น

| กฎ | |
|----|---|
| ทุกคอลัมน์เวลาเป็น `TIMESTAMPTZ` | ห้าม `TIMESTAMP` เปล่า |
| ค่าที่เขียนลงต้องเป็น **UTC จริง** | มาจาก `ts_server` ที่ [SPEC-063](SPEC-063-broker-time.md) แปลงแล้ว |
| `SET TIME ZONE 'UTC'` ตอนเปิด connection | ไม่พึ่ง timezone ของเซิร์ฟเวอร์ |

**ห้ามเก็บเวลา broker-local ลง DB เด็ดขาด** — G6 ทั้งหมดมีไว้เพื่อกันเรื่องนี้

### 5.3 Migration ต้องรันซ้ำได้และรันบนฐานว่างได้

| สถานการณ์ | ต้องได้ |
|-----------|---------|
| ฐานว่าง → `db-migrate` | สร้างครบทุกตาราง |
| รัน `db-migrate` ซ้ำ | ไม่มีอะไรเกิด ไม่ error |
| มีข้อมูลอยู่ → migrate ตัวใหม่ | ข้อมูลเดิมไม่หาย |
| `db-reset` | drop ทั้งหมดแล้วสร้างใหม่ · **ต้องถามยืนยัน** หรือต้องมี `--yes` · ห้ามลบเงียบ |

### 5.4 Index ที่ต้องมีตั้งแต่แรก

| ตาราง | index | ทำไม |
|-------|-------|------|
| `bars` | PK `(broker, symbol, timeframe, bar_time)` | มีใน contract แล้ว |
| `account_state` | `(session_id, ts DESC)` | query `latest_account_state` |
| `account_state` | partial: `WHERE foreign_position_count > 0 OR internal_hedge_detected` | query alert ที่ contract สั่งไว้ |
| `intents` | `(session_id, decided_at DESC)` · `(symbol, decided_at DESC)` | |
| `exec_reports` | `(intent_id)` · `(ts DESC)` | |
| `risk_events` | `(ts DESC)` · `(rule, ts DESC)` | dashboard |

**ตั้งชื่อ index ชัดเจน** (`ix_account_state_session_ts`) — ชื่ออัตโนมัติจะทำให้ migration
ตัวหลังอ้างถึงยาก

### 5.5 Connection

- URL มาจาก `FARM_DB_URL` ใน `.env` **เท่านั้น** — ห้าม hardcode ห้าม default ที่มีรหัสผ่าน
- pool: `min_size=2` `max_size=10` ปรับผ่าน env ได้
- **timeout ทุก query** — query ที่ค้างจะทำให้ gateway ค้างทั้งตัว
- ต่อ DB ไม่ได้ตอนเริ่ม → **fail ชัดเจนพร้อม URL ที่ mask รหัสผ่านแล้ว** ไม่ใช่ traceback ดิบ

---

## 6. Edge cases

1. **`FARM_DB_URL` ไม่ได้ตั้ง** → error ที่บอกว่าให้ก๊อป `.env.example` ไม่ใช่ `KeyError`
2. **DB ล่มกลางทาง** → pool ต้อง reconnect · **ห้ามกลืน exception** (AGENTS ข้อ 10)
3. **`insert_bar` ซ้ำ (PK ชน)** — เกิดได้จาก EA ส่ง backfill ซ้ำหลัง reconnect
   → **`ON CONFLICT DO NOTHING`** ไม่ใช่ error · แต่**นับจำนวนที่ชนแล้ว log**
   ถ้าชนเยอะผิดปกติ = EA ส่งซ้ำผิดจังหวะ
4. **`insert_intent` ซ้ำ `intent_id`** → **ต้อง error** (ต่างจาก bar) เพราะ `intent_id` ซ้ำ
   = bug ของ dedupe ที่ต้องเห็น ไม่ใช่กลืน
5. **`set_intent_ack` ครั้งที่สอง** → trigger ปฏิเสธ · Python ต้องแปลงเป็น exception ที่อ่านรู้เรื่อง
6. **`exec_report` อ้าง `intent_id` ที่ยังไม่มี** — FK จะ fail · เกิดได้ถ้า EA ตอบเร็วกว่า
   brain เขียน intent → **ต้องเขียน intent ก่อนส่งเสมอ** บันทึกกฎนี้ไว้ให้ SPEC-013
7. **JSONB `owned_net`** — เก็บ raw symbol เป็น key ตาม §4.4
8. **timestamp ที่มี microsecond** — `ts_sent` มี ms · `TIMESTAMPTZ` เก็บได้ถึง µs ไม่ต้องปัด
9. **connection pool หมดตอนโหลดสูง** → รอ ไม่ใช่ crash · แต่ต้อง log ว่ารอนาน

---

## 7. Acceptance criteria

- [ ] `python tools/task.py db-migrate` สร้างครบ 6 ตารางบนฐานว่าง
- [ ] รัน `db-migrate` ซ้ำ → ไม่ error ไม่เปลี่ยนอะไร
- [ ] `alembic downgrade base` แล้ว `upgrade head` ได้ครบ
- [ ] **`UPDATE intents SET symbol='X'` → โดนปฏิเสธจาก DB** (ไม่ใช่จาก Python)
- [ ] **`DELETE FROM exec_reports` → โดนปฏิเสธจาก DB**
- [ ] `set_intent_ack` ครั้งแรกผ่าน · **ครั้งที่สองโดนปฏิเสธ**
- [ ] `insert_bar` ซ้ำ → ไม่ error และนับ conflict ได้
- [ ] `insert_intent` ซ้ำ `intent_id` → **error**
- [ ] ทุกคอลัมน์เวลาเป็น `TIMESTAMPTZ` — ตรวจด้วย query จาก `information_schema`
      **ไม่ใช่ตาดู**
- [ ] เขียนเวลา UTC เข้าไป อ่านออกมาได้ค่าเดิมเป๊ะ (ไม่มี drift จาก timezone ของ server)
- [ ] `sessions_with_anomaly()` คืนแถวเมื่อมี `foreign_position_count > 0`
- [ ] index ครบตาม §5.4 — ตรวจจาก `pg_indexes`
- [ ] ต่อ DB ไม่ได้ → error message **ไม่มีรหัสผ่านโผล่**
- [ ] `python tools/task.py check` ยัง**ผ่านบนเครื่องที่ไม่มี DB** (test `db` ถูก skip)
- [ ] `grep -rn "except:" brain/store/` — ไม่เจอ bare except
- [ ] `grep -rn "create_hypertable\|timescale" brain/ migrations/` — **ไม่เจอ** (§3.1)

## 8. Test list — `tests/test_store.py` (marker `db`)

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_migrate_from_empty_creates_all_tables` | |
| 2 | `test_migrate_is_idempotent` | |
| 3 | `test_downgrade_then_upgrade` | |
| 4 | `test_update_intents_blocked_by_db` | ★★ §5.1 |
| 5 | `test_delete_intents_blocked_by_db` | ★★ |
| 6 | `test_delete_exec_reports_blocked_by_db` | ★★ |
| 7 | `test_ack_can_be_set_once_only` | ★★ |
| 8 | `test_ack_update_cannot_change_other_columns` | ★ ช่องโหว่ที่คนมองข้าม |
| 9 | `test_insert_bar_duplicate_is_noop_and_counted` | edge 3 |
| 10 | `test_insert_intent_duplicate_raises` | edge 4 |
| 11 | `test_all_time_columns_are_timestamptz` | query `information_schema` |
| 12 | `test_utc_roundtrip_no_drift` | ★ §5.2 |
| 13 | `test_exec_report_without_intent_fails_fk` | edge 6 |
| 14 | `test_anomaly_query_returns_flagged_sessions` | contract §5 |
| 15 | `test_required_indexes_exist` | §5.4 |
| 16 | `test_connection_error_masks_password` | §5.5 |

**test 4–8 คือหัวใจของ ticket นี้** — audit trail ที่แก้ได้ = ไม่ใช่ audit trail

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| **Q1** | **ติดตั้ง PostgreSQL อย่างไร?** เครื่องไม่มี Docker · ไม่มี PG · แต่มี WSL2 | 🔴 **ต้องให้เจ้าของตัดสิน — ต้องติดตั้งซอฟต์แวร์** ดู §9.1 |
| Q2 | เอา TimescaleDB ไหม | **แนะนำ: ยังไม่เอา** (§3.1) · เจ้าของยืนยันได้ · **ไม่บล็อก** — ทำ PG เปล่าไปก่อนได้เลย |
| Q3 | retention ของ `account_state` กี่วัน | **ไม่บล็อก** — ทำ 90 วันไปก่อน · job ลบจริงเป็นงาน Phase 6 |

### 9.1 ทางเลือกการติดตั้ง PostgreSQL

| | ทางเลือก | ข้อดี | ข้อเสีย |
|---|----------|-------|---------|
| **ก** | **PostgreSQL native บน Windows** (installer จาก postgresql.org) | ติดตั้งง่ายสุด · ไม่มีชั้นกลาง · ตรงกับ VPS ที่จะเป็น Windows | ไม่มี TimescaleDB สะดวก (ซึ่ง §3.1 บอกว่ายังไม่ต้องการ) |
| ข | PostgreSQL ใน **WSL2** | มี apt ครบ · เพิ่ม Timescale ทีหลังง่าย | เพิ่มชั้น WSL · networking Windows↔WSL อีกจุดที่พังได้ |
| ค | ติด Docker Desktop ก่อน | ตรงกับ roadmap เดิม | ติดตั้งใหญ่ · ต้องใช้ WSL2 อยู่ดี · ใบอนุญาตเชิงพาณิชย์ต้องดู |

**ผมแนะนำ ก** — ตรงกับสภาพ deploy จริงที่สุด (VPS เป็น Windows เพราะ MT5)
และเป็นทางที่มีชิ้นส่วนน้อยที่สุด

> **Codex เริ่มเขียน migration + repository ได้เลยโดยไม่ต้องรอ Q1**
> — ต่อ DB จริงค่อยทำตอนรัน test marker `db` · งานที่เหลือทั้งหมดไม่ขึ้นกับว่า PG อยู่ที่ไหน

---

## ภาคผนวก — ทำไม trigger ถึงสำคัญกว่า convention

`intents` กับ `exec_reports` คือหลักฐานว่า *"ตอนนั้นระบบตัดสินใจอะไร และเกิดอะไรขึ้นจริง"*

วันที่พอร์ตเสียหายแล้วต้องหาสาเหตุ สองตารางนี้คือสิ่งเดียวที่บอกได้ว่า
model สั่งอะไร · guard ปล่อยผ่านไหม · โบรกเกอร์ตอบอะไร

ถ้าโค้ด (หรือคน หรือ AI) แก้มันได้ **มันก็ไม่ต่างจากบันทึกที่เขียนทีหลัง**
และจะไม่มีทางรู้ว่าที่อ่านอยู่คือของจริงหรือของที่ถูกแก้แล้ว

trigger ทำให้คำตอบเป็น *"แก้ไม่ได้"* แทน *"เราตกลงกันว่าจะไม่แก้"* — สองอย่างนี้ต่างกันสิ้นเชิง
