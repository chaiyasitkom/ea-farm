# SPEC-028 — Ops dashboard v1 + kill switch

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-006, SPEC-014, SPEC-023
**Blocks:** SPEC-030b (runbook) · **อ้าง:** [risk-spec §Ops Dashboard](../03-risk-spec.md) · [roadmap Phase 2 exit](../04-roadmap.md) · [G4](../06-gap-audit.md)

---

## 1. Goal

หน้าจอเดียวที่ตอบได้ว่า **"ตอนนี้ฟาร์มปลอดภัยอยู่ไหม"** ภายใน 5 วินาทีที่มอง
และ **ปุ่มหยุดทุกอย่าง** ที่ทำงานได้**แม้ brain ตายไปแล้ว**

จบ ticket นี้ = ปิดเกณฑ์ Phase 2 exit ข้อ *"kill switch flatten ≤ 5s"*

## 2. Non-goals

- ❌ ห้ามมีปุ่มที่**ผ่อน**อะไรได้เลย — ไม่มีปุ่ม "resume" · ไม่มีปุ่มปรับ limit ★★
- ❌ ห้ามส่ง order / intent จาก dashboard
- ❌ ห้ามใช้ JS framework ที่ต้อง build step (React/Vue/bundler) — ดู §3.2
- ❌ ห้ามทำ auth ระบบผู้ใช้หลายคน (Phase 6 ค่อยคิด)
- ❌ ห้าม implement Telegram alert (SPEC-029) · watchdog (SPEC-062)
- ❌ ห้ามแตะตรรกะ risk — dashboard **อ่าน** DB เท่านั้น

---

## 3. Interface

### 3.1 ★★ dashboard ต้องเป็น process แยกจาก brain

```
                 ┌──────────────┐
   PostgreSQL ◄──┤  gateway     │  (brain: SPEC-013)
        ▲        └──────────────┘
        │  read-only
        │        ┌──────────────┐
        └────────┤  dashboard   │  ★ process แยก · ไม่ import brain · ไม่ต่อ gateway
                 └──────┬───────┘
                        │ เขียนไฟล์ตรง
                        ▼
        <terminal>\MQL5\Files\Common\farm_kill.txt   (R13 · SPEC-023)
```

| ข้อบังคับ | เหตุผล |
|-----------|--------|
| **ห้าม `import` จาก `brain/gateway/` หรือ `brain/risk/`** | dashboard ต้องเปิดดูได้ตอน brain crash — ถ้าแชร์โค้ดกัน bug เดียวกันจะฆ่าทั้งคู่ |
| **ห้ามต่อ gateway ผ่าน socket** | เหตุผลเดียวกัน |
| อ่าน DB **read-only** (`GRANT SELECT` เท่านั้น) | dashboard เขียน DB ไม่ได้ = ทำข้อมูล audit เสียไม่ได้ |
| kill switch **เขียนไฟล์ตรง ไม่ผ่าน brain** | ★★ ถ้าต้องผ่าน brain สวิตช์ฉุกเฉินจะตายพร้อม brain |

> นี่คือหลักการเดียวกับ [G2](../06-gap-audit.md)/[SPEC-062](SPEC-062-watchdog.md):
> **ของที่มีไว้ใช้ตอนระบบพัง ต้องไม่พึ่งของที่พัง**

### 3.2 Stack — ตัดสินแล้ว ห้ามเปลี่ยนโดยไม่เปิด ticket

| | เลือก | ทำไมไม่เอาอย่างอื่น |
|---|-------|---------------------|
| server | **FastAPI** (มีอยู่แล้วจาก SPEC-013) | — |
| หน้าเว็บ | **Jinja2 server-rendered + `<meta http-equiv="refresh" content="5">`** | SPA ต้องมี node/bundler บนเครื่องที่ไม่มี Docker · เพิ่มชิ้นส่วนที่พังได้ตอนตี 3 เพื่อ UI ที่ไม่ได้ดีขึ้น |
| chart | **ไม่มี** ใน v1 — ตัวเลข + ตาราง + แถบ % | equity curve เป็น v2 · Phase 2 ต้องการ "ปลอดภัยไหม" ไม่ใช่ "สวยไหม" |
| bind | **`127.0.0.1` เท่านั้น** + `DASHBOARD_TOKEN` ใน header/query | VPS ที่เปิด 0.0.0.0 พร้อมปุ่ม flatten = ของขวัญให้คนอื่น |

`refresh 5s` ทำให้หน้าจอ**ไม่มี state ฝั่ง client เลย** — รีเฟรชคือความจริงใหม่ทุกครั้ง

### 3.3 Endpoint

| method | path | ทำอะไร |
|--------|------|--------|
| `GET` | `/` | หน้าเดียวรวมทุกอย่าง §4.1 |
| `GET` | `/health` | `{"ok":true,"db":true,"newest_state_age_sec":N}` — ให้ SPEC-062 เรียก |
| `POST` | `/kill/arm` | ชั้นที่ 1 — คืน `arm_token` อายุ **30 วินาที** |
| `POST` | `/kill/confirm` | ชั้นที่ 2 — ต้องมี `arm_token` + พิมพ์คำว่า `FLATTEN` ตรงตัว |
| `POST` | `/kill/status` | คืนสถานะไฟล์ kill ของทุก terminal |

**ไม่มี endpoint สำหรับปลด kill** — ปลดด้วยมือตาม [SPEC-023 §4.2](SPEC-023-safemode.md) เท่านั้น
(ลบไฟล์ **และ** ลบ `GlobalVariable farm_killhalt_*` ทุกตัว) · จะเขียนลง runbook SPEC-030b

---

## 4. Behaviour

### 4.1 หน้าเดียว — 6 บล็อกเรียงตามลำดับที่ต้องมอง

| ลำดับ | บล็อก | แหล่ง | เกณฑ์สี |
|-------|-------|-------|---------|
| 1 | **แถบสถานะรวม** — `SAFE` / `WARN` / `BREACH` / `STALE` | คำนวณ §4.2 | เขียว/เหลือง/แดง/**เทา** |
| 2 | **ปุ่ม KILL** | — | แดงเสมอ · อยู่บนสุดที่มองเห็นโดยไม่ต้องเลื่อน ★ |
| 3 | **Farm equity + DD ปัจจุบัน เทียบ limit** (แสดงเป็น **% ของ limit** ไม่ใช่ % ดิบ) | `account_state` | ≥ 60% ของ limit = เหลือง · ≥ 90% = แดง |
| 4 | **ตารางทุก session** — heartbeat อายุ · day P/L · guard mode · จำนวน position · `foreign_position_count` · `internal_hedge_detected` | `account_state` แถวล่าสุดต่อ session | heartbeat > 30s = แดง (P11) · `foreign > 0` หรือ `hedge` = แดง |
| 5 | **Net currency exposure** — ตารางสกุล → % | `account_state.owned_net` | เกิน P3 = แดง |
| 6 | **Risk events 24 ชม.** | `risk_events` | `BREACH` = แดง |

> ข้อ 3 **ต้องเป็น % ของ limit** — *"DD 4.2%"* ต้องคิดในหัวว่าเพดานเท่าไร
> *"70% ของเพดาน"* อ่านแล้วรู้ทันที · ตอนตี 3 ไม่มีใครคิดเลขได้

**ข้อ 7 ของ risk-spec (champion vs challenger) ตัดออกจาก v1** — Phase 5 ค่อยมี ยังไม่มีข้อมูล

### 4.2 ★★ `STALE` ต้องแยกจาก `SAFE` ให้ขาด

```
newest(account_state.ts) เก่ากว่า 30 วินาที  →  STALE (เทา)  ไม่ใช่ SAFE
```

| ถ้าทำผิด | ผลจริง |
|----------|--------|
| ข้อมูลค้าง 6 ชม. แต่ตัวเลขสุดท้ายดูดี → แสดงเขียว | คนดูคิดว่าปกติ ทั้งที่ **ไม่มีใครรายงานมา 6 ชม.** |

นี่คือ bug class เดียวกับ [G1](../06-gap-audit.md) / [02-contracts §8.2](../02-contracts.md):
**ข้อมูลหายกลายเป็นไฟเขียว** · dashboard เป็นที่ที่ bug นี้แพงที่สุดเพราะมันคือสิ่งที่คนใช้ตัดสินใจ

**`STALE` ต้องเด่นเท่า `BREACH`** — ไม่ใช่ตัวหนังสือเล็กๆ มุมจอ

### 4.3 ★★ Kill switch — สองชั้น และต้องทำงานตอนทุกอย่างพัง

```
ชั้น 1  POST /kill/arm      → arm_token (อายุ 30 วิ) + หน้าจอเปลี่ยนเป็นโหมดยืนยัน
ชั้น 2  POST /kill/confirm  → ต้องส่ง arm_token + พิมพ์ "FLATTEN" ตรงตัว
        → เขียน farm_kill.txt ลง Common\Files ของ **ทุก terminal ใน config**
```

| กฎ | เหตุผล |
|----|--------|
| ต้อง**พิมพ์**คำว่า `FLATTEN` ไม่ใช่แค่กดยืนยัน | กันกดพลาด · กันคลิกรัว |
| `arm_token` หมดอายุ 30 วินาที | armed ค้างไว้ข้ามคืนแล้วมีคนมากดต่อ = อุบัติเหตุ |
| เขียนไฟล์ **ทุก terminal** ถึงจะถือว่าสำเร็จ | เขียนได้ 3 จาก 4 = **ยังไม่หยุด** → ต้องรายงานว่าล้มเหลว ★★ |
| เนื้อไฟล์: `ts_utc` · ผู้กด · เหตุผลที่พิมพ์ (ถ้ามี) | ให้สืบย้อนได้ · แต่ **EA ไม่อ่านเนื้อ** ([SPEC-023 Q1](SPEC-023-safemode.md)) |
| เขียนไฟล์แล้ว **fsync** | ไฟล์ที่ยังอยู่ใน buffer ตอนไฟดับ = ไม่ได้กด |
| ล้มเหลวบาง terminal | แสดง **แดง** + รายชื่อ terminal ที่เขียนไม่ได้ + **บอกให้ทำมือ** พร้อม path เต็ม ★★ |

**ห้ามส่ง `RISK_DIRECTIVE FLATTEN` แทนการเขียนไฟล์** — directive ต้องผ่าน brain + socket
ซึ่งเป็นสองอย่างที่อาจตายอยู่ตอนที่ต้องกดปุ่มนี้พอดี
· ถ้า brain ยังอยู่ SPEC-025 จะส่ง directive ของมันเองอยู่แล้ว **สองทางไม่ขัดกัน**

### 4.4 วัดว่า ≤ 5 วินาทีจริงไหม

เกณฑ์ Phase 2 exit คือ *"kill switch flatten ≤ 5s"* — ต้องวัด **ปลายถึงปลาย**:

```
t0 = /kill/confirm ตอบ 200
t1 = exec_reports แถวสุดท้ายที่ปิด position สุดท้าย (ts)
ต้อง t1 − t0 ≤ 5.0 วินาที
```

**ห้ามวัดแค่ "เขียนไฟล์เสร็จ"** — นั่นวัดตัวเอง ไม่ได้วัดสิ่งที่เกณฑ์ถาม
· ต้องมีอย่างน้อย 1 position เปิดอยู่ตอนทดสอบ ไม่งั้นไม่ได้พิสูจน์อะไร
· รายงาน**ตัวเลขจริง**ใน handoff ไม่ใช่ "ผ่าน"

### 4.5 Auth

| | |
|---|---|
| bind | `127.0.0.1` เท่านั้น — อ่านจาก `.env` `DASHBOARD_BIND` |
| token | `DASHBOARD_TOKEN` จาก `.env` · ทุก endpoint ตรวจ · **เทียบด้วย `secrets.compare_digest`** |
| ไม่มี token ใน `.env` | **ไม่สตาร์ท** — ห้าม default เป็นค่าว่างหรือ `admin` ★ |
| `POST /kill/*` | ตรวจ token ซ้ำอีกครั้งเสมอ แม้ session เดิม |

---

## 5. Edge cases

1. **DB ล่ม** — หน้าเว็บต้องยังขึ้น แสดง `STALE` + ข้อความว่าต่อ DB ไม่ได้
   · **ปุ่ม kill ต้องยังกดได้** (ไม่พึ่ง DB) ★★
2. **ยังไม่มี session ไหนเลย** — แสดง `STALE` ไม่ใช่ `SAFE`
3. **มีไฟล์ kill อยู่แล้ว** — แถบบนสุดขึ้น `KILLED` + เวลาที่กด + **วิธีปลดตาม runbook**
4. **terminal path ใน config ไม่มีอยู่จริง** — นับเป็นเขียวไม่ได้ → รายงานว่าล้มเหลว (§4.3)
5. **สอง tab กด arm พร้อมกัน** — `arm_token` แยกกัน ต่างคนต่างใช้ได้ · ไม่ต้อง lock
6. **นาฬิกาเครื่อง dashboard เพี้ยน** — อายุ heartbeat คำนวณจาก `now() - ts` ของ **DB**
   (`SELECT now()`) ไม่ใช่นาฬิกา Python ★
7. **`owned_net` เป็น `NULL`** — แสดง `—` ห้ามแสดง `0` (แยก "ไม่มีข้อมูล" จาก "ไม่มีไม้")
   · [02-contracts §8.2](../02-contracts.md)
8. **จอมือถือ** — บล็อก 1–2 ต้องอ่านได้และกดได้บนจอแคบ (runbook มีเคส "ปิดด่วนตอนไม่มีคอม")

---

## 6. Acceptance criteria

- [ ] `grep -rn "from brain.gateway\|from brain.risk\|import brain" brain/dashboard/` — **ไม่เจอ** ★★
- [ ] ปิด gateway ทิ้ง → dashboard ยังเปิดได้ · ยังกด kill ได้ · แสดง `STALE` ★★
- [ ] หยุด PostgreSQL → หน้าเว็บยังขึ้น · **ปุ่ม kill ยังทำงาน** ★★
- [ ] ข้อมูลเก่ากว่า 30s → `STALE` (เทา) **ไม่ใช่** `SAFE` ★★
- [ ] kill: กดชั้นเดียวไม่พอ · `arm_token` หมดอายุ 30s แล้วใช้ไม่ได้ · พิมพ์ผิดคำไม่ผ่าน
- [ ] kill เขียนไฟล์ครบ**ทุก** terminal ถึงรายงานสำเร็จ · ขาดตัวเดียว = **แดง + path ให้ทำมือ** ★★
- [ ] **วัด end-to-end ได้ ≤ 5.0 วินาที** โดยมี position เปิดอยู่จริง — รายงานตัวเลข ★★
- [ ] DB user ของ dashboard มีแค่ `SELECT` — พิสูจน์ด้วย `INSERT` แล้วต้อง permission denied ★
- [ ] ไม่มี `DASHBOARD_TOKEN` → **ไม่สตาร์ท**
- [ ] `grep -rn "0\.0\.0\.0" brain/dashboard/` — ไม่เจอ (ยกเว้นใน comment ที่อธิบายว่าห้าม)
- [ ] **ไม่มี endpoint หรือปุ่มใดที่ผ่อนข้อจำกัด** — ตรวจด้วยการอ่าน route ทั้งหมด ★★
- [ ] อายุ heartbeat คำนวณจาก `SELECT now()` ของ DB ไม่ใช่นาฬิกา Python
- [ ] `ruff` + `mypy` ผ่าน · `pytest` ผ่าน

## 7. Test list — `tests/unit/test_dashboard.py` + `tests/integration/test_kill_switch.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_stale_when_newest_state_older_than_30s` | ★★ §4.2 |
| 2 | `test_stale_when_no_sessions_at_all` | edge 2 |
| 3 | `test_status_is_breach_when_any_session_breached` | §4.1 |
| 4 | `test_dd_shown_as_pct_of_limit` | §4.1 |
| 5 | `test_page_renders_when_db_down` | ★★ edge 1 |
| 6 | `test_kill_works_when_db_down` | ★★ edge 1 |
| 7 | `test_kill_requires_arm_then_confirm` | §4.3 |
| 8 | `test_arm_token_expires_after_30s` | §4.3 |
| 9 | `test_confirm_requires_exact_word_flatten` | §4.3 |
| 10 | `test_kill_fails_loudly_when_one_terminal_unwritable` | ★★ §4.3 |
| 11 | `test_kill_file_content_has_timestamp_and_actor` | §4.3 |
| 12 | `test_no_route_can_relax_anything` | ★★ วน route ทั้งหมด · whitelist เฉพาะ GET + /kill/* |
| 13 | `test_missing_token_refuses_to_start` | §4.5 |
| 14 | `test_token_compared_with_compare_digest` | §4.5 |
| 15 | `test_heartbeat_age_uses_db_clock` | edge 6 |
| 16 | `test_null_owned_net_renders_dash_not_zero` | edge 7 |
| 17 | `test_kill_to_flat_within_5s` | ★★ §4.4 · integration · ต้องมี position จริง |

**test 5 · 6 · 10 · 12 · 17 คือห้าตัวที่ห้ามพลาด** — 5/6 คือ "ใช้ได้ตอนพัง" ·
10 คือ "ไม่โกหกว่าหยุดแล้ว" · 12 คือ "ไม่มีทางเผลอผ่อน" · 17 คือเกณฑ์ Phase 2 exit

## 8. Files

**Touch:** `brain/dashboard/` (ใหม่ทั้งโฟลเดอร์: `app.py` · `queries.py` · `kill.py` ·
`templates/index.html`) · `tests/unit/test_dashboard.py` · `tests/integration/test_kill_switch.py`
· `.env.example` (`DASHBOARD_BIND` · `DASHBOARD_TOKEN` · `TERMINAL_COMMON_PATHS`)
· `tools/task.py` (คำสั่ง `dashboard`)

**ห้ามแตะ:** `brain/gateway/**` · `brain/risk/**` · `mt5-ea/**` · `contracts/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | รายชื่อ terminal มาจากไหน | **ตอบแล้ว:** `.env` `TERMINAL_COMMON_PATHS` (คั่นด้วย `;`) · เป็นค่าเดียวกับที่ [chaos review C11](../reviews/SPEC-016-chaos-01.md) บอกให้เลิก hardcode ใน `run-mql5-tests.ps1` — **ปิดหนี้ข้อนั้นไปในตัว** |
| Q2 | ควรมีเสียงเตือนบนหน้าเว็บไหม | **ไม่ใน v1** — คนไม่ได้เฝ้าจอ นั่นคืองานของ SPEC-029 Telegram |
| Q3 | เก็บ log ว่าใครกด kill ที่ไหน | **ในไฟล์ kill + stdout log ของ dashboard** · ยังไม่เขียน DB เพราะ §3.1 บังคับ read-only · ถ้าอยากได้ตาราง `kill_events` → ticket ใหม่ |

---

## ภาคผนวก — ทำไมปุ่ม kill ถึงไม่ควรฉลาด

สิ่งที่ยั่วใจที่สุดของ ticket นี้คือทำให้ปุ่มนี้ "ฉลาดขึ้น": ถามยืนยันผ่าน Telegram ·
ตรวจว่ามี position ไหม · เลี่ยงกดตอนตลาดปิด

**ทุกอย่างที่เพิ่มเข้าไปคือสิ่งที่อาจไม่ทำงานในวันที่ต้องกด**

ปุ่มนี้มีหน้าที่เดียว: **เขียนไฟล์ให้ครบทุกเครื่อง แล้วบอกความจริงว่าเขียนได้กี่เครื่อง**
· ตรรกะที่เหลือทั้งหมดอยู่ใน EA ซึ่งเป็นที่ที่มันทำงานได้แม้เน็ตหลุด
([SPEC-023 ภาคผนวก](SPEC-023-safemode.md))
