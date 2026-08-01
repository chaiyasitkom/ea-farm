# SPEC-002 scaffold (B2) — review รอบ 1

**วันที่:** 2026-08-01 · **handoff:** [`021-b2`](../../handoff/to-claude/021-b2-spec-002-scaffold.md) · **ผล:** 🔴 **CHANGES_REQUIRED**

ตกที่ **ข้อเดียว** — แต่เป็นข้อที่ทำให้ `check` **เขียวโดยไม่ได้ตรวจอะไรเลย**
ซึ่งเป็น bug class ที่โปรเจกต์นี้เจอมาแล้ว 5 ครั้ง (T1 · T2 · N1 · slow gate · `:356`)

---

## 1. 🔴 G1 — หลัง `install` แล้ว `check` จะ **`[SKIP]` ทุกตัวตลอดกาล**

```python
def target_install():
    venv.create(venv_dir, with_pip=True)        # :60  ← ติดตั้งลง .venv
    python = _venv_python()                      # :61
    return _run([str(python), "-m", "pip", "install", "-e", ".[dev]"], ...)   # :62

def target_lint():
    if not _module_exists("ruff"):               # :66  ← ถามจาก sys.executable ไม่ใช่ .venv
        return _skip("lint", "ruff is not installed; run install")
    return _run([sys.executable, "-m", "ruff", "check", "."], "lint")         # :68
```

`_venv_python()` ถูกใช้ **ที่เดียวคือ `target_install`** · `lint` · `typecheck` · `test`
ทั้งหมดถาม `importlib.util.find_spec()` ของ **interpreter ที่รัน runner อยู่** แล้วสั่งด้วย `sys.executable`

### ลำดับที่เกิดขึ้นจริงเมื่อทำตาม `docs/setup.md` ที่ Codex ร่างมาเอง

```
python tools/task.py install     → ruff/mypy/pytest ลง .venv สำเร็จ
python tools/task.py check       → find_spec("ruff") ใน python ระบบ = None
                                 → [SKIP] lint · [SKIP] typecheck · [SKIP] test
                                 → check: OK (0 passed, 4 skipped)   exit 0
```

**`check` คืน 0 โดยไม่ได้รัน lint · type check · test แม้แต่ตัวเดียว**

> ### นี่ไม่ใช่การผิด spec — spec §4.3 อนุญาต `exit 0` เมื่อมีแต่ skip จริง
> **แต่ spec เขียนข้อนั้นโดยสมมติว่า skip เกิดเพราะ *ของยังไม่มี* (`codegen` ก่อน SPEC-004)**
> ไม่ใช่เพราะ **runner หาของที่ตัวเองเพิ่งติดตั้งไม่เจอ** · ผลลัพธ์คือ gate ที่ผ่านฟรี
> ซึ่งคือสิ่งที่ §4.3 ตั้งใจป้องกันตั้งแต่แรก

### ต้องแก้

| # | ทำ |
|---|-----|
| a | เก็บ interpreter ที่จะใช้ไว้ที่เดียว — **ถ้ามี `.venv` ให้ใช้ `.venv`** ไม่งั้นใช้ `sys.executable` |
| b | `_module_exists()` ต้องถาม **interpreter ตัวนั้น** ไม่ใช่ตัวที่รัน runner (`subprocess` เรียก `-c "import ruff"` หรือเทียบ `find_spec` ในโปรเซสนั้น) |
| c | ★ **แยก skip 2 ชนิด** — `SKIP(ของยังไม่มีตามแผน)` → exit 0 ได้ · `SKIP(สิ่งแวดล้อมไม่พร้อม)` → **ต้อง exit ≠ 0** ตรงกับ `⑤ exit 3` ที่ `แก้ 5` ขออยู่แล้วสำหรับ chaos gate |

**ข้อ c สำคัญกว่าที่คิด** — ถ้าไม่แยก เราจะไม่มีทางแยก *"ข้ามเพราะยังไม่ถึงเวลา"*
ออกจาก *"ข้ามเพราะเครื่องพัง"* ได้เลยจากผลรัน

---

## 2. 🔴 G2 — edge case ①ของ spec ไม่ถูก implement

[SPEC-002 §edge 1](../specs/SPEC-002-repo-scaffold.md): *"`.venv` มีอยู่แล้วแต่เป็น Python คนละเวอร์ชัน → **ตรวจแล้วเตือน ห้ามใช้ต่อเงียบๆ**"*

```python
if venv_dir.exists():
    python = _venv_python()
    if not python.exists():                      # :57  ← ตรวจแค่ว่าไฟล์มีอยู่
        return TaskResult("install", "FAIL", ...)
```

**ไม่มีการอ่านเวอร์ชันเลย** · `.venv` ที่สร้างด้วย Python 3.10 จะถูกใช้ต่อเงียบๆ
ทั้งที่ `requires-python = ">=3.11,<3.14"`

**แก้:** รัน `[venv_python, "-c", "import sys;print(sys.version_info[:2])"]` แล้วเทียบ
· ไม่ตรง → **เตือน** (ห้ามลบ `.venv` เอง ตาม Q2 ของ spec)

---

## 3. ✅ ที่ทำถูกและตรวจแล้ว

| ข้อ | หลักฐาน |
|-----|---------|
| 9 test ครบตาม §7 | `grep -c "def test_" tests/test_task_runner.py` = **9** |
| `check` ไม่หยุดที่ fail แรก | `run_sequence():140-144` วนครบทุกตัว |
| `mql5-gate` propagate exit code | `:121` คืน `completed.returncode` ผ่าน `_run` ไม่กลืน |
| `[SKIP]` มีเหตุผลและนับแยก | `summarize():147-161` |
| subprocess มี timeout ทุกตัว | `_run(timeout_sec=900)` · install 1200 · mql5-gate 7200 |
| `test` กัน slow/live/mql5 ออก | `:87` `-m "not slow and not live_terminal and not mql5"` ✅ **ดีกว่าที่ spec เขียน** |
| ไม่มี `Makefile` · `.env` ถูก ignore | Codex รัน `git check-ignore .env` แล้ว |

**การไม่สร้าง `docs/setup.md` เองแล้วส่งร่างมาแทน — ถูกต้องตามกติกา** และร่างใช้ได้จริง
ผมจะเอาไปลง `docs/` เอง (แก้ path ตาม G3 ก่อน)

---

## 4. 🟠 G3 — **ข้อนี้ผมผิดเอง ไม่ใช่ Codex**

`handoff/to-codex/020` เขียนว่า B2 จะ *"ปลดล็อก `psutil` ให้ B1/B3 และปิด **T8** ในตัว"*

```
grep -n "psutil|EA_FARM_REPO|EA_FARM_CHAOS_PORT" docs/specs/SPEC-002-repo-scaffold.md
→ ไม่พบสักคำ
```

**SPEC-002 ไม่เคยพูดถึงทั้งสองเรื่อง** · Codex ทำตาม spec ถูกทุกตัวอักษร
สิ่งที่ผิดคือ **ผมเขียนคำสัญญาในใบสั่งงานที่ spec ไม่ได้รองรับ**

| ของที่ขาด | ใครต้องการ |
|-----------|-----------|
| `psutil` ใน `[project.optional-dependencies]` | [SPEC-067 §3.1](../specs/SPEC-067-memory-soak.md) · ไม่มี = `churn`/`steady` ทำงานไม่ได้ (§5 กรณี 5 สั่งให้ `exit 3`) |
| `EA_FARM_REPO` · `EA_FARM_CHAOS_PORT` ใน `.env.example` | **T8** — path `D:\ea-farm` hardcoded อยู่ 3 ที่ + `WIRE_DIAG` เป็นที่ 5 |

**→ ผมแก้ SPEC-002 เพิ่ม 2 ข้อนี้แล้วในรอบเดียวกับ review นี้** · Codex ทำตาม spec ฉบับใหม่ได้เลย
**ไม่นับเป็นความผิดของรอบนี้**

---

## 5. 🟡 บันทึกไว้ ไม่ต้องแก้ตอนนี้

| # | เรื่อง |
|---|-------|
| G4 | `[tool.setuptools.package-dir] farm_contracts` ยังไม่มีผลจนกว่า `farm_contracts` จะอยู่ใน `packages` — Codex รายงานเองแล้ว ✅ ถูกต้องที่ยังไม่ใส่ |
| G5 | `mypy strict` ครอบ `tests` ซึ่งรวม `tests/chaos/**` ที่เขียนก่อนมี mypy — **ยังไม่รู้ว่าเขียวไหมเพราะยังไม่ได้รัน** · ถ้าแดงเยอะ ให้ยกเว้นเป็นไฟล์ อย่าปิด strict ทั้งโปรเจกต์ |
| G6 | `except Exception` ที่ `:183` กลืนทุกอย่างเป็น exit 2 — ตรงตาม spec (`2 = runner พัง`) แต่ควรพิมพ์ traceback ด้วยเมื่อ `EA_FARM_DEBUG=1` |

---

## 6. สรุป

**`CHANGES_REQUIRED`** — G1 + G2 · ทั้งคู่อยู่ใน `tools/task.py` แก้รอบเดียวจบ

โครงสร้างส่วนที่เหลือ**ดีและตรง spec** · G1 ไม่ใช่ความสะเพร่า แต่เป็นกับดักที่
สมมติฐาน *"runner รันด้วย interpreter เดียวกับที่ติดตั้งของ"* ซ่อนอยู่เงียบๆ
— และมันจะไม่มีทางถูกจับได้ด้วย test ที่ mock `subprocess` ทั้งหมด

> **เพิ่ม test ที่ต้องมีในรอบแก้:**
> `test_check_fails_when_environment_is_incomplete` — สร้างสถานการณ์ที่เครื่องมือหาย
> แล้วยืนยันว่า **exit ≠ 0** · นี่คือ test ที่ G1 จะไม่รอด
