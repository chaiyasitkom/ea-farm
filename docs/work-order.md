# Work Order — งานปัจจุบันของ Codex

**อัปเดต:** 2026-07-27 · **โดย:** Claude
เอกสารนี้เป็น **ลำดับงานที่มีผลบังคับ** — ทำจากบนลงล่าง ห้ามข้าม
ถ้าคิดว่าลำดับผิด → เขียน implementation note มาก่อน อย่าเปลี่ยนเอง

> สถานะรวม: **ยังไม่มี MQL5 test รันผ่าน Strategy Tester สำเร็จเลยแม้แต่ครั้งเดียว**
> นั่นคือสิ่งที่ต้องแก้เป็นอันดับแรก ทุกอย่างหลังจากนั้นพึ่งข้อนี้

---

## A. ปิดรอบที่ค้างอยู่ตอนนี้ — เล็กที่สุด แต่บล็อกทุกอย่าง

ตอนนี้มี 3 ไฟล์ค้างใน working tree ยังไม่ commit:
`mt5-ea/Include/Farm/Wire.mqh` · `tests/mql5/TestWire.mq5` · `tools/run-mql5-tests.ps1`

### A1 · 🔴 แก้เป้า XM ใน `tools/run-mql5-tests.ps1`

`CHANGES_REQUIRED` จาก [review รอบ 3 §2](reviews/SPEC-001-compile-gate-03.md)

**ปัญหา:** XM login ไม่ผ่าน (`Invalid account`) และ `EURUSD` history เป็น stub 15 KB
→ compile ผ่านแต่ tester ไม่ start → ไม่มี result JSON → `exit 1` **ทุกครั้งแม้ IUX ผ่านครบ**
→ gate แดงถาวร = gate ที่คนเลิกอ่าน

**ต้องทำ:**
```powershell
@{ Name = "XM"; Enabled = $false; ... }    # เหตุผล: D11 login ไม่ผ่าน · ไม่มี history
```
1. เพิ่ม field `Enabled` ให้ทุกเป้า · XM = `$false` · IUX = `$true`
2. เป้าที่ `Enabled = $false` → พิมพ์ `[SKIP] XM -- reason: ...` **ดังๆ** แล้วข้าม ไม่นับเป็น fail
3. **สรุปท้ายต้องบอกว่าเป้าไหนรันจริง เป้าไหนข้าม** — `[SKIP]` ห้ามดูเหมือน pass
4. pre-flight `Test-Path` ตรวจเฉพาะเป้าที่ `Enabled = $true`
5. ลบ `From`/`To` ของ XM ทิ้ง — **ห้ามลอก date range จากเป้า IUX** ค่าที่ถูกต้องยังไม่รู้

**เสร็จเมื่อ:** รันแล้วได้ `MQL5 TESTS: PASSED` + บรรทัด `[SKIP] XM` ปรากฏชัด

### A2 · รัน gate ให้เขียวจริง

```powershell
powershell -ExecutionPolicy Bypass -File D:\ea-farm\tools\run-mql5-tests.ps1
```

**เสร็จเมื่อ:** `status: PASS` · `ran_names` ครบ 11 ชื่อตาม [SPEC-001 §7](specs/SPEC-001-mt5-executor.md)
· **แปะ output จริงมาใน handoff** (AGENTS.md ข้อ 6)

### A3 · commit + handoff

```bash
git branch --show-current                       # ต้องเป็น feat/SPEC-001-*
git add mt5-ea tests tools                      # ระบุ path เสมอ ห้าม -A
```

**handoff ต้องมีหัวข้อ `## gate changes` แยกจากงานหลัก** (AGENTS.md ข้อ 17 ใหม่)
ลิสต์ทุกการแก้ใน `tools/**` — Claude อ่าน diff ของ gate ก่อนดูผลรันเสมอ

---

## B. แก้ defect ใน SPEC-001 — เป็น bug ไม่ใช่ feature ใหม่

Wire.mqh ส่งค่าที่**ละเมิด contract ที่ตกลงไว้แล้ว** · ทั้งสองข้อจะถูก fixture ใน
[SPEC-004 §3.6](specs/SPEC-004-codegen.md) จับทันที ทำตอนนี้ถูกกว่าทำหลัง codegen

### B1 · 🔴 `msg_id` ต้องเป็น ULID จริง

`Wire.mqh:97-102` — ตอนนี้ได้ 18 หลัก และ `static ulong seq = 0` **รีเซ็ตทุกครั้งที่ EA โหลด**
→ restart ในวินาทีเดียวกันได้ `msg_id` ซ้ำเป๊ะ · นี่คือ **dedupe key** ของ gateway
→ message ที่ถูกต้องจะถูกทิ้งเงียบๆ

**ต้องทำ:** ULID = 48-bit ms timestamp + 80-bit random → Crockford base32 26 ตัว
(`0123456789ABCDEFGHJKMNPQRSTVWXYZ` — ไม่มี `I` `L` `O` `U`)
· seed `MathSrand()` ด้วย `GetMicrosecondCount()` **ห้ามใช้ `TimeCurrent()`**
(สอง instance ที่เริ่มวินาทีเดียวกันจะได้ random ชุดเดียวกัน)

**เสร็จเมื่อ:** ตรง `common.json#/$defs/ulid` pattern `^[0-9A-HJKMNP-TV-Z]{26}$`
· มี test ว่ารัน 2 instance พร้อมกันแล้ว id ไม่ซ้ำ

### B2 · 🔴 `timeframe` / `session_id` ส่ง `PERIOD_H1`

`EnumToString((ENUM_TIMEFRAMES)Period())` คืน `"PERIOD_H1"` แต่ schema รับแค่ `"H1"`
· ยังใช้อยู่ **2 จุด** ใน `Wire.mqh`

**ต้องทำ:** ฟังก์ชันแปลงตัวเดียว → `M1|M5|M10|M15|M30|H1|H4`
· ใช้ทั้ง `session_id` และ field `timeframe`
· timeframe นอกชุดนี้ → `OnInit` **fail** ห้ามส่งค่าที่ schema ไม่รับขึ้นไป

**เสร็จเมื่อ:** `session_id` ตรง pattern ใน `common.json#/$defs/session_id`

---

## C. ปิด SPEC-001 ให้ครบ acceptance

### C1 · 🔴 chaos suite ต้อง EA-driven จริง

ค้างมาตั้งแต่ [gate-02 ข้อ 4](reviews/SPEC-001-compile-gate-02.md) · ตอนนี้เป็น Python client
5 ตัวคุยกับ `echo_server.py` — **ไม่มี EA จริงในลูป** จึงพิสูจน์ reconnect/backoff ไม่ได้เลย

[SPEC-001 §7](specs/SPEC-001-mt5-executor.md) ต้องมี 6 ชื่อ — มีจริง 1:

| test | มี? |
|------|-----|
| `test_duplicate_session_rejected` | ✅ (แต่ไม่ EA-driven) |
| `test_ea_reconnects_after_server_kill` | ❌ |
| `test_backoff_schedule_matches_spec` | ❌ |
| `test_bad_token_waits_60s` | ❌ (มี `test_bad_token_rejected` ซึ่งไม่พิสูจน์การรอ 60s) |
| `test_heartbeat_gap_triggers_reconnect` | ❌ (มี `test_heartbeat_ack`) |
| `test_no_heartbeat_loss_over_1h` | ❌ |

### C2 · วัด `Pump()` p99 < 20 ms

ด้วย `GetMicrosecondCount()` แล้วส่งขึ้นใน `HEARTBEAT.wire.pump_p99_us` (schema มี field แล้ว)

### C3 · soak 24 ชม. บน demo ผ่านสุดสัปดาห์

heartbeat ไม่ขาด · ไม่ memory leak · **เป็นข้อพิสูจน์ว่าไม่ได้พึ่ง `TimeCurrent()`**

### C4 · หนี้ที่มีเส้นตาย — `test_partial_send_resumes` ด้วย socket จริง

[gate-02 §3❷](reviews/SPEC-001-compile-gate-02.md) · **เส้นตาย: ก่อน merge SPEC-011**
วิธี: `echo_server.py` accept แล้วไม่อ่าน (หรือ `SO_RCVBUF` เล็ก) → บังคับให้ `SocketSend` short write

---

## D. SPEC-063 — BrokerTime

📄 [spec พร้อมแล้ว](specs/SPEC-063-broker-time.md) · **SPEC_READY**

ปิด finding ❸: `ts_server` ติดป้าย `Z` แต่เป็นเวลา broker-local → เพี้ยน 2–3 ชม. ตลอดเวลา
กระทบ primary key ของ `bars` และ parity test (SPEC-033)

> ⚠️ `AGENTS.md` §MQL5 เคยเขียนว่า "ใช้ `TimeCurrent()` ตัดสินใจ" — **แก้แล้ว**
> ถ้าคุณอ่านฉบับเก่าไว้ ให้ยึด SPEC-063: เรียกเวลาผ่าน `CBrokerTime` ตัวเดียวเท่านั้น

---

## E. SPEC-004 — Codegen

📄 [spec พร้อมแล้ว](specs/SPEC-004-codegen.md) · **SPEC_READY** · schema 14 ไฟล์เสร็จแล้ว

อ่าน [`contracts/schema/README.md`](../contracts/schema/README.md) ก่อนเริ่ม โดยเฉพาะ:
- ข้อ 2 `additionalProperties` ต้องเป็น `ignore` **ห้าม `forbid`**
- ข้อ 3 `null` ≠ `0` ≠ ไม่มี field

ตัวยากที่สุดคือ `JsonCore.mqh` — ต้องเป็น recursive-descent parser จริง
`Json.mqh` เดิมใช้ `StringFind` หา key ซึ่ง **parse `STATE.positions[]` ไม่ได้เลย**

---

## F. `local_limits` ต่อกับ EA input — เส้นตาย: ก่อน merge SPEC-019

ตอนนี้ hardcode `0.50/0.50/4/8/25/2.0/6.0` และ `FarmExecutor.mq5` ยังไม่มี input พวกนี้เลย
ทั้งที่ [contract §4.1](02-contracts.md) เขียนว่า **"ค่ามาจาก EA input เท่านั้น"**

ยังไม่อันตรายตอนนี้ (ไม่มี guard/order) แต่**อันตรายทันทีตอน SPEC-019**:
guard บังคับค่าจริงจาก input แต่ brain ถูกบอกค่าคงที่
→ brain ส่ง intent ที่คิดว่าอยู่ในเพดาน แต่ EA reject → **intent หายเงียบๆ ทั้งที่ทั้งสองฝั่ง "ทำถูก"**

`max_spread_points = 25` ยังขัด [ADR-002](decisions/ADR-002-symbols-capital-hours.md) ที่ทำให้ R5
เป็นตารางต่อ symbol → ค่าสุดท้ายต้องมาจาก SymbolRegistry (SPEC-064)

---

## ❌ ยังห้ามเริ่ม

| ticket | ทำไม |
|--------|------|
| **SPEC-011** OrderRouter | `SPEC_READY` ก็จริง แต่ depends on SPEC-010 ซึ่ง**ยังไม่มี spec** · และ C4 ต้องเสร็จก่อน merge |
| **SPEC-019/020** risk layer | รอ spec — Claude ยังไม่เขียน |
| อะไรก็ตามใน `contracts/schema/**` | Claude เป็นเจ้าของ · เสนอผ่าน implementation note |

---

## หมายเหตุที่ใช้ได้กับทุกงาน

| | |
|---|---|
| branch | `feat/SPEC-NNN-*` เท่านั้น · **ห้าม commit ลง `main`** · เช็คด้วย `git branch --show-current` ก่อนทุกครั้ง |
| `git add` | ระบุ path เสมอ — `git add mt5-ea brain tests research ops contracts/gen tools` · **ห้าม `-A` / `.`** |
| ไฟล์ที่เห็นค้างของ Claude | `docs/` `contracts/schema/` `AGENTS.md` `CLAUDE.md` `README.md` — **ปล่อยไว้ ห้ามแตะ** |
| `tools/**` | แก้ได้ แต่ต้องลงหัวข้อ `## gate changes` ใน handoff แยกจากงานหลัก |
| compile | ไม่มี MetaEditor ในสภาพแวดล้อมคุณ → เขียนว่า **"รอ compile gate"** ห้ามเขียนว่า "compile ผ่าน" |
| test แดง | รายงานตรงๆ พร้อม output จริง · **ห้ามปิด/ลด check เพื่อให้ผ่าน** |
