# 04 — Roadmap

**หลักการเรียงลำดับ:** ต่อท่อให้แน่น → กันตาย → แล้วค่อยฉลาด
ห้ามข้ามไป Phase 4+ ก่อน Phase 2 ผ่าน exit criteria ครบ

ประมาณเวลา = สมมติทำ part-time (~15 ชม./สัปดาห์) + Codex เขียนโค้ด
ตัวเลขนี้เอาไว้เรียงลำดับ ไม่ใช่สัญญา

---

## Phase 0 — Foundations · ~1 สัปดาห์

**เป้า:** มี repo, contract, และ data ที่เชื่อถือได้ ก่อนเขียน logic ใดๆ

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 0.1 | `git init`, layout, `.gitignore`, `.env.example` | Codex | repo structure ตาม README |
| 0.2 | เขียน `contracts/schema/*.json` ทุก message type | **Claude** | 10 schema files |
| 0.3 | Codegen: JSON Schema → pydantic + MQL5 struct | Codex | `make codegen` ทำงาน + round-trip test ผ่าน |
| 0.4 | Postgres + TimescaleDB ขึ้น (Docker Compose สำหรับ dev), migration | Codex | `make db-up`, alembic migration |
| 0.5 | Data ingest: ดึง M1/M5/H1 ย้อนหลัง 5 ปี ของ 8 คู่ → Parquet | Codex | `research/ingest/`, data quality report |
| 0.6 | Data quality gate: หา gap, spike, duplicate, weekend bar | Codex | report + fail ถ้าคุณภาพไม่ผ่าน |
| 0.7 | CI: ruff, mypy, pytest, codegen-diff check | Codex | GitHub Actions เขียว |

**Exit criteria**
- [ ] `make codegen && git diff --exit-code contracts/gen/` ผ่าน
- [ ] Round-trip test: python serialize → mql5 parse → mql5 serialize → python parse ตรงกันทุก message type
- [ ] Data ย้อนหลัง ≥ 5 ปี ครบ 8 คู่ ผ่าน quality gate (missing bar < 0.1%)
- [ ] CI เขียวบน `main`

---

## Phase 1 — Execution Plane + Gateway · ~2 สัปดาห์

**เป้า:** ท่อเชื่อมได้ ส่ง target-state แล้ว EA เทรดถูกบน **demo** ด้วยกลยุทธ์โง่ๆ

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 1.1 | `Wire.mqh` — socket, reconnect, JSON-lines, send queue | Codex | + unit test ใน MQL5 harness |
| 1.2 | `StateReporter.mqh` — HELLO/HEARTBEAT/BAR/STATE | Codex | |
| 1.3 | `OrderRouter.mqh` — target-state reconciler, dedupe, retry | Codex | ★ ตัวยากที่สุดใน phase นี้ |
| 1.4 | `FarmExecutor.mq5` — orchestrate + EA inputs | Codex | |
| 1.5 | Gateway: asyncio TCP server, auth, session registry, persist | Codex | |
| 1.6 | Strategy โง่ๆ: EMA(20/50) cross ไม่มี ML — ใช้พิสูจน์ท่อ | Codex | `brain/strategies/ema_baseline.py` |
| 1.7 | Chaos test harness: ตัดเน็ต, kill brain, restart EA, ส่ง intent ซ้ำ | Codex | `tests/chaos/` |
| 1.8 | Reconciliation: EA restart แล้ว sync position ให้ตรง | Codex | ★ ต้องทดสอบด้วยมือด้วย |

**Exit criteria**
- [ ] รัน 5 วันทำการติดกันบน demo 1 บัญชี ไม่มี order ผิด ไม่มี position ค้าง
- [ ] Chaos test ผ่านทุกเคส: ส่ง intent เดียวกัน 100 ครั้ง → มี 1 order · kill brain กลางทาง → EA SafeMode ใน ≤ 10s · restart EA ตอนถือ position → reconcile ถูก
- [ ] `intents` + `exec_reports` ใน DB ตรงกับ history ใน MT5 100% (มี script ตรวจสอบ)
- [ ] Latency p95 (intent ออกจาก brain → order filled) < 500ms

---

## Phase 2 — Risk Layer · ~2 สัปดาห์  ★ สำคัญที่สุด

**เป้า:** พอร์ตปลอดภัยแม้ทุกอย่างพัง

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 2.1 | `LocalRiskGuard.mqh` — R1–R17 ครบทุกข้อ | Codex | ★ ทุกข้อต้องมี test |
| 2.2 | Lot sizing + currency conversion (XAUUSD/USDJPY/EURGBP) | Codex | unit test 3 เคสขั้นต่ำ |
| 2.3 | HWM + halt state persistence ข้าม restart | Codex | |
| 2.4 | `SafeMode.mqh` + kill file | Codex | |
| 2.5 | `brain/risk/` — P1–P11, currency decomposition, correlation | Codex | |
| 2.6 | `RISK_DIRECTIVE` end-to-end | Codex | |
| 2.7 | Ops dashboard v1 + **kill switch** | Codex | ตาราง 1–6 ใน risk-spec |
| 2.8 | Telegram alerting: breach, disconnect, DD, order storm | Codex | |
| 2.9 | Risk test suite: จำลอง 20 สถานการณ์เลวร้าย | **Claude เขียน scenario, Codex implement** | `tests/risk_scenarios/` |

**Exit criteria**
- [ ] ทุกกฎ R1–R17 มี test และผ่าน
- [ ] ทุกกฎ P1–P11 มี test และผ่าน
- [ ] Manual test: กด kill switch → ทุกบัญชี flatten ใน ≤ 5s
- [ ] Manual test: สร้าง daily loss เกิน limit บน demo → HALT จริง และ restart EA แล้วยัง HALT
- [ ] รัน 3 บัญชี demo ขนาน 10 วันทำการ ไม่มีการละเมิด limit ใดๆ
- [ ] Claude review risk layer แล้วอนุมัติเป็นลายลักษณ์อักษรใน `docs/reviews/`

> **จุดตัดสินใจ:** ผ่าน Phase 2 = พร้อมขึ้น live ด้วยทุนเล็ก (≤10%) ด้วยกลยุทธ์ rule-based
> ทำแบบนี้จะได้ข้อมูล live จริงมาใช้ตอน Phase 3 และรู้ว่า infra ทนจริงไหม
> **แนะนำให้ทำ** — ดีกว่ารอ ML เสร็จแล้วขึ้น live ทั้งสองอย่างพร้อมกัน (debug แยกไม่ออก)

---

## Phase 3 — Research Pipeline + ML Signal v1 · ~3 สัปดาห์

**เป้า:** มี backtest ที่เชื่อได้ และ model แรกที่ผ่าน OOS

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 3.1 | Feature store: point-in-time correct, versioned, hashed | Codex | ★ ห้าม look-ahead |
| 3.2 | Backtest engine: event-driven, spread/slippage/commission/swap จริง | Codex | |
| 3.3 | Backtest ↔ live parity test: รัน strategy เดียวกันทั้ง 2 ทาง เทียบ signal | Codex | ★ ถ้าไม่ตรง = backtest เชื่อไม่ได้ |
| 3.4 | Label design (triple-barrier หรือ fixed-horizon) | **Claude ออกแบบ** | `docs/specs/SPEC-labels.md` |
| 3.5 | LightGBM baseline + ONNX export | Codex | |
| 3.6 | Walk-forward framework: purged CV + embargo กัน leakage | Codex | ★ |
| 3.7 | `brain/signal/` — ONNX inference service | Codex | p99 < 50ms |
| 3.8 | Model registry + promotion CLI | Codex | |

**Exit criteria**
- [ ] Backtest/live parity: signal ตรงกัน ≥ 99% บนข้อมูลชุดเดียวกัน
- [ ] Leakage test: shuffle label แล้ว Sharpe ต้องตกใกล้ 0 (ถ้ายังสูง = มี leak)
- [ ] Model แรกผ่านเกณฑ์ L3 promotion (OOS ≥ 6 เดือน, trades ≥ 100, Sharpe ≥ 0.8)
- [ ] Feature hash ของ live ตรงกับตอน train (มี assertion runtime)

> **คำเตือนตรงๆ:** ขั้นนี้มีโอกาสสูงที่ model แรกจะไม่ผ่านเกณฑ์ — **นั่นคือผลลัพธ์ที่ถูกต้อง**
> ไม่ใช่เหตุผลให้ลดเกณฑ์ลง ถ้าไม่ผ่าน ให้กลับไปทำ feature/label ใหม่
> ระบบยังทำเงินได้จาก rule-based strategy ใน Phase 2 อยู่ ไม่ต้องรีบ

---

## Phase 4 — Regime + News/LLM Filter · ~2 สัปดาห์

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 4.1 | Regime feature: realized vol, ADX, Hurst, correlation matrix | Codex | |
| 4.2 | Regime classifier (HMM หรือ KMeans) + label ที่ตีความได้ | Codex | |
| 4.3 | Regime → scale mapping + backtest เทียบมี/ไม่มี regime filter | Codex | ต้องพิสูจน์ว่าดีขึ้นจริง |
| 4.4 | Economic calendar ingest + block window | Codex | |
| 4.5 | `brain/news/` LLM sentiment (claude-sonnet-5) + cache + fallback | Codex | ★ ต้อง fail-closed |
| 4.6 | LLM output schema + validator (reject ถ้าไม่ตรง) | Codex | |
| 4.7 | Cost guard: จำกัดจำนวนเรียก LLM/วัน + budget alert | Codex | |

**Exit criteria**
- [ ] Regime filter ทำให้ backtest maxDD ลดลง ≥ 20% (ถ้าไม่ลด = ไม่คุ้ม อย่าใช้)
- [ ] LLM ล่ม → ระบบยังเทรดได้ด้วย calendar อย่างเดียว (test ด้วยการ block API)
- [ ] LLM ตอบขยะ → reject + log ไม่มีผลต่อ position
- [ ] `CRISIS` regime → REDUCE_ONLY อัตโนมัติ (test ด้วยข้อมูล COVID Mar 2020)

---

## Phase 5 — Auto-Optimization · ~2 สัปดาห์

| # | งาน | ผู้ทำ | Deliverable |
|---|-----|-------|-------------|
| 5.1 | Walk-forward orchestrator แบบตั้งเวลา (รายสัปดาห์) | Codex | |
| 5.2 | Parameter search (Optuna) + overfit penalty | Codex | |
| 5.3 | Champion/Challenger runner: challenger รัน micro lot ขนาน | Codex | |
| 5.4 | Degradation monitor (L3) → auto scale down | Codex | |
| 5.5 | Promotion gate: **ต้องมีมนุษย์อนุมัติ** ห้าม auto-promote | Codex | |
| 5.6 | Optimization report → dashboard | Codex | |

**Exit criteria**
- [ ] รัน walk-forward รายสัปดาห์อัตโนมัติ ไม่กระทบ execution (CPU isolation)
- [ ] Challenger promote ได้ผ่านการอนุมัติมือ + rollback ได้ใน 1 คำสั่ง
- [ ] Degradation จำลอง → auto scale down ทำงาน

---

## Phase 6 — Multi-Account Scale-Out · ~2 สัปดาห์

| # | งาน | ผู้ทำ |
|---|-----|-------|
| 6.1 | Account/strategy allocation config (declarative YAML) | Codex |
| 6.2 | Deploy automation: ติดตั้ง EA + config หลาย terminal ด้วยคำสั่งเดียว | Codex |
| 6.3 | NSSM service setup, auto-restart, log rotation | Codex |
| 6.4 | Multi-VPS: gateway ผ่าน VPN, TLS, session isolation | Codex |
| 6.5 | Backup/restore: DB, model artifact, config | Codex |
| 6.6 | Runbook: ทำอะไรเมื่ออะไรพัง | **Claude เขียน** |

**Exit criteria**
- [ ] 5+ terminal ต่อพร้อมกัน stable 10 วัน
- [ ] Terminal 1 ตัวตาย → ที่เหลือไม่กระทบ + alert ทันที
- [ ] Restore จาก backup สำเร็จบนเครื่องเปล่า

---

## Phase 7 — Live Ramp · ต่อเนื่อง

| ขั้น | ทุน | เงื่อนไขผ่าน |
|-----|-----|-------------|
| 7.1 | 10% | 30 วัน · live tracking error vs backtest < 30% · ไม่มี risk breach |
| 7.2 | 25% | 30 วันเพิ่ม · เงื่อนไขเดิม |
| 7.3 | 50% | 60 วันเพิ่ม |
| 7.4 | 100% | 90 วันเพิ่ม |

**กฎ ramp-down:** ถ้า live DD ถึง 60% ของ limit → ลดทุนกลับขั้นก่อนหน้า ไม่ต้องถาม

---

## สรุปเวลา

| Phase | เวลา | สะสม |
|-------|------|------|
| 0 Foundations | 1 สัปดาห์ | 1 |
| 1 Execution | 2 | 3 |
| 2 Risk ★ | 2 | 5 |
| 3 Research + ML | 3 | 8 |
| 4 Regime + News | 2 | 10 |
| 5 Auto-opt | 2 | 12 |
| 6 Scale-out | 2 | 14 |
| 7 Live ramp | 7 เดือน+ | — |

**~14 สัปดาห์ (3.5 เดือน) ถึงระบบครบ · แต่ขึ้น live ทุนเล็กได้ตั้งแต่สัปดาห์ที่ 5**
