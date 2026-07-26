# SPEC-001 — MT5 Executor Skeleton + Wire Layer

**Phase:** 0–1 · **Owner:** Codex · **Depends on:** — · **Blocks:** SPEC-010, SPEC-011

> นี่คือ ticket แรก และเป็น **ตัวอย่างมาตรฐานของ spec** ทุก ticket ต่อไปจะละเอียดระดับนี้

---

## 1. Goal

สร้าง EA โครงเปล่าที่ต่อ TCP ไปยัง gateway ได้ ส่ง/รับ JSON-lines ได้ reconnect เองได้
และ**ยังไม่เทรดอะไรเลย** เสร็จแล้วต้องพิสูจน์ได้ว่าท่อสื่อสารทนสภาพจริง

## 2. Non-goals (ห้ามทำใน ticket นี้)

- ❌ ห้ามส่ง order ใดๆ (ไม่มี `OrderSend` ในโค้ด ticket นี้)
- ❌ ห้ามมี trading logic / indicator
- ❌ ห้าม implement risk guard (SPEC-019)
- ❌ ห้าม implement `BAR`/`STATE` payload เต็ม (SPEC-010) — ticket นี้แค่ `HELLO` + `HEARTBEAT`
- ❌ ห้ามใช้ DLL หรือไฟล์กลางเป็น transport

## 3. Interface

### ไฟล์ที่ต้องสร้าง

```
mt5-ea/Include/Farm/Wire.mqh
mt5-ea/Include/Farm/Json.mqh          (ถ้าไม่ใช้ lib ภายนอก ต้องเขียนเอง — บอกใน note)
mt5-ea/Include/Farm/Logger.mqh
mt5-ea/Experts/FarmExecutor.mq5
tests/mql5/TestWire.mq5               (script รัน assertion แล้ว print ผล)
brain/gateway/echo_server.py          (server จิ๋วสำหรับทดสอบ ticket นี้เท่านั้น)
tests/chaos/test_wire_resilience.py
```

### `Wire.mqh` — public API ที่ต้องมีเป๊ะนี้

```mql5
class CWire {
public:
   // lifecycle
   bool  Init(const string host, const int port, const string token,
              const int connect_timeout_ms = 3000);
   void  Shutdown();

   // เรียกจาก OnTimer ทุก 1 วินาที — จัดการ connect/reconnect/heartbeat/drain
   void  Pump();

   // ส่ง 1 message; คืน false ถ้า queue เต็มหรือยังไม่ connect
   bool  Send(const string json_line);

   // ดึง message ที่รับมาแล้ว 1 ตัว; คืน false ถ้าไม่มี
   bool  Receive(string &out_json_line);

   // state
   bool  IsConnected() const;
   bool  IsAuthenticated() const;         // true หลังได้ HELLO_ACK accepted
   int   SecondsSinceLastInbound() const;  // ใช้กับ R16 brain timeout
   ENUM_WIRE_STATE State() const;

   // metrics (ให้ dashboard/log)
   int   SendQueueDepth() const;
   long  MessagesSent()  const;
   long  MessagesRecv()  const;
   long  ReconnectCount() const;
   long  BytesDropped()  const;
};

enum ENUM_WIRE_STATE {
   WIRE_DISCONNECTED, WIRE_CONNECTING, WIRE_CONNECTED,
   WIRE_AUTHENTICATING, WIRE_READY, WIRE_FAILED_AUTH
};
```

### EA inputs ที่ต้องมีใน `FarmExecutor.mq5`

```mql5
input string InpBrainHost        = "127.0.0.1";
input int    InpBrainPort        = 9101;
input string InpBrainToken       = "";          // ถ้าว่าง → OnInit fail พร้อม log ชัดเจน
input string InpStrategyId       = "trend_v1";
input int    InpMagic            = 770001;
input int    InpHeartbeatSec     = 2;
input int    InpBrainTimeoutSec  = 10;
input int    InpSendQueueMax     = 256;
input bool   InpVerboseLog       = false;
```

## 4. Behaviour

### State machine

```
DISCONNECTED ──Init/Pump──► CONNECTING ──socket ok──► CONNECTED
                  ▲                │                      │ ส่ง HELLO
                  │           socket fail                 ▼
                  │                │              AUTHENTICATING
                  │                │                 │         │
                  └────backoff─────┘        HELLO_ACK│         │HELLO_ACK
                  ▲                          accepted│         │rejected
                  │                                  ▼         ▼
                  └──── socket ปิด/error ─────────  READY   FAILED_AUTH
                                                              │
                                              รอ 60s แล้วกลับ DISCONNECTED
```

### ตารางพฤติกรรม

| สถานการณ์ | พฤติกรรมที่ต้องการ |
|-----------|-------------------|
| `Init` ด้วย token ว่าง | คืน false, log `FATAL: InpBrainToken is empty`, `OnInit` คืน `INIT_FAILED` |
| Connect สำเร็จ | ส่ง `HELLO` ทันที เข้า `AUTHENTICATING` |
| ได้ `HELLO_ACK accepted:true` | เข้า `READY`, เก็บ `assigned_session_id` |
| ได้ `HELLO_ACK accepted:false` | เข้า `FAILED_AUTH`, log reason, **รอ 60s** ก่อนลองใหม่ (ไม่ใช่ backoff ปกติ) |
| ไม่ได้ `HELLO_ACK` ใน 5s | ปิด socket → backoff → reconnect |
| Connect ล้มเหลว | backoff 1→2→4→8→16→30s (cap) + jitter ±20% |
| Reconnect สำเร็จ | reset backoff เป็น 1s, `ReconnectCount++`, ส่ง `HELLO` ใหม่ |
| `Send` ตอนไม่ `READY` | queue ไว้ (ยกเว้น `HELLO`) คืน true ถ้า queue ยังไม่เต็ม |
| Send queue เต็ม (`InpSendQueueMax`) | **drop ตัวเก่าสุด** ไม่ใช่ตัวใหม่, `BytesDropped +=`, log WARN ทุก 10 ครั้ง |
| `SocketSend` ส่งได้บางส่วน | เก็บส่วนที่เหลือไว้ส่งรอบถัดไป **ห้ามส่งซ้ำทั้ง frame** |
| รับข้อมูลไม่ครบ frame | เก็บใน inbound buffer จนพบ `\n` ค่อย emit |
| Inbound buffer > 64KB ไม่พบ `\n` | ส่ง `ERROR PROTOCOL_FRAME_TOO_LARGE`, ปิด socket, reconnect |
| ได้ JSON ที่ parse ไม่ได้ | log WARN, **ข้ามบรรทัดนั้น**, ไม่ปิด connection |
| ได้ message ที่ไม่รู้จัก `type` | log ที่ระดับ DEBUG, ข้าม (forward compat) |
| ได้ message มี field เกิน | **ต้องข้ามได้ ไม่ error** (forward compat — มี test) |
| `HEARTBEAT_ACK` ไม่มา 3 ครั้งติด | ถือว่าตาย ปิด socket → reconnect |
| ตลาดปิด (ไม่มี tick) | `Pump` ยังทำงานผ่าน `OnTimer` heartbeat ต้องไม่หยุด |
| `OnDeinit` | ส่ง `ERROR severity:WARN code:EA_SHUTDOWN` (best-effort), ปิด socket, ลบ timer |

### Timing constraint (บังคับ)

| จุด | ขอบเขต |
|-----|--------|
| `Pump()` ทั้งฟังก์ชัน | ≤ 20ms ปกติ, ≤ 50ms กรณีแย่สุด |
| Socket read ใน `Pump` | ต้องเช็ค `SocketIsReadable()` ก่อน อ่านเท่าที่มี ห้าม blocking |
| `OnTick` | ห้ามเรียก `Pump()` — Pump อยู่ใน `OnTimer` เท่านั้น |
| `EventSetTimer` | 1 วินาที |

## 5. Edge cases ที่ต้องจัดการ

1. Gateway ปิดกลาง `SocketSend` → detect `SocketIsConnected() == false` → reconnect ไม่ crash
2. Gateway ส่ง 3 message ติดกันในหนึ่ง TCP packet → ต้องแยกได้ครบ 3
3. Gateway ส่ง 1 message แยกมา 5 packet → ต้องรวมได้ถูก
4. `\r\n` แทน `\n` → ต้อง trim `\r` ทิ้ง ไม่ทำให้ parse fail
5. บรรทัดว่าง (`\n\n`) → ข้ามเงียบๆ
6. UTF-8 หลายไบต์ใน string (เช่น comment ภาษาไทย) → ต้องไม่ตัดกลางตัวอักษร
7. Terminal เปลี่ยน timezone / DST → heartbeat ต้องไม่พังเพราะใช้ tick count ไม่ใช่ wall clock
8. EA ถูก re-init (เปลี่ยน timeframe บนชาร์ต) → ปิด socket เก่าให้เรียบร้อยก่อนเปิดใหม่
9. รัน EA 2 ตัวบนบัญชีเดียว symbol เดียว → gateway ตอบ `DUPLICATE_SESSION` → EA ที่สองเข้า `FAILED_AUTH`
10. `InpBrainPort` ไม่ได้อยู่ใน allowed list ของ MT5 → `SocketConnect` fail → log ข้อความที่**บอกวิธีแก้** (Tools→Options→Expert Advisors→Allow…)

## 6. Acceptance criteria

- [ ] EA compile ไม่มี warning ด้วย MetaEditor build ≥ 3800
- [ ] ต่อ `echo_server.py` ได้ ส่ง `HELLO` ได้ รับ `HELLO_ACK` แล้วเข้า `READY`
- [ ] Token ผิด → เข้า `FAILED_AUTH` และรอ 60s (วัดจาก log timestamp)
- [ ] Kill server → EA reconnect ตาม backoff ที่กำหนด (พิสูจน์ด้วย log)
- [ ] Restart server → EA กลับ `READY` เอง ไม่ต้องแตะอะไร
- [ ] `Pump()` p99 < 20ms (วัดด้วย `GetMicrosecondCount()` แล้ว log)
- [ ] รันทิ้ง 24 ชม. บน demo (ผ่านสุดสัปดาห์ที่ตลาดปิด) — heartbeat ไม่ขาด ไม่ memory leak
- [ ] ไม่มี `OrderSend` ใน codebase ของ ticket นี้ (`grep` ต้องไม่เจอ)
- [ ] Send queue เต็ม → drop ตัวเก่าสุด (มี test)
- [ ] Message ที่มี field เกิน → ไม่ error (มี test)

## 7. Test list

### MQL5 (`tests/mql5/TestWire.mq5`)
| test | ตรวจอะไร |
|------|----------|
| `test_framing_multiple_in_one_read` | edge case 2 |
| `test_framing_split_across_reads` | edge case 3 |
| `test_framing_crlf_tolerance` | edge case 4 |
| `test_framing_empty_line_skipped` | edge case 5 |
| `test_framing_oversize_frame_rejected` | 64KB rule |
| `test_json_parse_malformed_skips_line` | ไม่ปิด connection |
| `test_json_unknown_field_ignored` | forward compat |
| `test_json_unknown_type_ignored` | forward compat |
| `test_queue_full_drops_oldest` | drop policy |
| `test_partial_send_resumes` | ไม่ส่งซ้ำ frame |
| `test_utf8_multibyte_not_split` | edge case 6 |

### Python (`tests/chaos/test_wire_resilience.py`)
| test | ตรวจอะไร |
|------|----------|
| `test_ea_reconnects_after_server_kill` | backoff + recovery |
| `test_backoff_schedule_matches_spec` | 1,2,4,8,16,30 + jitter |
| `test_bad_token_waits_60s` | ไม่ hammer server |
| `test_duplicate_session_rejected` | edge case 9 |
| `test_heartbeat_gap_triggers_reconnect` | 3 misses |
| `test_no_heartbeat_loss_over_1h` | soak แบบย่อ |

**Test ต้องพิสูจน์พฤติกรรมจริง ไม่ใช่ mock socket ทั้งหมด** — ใช้ `echo_server.py` จริง

## 8. Files

**Touch:** ตามรายการ §3
**ห้ามแตะ:** `contracts/schema/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions — Codex ต้องได้คำตอบก่อนเริ่ม

| # | คำถาม | ทำไมสำคัญ | ค่า default ถ้ายังไม่ตอบ |
|---|-------|-----------|------------------------|
| Q1 | บัญชีเป็น **netting** หรือ **hedging**? | เปลี่ยน `OrderRouter` ทั้งหมด (SPEC-011) — ticket นี้ยังไม่กระทบ แต่ต้องรู้ก่อน SPEC-011 | สมมติ **hedging** (โบรกเกอร์ไทย/offshore ส่วนใหญ่) |
| Q2 | มี JSON library MQL5 ที่ต้องการให้ใช้ หรือเขียนเอง? | เขียนเองคุมได้ แต่ใช้เวลา | เขียนเอง (parser ย่อยเฉพาะที่ contract ต้องใช้) — ไม่ดึง lib ภายนอกเข้า repo |
| Q3 | Symbol/timeframe หลักคืออะไร? | ยังไม่กระทบ ticket นี้ | EURUSD H1 สำหรับ dev |

> Q1, Q3 ไม่บล็อก ticket นี้ — Codex เริ่มได้เลย
> **Q2 ให้ตัดสินใจตาม default (เขียนเอง) แล้วรายงานขนาดโค้ดใน handoff**
