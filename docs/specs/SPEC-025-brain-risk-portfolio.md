# SPEC-025 — `brain/risk/` Portfolio Manager: P1 P2 P5 P6 P9 P10 P11 P12

**Phase:** 2 ★★ · **Owner:** Codex · **Depends on:** SPEC-024, SPEC-026, SPEC-027, SPEC-014, SPEC-061
**อ้าง:** [03-risk-spec §L2](../03-risk-spec.md) · [ADR-004](../decisions/ADR-004-exposure-unit.md) · [ADR-005](../decisions/ADR-005-cross-account-hedge.md)

> ticket นี้คือ **คนตัดสิน** ของชั้น L2 · [SPEC-027](SPEC-027-risk-directive.md) คือ **ท่อ**
> ที่พา directive ไปถึง EA · **ห้ามเขียน `stricter_of` / `STRICTNESS` / `DirectiveDispatcher` ใหม่ — `import` เท่านั้น**
>
> D9/D10 ปิดแล้ว → [ADR-004](../decisions/ADR-004-exposure-unit.md) (หน่วย exposure) · [ADR-005](../decisions/ADR-005-cross-account-hedge.md) (P12)

---

## 1. Goal

รวมกฎ L2 ที่เหลือทั้งหมดให้ทำงานเป็นชิ้นเดียว: ประเมินทุก intent ก่อนส่ง
และเฝ้าสถานะฟาร์มทุก 5 วินาทีเพื่อสั่ง `RISK_DIRECTIVE` เมื่อจำเป็น

จบ ticket นี้ = ชั้น L2 ครบตาม [03-risk-spec](../03-risk-spec.md) (P1–P12 ยกเว้น P7/P8 ที่เป็น Phase 4)

## 2. Non-goals

- ❌ ห้ามคำนวณ exposure/risk เอง — `import ExposureEngine` (SPEC-024)
- ❌ ห้ามคำนวณ correlation เอง — `import P4Guard` (SPEC-026)
- ❌ ห้ามเขียนตรรกะความเข้มของ mode ใหม่ — `import stricter_of` (SPEC-027) ★★
- ❌ ห้ามเขียน stale logic ใหม่ — `import StaleDataGuard` (SPEC-061)
- ❌ ห้าม implement P7 (regime) / P8 (news) — Phase 4 · **แต่ต้องเว้นที่ให้เสียบเข้ามาได้** (§4.2)
- ❌ ห้ามสร้าง strategy หรือ intent เอง — ที่นี่คือด่านตรวจ ไม่ใช่คนคิด
- ❌ ห้ามแตะ `mt5-ea/**` · `contracts/**` · `docs/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ทำอะไร |
|------|--------|
| `brain/risk/manager.py` | **สร้าง** — `PortfolioRiskManager` (orchestrator §4.2) |
| `brain/risk/rules/farm_dd.py` | **สร้าง** — P1 · P2 |
| `brain/risk/rules/concentration.py` | **สร้าง** — P5 · P6 |
| `brain/risk/rules/sanity.py` | **สร้าง** — P9 |
| `brain/risk/rules/session_health.py` | **สร้าง** — P11 |
| `brain/risk/rules/cross_hedge.py` | **สร้าง** — P12 ★ |
| `brain/risk/config.py` | **แก้** — เพิ่มค่าของ ticket นี้ (ไฟล์สร้างใน SPEC-024) |
| `tests/test_risk_manager.py` · `tests/test_farm_dd.py` · `tests/test_cross_hedge.py` · `tests/test_sanity.py` | **สร้าง** — §7 |

### 3.2 API

```python
@dataclass(frozen=True)
class RuleVerdict:
    rule: str                    # "P12" · ต้องจับคู่กับ rule id ใน risk_events ได้
    ok: bool
    scale: float                 # 1.0 = ไม่ลด
    reason: str                  # "" เมื่อ ok และ scale == 1.0

@dataclass(frozen=True)
class IntentDecision:
    allowed: bool
    scale: float                 # min ของทุกกฎ
    verdicts: tuple[RuleVerdict, ...]        # ★ ทุกกฎที่รัน ไม่ใช่เฉพาะตัวที่ปฏิเสธ
    reject_reason: str           # "" เมื่อ allowed

class PortfolioRiskManager:
    def __init__(self, exposure: ExposureEngine, p4: P4Guard, guard: StaleDataGuard,
                 dispatcher: DirectiveDispatcher, events: RiskEventRepo,
                 clock: Clock, config: PortfolioConfig): ...

    def evaluate_intent(self, intent: Intent) -> IntentDecision: ...
    async def reevaluate_farm(self) -> None: ...      # ทุก 5 วินาที (§4.6)
    def farm_status(self) -> FarmStatus: ...          # ให้ dashboard (SPEC-028)
```

### 3.3 `PortfolioConfig`

| key | default | กฎ |
|-----|---------|-----|
| `farm_daily_loss_warn_pct` / `breach_pct` | **1.5** / **3.0** | P1 |
| `farm_max_dd_warn_pct` / `breach_pct` | **8.0** / **12.0** | P2 |
| `max_same_direction_per_group` | **3** | P5 (§4.5) |
| `farm_open_risk_budget_pct` | **5.0** | P6 (§4.5) |
| `session_stale_sec` | **30** | P11 |
| `degraded_equity_share_pct` | **30** | P11 (§4.7) |
| `hysteresis_pp` / `min_hold_sec` | **0.3** / **60** | §4.8 |

---

## 4. Behaviour

### 4.1 ★★ กฎเหล็กของ ticket นี้: reject ชนะ scale เสมอ

```
allowed = ทุกกฎ ok            (AND -- ไม่มีกฎไหน veto)
scale   = min(scale ของทุกกฎ)  (MIN -- ตรงกับ SPEC-027 §4.1)
```

**ห้ามมีเงื่อนไขไหนที่ผลลัพธ์ผ่อนกว่ากฎที่เข้มที่สุด** · ห้ามให้กฎหลังเขียนทับกฎหน้า

### 4.2 ลำดับการประเมิน intent — ต้องเรียงแบบนี้

| # | กฎ | ทำไมอยู่ตรงนี้ | ผลเมื่อไม่ผ่าน |
|---|-----|----------------|----------------|
| 1 | **P9** sanity | ถ้า intent เพี้ยน กฎอื่นจะคำนวณจากขยะ | reject + alert `ERROR` (model เพี้ยน) |
| 2 | **P10** stale (`guard.require`) | ถูกกว่าการคำนวณ และเป็นเงื่อนไขของทุกกฎที่เหลือ | reject |
| 3 | **P11** session health | ต้องรู้ก่อนว่านับบัญชีไหน | ปรับ snapshot (§4.7) |
| 4 | **P2** farm DD → **P1** farm daily loss | สถานะฟาร์มคุมทุกอย่าง | reject (`HALT`/`FLATTEN` อยู่แล้ว) |
| 5 | **P12** cross-account hedge | ต้องอยู่**ก่อน** P3/P4 เพราะเปลี่ยนวิธีนับ (gross) | reject |
| 6 | **P3** currency exposure (SPEC-024) | | reject |
| 7 | **P4** correlated risk (SPEC-026) | | scale |
| 8 | **P5** same-direction per group | | reject ตัว confidence ต่ำสุด |
| 9 | **P6** strategy allocation | | scale |
| — | *(P7 regime · P8 news — Phase 4)* | **เว้นช่องไว้ที่ท้ายลูป** | — |

- ทุกกฎต้อง**รันครบ**และคืน `RuleVerdict` แม้จะมีกฎก่อนหน้าปฏิเสธไปแล้ว
  (ยกเว้นกฎที่คำนวณไม่ได้จริงๆ เช่น P3 เมื่อ P10 บอกว่าข้อมูลหาย) —
  **เพราะ log ที่บอกว่า "ตกข้อเดียว" ทำให้คนแก้ผิดจุดเมื่อจริงๆ ตก 3 ข้อ**
- `target_volume = 0` → **ผ่านทุกกฎเสมอ** ไม่ต้องประเมินอะไรเลย ★★
  ([SPEC-027 §4.5](SPEC-027-risk-directive.md) · [SPEC-023](SPEC-023-safemode.md))

### 4.3 P1 farm daily loss · P2 farm max DD

```
farm_equity     = Σ equity ของ (broker, login) ที่นับ   (ExposureEngine §4.2 -- ห้ามคำนวณเอง)
farm_day_pl_pct = (farm_equity − farm_day_start_equity) / farm_day_start_equity × 100
farm_dd_pct     = (farm_hwm − farm_equity) / farm_hwm × 100
```

| กฎ | เกณฑ์ | สั่ง |
|----|-------|------|
| P1 warn | ≤ **−1.5%** | `SCALED 0.5` ทั้งฟาร์ม |
| P1 breach | ≤ **−3.0%** | `FLATTEN` ทั้งฟาร์ม (`flatten_symbols = []`) |
| P2 warn | ≥ **8.0%** | `REDUCE_ONLY` |
| P2 breach | ≥ **12.0%** | `HALT` (ไม่มี `expires_at` — [SPEC-027 §4.3](SPEC-027-risk-directive.md)) |

**★ "วันใหม่" ของฟาร์มใช้ UTC 00:00 ไม่ใช่ broker time**

| ทางเลือก | ปัญหา |
|----------|-------|
| broker time ของแต่ละบัญชี | IUX กับ XM อาจ reset คนละเวลา → ตัวเลข "day P/L ของฟาร์ม" ไม่มีความหมายเดียว |
| ✅ **UTC 00:00** | นิยามเดียวทั้งฟาร์ม · ทุก `ts_server` เป็น UTC อยู่แล้ว ([SPEC-063](SPEC-063-broker-time.md)) |

R6 (ระดับบัญชี ใน EA) **ยังใช้ broker time ตามเดิม** — สองชั้นนี้ reset คนละนาทีได้
เป็นเรื่องที่ยอมรับแล้ว: L1 คุมบัญชีตัวเอง L2 คุมฟาร์ม **ห้ามพยายามทำให้ตรงกัน**
โดยเปลี่ยน R6 ไปใช้ UTC (จะทำให้ EA ต้องรู้เรื่องฟาร์ม = ผิดหลัก L1 offline-safe)

**`farm_hwm` และ `farm_day_start_equity` ต้อง persist** ([SPEC-014](SPEC-014-persistence.md)) —
brain restart แล้วต้องได้ค่าเดิม ไม่ใช่เริ่มนับใหม่จาก equity ปัจจุบัน
(เริ่มใหม่ = DD กลายเป็น 0 ทันทีที่ restart = ปลด limit ด้วยการรีสตาร์ต)

### 4.4 ★★ P12 no_cross_account_hedge — [ADR-005](../decisions/ADR-005-cross-account-hedge.md)

```
มี hedge เมื่อ:  ∃ บัญชี a, b (a ≠ b) ที่  net_a(c) > 0  และ  net_b(c) < 0
                 โดย c = canonical symbol  (net_by_account จาก ExposureSnapshot)
```

**ห้ามตัดสินจาก `farm_net(c)`** — `+0.10` กับ `−0.10` รวมเป็น 0 ซึ่งอ่านว่า "ไม่มีอะไร"
ทั้งที่คือเคสที่กฎนี้มีไว้จับพอดี

| สถานะ | intent | ผล |
|-------|--------|-----|
| A `+0.10` | B ขอ `−0.05` | ❌ reject `P12_CROSS_ACCOUNT_HEDGE` |
| A `+0.10` · B `−0.05` (สภาพที่ไม่ควรมี) | A ขอ `+0.02` | ❌ reject — ห้ามขยายสภาพที่ผิด |
| A `+0.10` · B `−0.05` | B ขอ `0` | ✅ ผ่านเสมอ |
| A `+0.10` · B `−0.05` | A ขอ `+0.05` | ✅ ผ่าน — gross ลดลง |

**หลักการเดียวที่ครอบทุกแถว:** intent ที่ทำให้ `Σ|net_i(c)|` **ลดลงหรือเท่าเดิม** ผ่านเสมอ

**ต้องนับ intent ที่ยังไม่ยืนยัน** ([ADR-005 §2.2](../decisions/ADR-005-cross-account-hedge.md)) —
`evaluate_intent` ต้อง **serialize ต่อ canonical symbol** (lock ต่อ symbol) ไม่งั้น intent สองใบ
ไปคนละบัญชีในวินาทีเดียวกันจะเห็นภาพเก่าทั้งคู่แล้วสร้าง hedge พร้อมกันโดยผ่านการตรวจทั้งคู่

**สภาพ hedge ที่เกิดขึ้นแล้ว** (เทรดมือ / ไม้ค้าง / race ที่หลุด):

```
ตรวจพบใน reevaluate_farm() → ส่ง RISK_DIRECTIVE REDUCE_ONLY เฉพาะ symbol นั้น
                            → alert P12_HEDGE_STATE_DETECTED severity ERROR ทุกรอบที่ยังพบ
                            → ★ ห้ามปิดไม้อัตโนมัติ -- ระบบไม่รู้ว่าควรปิดขาไหน
```

### 4.5 P5 · P6 — กฎที่ต้องนิยามให้ตรงกับปัญหาจริง

**P5 `max_concurrent_strategies_same_direction` นับต่อ correlation group ไม่ใช่ทั้งฟาร์ม**

[03-risk-spec](../03-risk-spec.md) ชี้ปัญหาไว้เอง: *"P5 = 3 หลวมเกินไป — 3 ไม้ในก้อนเดียว
= เดิมพันเดียวคูณ 3"* · นับรวมทั้งฟาร์มจะจับ `EURUSD`+`GBPUSD`+`XAUUSD` (คนละเดิมพัน) ผิด
และปล่อย `EURUSD`+`GBPUSD` ทิศเดียวกันในกลุ่มเดียวกันผ่าน

```
นับ distinct strategy_id ที่ถือทิศเดียวกัน ภายใน correlation group เดียวกัน (จาก SPEC-026)
เกิน max_same_direction_per_group  →  reject intent ของกลยุทธ์ที่ confidence ต่ำสุด
```

- "confidence ต่ำสุด" เทียบกับ **intent ที่กำลังพิจารณา** — ถ้าตัวที่จะเข้ามีค่าต่ำสุด → reject ตัวมันเอง
  · ถ้ามีตัวเก่าที่ต่ำกว่า → **ยัง reject ตัวใหม่** และ alert ว่ามีตัวเก่าที่ควรถูกแทนที่
  (ticket นี้**ไม่ปิดไม้ของกลยุทธ์อื่น** — การปิดไม้เพื่อเปิดไม้ใหม่ต้องเป็นการตัดสินใจที่ชัดเจน ไม่ใช่ผลข้างเคียงของกฎนับจำนวน)

**P6 `strategy_allocation` — งบเสี่ยงเท่ากันตอนเริ่ม**

```
budget_pct(s) = farm_open_risk_budget_pct / จำนวนกลยุทธ์ที่ active
used_pct(s)   = Σ risk_pct ของไม้ที่ strategy_id = s   (จาก ExposureSnapshot)
headroom      = budget_pct − used_pct
scale         = clamp(headroom / requested, 0.0, 1.0)      // เหมือน P4 §4.7
```

`farm_open_risk_budget_pct` default **5.0** — ตรงกับเพดาน P3 ของสกุลบัญชี
([ADR-004 §3](../decisions/ADR-004-exposure-unit.md)) เพราะทุกไม้มี USD ขาหนึ่งอยู่แล้ว
open risk รวมของฟาร์มจึงถูกจำกัดที่ระดับนั้นโดยปริยาย — **ไม่ได้ตั้งเพดานใหม่ที่ไม่มีที่มา**

"กลยุทธ์ที่ active" = strategy_id ที่มี session เชื่อมอยู่ (จาก `HELLO.strategy_id`)
**ไม่ใช่**จำนวนที่ถือไม้อยู่ (ไม่งั้นกลยุทธ์ที่ยังไม่เข้าไม้จะถูกกันงบไว้ไม่พอ)

### 4.6 P9 sanity — reject พร้อม alert เพราะแปลว่าโมเดลเพี้ยน

| เช็ค | reject reason |
|------|---------------|
| `confidence` ∉ [0, 1] หรือไม่ finite | `P9_CONFIDENCE_RANGE` |
| `target_volume` ไม่ finite / NaN | `P9_VOLUME_NOT_FINITE` |
| `sl_price` หายไปทั้งที่ `target_volume ≠ 0` | `P9_MISSING_SL` (R9 ระดับฟาร์ม) |
| `sl_price` อยู่ผิดฝั่งของ entry ตามทิศ | `P9_SL_WRONG_SIDE` ★ |
| `sl_price == entry` | `P9_SL_AT_ENTRY` (risk = 0 → หารศูนย์ที่ P3) |
| `symbol` ไม่รู้จักใน registry | `P9_UNKNOWN_SYMBOL` |
| `valid_until` ผ่านไปแล้ว | `P9_EXPIRED_INTENT` |

ทุกข้อ → alert severity **ERROR** (ไม่ใช่ WARN) — intent ที่ผิดรูปคือสัญญาณว่าโมเดลหรือท่อพัง
· นับ `p9_rejects_by_reason` ให้ dashboard เห็น

### 4.7 P11 session health — ★ ตาบอดต้องไม่ทำให้ตัวเลขดูดีขึ้น

| | ทำอะไร |
|---|--------|
| heartbeat หาย > `session_stale_sec` (30s) | บัญชีนั้น**หลุดจากตัวหาร** (`accounts_excluded`) |
| position ของบัญชีนั้น | **ยังนับต่อ** จาก `STATE` ล่าสุด ★★ ([SPEC-024 §4.7](SPEC-024-currency-exposure.md)) |
| บัญชีที่หายรวมกัน > `degraded_equity_share_pct` (30%) ของ equity ฟาร์มก่อนหน้า | ส่ง `REDUCE_ONLY` ทั้งฟาร์ม + alert ★ |
| บัญชีกลับมา | คำนวณใหม่ตามปกติ · ปลด `REDUCE_ONLY` ตาม hysteresis §4.8 |

ข้อที่สามคือกันเคส *"ครึ่งฟาร์มหลุด แล้วตัวเลข P1/P2 ดูดีขึ้นเพราะบัญชีที่ขาดทุนหายไปจากการคำนวณ"*

### 4.8 hysteresis — กันการสั่งกลับไปกลับมา

| | |
|---|---|
| เข้าโหมดเข้มขึ้น | **ทันที** ไม่มีหน่วง |
| ผ่อนกลับ | ต้องดีขึ้นเกินเกณฑ์อย่างน้อย `hysteresis_pp` (0.3pp) **และ** ค้างในสถานะเดิมแล้ว ≥ `min_hold_sec` (60s) |
| `FLATTEN` (P1 breach) · `HALT` (P2 breach) | ❌ **ไม่ปลดอัตโนมัติเลย** — ต้องมีคนปลด |

directive ใหม่ที่ผ่อนกว่าเก่า**แทนที่ได้** ([SPEC-027 §4.2](SPEC-027-risk-directive.md)) —
แต่ effective ยังถูก local guard ของ EA จำกัดอยู่ดี · ห้าม implement เป็น `max(เก่า, ใหม่)`

**ห้ามส่ง directive ซ้ำเมื่อสถานะไม่เปลี่ยน** (กัน storm) — dispatcher จัดการ resend
ตอน reconnect ให้แล้ว ([SPEC-027 §4.7](SPEC-027-risk-directive.md))

### 4.9 `reevaluate_farm()` ทุก 5 วินาที

```
1. snapshot = exposure.snapshot(states, pending)          // SPEC-024
2. ประเมิน P2 → P1 → P11 → P12(สภาพที่เกิดแล้ว)
3. mode = stricter_of(...) ของทุกกฎ                        // import จาก SPEC-027 ★
4. ถ้า mode/scale เปลี่ยน (ผ่าน hysteresis §4.8):
      เขียน risk_events ก่อน → ถ้าเขียนไม่ได้ ห้ามส่ง → dispatcher.broadcast(...)
```

ข้อ 4 ตรงกับ [SPEC-027 §4.8](SPEC-027-risk-directive.md): *"ไม่มีหลักฐาน = ไม่เทรด"*
· `rule` ใน `risk_events` ต้องเป็น P-rule id จริง (`"P1_FARM_DAILY_LOSS_BREACH"`) ไม่ใช่ข้อความอิสระ

**ถ้า `reevaluate_farm()` โยน exception** → ต้อง**ไม่เงียบ**: log `FATAL` + alert +
ส่ง `REDUCE_ONLY` (ลูปที่คุมความเสี่ยงตายแล้วเทรดต่อคือ fail-open ที่ร้ายที่สุดใน ticket นี้)

---

## 5. Edge cases

1. **ไม่มีบัญชีเชื่อมอยู่เลย** → ไม่มี intent ให้ประเมิน · `reevaluate_farm()` ไม่ส่ง directive · ไม่ error
2. **`farm_day_start_equity` ยังไม่มี (brain เพิ่งสตาร์ตกลางวัน)** → **ห้ามใช้ equity ปัจจุบันแทน**
   → อ่านจาก DB · ถ้าไม่มีจริงๆ ให้ `REDUCE_ONLY` + alert จนถึง UTC 00:00 ถัดไป ★★
3. **equity เพิ่มขึ้น** → `farm_hwm` ขยับขึ้น · **ห้ามลดลง**แม้ถอนเงิน (การถอนต้องเป็นงาน ops ที่บันทึกไว้ ไม่ใช่ให้กฎเดา)
4. **บัญชีใหม่เข้าฟาร์มกลางวัน** → `farm_day_start_equity` **บวกเพิ่ม**ด้วย equity ตอนเข้า
   ไม่ใช่คิดว่าเป็นกำไร ★★
5. **บัญชีหลุดถาวร** → equity หายจากตัวหาร แต่ position ยังนับ (§4.7) → ตัวเลขเข้มขึ้น = ตั้งใจ
6. **P1 breach และ P2 breach พร้อมกัน** → `stricter_of(FLATTEN, HALT)` = `HALT`
7. **intent มาถึงระหว่างที่ฟาร์ม `HALT`** → reject ทันทีที่ข้อ 4 ของ §4.2 · ยกเว้น `target_volume = 0`
8. **strategy เดียวมีหลาย session (หลาย symbol)** → P6 นับรวมทั้งกลยุทธ์ ไม่ใช่ต่อ session
9. **P5: intent ของกลยุทธ์ที่ถือไม้ในกลุ่มนั้นอยู่แล้ว** → ไม่นับเพิ่ม (นับ distinct strategy_id)
10. **สอง intent ของ symbol เดียวกันมาพร้อมกัน** → §4.4 serialize ต่อ symbol · ใบหลังเห็นผลของใบแรก
11. **DB เขียน `risk_events` ไม่ได้** → **ไม่ส่ง directive** · alert · **แต่ยังต้อง reject intent ต่อไปได้**
    (การปฏิเสธไม่ต้องรอ DB — ที่ต้องรอคือการ*สั่ง*ฟาร์ม)
12. **นาฬิกา brain ถอยหลัง** → `min_hold_sec` อาจคำนวณเพี้ยน → ใช้ monotonic clock สำหรับ hysteresis
    ไม่ใช่ wall clock ★
13. **`reevaluate_farm()` ใช้เวลานานกว่า 5 วินาที** → ห้ามซ้อนรอบ (ข้ามรอบถัดไป + นับ `reevaluate_overruns`)

---

## 6. Acceptance criteria

- [ ] `stricter_of` / `STRICTNESS` / `DirectiveDispatcher` **import จาก SPEC-027** —
      `grep -rn "STRICTNESS *=\|def stricter_of" brain/risk/` เจอที่ `directive.py` **ที่เดียว** ★★
- [ ] `risk_pct` ทุกค่ามาจาก `ExposureEngine` — `grep -rn "price_open\|contract_size" brain/risk/rules/` ไม่เจอ ★★
- [ ] `allowed = AND` · `scale = MIN` — มี test ที่กฎหนึ่ง reject อีกกฎ scale 1.0 แล้วผลรวมยัง reject ★★
- [ ] `target_volume = 0` ผ่านทุกกฎ **รวมตอน `HALT` และตอนข้อมูล stale** ★★
- [ ] P12 ตรวจ **ต่อบัญชี** ไม่ใช่ `farm_net` — long A + short B ถูกจับได้ ★★
- [ ] P12 reject intent ที่ **ขยาย** สภาพ hedge · แต่ปล่อย intent ที่ลด gross ★★
- [ ] P12 serialize ต่อ symbol — test สอง intent พร้อมกันคนละบัญชี **ผ่านได้ใบเดียว** ★★
- [ ] สภาพ hedge ที่เกิดแล้ว → `REDUCE_ONLY` เฉพาะ symbol นั้น + alert ERROR · **ไม่ปิดไม้เอง** ★
- [ ] P1/P2 ใช้ farm equity ที่ **dedupe ตามบัญชี** (จาก SPEC-024) ★
- [ ] `farm_hwm` + `farm_day_start_equity` **persist ข้าม restart** — restart แล้ว DD ไม่กลายเป็น 0 ★★
- [ ] "วันใหม่" ของ P1 ใช้ **UTC 00:00** · R6 ยังใช้ broker time (ไม่ถูกแก้) ★
- [ ] บัญชีใหม่เข้ากลางวัน → `farm_day_start_equity` เพิ่ม ไม่ใช่นับเป็นกำไร ★★
- [ ] บัญชี heartbeat หาย → equity ออกจากตัวหาร · **position ยังนับ** ★★
- [ ] บัญชีที่หายรวม > 30% ของ equity → `REDUCE_ONLY` ★
- [ ] P5 นับต่อ correlation group ไม่ใช่ทั้งฟาร์ม ★
- [ ] P9 ทุกเคสใน §4.6 reject + alert `ERROR`
- [ ] เขียน `risk_events` ไม่ได้ → **ไม่ส่ง directive** แต่ยัง reject intent ได้ ★
- [ ] `reevaluate_farm()` โยน exception → alert + `REDUCE_ONLY` ไม่ใช่เงียบ ★★
- [ ] hysteresis ใช้ **monotonic clock** · `FLATTEN`/`HALT` ไม่ปลดอัตโนมัติ ★
- [ ] `grep -rn "except:" brain/risk/` — ไม่เจอ bare except
- [ ] `grep -rniE "or 0|\.get\([^)]+, *0\)" brain/risk/rules/` — ไม่เจอ
- [ ] `python tools/task.py check` เขียว · ทุก test ใช้ fake dispatcher/repo ไม่ต่อ DB จริง

## 7. Test list

### 7.1 `tests/test_risk_manager.py` — orchestrator

| # | test | ตรวจอะไร | กฎ |
|---|------|----------|-----|
| 1 | `test_reject_beats_scale` | ★★ §4.1 | ทั้งหมด |
| 2 | `test_scale_is_min_of_all_rules` | ★★ §4.1 | ทั้งหมด |
| 3 | `test_all_rules_reported_even_after_first_reject` | §4.2 | ทั้งหมด |
| 4 | `test_zero_target_passes_everything` | ★★ §4.2 | ทั้งหมด |
| 5 | `test_rule_order_p9_before_p3` | §4.2 (intent เพี้ยนไม่ถึง P3) | P9 |
| 6 | `test_reevaluate_exception_triggers_reduce_only` | ★★ §4.9 | — |
| 7 | `test_no_directive_when_state_unchanged` | §4.8 | — |
| 8 | `test_risk_event_written_before_directive` | §4.9 | — |
| 9 | `test_directive_not_sent_when_db_write_fails` | ★★ edge 11 | — |
| 10 | `test_intent_still_rejected_when_db_down` | ★ edge 11 | — |
| 11 | `test_reevaluate_does_not_overlap` | edge 13 | — |

### 7.2 `tests/test_cross_hedge.py` — P12 ★★

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_opposite_net_across_accounts_detected` | ★★ §4.4 |
| 2 | `test_farm_net_zero_does_not_hide_hedge` | ★★ (`+0.10`/`−0.10`) |
| 3 | `test_intent_creating_hedge_rejected` | ★★ |
| 4 | `test_intent_expanding_existing_hedge_rejected` | ★ |
| 5 | `test_closing_intent_always_allowed` | ★★ |
| 6 | `test_shrinking_gross_allowed` | ★ |
| 7 | `test_two_concurrent_intents_only_one_passes` | ★★ serialize |
| 8 | `test_pending_intent_counted_before_confirmation` | ★★ |
| 9 | `test_existing_hedge_triggers_symbol_reduce_only` | ★ §4.4 |
| 10 | `test_existing_hedge_does_not_auto_close` | ★★ ห้ามปิดเอง |
| 11 | `test_same_account_opposite_is_r18_not_p12` | ขอบเขตกฎไม่ทับกัน |
| 12 | `test_cross_broker_same_canonical_detected` | ★★ `GOLD` (XM) vs `XAUUSD.iux` (IUX) |

### 7.3 `tests/test_farm_dd.py` — P1 · P2 · P11

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_p1_warn_sends_scaled_half` | |
| 2 | `test_p1_breach_sends_flatten_all_symbols` | ★ `flatten_symbols = []` |
| 3 | `test_p2_warn_sends_reduce_only` | |
| 4 | `test_p2_breach_sends_halt_without_expiry` | ★★ |
| 5 | `test_p1_and_p2_breach_yields_halt` | ★ edge 6 (`stricter_of`) |
| 6 | `test_day_boundary_is_utc_midnight` | ★★ §4.3 |
| 7 | `test_hwm_persists_across_restart` | ★★ |
| 8 | `test_day_start_equity_persists_across_restart` | ★★ |
| 9 | `test_missing_day_start_equity_forces_reduce_only` | ★★ edge 2 |
| 10 | `test_new_account_midday_increases_day_start_equity` | ★★ edge 4 |
| 11 | `test_hwm_never_decreases` | edge 3 |
| 12 | `test_stale_account_equity_excluded_positions_kept` | ★★ §4.7 |
| 13 | `test_large_missing_equity_share_triggers_reduce_only` | ★ §4.7 |
| 14 | `test_flatten_and_halt_never_auto_released` | ★★ §4.8 |
| 15 | `test_relax_requires_hysteresis_and_hold_time` | ★ §4.8 |
| 16 | `test_hysteresis_uses_monotonic_clock` | edge 12 |

### 7.4 `tests/test_sanity.py` — P9 · P5 · P6

| # | test | ตรวจอะไร |
|---|------|----------|
| 1–7 | `test_p9_<เคส>` ครบทั้ง 7 แถวใน §4.6 | ★ |
| 8 | `test_p9_reject_emits_error_alert` | ★ |
| 9 | `test_p5_counts_per_correlation_group` | ★★ §4.5 |
| 10 | `test_p5_rejects_lowest_confidence_new_intent` | ★ |
| 11 | `test_p5_does_not_close_other_strategy_positions` | ★★ |
| 12 | `test_p6_budget_split_equally_by_active_strategies` | §4.5 |
| 13 | `test_p6_scale_formula` | §4.5 |
| 14 | `test_p6_counts_active_sessions_not_holders` | ★ |

## 8. Files

**Touch:** ตาราง §3.1

**ห้ามแตะ:**
- `brain/risk/directive.py` · `brain/risk/dispatcher.py` (SPEC-027) ★★
- `brain/risk/exposure.py` (SPEC-024) · `brain/risk/correlation.py` (SPEC-026) ·
  `brain/risk/staleness.py` (SPEC-061) — **`import` ได้ ห้ามแก้**
- `brain/collector/**` · `contracts/**` · `mt5-ea/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md`

**ถ้าคิดว่าต้องแก้ไฟล์ของ ticket อื่น → เขียน implementation note ห้ามแก้เอง**
ตรรกะความเข้มและการคำนวณ risk ที่มีสองชุดคือ bug ที่ไม่มีใครเห็นจนกว่าจะเสียเงิน

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | P1 breach ควร `FLATTEN` หรือ `HALT` | **ตอบแล้ว: `FLATTEN`** ตาม risk-spec · `FLATTEN` ปิดของที่มีอยู่และไม่ให้เปิดใหม่ · `HALT` สงวนไว้ให้ P2 breach ซึ่งหนักกว่า (ทุนหายจากยอดสูงสุด 12%) |
| Q2 | `farm_open_risk_budget_pct` = 5.0 มาจากไหน | **ตอบแล้ว** §4.5 — ผูกกับเพดาน P3 ของสกุลบัญชี ([ADR-004 §3](../decisions/ADR-004-exposure-unit.md)) ไม่ใช่ตัวเลขใหม่ · ถ้าจะเปลี่ยนต้องแก้ ADR-004 ด้วย |
| Q3 | ควรมี P13 "จำนวนไม้รวมทั้งฟาร์ม" ไหม | **ไม่อยู่ใน ticket นี้** — R4 คุมต่อบัญชีแล้ว · ถ้าอยากได้ระดับฟาร์มให้เปิด ticket ใหม่ **ห้ามแถมเข้ามา** |
| Q4 | P5 ควรปิดไม้ของกลยุทธ์ที่ confidence ต่ำกว่าไหม | **ตอบแล้ว: ไม่** §4.5 — การปิดไม้ต้องเป็นคำสั่งที่ตั้งใจ ไม่ใช่ผลข้างเคียงของกฎนับจำนวน · alert ให้คนเห็นแทน |

> **ไม่มีคำถามที่บล็อก** — D9/D10 ปิดแล้ว · เริ่มได้เมื่อ SPEC-024 + SPEC-026 + SPEC-027 merge
