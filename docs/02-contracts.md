# 02 — Wire Protocol & Data Contracts

> **นี่คือเอกสารที่สำคัญที่สุดสำหรับ Codex**
> ทุก message ที่วิ่งระหว่าง MQL5 กับ Python ต้องตรงกับที่นี่เป๊ะ
> ถ้าจะเปลี่ยนอะไร → เปิด issue ให้ Claude อัปเดต spec ก่อน ห้ามแก้ฝ่ายเดียว

---

## 1. Transport

| หัวข้อ | ค่า |
|--------|-----|
| Protocol | TCP, client = EA, server = Gateway |
| Address | `127.0.0.1:9101` (dev) / VPN IP (multi-VPS) |
| Framing | **JSON-lines** — 1 message = 1 JSON object + `\n` (LF เท่านั้น ไม่ใช่ CRLF) |
| Encoding | UTF-8, ไม่มี BOM |
| Max frame | 64 KB — เกินนี้ = protocol error, ปิด session |
| Auth | field `token` ใน `HELLO` เท่านั้น เทียบกับ env `FARM_TOKEN` |
| Timeout | EA: read timeout 100ms (non-blocking) · Gateway: session stale หลัง heartbeat หาย 3 ครั้ง |
| Reconnect | EA: exponential backoff 1s → 2s → 4s → 8s → cap 30s + jitter |

**กฎ MQL5:** ห้ามเรียก `SocketRead` แบบ blocking ใน `OnTick`
ใช้ `SocketIsReadable()` เช็คก่อน แล้วอ่านเท่าที่มี — สะสมใน buffer จนพบ `\n`

---

## 2. Envelope (ทุก message ต้องมี)

```json
{
  "v": 1,
  "type": "BAR",
  "msg_id": "01J8X4K2P9QZ7M3N",
  "session_id": "acct-8123456-EURUSD-H1",
  "ts_server": "2026-07-26T14:30:00Z",
  "ts_sent": "2026-07-26T14:30:00.412Z",
  "payload": { }
}
```

| field | type | note |
|-------|------|------|
| `v` | int | protocol version — mismatch = ปฏิเสธ session |
| `type` | string | enum ตาราง §3 |
| `msg_id` | string(26) | ULID-like, monotonic ต่อ session — ใช้ dedupe |
| `session_id` | string | `acct-{login}-{symbol}-{timeframe}` |
| `ts_server` | ISO8601 UTC | **เวลาจาก broker server** (`TimeCurrent()`) — ใช้ตัดสินใจ |
| `ts_sent` | ISO8601 UTC | เวลา local ตอนส่ง — ใช้วัด latency เท่านั้น |
| `payload` | object | ตาม type |

**ห้ามใช้ `ts_sent` ตัดสินใจเทรดเด็ดขาด** — clock drift ทำให้ผลลัพธ์เพี้ยน

---

## 3. Message Types

| type | ทิศทาง | ความถี่ | ต้อง ack |
|------|--------|---------|----------|
| `HELLO` | EA → Brain | ครั้งเดียวตอนต่อ | ✅ `HELLO_ACK` |
| `HELLO_ACK` | Brain → EA | — | — |
| `HEARTBEAT` | EA → Brain | 2s | ✅ `HEARTBEAT_ACK` |
| `HEARTBEAT_ACK` | Brain → EA | — | — |
| `BAR` | EA → Brain | ทุก bar close | ❌ |
| `STATE` | EA → Brain | 5s หรือเมื่อ position เปลี่ยน | ❌ |
| `INTENT` | Brain → EA | เมื่อมีการตัดสินใจ | ✅ `INTENT_ACK` |
| `INTENT_ACK` | EA → Brain | — | — |
| `EXEC_REPORT` | EA → Brain | ทุกครั้งที่ order มีผล | ❌ |
| `RISK_DIRECTIVE` | Brain → EA | เมื่อ risk state เปลี่ยน | ✅ `INTENT_ACK` (reuse) |
| `CONFIG_UPDATE` | Brain → EA | ไม่บ่อย | ✅ |
| `ERROR` | ทั้งสองทาง | เมื่อเกิดปัญหา | ❌ |

---

## 4. Payload Schemas

### 4.1 `HELLO` (EA → Brain)

```json
{
  "token": "…",
  "ea_version": "1.0.0",
  "terminal_build": 4150,
  "account": {
    "login": 8123456,
    "server": "ICMarketsSC-MT5",
    "currency": "USD",
    "leverage": 500,
    "balance": 10000.00,
    "equity": 10000.00,
    "is_demo": true,
    "margin_mode": "NETTING"
  },
  "symbol": {
    "name": "EURUSD",
    "digits": 5,
    "point": 0.00001,
    "tick_size": 0.00001,
    "tick_value": 1.0,
    "contract_size": 100000,
    "volume_min": 0.01,
    "volume_max": 100.0,
    "volume_step": 0.01,
    "stops_level": 0,
    "freeze_level": 0,
    "swap_long": -7.2,
    "swap_short": 1.4,
    "trade_mode": "FULL"
  },
  "timeframe": "H1",
  "strategy_id": "trend_v1",
  "local_limits": {
    "max_lot_per_order": 0.50,
    "max_positions": 3,
    "max_spread_points": 25,
    "daily_loss_pct": 2.0,
    "max_dd_pct": 6.0
  }
}
```

`local_limits` ส่งขึ้นไปเพื่อให้ brain **รู้** ว่า EA จำกัดอะไรอยู่ (จะไม่ส่ง intent ที่เกิน)
แต่ **brain แก้ค่านี้ไม่ได้** — ค่ามาจาก EA input เท่านั้น

### 4.2 `HELLO_ACK` (Brain → EA)

```json
{
  "accepted": true,
  "server_time": "2026-07-26T14:30:01Z",
  "assigned_session_id": "acct-8123456-EURUSD-H1",
  "brain_version": "1.0.0",
  "reject_reason": null,
  "initial_directive": { "mode": "NORMAL", "scale_factor": 1.0 }
}
```

`accepted: false` + `reject_reason` (`BAD_TOKEN` / `VERSION_MISMATCH` / `DUPLICATE_SESSION` / `ACCOUNT_NOT_REGISTERED`)
→ EA ต้อง **ไม่ retry ทันที** รอ 60s แล้วค่อยลองใหม่ และเข้า SafeMode

### 4.3 `BAR` (EA → Brain)

```json
{
  "symbol": "EURUSD",
  "timeframe": "H1",
  "bar_time": "2026-07-26T14:00:00Z",
  "open": 1.08234, "high": 1.08301, "low": 1.08190, "close": 1.08277,
  "tick_volume": 4821,
  "real_volume": 0,
  "spread_points_avg": 8,
  "spread_points_max": 31,
  "is_final": true
}
```

- ส่งเฉพาะ bar ที่ **ปิดแล้ว** (`is_final: true`) เท่านั้นใน Phase 1–3
- ตอน `OnInit` ส่ง backfill 300 bar ล่าสุดเรียงเก่า→ใหม่ เพื่อให้ brain warm feature window ได้
- `spread_*` = สถิติ spread ระหว่าง bar (EA เก็บเองจาก tick)

### 4.4 `STATE` (EA → Brain)

```json
{
  "balance": 10000.00,
  "equity": 10142.30,
  "margin_used": 210.00,
  "margin_free": 9932.30,
  "margin_level_pct": 4829.6,
  "equity_hwm": 10200.00,
  "day_start_equity": 10050.00,
  "day_pl": 92.30,
  "day_pl_pct": 0.92,
  "positions": [
    {
      "ticket": 1234567,
      "symbol": "EURUSD",
      "side": "BUY",
      "volume": 0.20,
      "price_open": 1.08210,
      "sl": 1.08010,
      "tp": 1.08610,
      "profit": 13.40,
      "swap": -0.21,
      "magic": 770001,
      "comment": "intent:01J8X4…",
      "time_open": "2026-07-26T13:12:00Z"
    }
  ],
  "pending_orders": [],
  "net_position": { "EURUSD": 0.20 },
  "guard": {
    "halted": false,
    "halt_reason": null,
    "mode": "NORMAL",
    "current_spread_points": 9
  }
}
```

### 4.5 `INTENT` (Brain → EA) ★ สำคัญสุด

```json
{
  "intent_id": "01J8X4K2P9QZ7M3N",
  "symbol": "EURUSD",
  "target_volume": 0.20,
  "max_slippage_points": 15,
  "sl_price": 1.08010,
  "tp_price": 1.08610,
  "valid_until": "2026-07-26T14:31:00Z",
  "urgency": "NORMAL",
  "provenance": {
    "strategy_id": "trend_v1",
    "model_version": "lgbm-trend-2026.07.20-a3f9c1",
    "feature_hash": "sha256:9f2a…",
    "regime": "TREND_UP_LOW_VOL",
    "confidence": 0.68,
    "risk_scale_applied": 0.75,
    "news_state": "CLEAR",
    "decided_at": "2026-07-26T14:30:00.8Z"
  }
}
```

**สัญญาความหมาย (semantics) — Codex ต้อง implement ให้ตรงนี้:**

| กรณี | ความหมาย |
|------|----------|
| `target_volume` | **net position ที่ต้องการ** (บวก = long, ลบ = short, 0 = ปิดทั้งหมด) |
| `target_volume: 0` | flatten symbol นี้ |
| EA ปัจจุบัน +0.20, target +0.20 | **no-op** — ห้ามส่ง order ใดๆ |
| EA ปัจจุบัน +0.20, target +0.30 | ส่ง BUY 0.10 |
| EA ปัจจุบัน +0.20, target −0.10 | netting: ปิด 0.20 แล้วเปิด SELL 0.10 (หรือ 1 order 0.30 ถ้า netting mode) |
| `sl_price`/`tp_price` เปลี่ยน แต่ volume เท่าเดิม | `OrderModify` เท่านั้น ห้ามปิด/เปิดใหม่ |
| `valid_until` เลยแล้ว | **ทิ้ง intent** ตอบ `INTENT_ACK` status `EXPIRED` |
| `intent_id` ซ้ำกับที่เคยรับ | ทิ้ง ตอบ `DUPLICATE` (dedupe cache ≥ 1000 รายการ) |
| ขัดกับ `LocalRiskGuard` | ทิ้ง ตอบ `REJECTED_BY_GUARD` + reason |
| `target_volume` > `max_lot_per_order` | clamp ลงเป็น limit **ไม่ใช่ reject** แล้วรายงานว่า clamp |

`urgency`: `NORMAL` (รอ spread ปกติได้ ≤ 30s) / `IMMEDIATE` (ส่งเลย) / `PASSIVE` (ใช้ limit order — Phase 6+)

`provenance` **ต้องบันทึกลง DB ทุกครั้ง** และใส่ `intent_id` ย่อใน order comment
เพื่อให้ย้อนได้ว่า trade นี้มาจาก model ไหน

### 4.6 `INTENT_ACK` (EA → Brain)

```json
{
  "intent_id": "01J8X4K2P9QZ7M3N",
  "status": "ACCEPTED",
  "reason": null,
  "volume_before": 0.00,
  "volume_target": 0.20,
  "volume_clamped_to": null,
  "actions_planned": [
    { "op": "OPEN", "side": "BUY", "volume": 0.20 }
  ]
}
```

`status` ∈ `ACCEPTED` · `NOOP` · `EXPIRED` · `DUPLICATE` · `REJECTED_BY_GUARD` · `REJECTED_MARKET_CLOSED` · `REJECTED_INVALID`

### 4.7 `EXEC_REPORT` (EA → Brain)

```json
{
  "intent_id": "01J8X4K2P9QZ7M3N",
  "op": "OPEN",
  "result": "FILLED",
  "retcode": 10009,
  "retcode_text": "TRADE_RETCODE_DONE",
  "ticket": 1234567,
  "side": "BUY",
  "volume_requested": 0.20,
  "volume_filled": 0.20,
  "price_requested": 1.08277,
  "price_filled": 1.08281,
  "slippage_points": 4,
  "spread_at_send_points": 9,
  "latency_ms": 118,
  "attempt": 1,
  "commission": -0.40,
  "error": null
}
```

`result` ∈ `FILLED` · `PARTIAL` · `REJECTED` · `TIMEOUT` · `RETRYING`

### 4.8 `RISK_DIRECTIVE` (Brain → EA)

```json
{
  "directive_id": "01J8X4M…",
  "mode": "REDUCE_ONLY",
  "scale_factor": 0.5,
  "reason": "PORTFOLIO_DAILY_LOSS_WARNING",
  "detail": "farm day_pl = -1.6% (warn at -1.5%)",
  "expires_at": "2026-07-26T23:59:59Z",
  "flatten_symbols": []
}
```

`mode` (เรียงตามความเข้มงวด):

| mode | เปิดใหม่ | เพิ่มขนาด | ลดขนาด/ปิด | หมายเหตุ |
|------|---------|-----------|------------|----------|
| `NORMAL` | ✅ | ✅ | ✅ | |
| `SCALED` | ✅ | ✅ | ✅ | คูณ `scale_factor` ทุก target |
| `REDUCE_ONLY` | ❌ | ❌ | ✅ | ถือของเดิมได้ |
| `FLATTEN` | ❌ | ❌ | ✅ | ปิดทุกอย่างใน `flatten_symbols` (ว่าง = ทุก symbol) |
| `HALT` | ❌ | ❌ | ✅ manual only | หยุดสนิท ต้องปลดล็อกด้วยมือ |

**กฎเหล็ก:** brain สั่ง **เข้ม**กว่าที่ EA ตั้งไว้ได้ แต่สั่ง **ผ่อน**กว่าไม่ได้
ถ้า `LocalRiskGuard` halt อยู่ `RISK_DIRECTIVE: NORMAL` ก็ปลดล็อกไม่ได้

### 4.9 `ERROR`

```json
{
  "code": "PROTOCOL_FRAME_TOO_LARGE",
  "severity": "ERROR",
  "message": "frame 71204 bytes exceeds 65536",
  "context": { "type": "BAR" },
  "fatal": true
}
```

`severity` ∈ `WARN` · `ERROR` · `FATAL` — `fatal: true` → ปิด session

---

## 5. Database Schema (Postgres + TimescaleDB)

```sql
-- hypertable: ข้อมูลราคา
CREATE TABLE bars (
  symbol TEXT NOT NULL, timeframe TEXT NOT NULL, bar_time TIMESTAMPTZ NOT NULL,
  open DOUBLE PRECISION, high DOUBLE PRECISION, low DOUBLE PRECISION, close DOUBLE PRECISION,
  tick_volume BIGINT, spread_avg INT, spread_max INT, broker TEXT NOT NULL,
  PRIMARY KEY (broker, symbol, timeframe, bar_time)
);
SELECT create_hypertable('bars','bar_time');

-- append-only audit trail: ทุกการตัดสินใจ
CREATE TABLE intents (
  intent_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, symbol TEXT NOT NULL,
  target_volume DOUBLE PRECISION NOT NULL, sl_price DOUBLE PRECISION, tp_price DOUBLE PRECISION,
  strategy_id TEXT NOT NULL, model_version TEXT, feature_hash TEXT, regime TEXT,
  confidence DOUBLE PRECISION, risk_scale_applied DOUBLE PRECISION, news_state TEXT,
  decided_at TIMESTAMPTZ NOT NULL, valid_until TIMESTAMPTZ NOT NULL,
  ack_status TEXT, ack_reason TEXT, created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE exec_reports (
  id BIGSERIAL PRIMARY KEY, intent_id TEXT REFERENCES intents(intent_id),
  op TEXT, result TEXT, retcode INT, ticket BIGINT,
  volume_requested DOUBLE PRECISION, volume_filled DOUBLE PRECISION,
  price_requested DOUBLE PRECISION, price_filled DOUBLE PRECISION,
  slippage_points INT, latency_ms INT, attempt INT, commission DOUBLE PRECISION,
  ts TIMESTAMPTZ NOT NULL
);

CREATE TABLE account_state (      -- hypertable
  session_id TEXT NOT NULL, ts TIMESTAMPTZ NOT NULL,
  balance DOUBLE PRECISION, equity DOUBLE PRECISION, margin_level_pct DOUBLE PRECISION,
  day_pl_pct DOUBLE PRECISION, equity_hwm DOUBLE PRECISION,
  guard_halted BOOLEAN, guard_mode TEXT, net_positions JSONB
);
SELECT create_hypertable('account_state','ts');

CREATE TABLE risk_events (
  id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL, scope TEXT,  -- ACCOUNT|FARM
  session_id TEXT, rule TEXT NOT NULL, level TEXT,                -- WARN|BREACH
  observed DOUBLE PRECISION, threshold DOUBLE PRECISION,
  action_taken TEXT, detail JSONB
);

CREATE TABLE model_registry (
  model_version TEXT PRIMARY KEY, strategy_id TEXT NOT NULL,
  status TEXT NOT NULL,                          -- CHALLENGER|CHAMPION|RETIRED
  artifact_path TEXT NOT NULL, feature_spec_hash TEXT NOT NULL,
  train_start DATE, train_end DATE, oos_start DATE, oos_end DATE,
  metrics JSONB NOT NULL,                        -- sharpe, pf, maxdd, trades, winrate
  git_sha TEXT, promoted_at TIMESTAMPTZ, promoted_by TEXT, notes TEXT
);
```

**หลัก:** `intents` + `exec_reports` เป็น **append-only** ห้าม UPDATE/DELETE
(ยกเว้น `ack_status` ที่เติมทีหลังครั้งเดียว) — เป็นหลักฐาน audit

---

## 6. Codegen

```
contracts/schema/*.json        ← Claude เป็นคนแก้ไฟล์นี้เท่านั้น
        │
        ├─► contracts/gen/python/models.py    (datamodel-code-generator → pydantic v2)
        └─► contracts/gen/mql5/FarmMessages.mqh  (custom generator, Codex เขียน)
```

- `contracts/gen/` เป็น **generated** — commit ลง repo แต่ห้ามแก้มือ
- CI ต้องมี job: `make codegen && git diff --exit-code contracts/gen/` (fail ถ้าไม่ตรง)
- MQL5 generator ต้องสร้าง struct + serializer + parser ที่ทดสอบ round-trip ได้

## 7. Versioning

- `v` เพิ่มเมื่อมี **breaking change** เท่านั้น
- เพิ่ม optional field = ไม่ breaking (ทั้ง 2 ฝั่งต้องข้าม unknown field ได้ — Codex ต้องทดสอบข้อนี้)
- ลบ/เปลี่ยนความหมาย field = breaking → bump `v` + อัปเดตทั้ง 2 ฝั่งพร้อมกัน
