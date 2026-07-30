# Review — SPEC-016 ชั้น A / work-order รอบ 1.5–1.6 (chaos harness)

**วันที่:** 2026-07-29 · **ผู้ตรวจ:** Claude · **สถานะ:** uncommitted บน `feat/SPEC-001-mt5-executor`
**ตรวจจาก:** `tests/chaos/live_mt5_harness.py` · `tests/chaos/test_wire_resilience.py` · `brain/gateway/echo_server.py` · `tools/run-mql5-tests.ps1`

## ผลตัดสิน: 🔴 `CHANGES_REQUIRED`

สถาปัตยกรรมถูกตามที่ตัดสินไว้ทุกข้อ — ปัญหาอยู่ที่ **harness นี้ยังตอบไม่ได้ว่า "ถ้าฉันไม่ได้ทำงาน จะมีใครรู้ไหม"**
ซึ่งเป็นคำถามที่ [work-order](../work-order.md) ตั้งเป็นมาตรฐานของ gate ทุกตัวในโปรเจกต์นี้

---

## ✅ ทำถูกตามที่ตัดสินไว้ — ไม่ต้องรื้อ

| | หลักฐาน |
|---|---|
| live chart ผ่าน `[StartUp]` **ไม่ใช่ Strategy Tester** | `live_mt5_harness.py:144-164` ✅ ตรงตามที่ปิดประตูไว้ในรอบก่อน |
| ขับสถานการณ์**จากฝั่ง server ทั้งหมด** — EA ตัวเดิม token เดิม | `echo_server.py` flags: `--force-hello-reject` `--close-on-accept` `--close-after-hello` `--no-heartbeat-ack` ✅ |
| `echo_server.py` **ยังแยกจาก gateway จริง** | ไม่มีการรวม ✅ |
| แยก fast / slow | `test_no_heartbeat_loss_over_1h` อยู่หลัง `EA_FARM_LIVE_MT5_SLOW` ✅ |
| **ไม่มี retry ให้ test ที่ flake** | `grep` ไม่เจอ retry/rerun ✅ |
| kill เทอร์มินัลแม้ test fail | `finally:` ใน `live_terminal` + `terminate → kill` ✅ |
| เช็คเทอร์มินัลค้างก่อนเริ่ม | `assert_no_terminal_running()` ✅ |
| `free_port()` แทน port คงที่ | ✅ ทำให้รันซ้อนกันได้ |
| event log เป็น JSONL มี `monotonic` | ✅ เป็นฐานที่ถูกสำหรับวัด timing |

---

## 🔴 ต้องแก้ก่อนผ่าน

### C1 · chaos test ทั้ง 6 ตัว **ถูก skip โดยค่าเริ่มต้น และไม่มี gate ไหนบังคับให้รัน**

```python
@unittest.skipUnless(live_enabled(), "set EA_FARM_LIVE_MT5=1 …")
```

- ไม่มี `EA_FARM_LIVE_MT5` ที่ไหนใน `tools/` เลย
- `run-mql5-tests.ps1` ไม่รู้จัก suite นี้
- ยังไม่มี `tools/task.py` (SPEC-002 ยังไม่ทำ) → **ไม่มีที่ไหนในโปรเจกต์ที่รัน 6 test นี้เลย**

ผลคือ: รัน `pytest tests/` แล้วเห็น **เขียว 6 skipped** — และ [SPEC-002](../specs/SPEC-002-repo-scaffold.md)
กับกฎเป้า XM ใน MQL5 gate เขียนตรงกันว่า **`[SKIP]` ห้ามนับเป็น pass**

**ต้องทำ:**
1. เพิ่ม target ที่รันชุดนี้โดยตั้ง env ให้เอง (`tools/run-chaos.ps1` หรือรอ `task.py chaos`)
2. **สรุปท้ายการรันต้องบอกจำนวน ran / skipped แยกกัน** แบบเดียวกับ `$ranTargets`/`$skippedTargets`
3. ถ้ายังรันไม่ได้เพราะ socket whitelist → **รายงานว่ารันไม่ได้ ห้ามรายงานว่าผ่าน**

### C2 · `live_mt5_harness.py:104-117` — compile ล้มเหลวแล้ว test จะรัน `.ex5` ตัวเก่า

```python
if result.returncode not in (0, 1):        # ← ยอมรับ 1
    raise AssertionError(...)
if not (expert_dst / "FarmExecutor.ex5").exists():   # ← ไฟล์เก่าก็ผ่าน
```

MetaEditor คืน exit code ตามจำนวน error → **ยอมรับ `1` = ยอมรับ compile ที่มี 1 error**
และเช็ค "ไฟล์มีอยู่" กับไฟล์ที่ deploy ไว้ตั้งแต่รอบก่อน → **ผ่านเสมอ**

อาการที่จะเกิดจริง: แก้ `BrokerTime.mqh` ผิดจน compile ไม่ผ่าน → harness เงียบ →
chaos test รัน EA **เวอร์ชันเก่าที่ยังดีอยู่** → เขียว → เข้าใจว่าโค้ดใหม่ใช้ได้

นี่คือกับดักเดียวกับ `out-*.json` ค้างใน [SPEC-005 edge 1](../specs/SPEC-005-roundtrip-harness.md)
และกลไก 3 ชั้นของ [SPEC-065](../specs/SPEC-065-mql5-test-harness.md) test 2

**ต้องทำ:** ลบ `FarmExecutor.ex5` **ก่อน** compile · ยอมรับเฉพาะ `returncode == 0`
· อ่าน compile log แล้ว fail ถ้ามี `error` · เทียบ mtime ของ `.ex5` ว่าใหม่กว่า `.mq5` ทุกไฟล์

### C3 · `test_duplicate_session_rejected` — ผ่านได้แม้ EA จะตายไปแล้ว

```python
with echo_server(port, event_log, "--force-hello-reject", "DUPLICATE_SESSION"):
    with live_terminal(port):
        ack = wait_for_event(event_log, "hello_ack", timeout=30.0)
self.assertFalse(ack["accepted"])
self.assertEqual(ack["reason"], "DUPLICATE_SESSION")
```

ทั้งสอง assert เป็นค่าที่ **server เป็นคนเขียนเอง** จาก flag ที่ test เป็นคนสั่ง
→ พิสูจน์แค่ว่า *"echo_server ทำตามที่สั่ง"* · **ไม่มี assert ใดแตะพฤติกรรมของ EA เลย**
EA จะ crash · จะ hammer ต่อทันที · จะไม่ทำอะไรเลย — test เขียวเหมือนกันหมด

นี่คือรูปแบบเดียวกับ `test_msg_id_two_instances_not_duplicate` ที่จับได้ใน [work-order §1.3](../work-order.md)

**ต้องทำ:** เปลี่ยนชื่อเป็น `test_ea_handles_duplicate_session_rejection` และ assert
**พฤติกรรมของ EA หลังโดนปฏิเสธ** — เช่น connect ครั้งถัดไปห่าง ≥ 60s (แบบเดียวกับ `bad_token`)
หรือไม่มี `connect` ซ้ำภายใน N วินาที · ถ้ายังไม่ได้ตัดสินว่า EA ควรทำอะไร → **ถามมาก่อน อย่าเดา**

### C4 · `test_bad_token_waits_60s` เป็น test เดียวใน 6 ตัวที่วัดพฤติกรรม EA จริง — อีก 5 ตัวต้องยกระดับตาม

ไล่ดูแล้วเทียบกับ *"test นี้จับพฤติกรรมผิดแบบไหนได้"*:

| test | จับอะไรได้จริง | ประเมิน |
|------|----------------|---------|
| `test_bad_token_waits_60s` | EA ไม่ hammer server หลังโดนปฏิเสธ | ✅ ดี |
| `test_ea_reconnects_after_server_kill` | EA กลับมาต่อได้ | ✅ พอ |
| `test_backoff_schedule_matches_spec` | ช่วงห่าง 1,2,4,8 | 🟠 ดู C5 |
| `test_heartbeat_gap_triggers_reconnect` | reconnect ใน 4–12s | ✅ พอ |
| `test_no_heartbeat_loss_over_1h` | ไม่ขาดช่วง > 3.5s | ✅ ดี |
| `test_duplicate_session_rejected` | **ไม่จับอะไรเลย** | 🔴 C3 |

### C5 · `test_backoff_schedule_matches_spec` — ขาดสองข้อที่สำคัญกว่าตัวเลข

```python
expected = [1.0, 2.0, 4.0, 8.0]     # หยุดที่ connect ตัวที่ 5
```

1. **ไม่เคยเห็น 16 และ 30** — และ 30 คือ **เพดาน** ซึ่งเป็นค่าที่พังแล้วเจ็บที่สุด
   (backoff ไม่มีเพดาน = EA หายไปเป็นชั่วโมง · เพดานหลุด = hammer server)
2. **ไม่ได้ตรวจว่า "ต้องไม่ลดลง"** — [work-order §1.5](../work-order.md) ระบุเกณฑ์นี้ไว้ตรงตัว
   backoff ที่ลดลงกลางทางจะผ่าน test ปัจจุบันได้ถ้าบังเอิญตกในกรอบ

**ต้องทำ:** ยืดเป็น 7 connect (รวม ~61s ยังอยู่ในชุด fast) · assert `gaps` **non-decreasing**
· assert gap สุดท้ายไม่เกิน 30 × 1.5 · เกณฑ์ `[0.7×, 1.5×]` ตาม work-order (ตอนนี้ใช้ 0.75–1.35 แคบกว่า → เสี่ยง flake โดยไม่ได้ความเข้มเพิ่ม)

### C6 · `tools/run-mql5-tests.ps1:252` — gate ปล่อยผ่าน suite ที่ไม่มีรายชื่อ test

```powershell
$requiredNames = $RequiredSuiteNames[$name]
foreach ($required in $requiredNames) { … }     # $null → วนศูนย์รอบ → ผ่าน
```

การ refactor เป็น hashtable ต่อ suite **ถูกทิศ** (ตรงกับ manifest ที่ SPEC-065 จะทำ)
แต่ suite ที่ลืมใส่ใน `$RequiredSuiteNames` จะ **ผ่านโดยไม่ตรวจ `ran_names` เลย**

[SPEC-065](../specs/SPEC-065-mql5-test-harness.md) บอกว่ากำลังจะมีอีก **7 suite** →
กับดักนี้จะเกิดขึ้นจริงแน่นอน ไม่ใช่สมมติ

**ต้องทำ:** `if (-not $requiredNames -or $requiredNames.Count -eq 0) { FAIL "no required names registered for suite $name" }`

> 📌 **นี่คือ diff ของ gate ที่ Codex แก้เอง** — ตาม [CLAUDE.md](../../CLAUDE.md) ผมอ่าน diff นี้
> ก่อนดูผลรัน · ผลรันที่ได้จาก gate ที่มีช่องนี้ **ยังเชื่อไม่ได้เต็มที่จนกว่าจะแก้**

---

## 🟠 ควรแก้ — ต้องมีคำตอบใน handoff

### C7 · งานข้อ 1.6 (`test_partial_send_resumes` ด้วย socket จริง) **ยังไม่ได้ทำ**

`echo_server.py` ได้ `--close-on-accept` / `--close-after-hello` มาแล้ว แต่**ไม่มีโหมด
"accept แล้วไม่อ่าน"** ซึ่งเป็นสิ่งเดียวที่ทำให้ `SocketSend` คืนค่าน้อยกว่าที่ขอ
· `TestWire.mq5` แก้ไปบรรทัดเดียว (เรื่อง `started_at`)

[work-order §1.6](../work-order.md) กำหนดเส้นตายไว้ **ก่อน merge SPEC-011** — ยังไม่เลยกำหนด
แต่ต้องระบุในหัวข้อ "ยังไม่ทำ" ของ handoff **ห้ามให้หายไปเงียบๆ**

### C8 · harness ไม่เคยอ่าน log ของ EA เลย — เหลือช่องสังเกตผลแค่ครึ่งเดียว

[work-order §1.5](../work-order.md) กำหนดช่องสังเกต **2 ทาง**: (ก) socket ฝั่ง server (ข) log ของ EA
ตอนนี้มีแต่ (ก) · `MQL5\Logs\YYYYMMDD.log` (UTF-16LE) ไม่ถูกแตะเลย

ผลตรงๆ คือ C3 แก้ไม่ได้ดีถ้าไม่มี (ข) — และเมื่อ test แดง จะไม่รู้ว่า EA คิดอะไรอยู่
· ต้องมี log reader ที่ **จดตำแหน่งเริ่มต้นก่อนแต่ละ scenario** (กับดักผลค้างแบบเดียวกับ C2)

### C9 · เปิดเทอร์มินัลใหม่ทุก test — ขัดกับสถาปัตยกรรมที่ตัดสินไว้

`with live_terminal(port):` อยู่**ในแต่ละ test** → deploy + compile + boot ใหม่ 6 รอบ
· work-order §1.5 ระบุ *"เปิดครั้งเดียวทั้ง suite (session fixture) · startup ~15–20 วินาที ต่อ test ไม่ไหว"*

ยอมรับได้ชั่วคราวถ้าชุด fast ยังจบใน ~3 นาที — **แต่ต้องวัดแล้วรายงานตัวเลขจริง**
ถ้าเกิน ต้องย้ายไป fixture ระดับ session (แล้วเปลี่ยน port ต่อ test ไม่ได้ → ต้องคิดใหม่)

### C10 · `.set` ถูกเขียนลง 3 โฟลเดอร์พร้อมกัน — ยังไม่ตอบคำถามที่ถามไว้

`Presets/` · `Profiles/Tester/` · `Experts/` — work-order §1.5 ขอไว้ตรงๆ ว่า
**"รายงานว่าโฟลเดอร์ไหนถูกใน handoff"** เพราะเป็นความรู้ที่หายง่ายและเสียเวลามากถ้าไม่รู้

ยิงทั้ง 3 ที่ทำให้ test ผ่านแต่**ไม่ได้คำตอบ** · ต้องทดลองแล้วบันทึก แล้วเหลือที่เดียว
(ไฟล์ที่เขียนทิ้งไว้ในโฟลเดอร์เทอร์มินัลคือ state นอก git — ยิ่งน้อยยิ่งดี)

### C11 · path ฮาร์ดโค้ดซ้ำกับ `run-mql5-tests.ps1`

`C:\Program Files\IUX Markets MT5 Terminal3\…` และ GUID ของ terminal อยู่ใน 2 ที่แล้ว
· วันที่ย้ายขึ้น VPS จะแก้ไม่ครบ · ควรมีที่เดียว (เลื่อนไป SPEC-002 `.env` ได้ ถ้าจดไว้)

### C12 · `test_no_heartbeat_loss_over_1h` — `time.sleep(3600)` ไม่เช็คระหว่างทาง

ถ้าเทอร์มินัลตายที่นาทีที่ 5 ยังต้องรออีก 55 นาทีเพื่อได้ผลแดง
· ควร poll แล้ว fail เร็วเมื่อ heartbeat ขาดเกิน 3.5s (เกณฑ์เดิม) — ได้ผลเท่ากันแต่รู้เร็วขึ้น

### C13 · `monotonic` ข้ามโปรเซส

`test_ea_reconnects_after_server_kill` อ่าน event จาก echo_server **2 โปรเซส** ในไฟล์เดียวกัน
· ตอนนี้ยังไม่ได้เอา `monotonic` ข้ามโปรเซสมาลบกัน จึงยังไม่ผิด
· แต่ถ้าจะทำในอนาคต **ต้องใช้ `wall_time` แทน** — `time.monotonic()` ไม่รับประกันจุดอ้างอิงเดียวกันข้ามโปรเซส
· เขียน comment กันไว้ที่ `log_event`

---

## ก่อนรายงานผลรัน — 3 ข้อที่ต้องมีใน handoff

1. **socket whitelist**: `SocketConnect` ไป `127.0.0.1` ผ่านหรือไม่ · ถ้าต้องตั้งด้วยมือ
   → บันทึกเป็นขั้นตอน setup (จะย้ายไป runbook SPEC-030b)
2. **`.set` โฟลเดอร์ไหนที่ `[StartUp]` อ่านจริง** (C10)
3. **เวลาที่ชุด fast ใช้จริง** (C9) — ตัวเลขจริง ไม่ใช่ประมาณ

และตามกฎเดิม: **ถ้ารันไม่ได้ ให้รายงานว่ารันไม่ได้** — `[SKIP]` ไม่ใช่ผ่าน

---

## สรุปลำดับการแก้

1. **C2** ลบ `.ex5` ก่อน compile + ยอมรับเฉพาะ exit 0 ← ถ้าไม่แก้ข้อนี้ ผลรันทุกข้ออื่นเชื่อไม่ได้
2. **C6** gate ต้อง FAIL เมื่อ suite ไม่มีรายชื่อ test
3. **C1** ทำให้ 6 test นี้ถูกรันจริงจากที่ใดที่หนึ่ง + รายงาน ran/skipped
4. **C3 + C5** ยกระดับ 2 test ที่ยังพิสูจน์ไม่พอ
5. **C8** เพิ่ม log reader ฝั่ง EA
6. **C7 · C9–C13** รายงานใน handoff · แก้ตามที่ตัดสิน
