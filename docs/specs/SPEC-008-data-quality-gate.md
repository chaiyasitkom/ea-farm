# SPEC-008 — Data quality gate

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-007 · **Blocks:** SPEC-031, SPEC-032
**อ้าง:** [04-roadmap Phase 0](../04-roadmap.md) exit — *"missing bar < 0.1%"*

---

## 1. Goal

ตรวจว่าข้อมูลที่ ingest มาเชื่อถือได้พอที่จะสร้าง feature และ backtest บนมัน
และ**บอกได้ว่าตรงไหนเชื่อไม่ได้** ก่อนที่จะมีใครเอาไปใช้

## 2. Non-goals

- ❌ **ห้ามแก้ข้อมูล** — ดู §4.1 ★ (นี่คือกฎที่สำคัญที่สุดใน ticket นี้)
- ❌ ห้าม ingest ใหม่เอง — รายงานแล้วให้คนสั่ง `--force` (SPEC-007)
- ❌ ห้ามใช้ปฏิทินวันหยุดจากภายนอก — ดู §4.2
- ❌ ห้ามตรวจ resample (SPEC-007 §4.4 ทำแล้วด้วย ground truth ของ MT5)
- ❌ ห้ามแตะ `data/` นอกจากอ่าน

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `research/quality/profile.py` | สร้าง session profile จากข้อมูลเอง (§4.2) |
| `research/quality/checks.py` | ตัวตรวจแต่ละอย่าง — **ฟังก์ชันบริสุทธิ์** |
| `research/quality/report.py` | JSON + สรุปให้คนอ่าน |
| `research/quality/__main__.py` | CLI |
| `tools/task.py` | **แก้** — เพิ่ม `quality` |
| `tests/test_quality.py` | §7 |

### 3.2 CLI

```
python -m research.quality --all                 # ทุก symbol ใน registry ที่มีข้อมูล
python -m research.quality --symbol EURUSD.iux --broker IUXMarkets-Demo
python -m research.quality --all --fail-under-threshold   # ใช้ใน gate (exit 1 ถ้าไม่ผ่าน)
```

### 3.3 ผลลัพธ์

```
data/quality/
  report-<broker>-<symbol>.json    ← เครื่องอ่าน
  bad_ranges.json                  ← ★ ช่วงที่ห้ามใช้ downstream (§4.1)
  summary.txt                      ← คนอ่าน
```

`bad_ranges.json`:
```json
{
  "IUXMarkets-Demo/EURUSD.iux": [
    { "from": "2019-03-11T00:00:00", "to": "2019-03-11T23:59:00",
      "reason": "GAP_SYMBOL_SPECIFIC", "missing_bars": 1440 }
  ]
}
```

**SPEC-031 (feature store) และ SPEC-032 (backtest) ต้องอ่านไฟล์นี้และข้ามช่วงเหล่านี้**
— บันทึกไว้เป็นข้อผูกพันตั้งแต่ตอนนี้

---

## 4. Behaviour

### 4.1 ★★ ห้ามแก้ข้อมูล — เด็ดขาด

ห้าม forward-fill · ห้าม interpolate · ห้ามลบแท่งที่ดูแปลก · ห้ามเขียนทับไฟล์ใน `data/bars/`

**quality gate ที่ซ่อมข้อมูลเงียบๆ แย่กว่าไม่มี gate เลย** — เพราะหลังจากนั้น
จะไม่มีใครรู้ว่าตัวเลขที่เห็นเป็นของจริงหรือของที่เราเติมเข้าไป
และ backtest จะดูดีขึ้นด้วยเหตุผลที่ไม่ใช่กลยุทธ์

หน้าที่ของ ticket นี้คือ **ชี้ว่าตรงไหนเชื่อไม่ได้** แล้วให้ downstream ข้ามเอง

### 4.2 ★★ session profile — สร้างจากข้อมูลเอง ไม่ใช้ปฏิทินภายนอก

ปัญหาหลักคือ **แยก "ตลาดปิดตามปกติ" ออกจาก "ข้อมูลหาย"**
ทองมีพักรายวัน · FX ไม่มี · แต่ละโบรกเกอร์เปิด-ปิดไม่เท่ากัน · และเราไม่มีปฏิทินของใคร

**วิธี:** สำหรับแต่ละ symbol คำนวณว่าแต่ละ `(วันในสัปดาห์, นาทีของวัน)` มีแท่งกี่ % ของสัปดาห์ทั้งหมด

| สัดส่วนที่มีแท่ง | ตีความ | แท่งที่หายตรงนี้ |
|-----------------|--------|------------------|
| **> 0.90** | ช่วงเทรดปกติ | 🔴 **นับเป็น gap** |
| **< 0.10** | ตลาดปิดปกติ | ✅ ไม่นับ |
| 0.10 – 0.90 | ก้ำกึ่ง (วันหยุด · ขอบ DST) | 🟡 **รายงานแยก ไม่นับเป็น gap** |

**ทำไมวิธีนี้ถึงใช้ได้:** ข้อมูลเป็น **เวลา broker แบบ naive** ([SPEC-007 §4.3](SPEC-007-data-ingest.md))
และโบรกเกอร์เลื่อนเวลาตาม DST ไปพร้อมกับตลาด
→ **session ในเวลา broker จึงนิ่งข้าม DST** ซึ่งเป็นกรอบที่ถูกต้องสำหรับการวิเคราะห์นี้พอดี

### 4.3 ★ แยก gap ของ symbol เดียว ออกจาก gap ของทั้งตลาด

วันคริสต์มาส/ปีใหม่จะทำให้ทุก symbol หายพร้อมกัน — **ไม่ใช่ปัญหาของเรา**
แต่ถ้า `EURUSD` หายวันหนึ่งขณะที่อีก 5 ตัวมีข้อมูลครบ — **นั่นคือปัญหา**

| เงื่อนไข | ประเภท | นับเข้าเกณฑ์ fail ไหม |
|----------|--------|----------------------|
| หายพร้อมกัน **≥ 4 ใน 6 symbol** | `GAP_MARKET_WIDE` | ❌ รายงานอย่างเดียว |
| หายเฉพาะบาง symbol | `GAP_SYMBOL_SPECIFIC` | ✅ **นับ** |

การเทียบข้ามsymbol นี้ทำให้ไม่ต้องมีปฏิทินวันหยุดเลย และได้ผลถูกต้องกว่าปฏิทินสำเร็จรูป
เพราะสะท้อน**วันหยุดของโบรกเกอร์รายนี้จริงๆ**

### 4.4 รายการตรวจ + เกณฑ์

| # | ตรวจ | เกณฑ์ | เกิน = |
|---|------|-------|--------|
| 1 | `low <= min(open,close)` · `high >= max(open,close)` · `low <= high` | **0 แถว** | 🔴 FAIL |
| 2 | ราคา ≤ 0 | **0 แถว** | 🔴 FAIL |
| 3 | timestamp ซ้ำ | **0 แถว** | 🔴 FAIL |
| 4 | timestamp ไม่เรียงขึ้น | **0 แถว** | 🔴 FAIL |
| 5 | timestamp ไม่ตรงกริด (M1 ต้องวินาที = 0) | **0 แถว** | 🔴 FAIL |
| 6 | `spread < 0` | **0 แถว** | 🔴 FAIL |
| 7 | **`GAP_SYMBOL_SPECIFIC`** | **< 0.1%** ของแท่งที่คาดหวัง | 🔴 FAIL |
| 8 | spike (§4.5) | < 0.01% | 🔴 FAIL |
| 9 | `tick_volume == 0` แต่ `high != low` | < 0.1% | 🟡 WARN |
| 10 | spread สูงผิดปกติ (> p99.9 × 5) | — | 🟡 WARN |
| 11 | `GAP_MARKET_WIDE` | — | 🟡 WARN |
| 12 | ช่วงก้ำกึ่ง (§4.2) | — | 🟡 WARN |
| 13 | cross-broker: canonical เดียวกัน ราคาต่างเกิน 0.5% | — | 🟡 WARN · **ข้ามถ้ามีโบรกเกอร์เดียว** |

**ข้อ 1–6 เป็น invariant แข็ง ไม่มีเกณฑ์ให้ต่อรอง** — ผิดแม้แถวเดียวแปลว่าข้อมูลเสีย
หรือ ingest พัง ต้องหยุดแล้วหาสาเหตุ

### 4.5 Spike — ใช้สถิติทนทาน ไม่ใช่ค่าคงที่เป็น pip

เกณฑ์แบบ "ขยับเกิน 50 pip = spike" ใช้ไม่ได้ข้าม symbol
(ทอง 50 pip กับ EURUSD 50 pip คนละเรื่อง) และใช้ไม่ได้ข้ามยุค (ความผันผวนเปลี่ยน)

```
r_t   = ln(close_t / close_{t-1})
mad   = median(|r|) ของหน้าต่างย้อนหลัง 1440 แท่ง
spike ถ้า |r_t| > 20 × mad     (และ mad > 0)
```

- ใช้ **median absolute** ไม่ใช่ standard deviation — ค่า sd จะถูก spike ตัวมันเองดึงจนไม่จับอะไรเลย
- `mad == 0` (ตลาดนิ่งสนิท) → ข้าม ไม่ใช่หารศูนย์
- **spike ไม่ได้แปลว่าข้อมูลผิดเสมอ** — ข่าวแรงจริงก็เป็นแบบนี้
  จึงตั้งเกณฑ์ fail ไว้หลวม (0.01%) และ**ต้องลิสต์ทุกตัวออกมาให้คนดู**

### 4.6 ตัวหารของ "missing %"

```
แท่งที่คาดหวัง = จำนวนช่อง (dow, minute) ที่ profile > 0.90
                  รวมตลอดช่วงที่ "มีข้อมูลจริง" เท่านั้น
```

**ห้ามนับช่วงก่อนแท่งแรกและหลังแท่งสุดท้าย** — ข้อมูล IUX เริ่ม 2016
ขอ 2010 มาก็ต้องไม่ถูกนับว่าหาย 6 ปี

### 4.7 ผลลัพธ์ต้อง deterministic

ข้อมูลชุดเดิม → รายงานเหมือนเดิมทุกครั้ง (รวมลำดับใน JSON)
เพราะ gate นี้จะถูกใช้ตัดสินว่า "ผ่าน/ไม่ผ่าน" ซ้ำๆ

---

## 5. Edge cases

1. **ไม่มีข้อมูลเลยสำหรับ symbol นั้น** → รายงานว่า "ไม่มีข้อมูล" **ไม่ใช่ FAIL** และไม่ใช่ 100% missing
2. **ข้อมูลน้อยกว่า 4 สัปดาห์** → profile เชื่อไม่ได้ → **ข้ามการตรวจ gap + WARN**
   (ต้องมีตัวอย่างพอถึงจะรู้ว่าอะไรคือปกติ)
3. **symbol ที่มีโบรกเกอร์เดียว** → ข้ามข้อ 13
4. **DST เปลี่ยน** → ช่วงขอบจะตกในโซนก้ำกึ่ง 0.10–0.90 โดยอัตโนมัติ (ตั้งใจ)
5. **แท่งแรกของชุด** → คำนวณ return ไม่ได้ → ข้าม ไม่ใช่ error
6. **ทั้งไฟล์เป็น `tick_volume = 0`** → โบรกเกอร์ไม่ให้ค่า → WARN ครั้งเดียวไม่ใช่ทุกแถว
7. **หน่วยความจำ** — 3.8M แถว × 6 symbol · ประมวลผลทีละ symbol ทีละปี
8. **`bad_ranges.json` ว่าง** → ปกติ (ข้อมูลดี) ไม่ใช่ error
9. **รันตอน ingest ยังไม่เสร็จ** → เห็นข้อมูลไม่ครบ → ต้องอ่าน `_manifest.json` ของ SPEC-007
   แล้วตรวจเฉพาะช่วงที่ manifest บอกว่าสำเร็จ

---

## 6. Acceptance criteria

- [ ] `python -m research.quality --all` สร้าง report ครบทุก symbol ที่มีข้อมูล
- [ ] **`grep -rn "fillna\|interpolate\|ffill\|bfill\|to_parquet" research/quality/` — ไม่เจอ**
      ★ ข้อพิสูจน์ว่าไม่แก้ข้อมูล (§4.1)
- [ ] `data/bars/` **ไม่ถูกแก้เลย** — เทียบ checksum ก่อน/หลังรัน
- [ ] session profile ของ `XAUUSD.iux` **จับช่วงพักรายวันได้** โดยไม่ต้องบอก
      · ของ `EURUSD.iux` ต้องไม่มีช่วงพักรายวัน
- [ ] วันหยุดตลาด (เช่น 25 ธ.ค.) ถูกจัดเป็น `GAP_MARKET_WIDE` **ไม่ใช่** `GAP_SYMBOL_SPECIFIC`
- [ ] ฉีดข้อมูลเสียเข้าไปแล้วต้องจับได้ทุกแบบ (test 1–6 ใน §7)
- [ ] `--fail-under-threshold` คืน **exit 1** เมื่อ gap > 0.1% · **exit 0** เมื่อผ่าน
- [ ] รัน 2 ครั้ง → report **byte-identical**
- [ ] symbol ที่ไม่มีข้อมูล → รายงาน "ไม่มีข้อมูล" ไม่ใช่ FAIL
- [ ] `bad_ranges.json` อ่านได้และมี `reason` ทุกช่วง
- [ ] **roadmap Phase 0 exit ตรวจได้จริง**: รายงานบอก missing % ต่อ symbol เทียบกับ 0.1%
- [ ] `python tools/task.py check` ผ่าน (unit test ใช้ข้อมูลสังเคราะห์ ไม่ต้องมี MT5/ข้อมูลจริง)
- [ ] `grep -rn "except:" research/quality/` — ไม่เจอ bare except

## 7. Test list — `tests/test_quality.py`

**unit test ทั้งหมดใช้ข้อมูลสังเคราะห์ที่สร้างในเทสต์** — deterministic ไม่ต้องมี MT5

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_detects_ohlc_violation` | `high < low` |
| 2 | `test_detects_nonpositive_price` | |
| 3 | `test_detects_duplicate_timestamp` | |
| 4 | `test_detects_unsorted_timestamps` | |
| 5 | `test_detects_off_grid_timestamp` | วินาที ≠ 0 |
| 6 | `test_detects_negative_spread` | |
| 7 | `test_profile_learns_daily_break` | ★ สร้างข้อมูลที่มีพักรายวัน → profile ต้องจับได้ |
| 8 | `test_profile_learns_weekend` | |
| 9 | `test_gap_in_traded_session_is_counted` | ★ §4.2 |
| 10 | `test_gap_in_closed_session_is_not_counted` | ★ ตัวที่ทำให้ false positive ท่วม ถ้าทำผิด |
| 11 | `test_ambiguous_band_reported_separately` | 0.10–0.90 |
| 12 | `test_market_wide_gap_not_counted_as_failure` | ★★ §4.3 |
| 13 | `test_symbol_specific_gap_counted_as_failure` | ★★ |
| 14 | `test_spike_uses_mad_not_stddev` | ★ ใส่ spike ใหญ่ 1 ตัว → ต้องยังจับตัวที่สองได้ |
| 15 | `test_spike_skipped_when_mad_zero` | หารศูนย์ |
| 16 | `test_expected_bars_excludes_before_first_and_after_last` | ★ §4.6 |
| 17 | `test_short_history_skips_gap_check_with_warning` | edge 2 |
| 18 | `test_no_data_is_not_failure` | edge 1 |
| 19 | `test_report_is_deterministic` | §4.7 |
| 20 | `test_source_files_unchanged_after_run` | ★★ §4.1 — checksum ก่อน/หลัง |
| 21 | `test_exit_code_reflects_threshold` | |
| 22 | `test_cross_broker_check_skipped_with_one_broker` | edge 3 |

**test 10 · 12 · 20 คือสามตัวที่สำคัญที่สุด:**
- 10 กับ 12 คือตัวที่ถ้าทำผิด รายงานจะเต็มไปด้วย false positive จนไม่มีใครอ่าน
- 20 คือตัวที่ปกป้องกฎ "ห้ามแก้ข้อมูล"

## 8. Files

**Touch:** `research/quality/**` · `tests/test_quality.py` · `tools/task.py`

**ห้ามแตะ:** `data/bars/**` (อ่านอย่างเดียว) · `research/ingest/**` · `contracts/**`
· `docs/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | เกณฑ์ profile 0.90 / 0.10 เหมาะไหม | **ไม่บล็อก** — เริ่มที่ค่านี้ · **รันกับข้อมูลจริงแล้วรายงานว่าโซนก้ำกึ่งมีกี่ %** ถ้าเยอะผิดปกติแปลว่าเกณฑ์ไม่เหมาะ **อย่าปรับเอง** |
| Q2 | `20 × MAD` สำหรับ spike เหมาะไหม | **ไม่บล็อก** — รายงานจำนวน spike ที่เจอต่อ symbol · ถ้าเจอเป็นพันตัวแปลว่าเกณฑ์ต่ำไป |
| Q3 | เกณฑ์ market-wide (≥4 ใน 6) เหมาะไหม | **ไม่บล็อก** — ตอนนี้มีข้อมูลโบรกเกอร์เดียว 6 symbol · พอ XM เข้ามา (D11) ค่อยทบทวน |

> **ไม่มีคำถามที่บล็อก — เริ่มได้ทันที**
> unit test ทั้ง 22 ตัวใช้ข้อมูลสังเคราะห์ **จึงเขียนได้เลยโดยไม่ต้องรอ SPEC-007 ingest จริง**

---

## ภาคผนวก — ทำไมไม่ใช้ปฏิทินวันหยุดสำเร็จรูป

ทางที่ดูง่ายกว่าคือดึงปฏิทินวันหยุดตลาดมาใส่ แล้วบอกว่าวันไหนไม่ต้องมีข้อมูล

แต่สิ่งที่เราต้องรู้จริงๆ ไม่ใช่ *"ตลาดหยุดวันไหน"* — มันคือ ***"โบรกเกอร์รายนี้ ไม่ส่งราคา
ของ symbol นี้ ตอนไหน"*** ซึ่งไม่เท่ากัน: โบรกเกอร์ปิดเร็วกว่าตลาด · เปิดสายกว่า ·
มีพักที่ตลาดไม่มี · และเปลี่ยนนโยบายได้โดยไม่บอก

ปฏิทินภายนอกจะให้คำตอบที่ *"ถูกตามทฤษฎี"* แล้วสร้าง false positive ทุกครั้งที่โบรกเกอร์
ทำไม่เหมือนตลาด — พอ false positive เยอะ คนจะเลิกอ่านรายงาน แล้ว gate ก็ไร้ค่า

การเรียนจากข้อมูลเองให้คำตอบที่ *"ถูกตามความเป็นจริงของแหล่งข้อมูลเรา"*
และไม่ต้องดูแลปฏิทินให้ทันสมัยตลอดไป
