# SPEC-018 — DB ↔ MT5 history consistency checker

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-014, SPEC-064 · **Blocks:** Phase 1 exit criteria
**อ้าง:** [roadmap Phase 1](../04-roadmap.md) exit — *"`intents` + `exec_reports` ใน DB ตรงกับ history ใน MT5 100%"*

---

## 1. Goal

เทียบบันทึกของเรากับบันทึกของโบรกเกอร์ แล้วบอกได้ว่า**ตรงกันจริงไหม**

งานที่สำคัญที่สุดของเครื่องมือนี้คือ **หา order ที่เกิดขึ้นจริงแต่เราไม่รู้** —
ไม่ใช่การยืนยันว่าทุกอย่างเรียบร้อย

## 2. Non-goals

- ❌ **ห้ามแก้ข้อมูลทั้งสองฝั่ง** — read-only ทั้งหมด (หลักเดียวกับ [SPEC-008 §4.1](SPEC-008-data-quality-gate.md))
- ❌ ห้ามปิด position / ส่ง order เพื่อ "แก้ให้ตรง"
- ❌ ห้าม alert เอง (SPEC-029) — ให้ exit code + รายงาน
- ❌ ห้ามตรวจข้อมูลราคา (SPEC-008 ทำแล้ว) — ticket นี้ตรวจ **การซื้อขาย**
- ❌ ห้ามแตะ `contracts/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `ops/consistency/mt5_history.py` | ดึง deal/order จาก MT5 |
| `ops/consistency/checker.py` | เทียบ + จัดหมวดความไม่ตรง |
| `ops/consistency/report.py` | JSON + สรุปให้คนอ่าน |
| `ops/consistency/__main__.py` | CLI |
| `tools/task.py` | **แก้** — เพิ่ม `consistency` |
| `tests/test_consistency.py` | §7 |

### 3.2 CLI

```
python -m ops.consistency --days 7
python -m ops.consistency --from 2026-07-01 --to 2026-07-28
python -m ops.consistency --days 7 --fail-on critical    # exit 1 ถ้ามี CRITICAL
```

---

## 4. Behaviour

### 4.1 ★★ จับคู่ด้วย **ticket** ไม่ใช่ด้วยเวลา

MT5 คืนเวลา deal เป็น **เวลา broker** · DB เก็บ **UTC**
→ ถ้าจับคู่ด้วยเวลาจะต้องแปลง ซึ่งชนปัญหา [D15](../backlog.md) (offset ในอดีตไม่รู้)
และถ้ามี DST เปลี่ยนในช่วงที่ตรวจ **ทุกอย่างจะดูไม่ตรงพร้อมกันทั้งหมด**

**ticket เป็นเลขที่โบรกเกอร์ออกให้ ไม่ขึ้นกับ timezone** → ใช้เป็นกุญแจหลัก

เวลาใช้เป็น**ตัวกรองหยาบเท่านั้น** และต้อง **pad ±2 ชั่วโมง** ที่ขอบช่วง
เพื่อกันไม่ให้ deal ที่อยู่ริมขอบหลุดออกไปเพราะ offset

> ⚠️ **ต้องบันทึกใน handoff:** `exec_reports.ticket` ที่ EA รายงาน คือ **order ticket**
> หรือ **position ticket** — และ MT5 `history_deals_get` ให้ field ไหนที่ตรงกัน
> ตรวจกับข้อมูลจริงแล้วเขียนไว้ · ผิดตรงนี้ = จับคู่ไม่ได้เลยทั้งชุด

### 4.2 ★★ สิ่งที่ต้องหาให้เจอ เรียงตามความร้ายแรง

| # | เจออะไร | หมายความว่า | ระดับ |
|---|---------|-------------|-------|
| C1 | **deal ใน MT5 (magic ของเรา) ที่ไม่มี `exec_report`** | ★ **มี order เกิดขึ้นจริงโดยเราไม่รู้** | 🔴 CRITICAL |
| C2 | `exec_report result=FILLED` ที่ไม่มี deal | เรารายงานว่า fill แต่โบรกเกอร์ไม่มีบันทึก | 🔴 CRITICAL |
| C3 | **position ปัจจุบันใน MT5 ≠ `owned_net` ใน STATE ล่าสุด** | ภาพในหัว brain ไม่ตรงความจริง | 🔴 CRITICAL |
| C4 | `intents.ack_status=ACCEPTED` แต่ไม่มีทั้ง `exec_report` และ deal | intent หายระหว่างทาง | 🔴 CRITICAL |
| C5 | volume รวมต่อ intent ไม่ตรงกับ deal | | 🟠 WARN |
| C6 | `price_filled` ต่างจาก deal เกิน 1 point | | 🟠 WARN |
| C7 | `commission` ต่างเกิน 0.01 | | 🟠 WARN |
| C8 | deal ที่ magic ไม่ใช่ของเรา | ไม้ foreign (R19) — **ปกติ ไม่ใช่ error** | 🟡 INFO |
| C9 | deal ก่อนวันที่ระบบเริ่มทำงาน | นอกขอบเขต | 🟡 INFO |

### 4.3 ★ C1 คือเหตุผลทั้งหมดที่ ticket นี้มีอยู่

[SPEC-003 handoff](../reviews/SPEC-003-schema-handoff.md) เขียนไว้แล้วว่า
`exec_report.result = TIMEOUT` **ไม่ได้แปลว่า order ไม่เข้า** —
order อาจเข้าไปแล้วแต่ตอบกลับไม่ทัน

ตอนนั้นเรามีแต่คำเตือน · **ticket นี้คือเครื่องมือที่ทำให้คำเตือนนั้นตรวจได้จริง**

```
EA ส่ง order → โบรกเกอร์ทำสำเร็จ → เน็ตขาดก่อนตอบกลับ
  → EA รายงาน TIMEOUT ticket=null
  → เราไม่รู้ว่ามี position
  → brain คิดว่า flat แล้วสั่งเปิดใหม่ = สองเท่า
```

**C1 คือสิ่งเดียวที่จับเคสนี้ได้** — และมันจะไม่โผล่ใน log ที่ไหนเลย

### 4.4 C3 — เทียบ position ปัจจุบัน

```
MT5:  วน PositionsTotal() เลือกที่ magic + symbol ตรง → net
DB :  account_state แถวล่าสุดของ session นั้น → owned_net
```

ต่างกัน = **ไม่ใช่แค่รายงานผิด แต่แปลว่าเราไม่รู้ว่าถืออะไรอยู่**

⚠️ ต้องเทียบตอนที่ **ไม่มี order ค้างอยู่** — ถ้าเทียบระหว่างที่ EA กำลังส่ง order
จะเจอความต่างชั่วคราวที่ไม่ใช่ปัญหา
→ ถ้า `account_state` แถวล่าสุด**เก่ากว่า 30 วินาที** ให้ข้าม C3 + WARN ว่าข้ามเพราะอะไร

### 4.5 Partial fill — 1 intent ต่อได้หลาย deal

flip 2 จังหวะ ([ADR-001 §6](../decisions/ADR-001-hedging-account.md)) และ partial fill
ทำให้ intent เดียวมีหลาย deal → **ต้องรวมก่อนเทียบ ห้ามเทียบทีละใบ**

```
Σ volume ของ deal ที่ผูกกับ intent  ==  Σ volume_filled ของ exec_report ของ intent นั้น
```

### 4.6 read-only เด็ดขาด

- ห้ามเขียน DB · ห้ามส่ง order · ห้ามแก้ไฟล์ใดๆ นอก `data/consistency/`
- ต่อ MT5 แบบอ่านอย่างเดียว
- **acceptance มี `grep`** ห้ามเจอ `order_send` · `INSERT` · `UPDATE` · `DELETE`

**เครื่องมือที่ "แก้ให้ตรง" ให้อัตโนมัติคือเครื่องมือที่ทำให้ปัญหาหายไปโดยไม่มีใครรู้ว่าเคยมี**

### 4.7 ต้องรันตอนเทอร์มินัลเปิด

เหมือน [SPEC-007 §4.2](SPEC-007-data-ingest.md) — ใช้ `MetaTrader5` package
→ **ชนกับ MQL5 gate ที่ต้องการเทอร์มินัลปิด** · ต้องเช็คกันและกัน

---

## 5. Edge cases

1. **MT5 history ยังไม่โหลดช่วงที่ขอ** → `history_select()` คืน false → **error ไม่ใช่ "ไม่มี deal"**
   ★ ถ้าตีความว่าไม่มี deal จะกลายเป็นว่า "ตรงกันหมด" ทั้งที่ไม่ได้ตรวจอะไรเลย
2. **DB ว่าง (ยังไม่เคยเทรด)** → รายงาน "ไม่มีข้อมูลให้เทียบ" · exit 0
3. **MT5 มี deal แต่ DB ว่าง** → C1 ทุกใบ · ถูกต้องแล้ว
4. **deal ของ symbol ที่ไม่อยู่ใน registry** → INFO ไม่ใช่ error (อาจเทรดมือ)
5. **หลาย session ของ symbol เดียวกัน** (คนละ timeframe) → magic เดียวกัน
   → C3 ต้องรวมทุก session ที่ magic+symbol ตรง ไม่ใช่เทียบทีละ session
6. **DST เปลี่ยนในช่วงที่ตรวจ** → ไม่กระทบเพราะจับคู่ด้วย ticket (§4.1)
   แต่ **ตัวกรองเวลาต้อง pad พอ**
7. **ticket ซ้ำข้ามโบรกเกอร์** — IUX กับ XM ออก ticket ชนกันได้
   → กุญแจต้องเป็น **`(broker, ticket)`** ไม่ใช่ ticket เปล่า ★
8. **`exec_report` ที่ `ticket = null`** (TIMEOUT/REJECTED) → จับคู่ด้วย ticket ไม่ได้
   → ต้องหา deal ที่**เวลาใกล้เคียง + volume ตรง + symbol ตรง** แล้วรายงานเป็น
   **"น่าจะเป็นคู่กัน ต้องให้คนดู"** ไม่ใช่ยืนยันเอง ★
9. **โบรกเกอร์แก้ไข deal ย้อนหลัง** (correction) → รายงานว่าต่างจากรอบก่อน
10. **รันสองครั้งพร้อมกัน** → ไม่มีปัญหา (read-only) แต่ MT5 connection ชนกันได้

---

## 6. Acceptance criteria

- [ ] `python -m ops.consistency --days 7` รันได้และออกรายงาน
- [ ] **ฉีด deal ที่ไม่มี `exec_report` → ตรวจเจอเป็น C1** ★★
- [ ] ฉีด `exec_report FILLED` ที่ไม่มี deal → C2
- [ ] ทำให้ `owned_net` ใน DB ต่างจาก MT5 → C3
- [ ] `intents ACCEPTED` ที่ไม่มีผลตามมา → C4
- [ ] partial fill (1 intent → 3 deal) → **ไม่ถูกรายงานเป็นความไม่ตรง** ★ §4.5
- [ ] deal ของ magic อื่น → INFO **ไม่ใช่ CRITICAL**
- [ ] **`history_select()` ล้มเหลว → error** ไม่ใช่รายงานว่าตรงกันหมด ★★ edge 1
- [ ] กุญแจจับคู่เป็น `(broker, ticket)` — ตรวจด้วย test ที่มี ticket ซ้ำข้ามโบรกเกอร์ ★
- [ ] `exec_report` ที่ `ticket = null` → รายงานเป็น "ต้องให้คนดู" ไม่ใช่จับคู่เอง
- [ ] `--fail-on critical` → exit 1 เมื่อมี C1–C4 · exit 0 เมื่อมีแต่ WARN/INFO
- [ ] `account_state` เก่ากว่า 30 วินาที → **ข้าม C3 + บอกเหตุผล** ไม่ใช่รายงานว่าไม่ตรง
- [ ] **`grep -rniE "order_send|INSERT |UPDATE |DELETE " ops/consistency/` — ไม่เจอ** ★★
- [ ] รัน 2 ครั้ง → รายงาน byte-identical (ข้อมูลเท่าเดิม)
- [ ] `python tools/task.py check` ผ่านบนเครื่องที่ไม่มี DB/MT5 (marker ถูก skip)
- [ ] `grep -rn "except:" ops/consistency/` — ไม่เจอ bare except

## 7. Test list — `tests/test_consistency.py`

unit test ใช้ **ข้อมูลสังเคราะห์ทั้งสองฝั่ง** (จำลอง deal list + แถว DB) — ไม่ต้องมี MT5/DB จริง

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_matched_deal_and_exec_report_no_finding` | เคสปกติ |
| 2 | `test_orphan_deal_is_critical` | ★★ C1 |
| 3 | `test_orphan_filled_exec_report_is_critical` | C2 |
| 4 | `test_position_mismatch_is_critical` | C3 |
| 5 | `test_accepted_intent_without_result_is_critical` | C4 |
| 6 | `test_partial_fills_aggregated_before_compare` | ★ §4.5 |
| 7 | `test_foreign_magic_deal_is_info_only` | C8 |
| 8 | `test_ticket_key_includes_broker` | ★ edge 7 |
| 9 | `test_null_ticket_reported_as_needs_review` | ★ edge 8 |
| 10 | `test_history_select_failure_raises_not_passes` | ★★ edge 1 |
| 11 | `test_stale_account_state_skips_c3_with_reason` | §4.4 |
| 12 | `test_price_diff_within_tolerance_is_not_finding` | C6 |
| 13 | `test_exit_code_reflects_severity` | |
| 14 | `test_report_deterministic` | |
| 15 | `test_time_filter_pads_boundaries` | edge 6 |

**test 2 กับ 10 คือสองตัวที่สำคัญที่สุด:**
- 2 คือเหตุผลทั้งหมดที่ ticket นี้มีอยู่
- 10 คือตัวที่กัน **"ผ่านเพราะไม่ได้ตรวจ"** ซึ่งอันตรายกว่าตรวจแล้วเจอปัญหา

## 8. Files

**Touch:** `ops/consistency/**` · `tests/test_consistency.py` · `tools/task.py`

**ห้ามแตะ:** `brain/**` · `mt5-ea/**` · `contracts/**` · `docs/**` · `migrations/**`
· `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| **Q1** | `exec_reports.ticket` คือ order ticket หรือ position ticket · และตรงกับ field ไหนใน `history_deals_get` | **ไม่บล็อก แต่ต้องพิสูจน์ก่อนเขียน matcher** — เทรด demo 1 ไม้แล้วเทียบเลขจริง · **รายงานพร้อมตัวอย่างจริง** · ผิดตรงนี้ = จับคู่ไม่ได้ทั้งชุด |
| Q2 | tolerance ของราคา 1 point เหมาะไหม | **ไม่บล็อก** — เริ่มที่นี่ · รายงานว่าเจอ C6 กี่ครั้งตอน soak |
| Q3 | ควรรันอัตโนมัติทุกวันไหม | **ยังไม่ต้อง** — Phase 1 รันมือก่อน · การตั้งเวลาเป็นงาน SPEC-029/053 |

> **ไม่มีคำถามที่บล็อก — เริ่มจาก checker + unit test 1–15 ได้เลยด้วยข้อมูลสังเคราะห์**

---

## ภาคผนวก — ทำไม "ผ่านเพราะไม่ได้ตรวจ" ถึงอันตรายที่สุด

เครื่องมือเทียบข้อมูลมี failure mode เฉพาะตัว: **มันรายงานว่าทุกอย่างตรงกันได้
ทั้งที่ไม่ได้เทียบอะไรเลย**

`history_select()` คืน false แล้วโค้ดตีความว่า "ไม่มี deal ในช่วงนี้"
→ ไม่มี deal ก็ไม่มีอะไรให้ไม่ตรง → **รายงานเขียว**

แล้วเราจะเชื่อว่า DB ตรงกับโบรกเกอร์ 100% ทั้งที่ไม่เคยเทียบเลยสักครั้ง
และจะไปรู้ตอนที่ position ค้างไม่ตรงจนพอร์ตเสียหาย

edge 1 กับ test 10 มีไว้เพื่อกันเรื่องนี้โดยเฉพาะ — เป็นแบบเดียวกับ
`test_stale_output_detected_when_ea_missing` ใน [SPEC-005](SPEC-005-roundtrip-harness.md)
และกลไก 3 ชั้นของ backfill ใน [SPEC-010](SPEC-010-state-reporter.md)

**gate ทุกตัวในโปรเจกต์นี้ต้องตอบให้ได้ว่า "ถ้าฉันไม่ได้ทำงาน จะมีใครรู้ไหม"**
