# SPEC-002 — Repo scaffold + task runner + local gate

**Phase:** 0 · **Owner:** Codex · **Depends on:** — · **Blocks:** SPEC-004, SPEC-005, SPEC-006, SPEC-009, SPEC-013

---

## 1. Goal

ทำให้ฝั่ง Python เริ่มทำงานได้: ติดตั้ง dependency · lint · typecheck · test · เรียก gate
ด้วยคำสั่งเดียวที่**ใช้ได้จริงบนเครื่องนี้** และเป็นฐานให้ทุก ticket หลังจากนี้

## 2. Non-goals

- ❌ ห้ามตั้ง CI บน GitHub Actions — **G3 ยังไม่ตัดสิน** และยังไม่มี remote (SPEC-009)
- ❌ ห้ามแตะ `.gitignore` / `.gitattributes` — **มีอยู่แล้วและครบ** (§4.5)
- ❌ ห้ามเขียน generator/codegen — SPEC-004
- ❌ ห้าม implement logic ของ brain — แค่โครงว่าง
- ❌ ห้ามสร้าง `Makefile` — ดู §3.2 ★

---

## 3. Interface

### 3.1 ไฟล์ที่ต้องสร้าง

| ไฟล์ | หมายเหตุ |
|------|----------|
| `pyproject.toml` | project + deps + ruff + mypy + pytest config |
| `tools/task.py` | ★ task runner — **แทน Makefile** (§3.2) |
| `.env.example` | placeholder เท่านั้น ห้ามมีค่าจริง |
| `brain/__init__.py` + โครงโฟลเดอร์ | ตาม [README](../../README.md) |
| `research/` `ops/` โครงว่าง | `.gitkeep` |
| `docs/setup.md` | ขั้นตอนติดตั้งบนเครื่องเปล่า (รวมของที่ script ไม่ได้) |

### 3.2 ★ ไม่ใช้ `make` — เครื่องนี้ไม่มี และจะไม่มี

**ตรวจแล้ว 2026-07-28: `which make` → ไม่พบ**

และจะไม่ติดตั้งเพิ่มด้วยเหตุผลนี้:

| | |
|---|---|
| VPS ที่จะ deploy จริงเป็น **Windows** (MT5 รันได้แค่ Windows) | make ไม่ได้ช่วยอะไรเลย |
| ติด make บน Windows = PATH + shell quirks + อีก 1 ขั้นตอน setup | เพิ่มจุดพังโดยไม่ได้ประโยชน์ |
| Python เป็น dependency บังคับอยู่แล้ว | ใช้ Python เป็น runner ได้ฟรี |

> ⚠️ **แก้ spec ที่เขียนไปแล้ว:** [SPEC-004 §3.4](SPEC-004-codegen.md) และ
> [02-contracts §6](../02-contracts.md) เคยเขียนว่า `make codegen` — **เปลี่ยนเป็น
> `python tools/task.py codegen`** ทั้งหมด (Claude แก้เอกสารให้แล้ว)

### 3.3 `tools/task.py` — target ที่ต้องมี

```
python tools/task.py <target>
```

| target | ทำอะไร | ต้องผ่านเมื่อไร |
|--------|--------|-----------------|
| `install` | สร้าง `.venv` + `pip install -e ".[dev]"` | ครั้งแรก |
| `lint` | `ruff check .` | ทุก commit |
| `fmt` | `ruff format .` | ตามสะดวก |
| `typecheck` | `mypy` | ทุก commit |
| `test` | `pytest -m "not slow and not live_terminal and not mql5"` | ทุก commit |
| `test-all` | `pytest` ทั้งหมด | ก่อน handoff |
| `codegen` | เรียก `tools/codegen.py` (SPEC-004) | เมื่อ schema เปลี่ยน |
| `codegen-check` | `codegen` แล้ว `git diff --exit-code contracts/gen/` | ทุก commit |
| `mql5-gate` | เรียก `tools/run-mql5-tests.ps1` (Windows เท่านั้น) | ก่อน handoff |
| **`check`** | `lint` + `typecheck` + `test` + `codegen-check` | **ก่อน commit ทุกครั้ง** |
| **`check-full`** | `check` + `test-all` + `mql5-gate` | **ก่อน handoff ทุกครั้ง** |

**กฎของ runner:**
- target ที่ยังไม่มีของให้เรียก (เช่น `codegen` ก่อน SPEC-004 เสร็จ) → พิมพ์ `[SKIP] <target> -- <เหตุผล>` แล้ว **คืน exit 0**
- **`[SKIP]` ต้องปรากฏในสรุปท้าย** และห้ามดูเหมือน pass — กฎเดียวกับเป้า XM ใน MQL5 gate
- `check` ต้อง**รันทุก target ให้จบ** แล้วสรุปรวม ไม่ใช่หยุดที่ตัวแรกที่แดง
  (เห็นปัญหาทั้งหมดในรอบเดียว ดีกว่าไล่แก้ทีละรอบ)
- exit code: 0 = ผ่านหมด · 1 = มีตัวแดง · 2 = ตัว runner เองพัง

### 3.4 `pyproject.toml`

```toml
[project]
name = "ea-farm"
version = "0.1.0"
requires-python = ">=3.11,<3.14"     # ★ ดู §4.1
```

**dependency ที่ต้อง pin ด้วย `==`** (ห้าม `>=` — [SPEC-004 §4.1](SPEC-004-codegen.md) ต้องการ determinism):

| กลุ่ม | package |
|-------|---------|
| runtime | `pydantic` |
| dev | `pytest` · `pytest-asyncio` · `ruff` · `mypy` · **`psutil`** ← เพิ่ม rev.2 |
| codegen | อยู่ใน `requirements-codegen.txt` ที่ SPEC-004 สร้าง — **อย่าย้ายเข้ามา** |

> **rev.2 (2026-08-01) — เพิ่ม `psutil`**
> [SPEC-067 §3.1](SPEC-067-memory-soak.md) ใช้ `psutil.memory_info().private` เป็น**ตัวตัดสิน**
> ของ soak · §5 กรณี 5 สั่งให้ `exit 3` ถ้าไม่มี — ซึ่งแปลว่า **ถ้าไม่ประกาศที่นี่ soak รันไม่ได้เลย**
> · อยู่กลุ่ม `dev` เพราะ production path ไม่ใช้

**import mapping ที่ต้องตั้ง** — `contracts/gen/python/` ต้อง import ได้โดยไม่ต้องเขียน
`from contracts.gen.python.models import ...` ซึ่งอ่านไม่รู้เรื่อง:

```toml
[tool.setuptools.package-dir]
farm_contracts = "contracts/gen/python"
```
→ `from farm_contracts.models import BarPayload`

**ห้ามใส่ `contracts/__init__.py`** — `contracts/` เก็บ JSON schema ด้วย ไม่ใช่ package

### 3.5 ruff / mypy / pytest config

**ruff** — rule set ขั้นต่ำ:

| rule | ทำไม |
|------|------|
| `E`, `F`, `W` | พื้นฐาน |
| `I` | isort — กัน diff เน่าเพราะลำดับ import |
| `B` | bugbear |
| **`E722`** | ★ **bare `except:`** — [AGENTS ข้อ 10](../../AGENTS.md) "risk path ต้อง fail-closed" |
| `ASYNC` | เตรียมไว้ให้ gateway (SPEC-013) |

**mypy** — `strict = true` เป็นค่าเริ่มต้นทั้งรีโป
ผ่อนได้เฉพาะ `research/**` (งาน exploratory) · **`brain/risk/**` ผ่อนไม่ได้เด็ดขาด**

**pytest marker ที่ต้องประกาศ** (ไม่งั้น `-m` จะ warn):

| marker | ความหมาย | อยู่ใน `test` ปกติไหม |
|--------|----------|----------------------|
| `slow` | > 60 วินาที (soak 1 ชม.) | ❌ |
| `live_terminal` | ต้องมี MT5 เปิด EA จริง (chaos suite) | ❌ |
| `mql5` | ต้องมี MetaEditor | ❌ |

3 marker นี้มาจากข้อจำกัดจริงที่ตัดสินไปแล้วใน
[work-order §1.5](../work-order.md) — ห้ามเปลี่ยนความหมาย

### 3.6 `.env.example`

```bash
# ห้ามใส่ค่าจริงในไฟล์นี้ (AGENTS ข้อ 4) — ก๊อปเป็น .env แล้วเติมเอง
FARM_TOKEN=changeme
FARM_GATEWAY_HOST=127.0.0.1
FARM_GATEWAY_PORT=9101
FARM_DB_URL=postgresql://farm:changeme@localhost:5432/farm
FARM_LOG_LEVEL=INFO
# Phase 2 — ยังไม่ใช้
FARM_TELEGRAM_BOT_TOKEN=
FARM_TELEGRAM_CHAT_ID=

# rev.2 — ปิด T8: path ของเครื่อง ห้าม hardcode ในโค้ดอีก
EA_FARM_REPO=D:\ea-farm
EA_FARM_CHAOS_PORT=45001
EA_FARM_MT5_DATA_DIR=
EA_FARM_MT5_COMMON_DIR=
```

`.gitignore` กัน `.env` ไว้แล้ว และ `!.env.example` ยกเว้นไฟล์นี้ไว้แล้ว — **ตรวจว่ายังจริง**

> ### rev.2 (2026-08-01) — 4 ตัวล่างคือการปิด **T8**
>
> `D:\ea-farm` ถูก hardcode อยู่ **3 ที่** (`run-chaos.ps1:14` · `compile-gate.ps1:18` ·
> `run-mql5-tests.ps1:34`) และ path ของ MT5 อีก **4 ที่** (`live_mt5_harness.py:22-25` ·
> `test_wire_resilience.py:32`) — **ตัวหลังมีชื่อผู้ใช้ Windows อยู่บน remote สาธารณะ**
>
> | กฎ | |
> |----|--|
> | ทุก path ที่ขึ้นกับเครื่อง **ต้องอ่านจาก env** | มี default ได้ แต่ต้องมีที่เดียว |
> | ฝั่ง Python | helper เดียวใน `tests/chaos/live_mt5_harness.py` แล้ว `import` ไปใช้ |
> | ฝั่ง PowerShell | อ่าน `.env` หรือรับเป็นพารามิเตอร์ · **ห้ามประกาศซ้ำในแต่ละสคริปต์** |
>
> `EA_FARM_MT5_*` เว้นว่างได้ — ว่าง = ใช้ค่า default ที่ helper รู้จัก
> · **ห้ามใส่ค่าจริงของเครื่องใครลงไฟล์นี้** (ยังอยู่ใต้กฎ "placeholder เท่านั้น")

### 3.7 โครงโฟลเดอร์ตาม README

```
brain/{gateway,signal,regime,news,risk,store,common}/__init__.py
research/{ingest,features,backtest,registry}/.gitkeep
ops/.gitkeep
tests/{chaos,mql5,risk_scenarios}/
```
`brain/gateway/echo_server.py` **มีอยู่แล้ว — ห้ามแตะ**

---

## 4. Behaviour / การตัดสินใจที่ต้องทำตาม

### 4.1 Python version — เครื่องนี้มี 3.13 กับ 3.14

ตรวจแล้ว: `Python313` และ `Python314` (ไม่มี 3.11/3.12 แบบ system-wide)

| | |
|---|---|
| **ใช้ 3.13** | ✅ แนะนำ — ecosystem รองรับครบ |
| ใช้ 3.14 | ⚠️ ใหม่เกิน · `datamodel-code-generator` (SPEC-004) อาจยังไม่รองรับ |

`requires-python = ">=3.11,<3.14"` → **กัน 3.14 ออกตั้งแต่ตอน install**
ไม่ใช่ให้ไปพังตอน SPEC-004

**ต้องรายงานใน handoff:** เวอร์ชันเป๊ะที่ใช้ (`python -V`) และ path ของ interpreter
· ปัญหา "pytest คนละตัวกับ python" เคยเกิดบนเครื่องนี้แล้ว

### 4.2 `check` ต้องรันทุกตัวแล้วค่อยสรุป

```
$ python tools/task.py check
[ OK ] lint
[FAIL] typecheck -- 3 errors
[ OK ] test (24 passed)
[SKIP] codegen-check -- tools/codegen.py ยังไม่มี (SPEC-004)

check: FAILED (1 failed, 1 skipped)
```

**ห้ามหยุดที่ตัวแรกที่แดง** — คนจะได้เห็นปัญหาทั้งหมดในรอบเดียว

### 4.3 `[SKIP]` ห้ามนับเป็นผ่าน

ตอนนี้ `codegen` / `codegen-check` / บาง test จะ skip เพราะของยังไม่มี
สรุปท้ายต้องบอกจำนวน skip เสมอ · **exit 0 ได้ แต่ต้องเห็นว่าอะไรถูกข้าม**

เหตุผลเดียวกับเป้า XM ใน MQL5 gate: gate ที่ข้ามเงียบๆ = gate ที่โกหก

### 4.4 `mql5-gate` บนแพลตฟอร์มที่ไม่ใช่ Windows

`[SKIP] mql5-gate -- ต้องใช้ Windows + MetaEditor` แล้ว exit 0
(เตรียมไว้เผื่อรันบน Linux ในอนาคต — ตอนนี้ยังไม่มี แต่ตรรกะต้องรองรับ)

### 4.5 `.gitignore` / `.gitattributes` — **มีอยู่แล้ว ห้ามเขียนทับ**

ทั้งสองไฟล์เขียนไว้ครบตั้งแต่ commit แรก รวมทั้ง:
- `.env` ถูกกัน · `!.env.example` ยกเว้นไว้
- `contracts/gen/` **ไม่ได้** ถูก ignore (ต้อง commit ตาม [02-contracts §6](../02-contracts.md))
- `* text=auto eol=lf` — จำเป็นเพราะ wire protocol ใช้ `\n` เท่านั้น

**หน้าที่ของ ticket นี้คือ *ตรวจสอบ* ว่ายังจริง ไม่ใช่เขียนใหม่**
ถ้าต้องเพิ่มบรรทัด → **ระบุในรายงานว่าเพิ่มบรรทัดไหนและทำไม**

### 4.6 `docs/setup.md` — ต้องมีของที่ script ไม่ได้ด้วย

ไม่ใช่แค่ `pip install` — ต้องรวมขั้นตอนที่**อัตโนมัติไม่ได้** ซึ่งตอนนี้มีอย่างน้อย:

| ขั้นตอน | ทำไม script ไม่ได้ |
|---------|-------------------|
| MT5 socket whitelist (`127.0.0.1`) | `config\settings.ini` **เข้ารหัส** → GUI เท่านั้น ([work-order §1.5](../work-order.md)) |
| terminal ต้อง login บัญชีไว้ก่อน | credential ห้ามอยู่ในรีโป (AGENTS ข้อ 4) |
| path ของ terminal 2 ตัว (IUX / XM) | ต่างกันทุกเครื่อง |

> `docs/setup.md` เป็นไฟล์ใน `docs/` ซึ่ง **Claude เป็นเจ้าของ**
> → Codex เขียน **ร่างส่งมาใน handoff** แล้ว Claude เอาลงไฟล์ให้
> (นี่เป็นข้อยกเว้นเดียวใน ticket นี้ — ห้าม commit `docs/` เอง)

---

## 5. Edge cases

1. **`.venv` มีอยู่แล้วแต่เป็น Python คนละเวอร์ชัน** → ตรวจแล้วเตือน ห้ามใช้ต่อเงียบๆ
2. **รัน `task.py` จากโฟลเดอร์อื่น** → ต้องหา repo root เอง (จาก `__file__`) ห้ามพึ่ง cwd
3. **`git diff --exit-code` ตอนไม่มี `contracts/gen/`** → นับเป็น skip ไม่ใช่ fail
4. **ruff/mypy ยังไม่ติดตั้ง** → `[SKIP]` + บอกให้รัน `install` ก่อน ไม่ใช่ traceback
5. **`tools/run-mql5-tests.ps1` คืน exit 1** → `mql5-gate` ต้องคืน 1 ตาม **ห้ามกลืน**
6. **PowerShell ไม่มี** (Linux) → skip ตาม §4.4
7. **`brain/gateway/echo_server.py` มีอยู่แล้ว** → `__init__.py` ที่เพิ่มต้องไม่ทำให้ import พัง

---

## 6. Acceptance criteria

- [ ] `python tools/task.py install` สำเร็จบนเครื่องเปล่าที่มี Python 3.13
- [ ] `python tools/task.py check` รันได้และ**พิมพ์ผลทุก target** พร้อมสรุปท้าย
- [ ] `check` **ไม่หยุดที่ตัวแรกที่แดง** (ทดสอบด้วยการทำให้ lint แดงโดยตั้งใจ)
- [ ] `[SKIP]` ปรากฏพร้อมเหตุผล และนับแยกจาก pass ในสรุป
- [ ] `python tools/task.py mql5-gate` เรียก ps1 จริง และ**คืน exit code เดิม**
- [ ] `python -c "import brain"` ผ่าน
- [ ] `python -c "import farm_contracts"` → ผิดพลาดอย่างมีความหมาย (ยังไม่มี gen)
      **ไม่ใช่** `ModuleNotFoundError` ที่บอกอะไรไม่ได้ — mapping ต้องตั้งถูกรอไว้แล้ว
- [ ] `ruff check .` ผ่านบนโค้ดที่มีอยู่ (`echo_server.py`)
- [ ] `mypy` ผ่านบนโค้ดที่มีอยู่
- [ ] `pytest` เก็บ test เดิมได้ และ marker 3 ตัวประกาศครบ (ไม่มี warning)
- [ ] `grep -rn "except:" brain/ tests/` — **ไม่เจอ bare except** (ruff `E722` ต้องจับได้)
- [ ] `.env.example` **ไม่มีค่าจริงแม้แต่ตัวเดียว** · `git check-ignore .env` ต้องบอกว่า ignore
- [ ] **ไม่มีไฟล์ชื่อ `Makefile`** ในรีโป
- [ ] ร่าง `docs/setup.md` ส่งมาใน handoff (Codex ไม่ commit เอง)

## 7. Test list — `tests/test_task_runner.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_check_runs_all_targets_even_when_one_fails` | ★ §4.2 |
| 2 | `test_skip_is_reported_and_not_counted_as_pass` | ★ §4.3 |
| 3 | `test_exit_code_1_when_any_target_fails` | |
| 4 | `test_exit_code_0_when_only_skips` | |
| 5 | `test_finds_repo_root_from_any_cwd` | edge 2 |
| 6 | `test_mql5_gate_propagates_exit_code` | edge 5 — ห้ามกลืน |
| 7 | `test_missing_tool_reports_skip_not_traceback` | edge 4 |
| 8 | `test_env_example_has_no_real_values` | สแกนหาค่าที่ไม่ใช่ placeholder |
| 9 | `test_pytest_markers_declared` | ไม่มี unknown-marker warning |

## 8. Files

**Touch:** ตาม §3.1 ยกเว้น `docs/setup.md` (ส่งร่างมา)

**ห้ามแตะ:** `.gitignore` · `.gitattributes` (ตรวจได้ แก้ต้องรายงาน) ·
`brain/gateway/echo_server.py` · `docs/**` · `contracts/schema/**` · `AGENTS.md` · `CLAUDE.md`
· `tools/run-mql5-tests.ps1` (เรียกได้ ห้ามแก้ใน ticket นี้)

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | ใช้ `setuptools` หรือ `hatchling`? | **ไม่บล็อก — เลือกเอง** · ขอแค่ `package-dir` mapping ของ `farm_contracts` ทำงาน · รายงานว่าเลือกอะไร |
| Q2 | `install` ควรสร้าง `.venv` เองหรือให้คนทำ? | **ไม่บล็อก** — สร้างเองได้ แต่ถ้ามีอยู่แล้วและเวอร์ชันไม่ตรง **ต้องเตือน ห้ามลบทิ้งเอง** |
| Q3 | ต้องมี pre-commit hook ไหม? | **ยังไม่ต้อง** — `check` ก่อน commit พอ · hook เก็บไว้คู่กับ SPEC-009 ตอน G3 ตัดสินแล้ว |

> **ไม่มีคำถามที่บล็อก — เริ่มได้ทันที ไม่ต้องรอ ticket อื่น**

---

## ภาคผนวก — ทำไม `check` สำคัญกว่าที่ดู

**G3 ยังไม่ตัดสิน + ไม่มี git remote** → ตอนนี้ **ไม่มี CI เลย**
สิ่งเดียวที่กันของเสียเข้ารีโปได้คือคนรัน gate ก่อน commit

`check` จึงไม่ใช่ "ของอำนวยความสะดวก" แต่เป็น **CI ทั้งหมดที่โปรเจกต์นี้มี ณ ตอนนี้**
— และเพราะมันพึ่งวินัยล้วน มันต้อง**เร็วพอที่จะรันทุกครั้ง** (ไม่งั้นจะถูกข้าม)
นี่คือเหตุผลที่ `slow` / `live_terminal` / `mql5` ถูกแยกออกจาก `test` ปกติ
