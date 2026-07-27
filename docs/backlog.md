# Backlog — เรียงตามลำดับที่ต้องทำ

สถานะ: `TODO` · `SPEC_READY` (Claude เขียน spec เสร็จ Codex ทำได้) · `IN_PROGRESS` · `IN_REVIEW` · `DONE` · `BLOCKED`

---

## Phase 0 — Foundations

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-001 | MT5 Executor skeleton + Wire (socket, JSON-lines, reconnect) | Codex | — | **SPEC_READY** |
| SPEC-002 | Repo scaffold, `.gitignore`, `.env.example`, Makefile | Codex | — | TODO |
| SPEC-003 | `contracts/schema/*.json` ทุก message type | **Claude** | — | ✅ **DONE** — 13 schema + README · [handoff](reviews/SPEC-003-schema-handoff.md) |
| SPEC-004 | Codegen: schema → pydantic + MQL5 struct/serializer | Codex | 003 | **SPEC_READY** ← ปลดล็อกแล้ว |
| SPEC-005 | Round-trip test harness (py ↔ mql5) | Codex | 004 | TODO |
| SPEC-006 | Postgres + TimescaleDB, migration, repository layer | Codex | 003 | TODO |
| SPEC-007 | Data ingest: MT5 history → Parquet (**6 คู่ · M1 เท่านั้นแล้ว resample** · ~10 ปี) | Codex | 002 | TODO |
| SPEC-008 | Data quality gate (gap/spike/dup/weekend detection) | Codex | 007 | TODO |
| SPEC-009 | CI: ruff, mypy, pytest, codegen-diff | Codex | 004 | TODO |
| SPEC-063 | **BrokerTime module** — broker tz/DST เป็นแหล่งความจริงเดียว ห้ามคำนวณเวลาเอง (G6) | Codex | **001** (แก้จาก 002 — เป็น MQL5 ล้วน ไม่ต้องรอ scaffold) | **SPEC_READY** — [spec](specs/SPEC-063-broker-time.md) |
| SPEC-064 | **SymbolRegistry** — `(broker, raw)` → canonical + base/quote currency (G7) | Codex | 006 | TODO |
| SPEC-065 | **MQL5 test harness** — test ต้องเป็น **EA ไม่ใช่ Script** (`OnInit`+`ExpertRemove`) เพราะ Script รัน headless ไม่ได้ · เขียนผลเป็น JSON + git sha ให้ CI ตรวจได้ (G9, [07](07-compile-gate.md)) | Codex | 001 | TODO |

## Phase 1 — Execution Plane

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-010 | `StateReporter.mqh` — HELLO/HEARTBEAT/BAR/STATE + backfill 300 bar | Codex | 001,004 | TODO |
| SPEC-011 | `OrderRouter.mqh` — target-state reconciler (hedging) ★ ยากสุด | Codex | 010 | **SPEC_READY** |
| SPEC-012 | Intent dedupe cache + expiry handling | Codex | 011 | TODO |
| SPEC-013 | Gateway: asyncio TCP server, auth, session registry | Codex | 006 | TODO |
| SPEC-014 | Persist intents/exec_reports/account_state | Codex | 013 | TODO |
| SPEC-015 | EMA baseline strategy (พิสูจน์ท่อ ไม่ใช่ทำเงิน) | Codex | 013 | TODO |
| SPEC-016 | Chaos test harness (kill brain, cut net, restart EA, dup intent) | Codex | 011,013 | TODO |
| SPEC-017 | Position reconciliation ตอน `OnInit` | Codex | 011 | TODO |
| SPEC-018 | DB ↔ MT5 history consistency checker | Codex | 014 | TODO |

## Phase 2 — Risk Layer ★

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-019 | `LocalRiskGuard.mqh` R1–R5, R9–R12, R15, R17 | Codex | 011 | TODO |
| SPEC-020 | Lot sizing + currency conversion (XAUUSD/USDJPY/EURGBP) | Codex | 019 | TODO |
| SPEC-021 | R6 daily loss + R7 max DD + HWM persistence | Codex | 019 | TODO |
| SPEC-022 | R8 margin level + R14 consecutive loss + halt persistence | Codex | 021 | TODO |
| SPEC-023 | `SafeMode.mqh` + R13 kill file + R16 brain timeout | Codex | 019 | TODO |
| SPEC-060 | **MarketDataCollector** — MT5 read-only ป้อน bar ทุก symbol (G1) | Codex | 006 | TODO |
| SPEC-061 | **P10 stale-data guard ให้ fail-closed** — collector ตาย = reject ไม่ใช่ correlation 0 (G1) | Codex | 060 | TODO |
| SPEC-024 | Currency exposure decomposition (P3) | Codex | 014, 064 | TODO |
| SPEC-025 | `brain/risk/` P1,P2,P5,P6,P9,P10,P11 | Codex | 024 | TODO |
| SPEC-026 | Correlation engine + P4 correlated risk cap | Codex | 024, 060 | TODO |
| SPEC-027 | `RISK_DIRECTIVE` end-to-end + mode precedence test | Codex | 025 | TODO |
| SPEC-028 | Ops dashboard v1 + **kill switch** | Codex | 025 | TODO |
| SPEC-029 | Telegram alerting | Codex | 025 | TODO |
| SPEC-030 | Risk scenario suite (20 สถานการณ์เลวร้าย) | **Claude ออกแบบ** / Codex code | 019–027 | TODO |
| SPEC-030b | **Runbook ขั้นต้น** — ย้ายมาจาก Phase 6 เพราะเงินจริงเริ่มปลาย Phase 2 (G4) | **Claude** | 028 | TODO |
| SPEC-062 | **Watchdog** — process แยกเฝ้า brain ห้ามแชร์ dependency (G2) | Codex | 029 | TODO |

## Phase 3 — Research + ML

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-031 | Feature store (point-in-time, versioned, hashed) | Codex | 008 | TODO |
| SPEC-032 | Backtest engine (event-driven, spread/slip/comm/swap) | Codex | 031 | TODO |
| SPEC-033 | Backtest ↔ live parity test | Codex | 032,015 | TODO |
| SPEC-034 | Label design (triple-barrier) | **Claude** | 031 | TODO |
| SPEC-035 | LightGBM baseline + ONNX export | Codex | 034 | TODO |
| SPEC-036 | Walk-forward + purged CV + embargo | Codex | 035 | TODO |
| SPEC-037 | Leakage test suite (shuffled label sanity) | Codex | 036 | TODO |
| SPEC-038 | `brain/signal/` ONNX inference service | Codex | 035 | TODO |
| SPEC-039 | Model registry + promotion CLI | Codex | 036 | TODO |

## Phase 4 — Regime + News

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-040 | Regime features (realized vol, ADX, Hurst, corr matrix) | Codex | 031 | TODO |
| SPEC-041 | Regime classifier + interpretable labels | Codex | 040 | TODO |
| SPEC-042 | Regime → scale mapping + A/B backtest proof | Codex | 041,032 | TODO |
| SPEC-043 | Economic calendar ingest + block windows | Codex | 006 | TODO |
| SPEC-044 | `brain/news/` LLM sentiment + schema validator + fail-closed | Codex | 043 | TODO |
| SPEC-045 | LLM cost guard + budget alert | Codex | 044 | TODO |

## Phase 5 — Auto-Optimization

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-046 | Walk-forward orchestrator (scheduled, CPU-isolated) | Codex | 036 | TODO |
| SPEC-047 | Optuna param search + overfit penalty | Codex | 046 | TODO |
| SPEC-048 | Champion/Challenger runner (micro lot parallel) | Codex | 039 | TODO |
| SPEC-049 | Degradation monitor (L3) → auto scale down | Codex | 048 | TODO |
| SPEC-050 | Promotion gate (manual approval) + 1-command rollback | Codex | 048 | TODO |

## Phase 6 — Scale-Out

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-051 | Allocation config (declarative YAML) | Codex | 025 | TODO |
| SPEC-052 | Multi-terminal deploy automation | Codex | 051 | TODO |
| SPEC-053 | NSSM services, auto-restart, log rotation | Codex | 052 | TODO |
| SPEC-054 | Multi-VPS: VPN, TLS, session isolation | Codex | 053 | TODO |
| SPEC-055 | Backup/restore (DB, artifacts, config) | Codex | 053 | TODO |
| SPEC-056 | Runbook | **Claude** | 053 | TODO |

## Phase 7 — Live Ramp

| ID | งาน | ผู้ทำ | สถานะ |
|----|-----|-------|-------|
| SPEC-057 | Live readiness audit (full risk review) | **Claude** | TODO |
| SPEC-058 | Live tracking-error monitor vs backtest | Codex | TODO |
| SPEC-059 | Capital ramp automation + ramp-down trigger | Codex | TODO |

---

## หนี้เทคนิค / ค้างคาใจ

| # | เรื่อง | สถานะ | บันทึกเมื่อ |
|---|-------|-------|------------|
| ~~D1~~ | ~~Path โปรเจกต์มีอักษรไทย + เว้นวรรค — MQL5 compiler, venv, git บน Windows มีปัญหา encoding~~ | ✅ **แก้แล้ว** — ย้าย repo มา `D:\ea-farm` + `git init -b main` + `.gitattributes` บังคับ LF | 2026-07-26 |
| ~~D2~~ | ~~โบรกเกอร์/สเปก VPS — กระทบ spread model ใน backtest (SPEC-032)~~ | ✅ **ยืนยันแล้ว: IUX Markets** → [ADR-002](decisions/ADR-002-symbols-capital-hours.md) · history M1 ลึกกว่าที่เคยบันทึก (EURUSD/XAUUSD 2016–2026 · BTCUSD 2018–2026) — ข้อกำหนด ≥5 ปี ผ่านครบ · **ยังไม่รู้สเปก VPS** | 2026-07-27 |
| ~~D3~~ | ~~netting หรือ hedging account — กระทบ `OrderRouter` logic โดยตรง~~ | ✅ **ตัดสินแล้ว: hedging** → [ADR-001](decisions/ADR-001-hedging-account.md) · SPEC-011 เขียนครบแล้ว | 2026-07-26 |
| D4 | ชุด symbol และ timeframe หลัก | 🟡 **6 คู่** → [ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.3 · `EURUSD` `USDJPY` `GBPUSD` `AUDUSD` `USDCAD` `XAUUSD` × M1/M5/M10/M15/M30/H1/H4 · ingest ดึง **M1 อย่างเดียวแล้ว resample** · 🔴 **`USDCNY.iux` ไม่มีในโบรกเกอร์** → เลือก `USDCNH` หรือตัดทิ้ง · `XAGUSD` ตัดออกแล้ว | 2026-07-27 |
| **D5** | ทุนต่อบัญชี — กระทบ P1–P6 threshold | 🔴 **BLOCKER** — บัญชี ≥2 ✅ แต่ทุน **$10 ทำให้ R1 reject ทุก intent ทั้ง 6 คู่** (คำนวณใน [ADR-002](decisions/ADR-002-symbols-capital-hours.md) §3) · ตัด XAGUSD แล้วเพดานลงเหลือ **XAUUSD ~$1,430 แต่ยังห่าง 143 เท่า** · ต้องเลือกเพิ่ม **A** บัญชี cent · **B** เพิ่มทุน · **C** demo อย่างเดียว — **บล็อก SPEC-020 + SPEC-025** | 2026-07-27 |
| ~~D6~~ | ~~BTCUSD.iux เปิดเสาร์-อาทิตย์ไหม~~ | ✅ **ปิด — ไม่เกี่ยวแล้ว** ตัด BTCUSD ออกจากชุด symbol (rev.2) ทั้ง 6 คู่ปิดสุดสัปดาห์ กฎ weekend bar เดียวใช้ได้ทุกตัว | 2026-07-27 |
| **D7** | สเปก VPS (CPU/RAM/latency ไป IUX) | ⏳ กระทบ SPEC-032 spread model + Phase 6 | 2026-07-27 |
| ~~D8~~ | ~~contract size ของ `XAGUSD.iux`~~ | ✅ **ปิด — ไม่เกี่ยวแล้ว** ตัด XAGUSD ออกจากชุด symbol (rev.3) | 2026-07-27 |

---

## Environment (ยืนยันแล้ว 2026-07-26)

| หัวข้อ | ค่า |
|--------|-----|
| Repo path | `D:\ea-farm` (ASCII เท่านั้น — ห้ามย้ายกลับไป path ที่มีอักษรไทย/เว้นวรรค) |
| Git | 2.51.1.windows.1 · branch หลัก `main` |
| Line ending | LF บังคับผ่าน `.gitattributes` (ยกเว้น `.bat/.cmd/.ps1`) |
| Remote | ยังไม่มี — local only |
| **โบรกเกอร์** | **IUX Markets** · บัญชี `IUXMarkets-Demo` · hedging mode ([ADR-001](decisions/ADR-001-hedging-account.md)) |
| **Terminal** | `IUX Markets MT5 Terminal3` เท่านั้น — `C:\Program Files\MetaTrader 5` ไม่มีบัญชี/history รัน tester ไม่ได้ |
| **Symbol** | **6 คู่** `EURUSD` · `USDJPY` · `GBPUSD` · `AUDUSD` · `USDCAD` · `XAUUSD` (suffix `.iux` บังคับ) · `USDCNY` ไม่มีในโบรกเกอร์ · `XAGUSD` ตัดออก |
| **Timeframe** | M1 · M5 · M10 · M15 · M30 · H1 · H4 — MT5 เก็บแค่ M1 ที่เหลือ derive |
| **M1 history** | EURUSD/XAUUSD 2016–2026 · อื่นๆ มีแล้ว · **`USDJPY` ยังไม่ได้ดาวน์โหลด** (มี tick ไม่มี bar) |
| **บัญชี** | ≥ 2 บัญชี · ทุนต่อบัญชี = 🔴 **ยังไม่สรุป** ดู D5 |
