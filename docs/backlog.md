# Backlog — เรียงตามลำดับที่ต้องทำ

สถานะ: `TODO` · `SPEC_READY` (Claude เขียน spec เสร็จ Codex ทำได้) · `IN_PROGRESS` · `IN_REVIEW` · `DONE` · `BLOCKED`

---

## Phase 0 — Foundations

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-001 | MT5 Executor skeleton + Wire (socket, JSON-lines, reconnect) | Codex | — | **SPEC_READY** |
| SPEC-002 | Repo scaffold, `.env.example`, **`tools/task.py`** (ไม่ใช่ Makefile — เครื่องนี้ไม่มี `make`) + local gate `check` | Codex | — | **SPEC_READY** — [spec](specs/SPEC-002-repo-scaffold.md) |
| SPEC-003 | `contracts/schema/*.json` ทุก message type | **Claude** | — | ✅ **DONE** — 13 schema + README · [handoff](reviews/SPEC-003-schema-handoff.md) |
| SPEC-004 | Codegen: schema → pydantic + MQL5 struct/serializer | Codex | 003 | **SPEC_READY** — [spec](specs/SPEC-004-codegen.md) |
| SPEC-005 | Round-trip test harness (py ↔ mql5) | Codex | **002**, 004 | **SPEC_READY** — [spec](specs/SPEC-005-roundtrip-harness.md) |
| SPEC-006 | **PostgreSQL** + migration + repository layer (เลื่อน TimescaleDB — [§3.1](specs/SPEC-006-database.md)) | Codex | **002**, 004 | **SPEC_READY** — [spec](specs/SPEC-006-database.md) |
| SPEC-007 | Data ingest: MT5 history → Parquet (**6 คู่ · M1 เท่านั้นแล้ว resample** · ~10 ปี) | Codex | 002, **064** | **SPEC_READY** — [spec](specs/SPEC-007-data-ingest.md) |
| SPEC-008 | Data quality gate (gap/spike/dup/weekend detection) | Codex | 007 | **SPEC_READY** — [spec](specs/SPEC-008-data-quality-gate.md) |
| SPEC-009 | **CI: ปิด G3 ด้วย attestation** — `pre-push` hook + `mql5-attest` + workflow ที่รอ remote | Codex | 002, **065** | **SPEC_READY** — [spec](specs/SPEC-009-ci.md) |
| SPEC-063 | **BrokerTime module** — broker tz/DST เป็นแหล่งความจริงเดียว ห้ามคำนวณเวลาเอง (G6) | Codex | **001** (แก้จาก 002 — เป็น MQL5 ล้วน ไม่ต้องรอ scaffold) | 🔨 **IN_REVIEW รอบ 2 → `CHANGES_REQUIRED`** · [spec rev.2a](specs/SPEC-063-broker-time.md) · [review 1](reviews/SPEC-063.md) · [review 2](reviews/SPEC-063-02.md) — B1/B2/B3/B5/B8 ปิดแล้ว · เหลือ **B4** (ไม่เคยแตะ) · B15/B16 ใหม่ · **gate T1/T2 ต้องแก้ก่อนเชื่อผลรัน** |
| SPEC-064 | **SymbolRegistry** — `(broker, raw)` → canonical + base/quote + risk profile ต่อ symbol (G7) · 🔴 ขาดไม่ได้หลังเพิ่ม XM: `GOLD` → `XAUUSD` เดาด้วย string rule ไม่ได้ ([ADR-003](decisions/ADR-003-multi-broker.md)) | Codex | **004** (แก้จาก 006 — เป็นไฟล์ในรีโป ไม่ใช่ตาราง DB) | **SPEC_READY** — [spec](specs/SPEC-064-symbol-registry.md) |
| SPEC-065 | **MQL5 test harness** — ส่วนใหญ่ทำแล้ว · เหลือ manifest หลาย suite + attestation ให้ CI (G9, [07](07-compile-gate.md)) | Codex | 001 | **SPEC_READY** — [spec](specs/SPEC-065-mql5-test-harness.md) |

## Phase 1 — Execution Plane

| ID | งาน | ผู้ทำ | ขึ้นกับ | สถานะ |
|----|-----|-------|---------|-------|
| SPEC-010 | `StateReporter.mqh` — HELLO/HEARTBEAT/BAR/STATE + backfill 300 bar | Codex | 001, 004, **063** (เพิ่ม — `bar_time` เป็นส่วนของ PK ถ้าเวลาผิดต้อง migrate ทั้งตาราง) | **SPEC_READY** — [spec](specs/SPEC-010-state-reporter.md) |
| SPEC-011 | `OrderRouter.mqh` — target-state reconciler (hedging) ★ ยากสุด | Codex | 010 ← **ปลดล็อกแล้ว** | **SPEC_READY** (ยังต้องรอ 010 เสร็จ + `test_partial_send_resumes` ด้วย socket จริง) |
| SPEC-012 | Intent dedupe cache + expiry handling | Codex | 011, **063** | **SPEC_READY** — [spec](specs/SPEC-012-intent-cache.md) |
| SPEC-013 | Gateway: asyncio TCP server, auth, session registry ★ **คอขวดของ Phase 1** | Codex | 002, 004, 006, **064** | **SPEC_READY** — [spec](specs/SPEC-013-gateway.md) |
| SPEC-014 | Persist intents/exec_reports/account_state/bars | Codex | **006**, 013 | **SPEC_READY** — [spec](specs/SPEC-014-persistence.md) |
| SPEC-015 | EMA baseline strategy (พิสูจน์ท่อ ไม่ใช่ทำเงิน) | Codex | 013, **014**, **064** | **SPEC_READY** — [spec](specs/SPEC-015-ema-baseline.md) |
| SPEC-016 | Chaos test harness + scenario — **ชั้น A (wire) ต้องการแค่ 001** · ชั้น B (intent) ต้องการ 011+013 | Codex | **001** (A) · 011,013 (B) | **SPEC_READY** — [spec](specs/SPEC-016-chaos-harness.md) ← **ปลดล็อก work-order รอบ 1** |
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
| SPEC-024 | Currency exposure decomposition (P3) | Codex | 014, 064 | 🔴 **BLOCKED — D9** |
| SPEC-025 | `brain/risk/` P1,P2,P5,P6,P9,P10,P11 · **ต้อง `import` จาก SPEC-027 ห้ามเขียน `stricter_of` ใหม่** | Codex | 024, **027** | 🔴 **BLOCKED — D9 + D10** |
| SPEC-026 | Correlation engine + P4 correlated risk cap | Codex | 024, 060 | 🔴 **BLOCKED — D9** |
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
| ~~D4~~ | ~~ชุด symbol และ timeframe หลัก~~ | ✅ **ปิดแล้ว** → [ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.4 · **6 คู่** `EURUSD` `USDJPY` `GBPUSD` `AUDUSD` `USDCAD` `XAUUSD` × M1/M5/M10/M15/M30/H1/H4 · ingest ดึง **M1 อย่างเดียวแล้ว resample** · `USDCNY` ตัดทิ้ง · `XAGUSD` ตัดออก | 2026-07-27 |
| ~~D5~~ | ~~ทุนต่อบัญชี~~ | ✅ **ปิดแล้ว: demo-first** ([ADR-002](decisions/ADR-002-symbols-capital-hours.md) rev.5) · IUX ไม่มีบัญชี cent → $30 standard เทรดไม่ได้เลยทุกทาง (ตัวถูกสุด `USDJPY` ยังต้อง ~$383) · Phase 0–2 ไม่ต้องใช้เงินจริง roadmap วางให้ live เริ่มปลาย Phase 2 อยู่แล้ว → **ไม่ทำให้ช้าลง** · ตั้ง demo balance $3,000 ให้ lot math ทำงานเหมือนจริง · ทุน live ตัดสินตอนจบ Phase 2 (~$2,200 ครบ 6 คู่) | 2026-07-27 |
| **D10** | 🔴 **hedge ข้ามบัญชี/ข้ามโบรกเกอร์ไม่มีใครกัน** — R18 กันแค่ระดับ (magic, symbol) ในบัญชีเดียว · long `EURUSD` ที่ XM + short `EURUSD.iux` ที่ IUX = P3 net เป็น 0 มองว่าปลอดภัย แต่จ่าย spread+swap 2 ขาเพื่อ exposure สุทธิ 0 · เสนอ **P12 `no_cross_account_hedge`** ([ADR-003 §4](decisions/ADR-003-multi-broker.md)) | ⏳ **ต้องปิดก่อน SPEC-025** · เจ้าของต้องตัดสินก่อน: "แยกบัญชี = อนุญาตให้สวนกัน" หรือ "ห้ามสวนกันทั้งฟาร์ม" | 2026-07-27 |
| **D11** | 🔴 **XM login ไม่ผ่าน** — `'1301856021': authorization on XMGlobal-MT5 6 failed (Invalid account)` · ทุก server ตอบ `no demo/preliminary groups` = สร้าง demo ในเทอร์มินัลไม่ได้ ต้องสมัครผ่านเว็บ · **XM ยังใช้งานไม่ได้เลยจนกว่าจะแก้** | ⏳ บล็อกการใช้ XM ทั้งหมด · **ไม่บล็อกงาน IUX** | 2026-07-27 |
| **D12** | **contract spec จริงของ XM** (`SYMBOL_TRADE_CONTRACT_SIZE` · `VOLUME_MIN` · `VOLUME_STEP`) — ถ้าเป็นบัญชี **Micro** อาจพลิก D5 ให้ $30 ใช้ได้ | ⏳ อ่านไม่ได้จนกว่า D11 ผ่าน · **ห้ามวางแผนบนการเดา** ([ADR-003 §5](decisions/ADR-003-multi-broker.md)) | 2026-07-27 |
| **D9** | 🔴 **P3/P4 ไม่ระบุหน่วยของ exposure** — เพดานเป็น `% ของ farm equity` แต่ decomposition ให้ผลเป็น notional เทียบกันไม่ได้ · ตีความแบบ notional จะ **reject ทุกไม้ที่ทุนระดับไหนก็ตาม** (แม้ $100k ก็ได้เพดาน 0.02 lot) · เสนอนิยามเป็น **risk-normalized** ([03-risk-spec §P3](03-risk-spec.md)) | ⏳ **ต้องยืนยันก่อน SPEC-024** — เปลี่ยนความหมายของกฎ risk ไม่ใช่แค่ปรับตัวเลข | 2026-07-27 |
| ~~D6~~ | ~~BTCUSD.iux เปิดเสาร์-อาทิตย์ไหม~~ | ✅ **ปิด — ไม่เกี่ยวแล้ว** ตัด BTCUSD ออกจากชุด symbol (rev.2) ทั้ง 6 คู่ปิดสุดสัปดาห์ กฎ weekend bar เดียวใช้ได้ทุกตัว | 2026-07-27 |
| **D16** | ⭐ **สร้าง git remote ที่ไหน** — ตอนนี้ repo อยู่บนเครื่องเดียว **ไม่มี backup** เครื่องพัง = หาย ADR + spec + schema ทั้งหมด · และ **ไม่มี remote = ไม่มี CI** | 🔴 **แนะนำให้ทำก่อนอย่างอื่น** — ความเสี่ยงสูงสุดต่อความพยายามต่ำสุด · ตัวเลือก: GitHub private · GitLab · Gitea ในเครื่อง · **ไม่บล็อก SPEC-009 ชั้น 1–2** ([SPEC-009 §3.2](specs/SPEC-009-ci.md)) | 2026-07-28 |
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
