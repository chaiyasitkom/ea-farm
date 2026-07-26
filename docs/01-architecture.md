# 01 — สถาปัตยกรรมระบบ

## ภาพรวม 3 Plane

```
╔══════════════════════════════════════════════════════════════════════════╗
║  RESEARCH PLANE  (offline / รันเมื่อต้องการ)                              ║
║                                                                          ║
║  Data Ingest ──► Data Lake ──► Feature Store ──► Backtest Engine         ║
║  (MT5 hist,      (Parquet,     (versioned,       (event-driven,          ║
║   tick, calendar) partitioned)  point-in-time)    spread/slippage model) ║
║                                        │                                 ║
║                                        ▼                                 ║
║                          Walk-Forward Optimizer                          ║
║                                        │                                 ║
║                                        ▼                                 ║
║                     Model Registry  (champion / challenger)              ║
║                     artifacts: model.onnx, params.json, metadata.json    ║
╚════════════════════════════════════╪═════════════════════════════════════╝
                                     │ promote (manual approval gate)
                                     ▼
╔══════════════════════════════════════════════════════════════════════════╗
║  CONTROL PLANE  (Python, always-on, 1 instance)                          ║
║                                                                          ║
║  ┌────────────────────────────────────────────────────────────────────┐ ║
║  │ GATEWAY — TCP server, JSON-lines, token auth, session registry     │ ║
║  │  รู้จักทุก terminal ที่ต่อเข้ามา, route message, ตรวจ heartbeat      │ ║
║  └───────────────────────────┬────────────────────────────────────────┘ ║
║                              │                                          ║
║  ┌───────────────┬───────────┴──────┬──────────────┬─────────────────┐ ║
║  │ SignalEngine  │  RegimeService   │ NewsService  │ (per-strategy)  │ ║
║  │ ONNX inference│  HMM / cluster   │ calendar +   │ rule strategies │ ║
║  │ → intent      │  → regime label  │ LLM sentiment│                 │ ║
║  │                  + scale hint    │ → block/bias │                 │ ║
║  └───────┬───────┴─────────┬────────┴──────────────┴─────────────────┘ ║
║          │ features        │ ต้องการราคา "ทุก" symbol ไม่ใช่แค่ที่เทรด   ║
║  ┌───────┴─────────────────┴──────────────────────────────────────────┐ ║
║  │ MARKET DATA COLLECTOR  ★ ไม่ผูกกับบัญชีใด                          │ ║
║  │  1 MT5 terminal อ่านอย่างเดียว + MetaTrader5 python pkg            │ ║
║  │  push bar ทุก symbol ในจักรวาล → correlation (P4), regime, feature │ ║
║  │  EA ส่งมาแค่ symbol ที่ตัวเองเทรด — ไม่พอสำหรับ portfolio risk      │ ║
║  └────────────────────────────────────────────────────────────────────┘ ║
║                              │ proposed intents                        ║
║                              ▼                                          ║
║  ┌────────────────────────────────────────────────────────────────────┐ ║
║  │ PORTFOLIO RISK MANAGER  ── มีอำนาจ veto/ลดขนาด/สั่ง flatten ทั้งฟาร์ม │ ║
║  │  cross-account exposure netting · currency concentration           │ ║
║  │  correlation cap · aggregate daily loss · strategy allocation       │ ║
║  │  KILL SWITCH authority                                             │ ║
║  └───────────────────────────┬────────────────────────────────────────┘ ║
║                              │ approved intents + risk directives       ║
║  ┌───────────────┐  ┌────────┴───────┐  ┌────────────────────────────┐ ║
║  │ Postgres +    │  │ Ops Dashboard  │  │ Alerting (Telegram)        │ ║
║  │ TimescaleDB   │  │ FastAPI+HTMX   │  │ breach / disconnect / DD   │ ║
║  └───────────────┘  └────────────────┘  └────────────────────────────┘ ║
╚════════════════════════════════════╪═════════════════════════════════════╝
                                     │
        ┌────────────────────────────┴─────────────────────────────┐
        │ WATCHDOG  ★ process แยก เล็กที่สุด ไม่มี dependency ร่วม   │
        │  brain เขียน liveness file ทุก 5s · watchdog อ่านทุก 15s  │
        │  brain เงียบ > 60s → Telegram alert + restart service     │
        │  เหตุผล: alerting อยู่ *ใน* brain — brain ตาย = ไม่มีใครบอก │
        └──────────────────────────────────────────────────────────┘
                                     │ JSON-lines over TCP (localhost/VPN)
                                     │ 1 session per terminal
                                     ▼
╔══════════════════════════════════════════════════════════════════════════╗
║  EXECUTION PLANE  (Windows VPS, N × MT5 terminal)                        ║
║                                                                          ║
║   MT5 #1 (Acct A)        MT5 #2 (Acct B)        MT5 #3 (Acct C)  ...     ║
║   FarmExecutor.ex5       FarmExecutor.ex5       FarmExecutor.ex5         ║
║   ├─ Wire        (native MQL5 socket, reconnect, backpressure)           ║
║   ├─ LocalRiskGuard  ★ hard limits — ทำงานได้แม้ brain ตาย ★             ║
║   ├─ OrderRouter (target-state reconciler, idempotent, slippage cap)     ║
║   ├─ StateReporter (bar close, equity, positions, heartbeat)             ║
║   └─ SafeMode    (brain หาย > N วินาที → hold หรือ flatten ตาม config)   ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## ทำไมออกแบบแบบนี้

### 1. ทำไม EA ถือ risk guard เอง ไม่ใช่ Python จัดการหมด

Python process ตายได้ (OOM, exception, Windows update, VPS reboot) ถ้า risk logic อยู่ที่ Python
เท่านั้น พอ Python ตายตอนถือ position อยู่ = พอร์ตเปลือย ไม่มี stop ไม่มี daily limit

→ EA ต้องมี **hard limit ที่ compile ติดไปในตัว** และทำงานได้แม้ socket หลุด

### 2. ทำไม "target state" ไม่ใช่ "order command"

```
❌ แบบคำสั่ง:  brain → "BUY EURUSD 0.20"
   ปัญหา: ส่งซ้ำ = 0.40 lot / ack หาย = ไม่รู้ว่าเข้าไปหรือยัง / restart = สถานะไม่ตรง

✅ แบบสถานะเป้าหมาย: brain → "target EURUSD = +0.20 lot"
   EA อ่าน position ปัจจุบัน คำนวณ delta แล้วส่งเฉพาะส่วนต่าง
   ส่งซ้ำ 10 ครั้ง = ผลลัพธ์เดียวกัน / restart = reconcile ได้ทันที
```

นี่คือ **ข้อตัดสินใจสถาปัตยกรรมที่สำคัญที่สุดในโปรเจกต์นี้** ห้ามเปลี่ยนโดยไม่คุยกัน

### 3. ทำไม MQL5 native socket ไม่ใช่ DLL / ไฟล์กลาง

- `SocketCreate`/`SocketConnect`/`SocketSend`/`SocketRead` มีใน MQL5 มาตรฐาน ไม่ต้องพึ่ง DLL
  (ต้องใส่ host ใน MT5 → Tools → Options → Expert Advisors → Allow WebRequest/Socket list)
- ไฟล์กลาง (`Common\Files`) ช้า มี race condition และ debug ยาก
- DLL ต้อง compile แยก เพิ่ม attack surface และเปิด "Allow DLL imports" ซึ่งอันตราย

### 4. ทำไมต้องมี Research Plane แยก

ห้าม train หรือ optimize ในระบบ live เด็ดขาด — จะกิน CPU แย่ง execution และเสี่ยง
model ที่ยัง fit ไม่เสร็จหลุดไปเทรด promotion ต้องผ่าน **manual approval gate**

---

## Component Breakdown

### EXECUTION PLANE — `mt5-ea/`

| Component | หน้าที่ | ห้ามทำ |
|-----------|---------|--------|
| `Wire.mqh` | socket connect/reconnect, JSON-lines framing, send queue พร้อม drop-oldest | ห้าม block ใน `OnTick` เกิน 50ms |
| `LocalRiskGuard.mqh` | hard limits ทั้งหมดจาก [03-risk-spec](03-risk-spec.md) §L1 | ห้ามอ่านค่า limit จาก brain — ต้องมาจาก EA input เท่านั้น |
| `OrderRouter.mqh` | reconcile target vs actual, ส่ง delta, slippage cap, retry with backoff | ห้ามส่ง order ถ้า `LocalRiskGuard::IsHalted()` |
| `StateReporter.mqh` | push bar close / equity / positions / heartbeat | ห้าม push ทุก tick (throttle) |
| `SafeMode.mqh` | brain หาย → `HOLD` (ปิด new entry, คง SL/TP) หรือ `FLATTEN` | default = `HOLD` |
| `FarmExecutor.mq5` | orchestrate ทั้งหมด, EA inputs, `OnInit/OnTick/OnTimer/OnDeinit` | ห้ามมี trading logic เอง |

**หลักสำคัญ:** EA คือ *ท่อ + ยาม* ไม่ใช่นักคิด — logic การเทรดอยู่ Python 100%
ยกเว้น fallback rule ขั้นต่ำใน SafeMode

### CONTROL PLANE — `brain/`

| Service | Input | Output | Note |
|---------|-------|--------|------|
| `gateway` | TCP จาก EA | route ไป service, persist ลง DB | asyncio, 1 task/session |
| `signal` | bar + features | `Intent` (target position + confidence) | ONNX runtime, ห้ามโหลด model ใน request path |
| `regime` | multi-TF features | `RegimeLabel` + `scale_factor` 0.0–1.0 | update ทุก bar close ของ TF หลัก |
| `news` | economic calendar + headlines | `NewsWindow` (block period) + `Bias` | LLM เรียกแบบ async, cache, มี fallback = block ตาม calendar เฉยๆ |
| `risk` | intents ทุก account + state | approved intents / directives | **มีอำนาจสุดท้าย** ห้าม bypass |
| `store` | ทุกอย่าง | Postgres + TimescaleDB | append-only สำหรับ audit trail |
| `collector` | MT5 read-only terminal | bar ทุก symbol ในจักรวาล | ★ ไม่ผูกบัญชี · ไม่มีสิทธิ์เทรด · ถ้าตาย = regime/correlation ใช้ค่าเก่า → P10 stale guard ต้อง reject |
| `watchdog` | liveness file ของ brain | Telegram alert + restart | ★ process แยก **ห้ามแชร์ dependency กับ brain** (ไม่ใช้ DB, ไม่ import brain) |

### ทำไมต้องมี `collector` แยก — ช่องว่างที่เจอตอน audit

EA ส่ง `BAR` มาแค่ symbol ที่ตัวเองเทรด แต่:
- **P4 correlation cap** ต้องมีราคาของ **ทุก** symbol ในจักรวาล เพื่อคำนวณ correlation matrix
- **RegimeService** ต้องดูภาพรวมตลาด (DXY, ทองคำ, correlation ระหว่างคู่) ไม่ใช่แค่คู่ที่เทรด
- ถ้าฟาร์มเทรดแค่ EURUSD วันนี้ brain จะไม่มีข้อมูล GBPUSD เลย → correlation คำนวณไม่ได้

→ ต้องมี MT5 terminal 1 ตัวที่ **ไม่ผูกกับบัญชีเทรด** ทำหน้าที่ป้อนข้อมูลอย่างเดียว
ใช้ `MetaTrader5` python package ดึง bar ทุก symbol แล้ว push เข้า brain ผ่าน internal API
(ไม่ใช่ผ่าน wire protocol — collector เป็น process ใน control plane ไม่ใช่ execution plane)

**ถ้า collector ตาย:** regime/correlation ใช้ข้อมูลเก่า → P10 `stale_data_guard` ต้อง reject
intent ที่พึ่ง feature เก่ากว่า 2 bar **ห้าม fail-open** (ห้ามแปลว่า "ไม่มีข้อมูล = correlation 0")

### ทำไม `watchdog` ห้ามแชร์ dependency กับ brain

Alerting ทั้งหมดอยู่ **ใน** brain ถ้า brain ตาย (OOM, unhandled exception, VPS reboot)
จะไม่มีใครส่ง Telegram บอก — เงียบไปเลย ซึ่งเป็น failure mode ที่แย่ที่สุด
เพราะเจ้าของนอนหลับสบายคิดว่าทุกอย่างปกติ

watchdog จึงต้อง:
- เป็น process แยก แค่ไม่กี่สิบบรรทัด
- **ไม่ import โค้ด brain · ไม่ต่อ DB · ไม่ใช้ virtualenv เดียวกัน** (dependency ร่วม = ตายพร้อมกัน)
- อ่าน liveness file (brain เขียน timestamp ทุก 5s) เงียบ > 60s = alert + restart service
- ตัวมันเองเป็น Windows service ที่ auto-restart

### RESEARCH PLANE — `research/`

| Module | หน้าที่ |
|--------|---------|
| `ingest` | ดึง historical bar/tick จาก MT5 (`MetaTrader5` python pkg), economic calendar → Parquet |
| `features` | feature engineering แบบ **point-in-time correct** (ห้าม look-ahead) |
| `backtest` | event-driven engine, จำลอง spread/slippage/commission/swap ตามจริงของโบรกเกอร์ |
| `optimizer` | walk-forward: train window → validate → OOS test, กัน overfit |
| `registry` | เก็บ artifact + metadata (data range, feature hash, metrics, git sha) |

---

## Tech Stack (ตัดสินแล้ว — Codex ไม่ต้องเลือกเอง)

| ชั้น | เลือก | เหตุผล |
|-----|-------|--------|
| EA | MQL5 (MT5 build ≥ 3800) | native socket, ไม่ต้อง DLL |
| Brain | Python 3.12 + asyncio | MT5 python pkg, ML ecosystem |
| Wire format | JSON-lines over TCP | debug ง่ายด้วยตาเปล่า, MQL5 parse ได้ |
| Schema | JSON Schema → codegen ทั้ง 2 ฝั่ง | กัน drift |
| Validation (Py) | pydantic v2 | |
| DB | PostgreSQL 16 + TimescaleDB | time-series + relational ในตัวเดียว |
| Data lake | Parquet + pyarrow | |
| ML | LightGBM (baseline) → ONNX export | เร็ว, tabular ดี, inference ไม่ต้องพึ่ง Python framework |
| Regime | hmmlearn / KMeans on vol-trend features | ตีความได้ |
| LLM | Claude API (`claude-sonnet-5`) | news/sentiment; ต้องมี fallback เมื่อ API ล่ม |
| Dashboard | FastAPI + HTMX + Chart.js | เบา ไม่ต้องมี frontend build |
| Alert | Telegram Bot API | |
| Process mgr | NSSM (Windows service) | brain + gateway ต้อง auto-restart |
| Test | pytest (Python), MT5 Strategy Tester + unit harness (MQL5) | |
| CI | GitHub Actions: lint, test, schema-codegen-diff check | |

**ไม่ใช้:** Docker บน execution plane (MT5 ต้อง Windows native), ไม่ใช้ Kafka/RabbitMQ
(overkill สำหรับ N ≤ 20 terminal), ไม่ใช้ deep learning ใน Phase 1–5

---

## Failure Mode ที่ต้องออกแบบรับตั้งแต่วันแรก

| เหตุการณ์ | พฤติกรรมที่ต้องการ | ใครรับผิดชอบ |
|-----------|-------------------|--------------|
| Brain ตาย / socket หลุด | EA เข้า SafeMode ใน ≤ 10s, ไม่เปิดใหม่, คง SL/TP | EA |
| EA ตาย / terminal ปิด | brain ตรวจ heartbeat หาย → alert ทันที, mark session dead | Brain |
| Order reject / requote | retry ≤ 3 ครั้ง backoff, เกินนั้น log + alert + ไม่ retry ต่อ | EA |
| Position ไม่ตรงกับ target หลัง restart | reconcile ครั้งแรกใน `OnInit` ก่อนรับ intent ใหม่ | EA |
| Broker spread พุ่ง / gap | LocalRiskGuard block new entry เมื่อ spread > cap | EA |
| Daily loss ทะลุ | EA halt account นั้น + brain halt ทั้งฟาร์มถ้ารวมทะลุ | ทั้งคู่ |
| Model ให้ค่าเพี้ยน (NaN/inf/นอกช่วง) | risk manager reject intent + alert + fallback ไป champion เดิม | Brain |
| LLM API ล่ม / ตอบขยะ | fallback = block ตาม economic calendar อย่างเดียว | Brain |
| Clock drift ระหว่าง VPS กับ broker | ใช้ server time จาก MT5 เป็นหลักเสมอ, ห้ามใช้ local time ตัดสิน | ทั้งคู่ |
| DB เต็ม / เขียนไม่ได้ | brain ต้องไม่หยุดเทรด — buffer ใน memory + alert | Brain |
| **★ VPS ตายทั้งเครื่อง / ไฟดับ / โดนโบรกเกอร์ตัด** | **SL/TP ที่ฝากไว้ที่ broker คือด่านสุดท้าย** — position ถูกปิดเองแม้ไม่มีอะไรรันอยู่ | Broker (ดูกฎด้านล่าง) |
| **Brain ตายแบบเงียบ** (alerting อยู่ใน brain) | watchdog process แยกตรวจ liveness file → Telegram + restart | Watchdog |
| **Collector ตาย** | regime/correlation stale → P10 reject intent ที่พึ่ง feature เก่า > 2 bar | Brain |
| Foreign position โผล่บนบัญชีฟาร์ม | R19 alert (ไม่ block) — อาจเป็นเทรดมือทับ หรือ magic ชนกัน | EA |

### ★ กฎ: SL/TP ต้องอยู่ที่ broker เสมอ ห้าม EA จำลองเอง

กฎนี้เคยเป็นแค่นัยใน R9 — เขียนให้ชัดเพราะเป็นด่านสุดท้ายจริง:

> ทุก position ต้องมี `sl` ที่ฝากไว้ **ฝั่ง broker** (field `POSITION_SL`)
> **ห้าม** ใช้วิธี "EA เฝ้าราคาแล้วปิดเองเมื่อถึงจุด" (virtual/hidden SL) เด็ดขาด

เหตุผล: virtual SL ทำงานได้เฉพาะเมื่อ EA ยังรันอยู่ ถ้า VPS ดับ / MT5 crash /
เน็ตหลุดยาว position จะไม่มีอะไรปิดเลย — ขาดทุนได้ไม่จำกัดจนโดน margin call

ผลตามมา: SL ต้องตั้งพร้อมกับ order เปิด (`ORDER_TYPE_BUY` + `sl` ในคำสั่งเดียว)
ไม่ใช่เปิดแล้วค่อยตั้งตามหลัง — ถ้าเปิดสำเร็จแต่ตั้ง SL ไม่สำเร็จจะมีช่องเปลือย
ถ้าโบรกเกอร์ไม่ยอมรับ SL ในคำสั่งเปิด (บาง ECN) → ตั้งทันทีในขั้นถัดไปและ
**ถ้าตั้งไม่ได้ภายใน 3 ครั้ง ให้ปิด position นั้นทิ้ง** ไม่ใช่ปล่อยเปลือยไว้
