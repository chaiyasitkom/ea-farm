# SPEC-023 — SafeMode + R13 kill file + R16 brain timeout

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-019, SPEC-063
**อ้าง:** [risk-spec R13/R16](../03-risk-spec.md) · [G4](../06-gap-audit.md)

---

## 1. Goal

สองอย่างที่ต้องทำงานได้**ตอนที่ทุกอย่างอื่นพังหมดแล้ว**:
สวิตช์หยุดฉุกเฉินที่กดได้แม้ไม่มีเน็ต · และการรู้ตัวว่า brain ตายแล้ว

## 2. Non-goals

- ❌ ห้ามพึ่ง brain / socket / DB ในการทำงานของ ticket นี้เลย ★
- ❌ ห้าม implement dashboard kill switch (SPEC-028) — ที่นี่คือ**ไฟล์** ไม่ใช่ UI
- ❌ ห้าม implement Telegram alert (SPEC-029)
- ❌ ห้ามส่ง order เอง — เปลี่ยน `Mode()` เท่านั้น

---

## 3. Interface

```mql5
class CSafeMode
{
public:
   bool Init(CBrokerTime *clock, const string kill_file_name,   // "farm_kill.txt"
             const int brain_timeout_sec);                      // 10

   // เรียกทุก Pump() -- ต้องเรียกก่อน guard ตัวอื่นเสมอ
   bool Evaluate(const int seconds_since_last_inbound);

   ENUM_FARM_GUARD_MODE Mode() const;
   bool   KillFilePresent() const;
   bool   BrainTimedOut() const;
   string Reason() const;
};
```

ไฟล์: `mt5-ea/Include/Farm/SafeMode.mqh` · `tests/mql5/TestSafeMode.mq5`

---

## 4. Behaviour

### 4.1 ★★ R13 kill file — ต้องทำงานได้แม้ไม่มีอะไรทำงานเลย

```
มีไฟล์ Common\Files\farm_kill.txt  →  HALT + FLATTEN ทันที ทุก terminal
```

| กฎ | เหตุผล |
|----|--------|
| ใช้ `FILE_COMMON` | ไฟล์เดียว **หยุดทุก terminal พร้อมกัน** — นั่นคือทั้งหมดที่ต้องการ |
| เช็คใน **`OnTimer` ทุก 1 วินาที** | **ห้ามเช็คใน `OnTick`** — ตลาดปิด tick ไม่มา แล้ว kill switch จะไม่ทำงานตอนสุดสัปดาห์ ★ |
| **ลบไฟล์แล้วห้ามปลดเอง** | ★★ ดู §4.2 |
| อ่านไฟล์ไม่ได้ (permission/lock) | **ถือว่ามีไฟล์** → HALT ★ fail-closed |

**ข้อสุดท้ายสำคัญ:** ถ้าอ่านไม่ได้แล้วตีความว่า "ไม่มีไฟล์" คนที่กดหยุดฉุกเฉิน
จะคิดว่าหยุดแล้วทั้งที่ยังเทรดอยู่

### 4.2 ★★ kill file ปลดด้วยมือเท่านั้น

```
ลบ farm_kill.txt  →  ยัง HALT อยู่
ปลดจริง          →  ลบไฟล์ + ลบ GlobalVariable farm_killhalt_<magic>_<symbol>
```

**เหตุผล:** kill switch ถูกกดตอนมีเรื่อง · การที่ไฟล์หายไป (โดนลบ · ดิสก์มีปัญหา ·
สคริปต์ทำความสะอาด) **ไม่ใช่สัญญาณว่าเรื่องนั้นจบแล้ว**

ถ้าปลดเองเมื่อไฟล์หาย ระบบจะกลับมาเทรดโดยไม่มีใครตั้งใจให้กลับมา

`farm_killhalt_*` ต้อง **persist ข้ามรีสตาร์ต** — วางไฟล์ kill แล้ว EA รีสตาร์ต
ต้องยัง halt ★

### 4.3 R16 brain timeout — ต่างจาก R13 ตรงที่ **ปลดเอง**

```
seconds_since_last_inbound > brain_timeout_sec (10)  →  SafeMode
brain กลับมา (มี inbound)                            →  ปลดเอง กลับ NORMAL
```

| | R13 kill file | R16 brain timeout |
|---|---------------|-------------------|
| สาเหตุ | **คนตัดสินใจหยุด** | **ปัญหาการเชื่อมต่อ** |
| ปลด | **มือเท่านั้น** | **อัตโนมัติเมื่อกลับมา** |
| mode | `HALT` + `FLATTEN` | `REDUCE_ONLY` (§4.4) |

**ความต่างนี้สำคัญ** — ถ้า R16 ต้องปลดมือ เน็ตกระตุก 11 วินาทีจะทำให้ต้องมีคนมาปลด
· ถ้า R13 ปลดเอง สวิตช์ฉุกเฉินจะไม่ใช่สวิตช์ฉุกเฉิน

### 4.4 ★ SafeMode ทำอะไร — `REDUCE_ONLY` ไม่ใช่ `FLATTEN`

risk-spec เขียนว่า R16 → *"SafeMode (`HOLD` default)"*

| ทำได้ | ทำไม่ได้ |
|-------|----------|
| ปิด / ลดขนาด position | เปิดใหม่ · เพิ่มขนาด |
| SL/TP ที่ตั้งไว้ยังทำงาน (broker-side) | รับ INTENT ใหม่ |

**ห้าม flatten ตอน brain ตาย** — brain ตายไม่ได้แปลว่าตลาดเป็นอันตราย
· การปิดทุกไม้เพราะเน็ตหลุด = รับรู้ขาดทุนในจังหวะที่เลือกโดยความบังเอิญ
(เหตุผลเดียวกับ [SPEC-017](SPEC-017-reconciliation.md) ที่ห้าม EA ลงมือเองตอนรีสตาร์ต)

**SL ที่อยู่ฝั่งโบรกเกอร์คือสิ่งที่ปกป้องเราตอน brain ตาย** — ไม่ใช่การ flatten
· นี่คือเหตุผลที่ [G5](../06-gap-audit.md) บังคับให้ SL เป็น broker-side ทุกไม้

### 4.5 ลำดับความสำคัญ

```
R13 kill file  >  R6/R7 hard  >  R14  >  R16  >  R8  >  NORMAL
```

`CSafeMode.Evaluate()` ต้องถูกเรียก **ก่อน** guard ตัวอื่นใน `Pump()`
· ถ้า kill file มี → ไม่ต้องประเมินอะไรอีกเลย

### 4.6 ต้องไม่พึ่งอะไรที่พังได้

| ห้ามพึ่ง | เพราะ |
|----------|-------|
| socket / `CWire` | ตัว R16 มีไว้จับกรณีที่ socket ตาย |
| DB | ไม่มีทางเข้าถึงจาก EA อยู่แล้ว |
| `CBrokerTime` สำหรับ **R13** | ★ kill file ต้องทำงานแม้เวลาเพี้ยน — เช็คไฟล์ไม่ต้องใช้เวลา |
| `CBrokerTime` สำหรับ R16 | ใช้ `seconds_since_last_inbound` ที่ `CWire` นับด้วย tick count |

**R13 ต้องเป็นส่วนที่เรียบง่ายที่สุดในระบบทั้งหมด** — ยิ่งพึ่งของน้อย ยิ่งพังยาก

---

## 5. Edge cases

1. **ไฟล์ kill ว่างเปล่า** → ยังนับว่ามี · **เนื้อในไม่สำคัญ** การมีอยู่คือสัญญาณ
2. **ไฟล์ kill ถูกสร้างตอน EA ไม่ได้รัน** → เจอตอน `OnInit` → halt ทันที ★
3. **ตลาดปิด + kill file** → halt ได้ · flatten จะล้มเหลวที่โบรกเกอร์ → **retry ตอนตลาดเปิด**
   + คง halt ไว้
4. **`seconds_since_last_inbound` เป็นค่าลบ** (tick count wrap) → ถือว่า 0 ไม่ใช่ timeout
5. **brain กลับมาแล้วหลุดอีกทันที** → เข้า-ออก SafeMode ได้ · **ไม่ต้องมี hysteresis**
   (10 วินาทีเป็น buffer อยู่แล้ว)
6. **หลาย EA บนเครื่องเดียว** → ไฟล์เดียวหยุดทุกตัว ✅ ตามเจตนา
   · แต่ `GlobalVariable` แยกต่อ EA → ต้องลบทุกตัวตอนปลด **เขียนไว้ใน runbook** ★
7. **`Init()` ตอนมี kill file อยู่แล้ว** → `Mode() = HALT` ตั้งแต่ต้น · **ไม่ใช่ `INIT_FAILED`**
   (ต้องเชื่อมต่อ brain ได้เพื่อรายงานว่าถูก halt)

---

## 6. Acceptance criteria

- [ ] วางไฟล์ `farm_kill.txt` → EA เข้า `HALT` ภายใน **≤ 2 วินาที** ★★
- [ ] **ทำงานตอนตลาดปิด** (ไม่มี tick) — พิสูจน์ด้วยการทดสอบวันเสาร์ ★★
- [ ] **ลบไฟล์แล้วยัง halt** — ต้องลบ `GlobalVariable` ด้วยถึงจะปลด ★★
- [ ] วางไฟล์ → รีสตาร์ต EA → **ยัง halt** ★
- [ ] อ่านไฟล์ไม่ได้ → **ถือว่ามี** (fail-closed) ★★
- [ ] R16: ไม่มี inbound > 10 วิ → `REDUCE_ONLY` · กลับมา → `NORMAL` **อัตโนมัติ**
- [ ] **R16 ไม่ flatten** ★
- [ ] `HALT` จาก kill file **ยังยอมให้ `target_volume = 0` ผ่าน** ([SPEC-019 §4.1](SPEC-019-local-risk-guard.md)) ★★
- [ ] `grep -n "CWire\|Socket" mt5-ea/Include/Farm/SafeMode.mqh` — **ไม่เจอ** ★
- [ ] `grep -n "OnTick" mt5-ea/Include/Farm/SafeMode.mqh` — **ไม่เจอ**
- [ ] `Init()` ตอนมี kill file → `HALT` ไม่ใช่ `INIT_FAILED`
- [ ] ขั้นตอนปลด kill switch **เขียนเป็นร่างส่งมาใน handoff** (จะไปลง runbook SPEC-030b) ★
- [ ] compile 0 error 0 warning · gate เขียว

## 7. Test list — `tests/mql5/TestSafeMode.mq5`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_kill_file_present_halts` | |
| 2 | `test_kill_file_detected_within_2s` | |
| 3 | `test_kill_file_removal_does_not_release` | ★★ §4.2 |
| 4 | `test_kill_halt_persists_across_restart` | ★★ |
| 5 | `test_unreadable_kill_file_treated_as_present` | ★★ §4.1 |
| 6 | `test_empty_kill_file_still_counts` | edge 1 |
| 7 | `test_kill_file_found_at_init` | edge 2/7 |
| 8 | `test_brain_timeout_sets_reduce_only_not_flatten` | ★★ §4.4 |
| 9 | `test_brain_recovery_auto_releases` | ★ §4.3 |
| 10 | `test_negative_seconds_not_timeout` | edge 4 |
| 11 | `test_kill_beats_brain_timeout` | §4.5 |
| 12 | `test_safemode_does_not_use_wire` | ★ §4.6 |
| 13 | `test_flatten_still_allowed_when_halted` | ★★ ปิดได้เสมอ |

**test 3 · 5 · 8 · 13 คือสี่ตัวที่ห้ามพลาด:**
- 3 กับ 5 คือความน่าเชื่อถือของสวิตช์ฉุกเฉิน
- 8 คือการไม่ปิดไม้ทิ้งเพราะเน็ตหลุด
- 13 คือความสามารถในการปิดไม้ตอน halt

## 8. Files

**Touch:** `mt5-ea/Include/Farm/SafeMode.mqh` · `tests/mql5/TestSafeMode.mq5`
· `mt5-ea/Include/Farm/RiskGuard.mqh` (`AttachSafeMode`) · `mt5-ea/Experts/FarmExecutor.mq5`
· `tools/mql5-suites.json` · ร่างขั้นตอนปลด kill switch (ส่งใน handoff)

**ห้ามแตะ:** `contracts/**` · `docs/**` · `mt5-ea/Include/Farm/Wire.mqh`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | kill file ควรมีเนื้อหา (เหตุผล/เวลา) ไหม | **ไม่บล็อก — ตอบแล้ว: ไม่จำเป็น** · การมีอยู่คือสัญญาณ · ถ้าใส่เนื้อหาแล้วอ่านไม่ออกจะกลายเป็นจุดพังเพิ่ม · แต่ EA ควร **log เนื้อหาถ้าอ่านได้** เพื่อให้รู้ว่าใครกด |
| Q2 | ควรมี kill file ต่อ symbol ด้วยไหม | **ยังไม่ต้อง** — ฉุกเฉินคือหยุดทั้งหมด · การหยุดบาง symbol เป็นงานของ `RISK_DIRECTIVE` (SPEC-027) |

---

## ภาคผนวก — ทำไม kill file ถึงต้องเรียบง่ายที่สุดในระบบ

มันคือสิ่งสุดท้ายที่เหลืออยู่เมื่อทุกอย่างอื่นพัง: brain ตาย · เน็ตหลุด · DB ล่ม ·
dashboard เข้าไม่ได้ · และคนที่ต้องกดอาจอยู่บนมือถือผ่าน remote desktop ที่กระตุก

ทุกอย่างที่มันพึ่งพาคือสิ่งที่อาจไม่ทำงานในวันนั้น — จึงต้องเหลือแค่:
**"มีไฟล์นี้ไหม"** และคำตอบที่ปลอดภัยเมื่อไม่แน่ใจคือ **"ถือว่ามี"**

[G4](../06-gap-audit.md) ระบุไว้แล้วว่าหนึ่งในสถานการณ์ที่ runbook ต้องครอบคือ
*"ขอปิดทุกอย่างด่วนตอนไม่มีคอม"* — kill file คือคำตอบของข้อนั้น
และมันจะเป็นคำตอบได้ก็ต่อเมื่อมันเรียบง่ายพอที่จะเชื่อได้
