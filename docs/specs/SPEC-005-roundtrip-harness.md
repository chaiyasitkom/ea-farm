# SPEC-005 — Round-trip harness: Python ↔ MQL5

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-002, SPEC-004 · **Blocks:** Phase 0 exit criteria
**อ้าง:** [04-roadmap Phase 0](../04-roadmap.md) exit · [02-contracts §6](../02-contracts.md)

---

## 1. Goal

พิสูจน์ว่า **model ที่ generate ออกมาสองฝั่งเข้าใจ message เดียวกันจริง** ไม่ใช่แค่คอมไพล์ผ่าน

> "ทั้งสองฝั่ง compile ได้" ≠ "ทั้งสองฝั่งเข้าใจตรงกัน"
> ตัวที่พิสูจน์ข้อหลังได้มีแต่การส่งข้อมูลจริงข้ามภาษาแล้ววนกลับมาเทียบ

## 2. Non-goals

- ❌ ห้ามใช้ socket — ticket นี้ทดสอบ **serialization ล้วน** ไม่ใช่ transport
      (transport คือ SPEC-001 · chaos คือ SPEC-016)
- ❌ ห้ามทดสอบ business invariant (`low <= open <= high` ฯลฯ) — คนละเรื่อง ทำใน ticket ที่เป็นเจ้าของกฎ
- ❌ ห้ามทดสอบซ้ำสิ่งที่ SPEC-004 ทำแล้ว (round-trip **ภายในภาษาเดียว**)
- ❌ ห้ามแก้ `contracts/schema/**` · `contracts/gen/**` (generated)
- ❌ **ห้ามทำทิศ MQL5→Python แยกต่างหาก** — เหตุผลใน §4.5

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `tests/mql5/TestRoundTrip.mq5` | EA — อ่าน input, parse, serialize, เขียน output |
| `tests/test_roundtrip.py` | driver ฝั่ง Python (`@pytest.mark.mql5`) |
| `tools/run-mql5-tests.ps1` | **แก้** — เพิ่ม suite (ลงหัวข้อ `gate changes`) |

### 3.2 ช่องทางส่งข้อมูล — ไฟล์ใน `Common\Files` ไม่ใช่ socket

ใช้ pattern เดียวกับ harness ที่พิสูจน์แล้ว (`FILE_BIN | FILE_COMMON`)

```
Python  ──เขียน──►  Common\Files\ea-farm-rt-in-<n>.json
                          │
                    [Strategy Tester รัน TestRoundTrip.mq5]
                          │
Python  ◄──อ่าน───  Common\Files\ea-farm-rt-out-<n>.json
                    Common\Files\ea-farm-rt-result.json   (status/ran_names/git_sha)
```

**ทำไมใช้ Strategy Tester ไม่ใช่ live chart:** ticket นี้ต้องการ **determinism**
ไม่ต้องการเวลาจริง · tester รันซ้ำได้ผลเดิมเป๊ะ และเร็วกว่า
(ตรงข้ามกับ chaos suite ที่ต้องใช้ live chart เพราะวัดเวลาจริง — [work-order §1.5](../work-order.md))

### 3.3 Manifest — EA ต้องไม่ hardcode รายชื่อไฟล์

Python เขียน `ea-farm-rt-manifest.json` ก่อนรัน:

```json
{
  "cases": [
    { "id": 1, "type": "HELLO",  "in": "ea-farm-rt-in-1.json",  "out": "ea-farm-rt-out-1.json" },
    { "id": 2, "type": "STATE",  "in": "ea-farm-rt-in-2.json",  "out": "ea-farm-rt-out-2.json" }
  ]
}
```

EA วนตาม manifest · **1 tester run ต่อ 1 ชุด case ทั้งหมด** ห้ามรัน tester ต่อ 1 fixture
(tester run ละ ~30 วินาที — ถ้ารันต่อ fixture จะกลายเป็น 10+ นาที แล้วไม่มีใครรัน)

### 3.4 ★ การอ่านไฟล์ใน MQL5 — ยังไม่เคยทำในโปรเจกต์นี้

harness เดิม**เขียน**อย่างเดียว การ**อ่าน** UTF-8 เป็นของใหม่และมีกับดัก:

```mql5
// ❌ ผิด — FILE_TXT จะตีความตาม codepage ของเครื่อง อักษรไทยเพี้ยน
FileOpen(name, FILE_READ | FILE_TXT | FILE_COMMON);

// ✅ ถูก — อ่าน raw byte แล้วแปลงด้วย CP_UTF8 เอง
const int h = FileOpen(name, FILE_READ | FILE_BIN | FILE_COMMON);
uchar bytes[];
const int n = (int)FileReadArray(h, bytes, 0, (int)FileSize(h));
FileClose(h);
const string json = CharArrayToString(bytes, 0, n, CP_UTF8);
```

เป็นบทเรียนเดียวกับ [compile-gate-02 §1](../reviews/SPEC-001-compile-gate-02.md)
แต่กลับด้าน — **ต้องระวังทั้งขาอ่านและขาเขียน**

---

## 4. Behaviour

### 4.1 ★ ท่อ round-trip และนิยามของ "ตรงกัน"

```
fixture.json                                    (ไฟล์ต้นทาง)
   │
   ├─ py:  model  = Model.model_validate_json(fixture)
   ├─ py:  A      = canonical_json(model)       ← รูปแบบมาตรฐานฝั่ง Python
   │
   │       [เขียน A → Common\Files]
   ├─ mql5: st    = FarmParseXxx(A)
   ├─ mql5: B     = FarmSerializeXxx(st)
   │       [อ่าน B ← Common\Files]
   │
   ├─ py:  model2 = Model.model_validate_json(B)
   └─ py:  A2     = canonical_json(model2)

assert model2 == model      ①  semantic
assert A2 == A              ②  ★ byte-identical หลัง normalize ฝั่ง Python
assert no_sci_notation(B)   ③  ตรวจ B ดิบๆ
```

**`canonical_json` = `model_dump_json()` ที่ sort key + ไม่มีช่องว่างพิเศษ**

| assert | จับอะไร |
|--------|---------|
| ① | MQL5 ทำข้อมูล**หาย**หรือ**เพี้ยน** |
| ② | ตัวที่แรงที่สุด — ถ้า MQL5 ตกฟิลด์เดียวหรือปัดเลขผิด A2 จะต่างจาก A ทันที |
| ③ | ต้องตรวจ **B ดิบ** เพราะ normalize ผ่าน Python จะ**กลบ** `1e-05` ได้ |

**ทำไมไม่เทียบ `B == A` ตรงๆ:** MQL5 เรียงคีย์ต่างหรือเขียน `1.0` แทน `1` ได้
ซึ่ง**ไม่ใช่การละเมิด contract** · normalize ผ่าน Python ตัดความต่างเชิงรูปแบบทิ้ง
แต่เก็บความต่างเชิงความหมายไว้ — ③ จึงมีไว้ดักสิ่งที่ normalize กลบ

### 4.2 ตัวเลขทศนิยม — จุดที่พังบ่อยที่สุด

| เคส | ต้องรอด |
|-----|---------|
| `"point": 0.00001` | ต้องออกมาเป็น `0.00001` **ไม่ใช่ `1e-05`** |
| `"open": 1.08234` | ต้องไม่กลายเป็น `1.08234000` หรือ `1.0823` |
| `"contract_size": 100000` | รูปแบบจะเป็น `100000` หรือ `100000.0` ก็ได้ **แต่ต้องคงที่** |
| `"ticket": 9007199254740993` | ★ เกิน 2⁵³ — ต้องผ่าน `IntegerToString` ห้ามผ่าน `double` |
| `"profit": -0.0` | ต้องไม่กลายเป็น `0.0` แล้วเปลี่ยนความหมาย |

**ต้องมี fixture ที่มีเลขเหล่านี้จริง** ไม่ใช่แค่เลขกลมๆ

### 4.3 3 สถานะ `null` / มีค่า / ไม่มีคีย์ — ต้องรอดครบ

MQL5 เก็บเป็น `x` + `x_is_null` + `x_present` ([SPEC-004 §4.2](SPEC-004-codegen.md))
round-trip คือตัวที่พิสูจน์ว่ากลไกนี้ทำงานจริง

| input | ต้องได้กลับ |
|-------|------------|
| `"sl": 1.08010` | `"sl": 1.08010` |
| `"sl": null` | `"sl": null` — **ไม่ใช่ `0` และไม่ใช่หายไป** |
| ไม่มีคีย์ `sl` (optional) | ไม่มีคีย์ `sl` — **ไม่ใช่ `null`** |

ถ้าสามสถานะนี้ยุบเหลือสอง จะเห็นตอนนี้ **ก่อน**ที่ SPEC-010 จะส่ง STATE จริง

### 4.4 ★ forward-compat: unknown field **ต้องหาย ไม่ใช่ต้องรอด**

จุดนี้กลับด้านจากสัญชาตญาณ — เขียนไว้กันเข้าใจผิด

`extra="ignore"` ทำให้ **pydantic ทิ้ง unknown field ตั้งแต่ขั้น `model_validate_json`**
→ `A` ไม่มี field แปลกปลอมอยู่แล้ว → **fixture `.extra.json` ไม่ได้ทดสอบ MQL5 เลย**

**ต้องทำแบบนี้แทน:** สร้าง `A` ตามปกติ แล้ว **ฉีด** field แปลกปลอมเข้าไปใน `A`
ก่อนส่งให้ MQL5:

```
A_injected = inject_unknown_field(A, "__probe_unknown__", 12345)
   → MQL5 parse ต้อง "ผ่าน"  (ไม่ error)
   → B ต้อง "ไม่มี" __probe_unknown__
   → A2 == A   (ไม่ใช่ == A_injected)
```

**การที่ field แปลกปลอมหายไปคือผลลัพธ์ที่ถูกต้อง** ตาม [§7 forward compat](../02-contracts.md)
· ถ้า test แดงเพราะ field หาย = เข้าใจ test ผิด **ห้ามไป "แก้" ให้มันรอด**

ต้องทดสอบทั้ง 3 ตำแหน่ง: ระดับ envelope · ระดับ payload · **ใน object ที่ซ้อนอยู่**
(`state.positions[0]`) — ตัวหลังคือตัวที่ parser แบบ `StringFind` จะพัง

### 4.5 ทำไม**ไม่ต้อง**ทำทิศ MQL5 → Python แยก

ดูท่อใน §4.1 อีกครั้ง: `B` คือ**ผลผลิตของ MQL5** และ Python เป็นคน parse มัน
→ **"MQL5 เขียนแล้ว Python อ่านได้" ถูกพิสูจน์อยู่แล้วในทิศเดียว**

ที่ทิศเดียวไม่ครอบคลุมคือ "MQL5 สร้าง payload จากข้อมูล runtime ของตัวเอง"
(เช่น STATE ที่สร้างจาก `PositionGetDouble()` จริง) — **นั่นเป็นงานของ SPEC-010**
ไม่ใช่ของ ticket นี้

**อย่าสร้าง tester run รอบที่สองเพื่อทิศกลับ** — ได้ความมั่นใจเพิ่มน้อยมากแลกกับเวลารันสองเท่า

### 4.6 ต้องครอบทุก message type

12 type ใน `envelope.type` × 2 รูปแบบ:

| รูปแบบ | ที่มา |
|--------|-------|
| `<type>.valid.json` | ครบทุก field |
| `<type>.valid.min.json` | เฉพาะ `required` |

fixture มาจาก [SPEC-004 §3.6](SPEC-004-codegen.md) — **ใช้ของเดิม ห้ามสร้างชุดใหม่**
ถ้าขาดตัวไหน = SPEC-004 ยังไม่เสร็จ ให้กลับไปเติมที่นั่น

**24 case ขั้นต่ำ** + case พิเศษใน §4.2/§4.4

### 4.7 Determinism

รัน harness 2 ครั้งติดกัน → ไฟล์ `out-*.json` ทุกตัว **byte-identical**
ถ้าไม่ตรง = มีอะไรใน serializer ที่ขึ้นกับสถานะภายนอก (เวลา · ลำดับ hash · หน่วยความจำ)

---

## 5. Edge cases

1. **`ea-farm-rt-out-<n>.json` ค้างจากรอบก่อน** — Python ต้อง **ลบ output เก่าทิ้งก่อนรัน**
   ไม่งั้นถ้า EA ไม่ทำงานเลย จะอ่านผลเก่ามาแล้วผ่านแบบผิดๆ ← **กับดักร้ายแรงที่สุดใน ticket นี้**
2. **EA ประมวลผลไม่ครบทุก case** — `result.json` ต้องมี `cases_processed` เทียบกับ manifest
   ขาดแม้แต่ตัวเดียว = FAIL
3. **`git_sha` ไม่ตรง HEAD** — ผลเก่า ต้อง FAIL (harness เดิมมีกลไกนี้แล้ว ใช้ซ้ำ)
4. **ไฟล์ input ใหญ่เกิน** — STATE 64 position ~ใกล้ 64 KB · `FileSize()` ต้องเช็คก่อน `ArrayResize`
5. **BOM** — Python ต้องเขียน UTF-8 **ไม่มี BOM** (`encoding="utf-8"` ไม่ใช่ `utf-8-sig`)
   ถ้ามี BOM ตัวอักษรแรกที่ MQL5 เห็นจะเป็น `﻿` แล้ว parse พังแบบงงๆ
6. **อักษรไทยใน `comment`** — ต้องรอดทั้งไป-กลับ (`CP_UTF8` ทั้งอ่านและเขียน)
7. **ไฟล์ว่าง / JSON พัง** — EA ต้องบันทึกเป็น case ที่ fail **ไม่ใช่ crash ทั้ง suite**
8. **`Common\Files` ไม่มีสิทธิ์เขียน** — รายงานให้ชัด ไม่ใช่ fail เงียบ
9. **manifest ชี้ไฟล์ที่ไม่มี** — fail case นั้นพร้อมชื่อไฟล์ ไม่ใช่ข้าม

---

## 6. Acceptance criteria

- [ ] `TestRoundTrip.mq5` compile 0 error 0 warning
- [ ] `python tools/task.py test-all` รัน round-trip ได้ (marker `mql5`)
- [ ] **ครบ 12 type × 2 รูปแบบ = 24 case ขั้นต่ำ** ผ่านหมด
- [ ] `cases_processed` ใน `result.json` **เท่ากับ** จำนวนใน manifest
- [ ] `git_sha` ตรง HEAD
- [ ] Python **ลบ output เก่าก่อนรันทุกครั้ง** — พิสูจน์: ลบ EA ออกแล้วรัน ต้อง **FAIL**
      ไม่ใช่ผ่านด้วยผลเก่า (edge 1)
- [ ] `A2 == A` ทุก case (assert ②)
- [ ] `B` ไม่มี `e`/`E` ในตัวเลขเลยสักตัว (assert ③)
- [ ] `null` / มีค่า / ไม่มีคีย์ **รอดครบ 3 สถานะ**
- [ ] unknown field ที่ฉีดเข้าไป **หายไปใน B** ทั้ง 3 ตำแหน่ง (envelope · payload · nested)
- [ ] `ticket` เกิน 2⁵³ รอด
- [ ] `comment` ภาษาไทยรอดทั้งไป-กลับ
- [ ] รัน 2 ครั้งติดกัน → `out-*.json` byte-identical ทุกไฟล์
- [ ] `grep -rn "FILE_TXT" tests/mql5/TestRoundTrip.mq5` — **ไม่เจอ** (ต้องใช้ `FILE_BIN`)

## 7. Test list — `tests/test_roundtrip.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_roundtrip_all_types_full` | 12 type ฉบับเต็ม |
| 2 | `test_roundtrip_all_types_minimal` | 12 type เฉพาะ required |
| 3 | `test_canonical_json_identical_after_roundtrip` | ★ assert ② |
| 4 | `test_no_scientific_notation_in_mql5_output` | assert ③ |
| 5 | `test_null_value_absent_three_states_survive` | ★ §4.3 |
| 6 | `test_unknown_field_dropped_at_envelope` | §4.4 |
| 7 | `test_unknown_field_dropped_in_payload` | §4.4 |
| 8 | `test_unknown_field_dropped_in_nested_object` | ★ ตัวที่ parser แบบ `StringFind` จะพัง |
| 9 | `test_large_int64_ticket_survives` | §4.2 |
| 10 | `test_small_float_point_not_sci_notation` | `0.00001` |
| 11 | `test_thai_comment_survives_both_ways` | UTF-8 |
| 12 | `test_negative_zero_preserved` | §4.2 |
| 13 | `test_stale_output_detected_when_ea_missing` | ★★ edge 1 — **test ที่ปกป้อง test อื่นทั้งหมด** |
| 14 | `test_all_manifest_cases_processed` | edge 2 |
| 15 | `test_git_sha_matches_head` | edge 3 |
| 16 | `test_deterministic_across_two_runs` | §4.7 |
| 17 | `test_malformed_input_fails_case_not_suite` | edge 7 |

**test 13 สำคัญที่สุด** — ถ้ากลไกกันผลค้างพัง test อื่นทั้ง 16 ตัวจะ "ผ่าน" โดยไม่ได้รันอะไรเลย

## 8. Files

**Touch:** `tests/mql5/TestRoundTrip.mq5` · `tests/test_roundtrip.py` · `tools/run-mql5-tests.ps1`

**ห้ามแตะ:** `contracts/**` (schema และ gen) · `docs/**` · `AGENTS.md` · `CLAUDE.md`
· `tests/mql5/TestWire.mq5` · `tests/mql5/TestFarmMessages.mq5` (ของ SPEC-004)

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `canonical_json` ใช้ `model_dump_json()` ของ pydantic ตรงๆ หรือเขียนเอง? | **ไม่บล็อก** — ใช้ของ pydantic + `sort_keys` ถ้าทำได้ · ขอแค่ **deterministic และใช้ตัวเดียวกันทั้ง A และ A2** · รายงานว่าเลือกอะไร |
| Q2 | ถ้า MQL5 เขียน `100000.0` แต่ Python เขียน `100000` — นับว่าตรงไหม? | **ไม่บล็อก — ตอบแล้ว: ตรง** เพราะ assert ② เทียบหลัง normalize ผ่าน Python แล้ว · แต่รูปแบบที่ MQL5 เลือกต้อง **คงที่** (§4.7 จับได้) |
| Q3 | tester run ใช้ symbol/ช่วงวันไหน? | **ไม่บล็อก** — ใช้ค่าเดียวกับ `TestWire` (`EURUSD.iux` · 2026.06.02–06.19) · ticket นี้ไม่แตะราคาเลย ค่าอะไรก็ได้ที่ tester ยอมสตาร์ท |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ SPEC-004 merge**

---

## ภาคผนวก — ทำไม test 13 ถึงสำคัญกว่าทุกตัว

harness แบบนี้มี failure mode ที่อันตรายเป็นพิเศษ: **EA ไม่ได้รันเลย แต่ test เขียว**
เพราะไฟล์ `out-*.json` จากรอบก่อนยังอยู่ใน `Common\Files`

อาการคือ *"round-trip ผ่านหมดมาตลอด"* ทั้งที่ codegen อาจพังไปแล้วหลายวัน
และจะไปโผล่ตอน SPEC-010 ส่ง STATE จริงแล้ว gateway อ่านไม่ออก — ห่างจากต้นเหตุมาก

กลไกกัน 3 ชั้น ต้องมีครบ:
1. ลบ output เก่าก่อนรัน
2. `cases_processed` เทียบ manifest
3. `git_sha` เทียบ HEAD

ชั้นที่ 3 มีอยู่แล้วใน harness เดิม — **ชั้น 1 กับ 2 เป็นของใหม่ที่ ticket นี้ต้องเพิ่ม**
