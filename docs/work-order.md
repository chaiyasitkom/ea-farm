# Work Order — งานของ Codex

**อัปเดต:** 2026-07-27 (รอบ 2) · **โดย:** Claude
ทำจากบนลงล่าง · ห้ามข้าม · คิดว่าลำดับผิด → implementation note มาก่อน

---

## ✅ เสร็จแล้วตั้งแต่รอบก่อน — ไม่ต้องทำซ้ำ

| งาน | หลักฐาน |
|-----|---------|
| `FILE_UTF8` → `FILE_BIN` + `CP_UTF8` | ไม่มี `FILE_UTF8` เหลือใน `TestWire.mq5` |
| `ran_names` + harness ตรวจเทียบ 11 ชื่อ | `run-mql5-tests.ps1` มี `$requiredNames` |
| `if(total < 0)` guard | 3 จุดใน `Wire.mqh` |
| **❷ `PERIOD_H1`** | `FarmTimeframeCode()` ใช้ 2 จุด · `EnumToString` เหลือ **0** · `session_id` ใช้ code แล้ว |
| **XM `Enabled` flag** | มีใน `run-mql5-tests.ps1` แล้ว |
| `local_limits` ชื่อ field + `magic` | ตรง `common.json` ครบ 7 field |

---

# รอบที่ 1 — ปิด SPEC-001 ให้จบ

> **ห้ามเริ่มรอบ 2 จนกว่ารอบ 1 จะ `APPROVED`**
> SPEC-001 เป็นฐานของทุกอย่าง ปล่อยให้ค้างครึ่งๆ แล้วไปต่อ = หนี้ที่ทบกับทุก ticket

## 1.1 🔴 ULID — monotonic พัง ต้องแก้

**ผลตรวจ `FarmGenerateUlid()`:**

```mql5
const ulong timestamp_ms = (ulong)TimeGMT() * 1000ULL + (ulong)(GetTickCount() % 1000);
```

`GetTickCount()` = ms ตั้งแต่ **เครื่องบูต** ไม่ใช่ ms ภายในวินาทีปัจจุบัน
→ `% 1000` เป็นค่าที่**ไม่สัมพันธ์กับขอบวินาทีของ `TimeGMT()`** เลย

**เคสที่พังจริง:**
```
t=0.000s  TimeGMT()=1000  GetTickCount()=5000998  →  ts = 1000000998
t=0.005s  TimeGMT()=1000  GetTickCount()=5001003  →  ts = 1000000003   ← ย้อนหลัง
```

`GetTickCount()%1000` วนรอบทุก 1 วินาทีจริง แต่ขอบไม่ตรงกับวินาทีของ `TimeGMT()`
→ **ทุกครั้งที่ message 2 ตัวคร่อมจุดวน ลำดับจะกลับด้าน** เกิดได้หลายครั้งต่อชั่วโมง

ละเมิด `common.json#/$defs/ulid` ที่เขียนว่า *"ต้อง monotonic ต่อ session"*
และ [contract §2](02-contracts.md) *"monotonic ต่อ session — ใช้ dedupe"*

**ผลกระทบ:** gateway เรียงตาม `msg_id` ไม่ได้ · ตรวจ gap ไม่ได้ · audit trail ลำดับผิด
· timestamp ที่ฝังใน ULID ไร้ความหมาย (ความละเอียดวินาที + noise)

### ต้องทำ — monotonic clamp

```mql5
// state ต่อ instance
ulong  m_ulid_last_ms;      // 0 ตอนเริ่ม
string m_ulid_rand_prefix;  // สุ่มครั้งเดียวตอน Init 16 ตัว
ulong  m_ulid_seq;          // นับต่อ session

ulong ms = (ulong)TimeGMT() * 1000ULL;      // ← ความละเอียดวินาทีพอ อย่าปลอม sub-second
if(ms <= m_ulid_last_ms)
   ms = m_ulid_last_ms + 1;                 // ← clamp ให้เพิ่มขึ้นเสมอ
m_ulid_last_ms = ms;
```

- **monotonic เด็ดขาด** ✓ (clamp)
- **ไม่ซ้ำในเซสชัน** ✓ (ms เพิ่มขึ้นตลอด)
- **ไม่ซ้ำข้าม restart** ✓ (นาฬิกาเดินหน้า + `m_ulid_rand_prefix` ต่างกัน)
- drift เกิดเฉพาะเมื่อส่ง > 1000 msg/วินาที ซึ่งเราไม่เคยทำ (heartbeat 2s)

> เมื่อ SPEC-063 เสร็จ ให้เปลี่ยน `TimeGMT()` → `CBrokerTime.NowUtc()`
> clamp จะรองรับกรณี offset กระโดดตอน DST ให้เอง

## 1.2 🔴 ULID — seed ชนกันข้าม instance

```mql5
MathSrand((int)(GetMicrosecondCount() % 2147483647));
```

`GetMicrosecondCount()` = ไมโครวินาทีตั้งแต่ **โปรแกรม MQL5 เริ่ม** — ตอน `OnInit` ค่านี้
เป็นเลขเล็กๆ (หลักร้อยถึงหลักพัน) **ทุก instance เสมอ**

→ EA 2 ตัวบน 2 terminal จะได้ seed จากช่วงแคบมาก → **สตรีมสุ่มเหมือนกัน**

> ⚠️ คำแนะนำเดิมของผมใน work order รอบก่อนที่ว่า *"seed ด้วย `GetMicrosecondCount()`"*
> **ผิด** — ผมเข้าใจว่ามันเป็นเวลาระบบ แต่มันเป็นเวลาตั้งแต่โปรแกรมเริ่ม · ขอแก้

**ต้องทำ — ผสม entropy ที่ต่างกันจริงต่อ instance:**
```mql5
MathSrand((int)(GetMicrosecondCount()
                ^ (long)TimeLocal()
                ^ ChartID()
                ^ AccountInfoInteger(ACCOUNT_LOGIN)));
```

## 1.3 🟠 test ULID ที่มีอยู่ ผ่านแบบไม่ได้ทดสอบอะไร

```mql5
CWire wire_a, wire_b;                    // ← อยู่ในโปรแกรมเดียวกัน
AssertTrue(wire_a.TestNextMsgId() != wire_b.TestNextMsgId(), ...)
```

สอง instance นี้ **แชร์ RNG stream เดียวกัน** (MathRand เป็น process-wide)
→ เรียกติดกัน 2 ครั้งย่อมได้คนละค่าเสมอ → **test ผ่านโดยไม่พิสูจน์อะไร**
ความเสี่ยงจริงคือ 2 **process** คนละ terminal ซึ่ง test นี้แตะไม่ถึง

**ต้องเพิ่ม 3 test:**

| test | ตรวจอะไร |
|------|----------|
| `test_msg_id_monotonic_across_1000_calls` | เรียก 1000 ครั้ง → **เรียงเพิ่มขึ้นเสมอ** (เทียบ string ตรงๆ ได้ เพราะ Crockford32 เรียงตาม ASCII) |
| `test_msg_id_monotonic_when_clock_frozen` | ป้อนเวลาคงที่ → ยังต้องเพิ่มขึ้น (พิสูจน์ clamp) |
| `test_msg_id_unique_across_10000_calls` | ไม่ซ้ำเลยสักคู่ |

เปลี่ยนชื่อ `test_msg_id_two_instances_not_duplicate` → `test_msg_id_differs_between_wire_objects`
และ **เขียนใน handoff ว่ามันไม่ได้พิสูจน์เรื่อง cross-process** อย่าให้ชื่อหลอกคนอ่านผลรัน

## 1.4 🔴 `(int)` cast บน counter ที่เป็น `long` — แก้เลย ไม่ต้องรอ

```mql5
"\"messages_sent\":"   + IntegerToString((int)m_messages_sent) + ","
"\"messages_recv\":"   + IntegerToString((int)m_messages_recv) + ","
"\"reconnect_count\":" + IntegerToString((int)m_reconnect_count) + ","
"\"bytes_dropped\":"   + IntegerToString((int)m_bytes_dropped) + ","
```

**ที่คุณรายงานว่า "พอสำหรับ SPEC-001" — ถูกครึ่งเดียว**

`messages_sent` ล้น int32 ใช้เวลาประมาณ 96 ปี ✓ ไม่เป็นปัญหาจริง
แต่ **`bytes_dropped` เป็น *ไบต์* ไม่ใช่จำนวนข้อความ** — ถ้าเข้าลูป reconnect
แล้ว drop ข้อความ ~1 KB ที่ 100/วินาที → **ล้น int32 ใน ~6 ชั่วโมง**

และผลของการล้นไม่ใช่แค่ "เลขเพี้ยน":
```
int32 overflow → ค่าติดลบ → IntegerToString(-123) → "-123"
schema: "minimum": 0  →  validation FAIL  →  gateway ปฏิเสธ heartbeat
→ EA ดูเหมือนตาย → R16 SafeMode
```

**ต้นทุนการแก้ = ลบ cast 4 ตัว** — `IntegerToString()` รับ `long` อยู่แล้ว cast นี้ไม่มีประโยชน์เลย
· `(int)PumpP99Us()` ก็ลบด้วยเพื่อความสม่ำเสมอ
· ตรงกับ mapping rule ที่ [SPEC-004 §3.3](specs/SPEC-004-codegen.md) กำหนดไว้แล้วว่า
`integer` → `long` **ห้ามใช้ `int`** — ถ้าโค้ดมือกับโค้ด generate ไม่ตรงกันจะกลายเป็นกับดัก

**ไม่รับเป็นหนี้** — ของที่แก้ 4 บรรทัดแล้วจบ ไม่ควรอยู่ในทะเบียนหนี้

## 1.5 🔴 chaos suite ต้อง EA-driven จริง

ค้างมาตั้งแต่ [gate-02 ข้อ 4](reviews/SPEC-001-compile-gate-02.md)
ตอนนี้เป็น Python client 5 ตัวคุยกับ `echo_server.py` — **ไม่มี EA อยู่ในลูป**

[SPEC-001 §7](specs/SPEC-001-mt5-executor.md) ต้องมี 6 ชื่อ · มีจริง 1:

| test | สถานะ |
|------|-------|
| `test_duplicate_session_rejected` | ✅ (ยังไม่ EA-driven) |
| `test_ea_reconnects_after_server_kill` | ❌ |
| `test_backoff_schedule_matches_spec` | ❌ 1,2,4,8,16,30 + jitter ±20% |
| `test_bad_token_waits_60s` | ❌ (`test_bad_token_rejected` ไม่พิสูจน์การรอ 60s) |
| `test_heartbeat_gap_triggers_reconnect` | ❌ (`test_heartbeat_ack` คนละเรื่อง) |
| `test_no_heartbeat_loss_over_1h` | ❌ |

**test ที่ไม่มี EA จริง พิสูจน์ reconnect/backoff ไม่ได้เลย** — วัดได้แค่ว่า server ตอบถูก

## 1.6 🟠 `test_partial_send_resumes` ด้วย socket จริง

[gate-02 §3❷](reviews/SPEC-001-compile-gate-02.md) · **เส้นตาย: ก่อน merge SPEC-011**
วิธี: `echo_server.py` accept แล้ว**ไม่อ่าน** (หรือตั้ง `SO_RCVBUF` เล็ก) → EA ส่ง frame ใหญ่
→ `SocketSend` คืนค่าน้อยกว่าที่ขอ

ที่มีอยู่ตอนนี้พิสูจน์ *การจดบัญชี resume* ถูก แต่ไม่พิสูจน์ว่า **ค่าที่ `SocketSend` คืนมาจริง
ต่อเข้ากับตรรกะนั้น** — Phase 1 ส่งซ้ำแค่ได้ message ซ้ำ **Phase 2 message ซ้ำ = order ซ้ำ**

## 1.7 `Pump()` p99 + soak

- วัดด้วย `GetMicrosecondCount()` → `HEARTBEAT.wire.pump_p99_us` (schema มี field แล้ว) · **p99 < 20,000 µs**
- soak 24 ชม. บน demo **ผ่านสุดสัปดาห์** — heartbeat ไม่ขาด · ไม่ memory leak
  · เป็นข้อพิสูจน์ว่าไม่ได้พึ่ง `TimeCurrent()`

## ✅ รอบที่ 1 เสร็จเมื่อ

- [ ] `run-mql5-tests.ps1` เขียว · `[SKIP] XM` ปรากฏชัด · สรุปบอกว่าเป้าไหนรันจริง
- [ ] `ran_names` ครบ 11 ชื่อตาม SPEC-001 §7 **+ 3 test ULID ใหม่**
- [ ] chaos 6 ชื่อครบ · EA-driven ทุกตัว
- [ ] p99 < 20 ms · soak 24 ชม.ผ่าน
- [ ] handoff มีหัวข้อ `## gate changes` + **output จริง**ของ gate

---

# รอบที่ 2 — SPEC-063 BrokerTime

📄 [spec เต็ม](specs/SPEC-063-broker-time.md) · **SPEC_READY** · 15 test

ปิด finding ❸ ที่ยังค้าง: `FarmIsoUtcFromBrokerTime` ยังอยู่ 3 จุดใน `Json.mqh`
และ **ไม่แปลงเวลาเลย** — `ts_server` เพี้ยนเท่ากับ offset ของโบรกเกอร์ตลอดเวลา

**หัวใจที่ห้ามพลาด:**

| | |
|---|---|
| test seam | `CBrokerClockSource` เป็น virtual — test ป้อนเวลาปลอม · **ห้าม mock `CBrokerTime` เอง** |
| ห้ามใช้ | `TimeCurrent()` (ค้างตอนตลาดปิด) → ใช้ `TimeTradeServer()` |
| debounce | 3 sample × 20s ก่อนยอมรับว่า offset เปลี่ยน — กัน sample เพี้ยนตอน reconnect ไปเลื่อนเส้นแบ่งวันของ R6 |
| `IsValid()==false` | แปลงเวลา **คืน 0** ห้ามใช้ offset เก่า |
| วัน DST 23/25 ชม. | **ถูกต้องแล้ว ห้าม "แก้"** |
| ลบทิ้ง | `FarmIsoUtcFromBrokerTime` — ชื่อที่หลอกคือต้นเหตุ ปล่อยไว้จะมีคนเรียกซ้ำ |

**acceptance ที่พิสูจน์ "แหล่งเดียว":**
`grep -rn "TimeGMT()\|TimeTradeServer()\|TimeLocal()\|TimeCurrent()" mt5-ea/` → เจอเฉพาะใน `BrokerTime.mqh`

> ⚠️ `AGENTS.md` §MQL5 เคยเขียนว่า "ใช้ `TimeCurrent()` ตัดสินใจ" — **ผมแก้แล้ว**
> ถ้าจำฉบับเก่าไว้ ให้ยึด SPEC-063

---

# รอบที่ 3 — SPEC-004 Codegen  ★ ก้อนใหญ่ที่สุด

📄 [spec เต็ม](specs/SPEC-004-codegen.md) · **SPEC_READY** · schema 14 ไฟล์เสร็จแล้ว
· **27 test** (Python 15 · MQL5 12) · 10 ไฟล์ใหม่

อ่าน [`contracts/schema/README.md`](../contracts/schema/README.md) **ก่อนเขียนบรรทัดแรก**

**ตัวยากที่สุด: `JsonCore.mqh`** — ต้องเป็น recursive-descent parser จริง
`Json.mqh` เดิมใช้ `StringFind` หา `"key"` ซึ่งพังกับ:
- key ชื่อเดียวกันคนละชั้น (`symbol` อยู่ทั้งใน payload และใน `positions[]`)
- string ที่มีข้อความคล้าย key (`"comment": "sl:1.0800"`)
- **array ของ object → parse `STATE.positions[]` ไม่ได้เลย**

**3 กับดักที่จะกินเวลามากที่สุด:**

| # | กับดัก |
|---|--------|
| 1 | **determinism** — `make codegen` 2 ครั้งต้อง byte-identical · sort เอง ห้ามพึ่ง `os.listdir()` · ห้ามใส่ timestamp ในหัวไฟล์ · pin `==` |
| 2 | **`additionalProperties`** ต้องเป็น `ignore` **ห้าม `forbid`** (ยกเว้น `config_update.settings` ที่เดียว) |
| 3 | **`null` ≠ `0` ≠ ไม่มี field** — MQL5 คืน `0.0` เมื่อไม่มี SL · schema มี `exclusiveMinimum: 0` → ส่ง `0` จะ fail · ต้องมี helper ตัวเดียว ไม่ใช่เช็คกระจาย |

`contracts/fixtures/invalid/` 4 ไฟล์แรกคือกับดักที่ดัก bug จริงไว้ — ทำให้มันแดงถูกต้อง

---

# รอบที่ 4 — `local_limits` ต่อกับ EA input

**เส้นตาย: ก่อน merge SPEC-019**

ตอนนี้ hardcode `0.50/0.50/4/8/25/2.0/6.0` และ `FarmExecutor.mq5` ยังไม่มี input พวกนี้
ทั้งที่ [contract §4.1](02-contracts.md) เขียนว่า **"ค่ามาจาก EA input เท่านั้น"**

ยังไม่อันตรายตอนนี้ (ไม่มี guard/order) แต่อันตรายทันทีตอน SPEC-019:
guard บังคับค่าจริงจาก input แต่ brain ถูกบอกค่าคงที่
→ brain ส่ง intent ที่คิดว่าอยู่ในเพดาน แต่ EA reject → **intent หายเงียบๆ ทั้งที่ทั้งสองฝั่ง "ทำถูก"**

`max_spread_points = 25` ยังขัด [ADR-002](decisions/ADR-002-symbols-capital-hours.md) ที่ทำให้ R5
เป็นตารางต่อ symbol → ค่าสุดท้ายต้องมาจาก SymbolRegistry (SPEC-064)

---

## ❌ ยังห้ามเริ่ม

| ticket | ทำไม |
|--------|------|
| **SPEC-011** OrderRouter | `SPEC_READY` แต่ depends on SPEC-010 ซึ่ง**ยังไม่มี spec** · และ 1.6 ต้องเสร็จก่อน merge |
| **SPEC-019 / 020** risk layer | Claude ยังไม่เขียน spec |
| **SPEC-064** SymbolRegistry | Claude ยังไม่เขียน spec (เพิ่งเลื่อนเป็น blocker หลังเพิ่ม XM) |
| `contracts/schema/**` | Claude เป็นเจ้าของ — เสนอผ่าน implementation note |
| เป้า XM ใน gate | `Enabled = $false` จนกว่า **D11** (login) และ history จะพร้อม |

---

## กฎที่ใช้กับทุกงาน

| | |
|---|---|
| branch | `feat/SPEC-NNN-*` · **ห้าม commit ลง `main`** · `git branch --show-current` ก่อนทุกครั้ง |
| `git add` | ระบุ path เสมอ — `git add mt5-ea brain tests research ops contracts/gen tools` · **ห้าม `-A` / `.`** |
| ไฟล์ Claude ที่เห็นค้าง | `docs/` `contracts/schema/` `AGENTS.md` `CLAUDE.md` `README.md` → **ปล่อยไว้** |
| `tools/**` | แก้ได้ แต่ต้องลงหัวข้อ `## gate changes` ใน handoff **แยกจากงานหลัก** |
| compile | ไม่มี MetaEditor ในสภาพแวดล้อมคุณ → เขียน **"รอ compile gate"** ห้ามเขียน "compile ผ่าน" |
| test แดง | รายงานตรงๆ พร้อม output จริง · **ห้ามปิด/ลด check เพื่อให้ผ่าน** |
| test ที่ผ่านแบบไม่ได้ทดสอบอะไร | อันตรายกว่า test แดง — ถ้ารู้ตัวว่า test อ่อน **เขียนบอกใน handoff** (เช่นข้อ 1.3) |
