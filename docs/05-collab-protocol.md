# 05 — Claude ↔ Codex Collaboration Protocol

> โมเดล: **Claude = architect + reviewer · Codex = implementer**
> เป้าหมายไม่ใช่ "แบ่งกันทำคนละครึ่ง" แต่คือ **ให้ทั้งคู่ทำสิ่งที่ตัวเองเก่งกว่า และตรวจงานกันได้**

---

## แบ่งงานอย่างไร

| งาน | Claude | Codex |
|-----|--------|-------|
| ออกแบบสถาปัตยกรรม, ตัดสิน trade-off | ✅ เจ้าของ | อ่านและตั้งคำถามได้ |
| `contracts/schema/*.json` | ✅ **เจ้าของแต่คนเดียว** | ❌ ห้ามแก้ |
| เขียน spec รายงาน (`docs/specs/`) | ✅ เจ้าของ | อ่านแล้วทำ |
| ออกแบบ risk rule + ตัวเลข limit | ✅ เจ้าของ | implement ตามเป๊ะ |
| ออกแบบ label / feature semantics | ✅ เจ้าของ | implement |
| เขียน risk test scenario | ✅ เจ้าของ (เขียนเป็นข้อความ) | implement เป็นโค้ด |
| **เขียนโค้ดทั้งหมด** (MQL5, Python, SQL, CI) | ❌ ไม่แตะ | ✅ เจ้าของ |
| เขียน unit/integration test | ❌ | ✅ เจ้าของ |
| Refactor, แก้ bug, ปรับ performance | ❌ | ✅ เจ้าของ |
| Code review | ✅ เจ้าของ | ตอบและแก้ |
| ตรวจว่าโค้ดตรง contract ไหม | ✅ เจ้าของ | |
| Runbook, doc สำหรับมนุษย์ | ✅ เจ้าของ | |
| ตัดสินว่าผ่าน exit criteria ไหม | ✅ เจ้าของ | เสนอหลักฐาน |

**Claude ไม่แตะโค้ด** ยกเว้น 2 กรณี: (1) แก้ typo ใน doc/spec ของตัวเอง
(2) Codex ติดจริงๆ และขอความช่วยเหลือชัดเจน — ตอนนั้นให้เป็น *ตัวอย่างใน spec* ไม่ใช่แก้ไฟล์

---

## Flow ต่อ 1 ticket

```
┌─ 1. Claude เขียน SPEC ────────────────────────────────────────┐
│  docs/specs/SPEC-NNN-<slug>.md                                │
│  ต้องมี: Goal · Non-goals · Interface · Data contract         │
│          Behaviour table · Edge cases · Acceptance criteria    │
│          Test list · Files to touch · Files NOT to touch      │
└───────────────────────┬───────────────────────────────────────┘
                        ▼
┌─ 2. Codex อ่าน แล้วตอบก่อนเขียนโค้ด ─────────────────────────┐
│  โพสต์ "Implementation note" สั้นๆ (≤ 15 บรรทัด):             │
│   · จะแบ่งไฟล์อย่างไร                                          │
│   · จุดที่ spec กำกวม / ขัดแย้ง / ทำไม่ได้จริง  ← สำคัญสุด    │
│   · ข้อสมมติที่จะใช้ถ้าไม่มีคำตอบ                              │
│  ถ้าเจอจุดกำกวม → หยุด รอ Claude แก้ spec ก่อน               │
└───────────────────────┬───────────────────────────────────────┘
                        ▼
┌─ 3. Codex implement บน branch ────────────────────────────────┐
│  branch: feat/SPEC-NNN-<slug>                                 │
│  ต้องมี test ครบตาม Test list ก่อนเรียกว่าเสร็จ                │
│  commit message อ้าง SPEC-NNN                                 │
└───────────────────────┬───────────────────────────────────────┘
                        ▼
┌─ 4. Codex ส่ง Handoff Report ────────────────────────────────┐
│  (แบบฟอร์มด้านล่าง) — ห้ามส่งแค่ "เสร็จแล้ว"                  │
└───────────────────────┬───────────────────────────────────────┘
                        ▼
┌─ 5. Claude review ────────────────────────────────────────────┐
│  Checklist ด้านล่าง → เขียนผลลง docs/reviews/SPEC-NNN.md      │
│  ผล: APPROVED · APPROVED_WITH_NOTES · CHANGES_REQUIRED       │
└───────────────────────┬───────────────────────────────────────┘
                        ▼
              merge เข้า main (ถ้า APPROVED)
```

---

## แบบฟอร์ม: Codex Handoff Report

```markdown
## SPEC-NNN Handoff

**Branch:** feat/SPEC-NNN-slug
**Commits:** <sha ต้น>..<sha ปลาย>

### ทำอะไรไปแล้ว
- ไฟล์ที่เพิ่ม/แก้ (พร้อมบรรทัดสำคัญ)

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
(ถ้าไม่มีให้เขียน "ไม่มี" — ห้ามเว้นว่าง)

### Test
- ผลรัน: X passed / Y failed  (แปะ output จริง ไม่ใช่สรุป)
- Test ที่ spec ขอแต่ยังไม่ได้เขียน + เพราะอะไร
- Coverage ของโมดูลนี้

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
### จุดที่อยากให้ Claude ดูเป็นพิเศษ
### คำถามค้าง
```

**ห้ามรายงานว่าเสร็จถ้า test ยังแดง** — ให้บอกว่าแดงและแปะ output มา

---

## Checklist: Claude Review

**A. Contract compliance** (ตกข้อใดข้อหนึ่ง = `CHANGES_REQUIRED` ทันที)
- [ ] Message ทุกตัวตรง `docs/02-contracts.md` (field name, type, enum, หน่วย)
- [ ] `contracts/gen/` ไม่ถูกแก้มือ (codegen-diff CI เขียว)
- [ ] Idempotency: intent เดิมส่งซ้ำ = ไม่มี order ใหม่ (มี test พิสูจน์)
- [ ] Target-state semantics ตรงตารางใน §4.5 ทุกแถว
- [ ] ใช้ `ts_server` ตัดสินใจ ไม่ใช่ `ts_sent`

**B. Risk correctness** (เข้มที่สุด — นี่คือที่เงินหาย)
- [ ] R1–R17 ครบทุกข้อ ไม่มีข้อไหนถูกข้าม
- [ ] Local guard ทำงานได้แม้ brain ตาย (มี chaos test พิสูจน์)
- [ ] Guard limit มาจาก EA input ไม่ใช่จาก network
- [ ] Brain สั่งผ่อนกว่า local guard ไม่ได้
- [ ] HWM/halt state persist ข้าม restart
- [ ] ใช้ broker time สำหรับ "วันใหม่"/trading hours
- [ ] Lot sizing ถูกสำหรับ quote currency ≠ account currency
- [ ] ไม่มี fail-open ใน risk path (error = block ไม่ใช่ผ่าน)

**C. Failure handling**
- [ ] ทุกแถวในตาราง Failure Mode (`01-architecture.md`) มีโค้ดรองรับ
- [ ] ไม่มี bare `except:` / ไม่มี error ที่ถูกกลืน
- [ ] Retry มี cap + backoff ไม่มี infinite loop
- [ ] Timeout ทุกจุดที่มี I/O

**D. Correctness ทั่วไป**
- [ ] Look-ahead bias: feature ใช้แค่ข้อมูลที่มีจริงตอนนั้น
- [ ] Float comparison ใช้ tolerance ไม่ใช่ `==` (ราคา/lot)
- [ ] Lot ปัดตาม `volume_step` เสมอ ไม่ปัดขึ้นเกิน max
- [ ] Off-by-one ใน bar index (MQL5 `[0]` = bar ปัจจุบันยังไม่ปิด)

**E. Test quality**
- [ ] Test ทดสอบ *พฤติกรรม* ไม่ใช่ implementation
- [ ] มี test เคสร้าย ไม่ใช่แค่ happy path
- [ ] ไม่มี test ที่ผ่านเพราะ mock ทุกอย่าง
- [ ] Risk rule ทุกข้อมี test เฉพาะของตัวเอง

**F. Operability**
- [ ] Log พอให้ debug ย้อนหลังได้ (ทุก decision มี intent_id)
- [ ] ไม่มี secret ใน repo
- [ ] Config เปลี่ยนได้โดยไม่ recompile (ยกเว้น EA hard limit ที่ต้องเป็น input)

---

## เมื่อไม่เห็นตรงกัน

1. **Codex เห็นว่า spec ผิด/ทำไม่ได้** → หยุด อธิบายเหตุผลเชิงเทคนิค เสนอทางเลือก
   Claude ตัดสิน → อัปเดต spec → Codex ทำตามใหม่
2. **Claude เห็นว่าโค้ดผิด แต่ Codex ไม่เห็นด้วย** → ตัดสินด้วย **test ที่พิสูจน์ได้**
   ใครเขียน failing test ที่แสดงปัญหาได้ = ฝ่ายนั้นถูก ถ้าเขียนไม่ได้ = ข้อกังวลนั้นเป็นทฤษฎี
3. **เรื่อง risk** → ฝ่ายที่ conservative กว่าชนะโดยปริยาย จนกว่าจะมีหลักฐานตรงกันข้าม
4. **ติดกันเกิน 2 รอบ** → escalate ให้เจ้าของโปรเจกต์ตัดสิน พร้อมสรุป 2 ฝั่งอย่างละ 5 บรรทัด

---

## กฎที่ทั้งสองฝ่ายห้ามละเมิด

1. ❌ **ห้ามแตะ live account** ระหว่างพัฒนา — demo เท่านั้น จนถึง Phase 7
2. ❌ **ห้าม commit credential** — MT5 login, API key, DB password → `.env` เท่านั้น
3. ❌ **ห้ามลด/ปิด risk check เพื่อให้ test ผ่าน** — test ผิด แก้ test
4. ❌ **ห้ามแก้ `contracts/schema/` โดย Codex**
5. ❌ **ห้าม merge เข้า `main` โดยไม่ผ่าน review**
6. ❌ **ห้ามรายงานว่าเสร็จถ้า test แดง**
7. ❌ **ห้ามเพิ่ม dependency ใหม่โดยไม่บอก** — ระบุใน handoff report เสมอ
8. ⚠️ **ถ้าสงสัยเรื่อง risk → ถาม ไม่ใช่เดา**
9. ❌ **ห้ามใช้ `git add -A` / `git add .` เด็ดขาด — ต้องระบุ path ที่ตัวเองเป็นเจ้าของเท่านั้น**
10. ❌ **ห้าม commit ไฟล์ที่อีกฝ่ายเป็นเจ้าของ** แม้จะเห็นค้างอยู่ใน `git status`

---

## ⚠️ ทำงานพร้อมกันใน working tree เดียว

**เกิดขึ้นจริงแล้ว 2026-07-26:** Claude รัน `git add -A` เพื่อ commit เอกสาร แต่กวาดโค้ด
SPEC-001 ที่ Codex กำลังเขียนอยู่เข้ามาใน commit เดียวกัน และ commit นั้นไปลงบน
branch ของ Codex ด้วย ผลคือ commit message อธิบายแค่เอกสารแต่มีโค้ดปนอยู่
(แก้แล้ว: `git reset --soft` → แยก commit เอกสารไป `main` → ยืนยันไฟล์ Codex ครบด้วย md5)

### กฎแยกโซนความเป็นเจ้าของไฟล์

| path | เจ้าของ | อีกฝ่ายทำได้ |
|------|---------|--------------|
| `docs/**` · `contracts/schema/**` · `tools/**` · `AGENTS.md` · `CLAUDE.md` · `README.md` | **Claude** | อ่าน · เสนอแก้ผ่าน implementation note |
| `mt5-ea/**` · `brain/**` · `research/**` · `ops/**` · `tests/**` · `contracts/gen/**` · `.github/**` · `Makefile` | **Codex** | อ่าน · review · ห้ามแก้/commit |
| `.gitignore` · `.gitattributes` · `.env.example` | Codex (Claude แก้ได้ถ้าเกี่ยวกับ protocol เช่น LF) | บอกอีกฝ่ายในรายงาน |

### กฎ commit

```bash
# ✅ Claude
git add docs contracts/schema AGENTS.md CLAUDE.md README.md

# ✅ Codex
git add mt5-ea brain tests research ops contracts/gen

# ❌ ห้ามทั้งคู่
git add -A        git add .        git commit -a
```

### กฎ branch

- **Claude commit ลง `main` ตรงได้** (เอกสารไม่ต้อง review — แต่ Codex ตั้งคำถามได้)
- **Codex commit ลง `feat/SPEC-NNN-*` เท่านั้น** merge เข้า main หลัง review
- ก่อน commit ให้เช็ค `git branch --show-current` ว่าอยู่ branch ที่ควรอยู่
  (เหตุการณ์ข้างบนเกิดเพราะ Claude ไม่เช็คแล้ว commit ทับ branch ของ Codex)
- ถ้าเห็นไฟล์ของอีกฝ่ายค้างใน `git status` = **ปกติ ปล่อยไว้** ไม่ใช่ของเรา

---

## 🔨 MQL5 compile & test gate

**สถานะที่ตรวจพบ 2026-07-26:** Codex รัน Python test ได้ (มี `__pycache__`)
แต่ไม่มีไฟล์ `.ex5` ในโปรเจกต์เลย → **Codex ไม่มี MetaEditor/MT5 ให้คอมไพล์**

ผลคือ MQL5 ทั้งหมด (EA, LocalRiskGuard, OrderRouter — ส่วนที่สำคัญที่สุดของระบบ)
ถูกเขียนโดยไม่เคยผ่าน compiler เลย MQL5 มีกับดักที่ compiler จับได้และคนอ่านไม่เจอ
เช่น implicit conversion, `datetime` vs `long`, array ที่ไม่ resize, struct ที่มี string
ใน `ArrayResize` ดังนั้น "โค้ดที่ไม่เคยคอมไพล์" ≠ "โค้ดที่เสร็จ"

### ขั้นตอนเพิ่มเข้ามาใน flow

**ผู้รับผิดชอบ gate: Claude** (ตกลงแล้ว 2026-07-26) — วิธีรันดู [07-compile-gate.md](07-compile-gate.md)

```
Codex implement  ──►  ❶ COMPILE GATE (Claude รัน tools/compile-gate.ps1)
                          MetaEditor คอมไพล์ · เก็บ error+warning ทั้งหมด
                          เขียนผลลง docs/reviews/SPEC-NNN-compile-gate-NN.md
                              │ ส่งผลกลับให้ Codex
                              ▼
                      ❷ Codex แก้ตาม error  ──► วนซ้ำจน 0 error 0 warning
                              │
                              ▼
                      ❸ Handoff report (ต้องแนบ compiler output จริง)
                              │
                              ▼
                      ❹ Claude review
```

### ผลที่ต้องยอมรับ

- รอบแก้ MQL5 จะช้ากว่า Python ~2–3 เท่า เพราะมีมนุษย์อยู่ในลูป
- Codex **ห้ามเขียนในรายงานว่า "compile ผ่าน"** ถ้าไม่ได้เห็น compiler output จริง
  ให้เขียนว่า *"ยังไม่ได้คอมไพล์ — รอ compile gate"*
- SPEC-065 (MQL5 test harness) ต้องให้ test เขียนผลเป็น **JSON ลงไฟล์**
  เพื่อให้คน copy กลับมาให้ Codex ได้ง่าย และให้ CI ตรวจไฟล์ผลลัพธ์ได้
  (CI ยังรัน MT5 เองไม่ได้ แต่ตรวจได้ว่าผลล่าสุดเขียว และ commit hash ตรงกับโค้ดปัจจุบัน)

---

## Cadence ที่แนะนำ

| จังหวะ | ทำอะไร |
|--------|--------|
| ต่อ ticket | spec → note → implement → handoff → review |
| จบ phase | Claude เขียน phase review: exit criteria ผ่านครบไหม, หนี้เทคนิคค้างอะไร, spec ไหนต้องแก้ |
| ทุกสัปดาห์ (เมื่อมีของรัน) | ตรวจ live/demo metric เทียบ backtest, ดู risk event |
| ก่อนเพิ่มทุนทุกครั้ง | full risk review ใหม่ทั้งหมด ไม่ใช่แค่ diff |
