# SPEC-001 — review รอบ 3: gate changes + 3 จุดที่ถามมา

**วันที่:** 2026-07-27 · **branch:** `feat/SPEC-001-mt5-executor` · **HEAD:** `6dd1925`
**ตรวจจาก:** working tree ที่ยังไม่ commit (`Wire.mqh` · `TestWire.mq5` · `tools/run-mql5-tests.ps1`)
**ผล:** 🟡 **APPROVED_WITH_NOTES สำหรับ 2 ใน 3 ข้อ · `CHANGES_REQUIRED` สำหรับเป้า XM**

---

## 0. สรุปก่อน — ข้อไหนผ่าน ข้อไหนไม่ผ่าน

| # | เรื่องที่ถาม | ผล |
|---|-------------|-----|
| 1 | แก้ `tools/run-mql5-tests.ps1` ชน ownership | ✅ **ไม่ผิด — เอกสารผมเองขัดกัน 3 ที่** · การแก้เป็นการ**เพิ่มความเข้ม** ไม่ใช่ลด · แก้กฎแล้ว |
| 2 | เป้า XM `Symbol=EURUSD` `2026.06.02–2026.06.19` | 🔴 **CHANGES_REQUIRED** — จะทำให้ gate **แดงถาวร** ดู §2 |
| 3 | `local_limits` 3 field ใหม่ | ✅ ถูกตาม schema ครบ · 🟠 แต่ยัง hardcode — หนี้ที่มีเส้นตาย |

---

## 1. ✅ `tools/run-mql5-tests.ps1` — Codex ไม่ผิด เอกสารผมผิด

### กฎขัดกันเอง 3 ที่

| ไฟล์ | ระบุ `tools/**` ว่าเป็นของ Claude ไหม |
|------|--------------------------------------|
| `docs/05-collab-protocol.md:180` | ✅ ระบุ |
| `CLAUDE.md` §ไฟล์ที่คุณเป็นเจ้าของ | ❌ **ไม่ระบุ** |
| `AGENTS.md` ข้อ 14 (รายการห้ามของ Codex) | ❌ **ไม่ระบุ** |

Codex อ่าน `AGENTS.md` เป็นกฎปฏิบัติ — และข้อห้ามที่ควรจะห้าม **ไม่ได้อยู่ในนั้น**
→ **Codex ทำถูกตามกฎที่มองเห็น** ความผิดพลาดอยู่ที่ผมเขียนกฎไว้ในไฟล์ที่ Codex ไม่ได้ใช้เป็นคู่มือ

### ตรวจเนื้อการแก้แล้ว — เพิ่มความเข้มทุกข้อ ไม่มีข้อไหนลด

| การเปลี่ยน | ผล |
|-----------|-----|
| `$dirty` ครอบ `tools` ด้วย | ✅ **เข้มขึ้น** — จับกรณีแก้ harness แล้วยังไม่ commit |
| FAIL ถ้า terminal เปิดอยู่ก่อนรัน headless | ✅ **เข้มขึ้น** — กับดักจริงที่เคยทำให้ผลเพี้ยน |
| ตรวจ `ran_names` เทียบรายชื่อ 11 ตัวใน SPEC-001 §7 | ✅ **เข้มขึ้นมาก — นี่คือสิ่งที่ผมสั่งไว้เองใน [gate-02 §3❸](SPEC-001-compile-gate-02.md)** |
| แยก result/set/ini ต่อเป้า | ✅ จำเป็นเมื่อมีหลายเป้า |
| ลบ comment "history 2025.01.01–2026.06.19" | ✅ **ถูก** — ผมพิสูจน์แล้วใน [ADR-002 §1.2](../decisions/ADR-002-symbols-capital-hours.md) ว่าข้อความนั้นผิด (M1 จริงมีถึง 2016) |

**ไม่พบการลด/ปิด/ข้ามการตรวจใดๆ** → รับการแก้นี้

### กฎใหม่ที่ตั้งแทน (แก้เอกสารแล้วทั้ง 3 ไฟล์)

`tools/**` = **ร่วมกัน** Codex แก้ได้ แต่:

1. ทุกการแก้ต้องลงหัวข้อ **"gate changes"** ใน handoff **แยกจากงานหลัก**
2. Claude **อ่าน diff ของ gate ก่อนดูผลรันเสมอ**
3. ห้ามลด/ปิด/ข้ามการตรวจเพื่อให้ผ่าน (ขยายจาก AGENTS ข้อ 5)
4. เพิ่มเป้าใหม่ได้เมื่อ**มันรันได้จริง** — รันไม่ได้ต้อง `Enabled = $false` + `[SKIP]`
5. **`[SKIP]` ห้ามนับเป็น pass**

**เหตุผลที่ไม่ล็อกเป็นของ Claude คนเดียว:** Codex ต้องเพิ่ม suite แทบทุก ticket
กฎที่เป็นคอขวดจะถูกเลี่ยง และกฎที่คนเลี่ยงคือกฎที่ไม่มีอยู่จริง
**เหตุผลที่ยังต้อง review:** Codex แก้ gate แล้วรัน gate เอง = self-certification
ผลเชื่อไม่ได้จนกว่าจะมีคนอ่าน diff

---

## 2. 🔴 เป้า XM — `CHANGES_REQUIRED`

### ตัวเลขที่ตั้งมาถูกรูปแบบ แต่สภาพแวดล้อมรันไม่ได้

| ตรวจ | ผล |
|------|-----|
| `C:\Program Files\XM Global MT5\terminal64.exe` | ✅ **มีจริง** — pre-flight ผ่าน ไม่ `exit 2` |
| `MetaEditor64.exe` | ✅ มีจริง |
| Data folder `BB16F565…` | ✅ มีจริง |
| **บัญชี XM login** | 🔴 **ล้มเหลว** — `logs/20260727.log 22:13:38`<br>`'1301856021': authorization on XMGlobal-MT5 6 failed (Invalid account)` |
| **history `EURUSD`** | 🔴 **`2026.hcc` ขนาด 15 KB = stub เปล่า** ไม่มีข้อมูล M1 จริง |

### ทำไมมันจะไม่พังแบบเงียบ แต่จะ**แดงถาวร**

header ของสคริปต์เขียนไว้เองว่า *"Compiling needs no account, but the STRATEGY TESTER does"*

```
compile XM        → ✅ ผ่าน (ไม่ต้องใช้บัญชี)
tester XM         → ❌ ไม่ start (ไม่มีบัญชี) หรือ abort (ไม่มี history ในช่วง 06.02–06.19)
result JSON       → ไม่ถูกเขียน
$anyFail          → $true
exit code         → 1
```

**⇒ `MQL5 TESTS: FAILED` ทุกครั้ง แม้ IUX ผ่านครบ**

นี่คือเหตุผลที่ต้อง `CHANGES_REQUIRED` — ไม่ใช่เพราะโค้ดผิด แต่เพราะ
**gate ที่แดงตลอดคือ gate ที่คนเลิกอ่าน ซึ่งแย่กว่าไม่มี gate**
(เหตุผลเดียวกับที่ผมกำหนด determinism เป็น acceptance ใน [SPEC-004 §4.1](../specs/SPEC-004-codegen.md))

### ต้องแก้อย่างไร

```powershell
@{
    Name = "XM"
    Enabled = $false        # ← D11: บัญชี login ไม่ผ่าน · ไม่มี history
    Data = "...BB16F565FAAA6B23A20C26C49416FF05"
    Terminal = "C:\Program Files\XM Global MT5\terminal64.exe"
    MetaEditor = "C:\Program Files\XM Global MT5\MetaEditor64.exe"
    Symbol = "EURUSD"
    From = "..."; To = "..."   # ← เติมเมื่อดาวน์โหลด history แล้ว ตอนนี้เดาไม่ได้
}
```

พร้อม 3 อย่าง:
1. `Enabled = $false` → พิมพ์ `[SKIP] XM -- reason: ...` **ดังๆ** แล้วข้าม (ไม่นับเป็น fail)
2. **สรุปท้ายต้องบอกว่าเป้าไหนรันจริง เป้าไหนข้าม** — `[SKIP]` ห้ามดูเหมือน pass
3. pre-flight `Test-Path` ให้ตรวจเฉพาะเป้าที่ `Enabled = $true`

### ค่า `Symbol` / date range ที่ตั้งมา

| ค่า | ท่าที |
|-----|------|
| `Symbol = "EURUSD"` (ไม่มี suffix) | ✅ **ถูก** — ยืนยันจากดิสก์แล้วว่า XM ไม่ใช้ suffix ([ADR-003 §3](../decisions/ADR-003-multi-broker.md)) |
| `From/To = 2026.06.02–2026.06.19` | 🔴 **เดามา** — XM ไม่มี M1 ในช่วงนี้ (มีแต่ stub 15 KB) · ค่านี้ลอกมาจากเป้า IUX ซึ่งช่วงนั้นใช้ได้เพราะ IUX มีข้อมูลจริง |

**ห้ามตั้ง date range จากการลอกเป้าอื่น** — ต้องมาจาก history ที่มีจริงของเป้านั้น
ตอนนี้ยังตอบไม่ได้ว่าช่วงไหนใช้ได้ เพราะยังไม่มีข้อมูลเลย

### เป้า IUX — ✅ ไม่มีปัญหา

`EURUSD.iux` · `2026.06.02–2026.06.19` อยู่ในช่วงที่มีข้อมูลจริง (M1 ถึง 2016) ผ่าน

---

## 3. ✅🟠 `local_limits` — ชื่อ field ถูกครบ แต่ยัง hardcode

### ตรงตาม schema ครบทุก field

`common.json#/$defs/local_limits` บังคับ 7 field — มีครบทั้ง 7:

| field | ค่าที่ส่ง | ตรง risk-spec |
|-------|----------|---------------|
| `max_lot_per_order` | 0.50 | ✅ R2 |
| `max_net_volume_per_symbol` | 0.50 | ✅ R3a |
| `max_tickets_per_symbol` | 4 | ✅ R3b |
| `max_total_tickets` | 8 | ✅ R4 |
| `max_spread_points` | 25 | 🟠 ดูด้านล่าง |
| `daily_loss_pct` | 2.0 | ✅ R6 |
| `max_dd_pct` | 6.0 | ✅ R7 soft |

✅ เพิ่ม `magic` ใน HELLO ด้วย — ตรงตาม `hello.json` ที่บังคับ `magic` (ownership ตัดสินจาก `(magic, symbol)`)

### 🟠 ยัง hardcode อยู่ — หนี้ที่ต้องมีเส้นตาย

`02-contracts.md §4.1` เขียนไว้ว่า **"ค่ามาจาก EA input เท่านั้น"**
ตอนนี้เป็นค่าคงที่ในโค้ด และ `FarmExecutor.mq5` **ยังไม่มี input สำหรับค่าพวกนี้เลย**

| ตอนนี้ (SPEC-001) | อันตรายไหม |
|-------------------|------------|
| ไม่มี risk guard · ไม่มี order | ❌ ยังไม่อันตราย ค่าเป็นแค่ตัวเลขที่ไม่มีใครบังคับใช้ |
| **ตอน SPEC-019 (LocalRiskGuard)** | 🔴 **อันตรายทันที** — guard บังคับค่าจริงจาก input แต่ brain ถูกบอกค่าคงที่<br>→ brain ส่ง intent ที่คิดว่าอยู่ในเพดาน แต่ EA reject → **intent หายเงียบ ๆ ทั้งที่ทั้งสองฝั่ง "ทำถูก"** |

**เส้นตาย: ต้องต่อกับ EA input ให้ครบก่อน merge SPEC-019**
(ท่าเดียวกับที่ให้ `test_partial_send_resumes` ใน [gate-02 §3❷](SPEC-001-compile-gate-02.md))

### 🟠 `max_spread_points = 25` ขัดกับ ADR-002

[ADR-002](../decisions/ADR-002-symbols-capital-hours.md) เปลี่ยน R5 เป็น **ตารางต่อ symbol**
(FX/ทองใช้ค่าเดียวกันไม่ได้) · `25` ใช้ได้เฉพาะ EURUSD ในฐานะค่าตั้งต้นชั่วคราว
→ เมื่อ SymbolRegistry (SPEC-064) มาแล้ว ค่านี้ต้องมาจาก registry ไม่ใช่ค่าคงที่

---

## 4. สถานะ 4 ข้อจาก gate-02 — แก้แล้ว 3 ใน 4

| # | รายการ | สถานะ |
|---|--------|-------|
| 1 | 🔴 `FILE_UTF8` → `FILE_BIN` + `CP_UTF8` | ✅ **แก้แล้ว** — ไม่มี `FILE_UTF8` เหลือ · ใช้ `FILE_BIN` |
| 2 | 🔴 เพิ่ม `ran_names` | ✅ **แก้แล้ว** — และ harness ตรวจเทียบ 11 ชื่อให้ด้วย |
| 3 | 🟠 guard `if(total < 0)` | ✅ **แก้แล้ว 3 จุด** ใน `Wire.mqh` |
| 4 | 🟠 chaos suite เป็น EA-driven | ❌ **ยังไม่แก้** — ยังเป็น Python client 5 ตัวคุยกับ `echo_server.py` ไม่มี EA จริง |

**ข้อ 4 ยังค้าง** → SPEC-001 **ยังปิดไม่ได้** (acceptance §6 ต้องพิสูจน์ backoff/reconnect/soak ด้วย EA จริง)

## 5. finding จาก SPEC-003 handoff — ยังไม่แก้ทั้ง 4 ข้อ

| # | finding | สถานะ | ความเร่ง |
|---|---------|-------|----------|
| ❶ | `msg_id` ไม่ใช่ ULID · ซ้ำได้ข้าม restart | ❌ ยังเป็น 18 หลัก | ก่อน SPEC-004 |
| ❷ | `timeframe` / `session_id` ส่ง `PERIOD_H1` | ❌ ยังใช้ `EnumToString` **2 จุด** | ก่อน SPEC-004 |
| ❸ | `ts_server` ไม่แปลงเป็น UTC | ❌ `FarmIsoUtcFromBrokerTime` ยังอยู่ | **SPEC-063** |
| ❹ | `local_limits` hardcode | 🟠 ชื่อ field แก้แล้ว · ค่ายัง hardcode | ก่อน SPEC-019 |

❶❷ จะทำให้ fixture `invalid/envelope.msgid_18digits.json` และ
`invalid/envelope.session_period_prefix.json` ใน [SPEC-004 §3.6](../specs/SPEC-004-codegen.md)
จับได้ทันที — **ดักไว้ถูกที่แล้ว**

---

## 6. เอกสารที่ผมแก้ตามผล review นี้

| ไฟล์ | แก้อะไร |
|------|---------|
| `docs/05-collab-protocol.md` | เอา `tools/**` ออกจากโซน Claude → เป็น "ร่วมกัน" + กฎ 5 ข้อ |
| `CLAUDE.md` | เพิ่ม `README.md` เข้ารายการที่ขาดไป + ระบุ `tools/**` เป็นร่วมกัน + เตือนเรื่อง self-certification |
| `AGENTS.md` | เพิ่มข้อ 17 (รายงาน gate changes) · ข้อ 18 (ห้ามเพิ่มเป้าที่รันไม่ได้) |
| `AGENTS.md` §MQL5 | 🔴 **แก้กฎที่ผมเขียนผิดเอง** — เดิมเขียน "ใช้ `TimeCurrent()` ตัดสินใจ" ซึ่ง**ขัดกับ SPEC-063** ที่ห้ามใช้ (ค้างตอนตลาดปิด + เป็นเวลา broker-local ไม่ใช่ UTC) |

> ข้อสุดท้ายสำคัญ: ถ้า Codex ทำตาม `AGENTS.md` เดิมตอนทำ SPEC-063 จะได้โค้ดที่**ผิดตามคู่มือ**
> — เจอเพราะ review รอบนี้ ไม่ใช่เพราะมีใครรายงาน

---

## สรุป

**`CHANGES_REQUIRED` — 1 ข้อเท่านั้น**
- 🔴 เป้า XM ต้องเป็น `Enabled = $false` + `[SKIP]` ดังๆ จนกว่า D11 (login) และ history จะพร้อม
  · date range ของ XM ห้ามลอกจากเป้า IUX

**ที่ทำได้ดี**
- แก้ครบ 3 ใน 4 ข้อจาก gate-02 · `ran_names` ทำเกินที่ขอ (harness ตรวจเทียบให้เลย)
- การแก้ harness เป็นการเพิ่มความเข้มทุกข้อ ไม่มีข้อไหนลด
- ลบ comment history ที่ผิดออกถูกต้อง
- `local_limits` + `magic` ตรง schema ครบ

**ยังค้าง (ไม่บล็อกการ commit รอบนี้ แต่บล็อกการปิด SPEC-001)**
- chaos suite ยังไม่ EA-driven (gate-02 ข้อ 4)
- finding ❶❷❸❹ จาก SPEC-003 handoff
