# Setup — ตั้งเครื่องใหม่ให้รันโปรเจกต์นี้ได้

**สร้าง:** 2026-08-01 · ที่มา: ร่างของ Codex ใน [`handoff/to-claude/021-b2`](../handoff/to-claude/021-b2-spec-002-scaffold.md)
· Claude เรียบเรียงและแก้ path ตาม [SPEC-002 rev.2](specs/SPEC-002-repo-scaffold.md)

> เอกสารนี้ตอบคำถาม **"เครื่องเปล่าต้องทำอะไรบ้าง"** เท่านั้น
> ขั้นตอนตอนเกิดเหตุ (kill switch · SafeMode · ระบบล่ม) อยู่ใน runbook `SPEC-030b` ซึ่ง**ยังไม่มี**

---

## 1. Python

```bash
python tools/task.py install     # สร้าง .venv + pip install -e ".[dev]"
python tools/task.py check       # lint + typecheck + test + codegen-check
```

ต้องการ Python **`>=3.11,<3.14`**

> ### ⚠️ ข้อควรระวังที่รู้แล้วว่าเป็นกับดัก (G1)
>
> ถ้า `check` พิมพ์ `[SKIP] lint` · `[SKIP] typecheck` · `[SKIP] test` แล้วจบด้วย `OK`
> **แปลว่ามันไม่ได้ตรวจอะไรเลย** ไม่ใช่ว่าผ่าน — เกิดเมื่อ runner ถูกเรียกด้วย interpreter
> คนละตัวกับที่ `install` ติดตั้งของลงไป
>
> จนกว่า [G1 จะถูกแก้](reviews/SPEC-002-scaffold-01.md) ให้เรียกผ่าน `.venv` ตรงๆ:
> `.venv\Scripts\python.exe tools\task.py check`
>
> **`[SKIP]` ที่ยอมรับได้มีแค่** `codegen` / `codegen-check` (รอ SPEC-004)
> และ `mql5-gate` บนเครื่องที่ไม่ใช่ Windows

## 2. Environment

```bash
cp .env.example .env      # แล้วเติมค่าของเครื่องตัวเอง
```

**ห้าม commit `.env`** — `.gitignore` กันไว้แล้ว ตรวจซ้ำด้วย `git check-ignore .env`

| ตัวแปร | ใส่อะไร |
|--------|---------|
| `EA_FARM_REPO` | path ของ repo บนเครื่องนี้ |
| `EA_FARM_CHAOS_PORT` | ค่าเริ่มต้น `45001` — **ต้องตรงกับที่ whitelist ใน MT5** |
| `EA_FARM_MT5_DATA_DIR` · `EA_FARM_MT5_COMMON_DIR` | ว่างได้ = ใช้ค่าที่ helper รู้จัก |
| `FARM_DB_URL` | ยังไม่ต้องใส่จนกว่าจะติดตั้ง PostgreSQL (D13) |

---

## 3. MT5 — ขั้นที่ทำอัตโนมัติไม่ได้

ล็อกอินบัญชี demo ในเทอร์มินัลด้วยมือก่อน แล้วเปิดสิทธิ์ให้ EA ต่อ socket:

| ขั้น | ทำ |
|------|-----|
| 1 | `Tools → Options → Expert Advisors` |
| 2 | ✅ **Allow Algo Trading** |
| 3 | ✅ **Allow WebRequest for listed URL** ← ไม่ติ๊ก = รายการข้างล่างถูกละเลยทั้งหมด |
| 4 | เพิ่ม **`127.0.0.1`** และ **`127.0.0.1:45001`** (ทั้งสองบรรทัด) |
| 5 | ★ ปิดด้วย **`File → Exit`** — ปิดด้วย Task Manager แล้ว config **จะไม่ถูกเขียน** |

> **นี่คือ state ของเครื่องที่ไม่อยู่ใน git** — เครื่องใหม่ต้องทำใหม่ทุกครั้ง
> · อาการเมื่อลืม: EA log ขึ้น `err=4014` ทุก retry และ chaos ตกทั้งชุดโดยไม่มี `connect` เลย
> · `common.ini` **อ่านแล้วเชื่อไม่ได้** — มันไม่อัปเดตตามการแก้ setting จริง

## 4. รัน gate

| คำสั่ง | เวลา | เมื่อไร |
|--------|------|---------|
| `powershell -File tools\run-chaos.ps1` | **~4 นาที** | ทุกครั้งที่แตะ `Wire.mqh` หรือ test chaos |
| `powershell -File tools\run-chaos.ps1 -Slow` | **~65 นาที** | ก่อนปิด ticket ที่แตะ cadence/heartbeat |
| `powershell -File tools\run-mql5-tests.ps1` | ~2 นาที | ทุกครั้งที่แตะ `.mqh` |

**ก่อนรัน chaos ทุกครั้ง — preflight ด้วยมือ** (ยังไม่มีในสคริปต์ · [P1 ของ `แก้ 5`](work-order.md)):

1. ไม่มี `terminal64.exe` / `metaeditor64.exe` ค้างอยู่
2. พอร์ต `45001` ว่าง
3. **ห้ามแตะ MT5 ระหว่างรัน** — เปิดเทอร์มินัลกลางรอบทำให้ผลเพี้ยนแบบ W3 (EA หลายตัวตอบสลับกัน = **false pass**)

> `run-chaos.ps1` **ไม่พิมพ์อะไรเลยจนกว่าจะจบ** (T7 — `ReadToEnd()` สองสตรีมเรียงกัน)
> ระหว่างรันให้ดูความคืบหน้าจาก `%TEMP%\ea-farm-live-events-soak.jsonl` แทน

---

## 5. ของที่ยังไม่มีบนเครื่องนี้

| | สถานะ |
|---|-------|
| PostgreSQL (D13) | ⬜ ยังไม่ติดตั้ง — test ของ SPEC-006/014 รันไม่ได้ |
| `contracts/gen/` | ⬜ ยังไม่มี codegen (SPEC-004) → `farm_contracts` ยัง import ไม่ได้ |
| XM terminal (D11) | ⬜ login ไม่ผ่าน — path ยังกำหนดไม่ได้ |
| Telegram bot token | ⬜ ต้องมีก่อนรัน test ชั้น live ของ SPEC-029 |
