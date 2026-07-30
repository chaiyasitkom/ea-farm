# Work Order — งานของ Codex

**อัปเดต:** 2026-07-30 (รอบ 3) · **โดย:** Claude
ทำจากบนลงล่าง · ห้ามข้าม · คิดว่าลำดับผิด → implementation note มาก่อน

---

# ★ ต้องทำตอนนี้ — รอบแก้ SPEC-063 / SPEC-016 ครั้งที่ 3 (2026-07-30)

> ⚠️ อย่าสับสนกับ **"รอบที่ 3 — SPEC-004 Codegen"** ด้านล่าง — นั่นคือลำดับ ticket
> ส่วนนี้คือ **รอบแก้ตาม review** ของงานที่ค้างอยู่ในมือตอนนี้

> ที่มา: [review รอบ 3](reviews/SPEC-063-03.md) `CHANGES_REQUIRED` + ผลรัน live chaos จริงคืนนี้
> · รอบ 2 ปิดไป 9 ข้อ ([รายการ](#-ปิดแล้วในรอบแก้นี้--ไม่ต้องทำซ้ำ)) เหลือที่นี่คือของที่ยังค้าง
>
> **ห้ามรายงาน PASS จนกว่า "แก้ 1" จะเสร็จ** — gate ปัจจุบันเขียวได้แม้ไม่มีการคอมไพล์เกิดขึ้น

## แก้ 1 🔴 T1 · gate เชื่อไม่ได้ — **ค้างมา 2 รอบแล้ว ทำก่อนอย่างอื่น**

แก้ **ทั้งสองสคริปต์** `tools/run-mql5-tests.ps1` และ `tools/compile-gate.ps1`

| # | ทำ | ที่ |
|---|-----|-----|
| a | `Remove-Item` **`.ex5` และ compile log** ก่อน compile ทุกครั้ง (`-ErrorAction SilentlyContinue`) | `run-mql5-tests.ps1:167-171` · `compile-gate.ps1:46-48` |
| b | parse `Result: N errors` → **error > 0 หรือ parse ไม่ได้ = FAIL ทันที** ห้ามเดินต่อไปเช็ค `.ex5` | `run-mql5-tests.ps1:174-186` — ตอนนี้ `Write-Output "  compile: $result"` แล้วจบ **ไม่เคยตรวจเลย** |
| c | คง `Test-Path .ex5` ไว้เป็นด่านที่สอง | `:182` |
| d | (T3) `.mqh` ที่ไม่มี target ไหน include → **FAIL** ไม่ใช่ `[WARN]` | `compile-gate.ps1:101-106` — ตอนนี้ไม่เพิ่ม `$totalErr` เลย gate จึงเขียว |

**ทำไมรอไม่ได้ — `git_sha` ไม่ใช่ตาข่ายอย่างที่คิด:**

```
compile พัง → .ex5 เก่ายังอยู่ → :182 ผ่าน → tester รัน binary เก่า
→ EA อ่าน sha ปัจจุบันจาก .set (:193) → :250 ตรวจผ่าน → MQL5 TESTS: PASSED
```

`git_sha` **ฉีดผ่าน `.set` ไม่ได้ compile ติดมากับ `.ex5`** จึงจับ stale binary ไม่ได้เลย

## แก้ 2 🔴 `BrokerTime.mqh` — แก้ 4 ข้อพร้อมกัน ไฟล์เดียว

| # | finding | ทำ | ที่ |
|---|---------|-----|-----|
| a | **B4 + B16** | `LocalTime()` → **`GmtTime()`** ทั้ง throttle 20s และหน้าต่าง 90s · เปลี่ยนชื่อฟิลด์เป็น `_gmt` | `:157-168` · `:93-111` |
| b | **B16b** | **cast เป็น `long` ก่อนลบเสมอ** · เก็บฟิลด์ที่ใช้วัดระยะเป็น `long` ไม่ใช่ `datetime` | ทุกจุดที่ลบเวลา |
| c | **B18** | ตรรกะ 90 วินาทีถูกเขียนไว้ **2 ที่** → รวมเหลือฟังก์ชันเดียว | `:106-110` + `:160-164` |
| d | **B15** | ฟื้นจาก invalid: ถ้า offset **ต่างจากเดิมต้องคืน `true`** · `AcceptOffset` **ห้ามทับ** `m_previous_offset_sec` (ตอน `Init` ให้เป็น `0`) · อัปเดต `m_last_change_utc` | `:113-122` · `:178-182` |

**ข้อ b คือครึ่งหนึ่งของบั๊กที่ผมเพิ่งเจอ:** `datetime` เป็น **unsigned** →
นาฬิกาถอยหลัง (DST ปีละ 2 ครั้ง · NTP แก้เวลาเป็นก้อน) ทำให้ `a - b` **underflow เป็นบวกมหาศาล**
→ `> 90` เป็นจริงทันที → **EA เข้า SafeMode โดยไม่มีเหตุ**

**ข้อ d:** ตอนนี้ broker ดับคร่อม DST แล้วกลับมาที่ offset ใหม่ → เส้นแบ่งวัน R6 ขยับทั้งระบบ
โดย `FarmExecutor.mq5:92` ไม่เข้าเงื่อนไข → **ไม่ log ไม่ส่ง ERROR ไม่มีใครรู้**

spec: [`SPEC-063 §4.3.1 · §4.3.2`](specs/SPEC-063-broker-time.md) (rev.2a + rev.2b)

## แก้ 3 🔴 live chaos ต่อไม่ติด — **ตรึงพอร์ต**

**หลักฐานจากการรันจริง 2026-07-30 21:57–22:03:** ทั้ง 5 test ตายเพราะไม่มี `connect` เลย
· EA log: `socket_connect_failed host=127.0.0.1 port=62292 err=4014` ทุก retry
· พอร์ตที่สุ่มได้ต่างกันทุกครั้ง: `62292` `63011` `52337` `64343` `64415`

`free_port()` **ไม่ได้ให้ประโยชน์อะไรกับ suite นี้เลย** — `assert_no_terminal_running()`
บังคับให้รันทีละตัวอยู่แล้ว live chaos รันขนานไม่ได้ตั้งแต่ต้น
แต่ถ้า MT5 build นี้ต้องการ whitelist แบบ `address:port` → **สุ่มพอร์ต = whitelist ไม่ได้เลยตลอดกาล**

→ ตรึงพอร์ตเดียว อ่านจาก env มี default: `EA_FARM_CHAOS_PORT` default `45001`
→ เขียนขั้นตอน whitelist ลง handoff (จะย้ายไป runbook SPEC-030b)

> ⏳ **ยังมีงานเพิ่มถ้าผลทดสอบออกมาแบบหนึ่ง** — กำลังแยกสาเหตุด้วยการเปิด terminal เอง
> (ไม่ผ่าน `/config`) · ถ้าต่อติด แปลว่า `[Experts]` ใน ini ที่ `write_startup_files()` เขียน
> (`AllowLiveTrading` · `AllowDllImport` · `Enabled` · `Account` · `Profile`)
> ไปรีเซ็ต setting ของ terminal → ต้องเลิกเขียนทับ **Claude จะยืนยันให้ก่อน อย่าเพิ่งแก้ข้อนี้**

## แก้ 4 🔴 `Wire.mqh` — fallback ตัวสุดท้าย + counter reset

**a) ลบ fallback ใน `NextMsgId()`** — `:219-220`

```mql5
if(utc_now <= 0)
   return NextMsgIdFromMs(GetTickCount64());   // ← ลบทิ้ง คืน "" แทน
```

มันยังไม่ใช่ dead code เพราะ `TestWire.mq5:181,189,197,201,228,232` เรียกผ่าน
`TestNextMsgId()` **โดยไม่มี broker time** → เดินเข้า fallback ทุกครั้ง
· นี่คือสิ่งที่ [§4.7](specs/SPEC-063-broker-time.md) ห้ามตรงตัว: *"ห้ามให้ production path มีทางลัดสำหรับ test"*
→ **ฉีด fake `CBrokerTime`** ให้ 6 จุดนั้น (fake clock มีพร้อมใน `TestBrokerTime.mq5` แล้ว)

**b) `m_dropped_no_time` ต้อง reset เมื่อกลับมาส่งได้** — `:237-239`
ตอนนี้ `% 10` นับสะสมทั้ง session → ช่วงพังรอบที่ 2 จะเริ่มนับต่อจาก 16
แล้ว**บรรทัดแรกของช่วงใหม่ไม่ถูก log เลย** · ค่าสะสมเก็บแยกเป็น `m_dropped_no_time_total`
· acceptance ทดสอบได้อยู่ใน [§6.3](specs/SPEC-063-broker-time.md)

## แก้ 5 🟠 gate ที่เหลือ

> อัปเดตหลัง [review รอบ 4](reviews/SPEC-063-04.md) — T5 ปิดแล้ว · เพิ่ม **P1** และ **N1**

| # | ทำ | ที่ |
|---|-----|-----|
| ~~**T5**~~ | ✅ **ปิดแล้ว** — เขียน `*-observed.json` แยก ไม่แตะไฟล์ EA · `UTF8Encoding $false` ไม่มี BOM | — |
| **P1** ★ | **preflight ตรวจสิ่งแวดล้อมก่อนรัน** — ดู §P1 ด้านล่าง · **ทำก่อนข้ออื่นในตารางนี้** | `run-chaos.ps1` |
| **⑤** | แยก **`exit 3`** สำหรับ env failure · ทำคู่กับ P1 (P1 คือคนตรวจ · ⑤ คือรหัสที่คืน) | `run-chaos.ps1` |
| **N1** | `*-observed.json` บันทึก `git_sha = $sha` (HEAD) และเขียน**ก่อน**เช็ค `$j.git_sha` → ถ้าผลเป็นของเก่า ไฟล์จะอ้าง HEAD ปัจจุบันทั้งที่ผลไม่ใช่ของมัน · **เก็บทั้ง `git_sha_head` และ `git_sha_result = $j.git_sha`** หรือย้ายไปเขียนหลังเช็คผ่าน · สำคัญเพราะไฟล์นี้คือสิ่งที่ [SPEC-065](specs/SPEC-065-mql5-test-harness.md) เอาไป attest | `run-mql5-tests.ps1:266-282` |
| **T6** | เช็ค**รายชื่อ test ที่รันจริง** ไม่ใช่จำนวน skip — รัน `-v` แล้ว parse เทียบ required list แบบเดียวกับ `$RequiredSuiteNames` · **ปิดไปครึ่งเดียว** (regex อ่านค่าตอน fail ได้แล้ว แต่ยังนับจำนวน) | `run-chaos.ps1:44-48` |
| **T7** | `ReadToEnd()` สองสตรีมเรียงกัน → **deadlock ได้** ถ้า child เขียน stderr จนเต็ม buffer · ใช้ async read | `run-chaos.ps1:37-38` |
| **T9** | ไม่มี timeout รวม → `WaitForExit($ms)` + kill + FAIL (fast ~10 นาที · slow ~70 นาที) | `run-chaos.ps1:39` |
| **T8** | `$Repo = "D:\ea-farm"` hardcoded **ที่ที่ 3 แล้ว** → รวมเข้า `.env` ตอน SPEC-002 (`C11` เดิม · SPEC-028 จะใช้ค่าเดียวกันอีก) | `run-chaos.ps1:14` |

**หลักฐานสดของ T6 และ T9:** รัน 2026-07-30
· รอบแรก gate พิมพ์ `CHAOS GATE: FAILED -- skipped=0` ทั้งที่ unittest บอก `skipped=1`
· รอบสอง **ค้างเกิน 10 นาทีจนถูกตัด** แล้วทิ้ง `terminal64.exe` + `python` ค้าง 3 process
  เพราะไม่มี timeout และ `finally` ของ harness ไม่ได้ทำงานตอนแม่ถูก kill
  → **T9 ต้องมีทั้ง timeout และการเก็บกวาด process ลูกด้วย** ไม่ใช่แค่ `WaitForExit($ms)`

---

### §P1 ★ preflight — เจอปัญหาใน 5 มิลลิวินาที แทน 327 วินาที

**ที่มา:** คืน 2026-07-30 เสียเวลาไป 2 รอบเต็ม (327 วินาที + 10 นาที) เพื่อค้นพบว่า
**MT5 ไม่ได้เปิด WebRequest** ซึ่งเป็นค่าที่อ่านได้จากไฟล์ก่อนรันด้วยซ้ำ
· gate ที่ใช้เวลา 5 นาทีเพื่อบอกว่า "สิ่งแวดล้อมไม่พร้อม" คือ gate ที่คนจะเลิกรัน

#### ตรวจ 3 อย่างก่อนแตะ MT5

| # | ตรวจ | ไม่ผ่าน → |
|---|------|-----------|
| 1 | **พอร์ตว่างไหม** — ลอง bind `127.0.0.1:$EA_FARM_CHAOS_PORT` | `FAILED (ENV)` + **บอกว่า PID ไหนถืออยู่** (`netstat -ano`) · `exit 3` |
| 2 | **`WebRequest=1`** ใน `[Experts]` ของ `common.ini` | `FAILED (ENV)` + ขั้นตอนตั้งค่า · `exit 3` |
| 3 | **`WebRequestUrl=` มี `127.0.0.1`** | เหมือนข้อ 2 |

ไฟล์: `<TERMINAL_DATA>\config\common.ini` — **UTF-16LE อ่านได้ ไม่ได้เข้ารหัส**
(`settings.ini` ต่างหากที่เข้ารหัส — อย่าไปยุ่ง)

```
[Experts]      ← บรรทัด ~37
WebRequest=0   ← checkbox "Allow WebRequest for listed URL"
WebRequestUrl= ← รายการ whitelist คั่นด้วย ;
```

#### ★★ ข้อจำกัดที่ **ต้องเขียนกำกับไว้ในโค้ด** ห้ามละ

`common.ini` ถูกเขียน**เฉพาะตอน MT5 ปิดอย่างสะอาด** เท่านั้น
· harness `kill` terminal ทุกครั้ง → ไฟล์นี้จะค้างเป็นค่าของ **"ครั้งล่าสุดที่ปิดสะอาด"**
· ตัวอย่างจริง: 2026-07-30 ผู้ใช้แก้ setting เวลา 22:21 (`settings.ini` เปลี่ยน)
  แต่ `common.ini` ยังเป็นของ **07-29 16:31** เพราะไม่เคยปิดสะอาดเลยตั้งแต่นั้น

| ต้องทำ | ห้ามทำ |
|--------|--------|
| เตือนเมื่อ `common.ini` เก่ากว่า `settings.ini` — *"ค่าที่อ่านอาจไม่ใช่ค่าปัจจุบัน ปิด MT5 ให้สนิทหนึ่งครั้งแล้วรันใหม่"* | ถือว่า preflight ผ่าน = สิ่งแวดล้อมพร้อมแน่นอน |
| ให้ preflight เป็น **ด่านคัดกรอง** ที่จับเคสชัดๆ ได้เร็ว | ให้ preflight เป็น**หลักฐาน**ว่าพร้อม |

**ถ้าละข้อนี้ P1 จะกลายเป็น bug class เดิมของโปรเจกต์นี้ทันที** —
*"เขียวเพราะอ่านของเก่า"* ซึ่งเป็นสิ่งเดียวกับ T1 (stale `.ex5`) และ G1 (`correlation = 0`)

#### ห้าม preflight แก้ค่าให้เอง

อย่าเขียน `common.ini` เพื่อ "ช่วยตั้งให้" — MT5 เขียนทับตอนปิด และการมี 2 คนเขียนไฟล์เดียวกัน
จะทำให้สืบไม่ได้ว่าค่าที่รันจริงมาจากไหน · **preflight มีหน้าที่บอก ไม่ใช่ซ่อม**
(หลักการเดียวกับ [SPEC-028 §4.3](specs/SPEC-028-dashboard-kill-switch.md) — เครื่องมือฉุกเฉินยิ่งโง่ยิ่งเชื่อได้)

#### ผลพลอยได้: ขั้นตอนที่ต้องลง runbook (SPEC-030b)

| ขั้น | ทำ |
|------|-----|
| 1 | `Tools → Options → Expert Advisors` |
| 2 | ✅ Allow Algo Trading |
| 3 | ✅ **Allow WebRequest for listed URL** ← ไม่ติ๊ก = รายการข้างล่างถูกละเลยทั้งหมด |
| 4 | เพิ่ม `127.0.0.1` **และ** `127.0.0.1:45001` |
| 5 | ★ **ปิดด้วย `File → Exit`** — ห้ามปิดด้วย Task Manager ไม่งั้น config ไม่ถูกเขียน |

## ✅ ปิดแล้วในรอบแก้นี้ — ไม่ต้องทำซ้ำ

ตรวจจากโค้ดจริงเมื่อ 2026-07-30 · [review](reviews/SPEC-063-03.md)

| finding | หลักฐาน |
|---------|---------|
| **T2** gate ผ่านฟรีเมื่อ suite ไม่มีรายชื่อ | `run-mql5-tests.ps1:261-265` guard ครบ ✅ |
| **B9** error code + context | `FarmExecutor.mq5:95-100` `BROKER_TIME_OFFSET_CHANGED` + `{old_offset_sec,new_offset_sec}` ✅ |
| **B10** `DiagnosticLine()` | `BrokerTime.mqh:305-325` — `local=` · `rounded_offset` แยก · เวลาอ่านออก ✅ **ดีกว่าที่ spec ขอ** |
| **B13** `detected_at` | `:118` + `Wire.mqh:468` ✅ |
| **B11** ULID seed | **Claude ถอน finding เอง** — seed มี `ChartID` + `ACCOUNT_LOGIN` อยู่แล้ว ไม่ต้องแก้ ✅ |
| **B8** seam retry loop | ตัวนับ `elapsed_ms` **ดีกว่าที่ spec เขียน** — Claude แก้ spec ตามโค้ด ✅ |
| **C3** backoff ถึง 30s cap | `test_wire_resilience.py:227-236` 7 connect + ยืนยัน monotonic ✅ |
| **C5** duplicate session หน่วง 60s | `:253-266` + เปลี่ยนชื่อ test ให้ตรงสิ่งที่ทดสอบ ✅ |
| **C8** log reader ฝั่ง EA | `mark_ea_log` / `read_ea_log_since` + test UTF-16 ✅ |
| **C12** soak ไม่ `sleep(3600)` | `:291-304` poll 0.5s + fail ภายใน ~4 วินาที ✅ **ตรงตามที่ขอเป๊ะ** |
| **C13** comment `monotonic` ข้ามโปรเซส | `echo_server.py:65` ✅ |
| **C9** เวลาที่ชุด fast ใช้จริง | **327 วินาที** — วัดได้แล้วจากการรันจริง ไม่ต้องเดา ✅ |
| **C10** `.set` โฟลเดอร์ไหนที่ `[StartUp]` อ่านจริง | terminal log: **`MQL5\Presets\farm-chaos.set`** · `write_startup_files()` เขียน 3 ที่ ใช้จริงที่เดียว → **ลบอีก 2 ที่ได้** ✅ |

**ยืนยันเพิ่ม:** `CBrokerTime` ทำงานถูกบนเทอร์มินัลจริง —
`broker_time valid=true offset=3600 detected_at_utc=2026.07.30 15:00:04`
`DiagnosticLine()` ที่เพิ่งแก้ **ใช้ debug ได้จริง** ไม่ใช่แค่ผ่าน test

---

## ✅ เสร็จแล้ว — Claude ตรวจหลักฐานจริงแล้ว ไม่ต้องทำซ้ำ

ตรวจเมื่อ 2026-07-28 · commit `543386e` `56bc78f` `7e1729e` `77386fc`

| งาน | หลักฐานที่ตรวจ |
|-----|----------------|
| `FILE_UTF8` → `FILE_BIN` + `CP_UTF8` | ไม่มี `FILE_UTF8` เหลือ |
| `ran_names` + harness ตรวจเทียบ 11 ชื่อ | `$requiredNames` ใน ps1 |
| `if(total < 0)` guard | 3 จุด |
| **❷ `PERIOD_H1`** | `EnumToString` เหลือ **0** · `FarmTimeframeCode()` 2 จุด |
| **1.1 ULID monotonic** | `NextMsgIdFromMs()` มี clamp `ts <= last → last+1` · ใช้ `TimeGMT()*1000` ไม่ปลอม sub-second · `m_ulid_rand_suffix` สุ่มครั้งเดียวต่อ instance ✅ **ตรงตามที่สั่งทุกข้อ** |
| **1.2 ULID seed** | ผสม `GetMicrosecondCount ^ TimeLocal ^ ChartID ^ ACCOUNT_LOGIN` ✅ |
| **1.3 test ULID** | เพิ่ม 3 ตัวครบ + **เปลี่ยนชื่อตัวที่อ่อนเป็น `test_msg_id_differs_between_wire_objects` ตามที่ขอ** ✅ |
| **1.4 `(int)` cast** | `grep` ไม่เหลือ cast เลย ✅ |
| **XM skip** | `[SKIP] $targetName -- reason:` + ติดตาม `$ranTargets` / `$skippedTargets` ✅ |
| **ผล gate** | อ่านจาก `ea-farm-IUX-TestWire-result.json` โดยตรง — `git_sha=77386fc…` **ตรงกับ HEAD ไม่ใช่ผลค้าง** · `status:PASS total:47 passed:47 failed:0` · `ran_names` 23 ชื่อ ✅ |

**`NextMsgIdFromMs(ulong)` แยกออกมาเป็น seam ให้ test ป้อน ms คงที่ได้ — ดีกว่าที่ spec ขอ**

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

## 1.5 🔴 chaos suite ต้อง EA-driven จริง — **ตัดสินแล้ว: ห้ามใช้ Strategy Tester**

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

### ❌ ข้อเสนอ "รัน FarmExecutor ผ่าน Strategy Tester" — ไม่รับ

**เหตุผลที่ตัดสินได้เลยโดยไม่ต้องทดลอง: Strategy Tester ใช้เวลาจำลอง**

chaos test ทั้ง 6 ตัวเป็นเรื่อง **wall-clock timing ล้วนๆ**:

| test | สิ่งที่วัด | ใน tester จะเป็น |
|------|-----------|-----------------|
| `test_backoff_schedule_matches_spec` | 1,2,4,8,16,30 วินาที**จริง** | เวลาจำลอง — ผ่านไปในพริบตา |
| `test_bad_token_waits_60s` | รอ 60 วินาที**จริง** | จบทันที ไม่ได้พิสูจน์ว่าไม่ hammer server |
| `test_heartbeat_gap_triggers_reconnect` | ขาด ack 3 ครั้ง × 2 วินาที | เวลาจำลอง |
| `test_no_heartbeat_loss_over_1h` | 1 ชั่วโมง**จริง** | 1 ชม.จำลองผ่านไปเป็นมิลลิวินาที |

`OnTimer` ใน tester เดินตาม **modeled time** ไม่ใช่นาฬิกาจริง
→ วัด "รอ 60 วินาที" เทียบกับ server ที่อยู่ในเวลาจริง = **คนละแกนเวลา วัดไม่ได้เลย**

แม้ socket จะใช้ได้ใน tester (ซึ่งยังไม่ยืนยัน — ดูหมายเหตุล่าง) ผลที่ได้ก็ยังไม่มีความหมาย

> ถ้าจะยืนยันเรื่อง socket ใน tester ให้เขียน probe 20 บรรทัดแบบเดียวกับ
> `tools/probe/TesterProbe.mq5` แล้วรายงานผล — **แต่ไม่ต้องทำ เพราะเหตุผลเรื่องเวลาปิดประตูไปแล้ว**

### ✅ ที่ต้องทำแทน: รัน `FarmExecutor` บน **live chart** ผ่าน `[StartUp]`

```ini
[StartUp]
Expert=FarmExecutor
Symbol=EURUSD.iux
Period=H1
ExpertParameters=farm-chaos.set
```
```
terminal64.exe /config:<ini>
```

เทอร์มินัลเปิดขึ้นมาแล้วแนบ EA เข้าชาร์ตใน **โหมดจริง** — นาฬิกาเป็นเวลาจริง
· EA เป็น timer-driven จึงทำงานได้แม้ตลาดปิด (ไม่ต้องรอ tick) **ทดสอบเสาร์-อาทิตย์ได้**

### สถาปัตยกรรม harness ที่ต้องการ

| หลัก | รายละเอียด |
|------|-----------|
| ใครสั่ง | **Python (pytest fixture)** launch เทอร์มินัลผ่าน `subprocess` — **ไม่ต้องเพิ่ม PowerShell** |
| อายุเทอร์มินัล | **เปิดครั้งเดียวทั้ง suite** (session fixture) · startup ~15–20 วินาที ต่อ test ไม่ไหว |
| ขับสถานการณ์จากไหน | **ฝั่ง server ทั้งหมด** — EA ตัวเดิม token เดิม แต่ `echo_server.py` เปลี่ยนพฤติกรรม |
| สังเกตผลจากไหน | (ก) socket ฝั่ง server เห็น connect/disconnect พร้อม timestamp · (ข) log ของ EA |

**ทุก 6 test ขับจากฝั่ง server ได้หมด — ไม่ต้องรีสตาร์ท EA เลย:**

| test | `echo_server.py` ทำอะไร |
|------|------------------------|
| `test_bad_token_waits_60s` | ตอบ `HELLO_ACK accepted:false reason:BAD_TOKEN` → จับเวลาว่า connect ครั้งถัดไปห่าง ≥ 60s |
| `test_duplicate_session_rejected` | ตอบ `DUPLICATE_SESSION` |
| `test_ea_reconnects_after_server_kill` | accept แล้วปิด socket ทิ้ง |
| `test_backoff_schedule_matches_spec` | ปิดทุกครั้งที่ต่อ → บันทึกช่วงห่างของ connect → เทียบ 1,2,4,8,16,30 **± jitter 20%** |
| `test_heartbeat_gap_triggers_reconnect` | accept ปกติ แต่ **หยุดส่ง `HEARTBEAT_ACK`** → ต้อง reconnect หลังขาด 3 ครั้ง |
| `test_no_heartbeat_loss_over_1h` | ตอบปกติ 1 ชม. → นับ heartbeat ที่ได้ ต้องไม่ขาดช่วง |

### แยก fast / slow — **`test_no_heartbeat_loss_over_1h` ห้ามอยู่ใน gate ปกติ**

| ชุด | เวลา | รันเมื่อไร |
|-----|------|-----------|
| fast (5 test) | ~3 นาที | ทุกครั้ง |
| slow (`..._over_1h`) | 1 ชั่วโมง | mark `@pytest.mark.slow` · รันมือ/รายคืน |

gate ที่ใช้เวลา 1 ชม.ทุกครั้ง = gate ที่ไม่มีใครรัน

### ✅ ยืนยันแล้ว: launch บน live chart **ทำงานอยู่แล้ว** — มีหลักฐาน

Codex ถามว่า *"ต้องยืนยันวิธี launch ให้ `OnInit` execute จริงก่อน"*
**ตรวจแล้ว — มันรันไปแล้วเมื่อ 00:40 วันนี้** ดูใน
`…\A45801173FBAFA01B9AFF0EEDE7938E3\MQL5\Logs\20260728.log`:

```
00:40:20.764  FarmExecutor (EURUSD.iux,H1)  FATAL component=FarmExecutor InpBrainToken is empty
```

บรรทัดนี้พิสูจน์ **4 อย่างพร้อมกัน**:

| | |
|---|---|
| EA แนบชาร์ต `EURUSD.iux,H1` ได้ | ✅ |
| **`OnInit` รันจริง** — ไปถึงบรรทัดเช็ค token แล้ว `return INIT_FAILED` | ✅ |
| บัญชี login อยู่ (`common.ini` → `Login=2101178419 Server=IUXMarkets-Demo`) | ✅ |
| `Print()` ของ EA ลงที่ `MQL5\Logs\YYYYMMDD.log` | ✅ ← **นี่คือช่องสังเกตผล** |

**ที่ขาดคือ `ExpertParameters` เท่านั้น** — ตอนนั้นไม่ได้ส่ง `.set` เข้าไป token จึงว่าง
· `farm-chaos.set` ที่คุณสร้างตอน 00:54 มี `InpBrainToken=test-token` แล้ว **ยังไม่ได้ลองรันซ้ำ**

### ini สำหรับ live chart

```ini
[Common]
Login=2101178419
; ห้ามใส่ Password — บัญชีจำไว้แล้วใน common.ini (AGENTS ข้อ 4)

[Experts]
AllowLiveTrading=1
Enabled=1
Account=0
Profile=0

[StartUp]
Expert=FarmExecutor
ExpertParameters=farm-chaos.set
Symbol=EURUSD.iux
Period=H1
```
```
terminal64.exe /config:<ini>
```

`FarmExecutor.ex5` deploy อยู่ที่ `MQL5\Experts\FarmExecutor.ex5` แล้ว → `Expert=FarmExecutor` (ไม่มี path)

**⚠️ กับดักที่ต้องลองก่อน:** `[Tester]` อ่าน `.set` จาก `MQL5\Profiles\Tester\`
แต่ **`[StartUp]` อาจอ่านจาก `MQL5\Presets\`** — ถ้า token ยังว่างหลังใส่ `ExpertParameters`
ให้ก๊อป `.set` ไปไว้ `MQL5\Presets\` แล้วลองใหม่ · **รายงานว่าโฟลเดอร์ไหนถูกใน handoff**
(ข้อมูลแบบนี้หายง่าย ต้องบันทึกไว้เหมือน 5 กับดักใน [gate-02 §4](reviews/SPEC-001-compile-gate-02.md))

**⚠️ `[StartUp]` ไม่มี `ShutdownTerminal`** — เทอร์มินัลจะค้างเปิด
Python fixture **ต้อง kill process เองตอนจบ** (และเช็คว่าไม่มีตัวเปิดค้างก่อนเริ่ม)

### วิธีอ่าน log จาก Python — `MQL5\Logs\*.log` เป็น **UTF-16LE**

```python
open(log_path, encoding="utf-16-le")     # ไม่ใช่ utf-8
```
เปิดเป็น utf-8 จะได้ข้อความแทรกด้วย `\x00` แล้ว regex ไม่แมตช์
— เสียเวลาไล่หาสาเหตุเป็นชั่วโมงถ้าไม่รู้

### 🔴 สิ่งที่ยัง**ไม่รู้** และเป็นด่านถัดไป: socket whitelist

รอบ 00:40 EA fail ที่เช็ค token **ก่อนถึง `g_wire.Init()`** → **ยังไม่เคยมีการเรียก
`SocketConnect` เลยสักครั้ง** เราจึงยังไม่รู้ว่า MT5 ยอมให้ต่อ `127.0.0.1` ไหม

**และตั้งค่านี้ script ไม่ได้** — ผมตรวจแล้ว `config\settings.ini` เป็น **ไฟล์เข้ารหัส**
(อ่านเป็น binary ไม่ใช่ ini) → รายการ allowed URL แก้ได้จาก **GUI เท่านั้น**

**ขั้นตอนถัดไปที่ชัดเจน:**
1. รัน ini ข้างบนพร้อม `farm-chaos.set` + `echo_server.py` ฟังที่ port 60083
2. ดู `MQL5\Logs\` — ถ้าเจอ error ของ `SocketConnect` → **เจ้าของต้องเปิดให้ด้วยมือ**
   Tools → Options → Expert Advisors → เพิ่ม `127.0.0.1`
3. ไม่ว่าผลเป็นอย่างไร **บันทึกเป็นขั้นตอน setup ในรายงาน** — เป็น state ของเครื่อง
   ที่ไม่อยู่ใน git เครื่องใหม่จะไม่มี (จะย้ายไป runbook SPEC-030b)

> [SPEC-001 §5 edge 10](specs/SPEC-001-mt5-executor.md) สั่งไว้แล้วว่า ถ้า `SocketConnect`
> fail ต้อง log ข้อความที่**บอกวิธีแก้** — นี่คือเคสที่กฎข้อนั้นถูกออกแบบมาเพื่อ

### 📌 หมายเหตุ: การแก้ config ของเทอร์มินัลต้องบันทึก

เจอ `config\common.ini.codex-backup-20260728-005148` — **สำรองไว้ก่อนแก้ ทำถูกแล้ว**
(ตรวจแล้วเนื้อไฟล์ปัจจุบันเหมือน backup ทุกบรรทัด = ไม่ได้เปลี่ยนอะไรค้างไว้)

แต่ config ของเทอร์มินัล **อยู่นอก git** → ทุกการเปลี่ยนต้องลงใน handoff
ไม่งั้นเครื่องใหม่จะตั้งไม่เหมือนเดิมแล้วหาสาเหตุไม่เจอ

### ต้องเช็คก่อนเริ่ม (2 ข้อ)

1. **socket whitelist** — MT5 บล็อก `SocketConnect` ถ้า host/port ไม่อยู่ใน allow list
   (Tools → Options → Expert Advisors) · [SPEC-001 §5 edge 10](specs/SPEC-001-mt5-executor.md)
   ระบุไว้แล้ว · **ยืนยันว่า `127.0.0.1` ตั้งไว้แล้วในเทอร์มินัล IUX** ก่อนเขียน test
   ถ้าตั้งด้วยมือ ให้บันทึกเป็นขั้นตอน setup ในรายงาน (จะย้ายไป runbook SPEC-030b)
2. **เทอร์มินัลต้องไม่เปิดอยู่ก่อน** — เช็คแบบเดียวกับที่คุณเพิ่งใส่ใน `run-mql5-tests.ps1`

### 📄 spec เต็มออกแล้ว — [SPEC-016](specs/SPEC-016-chaos-harness.md)

**§1.5 และ §1.6 คือ "ชั้น A" ของ SPEC-016** — ต้องการแค่ SPEC-001 ที่มีอยู่แล้ว
เริ่มได้ทันทีไม่ต้องรอ ticket อื่น · 7 scenario + 6 test ของตัว harness เอง

ในนั้นมีของที่ยังไม่ได้เขียนไว้ที่นี่:
- `ScriptedServer` API เต็ม (`reject_next_hello` · `stop_acking_heartbeats` · `stop_reading_socket` …)
- `TerminalController` API + กฎ `kill()` ต้องถูกเรียกแม้ test fail
- **เกณฑ์เวลาที่หลวมพอไม่ให้ flake แต่ยังจับของผิด** — backoff ต้องอยู่ใน [0.7×, 1.5×]
  และ**ต้องไม่ลดลง** · ผูกเกณฑ์กับ "พฤติกรรมผิดแบบไหนที่ต้องจับ" ไม่ใช่ตัวเลขเป๊ะ
- **ห้ามใส่ retry ให้ test ที่ flake** — chaos test ที่ retry จนผ่านบอกอะไรไม่ได้เลย
  และการ flake มักแปลว่าพฤติกรรมจริงไม่นิ่ง ซึ่งคือสิ่งที่เรากำลังหาอยู่พอดี
- **log reader ต้องจดตำแหน่งเริ่มต้นก่อนแต่ละ scenario** — กับดักผลค้างแบบเดียวกับ
  `out-*.json` ใน SPEC-005

### 💡 harness นี้ถูกใช้ซ้ำใน SPEC-010

[SPEC-010 §7](specs/SPEC-010-state-reporter.md) ต้องการ Python test 5 ตัวที่ต้องมี EA จริง
เหมือนกัน (`test_backfill_300_bars_all_received_in_order`,
`test_heartbeat_uninterrupted_during_backfill`) — **ออกแบบให้ reuse ได้ตั้งแต่แรก**
อย่าทำเฉพาะกิจสำหรับ chaos

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
| 1 | **determinism** — `python tools/task.py codegen` 2 ครั้งต้อง byte-identical · sort เอง ห้ามพึ่ง `os.listdir()` · ห้ามใส่ timestamp ในหัวไฟล์ · pin `==` |
| 2 | **`additionalProperties`** ต้องเป็น `ignore` **ห้าม `forbid`** (ยกเว้น `config_update.settings` ที่เดียว) |
| 3 | **`null` ≠ `0` ≠ ไม่มี field** — MQL5 คืน `0.0` เมื่อไม่มี SL · schema มี `exclusiveMinimum: 0` → ส่ง `0` จะ fail · ต้องมี helper ตัวเดียว ไม่ใช่เช็คกระจาย |

`contracts/fixtures/invalid/` 4 ไฟล์แรกคือกับดักที่ดัก bug จริงไว้ — ทำให้มันแดงถูกต้อง

---

# รอบที่ 4 — SPEC-010 StateReporter

📄 [spec เต็ม](specs/SPEC-010-state-reporter.md) · **SPEC_READY** · 24 test (MQL5 19 · Python 5)
· ต้องรอ SPEC-004 **และ** SPEC-063 merge ก่อน

**★ จุดที่จะกินเวลามากที่สุด — backfill pacing**

คำนวณแล้ว: `InpSendQueueMax = 256` แต่ backfill = **300 bar** และนโยบายตอนคิวเต็มคือ
**ทิ้งตัวเก่าสุด** → enqueue รวดเดียว = **44 bar เก่าที่สุดหายเงียบ** ซึ่งคือตัวที่ brain
ต้องใช้ warm feature window พอดี

แล้วอาการที่เห็นจะเป็น *"EA reconnect ตลอดเวลา"* เพราะ heartbeat โดนเบียดออกจากคิวด้วย
→ gateway ตัด session → reconnect → backfill เริ่มใหม่ → **วนไม่จบ**
คนจะไปไล่หาปัญหาที่ socket ทั้งที่ต้นเหตุคือ backfill กินคิว

**แก้ด้วย pacing ไม่ใช่เพิ่ม queue** — เติมได้เท่าที่ `SendQueueDepth() < queue_max/2`
เหลืออีกครึ่งไว้ให้ heartbeat/STATE

**อีก 3 จุดที่พลาดง่าย:**
- **ห้ามส่ง shift 0** — bar ที่ยังไม่ปิด = look-ahead bias · `bar.json` บังคับ `is_final: const true`
- **`sl`/`tp` = `0.0` → ส่ง `null`** — ทำ helper ตัวเดียว ห้ามเช็คกระจาย
- **ownership ต้องเช็คทั้ง `magic` และ `symbol`** ไม่ใช่แค่ magic

---

# รอบที่ 5 — SPEC-064 SymbolRegistry

📄 [spec เต็ม](specs/SPEC-064-symbol-registry.md) · **SPEC_READY** · 20 test · ต่อจาก SPEC-004 ได้ทันที

ปิด [G7](06-gap-audit.md) ที่ตอนนี้เกิดขึ้นจริงแล้ว:

```
IUX: EURUSD.iux · XAUUSD.iux      XM: EURUSD · GOLD
                                          └── เดาด้วย string rule ไม่ได้
```

**หัวใจ 3 ข้อ:**

| | |
|---|---|
| **fail-closed** | เจอ raw ที่ไม่มีในตาราง → EA `INIT_FAILED` · brain ทิ้ง message · **ห้ามเดา** |
| **ห้ามตัด suffix** | acceptance มี `grep` ห้ามเจอ `.replace` / `StringSubstr` / `removesuffix` ใน path นี้ — ต้องเป็น table lookup ล้วน |
| **cross-check 2 ฝั่ง** | MQL5 dump ทุก mapping ลง JSON แล้ว Python เทียบทีละคู่ — **ถ้าสองฝั่งไม่ตรง ระบบจะนับ exposure ผิดโดยไม่มีอะไรพัง** |

`contracts/symbols.json` **Claude กรอกเนื้อให้ครบแล้วใน spec §5** — ก๊อปไปใช้ได้เลย
**ห้ามแก้เอง** เพราะมีค่า risk (R5/R10/R11) อยู่ข้างใน

`max_spread_points` ยัง `null` ทั้ง 6 ตัว (ยังไม่ calibrate จากสถิติจริง)
→ R5 ข้าม + WARN · `production_ready = false` · **บล็อกที่ประตูเงินจริง ไม่ใช่บล็อกตอนนี้**

---

# รอบที่ 0 (แทรกได้ทุกเมื่อ) — SPEC-002 scaffold

📄 [spec เต็ม](specs/SPEC-002-repo-scaffold.md) · **SPEC_READY** · 9 test · **ไม่ขึ้นกับ ticket ไหนเลย**

> แทรกทำได้ทันทีที่ว่าง — และ**ควรทำก่อนรอบ 3 (SPEC-004)** เพราะ codegen ต้องมี
> runner กับ pytest config อยู่แล้ว

**🔴 แก้ของที่ผมเขียนผิดไว้: ไม่ใช้ `Makefile`**

ตรวจแล้ว **เครื่องนี้ไม่มี `make`** และจะไม่ติดตั้ง — VPS ที่จะ deploy จริงก็เป็น Windows
(MT5 รันได้แค่ Windows) make จึงไม่ได้ช่วยอะไรเลย มีแต่เพิ่มขั้นตอน setup + PATH quirks

→ **`tools/task.py`** เป็น runner แทน · ผมแก้ SPEC-004 · `02-contracts §6` · roadmap
· work-order ให้ตรงกันหมดแล้ว

**target ที่สำคัญที่สุดคือ `check`** = `lint + typecheck + test + codegen-check`

เพราะ **G3 ยังไม่ตัดสิน + ไม่มี git remote → ตอนนี้ไม่มี CI เลย**
`check` คือ CI ทั้งหมดที่โปรเจกต์นี้มี ณ ตอนนี้ · และเพราะพึ่งวินัยล้วน
มันต้อง**เร็วพอที่จะรันทุกครั้ง** → `slow` / `live_terminal` / `mql5` ถูกแยกออกจาก `test` ปกติ

**2 กฎที่ห้ามพลาด:**
- `check` **ต้องรันทุก target ให้จบแล้วค่อยสรุป** ห้ามหยุดที่ตัวแรกที่แดง
- `[SKIP]` **ห้ามนับเป็น pass** — กฎเดียวกับเป้า XM ใน MQL5 gate

---

# รอบที่ 5.5 — SPEC-005 Round-trip harness

📄 [spec เต็ม](specs/SPEC-005-roundtrip-harness.md) · **SPEC_READY** · 17 test · ต่อจาก SPEC-004 ทันที

**นี่คือข้อพิสูจน์ว่า codegen ถูกจริง** — "ทั้งสองฝั่ง compile ได้" ≠ "ทั้งสองฝั่งเข้าใจตรงกัน"
และเป็น **exit criteria ของ Phase 0** ตรงตัว

```
fixture → py parse → A → [mql5 parse → serialize] → B → py parse → A2
assert A2 == A          ★ ตกฟิลด์เดียวหรือปัดเลขผิด จับได้ทันที
assert ไม่มี e/E ใน B    ตรวจ B ดิบ เพราะ normalize จะกลบ 1e-05
```

**3 จุดที่กลับด้านจากสัญชาตญาณ:**

| | |
|---|---|
| **unknown field ต้อง *หาย* ไม่ใช่ต้องรอด** | forward compat บอกว่าให้ข้าม · ถ้า test แดงเพราะ field หาย = เข้าใจ test ผิด **ห้ามไป "แก้" ให้มันรอด** |
| **fixture `.extra.json` ไม่ได้ทดสอบ MQL5 เลย** | `extra="ignore"` ทำให้ pydantic ทิ้ง field ตั้งแต่ขั้นแรก → ต้อง**ฉีด** field แปลกเข้า `A` เองก่อนส่งให้ MQL5 |
| **ไม่ต้องทำทิศ MQL5→Python แยก** | `B` คือผลผลิตของ MQL5 ที่ Python เป็นคน parse อยู่แล้ว · อย่าสร้าง tester run รอบสอง ได้เพิ่มน้อยแลกเวลาสองเท่า |

**⚠️ ของใหม่ที่ยังไม่เคยทำ: MQL5 *อ่าน* ไฟล์**
harness เดิมเขียนอย่างเดียว · ต้องใช้ `FILE_BIN` + `CharArrayToString(..., CP_UTF8)`
**ห้ามใช้ `FILE_TXT`** (จะตีความตาม codepage เครื่อง อักษรไทยเพี้ยน) — บทเรียนเดียวกับ
gate-02 แต่กลับด้าน

**★★ test ที่สำคัญที่สุดคือ `test_stale_output_detected_when_ea_missing`**
harness แบบนี้มี failure mode ที่ **EA ไม่ได้รันเลยแต่ test เขียว** เพราะไฟล์ `out-*.json`
รอบก่อนยังค้างอยู่ · อาการคือ *"round-trip ผ่านมาตลอด"* ทั้งที่ codegen พังไปแล้วหลายวัน
→ ต้องมีกลไกกัน 3 ชั้น: ลบ output เก่าก่อนรัน · `cases_processed` เทียบ manifest ·
`git_sha` เทียบ HEAD (ชั้น 3 มีแล้วในของเดิม)

---

# รอบที่ 5.6 — SPEC-006 Database

📄 [spec เต็ม](specs/SPEC-006-database.md) · **SPEC_READY** · 16 test (marker `db`)
· **เขียนได้เลยโดยไม่ต้องรอ D13** (ติดตั้ง PG จริงค่อยทำตอนรัน test)

**🔴 สภาพเครื่องจริง:** ไม่มี Docker · ไม่มี PostgreSQL · มี WSL2
→ [roadmap](04-roadmap.md) ที่เขียนว่า "Docker Compose" ทำตามตรงๆ ไม่ได้
(บทเรียนเดียวกับ `make`)

**ตัดสิน: ยังไม่ใช้ TimescaleDB** — ปริมาณจริงไม่ต้องการ:

| เดิมคิดว่า | ความจริง |
|-----------|----------|
| ข้อมูล 10 ปี × 6 คู่ M1 ~22M แถว ต้องใช้ hypertable | **ไม่เข้า DB เลย** — SPEC-007 เก็บลง **Parquet** |
| `bars` ใน DB เยอะ | เฉพาะ bar **สด**จาก EA = หลักพันแถว/เดือน |
| `account_state` 103k/วัน | เก็บ 90 วัน ≈ 9M แถว — **PG เปล่ารับไหวสบาย** |

เป็น**ประตูที่เปิดกลับได้** (`create_hypertable(migrate_data => true)`)
แต่ห้ามใช้ฟีเจอร์ที่ผูกกับ Timescale ในระหว่างนี้ (acceptance มี `grep` ตรวจ)

## ★★ หัวใจของ ticket นี้: append-only ต้องบังคับที่ **DB** ไม่ใช่ Python

`intents` / `exec_reports` คือหลักฐานว่า *"ตอนนั้นระบบตัดสินใจอะไร และเกิดอะไรขึ้นจริง"*
วันที่พอร์ตเสียหายแล้วต้องหาสาเหตุ สองตารางนี้คือสิ่งเดียวที่ตอบได้

**ถ้าบังคับใน Python มันไม่ใช่การบังคับ** — เป็นแค่ข้อตกลง เขียน query ตรงๆ ก็ข้ามได้
→ ต้องเป็น **trigger** ที่ปฏิเสธ `UPDATE`/`DELETE` โดยยอมเฉพาะเติม `ack_status` **ครั้งเดียว**
· spec §5.1 ให้ SQL ของ trigger ไว้ครบแล้ว

**test 4–8 คือหัวใจ** — `UPDATE intents` ต้องโดนปฏิเสธ **จาก DB ไม่ใช่จาก Python**
· และข้อ 8 (`ack update ห้ามแก้คอลัมน์อื่นไปด้วย`) คือช่องโหว่ที่คนมองข้าม

**อีก 3 จุด:**
- ทุกคอลัมน์เวลา `TIMESTAMPTZ` + **UTC เท่านั้น** — ตรวจด้วย query จาก `information_schema` ไม่ใช่ตาดู
- `bars.symbol` เก็บ **raw** (`EURUSD.iux` / `GOLD`) คู่กับ `broker` — ถ้าเก็บ canonical แล้ววันหนึ่ง mapping เปลี่ยน ข้อมูลเก่าจะตีความไม่ได้อีก
- `insert_bar` ซ้ำ → `ON CONFLICT DO NOTHING` **แต่ต้องนับ** · `insert_intent` ซ้ำ → **error** (คนละนโยบายโดยตั้งใจ — intent ซ้ำ = dedupe พัง ต้องเห็น)

---

# รอบที่ 5.7 — SPEC-013 Gateway  ★ คอขวดของ Phase 1

📄 [spec เต็ม](specs/SPEC-013-gateway.md) · **SPEC_READY** · 27 test
· ต้องรอ 002 · 004 · 006 · 064

**ไม่มี gateway = ทดสอบ end-to-end ไม่ได้เลย** — ทุก ticket ที่เหลือใน Phase 1 รอตัวนี้

## ★★ จุดที่ต้องคิดให้ขาด: duplicate session (§4.2)

spec เดิมสองที่ขัดกัน และ ticket นี้ตัดสิน:

- SPEC-001 edge 9 บอกว่า EA ตัวที่สองต้องได้ `DUPLICATE_SESSION`
- แต่ **EA ที่ reconnect หลังเน็ตหลุดส่ง `session_id` เดิม** และ server อาจยังไม่รู้ว่า
  connection เก่าตาย → reject ตรงๆ = EA รอ 60 วินาที **แล้ววนไม่จบจนกว่า TCP จะยอมตาย**
  อาการที่เห็นคือ *"EA ต่อไม่ติดเป็นชั่วโมง"* หลังเน็ตสะดุดวินาทีเดียว

**กฎที่ใช้: แยกสองเคสด้วย *ความถี่* ไม่ใช่ด้วยตัว message**

| | |
|---|---|
| ซ้ำครั้งที่ 1–2 ใน 5 นาที | **ตัวใหม่ชนะ** — ปิดตัวเก่า `eviction_count++` |
| โดน evict **≥ 3 ครั้งใน 5 นาที** | **นี่คือ EA สองตัวจริง** → `DUPLICATE_SESSION` + alert |

reconnect เกิดนานๆ ครั้ง · การแย่งกันเกิดตลอดเวลา → `eviction_count` เป็นตัวแยกสองสถานการณ์นี้

## ★★ อีกคู่ที่สำคัญที่สุด: session พังตัวเดียวห้ามลากตัวอื่นลง

| | |
|---|---|
| คิวขาออกเต็ม | **`raise OutboundQueueFull` ห้าม drop เงียบ** — ต่างจากฝั่ง EA เพราะที่นี่คือ `INTENT` = คำสั่งเทรด · ถ้าหายเงียบ brain จะคิดว่าสั่งแล้วแต่ไม่มีอะไรเกิด |
| EA ไม่อ่าน socket | `drain()` ต้องมี **timeout** → ตัด session นั้น · **session อื่นต้องไม่กระทบ** |
| handler ฝั่ง brain raise | session **ยังอยู่** + นับไว้ · EA ไม่ควรโดนตัดเพราะ bug ฝั่งเรา |

test 22–23 คือคู่นี้

## 3 จุดที่เหลือ

- **ตรวจซ้ำชั้นที่สอง** — `MARGIN_MODE_NOT_HEDGING` + `SYMBOL_NOT_IN_REGISTRY` ที่ HELLO
  EA ควร fail ที่ `OnInit` ไปแล้ว แต่ EA เก่าหรือถูกแก้อาจข้าม (ผมเพิ่ม enum ใน schema ให้แล้ว)
- **`ts_sent >= ts_server`** — gateway คือที่ที่ตรวจได้จริงเพราะเห็นทั้งสองค่า
  → เป็นเครื่องตรวจว่า SPEC-063 ทำงานจริงไหม **จากฝั่งที่เป็นกลาง** · WARN ห้ามปิด session
- **`echo_server.py` ต้องอยู่ต่อ** — คนละหน้าที่ (test double ที่สั่งให้พังได้ vs ตัวจริง)
  **ห้ามรวมกัน** — ตัวจริงที่มี "โหมดทำตัวพัง" คือของอันตราย

---

# รอบที่ 5.8 — SPEC-007 Data ingest

📄 [spec เต็ม](specs/SPEC-007-data-ingest.md) · **SPEC_READY** · 18 test
· **เริ่ม `resample.py` + test 1–6 ได้เลยโดยไม่ต้องมี MT5** (เป็นฟังก์ชันบริสุทธิ์)

## 🔴 กับดักที่ตรวจเจอแล้วจากเครื่องจริง

**`config\common.ini` ตั้ง `[Charts] MaxBars=100000`
แต่ M1 10 ปี ≈ 3.8 ล้าน bar/symbol = เกินเพดาน 38 เท่า**

→ ดึงเป็น**รายเดือน** (~30k bar/ครั้ง) · **นับผลทุกช่วง** · ได้น้อยกว่าคาด = WARN
ไม่ใช่เขียนลงไฟล์เงียบๆ · **acceptance: M1 ต่อปีต้อง ≥ 300,000 แท่ง**
ถ้าได้ ~100,000 แปลว่าชนเพดาน **ต้องรายงาน ไม่ใช่ยอมรับ**

`common.ini` แก้ได้ (ต่างจาก `settings.ini` ที่เข้ารหัส) แต่**ห้ามแก้เอง** — รายงานมาพร้อมตัวเลข

## ★★ ห้ามแปลงเป็น UTC ใน ticket นี้

ทางที่ง่ายคือเอา offset ปัจจุบันจาก `CBrokerTime` ลบออกจากทุกแท่ง — โค้ดบรรทัดเดียว
**แล้วมันจะผิดประมาณครึ่งปี ทุกปี** เพราะโบรกเกอร์เลื่อนตาม DST ปีละ 2 ครั้ง
และเราไม่มีปฏิทินย้อนหลัง 10 ปี

ความผิดพลาดแบบนี้ **ไม่ทำให้อะไรพัง** — Parquet เขียนได้ · backtest รันได้ · ตัวเลขสวย
แล้วเราจะเชื่อมันไปจนถึงวันที่เอาเงินจริงลง

→ เก็บ `time_broker` แบบ **naive** ห้ามใส่ tzinfo ห้ามบวกลบ
· acceptance มี `grep` ห้ามเจอ `tz_localize` / `astimezone` / `utc`
· เพิ่มหนี้ **D15** ให้ไปแก้ตอน SPEC-032/033 ซึ่งเป็นตอนที่มีเวลาแก้

## ★★ resample ต้องพิสูจน์ด้วย ground truth ที่มีอยู่แล้ว

**MT5 มี H1/H4 ของตัวเอง** → resample M1→H1 แล้วเทียบ **ต้องตรงทุกแท่ง**

ถ้าไม่ตรง = backtest ทุกตัวที่สร้างบนนั้นผิดตาม **โดยไม่มีอะไรพัง**

4 จุดที่ resample พลาดบ่อย: ขอบ H4 (00/04/08 **ตามเวลา broker**) · ห้ามสร้างแท่งเปล่าตอนตลาดปิด ·
`tick_volume` ต้อง**รวม**ไม่ใช่เอาค่าสุดท้าย · แท่งสุดท้ายที่ไม่ครบต้อง**ตัดทิ้ง**

## ⚠️ ingest กับ MQL5 gate ใช้เทอร์มินัลพร้อมกันไม่ได้

`ingest` ต้องการเทอร์มินัล **เปิดและ login** · gate/roundtrip ต้องการ **ปิดสนิท**
→ ต้องเช็คกันและกัน + เขียนไว้ใน `docs/setup.md`

## Q1 ที่ต้องพิสูจน์ก่อนดึงจริง

`copy_rates_range` ตีความ `date_from`/`date_to` เป็น **UTC หรือเวลา broker**?
→ ดึง 1 วันที่รู้ผลแล้วเทียบกับชาร์ตใน MT5 · **รายงานพร้อมหลักฐาน**
ผิดตรงนี้ = ข้อมูลเลื่อนทั้งชุดโดยไม่มีอะไรฟ้อง

---

# รอบที่ 5.9 — SPEC-008 Data quality gate

📄 [spec เต็ม](specs/SPEC-008-data-quality-gate.md) · **SPEC_READY** · 22 test
· **เขียนได้ทันที ไม่ต้องรอ SPEC-007** — unit test ทั้ง 22 ตัวใช้ข้อมูลสังเคราะห์

## ★★ กฎที่สำคัญที่สุด: ห้ามแก้ข้อมูล

ห้าม `fillna` · `interpolate` · `ffill` · ลบแท่งที่ดูแปลก · เขียนทับไฟล์ใน `data/bars/`

**quality gate ที่ซ่อมข้อมูลเงียบๆ แย่กว่าไม่มี gate เลย** — หลังจากนั้นจะไม่มีใครรู้ว่า
ตัวเลขที่เห็นเป็นของจริงหรือของที่เราเติมเข้าไป และ **backtest จะดูดีขึ้นด้วยเหตุผลที่ไม่ใช่กลยุทธ์**

หน้าที่คือ**ชี้ว่าตรงไหนเชื่อไม่ได้** ผ่าน `bad_ranges.json` แล้วให้ SPEC-031/032 ข้ามเอง
· acceptance มี `grep` + เทียบ checksum ก่อน/หลังรัน

## ★★ session profile — เรียนจากข้อมูลเอง ไม่ใช้ปฏิทินภายนอก

ปัญหาหลักคือแยก **"ตลาดปิดปกติ"** ออกจาก **"ข้อมูลหาย"** — ทองมีพักรายวัน FX ไม่มี
และเราไม่มีปฏิทินของโบรกเกอร์รายไหนเลย

นับว่าแต่ละ `(วันในสัปดาห์, นาทีของวัน)` มีแท่งกี่ % ของสัปดาห์ทั้งหมด:

| % | ตีความ | แท่งที่หาย |
|---|--------|-----------|
| > 0.90 | ช่วงเทรดปกติ | 🔴 นับเป็น gap |
| < 0.10 | ปิดปกติ | ✅ ไม่นับ |
| 0.10–0.90 | ก้ำกึ่ง (วันหยุด · ขอบ DST) | 🟡 รายงานแยก |

**ใช้ได้เพราะข้อมูลเป็นเวลา broker แบบ naive** (SPEC-007 §4.3) และโบรกเกอร์เลื่อนตาม DST
ไปพร้อมตลาด → **session ในเวลา broker นิ่งข้าม DST** — การตัดสินใจใน SPEC-007 จ่ายผลตรงนี้พอดี

## ★ แยก gap ของ symbol เดียว ออกจาก gap ของทั้งตลาด

คริสต์มาสจะทำให้ทุก symbol หายพร้อมกัน — ไม่ใช่ปัญหาเรา
แต่ `EURUSD` หายวันหนึ่งขณะที่อีก 5 ตัวครบ — **นั่นคือปัญหา**

หายพร้อมกัน **≥4 ใน 6** → `GAP_MARKET_WIDE` รายงานอย่างเดียว
· หายเฉพาะบางตัว → `GAP_SYMBOL_SPECIFIC` **นับเข้าเกณฑ์ 0.1%**

→ **ไม่ต้องมีปฏิทินวันหยุดเลย** และได้ผลถูกกว่าปฏิทินสำเร็จรูป เพราะสะท้อนวันหยุด
ของโบรกเกอร์รายนี้จริงๆ

## spike ใช้ MAD ไม่ใช่ standard deviation

`|r_t| > 20 × median(|r|)` บนหน้าต่าง 1440 แท่ง — **ใช้ sd ไม่ได้เพราะ spike
จะดึง sd ขึ้นจนไม่จับอะไรเลย** · และเกณฑ์เป็น pip คงที่ใช้ข้าม symbol ไม่ได้

**test 10 · 12 · 20 คือสามตัวที่สำคัญที่สุด** — 10/12 คือตัวที่ถ้าผิดรายงานจะเต็มไปด้วย
false positive จนไม่มีใครอ่าน · 20 คือตัวที่ปกป้องกฎ "ห้ามแก้ข้อมูล"

---

# รอบที่ 5.10 — SPEC-014 Persistence

📄 [spec เต็ม](specs/SPEC-014-persistence.md) · **SPEC_READY** · 18 test (marker `db`)
· ต้องรอ 006 + 013

## ★★ กฎเดียวที่เป็นหัวใจ: **ไม่มีหลักฐาน = ไม่เทรด**

**ต้องเขียน `intents` ให้ commit สำเร็จ *ก่อน* ส่ง INTENT ออกสาย**

```
เขียน intents (commit)  →  gateway.send_intent()  →  รอ INTENT_ACK
         │
         └─ ล้มเหลว → raise → ไม่ส่งอะไรออกสายเลย
```

เหตุผล 2 ข้อ:
1. `exec_reports.intent_id` มี **FK ไปที่ `intents`** — EA อาจตอบกลับเร็วกว่าที่เราเขียนเสร็จ
2. ★ ถ้าส่งก่อนเขียนแล้วโปรเซสตายระหว่างนั้น จะมี **order เกิดขึ้นจริงโดยไม่มีบันทึก**
   ว่าใครสั่ง ตอนไหน ด้วยเหตุผลอะไร

**ยอมให้ intent ตกหล่นเพราะ DB ล่ม ดีกว่ายอมให้ order ไม่มีหลักฐาน**

→ `brain` ต้องเรียกผ่าน `IntentDispatcher` เท่านั้น · acceptance มี `grep` ว่า
`send_intent` เจอได้เฉพาะใน `dispatch.py` กับ `gateway/`

## ★★ สองเส้นทางเขียน — เลือกคนละแบบโดยตั้งใจ

| | ใช้กับ | DB ล่มแล้ว |
|---|--------|-----------|
| **durable (sync)** | `intents` · `intent_ack` | 🔴 **หยุดเทรด** |
| **buffered (async batch)** | `exec_reports` | 🟠 buffer · **ห้าม drop** · เต็ม = FATAL alert |
| | `account_state` · `bars` | 🟡 drop ตัวเก่าสุด + นับ |

**ทำไมไม่ durable ทั้งหมด:** SPEC-013 edge 9 บังคับว่า handler ห้ามบล็อกการอ่าน socket
— ถ้า `on_bar` รอ commit ทุกแท่ง ตอน backfill 300 แท่ง gateway จะค้างจน EA heartbeat timeout

**ทำไมไม่ buffer ทั้งหมด:** เหตุผลข้างบน

## ทำไม "DB ล่ม = ไม่เทรด" ถึงถูก

ทางที่ดูยืดหยุ่นกว่าคือเทรดต่อแล้ว log ลงไฟล์ไว้ก่อน — **แต่ DB ล่มไม่ใช่เหตุการณ์สุ่ม**
มันมักเกิดพร้อมดิสก์เต็ม · เครื่องโหลดหนัก · เน็ตมีปัญหา · โปรเซสกำลังจะตาย

แปลว่าช่วงที่บันทึกไม่ได้ คือช่วงที่**มีแนวโน้มจะเกิดเรื่องมากที่สุด**
ระบบที่เทรดต่อในช่วงนั้นกำลังเลือกที่จะ**ไม่มีหลักฐานพอดีตอนที่ต้องการมันที่สุด**

**test 1 · 2 · 4 คือสามตัวที่สำคัญที่สุด** — ทั้งสามคือกฎนี้

---

# รอบที่ 5.11 — SPEC-017 Reconciliation

📄 [spec เต็ม](specs/SPEC-017-reconciliation.md) · **SPEC_READY** · 15 test
· ต้องรอ 010 + 011 + 063 · เป็น **exit criteria ของ Phase 1**

## ★★ กฎหลัก: รายงานความจริง อย่าลงมือ

สัญชาตญาณตอนเห็น position ค้างหลังรีสตาร์ตคือ *"ต้องจัดการมัน"* — ปิดทิ้งให้สะอาด
หรือเปิดเพิ่มให้ตรงกับที่เคยตั้งใจ · **ทั้งสองทางผิด เพราะ EA ไม่มีข้อมูลพอที่จะตัดสิน**

มันไม่รู้ target ล่าสุด · ไม่รู้ว่า regime เปลี่ยนไหม · ไม่รู้ว่าบัญชีอื่นถืออะไร ·
ไม่รู้ว่าช่วงที่หายไปเกิดอะไรในตลาด

การปิดทิ้งอัตโนมัติ = **รับรู้ขาดทุนในจังหวะที่เลือกโดยความบังเอิญ** (จังหวะที่ EA รีสตาร์ตพอดี)

**ข้อยกเว้นเดียว: internal hedge** — net ออกได้เลย เพราะมัน**ไม่มีทางถูกต้องไม่ว่ากลยุทธ์ไหน**
(exposure สุทธิเท่าเดิม แต่จ่าย spread+swap 2 ขา) → การ net ออกเป็นการกระทำที่ปลอดภัยเสมอ

## ★★ คุณสมบัติที่ไม่ชัดเจน: dedupe cache **ไม่ต้อง** รอดข้ามรีสตาร์ต

สถานการณ์ที่ดูน่ากลัว:
```
brain ส่ง X → EA ทำสำเร็จ → EA ตายก่อนส่ง ACK → brain ส่ง X ซ้ำ
→ EA กลับมาไม่มี cache → ทำซ้ำ → position สองเท่า?
```

**ไม่เกิด** — `INTENT` เป็น **target-state ไม่ใช่คำสั่ง** · รอบสอง reconciler เห็น
`N = 0.20` `T = 0.20` → **NOOP**

นี่คือผลตอบแทนของการเลือก target-state ตั้งแต่ต้น และเป็นเหตุผลที่ AGENTS ข้อ 12
ห้ามเปลี่ยนเป็น imperative order command

→ **ห้าม over-engineer persist cache ลงดิสก์** ไม่ได้ให้ความปลอดภัยเพิ่มเลย

## 🔴 กับดักที่ทำให้ position กลายเป็นสองเท่า

`PositionsTotal()` ตอน terminal เพิ่งเปิด อาจคืน **0 ทั้งที่มี position จริง** (ยังไม่ sync)

ถ้าเชื่อค่านั้น → รายงานว่า "ไม่มีอะไร" → brain คิดว่า flat → **ส่ง intent เปิดใหม่ = สองเท่า**

→ อ่านซ้ำ 3 ครั้ง ห่างกัน 500 ms ต้องได้เท่ากัน · ไม่นิ่งใน 10 วิ → **`INIT_FAILED`**
**ยอมไม่สตาร์ท ดีกว่าสตาร์ทแล้วรายงานภาพที่ไม่จริง**

## ลำดับที่บังคับ

```
READY → 1. STATE ทันที ← ก่อน backfill ก่อนทุกอย่าง
        2. ERROR ถ้ามี anomaly
        3. backfill 300 bar
```
+ กฎที่ผูกไปถึง brain: **ห้ามส่ง INTENT ให้ session ที่ยังไม่เคยส่ง STATE**

**test 12 · 13 คือสองตัวที่เงินหายถ้าผิด** — 12 คือ EA ลงมือเองตอนที่ไม่ควร ·
13 คือ order ซ้ำหลังรีสตาร์ต

---

# รอบที่ 5.12 — SPEC-012 Intent cache

📄 [spec เต็ม](specs/SPEC-012-intent-cache.md) · **SPEC_READY** · 15 test · ต้องรอ 011 + 063
· **ตัวเล็กที่สุดในชุด** แต่มี 2 จุดที่ผิดแล้วเงินหาย

## ★★ ลำดับการเช็คเปลี่ยนคำตอบที่ brain เห็น

```
1. dedupe → DUPLICATE
2. expiry → EXPIRED
3. guard  → REJECTED_BY_GUARD
4. reconcile → ACCEPTED / NOOP
```

**dedupe ต้องมาก่อน expiry** — intent ที่เคยตอบไปแล้ว ถ้าส่งซ้ำหลังหมดอายุ
คำตอบต้องเป็น `DUPLICATE` **ไม่ใช่ `EXPIRED`**

ถ้าตอบ `EXPIRED` brain จะเข้าใจว่าคำสั่งไม่เคยถูกทำ ทั้งที่ทำไปแล้ว → **อาจส่งใหม่แล้วเปิดซ้ำ**

## ★★ ตัดสินไม่ได้ = ปฏิเสธ ไม่ใช่ปล่อยผ่าน

`valid_until` เป็น UTC → ต้องเทียบกับ **`CBrokerTime.NowUtc()` เท่านั้น**
ห้าม `TimeCurrent()` (เวลา broker) ห้าม `TimeGMT()` (พึ่งนาฬิกาเครื่อง)

`IsValid() == false` → `REJECTED_INVALID` reason `BROKER_TIME_UNAVAILABLE`
— **เทรดโดยไม่รู้ว่าคำสั่งหมดอายุหรือยัง = เทรดด้วยข้อมูลที่อาจเก่าหลายนาที**

acceptance มี `grep` ห้ามเจอ `TimeCurrent`/`TimeGMT`/`TimeLocal` ในไฟล์นี้

## cache เก็บ "คำตอบ" ไม่ใช่แค่ id

`(intent_id, final_status, ts)` → ตอบ `DUPLICATE` พร้อม `reason = "original_status=ACCEPTED"`

เวลา debug ว่า *"ทำไม order ไม่เกิด"* ต้องแยกออกว่ารอบแรกตอบ `ACCEPTED` (ทำไปแล้ว)
หรือ `REJECTED_BY_GUARD` (ไม่เคยทำ) — ถ้าตอบ `DUPLICATE` เปล่าๆ ข้อมูลนั้นหายไป

## ห้าม over-engineer 2 อย่าง

- **ห้าม persist ลงดิสก์** — SPEC-017 §4.5 พิสูจน์แล้วว่าไม่ได้ให้ความปลอดภัยเพิ่ม
- **ห้ามทำ hash table** — ring buffer + linear scan พอที่อัตราไม่กี่ intent ต่อนาที
  ถ้า `Pump()` p99 เกิน 20 ms เพราะตัวนี้ ค่อยรายงานตัวเลขมา

**cache นี้เป็นเครื่องมือของความชัดเจน ไม่ใช่ความปลอดภัย** — brain ต้องได้คำตอบที่คงที่
สำหรับคำถามเดิม ไม่งั้น `intents` ใน DB จะมีสองแถวที่เล่าเรื่องคนละแบบสำหรับคำสั่งเดียว

---

# รอบที่ 5.13 — SPEC-018 Consistency checker

📄 [spec เต็ม](specs/SPEC-018-consistency-checker.md) · **SPEC_READY** · 15 test
· ต้องรอ 014 + 064 · เป็น **exit criteria ของ Phase 1**
· **เริ่ม checker + unit test ทั้ง 15 ได้เลยด้วยข้อมูลสังเคราะห์**

## ★★ งานที่สำคัญที่สุดของเครื่องมือนี้: หา order ที่เกิดขึ้นจริงแต่เราไม่รู้

[SPEC-003 handoff](reviews/SPEC-003-schema-handoff.md) เขียนเตือนไว้แล้วว่า
`exec_report.result = TIMEOUT` **ไม่ได้แปลว่า order ไม่เข้า**

```
EA ส่ง order → โบรกเกอร์ทำสำเร็จ → เน็ตขาดก่อนตอบกลับ
  → EA รายงาน TIMEOUT ticket=null
  → เราไม่รู้ว่ามี position
  → brain คิดว่า flat แล้วสั่งเปิดใหม่ = สองเท่า
```

**C1 (deal ใน MT5 ที่ไม่มี `exec_report`) คือสิ่งเดียวที่จับเคสนี้ได้**
— และมันจะไม่โผล่ใน log ที่ไหนเลย

## ★★ จับคู่ด้วย **ticket** ไม่ใช่ด้วยเวลา

MT5 คืนเวลา deal เป็นเวลา broker · DB เก็บ UTC → จับคู่ด้วยเวลาจะชน [D15](backlog.md)
และถ้ามี DST เปลี่ยนในช่วงที่ตรวจ **ทุกอย่างจะดูไม่ตรงพร้อมกันทั้งหมด**

ticket เป็นเลขที่โบรกเกอร์ออกให้ **ไม่ขึ้นกับ timezone** → ใช้เป็นกุญแจ
เวลาใช้เป็นตัวกรองหยาบเท่านั้น + **pad ±2 ชม.**

⚠️ กุญแจต้องเป็น **`(broker, ticket)`** — IUX กับ XM ออก ticket ชนกันได้

## ★★ "ผ่านเพราะไม่ได้ตรวจ" คือ failure mode ที่อันตรายที่สุด

`history_select()` คืน false → โค้ดตีความว่า "ไม่มี deal" → ไม่มีอะไรให้ไม่ตรง →
**รายงานเขียว** ทั้งที่ไม่เคยเทียบอะไรเลย

→ edge 1 + test 10 บังคับให้ `history_select()` ล้มเหลว = **error ไม่ใช่ผ่าน**

เป็นแบบเดียวกับ `test_stale_output_detected_when_ea_missing` ใน SPEC-005
และกลไก 3 ชั้นของ backfill ใน SPEC-010

**gate ทุกตัวในโปรเจกต์นี้ต้องตอบให้ได้ว่า "ถ้าฉันไม่ได้ทำงาน จะมีใครรู้ไหม"**

## read-only เด็ดขาด

ห้ามเขียน DB · ห้ามส่ง order · acceptance มี `grep` ห้ามเจอ
`order_send` / `INSERT` / `UPDATE` / `DELETE`

**เครื่องมือที่ "แก้ให้ตรง" อัตโนมัติ คือเครื่องมือที่ทำให้ปัญหาหายไปโดยไม่มีใครรู้ว่าเคยมี**

---

# รอบที่ 5.14 — SPEC-015 EMA baseline

📄 [spec เต็ม](specs/SPEC-015-ema-baseline.md) · **SPEC_READY** · 20 test
· **เริ่ม `sizing.py` + test 1–6 ได้เลย** (ฟังก์ชันบริสุทธิ์)
· **ปิด Phase 1 — spec ครบทั้ง phase แล้ว**

## ★★ ต้องเป็นฟังก์ชันบริสุทธิ์ — SPEC-033 จะเอาไปเทียบ

SPEC-033 (backtest ↔ live parity) จะรัน **กลยุทธ์ตัวนี้ทั้งสองทาง** แล้วเทียบว่า signal
ตรงกัน ≥ 99% · ถ้าไม่ตรง = **backtest ทั้งระบบเชื่อไม่ได้**

→ ห้ามพึ่ง `datetime.now()` · `random` · ลำดับที่ message มาถึง · สถานะนอก `ctx`
· acceptance มี `grep` ห้ามเจอ `datetime.now|time.time|random.`

**ถ้าข้อนี้พลาด เราจะไม่มีวันรู้ว่า backtest เชื่อได้ไหม — และจะไปรู้ตอนเอาเงินจริงลง**

## ★★ สูตร lot ต้องตรงกับ R1 **รวมลำดับที่แก้แล้ว**

```
lot = floor(raw_lot / volume_step) × volume_step
if lot < volume_min → ไม่ส่ง INTENT           ← ★ ก่อน clamp
lot = min(lot, volume_max, max_lot_per_order) ← clamp ลงเท่านั้น
```

**ห้ามสลับ 2 บรรทัดสุดท้าย** — เป็น bug ที่เคยอยู่ใน risk-spec เอง
([ADR-002 §4](decisions/ADR-002-symbols-capital-hours.md)) · **ห้ามให้มันกลับมาทางฝั่ง Python**

⚠️ `raw_lot < volume_min` → ไม่ส่ง INTENT · **นี่คือสถานะปกติที่ทุน $30** — ห้ามตกใจ ห้าม "แก้"

กลไกตรวจสอบตัวเองที่ได้ฟรี: ถ้า `INTENT_ACK.volume_clamped_to` ไม่ null **บ่อยผิดปกติ**
แปลว่าสองฝั่งคำนวณไม่ตรงกัน → **นับและ log**

## จุดที่ห้ามพลาด

- **ห้าม optimize / tune parameter** — ผลกำไรไม่ใช่เกณฑ์วัดของ ticket นี้เลย
- **`target_volume ≠ 0` ต้องมี `sl_price` เสมอ** (R9) · ATR คำนวณไม่ได้ → **ไม่ส่ง** ไม่ใช่ส่งโดยไม่มี SL
- **ห้ามส่ง INTENT ก่อนได้ `STATE` ตัวแรก** (SPEC-017 §4.2)
- **ต้องปิดได้ด้วย env** + log WARN ทุกครั้งที่สตาร์ตว่าเป็น baseline
  — *กลยุทธ์ชั่วคราวที่ไม่มีใครถอดออกคือกลยุทธ์ถาวร*
- หลาย session ของ canonical เดียวกัน (XM + IUX) → ตัดสินใจแยกกัน
  **exposure เป็นสองเท่าโดยตั้งใจ** · P3/P4 เป็นคนคุม ไม่ใช่ strategy

---

# รอบที่ 5.15 — SPEC-065 + SPEC-009 (ปิด Phase 0)

📄 [SPEC-065](specs/SPEC-065-mql5-test-harness.md) · [SPEC-009](specs/SPEC-009-ci.md)
· ทำคู่กัน — 009 พึ่งไฟล์ที่ 065 ออก

## SPEC-065 — ส่วนใหญ่ทำไปแล้ว เหลือ 2 อย่าง

**สิ่งที่มีแล้ว ห้ามทำซ้ำ:** deploy · compile · `.set` · tester headless ·
เทียบ `git_sha` · ตรวจ `ran_names` · หลายโบรกเกอร์ + `[SKIP]` · เช็ค terminal ค้าง

**ที่ต้องเพิ่ม:**
1. **manifest แยกไฟล์** `tools/mql5-suites.json` — เพิ่ม suite = แก้ JSON อย่างเดียว
   · กำลังจะมีอีก **7 suite** (BrokerTime · FarmMessages · RoundTrip · FarmSymbols ·
   StateReporter · IntentCache · Reconciler) · suite ที่ยังไม่มีไฟล์ → `[SKIP]` ไม่ใช่ FAIL
2. **`gate/mql5-latest.json`** — attestation ที่ commit ลง repo (ดู SPEC-009)

★★ **ต้องลบไฟล์ผลลัพธ์ก่อนรันทุก suite** — ถ้าไม่ลบ suite ที่ compile ไม่ผ่าน
จะ "ผ่าน" ด้วยผลรอบก่อน (กับดักเดียวกับ SPEC-005 edge 1) · **test 2 คือตัวที่กันเรื่องนี้**

## SPEC-009 — ปิด G3 ด้วย attestation

**CI รัน MQL5 ไม่ได้ แต่ตรวจได้ว่ามีคนรันแล้ว**

```
mql5-attest:
  แตะ mt5-ea/** หรือ tests/mql5/** แล้ว git_sha ใน attestation ไม่ตรง HEAD
  → FAIL → push ไม่ผ่าน
  แก้แต่ docs/ หรือ brain/ → PASS โดยไม่ต้องรัน MT5
```

**3 ชั้น — ชั้น 1–2 ใช้ได้วันนี้ ไม่ต้องมี remote:**

| ชั้น | | ต้องมี remote |
|------|---|---------------|
| 1 | `pre-push` hook รัน `check` | ❌ |
| 2 | `mql5-attest` อยู่ใน `check` | ❌ |
| 3 | workflow บน runner | ✅ |

**`pre-push` ไม่ใช่ `pre-commit`** — pre-commit ช้าเกินไป คนจะใช้ `--no-verify`
จนเป็นนิสัย และ commit ระหว่างทางควร commit ได้

🔴 **พูดตรงๆ: นี่คือ attestation ไม่ใช่ proof** — แก้ JSON ด้วยมือได้
แต่มันเปลี่ยนคำกล่าวอ้าง *"test ผ่าน"* จากข้อความที่ตรวจไม่ได้ →
**ไฟล์ที่ diff ได้ · มีประวัติใน git · ไม่ตรงเมื่อไรก็เห็น**
· ทางที่แข็งกว่าคือ self-hosted runner (D17) ซึ่งต้องมี remote ก่อน (D16)
· **สองทางไม่ขัดกัน** — วันที่มี runner มันจะเขียนไฟล์เดิมนี้ โครงสร้างไม่ต้องรื้อ

**`check` ทั้งชุดต้อง < 2 นาที** — gate ที่ช้าคือ gate ที่ถูก `--no-verify`

---

# รอบที่ 7 — Phase 2 ★ Risk layer L1 (SPEC-019…023)

📄 [019](specs/SPEC-019-local-risk-guard.md) · [020](specs/SPEC-020-lot-sizing.md)
· [021](specs/SPEC-021-drawdown-guard.md) · [022](specs/SPEC-022-margin-and-loss-streak.md)
· [023](specs/SPEC-023-safemode.md) · **~80 test รวม**

> **นี่คือชั้นที่เงินหาย** — [CLAUDE.md](../CLAUDE.md) กำหนดให้ review เข้มที่สุดตรงนี้
> **ตกข้อเดียวก็ `CHANGES_REQUIRED`**

## ★★ 3 หลักการที่ใช้กับทั้ง 5 ticket

**1. "ลดความเสี่ยงต้องผ่านได้เสมอ"**
`target_volume = 0` ต้องผ่าน**ทุกสถานะ รวม HALT** · R5/R11/R17 ห้าม block คำสั่งที่ลดขนาด
— ไม่งั้นเราจะติดอยู่ในไม้ที่ปิดไม่ได้ตอนที่อยากปิดที่สุด

**2. "ประเมินไม่ได้ = ปฏิเสธ"**
นาฬิกาเพี้ยน · อ่าน spread ไม่ได้ · `tick_value = 0` · อ่าน history ไม่ได้ ·
อ่าน kill file ไม่ได้ → **ทุกกรณีคือ reject/halt ไม่ใช่ปล่อยผ่าน**

**3. "guard ไม่ส่ง order เอง"**
ทุกตัวเปลี่ยนแค่ `Mode()` · `OrderRouter` เป็นคนลงมือ
· flatten = **วนปิดทุก ticket** ไม่ใช่ส่งสวน 1 ไม้ (จะกลายเป็น internal hedge ละเมิด R18)

## จุดที่ผิดแล้วเงินหาย — ตัวละ 1–2 ข้อ

| spec | จุด |
|------|-----|
| **019** | `target=0` ต้องผ่านตอน HALT · clamp **ลงเท่านั้น** · SL ผิดฝั่ง (R9b — risk-spec ไม่ได้เขียนไว้) · R17 นับ order ที่ **ส่ง** ไม่ใช่ที่สำเร็จ |
| **020** | ลำดับ **reject-ก่อน-clamp** (bug เดิมของ risk-spec) · `tick_value` **อ่านสดห้าม cache** และ `≤ 0` = reject ห้ามใช้ค่าเก่า |
| **021** | วัดจาก **equity ไม่ใช่ closed P/L** · halt + HWM ต้อง**รอดรีสตาร์ต** · **R7 hard ปลดเองไม่ได้** · นาฬิกาเพี้ยน = ห้ามตัดสินว่าวันใหม่ (จะล้างขาดทุนทั้งวัน) |
| **022** | `margin = -1` (ไม่มี position) → **NORMAL ไม่ใช่ REDUCE_ONLY** (ไม่งั้นเปิดไม้แรกไม่ได้ตลอดกาล) · R14 ต้องรวม **swap + commission** · อ่าน history ไม่ได้ ≠ streak 0 |
| **023** | อ่าน kill file ไม่ได้ = **ถือว่ามี** · ลบไฟล์แล้ว**ห้ามปลดเอง** · เช็คใน `OnTimer` **ห้าม `OnTick`** (ตลาดปิดไม่มี tick) · R16 → **REDUCE_ONLY ไม่ใช่ flatten** |

## ★ `MarketSnapshot` — seam ที่ทำให้ทดสอบได้จริง

guard **ห้ามเรียก `SymbolInfoDouble` / `AccountInfoDouble` ตรงๆ** ต้องผ่าน virtual class
· เหตุผลเดียวกับ `CBrokerClockSource` ใน SPEC-063

ถ้าไม่มี seam นี้จะทดสอบ *"spread 30 point ตอนเพดาน 25"* ไม่ได้เลยเพราะควบคุมตลาดจริงไม่ได้
· **mock guard เองไม่นับ แต่ mock ตลาดคือรอยต่อที่ถูก**

## R13 kill file ต้องเรียบง่ายที่สุดในระบบทั้งหมด

มันคือสิ่งสุดท้ายที่เหลือเมื่อทุกอย่างพัง: brain ตาย · เน็ตหลุด · DB ล่ม ·
dashboard เข้าไม่ได้ · คนที่ต้องกดอาจอยู่บนมือถือผ่าน remote desktop ที่กระตุก

→ เหลือแค่ **"มีไฟล์นี้ไหม"** และคำตอบที่ปลอดภัยเมื่อไม่แน่ใจคือ **"ถือว่ามี"**
· `grep` ห้ามเจอ `CWire`/`Socket`/`OnTick` ใน `SafeMode.mqh`

## ★ ปิดหนี้ `local_limits` ไปในตัว

SPEC-019 §3.5 เพิ่ม EA input ครบทุกกฎ → `HELLO.local_limits` ส่งค่าจริงได้
**รอบที่ 6 ด้านล่างถูกดูดเข้ามาอยู่ในนี้แล้ว**

---

# รอบที่ 8 — SPEC-060 + SPEC-061 (ปิด G1)

📄 [060](specs/SPEC-060-market-data-collector.md) · [061](specs/SPEC-061-stale-data-guard.md)
· 28 test · ทำคู่กัน — 061 พึ่ง metadata ที่ 060 ออก

## ★★ G1 คือ **fail-open ในชั้น risk**

gap-audit เขียนไว้ตรงๆ: EA ส่ง `BAR` เฉพาะ symbol ของตัวเอง · ถ้าวันนี้เทรดแค่ `EURUSD`
brain ไม่มีข้อมูล `GBPUSD` เลย → P4 คำนวณ correlation ไม่ได้ →
**ได้ `correlation = 0` แล้วปล่อยผ่านทุก intent**

### ทำไม `correlation = 0` ถึงเป็น bug ที่มองไม่เห็น

`corr = data.get(pair, 0)` ดูสะอาดและไม่มีใครทักท้วง

แต่ใน P4 `0` **ไม่ใช่ "ไม่มีข้อมูล"** — มันแปลว่า ***"ยืนยันแล้วว่าสองตัวนี้ไม่เกี่ยวกันเลย"***
ซึ่งเป็นข้ออ้างที่ทำให้ P4 **ยอมให้ถือทั้งสองตัวเต็มขนาดพร้อมกัน**

⇒ ความเสียหายเกิดตอนข้อมูลหาย **แล้วระบบเทรดหนักขึ้นกว่าปกติ** — ตรงข้ามกับที่ควรเป็น
และไม่มี log บรรทัดไหนบอกว่าเกิดอะไรขึ้น

**`1.0` แปลว่า "สมมติว่าแย่ที่สุด"** → P4 จำกัดกลุ่มนั้นเป็นก้อนเดียว →
ระบบเทรดน้อยลงตอนที่ตาบอด ซึ่งคือสิ่งที่ควรเกิด

## SPEC-061 §4.1 คือเนื้อหาทั้งหมด — ตารางบังคับ

| กฎ | ข้อมูลหาย → ต้องทำ | ❌ ห้ามทำ |
|----|-------------------|-----------|
| **P3** | reject intent | ใช้ rate เก่า · ข้าม symbol |
| **P4** | **correlation = 1.0** | ★ **= 0** |
| **P7** | ใช้ scale เข้มที่สุด | ใช้ `1.0` |
| **P8** | block | ปล่อยผ่าน |
| **R1** | reject | ใช้ equity เก่า |

**หลักการเดียว: "ไม่รู้" ต้องถูกปฏิบัติเหมือน "แย่ที่สุดที่เป็นไปได้"**
· ห้ามใช้ค่าเริ่มต้น · ค่าเฉลี่ย · ค่าล่าสุดที่รู้ · `0`
· acceptance มี `grep` ห้ามเจอ `or 0` / `fillna(0)` / `correlation = 0`

## ★★ "ตลาดปิด" ≠ "ข้อมูลหาย" — แยกให้ขาด

ทั้ง 6 คู่ปิดสุดสัปดาห์ · **ถ้าไม่แยก ทุกสุดสัปดาห์ระบบจะรายงานว่าข้อมูลหายทั้งหมด
แล้วคนจะเลิกสนใจ alert**

`MARKET_CLOSED` → **reject intent อยู่ แต่ไม่ alert** (ไม่ใช่ความผิดปกติ)
`STALE` (collector ตาย) → **alert**

## ★★ collector ห้ามเดา broker offset เอง

MT5 คืนเวลา broker · brain ต้องการ UTC → offset **ต้องขอจาก gateway**
(`HELLO.broker_time` / `HEARTBEAT.wire.broker_utc_offset_sec`)

**ไม่มี EA session ของ broker นั้น → ไม่เขียนข้อมูลของ broker นั้น + WARN**
· ห้ามคำนวณเอง**แม้จะทำได้** — จะกลายเป็นแหล่งความจริงที่สอง = **G6 กลับมาอีกรอบ**

## จุดอื่นที่ห้ามพลาด

- **collector read-only 100%** — `grep` ห้ามเจอ `order_send`/`positions_get`
- **collector ตาย → `freshness()` ต้องค้างที่เวลาเดิม** ห้ามคืนค่าที่ดูสด · **นี่คือหัวใจของ G1**
- `require()` ต้องตรวจ **ทุก symbol ในกลุ่ม** ไม่ใช่แค่ตัวที่จะเทรด — จะเทรด `EURUSD`
  แต่ถ้า `GBPUSD` (กลุ่ม `EUROPE` เดียวกัน) ไม่มีข้อมูล **P4 ก็คำนวณไม่ได้อยู่ดี**
- **cold start → `MISSING` → reject** ไม่ใช่ปล่อยผ่านช่วง warm-up
- collector แยกหน้าที่กับ guard: collector บอก *"ล่าสุดเมื่อไร"* · guard ตัดสิน *"เก่าไปไหม"*
  — ถ้ารวมกัน วันหนึ่งเกณฑ์เปลี่ยนจะต้องแก้สองที่แล้วไม่ตรงกัน

---

# รอบที่ 6 — `local_limits` ต่อกับ EA input

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
| **SPEC-011** OrderRouter | spec ปลดล็อกแล้ว แต่ต้องรอ **SPEC-010 เสร็จจริง** + ข้อ 1.6 (`test_partial_send_resumes` ด้วย socket จริง) |
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
