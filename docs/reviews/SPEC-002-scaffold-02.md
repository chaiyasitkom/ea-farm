# SPEC-002 scaffold (B2) — review รอบ 2

**วันที่:** 2026-08-01 · **handoff:** [`023`](../../handoff/to-claude/023-b2-fix.md) · **ผล:** ✅ **G1 · G2 ปิด** · ⏳ ticket ยังไม่ปิด (รอ B2b)

รอบนี้ต่างจากรอบ 1 ตรงที่ **มีผลรันจริง** — รอบ 1 ตรวจได้แค่โค้ดเพราะเครื่องไม่มี pytest

---

## 1. G1 — ปิดแล้ว **พิสูจน์ 2 ทาง**

| สภาพเครื่อง | ผลรัน | ตีความ |
|-------------|-------|--------|
| **ไม่มี `.venv`** | `check: ENVIRONMENT INCOMPLETE (3 environment skipped, 1 planned skipped, 0 passed)` · **exit 3** | แยก "ข้ามเพราะเครื่องไม่พร้อม" ออกจาก "ข้ามเพราะยังไม่ถึงเวลา" ได้จริง |
| **มี `.venv`** | รัน lint · typecheck · test **จริง** แล้วรายงานตามจริง · exit 1 | ไม่ `[SKIP]` อีกแล้ว |

**เดิมทั้งสองกรณีคืน `check: OK` + exit 0 โดยไม่ได้ตรวจอะไรเลย**

โค้ดที่แก้ตรงจุด:

| | ที่ | ทำอะไร |
|---|-----|--------|
| a | `_selected_python():71` | มี `.venv` ใช้ `.venv` · ไม่มีใช้ `sys.executable` — **จุดเดียวที่ตัดสิน** |
| b | `_module_exists(name, python):28` | ยิง `subprocess` ถาม **interpreter ตัวนั้น** ไม่ใช่ตัวที่รัน runner |
| c | `_env_skip():66` + `summarize():268` | `SKIP` ที่มี `code != 0` ถูกนับแยกและทำให้คืน **3** |

**`target_codegen_check()` ส่งต่อ `code` ของ `codegen` อยู่แล้ว** → env-skip ไหลผ่านถูกต้อง ✅

## 2. G2 — ปิดแล้ว และ **แรงกว่าที่ spec ขอ**

`_python_version_failure():108` อ่านเวอร์ชันจาก `.venv` จริงผ่าน `subprocess`
เทียบกับ `>=3.11,<3.14` → ไม่ตรงคืน **`FAIL`** พร้อมข้อความ `Recreate .venv manually.`

spec edge ① เขียนแค่ *"เตือน ห้ามใช้ต่อเงียบๆ"* — Codex ทำเป็น **fail-closed**
**รับ** เพราะทิศทางถูกสำหรับโปรเจกต์นี้ · และ test ยืนยันว่า **ไม่ลบ `.venv` เอง** (`created == []`)

## 3. ผลรัน test — **11 ตัวของ B2 ผ่านครบ**

```
tests\chaos\test_wire_resilience.py .......ssssss   [ 54%]
tests\test_task_runner.py ...........               [100%]
18 passed, 6 skipped in 1.44s
```

6 skip = live/slow chaos ที่ถูกกันด้วย marker `-m "not slow and not live_terminal and not mql5"` ✅
**marker ทำงานจริง** ไม่ใช่แค่ประกาศไว้ใน `pyproject.toml`

`psutil==7.2.2` — ตรวจกับ PyPI แล้ว **มีจริงและเป็นเวอร์ชันล่าสุด** ✅ (ไม่ใช่เลขที่เดาขึ้นมา)

---

## 4. 🔴 `check` ยังแดง — 4 ข้อ ทั้งหมดเป็น**ของเก่าที่ไม่เคยถูกตรวจ**

| เครื่องมือ | ข้อ | ที่ |
|-----------|-----|-----|
| ruff `I001` | import ไม่เรียง | `tests/chaos/live_mt5_harness.py:1` · `tests/chaos/test_wire_resilience.py:1` |
| ruff `E501` | 101 > 100 | `tests/chaos/live_mt5_harness.py:75` |
| mypy | *Source file found twice under different module names* | `tests/chaos/` ไม่มี `__init__.py` |

**นี่คือผลตอบแทนของ B2 ทั้งใบ** — ไฟล์ chaos เขียนตั้งแต่ SPEC-016 และ **ไม่เคยผ่าน linter เลยสักครั้ง**
เพราะยังไม่มี linter · พอมีก็เจอทันที

> ตรงกับ **G5** ที่ [review รอบ 1](SPEC-002-scaffold-01.md) เตือนไว้ว่า *"mypy strict ครอบ `tests/chaos/**`
> — ยังไม่รู้ว่าเขียวไหมเพราะยังไม่ได้รัน"* · คราวนี้รันแล้ว รู้แล้ว

**→ ยกเป็น B2b** ([`024`](../../handoff/to-codex/024-A1-ปิดแล้ว-เกณฑ์-A2.md) ไม่ใช่ใบนี้ · ส่งแยกแล้ว) — ขอบเขตแคบ 5 ข้อ
· ⚠️ การแก้ mypy **ห้ามเปลี่ยนพฤติกรรมตอนรันของ chaos harness** · Claude รัน fast chaos gate ยืนยันเอง

---

## 5. 🟠 R-B1 — **ความผิดของ Claude** `.env.example` มี path จริงของเครื่อง

```
EA_FARM_REPO=D:\ea-farm        ← อยู่ในไฟล์ที่ commit และ push ขึ้น remote สาธารณะ
```

Codex ลอกจากตัวอย่างที่ **ผมเขียนไว้เองใน [SPEC-002 rev.2](../specs/SPEC-002-repo-scaffold.md)**
ซึ่งขัดกับกฎ *"placeholder เท่านั้น ห้ามมีค่าจริง"* ที่อยู่ในหน้าเดียวกัน
· **ทำตาม spec ถูกทุกตัวอักษร — ความผิดอยู่ที่ spec** → แก้เป็น **rev.2a** แล้ว

### และ test ที่ควรจับได้ ก็จับไม่ได้

```python
def test_env_example_has_no_real_values():
    assert "changeme" in env
    assert "FARM_TELEGRAM_BOT_TOKEN=\n" in env
    assert "FARM_TELEGRAM_CHAT_ID=\n" in env
    assert "test-token" not in env
```

**ตรวจแค่ 4 บรรทัดที่รู้จักล่วงหน้า** — ค่าจริงรูปแบบใหม่ผ่านฉลุย
· ชื่อ test สัญญาว่า *"no real values"* แต่ทำได้แค่ *"ไม่มี 2 ค่าที่เคยเจอ"*

> **bug class เดิมของโปรเจกต์นี้ครั้งที่เจ็ด** — T1 · T2 · N1 · slow gate · `:356` · G1 · **ข้อนี้**
> ทุกครั้งคือ *เครื่องมือที่ดูเหมือนตรวจ แต่ไม่ได้ตรวจสิ่งที่ชื่อมันบอก*

→ B2b ต้องเสริมให้ห้าม drive letter · `/Users/` · `/home/`

## 6. 🟠 R-B2 — ไม่มี test ไหนจับการถอยกลับของ G1 ได้

`test_check_fails_when_environment_is_incomplete` ทดสอบ **`summarize()` อย่างเดียว** ด้วย result ที่ปั้นมือ
· `test_missing_tool_reports_skip_not_traceback` **monkeypatch `_module_exists` ทิ้ง**

→ ถ้าใครเปลี่ยน `_module_exists` กลับไปถาม `sys.executable` **test ทั้ง 11 ตัวยังเขียวหมด**
· บั๊กที่เพิ่งแก้ ไม่มีตาข่ายรองรับ → **B2b ต้องเพิ่ม test ที่ยืนยันว่า `_module_exists` ถูกเรียกด้วย `_selected_python()`**

## 7. 🟡 R-B3

ไม่มี `.venv` → `_selected_python()` คืน `sys.executable` และ **ข้ามการตรวจเวอร์ชันทั้งหมด**
→ รันด้วย Python 3.10 ได้เงียบๆ · ตรงตาม spec edge ① (พูดถึงแค่ `.venv`) แต่ช่องว่างมีจริง
**ไม่ต้องแก้ตอนนี้** — บันทึกไว้

---

## 8. สรุป

| | |
|---|---|
| **G1** | ✅ ปิด · พิสูจน์ด้วยผลรัน 2 สภาพ |
| **G2** | ✅ ปิด · แรงกว่า spec |
| ขอบเขต | ✅ แตะ 4 ไฟล์ + handoff · ไม่หลุดออกนอกเลย |
| **ticket** | ⏳ **ยังไม่ปิด** — `check` ต้องเขียวก่อน (B2b) |

**Codex ทำรอบนี้ได้ตรงทุกข้อที่สั่ง** · ของที่เหลือเป็นหนี้เก่าที่เพิ่งถูกมองเห็นเป็นครั้งแรก
และ **หนึ่งในสองข้อที่ต้องแก้เพิ่มเกิดจาก spec ของผมเอง**
