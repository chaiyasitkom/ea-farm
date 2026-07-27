# SPEC-007 — Data ingest: MT5 → Parquet

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-002, SPEC-064 · **Blocks:** SPEC-008, SPEC-031, SPEC-032
**อ้าง:** [ADR-002 §2.5](../decisions/ADR-002-symbols-capital-hours.md) · [ADR-003](../decisions/ADR-003-multi-broker.md)

---

## 1. Goal

ดึงข้อมูล **M1 ย้อนหลัง ~10 ปี ของ 6 คู่** ออกจาก MT5 ลง Parquet
แล้ว resample เป็น M5/M10/M15/M30/H1/H4 **โดยพิสูจน์ได้ว่า resample ตรงกับ MT5 เอง**

**ดึง M1 อย่างเดียว ที่เหลือคำนวณเอง** ([ADR-002 §2.5](../decisions/ADR-002-symbols-capital-hours.md))
— ดึง 7 TF แยกกันจะได้ข้อมูลไม่ consistent กันเองถ้าโบรกเกอร์แก้ประวัติย้อนหลัง (G12)
และ resample เองทำให้ backtest กับ live ใช้ตรรกะเดียวกัน (จำเป็นสำหรับ SPEC-033 parity)

## 2. Non-goals

- ❌ ห้ามเขียนลง PostgreSQL — **ข้อมูลย้อนหลังอยู่ Parquet ไม่ใช่ DB** ([SPEC-006 §3.1](SPEC-006-database.md))
- ❌ ห้าม implement quality gate (SPEC-008) — ticket นี้แค่ดึงมาให้ครบ
- ❌ ห้าม implement feature engineering (SPEC-031)
- ❌ ห้ามดึง tick data — M1 พอสำหรับทุกอย่างที่วางแผนไว้ · tick เป็นเรื่องของ SPEC-032 ถ้าจำเป็น
- ❌ **ห้ามคำนวณ UTC เอง** — ดู §4.3 ★

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `research/ingest/mt5_source.py` | คุยกับ MT5 ผ่าน package `MetaTrader5` |
| `research/ingest/writer.py` | เขียน Parquet + partition |
| `research/ingest/resample.py` | M1 → TF อื่น ★ ต้องพิสูจน์ความถูกต้อง (§4.4) |
| `research/ingest/__main__.py` | CLI |
| `tools/task.py` | **แก้** — เพิ่ม `ingest` |
| `tests/test_ingest.py` | §7 |

### 3.2 CLI

```
python -m research.ingest --broker IUXMarkets-Demo --symbol EURUSD.iux \
                          --from 2016-01-01 --to 2026-07-01
python -m research.ingest --all              # ทุก symbol ที่อยู่ใน registry
python -m research.ingest --all --resume     # ★ ทำต่อจากที่ค้าง (§4.5)
```

### 3.3 Layout ปลายทาง

```
data/bars/
  broker=IUXMarkets-Demo/
    symbol=EURUSD.iux/
      tf=M1/year=2016/part.parquet
      tf=H1/year=2016/part.parquet
      …
  _manifest.json          ← ดึงอะไรไปแล้วบ้าง ช่วงไหน เมื่อไร (§4.5)
```

Hive-style partition → duckdb/polars ทำ predicate pushdown ได้
`data/` ถูก `.gitignore` ไว้แล้ว **ห้าม commit**

### 3.4 Schema ของ Parquet

| คอลัมน์ | ชนิด | หมายเหตุ |
|---------|------|----------|
| `time_broker` | `timestamp[s]` **naive** | ★ เวลาของโบรกเกอร์ตรงๆ **ไม่แปลง** ดู §4.3 |
| `open` `high` `low` `close` | `float64` | |
| `tick_volume` | `int64` | |
| `spread` | `int32` | หน่วย point |
| `real_volume` | `int64` | 0 บนบัญชี retail |

`broker` · `symbol` · `tf` · `year` อยู่ใน path ไม่ต้องซ้ำในไฟล์

---

## 4. Behaviour

### 4.1 🔴 `MaxBars=100000` — ตัวที่จะทำให้ข้อมูลขาดแบบเงียบ

ตรวจแล้ว `config\common.ini` ของ IUX ตั้ง `[Charts] MaxBars=100000`
แต่ **M1 10 ปี ≈ 3.8 ล้าน bar ต่อ symbol = เกินเพดาน 38 เท่า**

**ต้องทำ:**
1. **ดึงเป็นช่วงย่อย** — เดือนละครั้ง (M1 1 เดือน ≈ 30k bar อยู่ใต้เพดานสบาย)
2. **นับผลทุกช่วง** — ถ้าจำนวน bar ที่ได้ **น้อยกว่าที่คาดอย่างมีนัยสำคัญ** ต้อง WARN
   ไม่ใช่เขียนลงไฟล์เงียบๆ
3. ถ้าดึงได้ 0 bar ทั้งที่ช่วงนั้นเป็นวันทำการ → **error ไม่ใช่ข้าม**

> `common.ini` เป็น **ไฟล์ ini ธรรมดา แก้ได้** (ต่างจาก `settings.ini` ที่เข้ารหัส)
> ถ้าพิสูจน์ได้ว่า `MaxBars` เป็นตัวจำกัดจริง ให้**รายงานพร้อมตัวเลข** อย่าไปแก้เอง
> — เป็น config ของเครื่องที่อยู่นอก git ([work-order §1.5](../work-order.md))

### 4.2 ★ ingest กับ MQL5 gate ใช้เทอร์มินัลพร้อมกันไม่ได้

| งาน | ต้องการ |
|-----|---------|
| `ingest` | เทอร์มินัล **เปิดและ login อยู่** (`mt5.initialize()`) |
| `mql5-gate` / `test-roundtrip` | เทอร์มินัล **ปิดสนิท** (headless tester) |

→ `tools/task.py ingest` ต้อง **เช็คว่า gate ไม่ได้กำลังรัน** และในทางกลับกัน
· `check-full` **ห้ามรัน ingest** อยู่แล้วเพราะ ingest ไม่ใช่ test

**เขียนข้อจำกัดนี้ไว้ใน `docs/setup.md`** (ร่างส่งมาใน handoff) — คนที่มาทีหลังจะไม่รู้เอง

### 4.3 ★★ เวลา — **ห้ามแปลงเป็น UTC ใน ticket นี้**

MT5 คืนเวลา bar เป็น **เวลา broker** · การแปลงเป็น UTC ต้องรู้ offset **ณ ขณะนั้นในอดีต**
ซึ่งเปลี่ยนตาม DST ปีละ 2 ครั้ง **เราไม่มีข้อมูลนั้น**

[SPEC-063](SPEC-063-broker-time.md) `CBrokerTime` ตรวจ offset **ปัจจุบัน** ได้เท่านั้น
→ ใช้ offset ปัจจุบันแปลงข้อมูลปี 2016 = **ผิดครึ่งปี ทุกปี**

**กฎ:**
- เก็บ `time_broker` แบบ naive ตรงตามที่ MT5 ให้ **ห้ามใส่ tzinfo ห้ามบวกลบอะไร**
- ชื่อคอลัมน์ต้องบอกชัดว่าเป็นเวลาอะไร — **ห้ามตั้งชื่อว่า `time` หรือ `ts` เฉยๆ**
- `broker` อยู่ใน path แล้ว → รู้เสมอว่าเป็นนาฬิกาของใคร

> **นี่คือการปฏิเสธที่จะเดา** — เขียน UTC ผิดลง 3.8 ล้านแถว × 6 symbol
> แล้วมารู้ตอน Phase 3 ว่าเพี้ยน จะต้อง ingest ใหม่ทั้งหมดและ backtest ทุกตัวเป็นโมฆะ

**เพิ่มหนี้ใหม่ D15** — "historical broker→UTC mapping" ต้องแก้ก่อน SPEC-032/033
(ตอนนั้นค่อยเลือกวิธี: ปฏิทิน DST ของโบรกเกอร์ · หรือ infer จากขอบสัปดาห์ของข้อมูลเอง)

### 4.4 ★★ Resample ต้องพิสูจน์ด้วยของจริง ไม่ใช่เชื่อว่าถูก

เรามี **ground truth อยู่แล้ว**: MT5 มี H1/H4 ของตัวเอง

```
resample(M1 → H1)  เทียบกับ  MT5 H1 ช่วงเดียวกัน
→ open/high/low/close ต้องตรง "ทุกแท่ง"
```

ถ้าไม่ตรง = การ resample ของเราผิด และ **backtest ทุกตัวที่สร้างบนนั้นจะผิดตาม**
โดยไม่มีอะไรพัง

| จุดที่ resample พลาดบ่อย | |
|--------------------------|---|
| การจัดขอบ H4 | H4 เริ่มที่ 00/04/08… **ตามเวลา broker** ไม่ใช่ UTC |
| bar ที่ไม่มีข้อมูล | ช่วงตลาดปิด → **ห้ามสร้างแท่งเปล่า** ต้องข้ามไปเลย |
| `tick_volume` | ต้อง **รวม** ไม่ใช่เอาค่าสุดท้าย |
| `spread` | เอา **ค่าเฉลี่ย** และเก็บ **max** แยก (ตรงกับ `bar.json`) |
| แท่งสุดท้ายของช่วง | อาจไม่ครบชั่วโมง → **ตัดทิ้ง** ไม่ใช่เก็บแท่งที่ไม่สมบูรณ์ |

**ต้องเทียบอย่างน้อย 3 เดือน × 2 symbol** และรายงานจำนวนแท่งที่ไม่ตรง (ต้องเป็น 0)

### 4.5 Incremental / resume

`_manifest.json` เก็บ: `broker` · `symbol` · `tf` · ช่วงที่สำเร็จ · `bar_count` · เวลาที่ดึง

| สถานการณ์ | ทำอะไร |
|-----------|--------|
| รันซ้ำช่วงเดิม | ข้าม (มีใน manifest แล้ว) เว้นแต่ใส่ `--force` |
| ค้างกลางทาง | `--resume` ทำต่อจากเดือนที่ยังไม่สำเร็จ |
| โบรกเกอร์แก้ประวัติย้อนหลัง | `--force` ดึงใหม่ · **manifest ต้องบันทึกว่าเคยดึงได้กี่แท่ง** เพื่อให้เห็นว่าเปลี่ยน (G12) |

**เขียนไฟล์แบบ atomic** — เขียนไฟล์ชั่วคราวแล้ว rename
ไม่งั้นถ้าตายกลางทางจะได้ Parquet ที่พังและ manifest บอกว่าสำเร็จ

### 4.6 หลาย broker — ต่อทีละตัว

`MetaTrader5` package ต่อได้ **ทีละเทอร์มินัลเท่านั้น**
→ `initialize(path=IUX)` → ดึง → `shutdown()` → `initialize(path=XM)` → ดึง → `shutdown()`

**XM ตอนนี้ login ไม่ได้ (D11)** → ต้อง `[SKIP]` พร้อมเหตุผลชัด **ไม่ใช่ fail ทั้งงาน**
· กฎเดียวกับเป้า XM ใน MQL5 gate

symbol ที่จะดึงมาจาก **SymbolRegistry** (SPEC-064) ไม่ใช่ hardcode
→ XM ไม่มี `AUDUSD`/`USDCAD` ในตาราง = ไม่ต้องดึง ไม่ใช่ error

---

## 5. Edge cases

1. **`mt5.initialize()` ล้มเหลว** — เทอร์มินัลไม่ได้เปิด / path ผิด / ไม่ได้ login
   → error ที่บอกว่าต้องทำอะไร ไม่ใช่ `RuntimeError` ดิบ
2. **symbol ไม่อยู่ใน Market Watch** — ต้อง `symbol_select(name, True)` ก่อน · ถ้ายังไม่ได้ → error พร้อมชื่อ
3. **ช่วงที่ขอเก่ากว่าที่โบรกเกอร์มี** — คืน 0 แท่ง → บันทึกว่า "ไม่มีข้อมูล" ใน manifest **ไม่ใช่ error**
   (IUX มีตั้งแต่ 2016 · ขอ 2010 ก็ต้องไม่พัง)
4. **สุดสัปดาห์/วันหยุด** — ไม่มีแท่ง = ปกติ ไม่ใช่ gap ที่ต้องเตือน (SPEC-008 เป็นคนตัดสิน)
5. **`copy_rates_range` คืน `None`** — ต่างจากคืน array ว่าง · ต้องแยกสองกรณีนี้และ retry
6. **หน่วยความจำ** — 3.8M แถว × 6 symbol ห้ามโหลดพร้อมกัน → เขียนทีละปี แล้วปล่อย
7. **เวลาที่ซ้ำกัน** — ถ้า MT5 คืนแท่งเวลาเดียวกัน 2 ครั้ง → เก็บตัวหลัง + WARN
8. **เวลาที่ย้อนหลัง** — array ต้องเรียงขึ้นเสมอ · ถ้าไม่เรียง = ข้อมูลเสีย → error
9. **ดิสก์เต็ม** — ~1 GB ต่อ symbol ก่อนบีบ · ต้องเช็คก่อนเริ่ม
10. **เทอร์มินัลถูกปิดกลางทาง** — จับได้และ resume ได้ ไม่ใช่เขียนไฟล์พัง

---

## 6. Acceptance criteria

- [ ] `python -m research.ingest --all` ดึง IUX ครบ 6 symbol · **XM `[SKIP]` พร้อมเหตุผล**
- [ ] `data/bars/broker=…/symbol=…/tf=M1/year=…/part.parquet` ครบทุกปีที่โบรกเกอร์มี
- [ ] **จำนวนแท่ง M1 ต่อปี ≥ 300,000** สำหรับปีที่ครบ (ปีทำการ ~370k แท่ง)
      — ถ้าได้ ~100,000 แปลว่าชน `MaxBars` **ต้องรายงาน ไม่ใช่ยอมรับ**
- [ ] **★ resample M1→H1 ตรงกับ H1 ของ MT5 ทุกแท่ง** อย่างน้อย 3 เดือน × 2 symbol
      · รายงานจำนวนแท่งที่ไม่ตรง = **0**
- [ ] resample M1→H4 ตรงกับ H4 ของ MT5 เช่นกัน (ขอบ H4 คือจุดที่พลาดง่าย)
- [ ] คอลัมน์เวลาชื่อ **`time_broker`** และเป็น **naive** — `grep -rn "tz_localize\|astimezone\|utc" research/ingest/` **ไม่เจอ**
- [ ] ไม่มีแท่งเปล่าในช่วงตลาดปิด
- [ ] รันซ้ำ → ข้ามของที่มีแล้ว (ไม่ดึงซ้ำ)
- [ ] `--resume` หลังฆ่ากลางทาง → ทำต่อได้ ไฟล์ไม่พัง
- [ ] `_manifest.json` มี `bar_count` ต่อช่วง
- [ ] ไม่มีอะไรใน `data/` ถูก commit — `git status` สะอาด
- [ ] `python tools/task.py check` ยังผ่านบนเครื่องที่ไม่มี MT5 (test ที่ต้องใช้ MT5 = marker `mt5_live`)
- [ ] `grep -rn "except:" research/ingest/` — ไม่เจอ bare except

## 7. Test list — `tests/test_ingest.py`

test ที่ไม่ต้องใช้ MT5 (รันใน `check` ปกติ):

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_resample_m1_to_h1_ohlc` | open=แท่งแรก · high=max · low=min · close=แท่งสุดท้าย |
| 2 | `test_resample_sums_tick_volume` | ★ รวม ไม่ใช่เอาค่าสุดท้าย |
| 3 | `test_resample_spread_avg_and_max` | ตรงกับ `bar.json` |
| 4 | `test_resample_skips_empty_periods` | ★ ห้ามสร้างแท่งเปล่า |
| 5 | `test_resample_drops_incomplete_last_bar` | ★ |
| 6 | `test_resample_h4_boundary_alignment` | ★ ขอบ 00/04/08 ตามเวลา broker |
| 7 | `test_time_column_is_naive_not_utc` | ★★ §4.3 |
| 8 | `test_manifest_records_bar_count` | |
| 9 | `test_rerun_skips_completed_ranges` | |
| 10 | `test_resume_after_partial_failure` | |
| 11 | `test_atomic_write_no_partial_file` | ฆ่ากลางเขียน → ไม่มีไฟล์พังค้าง |
| 12 | `test_duplicate_timestamps_warn_and_keep_last` | edge 7 |
| 13 | `test_unsorted_input_raises` | edge 8 |
| 14 | `test_symbols_come_from_registry_not_hardcoded` | SPEC-064 |

test ที่ต้องใช้ MT5 จริง (marker `mt5_live`):

| # | test | ตรวจอะไร |
|---|------|----------|
| 15 | `test_pull_one_month_returns_expected_bar_count` | ★ จับ `MaxBars` |
| 16 | `test_resampled_h1_matches_mt5_h1` | ★★ **ground truth** |
| 17 | `test_resampled_h4_matches_mt5_h4` | ★★ |
| 18 | `test_missing_broker_skips_not_fails` | XM (D11) |

**test 16–17 คือหัวใจ** — ถ้า resample ผิด ทุกอย่างที่สร้างบนข้อมูลนี้ผิดตามโดยไม่มีอะไรพัง

## 8. Files

**Touch:** `research/ingest/**` · `tests/test_ingest.py` · `tools/task.py`
· ร่าง `docs/setup.md` เพิ่มเติม (ส่งมาใน handoff · ห้าม commit `docs/`)

**ห้ามแตะ:** `contracts/**` · `docs/**` · `brain/**` · `mt5-ea/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| **Q1** | **`copy_rates_range` ตีความ `date_from`/`date_to` เป็นเวลาอะไร** — UTC หรือเวลา broker? | **ไม่บล็อก แต่ต้องพิสูจน์ก่อนดึงจริง** — ดึง 1 วันที่รู้ผลแล้วเทียบกับชาร์ตใน MT5 · **รายงานผลพร้อมหลักฐาน** ในหัวข้อแยกของ handoff · ผิดตรงนี้ = ข้อมูลเลื่อนทั้งชุดโดยไม่มีอะไรฟ้อง |
| Q2 | `MaxBars=100000` จำกัด `copy_rates_range` จริงไหม | **ไม่บล็อก** — ดึงเป็นรายเดือนอยู่แล้วซึ่งไม่น่าชน · แต่**ต้องวัดแล้วรายงาน** ว่าชนหรือไม่ · ห้ามแก้ `common.ini` เอง |
| Q3 | ใช้ pandas หรือ polars | **ไม่บล็อก — เลือกเอง** · polars เร็วกว่ามากที่ขนาดนี้และกิน RAM น้อยกว่า · pandas คนคุ้นกว่า · **pin เวอร์ชันและรายงานว่าเลือกอะไร** |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ SPEC-002 และ SPEC-064 merge**
> (เริ่มจาก `resample.py` + test 1–6 ได้เลยโดยไม่ต้องมี MT5 — เป็นฟังก์ชันบริสุทธิ์)

---

## ภาคผนวก — ทำไมถึงไม่ยอมเขียน UTC

ทางที่ง่ายคือ: อ่าน offset ปัจจุบันจาก `CBrokerTime` แล้วลบออกจากทุกแท่ง
โค้ด 1 บรรทัด ได้คอลัมน์ `time_utc` สวยงาม พร้อม join กับอะไรก็ได้

**แล้วมันจะผิดประมาณครึ่งปี ทุกปี** เพราะโบรกเกอร์เลื่อนตาม DST ปีละ 2 ครั้ง
และเราไม่มีปฏิทินว่าเลื่อนวันไหนบ้างย้อนหลัง 10 ปี

ความผิดพลาดแบบนี้ **ไม่ทำให้อะไรพัง** — Parquet เขียนได้ · backtest รันได้ ·
ตัวเลขออกมาสวย · แล้วเราจะเชื่อมันไปจนถึงวันที่เอาเงินจริงลง

การเขียน `time_broker` แล้วปฏิเสธที่จะเดา ทำให้**ปัญหาปรากฏตอนที่ต้องใช้ UTC จริง**
(SPEC-032/033) ซึ่งเป็นตอนที่เรามีเวลาแก้ ไม่ใช่ตอนที่พอร์ตขาดทุนแล้วหาสาเหตุไม่เจอ
