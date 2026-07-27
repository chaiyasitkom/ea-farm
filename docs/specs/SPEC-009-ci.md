# SPEC-009 — CI: ปิดช่องว่าง G3 ด้วย attestation

**Phase:** 0 · **Owner:** Codex · **Depends on:** SPEC-002, SPEC-065 · **Blocks:** Phase 0 exit
**ปิดช่องว่าง:** [G3](../06-gap-audit.md) · **อ้าง:** [08-status-and-plan §5.2](../08-status-and-plan.md)

---

## 1. Goal

ทำให้ *"test ผ่าน"* เป็นสิ่งที่**เครื่องตรวจได้** ไม่ใช่ข้อความใน handoff
โดยยอมรับความจริงว่า **CI รัน MQL5 ไม่ได้**

## 2. Non-goals

- ❌ ห้ามพยายามรัน MQL5 test ใน CI — **เป็นไปไม่ได้** (§3.1)
- ❌ ห้ามสร้าง git remote เอง — เป็นการตัดสินใจของเจ้าของ (§3.2)
- ❌ ห้ามเขียน test ใหม่
- ❌ ห้ามแก้ `tools/run-mql5-tests.ps1` (SPEC-065)

---

## 3. ข้อจำกัดจริงที่ต้องออกแบบรอบมัน

### 3.1 CI รัน MQL5 ไม่ได้ — และส่วนสำคัญที่สุดของระบบเป็น MQL5

| | |
|---|---|
| MQL5 ต้องมี MetaEditor + MT5 terminal ที่มีบัญชีและ history | GitHub Actions ไม่มี |
| ส่วนที่เป็น MQL5 | EA · Wire · **RiskGuard** · **OrderRouter** — ชั้นที่เงินหาย |
| ถ้าปล่อยไว้ | โค้ดที่สำคัญที่สุด **ไม่มีใครจับ regression อัตโนมัติเลย** |

นี่คือ [G3](../06-gap-audit.md) ที่ค้างมาตั้งแต่ audit

### 3.2 🔴 ยังไม่มี git remote — CI จึงยังรันไม่ได้เลย

`git remote -v` ว่างเปล่า · repo อยู่บนเครื่องเดียว

**ผลที่ตามมา 2 ข้อ:**
1. ไม่มี CI — และ **ไม่มี backup** เครื่องพัง = หายทั้งหมด (ADR · spec · schema)
2. workflow file ที่เขียนไว้จะ **inert** จนกว่าจะมี remote

> **ticket นี้เขียน workflow ไว้ให้พร้อม แต่ประโยชน์จริงเกิดต่อเมื่อมี remote**
> · การสร้าง remote เป็นงานของเจ้าของ ([D16](../backlog.md))

---

## 4. Behaviour

### 4.1 ★ แบ่งเป็น 3 ชั้น — ชั้น 1 ใช้ได้วันนี้

| ชั้น | ทำอะไร | ต้องมี remote ไหม |
|------|--------|-------------------|
| **1 — local gate** | `pre-push` hook รัน `check` | ❌ **ใช้ได้ทันที** |
| **2 — attestation** | ตรวจว่า MQL5 gate ถูกรันบน commit นี้ | ❌ ใช้ได้ทันที |
| **3 — CI จริง** | workflow บน runner | ✅ ต้องมี |

### 4.2 ชั้น 1 — `pre-push` ไม่ใช่ `pre-commit`

| hook | ทำไม |
|------|------|
| ~~`pre-commit`~~ | ช้าเกินไป · คนจะใช้ `--no-verify` จนเป็นนิสัย · commit ระหว่างทางควร commit ได้ |
| **`pre-push`** | ✅ จังหวะที่ควรสมบูรณ์แล้ว · รันไม่บ่อย · ยังเร็วพอ |

- `pre-push` รัน `python tools/task.py check`
- แดง → **บล็อกการ push** พร้อมบอกว่า target ไหนแดง
- ติดตั้งด้วย `python tools/task.py install-hooks` (ไม่ใช่อัตโนมัติ — hook ที่โผล่มาเองน่ากลัว)
- **`--no-verify` ยังข้ามได้** — นั่นคือธรรมชาติของ git · แต่ต้องเป็นการตัดสินใจที่รู้ตัว

### 4.3 ★★ ชั้น 2 — attestation คือคำตอบของ G3

CI รัน MQL5 ไม่ได้ **แต่ตรวจได้ว่ามีคนรันแล้ว**

`gate/mql5-latest.json` ([SPEC-065 §5.2](SPEC-065-mql5-test-harness.md)) มี `git_sha` อยู่

```
target ใหม่:  python tools/task.py mql5-attest

1. อ่าน gate/mql5-latest.json
2. ไฟล์ไม่มี                        → FAIL
3. overall != PASS                  → FAIL
4. git_sha != HEAD  และ  มีไฟล์ใน mt5-ea/** หรือ tests/mql5/** เปลี่ยน
   ตั้งแต่ commit ที่ attest ไว้    → FAIL  ★
5. นอกนั้น                          → PASS
```

**ข้อ 4 คือหัวใจ** — commit ที่แก้แต่ `docs/` หรือ `brain/` ไม่ต้องรัน MQL5 gate ใหม่
· แต่ทันทีที่แตะโค้ด MQL5 **ต้องรันใหม่ ไม่งั้น push ไม่ผ่าน**

`mql5-attest` ต้องอยู่ใน `check` → ชั้น 1 บังคับให้ชั้น 2 ทำงานโดยอัตโนมัติ

#### 🔴 ข้อจำกัดที่ต้องพูดตรงๆ

**นี่คือ attestation ไม่ใช่ proof** — คนแก้ JSON ด้วยมือได้

แต่มันเปลี่ยนสถานะของคำกล่าวอ้าง *"test ผ่าน"* จาก
**"ข้อความใน handoff ที่ตรวจไม่ได้"** → **"ไฟล์ที่ diff ได้ · มีประวัติใน git · และไม่ตรงเมื่อไรก็เห็น"**

การแก้มือจะปรากฏใน `git log` ว่าใครแก้ ตอนไหน โดยไม่มีการรัน gate คู่กัน
— ตรวจย้อนหลังได้ ต่างจากการเชื่อคำพูดซึ่งตรวจย้อนหลังไม่ได้เลย

**ทางเลือกที่แข็งกว่านี้คือ self-hosted runner (§4.4) ซึ่งต้องมี remote ก่อน**

### 4.4 ชั้น 3 — workflow (inert จนกว่าจะมี remote)

เขียนไฟล์ไว้ให้พร้อม 2 แบบ · **เจ้าของเลือกทีหลัง** ([D16](../backlog.md)):

| ไฟล์ | รันที่ไหน | ครอบอะไร |
|------|-----------|----------|
| `.github/workflows/check.yml` | GitHub-hosted (ubuntu) | Python ทั้งหมด + `mql5-attest` |
| `.github/workflows/mql5.yml` | **self-hosted** (เครื่อง Windows นี้) | รัน MQL5 gate จริง |

`mql5.yml` ต้องมี `if:` ที่ทำให้มัน **ไม่รันถ้าไม่มี runner** แทนที่จะค้าง

**`check.yml` ต้องรัน `mql5-attest` ด้วย** — นี่คือจุดที่ G3 ถูกปิดจริงแม้ไม่มี self-hosted runner

### 4.5 สิ่งที่ CI ตรวจ (ชั้น 3)

| ตรวจ | มาจาก |
|------|-------|
| `ruff check` | SPEC-002 |
| `mypy` | SPEC-002 |
| `pytest` (ไม่รวม `slow`/`live_terminal`/`mql5`/`db`) | SPEC-002 |
| `codegen-check` | [SPEC-004](SPEC-004-codegen.md) — **ต้องอยู่ตั้งแต่ commit แรก** |
| **`mql5-attest`** | §4.3 ★ |
| `contracts/schema` validate | schema ทุกไฟล์ parse + `$ref` resolve ได้ |

### 4.6 ต้องไม่ทำให้ `check` ช้าจนคนเลี่ยง

| target | งบเวลา |
|--------|--------|
| `lint` + `typecheck` | < 20 วินาที |
| `test` (fast) | < 60 วินาที |
| `codegen-check` | < 20 วินาที |
| `mql5-attest` | < 2 วินาที (อ่านไฟล์เฉยๆ) |
| **`check` รวม** | **< 2 นาที** |

เกินนี้ **ต้องรายงาน** — gate ที่ช้าคือ gate ที่ถูก `--no-verify`

---

## 5. Edge cases

1. **ไม่มี `gate/mql5-latest.json`** (repo ใหม่) → `mql5-attest` FAIL พร้อมบอกให้รัน gate
2. **แก้แต่ `docs/`** → `mql5-attest` PASS โดยไม่ต้องรัน MT5 (§4.3 ข้อ 4)
3. **แก้ `mt5-ea/` แล้วไม่ได้รัน gate** → **FAIL** ★
4. **`gate/mql5-latest.json` มี `overall: FAIL`** → FAIL แม้ `git_sha` จะตรง
5. **ไม่มี git remote** → workflow ไม่ทำงาน · **ชั้น 1–2 ยังทำงานปกติ**
6. **hook ยังไม่ติดตั้ง** → `check` ยังรันมือได้ · แต่ `install-hooks` ต้องบอกสถานะ
7. **รัน `check` บนเครื่องที่ไม่มี MT5/DB** → target ที่เกี่ยวข้อง `[SKIP]` · **`mql5-attest` ยังทำงาน**
   (อ่านไฟล์ ไม่ต้องมี MT5) ★
8. **`git diff` เทียบ commit ที่ attest ไว้ แต่ commit นั้นไม่มีแล้ว** (rebase) → FAIL พร้อมบอกให้รันใหม่

---

## 6. Acceptance criteria

- [ ] `python tools/task.py install-hooks` ติดตั้ง `pre-push` · บอกผลชัดเจน
- [ ] `pre-push` แดง → **push ถูกบล็อก** พร้อมบอก target ที่แดง
- [ ] `mql5-attest` อยู่ใน `check` และรันได้**บนเครื่องที่ไม่มี MT5** ★
- [ ] แก้ `docs/` อย่างเดียว → `mql5-attest` **PASS**
- [ ] **แก้ `mt5-ea/` แล้วไม่รัน gate → `mql5-attest` FAIL** ★★
- [ ] `gate/mql5-latest.json` ที่ `overall != PASS` → FAIL
- [ ] ไม่มีไฟล์ attestation → FAIL พร้อมบอกวิธีแก้
- [ ] `.github/workflows/check.yml` **มี `mql5-attest` เป็น step**
- [ ] `.github/workflows/mql5.yml` ไม่ค้างเมื่อไม่มี self-hosted runner
- [ ] `check` ทั้งชุด **< 2 นาที** — รายงานเวลาจริง
- [ ] `contracts/schema` validation อยู่ใน `check`
- [ ] `grep -rn "except:" tools/` — ไม่เจอ bare except

## 7. Test list — `tests/test_ci_gate.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_attest_passes_when_sha_matches` | |
| 2 | `test_attest_fails_when_overall_not_pass` | |
| 3 | `test_attest_fails_when_file_missing` | |
| 4 | `test_attest_passes_when_only_docs_changed` | ★ §4.3 ข้อ 4 |
| 5 | `test_attest_fails_when_mt5ea_changed_without_rerun` | ★★ หัวใจ |
| 6 | `test_attest_fails_when_tests_mql5_changed` | |
| 7 | `test_attest_works_without_mt5_installed` | ★ edge 7 |
| 8 | `test_attest_fails_when_attested_commit_missing` | edge 8 |
| 9 | `test_pre_push_hook_blocks_on_failure` | |
| 10 | `test_check_includes_attest` | |

**test 5 คือตัวที่ปิด G3** — ถ้าข้อนี้ผ่าน แปลว่าโค้ด MQL5 จะถูกแก้โดยไม่ผ่าน gate ไม่ได้

## 8. Files

**Touch:** `tools/task.py` · `tools/hooks/pre-push` · `.github/workflows/*.yml`
· `tests/test_ci_gate.py`

**ห้ามแตะ:** `tools/run-mql5-tests.ps1` (SPEC-065) · `contracts/**` · `docs/**`
· `mt5-ea/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| **Q1** | **สร้าง git remote ที่ไหน** (GitHub private / GitLab / Gitea ในเครื่อง) | 🔴 **เจ้าของตัดสิน — D16** · **ไม่บล็อก ticket นี้** (ชั้น 1–2 ใช้ได้เลย) |
| Q2 | ตั้ง self-hosted runner บนเครื่องนี้ไหม | 🟠 **เจ้าของตัดสิน** — ต้องมี remote ก่อน · ถ้าเอา จะได้ MQL5 gate อัตโนมัติจริง แทน attestation |
| Q3 | ควรบังคับ coverage ขั้นต่ำไหม | **ยังไม่ต้อง** — จำนวน test ที่ spec สั่งเป็นเกณฑ์ที่ตรงกว่า coverage % |

> **ไม่มีคำถามที่บล็อก — ชั้น 1 กับ 2 เริ่มได้ทันที**

---

## ภาคผนวก — ทำไม attestation ถึงคุ้มทั้งที่มันไม่ใช่ proof

ทางเลือกที่มีจริงตอนนี้มีแค่ 3 ทาง:

| | ทาง | สิ่งที่ได้ |
|---|-----|-----------|
| ก | เชื่อ handoff | ตรวจย้อนหลังไม่ได้เลย |
| **ข** | **attestation** | **ตรวจได้ · มีประวัติ · จับได้ถ้าไม่ตรง** |
| ค | self-hosted runner | พิสูจน์ได้จริง — **แต่ต้องมี remote ก่อน** |

ข ไม่ได้ดีเท่า ค แต่**ดีกว่า ก อย่างมีนัยสำคัญ** และ**ทำได้วันนี้โดยไม่ต้องรออะไรเลย**

ที่สำคัญกว่านั้น: ข กับ ค **ไม่ขัดกัน** — วันที่มี runner แล้ว runner จะเป็นคนเขียน
`gate/mql5-latest.json` เอง และ `mql5-attest` ก็ยังทำงานเหมือนเดิม
**โครงสร้างไม่ต้องรื้อ**

การเลือก ข วันนี้จึงไม่ใช่การยอมแพ้ แต่เป็นการวางรากที่ ค จะมาต่อได้พอดี
