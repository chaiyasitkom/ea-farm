# SPEC-067 — Memory / handle soak harness
Phase 0 · Owner: Codex · Depends on: **SPEC-001 §S1** ([review](../reviews/SPEC-001-soak-01.md)) · SPEC-016 ชั้น A

## 1. Goal

ปิดครึ่งที่ยังไม่มีของของ [`SPEC-001:160`](SPEC-001-mt5-executor.md) — *"รันทิ้ง 24 ชม. … **ไม่ memory leak**"*
วันนี้มีแค่ test heartbeat 1 ชม. · **ไม่มี sampler ไม่มีเกณฑ์ ไม่มีใครวัดหน่วยความจำเลยสักครั้ง**

เสร็จแล้วได้: harness ที่รัน EA ทิ้งไว้ เก็บ RSS/handle/thread เป็นระยะ แล้ว**ตัดสินด้วยความชัน**
ไม่ใช่ค่าสูงสุด · พร้อม artifact ที่ [SPEC-065](SPEC-065-mql5-test-harness.md) เอาไป attest ได้

## 2. Non-goals

- ❌ **ไม่ทำ profiler / ไม่หาว่ารั่วที่บรรทัดไหน** — ticket นี้ตอบแค่ "รั่วหรือไม่รั่ว" ถ้ารั่วค่อยเปิด ticket ไล่
- ❌ ไม่แตะ `Wire.mqh` เพื่อ "ลด memory" — ห้ามแก้ของที่ยังไม่มีหลักฐานว่าเป็นปัญหา
- ❌ ไม่รวมเข้า fast gate — soak ไม่มีวันอยู่ใน gate ที่รันทุก commit
- ❌ ไม่ทำ dashboard / กราฟ — artifact เป็น JSONL + verdict JSON พอ
- ❌ ไม่ครอบ Phase 1 ขึ้นไป (order flow · DB) — ticket นี้วัดเฉพาะ wire layer ที่มีอยู่จริงวันนี้

## 3. Interface

### 3.1 `tests/soak/soak_sampler.py`

```python
SAMPLE_INTERVAL_SEC = 30
WARMUP_SEC = {"steady": 3600, "churn": 600}   # rev.2 — ต่อ profile ดู §4.2

@dataclass(frozen=True)
class Sample:
    monotonic: float       # เวลาตั้งแต่เริ่มเก็บ
    wall_utc: str          # ISO-8601 Z — ใช้จับ gap ตอนเครื่อง sleep
    pid: int
    rss_bytes: int         # psutil memory_info().rss
    private_bytes: int     # psutil memory_info().private  ← ตัวตัดสิน ดู §4.1
    num_handles: int
    num_threads: int
    mql5_memory_used_mb: int | None   # จาก EA ดู §3.3 · None ถ้าอ่านไม่ได้ในรอบนั้น

@dataclass(frozen=True)
class Verdict:
    passed: bool
    reason: str                     # ว่างเมื่อผ่าน · ระบุกฎที่ตกเมื่อไม่ผ่าน
    private_slope_mb_per_hour: float
    private_growth_mb: float        # ตัวสุดท้าย − baseline
    handle_growth: int
    thread_growth: int
    samples_used: int
    gaps_detected: list[tuple[str, float]]   # (wall_utc, seconds) ที่ห่างเกิน §5.1

def collect(pid: int, duration_sec: float, out_path: Path) -> Path: ...
def analyse(samples: list[Sample]) -> Verdict: ...
def load_samples(path: Path) -> list[Sample]: ...
def linear_slope(xs: list[float], ys: list[float]) -> float: ...   # least squares · ต้อง unit-test
```

**`analyse()` ต้องเป็นฟังก์ชันบริสุทธิ์** — รับ list ของ `Sample` คืน `Verdict` ไม่แตะไฟล์ ไม่แตะ process
เพื่อให้ทดสอบด้วยชุดข้อมูลสังเคราะห์ได้ทั้งหมด (§7.1)

### 3.2 `tools/run-soak.ps1`

```
powershell -ExecutionPolicy Bypass -File tools\run-soak.ps1 -Profile steady   # 24 ชม.
powershell -ExecutionPolicy Bypass -File tools\run-soak.ps1 -Profile churn    # 2 ชม.
```

| exit | ความหมาย |
|------|----------|
| `0` | ผ่าน |
| `1` | ตกเกณฑ์ (มี verdict จริง) |
| `3` | **environment ไม่พร้อม** — ใช้กติกาเดียวกับ [work-order §P1](../work-order.md) |

### 3.3 ฝั่ง EA — ไม่เพิ่ม input ใหม่

ใช้ diag stream ที่มีอยู่แล้ว (`FARM_WIRE_DIAG_FILE`) เพิ่มบรรทัดชนิดใหม่ทุก **60 วินาที**:

```json
{"ev":"mem","ts":<utc_ms>,"mql5_used_mb":<int>,"heartbeat_seq":<int>}
```

ค่ามาจาก `MQL5InfoInteger(MQL5_MEMORY_USED)`
· ⚠️ **ห้ามเดาหน่วย** — รันจริงแล้ว**บันทึกหน่วยที่สังเกตได้ลง handoff** ก่อนใช้เป็นเกณฑ์
ถ้าค่าที่ได้ดูไม่สมเหตุสมผล ให้รายงานแทนที่จะปรับสูตรให้ดูดี

## 4. Behaviour

### 4.1 ตัววัดที่ใช้ตัดสิน

| ตัววัด | ใช้ทำอะไร | เหตุผล |
|--------|-----------|--------|
| **`private_bytes`** | ★ **ตัวตัดสินหลัก** | ไม่ถูกรบกวนจาก paging ของ OS · RSS ลดได้เองเมื่อเครื่องขาดแรมทั้งที่ยังรั่วอยู่ |
| `num_handles` | ★ **ตัดสินคู่กัน** | reconnect loop สร้าง socket — handle leak คือความเสี่ยงที่ตรงกับโค้ดจริงที่สุด |
| `rss_bytes` | บันทึกไว้ดูประกอบ | **ห้ามใช้ตัดสิน** |
| `num_threads` | ตัดสิน (เกณฑ์หลวม) | thread งอกคือสัญญาณของ resource ที่ไม่ถูกปิด |
| `mql5_memory_used_mb` | **วินิจฉัยเท่านั้น** | ใช้แยกว่า "EA รั่ว" หรือ "MT5 เองโต" — ดู §4.4 |

### 4.2 เกณฑ์ตัดสิน

ตัดช่วงเริ่มต้นทิ้ง (`WARMUP_SEC`) — MT5 โหลด history/สร้าง cache ตอนเริ่ม
ตัวเลขช่วงนั้นไม่ใช่ steady state · **baseline = ตัวอย่างแรกหลัง warmup**

> ### 🔴 rev.2 (2026-08-02) — warmup ต้องแยกตาม profile · ฉบับ rev.1 ผมเขียนผิดเอง
>
> rev.1 เขียน `WARMUP_SEC = 3600` เป็นค่าเดียวใช้ทั้งสอง profile **ซึ่งขัดกับ §4.3 ของตัวเอง**
>
> | | steady 24 ชม. | churn 2 ชม. |
> |---|---|---|
> | warmup 3600 คิดเป็น | 4% ของรอบ — ไม่มีผล | **50% ของรอบ** |
> | §4.3 บอกว่าสัญญาณโผล่เมื่อไร | ตามเวลา | **~25 นาที** ← **อยู่ในช่วงที่ถูกทิ้งทั้งหมด** |
>
> **หลักฐานจากการรันจริง 2026-08-02:** churn ถูกหยุดที่นาทีที่ 59.5 · เก็บได้ **120 sample**
> · `analyse()` โยน `SoakEnvironmentError("fewer than two samples after warmup")`
> — มีข้อมูลเกือบชั่วโมงแต่วิเคราะห์ไม่ได้เลยสักตัว
>
> **แก้:** `WARMUP_SEC` เป็น dict ต่อ profile · `churn = 600` (10 นาที)
> เพียงพอสำหรับ MT5 โหลด history ซึ่งใช้เวลาหลักนาที ไม่ใช่หลักชั่วโมง
> · `steady = 3600` คงเดิม เพราะไม่มีต้นทุน
>
> **`_post_warmup_samples()` ต้องรับ profile เป็นพารามิเตอร์** และ
> `analyse()` ต้องรับด้วย — ห้ามเดาจากความยาวของข้อมูลที่ได้รับ
> เพราะรอบที่ถูกตัดกลางคันจะเดาผิดเสมอ

| กฎ | เกณฑ์ | ตกแล้วหมายความว่า |
|----|-------|------------------|
| **M1** | `private_slope_mb_per_hour` ≤ **1.0** | โตต่อเนื่อง = รั่วจริง |
| **M2** | `private_growth_mb` ≤ **24** | กันกรณีโตเป็นขั้นบันไดที่ความชันเฉลี่ยยังต่ำ |
| **M3** | `handle_growth` ≤ **50** | handle leak |
| **M4** | `thread_growth` ≤ **4** | thread leak |
| **M5** | `samples_used` ≥ **90%** ของที่ควรได้ | เก็บตัวอย่างไม่ครบ = ผลเชื่อไม่ได้ ดู §5.1 |

**ต้องผ่านครบทั้ง 5** · ตกข้อเดียว = `passed: false` และ `reason` ต้องระบุว่าเป็นข้อไหนพร้อมตัวเลข

> **M1 กับ M2 ต้องมีคู่กัน อย่าตัดข้อใดข้อหนึ่งทิ้ง**
> M1 อย่างเดียวปล่อยการโตเป็นขั้นบันไดผ่าน (โต 20 MB ครั้งเดียวใน 24 ชม. → ความชันต่ำ)
> M2 อย่างเดียวปล่อยการรั่วช้าผ่าน (0.9 MB/ชม. = 21.6 MB ใน 24 ชม. → ไม่ถึง 24)
> **การรั่วที่แท้จริงจะตกอย่างน้อยหนึ่งข้อเสมอ**

### 4.3 สอง profile — และเหตุผลที่ churn ใช้แค่ 2 ชั่วโมง

| profile | เวลา | server ทำอะไร | จับอะไร |
|---------|------|---------------|---------|
| **`steady`** | **24 ชม.** | ตอบปกติตลอด | รั่วตามเวลา · ตอบ checkbox `SPEC-001:160` โดยตรง |
| **`churn`** | **2 ชม.** | **ตัด connection ทุก 30 วินาที** (~240 รอบ) | รั่วต่อ **เหตุการณ์ reconnect** |

★ **หลักคิดที่ทำให้ churn ไม่ต้องใช้ 24 ชม.:**

> การรั่วต่อเหตุการณ์ต้องการ **จำนวนเหตุการณ์** ไม่ใช่เวลาบนนาฬิกา

`steady` 24 ชม. เกิด reconnect ~0 ครั้ง · `churn` 2 ชม. เกิด **240 ครั้ง**
→ churn จับ socket-handle leak ได้ **ดีกว่า** steady ทั้งที่ใช้เวลา 1/12
· ถ้ารั่ว 1 handle ต่อ reconnect → M3 (>50) ตกภายใน ~25 นาที

**ทั้งสอง profile ต้องผ่านถึงจะปิด §1.7** — คนละความเสี่ยง แทนกันไม่ได้

### 4.4 แยกสาเหตุเมื่อตก — ห้ามสรุปว่า "EA รั่ว" ทันที

| `private_bytes` | `mql5_used_mb` | สรุป | ทำต่อ |
|---|---|---|---|
| โต | โต | **EA รั่วจริง** | ticket ไล่หาจุดรั่ว |
| โต | นิ่ง | **MT5 เองโต** ไม่ใช่ EA | ยัง**ตก** อยู่ (VPS ตายเหมือนกัน) แต่เป็นคนละ ticket → นโยบายรีสตาร์ต |
| นิ่ง | โต | ตัวเลขขัดกัน | **ห้ามเดา** — รายงานว่าเครื่องมือวัดเชื่อไม่ได้ |

`reason` ต้องระบุการจำแนกนี้ด้วย ไม่ใช่แค่บอกว่ากฎไหนตก

## 5. Edge cases

### 5.1 🔴 ต้องจับให้ได้ ไม่ใช่ปล่อยผ่านเงียบๆ

| # | เคส | ต้องทำ |
|---|-----|--------|
| 1 | **log ข้ามวันตอนเที่ยงคืน** — MT5 เขียน `MQL5\Logs\YYYYMMDD.log` แยกตามวัน · **การรัน 24 ชม. ข้ามเที่ยงคืนเสมอ** | `read_ea_log_since` ปัจจุบันจดตำแหน่งในไฟล์เดียว → หลังเที่ยงคืนจะ**อ่านไม่เจออะไรเลยและเงียบ** · ต้องตามไปไฟล์วันถัดไปเมื่อไฟล์เดิมหยุดโต |
| 2 | **เครื่อง sleep / hibernate** | `wall_utc` ห่างเกิน `2 × SAMPLE_INTERVAL` = บันทึกลง `gaps_detected` · ถ้ารวมเกิน 10% → **M5 ตก** ห้ามเติมค่าแทน |
| 3 | **PID เปลี่ยน** (MT5 auto-update · crash แล้วขึ้นใหม่) | **ยกเลิกรอบทันที** `exit 3` — ไม่ใช่ตกเกณฑ์ แต่คือรอบที่ใช้ไม่ได้ · ห้ามต่อ sample ข้าม PID |
| 4 | **ตลาดเปิดกลางรอบ** (อาทิตย์เย็น) | บันทึก `market_open` ต่อ sample · ถ้ารอบคร่อมช่วงเปิด ให้เขียนกำกับใน verdict — **ห้ามใช้เป็นข้ออ้างตอนตก** ถ้าไม่ได้บันทึกไว้ก่อน |
| 5 | **psutil ไม่มี** | **`exit 3` พร้อมข้อความติดตั้ง** · ห้าม fallback ไปวิธีที่แม่นน้อยกว่าเงียบๆ — เครื่องมือวัดที่ degrade เองคือที่มาของความมั่นใจผิดๆ |
| 6 | terminal ตายกลางรอบ | `exit 1` + `reason` บอกเวลาที่ตาย + 50 บรรทัดท้ายของ EA log |
| 7 | **DST / นาฬิกาถอยหลังกลางรอบ** | ใช้ `time.monotonic()` เป็นแกนวิเคราะห์เสมอ · `wall_utc` ใช้แค่รายงานและจับ gap |

### 5.2 🟠 รู้ไว้ ไม่ถึงกับบล็อก

| # | เคส | หมายเหตุ |
|---|-----|---------|
| 8 | **diag file โตต่อเนื่อง ไม่มี rotation** | วัดจริง 2026-07-31: **9,564 byte/60s → ~13.1 MB ใน 24 ชม.** · ดิสก์ว่าง 116 GB **ไม่ใช่ปัญหาสำหรับ 24 ชม.** · แต่ต้อง**บันทึกขนาดสุดท้ายลง verdict** เพราะ soak ที่ยาวกว่านี้หรือ verbose ที่ดังกว่านี้จะเปลี่ยนคำตอบ |
| 9 | `GetTickCount()` wrap ทุก ~49.7 วัน | ไม่ถึงใน 24 ชม. · แต่**ห้ามเขียนโค้ดที่พังถ้ารันยาวกว่านี้** ([SPEC-001-soak-01 §S1](../reviews/SPEC-001-soak-01.md)) |
| 10 | `m_heartbeat_seq` ใน 24 ชม. = 43,200 | `int` รับไหว ไม่ต้องแก้ |

## 6. Acceptance criteria

- [ ] `tools\run-soak.ps1 -Profile churn` รันจบ **ผ่าน M1–M5** พร้อม artifact
- [ ] `tools\run-soak.ps1 -Profile steady` รันจบ 24 ชม. **ผ่าน M1–M5** พร้อม artifact
- [ ] `analyse()` เป็นฟังก์ชันบริสุทธิ์ — test ทั้งหมดใน §7.1 รันได้**โดยไม่ต้องมี MT5**
- [ ] ป้อนชุดข้อมูลที่รั่วจริงเข้า `analyse()` แล้ว **ต้องตก** (§7.1) — พิสูจน์ว่าเกณฑ์จับของได้จริง
- [ ] preflight ครบตาม [§P1 ชั้น A](../work-order.md) · env ไม่พร้อม → **`exit 3` ไม่ใช่ `exit 1`**
- [ ] artifact บันทึก **`git_sha_head` และ `git_sha_result` แยกกัน** (บทเรียน N1 จาก [SPEC-063-04](../reviews/SPEC-063-04.md))
- [ ] log ข้ามเที่ยงคืนแล้วยังอ่าน EA log ต่อได้ — **พิสูจน์ด้วย test ไม่ใช่คำยืนยัน** (§7.1)
- [ ] `verdict.json` อ่านแล้วเข้าใจได้โดยไม่ต้องเปิดโค้ด: ผ่าน/ตก · กฎไหน · ตัวเลขจริง · การจำแนก §4.4
- [ ] handoff บันทึก **หน่วยจริงของ `MQL5_MEMORY_USED`** ที่สังเกตได้
- [ ] มี **timeout รวม + เก็บกวาด process ลูก** แม้ถูก kill (บทเรียน T9) — `steady` cap ที่ 25 ชม.

## 7. Test list

### 7.1 ไม่ต้องมี MT5 — `tests/soak/test_soak_analysis.py`

| test | ตรวจอะไร |
|------|----------|
| `test_flat_series_passes` | ข้อมูลนิ่ง + noise ±2 MB → ผ่าน |
| `test_linear_leak_2mb_per_hour_fails_m1` | รั่วเชิงเส้น 2 MB/ชม. → **ตก M1** |
| `test_step_growth_30mb_fails_m2_not_m1` | โตขั้นบันไดครั้งเดียว 30 MB → **ตก M2 แต่ไม่ตก M1** ← พิสูจน์ว่าสองกฎทำงานคนละแบบ |
| `test_slow_leak_0_9mb_per_hour_fails_m2` | 0.9 MB/ชม. → ผ่าน M1 แต่ **ตก M2** ← อีกทิศของคู่เดียวกัน |
| `test_handle_leak_one_per_reconnect_fails_m3` | +1 handle ต่อรอบ × 240 → ตก M3 |
| `test_warmup_hour_excluded_from_baseline` | ใส่ spike ใหญ่ในช่วง warmup → ต้องไม่กระทบ verdict |
| `test_warmup_differs_per_profile` | **rev.2** — ข้อมูล 2 ชม. แบบ `churn` ต้องวิเคราะห์ได้ · ข้อมูลชุดเดียวกันแบบ `steady` ต้องบอกว่าสั้นเกินไป |
| `test_churn_60min_run_is_analysable` | **rev.2** — ป้องกันเคสที่เพิ่งเจอจริง: 120 sample ใน 59.5 นาที ต้องไม่โยน `fewer than two samples after warmup` |
| `test_sleep_gap_20pct_fails_m5` | เจาะช่องว่าง 20% → ตก M5 · **ห้ามผ่านด้วยการ interpolate** |
| `test_pid_change_is_env_failure_not_verdict` | PID เปลี่ยน → env failure ไม่ใช่ `passed: false` |
| `test_linear_slope_matches_known_series` | ป้อนเส้นที่รู้ความชัน → คลาดเคลื่อน < 1% |
| `test_ea_log_reader_follows_midnight_rollover` | สร้าง `20260731.log` + `20260801.log` → อ่านต่อเนื่องครบ (§5.1 ข้อ 1) |

★ **4 ตัวแรกคือหัวใจ** — เกณฑ์ที่ไม่เคยถูกพิสูจน์ว่า "ตกได้" คือเกณฑ์ที่ไม่มีค่า
เป็นบทเรียนตรงจาก [chaos รอบ 3 §N1](../reviews/SPEC-016-chaos-03.md) (assertion ที่ล้มไม่ได้)

### 7.2 ต้องมี MT5

| test | เวลา |
|------|------|
| `test_soak_churn_2h_no_handle_leak` | 2 ชม. |
| `test_soak_steady_24h_no_memory_leak` | 24 ชม. · `@skipUnless` แยก env จาก slow gate เดิม |

## 8. Files to touch / NOT to touch

| | |
|---|---|
| **สร้างใหม่** | `tests/soak/soak_sampler.py` · `tests/soak/test_soak_analysis.py` · `tests/soak/test_memory_soak.py` · `tools/run-soak.ps1` |
| **แก้ได้** | `tests/chaos/live_mt5_harness.py` — **เพิ่ม** midnight rollover ใน log reader + export `live_terminal` ให้ soak ใช้ซ้ำ · `Wire.mqh` เฉพาะบรรทัด `{"ev":"mem"...}` (§3.3) |
| **ห้ามแตะ** | `contracts/schema/**` · `BrokerTime.mqh` · ตรรกะ heartbeat (เป็นของ [S1](../reviews/SPEC-001-soak-01.md) คนละ ticket — **ห้ามรวมแก้**) |
| **ห้ามทำ** | ห้ามลด `SAMPLE_INTERVAL` เพื่อให้ได้ตัวอย่างเยอะขึ้นจนกวน process ที่กำลังวัด · ห้ามผ่อน M1–M5 เพื่อให้รอบแรกผ่าน |

## 9. Open questions

**ไม่มีข้อที่บล็อก** — เริ่มได้ทันทีหลัง S1 merge

### สิ่งที่ต้องรายงานกลับ ไม่ใช่คำถามที่ต้องรอคำตอบ

| # | เรื่อง | ทำอย่างไร |
|---|-------|-----------|
| 1 | **M1–M5 เป็นตัวเลขที่ยังไม่มี baseline** | ตั้งจากการประมาณ ไม่ใช่จากการวัด · **รอบแรกให้รายงานค่าจริงที่วัดได้ทุกตัวมาด้วย** ถ้าเกณฑ์หลวมหรือแคบเกินจนไม่มีประโยชน์ Claude จะแก้ spec ตามข้อมูล — **ห้าม Codex ปรับเกณฑ์เอง** |
| 2 | หน่วยของ `MQL5_MEMORY_USED` | รันแล้วบันทึก (§3.3) |
| 3 | `churn` 30 วินาที/รอบ ชนกับ backoff ladder (1,2,4,…,30) ไหม | ถ้า EA เข้า backoff ยาวจนได้ไม่ถึง 240 รอบใน 2 ชม. → **รายงานจำนวนรอบจริง** แล้ว Claude จะปรับคาบหรือยืดเวลา · อย่าแก้เกณฑ์ M3 แทน |

> ⚠️ **ห้ามเริ่ม `steady` 24 ชม. ก่อน [S1](../reviews/SPEC-001-soak-01.md) จะ merge**
> soak บนโค้ดที่รู้อยู่แล้วว่า cadence ผิด = ใช้เวลา 24 ชม.เพื่อวัดของที่กำลังจะถูกเปลี่ยน
> · `churn` 2 ชม. รันก่อนได้ เพราะ handle leak ไม่ขึ้นกับ cadence
