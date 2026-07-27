# SPEC-013 — Gateway: asyncio TCP server · auth · session registry

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-002, SPEC-004, SPEC-006, SPEC-064
**Blocks:** SPEC-014, SPEC-015, SPEC-016, SPEC-018, SPEC-027, SPEC-028
**อ้าง:** [02-contracts §1–§3](../02-contracts.md) · [`envelope.json`](../../contracts/schema/envelope.json)

> **นี่คือคอขวดของ Phase 1 ทั้ง phase** — ไม่มี gateway = ทดสอบ end-to-end ไม่ได้เลย

---

## 1. Goal

server ที่ EA ต่อเข้ามาแล้วคุยกันได้ครบวงจร: auth · session registry · framing ·
validate ทุก message · ส่ง INTENT/RISK_DIRECTIVE ออกไปหา session ที่ต้องการ ·
และตรวจจับ session ที่ตายแล้ว

## 2. Non-goals

- ❌ **ห้ามเขียนลง DB** — SPEC-014 เป็นคนทำ · ticket นี้ให้แค่ **handler interface** (§3.4)
- ❌ ห้ามมี trading logic / strategy (SPEC-015)
- ❌ ห้ามมี portfolio risk (SPEC-025) — ส่ง `RISK_DIRECTIVE` ได้ แต่ **ไม่ตัดสินใจเอง**
- ❌ **ห้ามลบ/แทนที่ `brain/gateway/echo_server.py`** — ดู §3.2
- ❌ ห้ามแตะ `contracts/schema/**` · `contracts/gen/**`
- ❌ ห้ามทำ TLS / VPN (Phase 6 · SPEC-054)

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `brain/gateway/server.py` | `FarmGateway` — ตัวจริง |
| `brain/gateway/session.py` | `Session` — สถานะต่อ 1 connection |
| `brain/gateway/framing.py` | อ่าน/เขียน JSON-lines (ฝั่ง server) |
| `brain/gateway/handlers.py` | protocol ของ handler + ตัว default ที่แค่ log |
| `brain/gateway/__main__.py` | รันเป็น service |
| `tests/test_gateway.py` | driver เป็น Python TCP client |

### 3.2 `echo_server.py` **ต้องอยู่ต่อ** — คนละหน้าที่กัน

| | `echo_server.py` (มีอยู่) | `server.py` (ticket นี้) |
|---|---|---|
| หน้าที่ | **test double ที่สั่งพฤติกรรมได้** | ตัวจริง |
| ใช้ที่ไหน | chaos suite — ต้องสั่งให้ reject HELLO · หยุดส่ง ack · ปิด socket ทิ้ง ([work-order §1.5](../work-order.md)) | production |
| validate schema | ไม่จำเป็น | **บังคับ** |

**ห้ามรวมสองตัวเข้าด้วยกัน** — ตัวจริงที่มี "โหมดทำตัวพัง" ไว้ให้ test คือของอันตราย

### 3.3 `FarmGateway` — API

```python
class FarmGateway:
    def __init__(self, *, host: str, port: int, token: str,
                 registry: SymbolRegistry,
                 handlers: Handlers,
                 heartbeat_miss_limit: int = 3,
                 hello_timeout_sec: float = 5.0,
                 outbound_queue_max: int = 256) -> None: ...

    async def start(self) -> None: ...
    async def stop(self) -> None: ...          # ปิดทุก session อย่างสุภาพ

    # ---- ส่งออกไปหา EA ----
    async def send_intent(self, session_id: str, payload: IntentPayload) -> None: ...
    async def send_risk_directive(self, session_id: str, payload: RiskDirectivePayload) -> None: ...
    async def send_config_update(self, session_id: str, payload: dict) -> None: ...
        # ทั้งสามอย่าง: ไม่มี session -> SessionNotFound · คิวเต็ม -> OutboundQueueFull

    # ---- ข้อมูลสำหรับ dashboard/risk ----
    def sessions(self) -> list[SessionInfo]: ...
    def session(self, session_id: str) -> SessionInfo | None: ...
```

### 3.4 `Handlers` — จุดต่อของ SPEC-014

```python
class Handlers(Protocol):
    async def on_hello(self, s: SessionInfo, payload: HelloPayload) -> None: ...
    async def on_bar(self, s: SessionInfo, payload: BarPayload) -> None: ...
    async def on_state(self, s: SessionInfo, payload: StatePayload) -> None: ...
    async def on_intent_ack(self, s: SessionInfo, payload: IntentAckPayload) -> None: ...
    async def on_exec_report(self, s: SessionInfo, payload: ExecReportPayload) -> None: ...
    async def on_error(self, s: SessionInfo, payload: ErrorPayload) -> None: ...
    async def on_session_closed(self, s: SessionInfo, reason: str) -> None: ...
```

**default = log อย่างเดียว** · handler ที่ raise **ต้องไม่ทำให้ session ตาย**
→ log `ERROR` + นับ แล้วไปต่อ (EA ไม่ควรโดนตัดเพราะ bug ฝั่ง brain)

⚠️ **แต่ห้ามกลืนเงียบ** — ต้องมีตัวนับที่ dashboard เห็น (AGENTS ข้อ 10)

---

## 4. Behaviour

### 4.1 Handshake

| ลำดับ | กฎ |
|-------|-----|
| 1 | connection เปิด → **ต้องได้ `HELLO` เป็น message แรกภายใน 5 วินาที** ไม่งั้นปิด |
| 2 | ไม่ใช่ `HELLO` → ปิดทันที (ไม่ตอบอะไร — ยังไม่ยืนยันตัวตน) |
| 3 | `v != 1` → `HELLO_ACK accepted:false VERSION_MISMATCH` แล้วปิด |
| 4 | token ผิด → `BAD_TOKEN` แล้วปิด |
| 5 | `account.margin_mode != RETAIL_HEDGING` → `MARGIN_MODE_NOT_HEDGING` |
| 6 | `symbol.name` ไม่อยู่ใน registry ของ `account.server` → `SYMBOL_NOT_IN_REGISTRY` |
| 7 | ผ่านหมด → `accepted:true` + `assigned_session_id` + `initial_directive` |

**ข้อ 5–6 คือการตรวจซ้ำ** — EA ควรจะ fail ที่ `OnInit` ไปแล้ว แต่ EA เวอร์ชันเก่า
หรือถูกแก้อาจข้ามไป · **ชั้น server ต้องกันเอง** (เหตุผลเดียวกับที่เขียนไว้ใน
[02-contracts §4.2](../02-contracts.md))

**token เทียบด้วย `secrets.compare_digest`** และ **ห้าม log ค่า token เด็ดขาด**
— log ได้แค่ `token=***` หรือความยาว

### 4.2 ★ Duplicate session — "ตัวใหม่ชนะ" แต่ต้องนับ

นี่คือจุดที่ spec เดิมสองที่ขัดกัน และต้องตัดสิน:

- [SPEC-001 §5 edge 9](SPEC-001-mt5-executor.md) บอกว่า EA ตัวที่สองต้องได้ `DUPLICATE_SESSION`
- แต่ **EA ที่ reconnect หลังเน็ตหลุดจะส่ง `session_id` เดิม** และฝั่ง server อาจยังไม่รู้ว่า
  connection เก่าตายแล้ว → ถ้า reject ตรงๆ EA จะรอ 60 วินาที **แล้ววนซ้ำไม่จบ**

**กฎที่ใช้:**

| สถานการณ์ | ทำอะไร |
|-----------|--------|
| `session_id` ซ้ำ ครั้งที่ 1–2 ภายใน 5 นาที | **ตัวใหม่ชนะ** — ปิด connection เก่า (`on_session_closed` reason `EVICTED_BY_NEWER`) แล้วรับตัวใหม่ · `eviction_count++` |
| `session_id` เดิมโดน evict **≥ 3 ครั้งใน 5 นาที** | **นี่คือ EA สองตัวจริง** → ตอบ `DUPLICATE_SESSION` + **alert** |

**เหตุผล:** EA จะ reconnect ก็ต่อเมื่อมันเชื่อว่าท่อเดิมตายแล้ว — การให้ตัวใหม่ชนะ
จึงถูกเกือบทุกครั้ง · ส่วน EA สองตัวจริงจะแย่งกันตลอดเวลา ซึ่งจะทะลุเกณฑ์ 3 ครั้งเร็วมาก
→ ได้ทั้ง reconnect ที่ลื่นและการจับ misconfiguration

`eviction_count` **ต้องขึ้น dashboard** — ค่าที่ค่อยๆ ไต่ขึ้นคือสัญญาณว่าท่อไม่นิ่ง

### 4.3 Framing ฝั่ง server — ต้องสมมาตรกับ EA

กฎเดียวกับ [SPEC-001 §4/§5](SPEC-001-mt5-executor.md) แต่มองจากอีกฝั่ง
**ความไม่สมมาตรตรงนี้คือ bug ที่หายาก**

| สถานการณ์ | ต้องได้ |
|-----------|---------|
| หลาย message ใน packet เดียว | แยกครบทุกตัว |
| message เดียวมาหลาย packet | รวมได้ถูก |
| `\r\n` แทน `\n` | trim `\r` ทิ้ง |
| บรรทัดว่าง | ข้ามเงียบๆ |
| ยังไม่พบ `\n` แต่ buffer > **64 KB** | ส่ง `ERROR PROTOCOL_FRAME_TOO_LARGE` แล้ว**ปิด session** |
| JSON parse ไม่ได้ | log WARN · **ข้ามบรรทัดนั้น** · **ห้ามปิด session** |
| `type` ไม่รู้จัก | log DEBUG · ข้าม (forward compat) |
| schema ไม่ผ่าน | ดู §4.4 |

**นับ byte ไม่ใช่ตัวอักษร** สำหรับเพดาน 64 KB — ข้อความไทย 1 ตัว = 3 byte

### 4.4 message ที่ schema ไม่ผ่าน — ทิ้ง ไม่ใช่ตัด แต่มีเพดาน

| ครั้งที่ | ทำอะไร |
|---------|--------|
| 1–N | ทิ้ง message นั้น · ส่ง `ERROR severity:WARN code:SCHEMA_VALIDATION_FAILED` พร้อม**ชื่อ field ที่พัง** · `invalid_count++` |
| `invalid_count` > **20 ใน 60 วินาที** | **ปิด session** พร้อม `ERROR severity:FATAL` |

เหตุผลของเพดาน: EA ที่พัง (หรือถูกแก้) อาจยิง message เสียรัวจนกิน CPU ทั้ง gateway
· ตัดตัวที่พังออกดีกว่าให้มันลาก session อื่นลงไปด้วย

**`ERROR` ที่ส่งกลับต้องมีชื่อ field** — `"payload.sl: value must be > 0"`
ไม่ใช่ `"validation failed"` (กฎเดียวกับ [`error.json`](../../contracts/schema/error.json))

### 4.5 Heartbeat

| | |
|---|---|
| ได้ `HEARTBEAT` | ตอบ `HEARTBEAT_ACK` ทันที **echo `seq` เดิม** |
| ไม่ได้ inbound เลย > `heartbeat_sec × (miss_limit + 1)` | ถือว่าตาย → ปิด session reason `HEARTBEAT_TIMEOUT` |
| `wire.bytes_dropped > 0` | **log WARN + นับ** — EA ทำข้อมูลหาย |
| `wire.reconnect_count` ไต่ขึ้น | log · ขึ้น dashboard |
| `broker_utc_offset_sec` เปลี่ยน | log WARN — DST เปลี่ยนหรือ [G6](../06-gap-audit.md) กลับมา |

### 4.6 ★ ตรวจ `ts_sent >= ts_server` ทุก message

invariant นี้เขียนไว้ใน [02-contracts §2](../02-contracts.md) แล้ว
**gateway คือที่ที่ตรวจได้จริง** เพราะเห็นทั้งสองค่าพร้อมกัน

ถ้ากลับกัน = EA ยังไม่หัก broker offset ([SPEC-063](SPEC-063-broker-time.md))
→ log `WARN` ครั้งแรกต่อ session แล้วนับ · **ห้ามปิด session** (Phase 1 ยังมี bug นี้อยู่จริง)

ถือเป็น**เครื่องตรวจว่า SPEC-063 ทำงานจริงไหม** จากฝั่งที่เป็นกลาง

### 4.7 Backpressure ขาออก

| กฎ | |
|----|---|
| ทุก session มีคิวขาออกของตัวเอง สูงสุด `outbound_queue_max` (256) | |
| คิวเต็ม → `send_*()` **raise `OutboundQueueFull`** | **ห้าม drop เงียบ** — ต่างจากฝั่ง EA เพราะที่นี่คือ `INTENT` = คำสั่งเทรด |
| `await writer.drain()` ต้องมี **timeout** | EA ที่ค้างต้องไม่ทำให้ gateway ค้าง |
| drain timeout → ปิด session นั้น | **ห้ามให้ session ช้าตัวเดียวบล็อกตัวอื่น** |

**ทำไม EA drop ได้แต่ gateway ห้าม:** ฝั่ง EA ที่หายคือ telemetry (BAR/STATE)
ซึ่ง brain ตรวจ gap ได้ · ฝั่ง gateway ที่หายคือ **INTENT ที่หายไปเงียบๆ**
= brain คิดว่าสั่งแล้วแต่ไม่มีอะไรเกิดขึ้น

### 4.8 การแยกงานต่อ session

1 connection = **1 task อ่าน + 1 task เขียน** (หรือ 1 task + คิว)
· exception ใน session หนึ่ง **ห้ามกระทบ session อื่น**
· `stop()` ต้องรอทุก task จบ (มี timeout) ไม่ใช่ยิง `cancel()` แล้วจบ

### 4.9 Config จาก env เท่านั้น

`FARM_TOKEN` · `FARM_GATEWAY_HOST` · `FARM_GATEWAY_PORT` — จาก `.env` ([SPEC-002](SPEC-002-repo-scaffold.md))
**ห้ามมี default ที่เป็น token จริง** · `FARM_TOKEN` ว่าง → **ไม่ยอมสตาร์ท**

---

## 5. Edge cases

1. **EA ส่ง `HELLO` ซ้ำบน connection เดิม** → ละเว้น + WARN (ไม่ใช่ reset session)
2. **EA ปิด socket กลาง frame** → ทิ้ง buffer · `on_session_closed` · ไม่ leak
3. **client ต่อเข้ามาแล้วเงียบ** → ตัดที่ 5 วินาทีตาม §4.1 ข้อ 1
4. **client ที่ไม่ใช่ EA เลย** (เช่น browser ยิง HTTP) → parse ไม่ได้ → ปิดหลังเกินเพดาน §4.4
5. **`send_intent` ตอน session เพิ่งตายเสี้ยววินาทีก่อน** → `SessionNotFound`
   · caller (SPEC-025) ต้องจัดการ ไม่ใช่ gateway เดาแทน
6. **`stop()` ตอนมี session ค้าง** → ปิดสุภาพ มี timeout แล้วบังคับ
7. **port ถูกใช้อยู่** → error ที่บอก port ชัดเจน ไม่ใช่ `OSError` ดิบ
8. **`registry` ไม่มี broker ตาม `account.server`** → `SYMBOL_NOT_IN_REGISTRY` (§4.1 ข้อ 6)
9. **handler ช้ามาก** → **ห้ามบล็อกการอ่าน socket** · handler ต้องถูกเรียกแบบไม่รอผล
   หรือมี timeout · ไม่งั้น EA จะ heartbeat timeout เพราะ brain ช้า
10. **message ใหญ่ 63 KB (ผ่านเกณฑ์)** → ต้องรับได้ ไม่ใช่พังที่ buffer
11. **หลาย EA ต่อพร้อมกัน 6 ตัว** → ทำงานอิสระกันจริง
12. **`seq` ของ heartbeat ย้อนหลัง** (EA restart) → ยอมรับ + log ไม่ใช่ error

---

## 6. Acceptance criteria

- [ ] EA จริง (`FarmExecutor`) ต่อได้ ได้ `HELLO_ACK accepted:true` และเข้า `READY`
      — **พิสูจน์ด้วย harness ใน [work-order §1.5](../work-order.md)**
- [ ] `python -m brain.gateway` สตาร์ทได้จาก `.env`
- [ ] `FARM_TOKEN` ว่าง → **ไม่สตาร์ท** พร้อม error ที่อ่านรู้เรื่อง
- [ ] token ผิด → `BAD_TOKEN` · **`grep -ri "token" logs` ไม่เจอค่า token จริง**
- [ ] `margin_mode != RETAIL_HEDGING` → `MARGIN_MODE_NOT_HEDGING`
- [ ] symbol นอก registry → `SYMBOL_NOT_IN_REGISTRY`
- [ ] **reconnect ด้วย `session_id` เดิม 2 ครั้ง → สำเร็จทั้งสองครั้ง** (ตัวใหม่ชนะ)
- [ ] **ครั้งที่ 3 ใน 5 นาที → `DUPLICATE_SESSION`** + `eviction_count` ถูกต้อง
- [ ] framing ผ่านครบทุกเคสใน §4.3 (มี test ต่อเคส)
- [ ] frame > 64 KB → `PROTOCOL_FRAME_TOO_LARGE` + ปิด · **นับเป็น byte**
- [ ] JSON พัง → session **ยังอยู่** · schema พัง 21 ครั้งใน 60s → **ปิด**
- [ ] `ts_sent < ts_server` → WARN + นับ · session ยังอยู่
- [ ] คิวขาออกเต็ม → `OutboundQueueFull` **ไม่ใช่ drop เงียบ**
- [ ] EA ที่ไม่อ่าน socket → session นั้นโดนตัดที่ drain timeout · **session อื่นไม่กระทบ**
- [ ] handler ที่ raise → session ยังอยู่ + ตัวนับเพิ่ม
- [ ] 6 session พร้อมกัน ส่ง BAR/STATE ครบ ไม่มีข้าม ไม่มีสลับ session
- [ ] `python tools/task.py check` ผ่าน (test ของ ticket นี้ไม่ต้องใช้ DB/MT5)
- [ ] `grep -rn "except:" brain/gateway/` — ไม่เจอ bare except
- [ ] `brain/gateway/echo_server.py` **ยังอยู่และยังใช้งานได้**

## 7. Test list — `tests/test_gateway.py`

driver เป็น **Python TCP client จริง** (ไม่ mock socket)

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_hello_accepted_assigns_session` | |
| 2 | `test_no_hello_within_timeout_closes` | §4.1 ข้อ 1 |
| 3 | `test_first_message_not_hello_closes` | §4.1 ข้อ 2 |
| 4 | `test_version_mismatch_rejected` | |
| 5 | `test_bad_token_rejected` | |
| 6 | `test_token_never_appears_in_logs` | ★ ความปลอดภัย |
| 7 | `test_margin_mode_not_hedging_rejected` | ADR-001 ชั้นที่ 2 |
| 8 | `test_symbol_not_in_registry_rejected` | SPEC-064 ชั้นที่ 2 |
| 9 | `test_reconnect_same_session_evicts_old` | ★★ §4.2 |
| 10 | `test_third_duplicate_within_window_rejected` | ★★ §4.2 |
| 11 | `test_framing_multiple_in_one_packet` | สมมาตรกับ EA |
| 12 | `test_framing_split_across_packets` | |
| 13 | `test_framing_crlf_and_blank_lines` | |
| 14 | `test_frame_over_64kb_bytes_closes_session` | ★ นับ byte |
| 15 | `test_malformed_json_does_not_close_session` | ★ |
| 16 | `test_schema_invalid_replies_error_with_field_name` | |
| 17 | `test_invalid_flood_closes_session_after_threshold` | §4.4 |
| 18 | `test_unknown_type_ignored` | forward compat |
| 19 | `test_heartbeat_ack_echoes_seq` | |
| 20 | `test_heartbeat_timeout_closes_session` | |
| 21 | `test_ts_sent_before_ts_server_warns_not_closes` | ★ ตรวจ SPEC-063 จากฝั่งกลาง |
| 22 | `test_outbound_queue_full_raises_not_drops` | ★★ §4.7 |
| 23 | `test_slow_client_does_not_block_other_sessions` | ★★ §4.8 |
| 24 | `test_handler_exception_does_not_kill_session` | |
| 25 | `test_six_concurrent_sessions_isolated` | |
| 26 | `test_send_to_dead_session_raises` | edge 5 |
| 27 | `test_stop_closes_all_sessions_cleanly` | edge 6 |

**test 22–23 คือคู่ที่สำคัญที่สุด** — ทั้งคู่เป็นเรื่อง "session หนึ่งพัง ต้องไม่ลากตัวอื่นลงไป"

> **หมายเหตุเรื่อง "test ที่ mock หมดไม่นับ":** ที่นี่ใช้ Python client ได้เต็มที่
> เพราะ**สิ่งที่ทดสอบคือ server** และ client เป็น TCP client จริง ไม่ใช่ mock
> ส่วนการพิสูจน์ว่า **EA จริง** คุยกับ gateway ได้ อยู่ที่ chaos harness (§6 ข้อแรก)

## 8. Files

**Touch:** `brain/gateway/{server,session,framing,handlers,__main__}.py` · `tests/test_gateway.py`

**ห้ามแตะ:** `brain/gateway/echo_server.py` · `contracts/**` · `docs/**` · `mt5-ea/**`
· `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | handler เรียกแบบ `await` ตรงๆ หรือโยนเข้า task queue? | **ไม่บล็อก** — ขอแค่ handler ช้าต้อง**ไม่บล็อกการอ่าน socket** (edge 9) · เลือกทางไหนก็ได้ที่ทำให้ test 23 ผ่าน · **รายงานว่าเลือกอะไรและ trade-off คืออะไร** |
| Q2 | เกณฑ์ duplicate (3 ครั้ง / 5 นาที) เหมาะไหม | **ไม่บล็อก** — เริ่มที่ค่านี้ · ถ้าเจอ false positive ตอน soak ให้**รายงานตัวเลขจริง** อย่าปรับเอง |
| Q3 | ควรมี rate limit ของ BAR/STATE ต่อ session ไหม | **ยังไม่ต้อง** — §4.4 คุมเฉพาะ message เสีย · rate limit ของ message ที่ถูกต้องเก็บไว้ตอนเจอปัญหาจริง |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ 002 · 004 · 006 · 064 merge**

---

## ภาคผนวก — ทำไม §4.2 ถึงเป็นจุดที่ต้องคิดให้ขาด

"EA ตัวที่สองต้องโดนปฏิเสธ" ฟังดูถูกจนไม่มีใครตั้งคำถาม
แต่บนเน็ตจริง **EA ตัวเดิมที่ reconnect กับ EA ตัวที่สอง หน้าตาเหมือนกันทุกอย่าง**
ฝั่ง server แยกไม่ออกจาก HELLO ใบเดียว

ถ้าเลือก "ปฏิเสธไว้ก่อน" → เน็ตกระตุกครั้งเดียว EA จะโดนล็อกออก 60 วินาที
และถ้า TCP ฝั่ง server ยังไม่ timeout มันจะโดนปฏิเสธซ้ำ **วนไม่จบจนกว่า TCP จะยอมตาย**
— อาการที่เห็นคือ *"EA ต่อไม่ติดเป็นชั่วโมง"* หลังเน็ตสะดุดแค่วินาทีเดียว

ถ้าเลือก "ตัวใหม่ชนะเสมอ" → EA สองตัวจริงจะแย่งกันเงียบๆ ตลอดไป
ทั้งคู่ทำงานครึ่งๆ และไม่มีใครรู้

**ทางออกคือแยกสองเคสด้วย *ความถี่* ไม่ใช่ด้วยตัว message** — reconnect เกิดนานๆ ครั้ง
การแย่งกันเกิดตลอดเวลา · `eviction_count` จึงไม่ใช่แค่ตัวเลขสวยๆ บน dashboard
แต่เป็นตัวแยกสองสถานการณ์นี้ออกจากกัน
