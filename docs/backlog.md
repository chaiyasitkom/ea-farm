# Backlog — เรียงตามลำดับที่ต้องทำ

สถานะ: `TODO` · `SPEC_READY` (Claude เขียน spec เสร็จ Codex ทำได้) · `IN_PROGRESS` · `IN_REVIEW` · `DONE` · `BLOCKED`

---

## Phase 0 — Foundations

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-001 | MT5 Executor skeleton + Wire (socket, JSON-lines, reconnect) | Codex | — | 🔨 **IN_REVIEW** (2026-07-31) — ฟังก์ชันครบ · gate เขียว: **TestWire 53/53** · `Pump()` p99 **16,576 µs** (เกณฑ์ < 20,000) · §1.6 partial-send ปิดแล้ว · **เหลือ 4 ข้อ:** soak 24 ชม. 🔴 · slow gate `..._over_1h` 🔴 · N1 (assertion เป็น dead code) 🟠 · W2 (`echo_server` นับ TCP ขยะ) 🟠 — [review chaos 03](reviews/SPEC-016-chaos-03.md) |
| SPEC-002 | Repo scaffold, `.env.example`, **`tools/task.py`** (ไม่ใช่ Makefile — เครื่องนี้ไม่มี `make`) + local gate `check` | Codex | — | ✅ **DONE** (2026-08-02) — `check: OK 4/4` เชื่อได้จริง · G1 (interpreter คนละตัว) + G2 (.venv version) ปิด · [review](reviews/SPEC-002-scaffold-02.md) |
| SPEC-003 | `contracts/schema/*.json` ทุก message type | **Claude** | — | ✅ **DONE** — 13 schema + README · [handoff](reviews/SPEC-003-schema-handoff.md) |
| SPEC-004 | Codegen: schema → pydantic + MQL5 struct/serializer | Codex | 003 | ✅ **DONE** (2026-08-02) — codegen 2 ฝั่ง deterministic · `codegen-check` บังคับโดย gate · `JsonCore.mqh` recursive-descent parser · TestFarmMessages 12/12 · rev.2a/2b/2c แก้ 10 จุดที่กำกวม |
| SPEC-005 | Round-trip test harness (py ↔ mql5) | Codex | **002**, 004 | ✅ **DONE** (2026-08-02) — **round-trip py↔mql5 17/17 รันของจริงทั้งสองฝั่ง ไม่มี mock** = **exit criteria Phase 0** · ใช้ 7 รอบ ไม่มีรอบไหนเป็นบั๊ก round-trip เอง ดู [08 §1.7](08-status-and-plan.md) |
| SPEC-006 | **PostgreSQL** + migration + repository layer (เลื่อน TimescaleDB — [§3.1](specs/SPEC-006-database.md)) | Codex | **002**, 004 | **SPEC_READY** — [spec](specs/SPEC-006-database.md) |
| SPEC-007 | Data ingest: MT5 history → Parquet (**6 คู่ · M1 เท่านั้นแล้ว resample** · ~10 ปี) | Codex | 002, **064** | **SPEC_READY** — [spec](specs/SPEC-007-data-ingest.md) |
| SPEC-008 | Data quality gate (gap/spike/dup/weekend detection) | Codex | 007 | ✅ **DONE** (2026-08-02) — 22 test · ข้อมูลทดสอบใช้ราคาจริง · แยก "symbol ไม่มีข้อมูล" ออกจาก "gate ไม่มีอะไรให้ตรวจ" |
| SPEC-009 | **CI: ปิด G3 ด้วย attestation** — `pre-push` hook + `mql5-attest` + workflow ที่รอ remote | Codex | 002, **065** | **SPEC_READY** — [spec](specs/SPEC-009-ci.md) |
| SPEC-063 | **BrokerTime module** — broker tz/DST เป็นแหล่งความจริงเดียว ห้ามคำนวณเวลาเอง (G6) | Codex | **001** (แก้จาก 002 — เป็น MQL5 ล้วน ไม่ต้องรอ scaffold) | ✅ **APPROVED_WITH_NOTES** (รอบ 4 · 2026-07-31) — [review](reviews/SPEC-063-04.md) · gate เขียว: compile 0/0 · **TestBrokerTime 67/67** (`ran_names` 21 ชื่อ) · `git_sha` ตรงจริง commit `294da01` · ค้าง 2 ข้อภาคสนาม (§6.5 ตลาดปิด · §9 Q2 drift) ที่ต้องรอ **W1** + สุดสัปดาห์ |
| SPEC-064 | **SymbolRegistry** — `(broker, raw)` → canonical + base/quote + risk profile ต่อ symbol (G7) · 🔴 ขาดไม่ได้หลังเพิ่ม XM: `GOLD` → `XAUUSD` เดาด้วย string rule ไม่ได้ ([ADR-003](decisions/ADR-003-multi-broker.md)) | Codex | **004** (แก้จาก 006 — เป็นไฟล์ในรีโป ไม่ใช่ตาราง DB) | ✅ **DONE** (2026-08-02) — `GOLD`→`XAUUSD` ทั้งสองฝั่ง · fail-closed ไม่คืน raw · TestFarmSymbols 11/11 · ปิด G7 |
| SPEC-065 | **MQL5 test harness** — ส่วนใหญ่ทำแล้ว · เหลือ manifest หลาย suite + attestation ให้ CI (G9, [07](07-compile-gate.md)) | Codex | 001 | **SPEC_READY** — [spec](specs/SPEC-065-mql5-test-harness.md) |
| SPEC-066 | **กริ่ง handoff ผ่าน git hook** — ของชั่วคราวก่อน SPEC-029 · ~40 บรรทัด ใช้ได้วันนี้ · **ลบทิ้งเมื่อ SPEC-029 §4.2.1 ขึ้น** | Codex | — | **SPEC_READY** — [spec](specs/SPEC-066-handoff-doorbell-hook.md) |
| SPEC-067 | **Memory / handle soak harness** — ปิดครึ่งที่ยังไม่มีของของ `SPEC-001:160` (*"ไม่ memory leak"*) · sampler + เกณฑ์ตัดสิน**ด้วยความชัน ไม่ใช่ค่าสูงสุด** · 2 profile: `steady` 24 ชม. · **`churn` 2 ชม. (~240 reconnect — จับ handle leak ได้ดีกว่า steady ที่ใช้เวลา 12 เท่า)** | Codex | **001 §S1** ([review](reviews/SPEC-001-soak-01.md)) · 016 | **SPEC_READY** — [spec](specs/SPEC-067-memory-soak.md) · ⚠️ ห้ามเริ่ม `steady` ก่อน S1 merge |

## Phase 1 — Execution Plane

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-010 | `StateReporter.mqh` — HELLO/HEARTBEAT/BAR/STATE + backfill 300 bar | Codex | 001, 004, **063** (เพิ่ม — `bar_time` เป็นส่วนของ PK ถ้าเวลาผิดต้อง migrate ทั้งตาราง) | **SPEC_READY** — [spec](specs/SPEC-010-state-reporter.md) |
| SPEC-011 | `OrderRouter.mqh` — target-state reconciler (hedging) ★ ยากสุด | Codex | 010 ← **ปลดล็อกแล้ว** | **SPEC_READY** (ยังต้องรอ 010 เสร็จ + `test_partial_send_resumes` ด้วย socket จริง) |
| SPEC-012 | Intent dedupe cache + expiry handling | Codex | 011, **063** | **SPEC_READY** — [spec](specs/SPEC-012-intent-cache.md) |
| SPEC-013 | Gateway: asyncio TCP server, auth, session registry ★ **คอขวดของ Phase 1** | Codex | 002, 004, 006, **064** | **SPEC_READY** — [spec](specs/SPEC-013-gateway.md) |
| SPEC-014 | Persist intents/exec_reports/account_state/bars | Codex | **006**, 013 | **SPEC_READY** — [spec](specs/SPEC-014-persistence.md) |
| SPEC-015 | EMA baseline strategy (พิสูจน์ท่อ ไม่ใช่ทำเงิน) | Codex | 013, **014**, **064** | **SPEC_READY** — [spec](specs/SPEC-015-ema-baseline.md) |
| SPEC-016 | Chaos test harness + scenario — **ชั้น A (wire) ต้องการแค่ 001** · ชั้น B (intent) ต้องการ 011+013 | Codex | **001** (A) · 011,013 (B) | ✅ **ชั้น A APPROVED_WITH_NOTES** (2026-07-31) — `CHAOS GATE: PASSED` 5 ผ่าน 1 skip (soak) · backoff พิสูจน์ครบ**ถึง cap 30s** · **W1 ปิด: `SocketRead` ขอ 4096 byte เสมอ → บล็อก `Pump()` 29 วินาที** ([review](reviews/SPEC-016-chaos-03.md)) · ค้าง N1 🟠 · **ชั้น B ยังไม่เริ่ม** รอ 011+013 — [spec](specs/SPEC-016-chaos-harness.md) |
| SPEC-017 | Position reconciliation ตอน `OnInit` | Codex | **010**, 011, **063** | **SPEC_READY** — [spec](specs/SPEC-017-reconciliation.md) |
| SPEC-018 | DB ↔ MT5 history consistency checker | Codex | 014, **064** | **SPEC_READY** — [spec](specs/SPEC-018-consistency-checker.md) |

## Phase 2 — Risk Layer ★

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-019 | **LocalRiskGuard กรอบ + R2·R3·R4·R5·R9·R10·R11·R12·R15·R17** (R1 อยู่ที่ 020) | Codex | 011, 012, 063, 064 | **SPEC_READY** — [spec](specs/SPEC-019-local-risk-guard.md) |
| SPEC-020 | **R1 Lot sizing + currency conversion** (USDJPY/USDCAD/XAUUSD) + แก้ bug ลำดับ clamp | Codex | 019, 064 | **SPEC_READY** — [spec](specs/SPEC-020-lot-sizing.md) |
| SPEC-021 | R6 daily loss + R7 max DD + HWM persistence | Codex | 019, **063** | **SPEC_READY** — [spec](specs/SPEC-021-drawdown-guard.md) |
| SPEC-022 | R8 margin level + R14 consecutive loss + halt persistence | Codex | 019, 021, **063** | **SPEC_READY** — [spec](specs/SPEC-022-margin-and-loss-streak.md) |
| SPEC-023 | `SafeMode.mqh` + R13 kill file + R16 brain timeout | Codex | 019, **063** | **SPEC_READY** — [spec](specs/SPEC-023-safemode.md) |
| SPEC-060 | **MarketDataCollector** — MT5 read-only ป้อน quote+bar ทุก symbol (G1) | Codex | 006, **013**, **064** | **SPEC_READY** — [spec](specs/SPEC-060-market-data-collector.md) |
| SPEC-061 | **P10 stale-data guard ให้ fail-closed** — collector ตาย = reject ไม่ใช่ correlation 0 (G1) | Codex | 060 | **SPEC_READY** — [spec](specs/SPEC-061-stale-data-guard.md) |
| SPEC-027 | **`RISK_DIRECTIVE` end-to-end + mode precedence** — ★ **กลับด้าน dependency: ไม่ขึ้นกับ 025 แล้ว** ท่อ+กฎ precedence แยกจากคนตัดสิน → **หลุดจากเงา D9/D10** | Codex | **013, 019, 023, 063** (แก้จาก 025) | **SPEC_READY** — [spec](specs/SPEC-027-risk-directive.md) |
| SPEC-028 | Ops dashboard v1 + **kill switch** — process แยกจาก brain · กดได้ตอน brain ตาย | Codex | 006, 014, **023** (แก้จาก 025) | **SPEC_READY** — [spec](specs/SPEC-028-dashboard-kill-switch.md) |
| SPEC-029 | Telegram alerting — outbox pattern · storm cap ห้ามกลืน BREACH | Codex | 006, 014 (แก้จาก 025) | **SPEC_READY** — [spec](specs/SPEC-029-telegram-alerting.md) · 🔑 ต้องมี bot token ตอนรัน test ชั้น live |
| SPEC-062 | **Watchdog** — process แยกเฝ้า brain ห้ามแชร์ dependency (G2) · stdlib ล้วน | Codex | 028, 029 | **SPEC_READY** — [spec](specs/SPEC-062-watchdog.md) |
| SPEC-024 | Currency exposure decomposition (P3) — **risk-normalized** ([ADR-004](decisions/ADR-004-exposure-unit.md)) | Codex | **060, 061, 064, 013** | **SPEC_READY** — [spec](specs/SPEC-024-currency-exposure.md) |
| SPEC-025 | `brain/risk/` P1,P2,P5,P6,P9,P10,P11 **+ P12 no_cross_account_hedge** ([ADR-005](decisions/ADR-005-cross-account-hedge.md)) · **ต้อง `import` จาก SPEC-027 ห้ามเขียน `stricter_of` ใหม่** | Codex | 024, 026, **027**, 014, 061 | **SPEC_READY** — [spec](specs/SPEC-025-brain-risk-portfolio.md) |
| SPEC-026 | Correlation engine + P4 correlated risk cap — fail-closed `corr = 1.0` (G1) | Codex | 024, 060, 061, 064 | **SPEC_READY** — [spec](specs/SPEC-026-correlation-engine.md) |
| SPEC-030 | Risk scenario suite (20 สถานการณ์เลวร้าย) | **Claude ออกแบบ** / Codex code | 019–027 | TODO — เขียนได้เมื่อ 019–027 implement เสร็จ |
| SPEC-030b | **Runbook ขั้นต้น** — ย้ายมาจาก Phase 6 เพราะเงินจริงเริ่มปลาย Phase 2 (G4) | **Claude** | 028 | TODO — ต้องรอ 028 + 023 ทำงานจริงก่อน ไม่งั้นเขียนจากจินตนาการ |

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
| SPEC-053 | NSSM services, auto-restart, log rotation · ★ **+ auto-start ตอนบูต** (ดู §R1 ด้านล่าง) | Codex | 052 | TODO |
| SPEC-054 | Multi-VPS: VPN, TLS, session isolation | Codex | 053 | TODO |
| SPEC-055 | Backup/restore (DB, artifacts, config) | Codex | 053 | TODO |
| SPEC-056 | Runbook | **Claude** | 053 | TODO |

### §R1 ★ ข้อกำหนด: เปิดเครื่อง + มีเน็ต → ระบบขึ้นเองทั้งหมด

**สั่งโดยเจ้าของ 2026-07-31** · เข้าขอบเขต **SPEC-053** (Phase 6) — บันทึกไว้ที่นี่เพื่อไม่ให้หล่น

```
เครื่องบูต → รอเน็ตพร้อม → PostgreSQL → gateway → dashboard → alert sender
           → watchdog → MT5 terminal ทุกตัว → EA attach
```

| ต้องมี | เหตุผล |
|--------|--------|
| ทุก service ขึ้นเอง **ไม่ต้องมีคนกด** | นี่คือข้อกำหนดหลัก · VPS รีบูตเองได้ทุกเมื่อ (Windows Update · ไฟดับ) |
| **รอเน็ตจริงก่อน** ไม่ใช่แค่รอ service `Network` | Windows บอกว่าเน็ตพร้อมก่อนที่ DNS/route จะใช้ได้จริง → ให้ probe จริง (ping broker / resolve host) แล้วค่อยเริ่ม |
| ลำดับ dependency ถูกต้อง | gateway ที่ขึ้นก่อน DB จะ crash loop |
| **watchdog ขึ้นเป็นตัวแรก** ไม่ใช่ตัวสุดท้าย | ถ้าตัวอื่นขึ้นไม่สำเร็จ ต้องมีคนแจ้ง ([SPEC-062 §4.7](specs/SPEC-062-watchdog.md) มี Scheduled Task `At startup` อยู่แล้ว) |
| **แจ้ง Telegram ทุกครั้งที่ระบบขึ้นจากการบูต** | การบูตที่ไม่ได้ตั้งใจ = สัญญาณว่ามีอะไรผิด · ห้ามให้ระบบกลับมาเงียบๆ |

#### ★★ จุดที่ต้องแยกให้ขาด — "ระบบขึ้นเอง" ≠ "กลับไปเทรดเองทันที"

ผมทำตามข้อกำหนดนี้เต็มที่ **แต่ขอบันทึกความเสี่ยงหนึ่งข้อไว้ให้ชัด:**
ถ้าเครื่องรีบูตเพราะ**มีอะไรพัง** การกลับมาเทรดอัตโนมัติจะกลบปัญหานั้น
และถ้าพังซ้ำจะกลายเป็น boot loop ที่เปิด-ปิด position รัวๆ

**ทางที่ได้ทั้งสองอย่าง — ไม่ต้องมีคนกดในกรณีปกติ:**

| กลไก | มีอยู่แล้วที่ |
|------|--------------|
| EA ทำ reconciliation ตอน `OnInit` ก่อนเทรด | [SPEC-017](specs/SPEC-017-reconciliation.md) — *"รายงานความจริง อย่าลงมือ"* |
| กลับมาแล้วเจอ kill file → ยัง HALT | [SPEC-023 §4.2](specs/SPEC-023-safemode.md) — ลบไฟล์อย่างเดียวไม่ปลด |
| halt state persist ข้ามรีสตาร์ต | [risk-spec R6/R14](03-risk-spec.md) |

**บวกที่ต้องเพิ่มใน SPEC-053 — ✅ เจ้าของอนุมัติแล้ว 2026-07-31:**

- **boot counter** — บูต ≥ **3 ครั้งใน 30 นาที** → ขึ้นทุก service ตามปกติ
  **แต่ EA เข้า `REDUCE_ONLY`** + alert `FATAL` · **ต้องมีคนปลดด้วยมือ**
  (boot loop คือสัญญาณว่ามีอะไรพังจริง ไม่ใช่เหตุบังเอิญ)
- บูตปกติ (ยังไม่ถึงเกณฑ์) → เทรดต่อได้ทันทีหลัง reconciliation ผ่าน **ไม่ต้องรอคน**
- ตัวนับต้อง **persist ข้ามการบูต** (ไฟล์บนดิสก์ · ไม่ใช่ตัวแปรใน memory)
  และ **ล้างเมื่อระบบอยู่รอดเกิน 30 นาที** — ไม่งั้นจะสะสมจนติดกับดักตัวเองในอีกหลายเดือน

> เขียนไว้เพื่อให้ตอนเขียน SPEC-053 ไม่ต้องมาเถียงกันใหม่ — **ข้อกำหนดคือขึ้นเองทั้งหมด
> และมันทำได้โดยไม่ต้องลดความปลอดภัย** เพราะด่านที่ต้องผ่านมีอยู่ในระบบแล้วทุกด่าน

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
| ~~D4~~ | ~~ชุด symbol และ timeframe หลัก~~ | ✅ **ปิดแล้ว** → [ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.4 · **6 คู่** `EURUSD` `USDJPY` `GBPUSD` `AUDUSD` `USDCAD` `XAUUSD` × M1/M5/M10/M15/M30/H1/H4 · ingest ดึง **M1 อย่างเดียวแล้ว resample** · `USDCNY` ตัดทิ้ง · `XAGUSD` ตัดออก | 2026-07-27 |
| ~~D5~~ | ~~ทุนต่อบัญชี~~ | ✅ **ปิดแล้ว: demo-first** ([ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.5) · IUX ไม่มีบัญชี cent → $30 standard เทรดไม่ได้เลยทุกทาง (ตัวถูกสุด `USDJPY` ยังต้อง ~$383) · Phase 0–2 ไม่ต้องใช้เงินจริง roadmap วางให้ live เริ่มปลาย Phase 2 อยู่แล้ว → **ไม่ทำให้ช้าลง** · ตั้ง demo balance $3,000 ให้ lot math ทำงานเหมือนจริง · ทุน live ตัดสินตอนจบ Phase 2 (~$2,200 ครบ 6 คู่) | 2026-07-27 |
| ~~D10~~ | ~~hedge ข้ามบัญชี/ข้ามโบรกเกอร์ไม่มีใครกัน~~ | ✅ **ปิดแล้ว: ห้ามสวนกันทั้งฟาร์ม** → [ADR-005](decisions/ADR-005-cross-account-hedge.md) · **P12 `no_cross_account_hedge`** reject intent ที่จะทำให้เกิด · สภาพที่เกิดแล้ว = `REDUCE_ONLY` เฉพาะ symbol นั้น + alert ERROR ค้างจนคนแก้ · P3/P4 รวม gross ที่ระดับ symbol · "แยกบัญชีแล้วสวนได้" ของ ADR-001 ถูกยกเลิก | 2026-07-30 |
| **D11** | 🔴 **XM login ไม่ผ่าน** — `'1301856021': authorization on XMGlobal-MT5 6 failed (Invalid account)` · ทุก server ตอบ `no demo/preliminary groups` = สร้าง demo ในเทอร์มินัลไม่ได้ ต้องสมัครผ่านเว็บ · **XM ยังใช้งานไม่ได้เลยจนกว่าจะแก้** | ⏳ บล็อกการใช้ XM ทั้งหมด · **ไม่บล็อกงาน IUX** | 2026-07-27 |
| **D12** | **contract spec จริงของ XM** (`SYMBOL_TRADE_CONTRACT_SIZE` · `VOLUME_MIN` · `VOLUME_STEP`) — ถ้าเป็นบัญชี **Micro** อาจพลิก D5 ให้ $30 ใช้ได้ | ⏳ อ่านไม่ได้จนกว่า D11 ผ่าน · **ห้ามวางแผนบนการเดา** ([ADR-003 §5](decisions/ADR-003-multi-broker.md)) | 2026-07-27 |
| ~~D9~~ | ~~P3/P4 ไม่ระบุหน่วยของ exposure~~ | ✅ **ปิดแล้ว: risk-normalized** → [ADR-004](decisions/ADR-004-exposure-unit.md) · เพดาน 2.0% ต่อสกุล · **USD (สกุลบัญชี) 5.0%** เพราะทั้ง 6 คู่มี USD ขาหนึ่ง · `value_per_point` คำนวณจาก `contract_size` + ราคาปัจจุบัน ห้ามใช้ `tick_value` จาก `HELLO` · farm equity dedupe ตาม `(broker, login)` | 2026-07-30 |
| ~~D6~~ | ~~BTCUSD.iux เปิดเสาร์-อาทิตย์ไหม~~ | ✅ **ปิด — ไม่เกี่ยวแล้ว** ตัด BTCUSD ออกจากชุด symbol (rev.2) ทั้ง 6 คู่ปิดสุดสัปดาห์ กฎ weekend bar เดียวใช้ได้ทุกตัว | 2026-07-27 |
| ~~**D16**~~ | ~~สร้าง git remote ที่ไหน~~ | ✅ **ปิด 2026-07-31** — remote มีอยู่จริงและใช้งานได้: `github.com/chaiyasitkom/ea-farm` · `main` + 2 branch push แล้ว · ⚠️ **แต่เป็น public** → เจ้าของกำลังเปลี่ยนเป็น private ([08 §1.4](08-status-and-plan.md)) · **ไม่มี credential หลุด** (`.gitignore` ครอบครบ) แต่เลขบัญชี demo `2101178419` อยู่บน public แล้ว · 📌 **บทเรียน: เอกสารอ้างว่า "ไม่มี remote" มา 3 rev. โดยไม่เคยรัน `git remote -v` เลย** | 2026-07-28 |
| **D17** | ตั้ง self-hosted runner บนเครื่อง Windows นี้ไหม | 🟠 ถ้าเอา จะได้ MQL5 gate อัตโนมัติจริง **แทน attestation** · ต้องมี D16 ก่อน ([SPEC-009 §4.4](specs/SPEC-009-ci.md)) | 2026-07-28 |
| **D7** | สเปก VPS (CPU/RAM/latency ไป IUX) | ⏳ กระทบ SPEC-032 spread model + Phase 6 | 2026-07-27 |
| **D13** | **ติดตั้ง PostgreSQL อย่างไร** — เครื่องไม่มี Docker · ไม่มี PG · มี WSL2 · **ต้องติดตั้งซอฟต์แวร์ = เจ้าของตัดสิน** | ⏳ แนะนำ **native บน Windows** (ตรงกับ VPS ที่จะเป็น Windows เพราะ MT5 · ชิ้นส่วนน้อยสุด) · **ไม่บล็อกการเขียนโค้ด** — Codex เขียน migration + repository ได้เลย ต่อ DB จริงตอนรัน test marker `db` ([SPEC-006 §9.1](specs/SPEC-006-database.md)) | 2026-07-28 |
| **D15** | 🔴 **historical broker→UTC mapping** — MT5 คืนเวลา broker · แปลงเป็น UTC ต้องรู้ offset **ณ ขณะนั้นในอดีต** ซึ่งเลื่อนตาม DST ปีละ 2 ครั้ง · `CBrokerTime` (SPEC-063) ตรวจได้แค่ offset **ปัจจุบัน** → ใช้แปลงข้อมูลปี 2016 = **ผิดครึ่งปีทุกปี** · SPEC-007 จึงเก็บ `time_broker` แบบ naive **ปฏิเสธที่จะเดา** | ⏳ **ต้องแก้ก่อน SPEC-032/033** · ทางเลือก: ปฏิทิน DST ของโบรกเกอร์ · หรือ infer จากขอบสัปดาห์ของข้อมูลเอง ([SPEC-007 §4.3](specs/SPEC-007-data-ingest.md)) | 2026-07-28 |
| **D14** | **เอา TimescaleDB ไหม** | 🟡 **แนะนำ: ยังไม่เอา** — ข้อมูลย้อนหลังไป Parquet ไม่ใช่ DB · `bars` สดหลักพันแถว/เดือน · `account_state` 90 วัน ≈ 9M แถว PG เปล่ารับไหว · **เป็นประตูที่เปิดกลับได้** (`create_hypertable(migrate_data=>true)`) ([SPEC-006 §3.1](specs/SPEC-006-database.md)) | 2026-07-28 |
| ~~D8~~ | ~~contract size ของ `XAGUSD.iux`~~ | ✅ **ปิด — ไม่เกี่ยวแล้ว** ตัด XAGUSD ออกจากชุด symbol (rev.3) | 2026-07-27 |

---

## Environment (ยืนยันแล้ว 2026-07-26)

| หัวข้อ | ค่า |
|--------|-----|
| Repo path | `D:\ea-farm` (ASCII เท่านั้น — ห้ามย้ายกลับไป path ที่มีอักษรไทย/เว้นวรรค) |
| Git | 2.51.1.windows.1 · branch หลัก `main` |
| Line ending | LF บังคับผ่าน `.gitattributes` (ยกเว้น `.bat/.cmd/.ps1`) |
| Remote | ยังไม่มี — local only |
| **โบรกเกอร์** | **2 ราย** ([ADR-003](decisions/ADR-003-multi-broker.md)) — **IUX Markets** `IUXMarkets-Demo` ✅ ใช้ได้ · **XM Global** `XMGlobal-MT5 6` 🔴 login ไม่ผ่าน (D11) |
| **Terminal IUX** | `…\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3` — `C:\Program Files\MetaTrader 5` ไม่มีบัญชี/history รัน tester ไม่ได้ |
| **Terminal XM** | `…\Terminal\BB16F565FAAA6B23A20C26C49416FF05` · build 6063 · **ไม่มี history ใช้ได้เลย** (stub 15 KB) |
| **ชื่อ symbol** | ⚠️ **ไม่ตรงกันข้ามโบรกเกอร์** — IUX `EURUSD.iux` / `XAUUSD.iux` · XM `EURUSD` / **`GOLD`** → ต้องมี SymbolRegistry (SPEC-064) ห้ามตัด suffix ด้วย string rule |
| **Symbol** | **6 คู่ (ปิดแล้ว)** `EURUSD` · `USDJPY` · `GBPUSD` · `AUDUSD` · `USDCAD` · `XAUUSD` — suffix `.iux` บังคับ |
| **Timeframe** | M1 · M5 · M10 · M15 · M30 · H1 · H4 — MT5 เก็บแค่ M1 ที่เหลือ derive |
| **M1 history** | EURUSD/XAUUSD 2016–2026 · อื่นๆ มีแล้ว · **`USDJPY` ยังไม่ได้ดาวน์โหลด** (มี tick ไม่มี bar) |
| **บัญชี** | **demo-first** — IUX ไม่มีบัญชี cent · $30 standard เทรดไม่ได้ · ตั้ง demo balance **$3,000** · ทุน live ตัดสินตอนจบ Phase 2 (D5) |
