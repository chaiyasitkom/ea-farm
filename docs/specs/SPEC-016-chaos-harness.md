# SPEC-016 — Chaos test harness + scenario suite

**Phase:** 1 · **Owner:** Codex
**Depends on:** SPEC-001 (ชั้น A) · SPEC-002 · เพิ่ม SPEC-011 + SPEC-013 (ชั้น B)
**Blocks:** SPEC-001 ปิดงาน · Phase 1 exit criteria
**อ้าง:** [work-order §1.5](../work-order.md) (สถาปัตยกรรมตัดสินไปแล้ว) · [04-roadmap Phase 1](../04-roadmap.md) exit

> **ticket นี้ปลดล็อก work-order รอบ 1** — §1.5/§1.6 ที่ Codex ติดอยู่ตอนนี้คือ **ชั้น A** ของ spec นี้

---

## 1. Goal

harness ที่รัน **`FarmExecutor` ตัวจริงบน live chart** แล้วสร้างสถานการณ์เลวร้ายจากฝั่ง server
เพื่อพิสูจน์ว่า EA ทนจริง — **ไม่ใช่พิสูจน์ว่า server ตอบถูก**

## 2. Non-goals

- ❌ **ห้ามใช้ Strategy Tester** — ตัดสินไปแล้วใน [work-order §1.5](../work-order.md)
      (tester ใช้เวลาจำลอง · chaos test ทั้งหมดวัด wall-clock)
- ❌ ห้ามแก้ `FarmExecutor` / `Wire.mqh` เพื่อให้ test ผ่านง่ายขึ้น
- ❌ ห้ามใช้ `server.py` ตัวจริง (SPEC-013) เป็นตัวขับสถานการณ์ — ใช้ `echo_server.py` (§3.3)
- ❌ ห้ามต่อบัญชี live — demo เท่านั้น (AGENTS ข้อ 3)
- ❌ ห้ามใส่ retry ให้ test ที่ flake — ดู §4.7 ★

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `tests/chaos/harness/terminal.py` | คุมเทอร์มินัล MT5 (launch/kill/รอ) |
| `tests/chaos/harness/scripted_server.py` | `echo_server` ที่สั่งพฤติกรรมได้ |
| `tests/chaos/harness/ea_log.py` | อ่าน `MQL5\Logs\*.log` (**UTF-16LE**) + tail + match |
| `tests/chaos/conftest.py` | fixture |
| `tests/chaos/test_wire_chaos.py` | **ชั้น A** — 7 scenario |
| `tests/chaos/test_intent_chaos.py` | **ชั้น B** — 5 scenario (รอ 011+013) |
| `tools/task.py` | **แก้** — เพิ่ม `chaos` · `chaos-slow` |

### 3.2 ★ แบ่ง 2 ชั้น — ชั้น A ทำได้เลยวันนี้

| ชั้น | ต้องมีอะไรก่อน | ครอบอะไร |
|------|----------------|----------|
| **A — wire** | **SPEC-001 เท่านั้น** | reconnect · backoff · auth · heartbeat · partial send |
| **B — intent** | SPEC-011 + SPEC-013 | intent ซ้ำ · SafeMode · reconcile |

**ชั้น A คือสิ่งที่ [work-order §1.5/§1.6](../work-order.md) ต้องการ** — เขียนได้ทันที
ไม่ต้องรอ ticket อื่น · ชั้น B ค่อยมาต่อในไฟล์แยก

### 3.3 `scripted_server` — ขับสถานการณ์จากฝั่ง server ทั้งหมด

รันเป็น **asyncio task ในโปรเซสของ pytest เอง** (ไม่ใช่ subprocess)
→ EA ต่อเข้ามาผ่าน **socket จริง** แต่ test สั่งพฤติกรรมได้เต็มที่โดยไม่ต้องมี IPC

```python
class ScriptedServer:
    async def start(self) -> int: ...          # คืน port ที่ bind ได้จริง
    async def stop(self) -> None: ...

    # ---- สั่งพฤติกรรม ----
    def reject_next_hello(self, reason: str) -> None: ...
    def stop_acking_heartbeats(self) -> None: ...
    def resume_acking_heartbeats(self) -> None: ...
    async def drop_all_connections(self) -> None: ...
    def stop_reading_socket(self) -> None: ...      # ★ บังคับ partial send (§4.5)

    # ---- สังเกตผล ----
    def connection_events(self) -> list[ConnEvent]: ...   # (ts, "connect"|"disconnect")
    def messages(self, type: str | None = None) -> list[Msg]: ...
    async def wait_for(self, type: str, timeout: float) -> Msg: ...
```

**สังเกตผลจากฝั่ง server เป็นหลัก** — timestamp แม่นกว่าและไม่ต้อง parse log
· ใช้ log เฉพาะสถานะภายในของ EA ที่ server มองไม่เห็น (เช่น เข้า SafeMode)

### 3.4 `terminal` — คุม MT5

```python
class TerminalController:
    def __init__(self, terminal_exe: str, data_dir: str, symbol: str, period: str): ...

    def assert_not_running(self) -> None: ...        # ★ ต้องเช็คก่อนเสมอ
    def write_set(self, params: dict[str, str]) -> Path: ...
    def launch(self, set_file: Path) -> None: ...    # /config: + [StartUp]
    def kill(self) -> None: ...                      # ★ ต้องเรียกได้แม้ test พัง
    def wait_for_ea_init(self, timeout: float = 60) -> None: ...
```

ini ตาม [work-order §1.5](../work-order.md):
```ini
[Experts]
AllowLiveTrading=1
Enabled=1
[StartUp]
Expert=FarmExecutor
ExpertParameters=<set>
Symbol=EURUSD.iux
Period=H1
```

---

## 4. Behaviour

### 4.1 อายุของเทอร์มินัล

| ระดับ | ขอบเขต |
|-------|--------|
| **session fixture** | launch ครั้งเดียวสำหรับ scenario ที่ไม่ต้อง restart EA (ส่วนใหญ่) |
| **function fixture** | เฉพาะ scenario ที่ต้อง restart EA — MT5 ไม่มีคำสั่ง reload EA จากภายนอก → **restart EA = restart terminal** (~20 วินาที) |

**`kill()` ต้องถูกเรียกเสมอแม้ test จะ fail** (`try/finally` หรือ fixture teardown)
เทอร์มินัลที่ค้างจะทำให้รอบถัดไปพังทันที เพราะ gate มีเช็ค "terminal already running"

### 4.2 Port

เลือก **port ว่างแบบสุ่ม** ตอนเริ่ม session แล้วเขียนลง `.set` ก่อน launch
**ห้ามใช้ 9101** — จะชนกับ gateway จริงถ้ามีคนรันอยู่

`.set` ต้องเขียนแบบ `Name=value` เปล่าๆ — **ห้ามมี suffix `||||N`**
([gate-02 กับดัก #4](../reviews/SPEC-001-compile-gate-02.md))

### 4.3 อ่าน log ของ EA

`MQL5\Logs\YYYYMMDD.log` เป็น **UTF-16LE** — เปิดเป็น utf-8 จะได้ `\x00` แทรกแล้ว regex ไม่แมตช์

- ต้อง **tail** ได้ (ไฟล์โตระหว่างรัน)
- ต้องจดตำแหน่งเริ่มต้นก่อน scenario **เพื่อไม่ให้อ่านของรอบก่อนมาปน** ← กับดักเดียวกับ
  `out-*.json` ค้างใน [SPEC-005](SPEC-005-roundtrip-harness.md)
- แยก timestamp ออกมาได้ (บรรทัดขึ้นต้นด้วย `HH:MM:SS.mmm`)

### 4.4 เกณฑ์เวลา — หลวมพอให้ไม่ flake แต่ยังจับของผิด

| วัด | เกณฑ์ |
|-----|-------|
| backoff แต่ละช่วง | อยู่ใน **[0.7×, 1.5×]** ของค่าที่คาด (nominal + jitter ±20% + ความหน่วงของ OS) |
| ลำดับ backoff | **ต้องไม่ลดลง** จนถึง cap 30s |
| รอหลัง `BAD_TOKEN` | **≥ 55 วินาที** (nominal 60) |
| SafeMode หลัง brain ตาย | **≤ 12 วินาที** (nominal 10) |

**หลักการ:** ผูกเกณฑ์กับ *"พฤติกรรมผิดแบบไหนที่ต้องจับให้ได้"*
— ไม่มี backoff เลย · backoff ถอยหลัง · retry รัวทันที
ไม่ใช่ผูกกับตัวเลขเป๊ะๆ ที่ OS การันตีไม่ได้

### 4.5 บังคับให้เกิด partial send จริง

[gate-02 §3❷](../reviews/SPEC-001-compile-gate-02.md) ค้างมานาน · **เส้นตาย: ก่อน merge SPEC-011**

วิธี: `stop_reading_socket()` → server accept แล้ว**ไม่อ่านเลย** → TCP receive buffer เต็ม
→ EA ส่ง frame ใหญ่ → `SocketSend` คืนค่า**น้อยกว่าที่ขอ**

จากนั้น `resume_reading()` แล้วตรวจว่า server ได้ frame **ครบถ้วนหนึ่งชุด ไม่ซ้ำ ไม่ขาด**

> ที่มีอยู่ตอนนี้พิสูจน์แค่ *การจดบัญชี resume* — ไม่ได้พิสูจน์ว่า
> **ค่าที่ `SocketSend` คืนมาจริงต่อเข้ากับตรรกะนั้น**
> Phase 1 ส่งซ้ำแค่ได้ message ซ้ำ · **Phase 2 message ซ้ำ = order ซ้ำ**

### 4.6 แยก fast / slow

| ชุด | เวลา | marker | รันเมื่อไร |
|-----|------|--------|-----------|
| fast (A1–A6, B1–B5) | ~4 นาที | `live_terminal` | ก่อน handoff |
| slow (A7 soak 1 ชม.) | 1 ชั่วโมง | `live_terminal` + `slow` | รันมือ/รายคืน |

**gate ที่ใช้ 1 ชม.ทุกครั้ง = gate ที่ไม่มีใครรัน**

### 4.7 ★ ห้ามใส่ retry ให้ test ที่ flake

ถ้า scenario ไหน flake:
1. **รายงานพร้อมจำนวนครั้งที่ flake และค่าที่วัดได้จริง**
2. ปรับ**เกณฑ์**ตามข้อมูลที่วัดได้ (แล้วบอกว่าปรับเพราะอะไร)
3. **ห้ามใส่ `@pytest.mark.flaky` หรือ retry loop**

chaos test ที่ retry จนผ่านคือ test ที่บอกอะไรไม่ได้เลย — และการ flake มักแปลว่า
**พฤติกรรมจริงไม่นิ่ง** ซึ่งคือสิ่งที่เรากำลังหาอยู่พอดี

---

## 5. Scenario

### ชั้น A — wire (ต้องการแค่ SPEC-001)

| # | test | สร้างสถานการณ์อย่างไร | ต้องได้ |
|---|------|----------------------|---------|
| A1 | `test_ea_reconnects_after_server_kill` | `drop_all_connections()` | ต่อกลับมาเอง ไม่ต้องแตะอะไร |
| A2 | `test_backoff_schedule_matches_spec` | ปิดทุกครั้งที่ต่อ | ช่วงห่าง 1,2,4,8,16,30 ตาม §4.4 · **ไม่ลดลง** |
| A3 | `test_bad_token_waits_60s` | `reject_next_hello("BAD_TOKEN")` | ต่อครั้งถัดไป **≥ 55 วินาที** — ไม่ hammer |
| A4 | `test_duplicate_session_rejected` | ตอบ `DUPLICATE_SESSION` | EA เข้า `FAILED_AUTH` (จาก log) |
| A5 | `test_heartbeat_gap_triggers_reconnect` | `stop_acking_heartbeats()` | reconnect หลังขาด ack **3 ครั้ง** |
| A6 | `test_partial_send_resumes_real_socket` | `stop_reading_socket()` (§4.5) | frame ครบ **ไม่ซ้ำ ไม่ขาด** |
| A7 | `test_no_heartbeat_loss_over_1h` | ตอบปกติ 1 ชม. | heartbeat ไม่ขาดช่วง · `seq` ต่อเนื่อง `slow` |

### ชั้น B — intent (ต้องการ SPEC-011 + SPEC-013)

| # | test | ต้องได้ | ที่มา |
|---|------|---------|-------|
| B1 | `test_duplicate_intent_100x_yields_one_order` | ส่ง `intent_id` เดิม 100 ครั้ง → **order เดียว** | roadmap Phase 1 exit |
| B2 | `test_brain_death_triggers_safemode_within_10s` | หยุด server → EA เข้า SafeMode **≤ 12 วินาที** | roadmap |
| B3 | `test_ea_restart_reconciles_position` | restart terminal ตอนถือ position → `STATE` ตรงกับ MT5 | roadmap · ต้องใช้ function fixture (§4.1) |
| B4 | `test_expired_intent_not_executed` | `valid_until` ที่ผ่านไปแล้ว → `INTENT_ACK EXPIRED` **ไม่มี order** | [contract §4.5](../02-contracts.md) |
| B5 | `test_flip_interrupted_leaves_flat` | ตัดหลังปิดขาเก่าแต่ก่อนเปิดขาใหม่ → **อยู่ที่ flat** ไม่ใช่ hedge ค้าง | [ADR-001 §6](../decisions/ADR-001-hedging-account.md) |

**B1 กับ B5 คือสองตัวที่เงินหายถ้าผิด** — B1 คือ order ซ้ำ · B5 คือ internal hedge ค้าง (R18)

---

## 6. Acceptance criteria

- [ ] `python tools/task.py chaos` รันชั้น A ครบ 6 ตัว (ไม่รวม soak) **ผ่านหมด**
- [ ] `python tools/task.py chaos-slow` รัน A7 ผ่าน
- [ ] **เทอร์มินัลถูก kill ทุกครั้งแม้ test fail** — พิสูจน์: ทำให้ test fail โดยตั้งใจ
      แล้วเช็คว่าไม่มี `terminal64.exe` ค้าง
- [ ] `assert_not_running()` ทำงาน — เปิดเทอร์มินัลค้างไว้แล้วรัน → **fail ทันทีพร้อมข้อความชัด**
      ไม่ใช่ timeout งงๆ
- [ ] log reader อ่าน **UTF-16LE** ถูก — `grep -n "utf-16" tests/chaos/harness/ea_log.py` เจอ
- [ ] log reader **จดตำแหน่งเริ่มต้นก่อนแต่ละ scenario** — ไม่อ่านของรอบก่อนมาปน
- [ ] port เป็น ephemeral **ไม่ใช่ 9101**
- [ ] `.set` ไม่มี suffix `||||N`
- [ ] A6 พิสูจน์ partial send ด้วย **socket จริง** — `stop_reading_socket()` ทำให้ `SocketSend`
      คืนค่าน้อยกว่าที่ขอจริง (มีหลักฐานใน log/metric)
- [ ] **ไม่มี `@pytest.mark.flaky` และไม่มี retry loop** ในไฟล์ chaos ทั้งหมด (§4.7)
- [ ] `python tools/task.py check` ยังผ่านบนเครื่องที่ไม่มี MT5 (marker `live_terminal` ถูก skip)
- [ ] **บันทึกใน handoff:** `[StartUp] ExpertParameters` อ่าน `.set` จากโฟลเดอร์ไหน
      (`Profiles\Tester\` หรือ `Presets\`) — [work-order §1.5](../work-order.md) ยังไม่รู้
- [ ] **บันทึกใน handoff:** `SocketConnect` ไปที่ `127.0.0.1` ต้อง whitelist ไหม
      · ถ้าต้อง ให้เขียนเป็นขั้นตอน setup (`settings.ini` เข้ารหัส → GUI เท่านั้น)

## 7. Test list

**scenario ทั้ง 12 ตัวใน §5 คือ test list** · เพิ่ม test ของตัว harness เอง:

| # | test | ตรวจอะไร |
|---|------|----------|
| H1 | `test_log_reader_handles_utf16` | ★ §4.3 |
| H2 | `test_log_reader_ignores_lines_before_mark` | ★ กับดักผลค้าง |
| H3 | `test_terminal_killed_on_fixture_teardown` | ★ §4.1 |
| H4 | `test_assert_not_running_detects_existing` | |
| H5 | `test_scripted_server_binds_ephemeral_port` | |
| H6 | `test_set_file_has_no_optimization_suffix` | gate-02 กับดัก #4 |

H1–H6 รันได้**โดยไม่ต้องมี MT5** (ทดสอบตัว harness ไม่ใช่ตัว EA)
→ อยู่ใน `check` ปกติ

## 8. Files

**Touch:** `tests/chaos/**` · `tools/task.py`
· `brain/gateway/echo_server.py` — **ขยายได้** ให้รองรับ `ScriptedServer`
  แต่ **ห้ามทำให้พฤติกรรมเริ่มต้นเปลี่ยน** (ของเดิมยังต้องใช้ได้เหมือนเดิม)

**ห้ามแตะ:** `mt5-ea/**` ★ (แก้ EA เพื่อให้ test ผ่าน = ทำให้ test ไร้ความหมาย)
· `brain/gateway/server.py` · `contracts/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `[StartUp] ExpertParameters` อ่าน `.set` จากโฟลเดอร์ไหน | **ไม่บล็อก** — ลองทั้ง 2 ที่แล้ว**รายงาน** (acceptance บังคับ) |
| Q2 | `SocketConnect` → `127.0.0.1` ต้อง whitelist ไหม | **ไม่บล็อก** — รู้ผลจากการรันครั้งแรก · ถ้าต้อง เจ้าของเปิดให้ทาง GUI แล้วบันทึกเป็น setup step |
| Q3 | restart EA โดยไม่ restart terminal ทำได้ไหม | **ไม่บล็อก — สมมติว่าไม่ได้** ใช้ restart terminal (§4.1) · ถ้าเจอวิธีให้รายงาน จะช่วยลดเวลา B3 มาก |

> **ไม่มีคำถามที่บล็อก — ชั้น A เริ่มได้ทันที ต้องการแค่ SPEC-001 ที่มีอยู่แล้ว**

---

## ภาคผนวก — ทำไม harness นี้คุ้มกับเวลาที่ลง

ชั้น A ดูเหมือนงานเยอะเพื่อพิสูจน์เรื่องที่ "น่าจะทำงานอยู่แล้ว"

แต่สิ่งที่มันพิสูจน์คือ **พฤติกรรมตอนทุกอย่างพัง** — ซึ่งเป็นตอนเดียวที่สำคัญจริง
และเป็นตอนที่ทดสอบด้วยมือไม่ได้เลย (ใครจะนั่งตัดเน็ตแล้วจับเวลา backoff 6 รอบ)

harness ตัวเดียวกันนี้ถูกใช้ซ้ำใน:
- **SPEC-010** — `test_backfill_300_bars` · `test_heartbeat_uninterrupted_during_backfill`
- **SPEC-013** — พิสูจน์ว่า EA จริงคุยกับ gateway จริงได้
- **ชั้น B** — 3 ข้อใน Phase 1 exit criteria
- **SPEC-030** — 20 สถานการณ์เลวร้ายของ risk layer (Phase 2)

**ลงแรงครั้งเดียว ใช้ตลอด 3 phase** — และถ้าไม่มีมัน exit criteria ของ Phase 1 กับ 2
จะพิสูจน์ไม่ได้เลยนอกจากใช้ตาดู
