# SPEC-065 — MQL5 test harness (ปิดงานที่ทำไปแล้ว + ขยายให้รองรับหลาย suite)

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-001 · **Blocks:** SPEC-009
**อ้าง:** [07-compile-gate](../07-compile-gate.md) · [gate-02](../reviews/SPEC-001-compile-gate-02.md) · [G9](../06-gap-audit.md)

> ⚠️ **ส่วนใหญ่ทำไปแล้ว** — ticket นี้คือการ**เขียนกฎที่เรียนมาให้เป็นลายลักษณ์อักษร**
> และขยายให้รองรับ suite ที่กำลังจะมาอีก 7 ตัว

---

## 1. Goal

harness ที่รัน MQL5 test ได้ด้วยคำสั่งเดียว รองรับหลาย suite หลายโบรกเกอร์
และ**ออกหลักฐานที่ตรวจได้ว่า test รันบน commit ไหน**

## 2. Non-goals

- ❌ ห้ามเขียน test ใหม่ — ticket นี้คือ**ตัวรัน** ไม่ใช่ตัวทดสอบ
- ❌ ห้ามทำ CI (SPEC-009) — ที่นี่แค่ออกไฟล์ผลลัพธ์ให้ CI ใช้
- ❌ ห้ามใช้ live chart (SPEC-016 เป็นคนทำ) — ที่นี่ใช้ **Strategy Tester** เท่านั้น
- ❌ ห้ามแตะโค้ดใน `mt5-ea/**` หรือ `tests/mql5/*.mq5`

---

## 3. สิ่งที่มีอยู่แล้ว — อย่าทำซ้ำ

| ทำแล้ว | หลักฐาน |
|--------|---------|
| deploy include + expert เข้า data folder | `tools/run-mql5-tests.ps1` |
| compile ผ่าน MetaEditor CLI + จับ error/warning | มี |
| ฉีด input ผ่าน `.set` (แบบ `Name=value` เปล่า) | มี |
| รัน Strategy Tester headless + `ShutdownTerminal=1` | มี |
| อ่านผล JSON จาก `Common\Files` + เทียบ `git_sha` | มี |
| ตรวจ `ran_names` เทียบรายชื่อที่ spec สั่ง | มี |
| เตือนถ้ามีไฟล์ค้าง uncommitted | มี |
| หลายโบรกเกอร์ + `Enabled` / `[SKIP]` | มี |
| ตรวจว่า terminal ไม่ได้เปิดอยู่ | มี |

**ticket นี้เพิ่มแค่ §5** — ที่เหลือคือการเขียนกฎให้ชัดใน §4

---

## 4. กฎที่เรียนมาแล้ว — เขียนไว้กันลืม

### 4.1 test ต้องเป็น **EA ไม่ใช่ Script**

Script รัน headless ผ่าน Strategy Tester ไม่ได้ → test ต้องเป็น EA ที่ทำงานใน
`OnInit` แล้วเรียก `ExpertRemove()`

### 4.2 ★ ห้ามตัดสินผลจาก exit code ของ terminal

EA ที่เรียก `ExpertRemove()` ใน `OnInit` ทำให้ tester log ว่า
`tester stopped because OnInit failed` และ **exit code = 0 ทั้งที่ test รันสำเร็จ**

→ ตัดสินจาก **ไฟล์ JSON เท่านั้น** ([gate-02 กับดัก #5](../reviews/SPEC-001-compile-gate-02.md))

### 4.3 เขียนไฟล์ผลลัพธ์ต้องเป็น UTF-8 จริง

MQL5 ไม่มี `FILE_UTF8` → ต้อง `FILE_BIN` + `StringToCharArray(..., CP_UTF8)`
· `FILE_TXT|FILE_ANSI` จะเพี้ยนตาม codepage เครื่อง (CP874 บนเครื่องนี้)

### 4.4 `.set` — ค่า string ห้ามมี suffix `||||N`

suffix นั้นใช้กับ numeric param ตอน optimization · ถ้าใส่กับ string มันจะกลาย
**เป็นส่วนหนึ่งของค่า** → เคยทำให้ `FileOpen` error 5004 เพราะชื่อไฟล์กลายเป็น
`result.json||||N`

### 4.5 ต้องรันบนเทอร์มินัลที่มีบัญชีและ history

`C:\Program Files\MetaTrader 5` ไม่มีบัญชี → tester สตาร์ตไม่ได้
· symbol ต้องมี suffix ให้ถูก (`EURUSD.iux` ไม่ใช่ `EURUSD`)
· ช่วงวันต้องอยู่ในข้อมูลที่มีจริง

### 4.6 ★ ต้องเทียบ `git_sha` และ **ต้องลบผลเก่าก่อนรัน**

ไฟล์ผลลัพธ์อยู่ใน `Common\Files` ซึ่งอยู่**นอก repo** → ผลรอบก่อนค้างอยู่ได้

| ชั้น | กัน |
|------|-----|
| 1 | **ลบไฟล์ผลลัพธ์ของ suite นั้นก่อนรันทุกครั้ง** |
| 2 | เทียบ `git_sha` กับ `HEAD` |
| 3 | เทียบ `ran_names` กับรายชื่อที่ spec สั่ง |

ชั้น 2–3 มีแล้ว · **ชั้น 1 ต้องยืนยันว่ามี** — ถ้าไม่มี suite ที่ compile ไม่ผ่าน
จะ "ผ่าน" ด้วยผลเก่า (แบบเดียวกับ [SPEC-005](SPEC-005-roundtrip-harness.md) edge 1)

---

## 5. สิ่งที่ต้องเพิ่ม

### 5.1 รองรับ suite ที่กำลังจะมาอีก 7 ตัว

| suite | มาจาก |
|-------|-------|
| `TestWire` | SPEC-001 ✅ มีแล้ว |
| `TestBrokerTime` | SPEC-063 |
| `TestFarmMessages` | SPEC-004 |
| `TestRoundTrip` | SPEC-005 |
| `TestFarmSymbols` | SPEC-064 |
| `TestStateReporter` | SPEC-010 |
| `TestIntentCache` | SPEC-012 |
| `TestReconciler` | SPEC-017 |

**กฎ:**
- รายชื่อ `ran_names` ที่บังคับ ต้องอยู่**ใน manifest แยกไฟล์** ไม่ใช่ hardcode ในสคริปต์
  → `tools/mql5-suites.json` ระบุ `{name, source, required_tests[]}`
- **8 suite × ~30 วินาที ≈ 4 นาที** — ยอมรับได้ · ถ้าเกิน 10 นาที **ให้รายงาน**
- suite ที่ยังไม่มีไฟล์ต้นทาง → `[SKIP]` พร้อมเหตุผล **ไม่ใช่ FAIL**
  (จะได้เพิ่ม manifest ล่วงหน้าได้โดยไม่ทำให้ gate แดง)

### 5.2 ★★ ออกไฟล์ attestation ให้ CI ใช้ — `gate/mql5-latest.json`

```json
{
  "git_sha": "0d2f55e…",
  "ran_at_utc": "2026-07-28T09:12:33Z",
  "targets_run": ["IUX"],
  "targets_skipped": [{"name": "XM", "reason": "D11 login invalid"}],
  "suites": [
    {"name": "TestWire", "status": "PASS", "total": 47, "passed": 47, "failed": 0}
  ],
  "overall": "PASS"
}
```

**commit ไฟล์นี้ลง repo** — เป็นสิ่งเดียวที่ทำให้ CI (ซึ่งไม่มี MT5) ตรวจได้ว่า
*"มีคนรัน MQL5 gate บน commit นี้แล้วผ่าน"*

> ⚠️ **นี่คือ attestation ไม่ใช่ proof** — แก้ด้วยมือได้
> แต่มันทำให้คำกล่าวอ้าง *"test ผ่าน"* กลายเป็นสิ่งที่ **diff ได้ · ตรวจได้ · มีประวัติ**
> ซึ่งดีกว่าเชื่อข้อความใน handoff เฉยๆ · ดู [SPEC-009 §4.3](SPEC-009-ci.md)

### 5.3 สรุปท้ายต้องอ่านออกในบรรทัดเดียว

```
MQL5 GATE  HEAD=0d2f55e  targets: IUX ran, XM skipped
  TestWire         PASS  47/47
  TestBrokerTime   PASS  15/15
  TestRoundTrip    SKIP  (source not found)
RESULT: PASS (2 suites, 1 skipped)
```

**`SKIP` ต้องปรากฏในสรุป** และ**ห้ามนับเป็น pass**

---

## 6. Acceptance criteria

- [ ] `tools/mql5-suites.json` เป็นแหล่งเดียวของรายชื่อ suite + `required_tests`
      — **`grep` ไม่เจอรายชื่อ test hardcode ใน `.ps1`**
- [ ] เพิ่ม suite ใหม่ = แก้ JSON อย่างเดียว ไม่ต้องแตะสคริปต์
- [ ] suite ที่ยังไม่มีไฟล์ → `[SKIP]` ไม่ใช่ FAIL
- [ ] **ลบไฟล์ผลลัพธ์ก่อนรันทุก suite** — พิสูจน์: ลบ `.ex5` ของ suite หนึ่งแล้วรัน
      ต้องได้ **FAIL** ไม่ใช่ผ่านด้วยผลเก่า ★★
- [ ] `git_sha` ไม่ตรง HEAD → FAIL
- [ ] `ran_names` ขาด → FAIL พร้อมชื่อที่ขาด
- [ ] `gate/mql5-latest.json` ถูกเขียนทุกครั้งที่รัน (ทั้งตอนผ่านและไม่ผ่าน)
- [ ] สรุปท้ายแสดง suite ที่รัน · ที่ skip · และผลรวม
- [ ] เวลารวมทั้ง gate **< 10 นาที** — ถ้าเกินให้รายงานตัวเลข
- [ ] เอกสาร: ร่างอัปเดต [`docs/07-compile-gate.md`](../07-compile-gate.md) ส่งมาใน handoff

## 7. Test list

harness เป็น PowerShell — test ทำแบบ**สถานการณ์จริง** ไม่ใช่ unit test

| # | สถานการณ์ | ต้องได้ |
|---|-----------|---------|
| 1 | ทุกอย่างปกติ | `RESULT: PASS` · exit 0 |
| 2 | ลบ `.ex5` ของ suite หนึ่ง | **FAIL** ไม่ใช่ผ่านด้วยผลเก่า ★★ |
| 3 | แก้ไฟล์ `.mq5` ให้ compile ไม่ผ่าน | FAIL พร้อม compiler output |
| 4 | เอา test ออก 1 ตัวจาก `RunAllTests()` | FAIL พร้อมชื่อที่ขาด |
| 5 | suite ใน manifest ที่ไม่มีไฟล์ | `[SKIP]` · exit 0 |
| 6 | เทอร์มินัลเปิดค้างอยู่ | FAIL ทันทีพร้อมข้อความชัด |
| 7 | มีไฟล์ค้าง uncommitted | WARN แต่รันต่อ |

**ข้อ 2 สำคัญที่สุด** — เป็นตัวเดียวที่กัน *"เขียวเพราะไม่ได้รัน"*

## 8. Files

**Touch:** `tools/run-mql5-tests.ps1` · `tools/mql5-suites.json` · `gate/mql5-latest.json`
· ร่าง `docs/07-compile-gate.md` (ส่งมาใน handoff · ห้าม commit `docs/`)

**ห้ามแตะ:** `mt5-ea/**` · `tests/mql5/*.mq5` · `contracts/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `gate/` ควรถูก gitignore ไหม | **ไม่ — ต้อง commit** เพราะเป็น attestation ที่ CI อ่าน (§5.2) · เพิ่ม exception ใน `.gitignore` ถ้าจำเป็น **แล้วรายงาน** |
| Q2 | 8 suite ใช้เวลาเท่าไรจริง | **ไม่บล็อก** — วัดแล้วรายงาน |

> **ไม่มีคำถามที่บล็อก**
