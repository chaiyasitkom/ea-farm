# SPEC-015 — EMA baseline strategy (พิสูจน์ท่อ ไม่ใช่ทำเงิน)

**Phase:** 1 · **Owner:** Codex · **Depends on:** SPEC-013, SPEC-014, SPEC-064 · **Blocks:** Phase 1 exit criteria · SPEC-033
**อ้าง:** [roadmap 1.6](../04-roadmap.md) · [risk-spec R1](../03-risk-spec.md)

---

## 1. Goal

กลยุทธ์ที่**ง่ายจนไม่มีอะไรให้เถียง** เพื่อพิสูจน์ว่าท่อทั้งเส้นทำงาน:
bar เข้า → ตัดสินใจ → `INTENT` ออก → EA ทำ → `EXEC_REPORT` กลับ → ลง DB

**ไม่ใช่กลยุทธ์ที่จะเอาไปหาเงิน** และ **ห้ามปรับให้ผลดีขึ้น** ([§2](#2-non-goals))

## 2. Non-goals

- ❌ **ห้าม optimize / tune parameter** — ผลกำไรไม่ใช่เกณฑ์วัดของ ticket นี้เลย
- ❌ ห้ามใช้ ML · indicator เพิ่ม · multi-timeframe · news filter (Phase 3–4)
- ❌ ห้าม implement portfolio risk P1–P11 (SPEC-025)
- ❌ ห้าม implement backtest engine (SPEC-032)
- ❌ ห้ามให้มันรันตอนขึ้นเงินจริง — ดู §4.7 ★
- ❌ ห้ามแตะ `contracts/**` · `mt5-ea/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `brain/strategies/__init__.py` | |
| `brain/strategies/base.py` | protocol ของ strategy (ให้ SPEC-035 มาต่อทีหลัง) |
| `brain/strategies/ema_baseline.py` | ★ ตัวจริงของ ticket นี้ |
| `brain/strategies/sizing.py` | ★ สูตร lot ฝั่ง Python (§4.4) |
| `brain/runner.py` | ต่อ gateway → strategy → dispatcher |
| `tests/test_ema_baseline.py` | §7 |
| `tests/test_sizing.py` | §7 |

### 3.2 Strategy protocol

```python
class Strategy(Protocol):
    def on_bar(self, ctx: StrategyContext, bar: BarPayload) -> Decision | None: ...
    def on_state(self, ctx: StrategyContext, state: StatePayload) -> None: ...

@dataclass(frozen=True)
class Decision:
    canonical_symbol: str
    target_volume: float      # + long / − short / 0 flatten
    sl_price: float | None
    tp_price: float | None
    reason: str               # ใส่ลง provenance
```

`StrategyContext` ให้: ประวัติ bar ของ symbol นั้น · `owned_net` ล่าสุด ·
`equity` ล่าสุด · `symbol_spec` จาก `HELLO` · `SymbolRegistry`

### 3.3 กติกา EMA

| | |
|---|---|
| ตัวชี้วัด | `EMA(20)` และ `EMA(50)` บน `close` ของ **bar ที่ปิดแล้วเท่านั้น** |
| long | `EMA20 > EMA50` |
| short | `EMA20 < EMA50` |
| เท่ากันเป๊ะ | **คงสถานะเดิม** ไม่ทำอะไร |
| warm-up | ต้องมี ≥ **50 bar ที่ปิดแล้ว** ก่อนตัดสินใจครั้งแรก |
| ตัดสินใจเมื่อไร | **เฉพาะตอนได้ `BAR` ใหม่** ห้ามตัดสินใจตามเวลา |

---

## 4. Behaviour

### 4.1 ★★ ต้องเป็นฟังก์ชันบริสุทธิ์ — SPEC-033 จะเอาไปเทียบ

[SPEC-033](../backlog.md) (backtest ↔ live parity) จะรัน **กลยุทธ์ตัวนี้ทั้งสองทาง**
แล้วเทียบว่า signal ตรงกัน ≥ 99%

→ การตัดสินใจต้องเป็น **ฟังก์ชันของ (ประวัติ bar, position ปัจจุบัน) เท่านั้น**

| ห้ามพึ่ง | เพราะ |
|----------|-------|
| `datetime.now()` / เวลาจริง | backtest ไม่มีเวลาจริง |
| `random` | ต้อง reproduce ได้ |
| ลำดับที่ message มาถึง | backtest ป้อนตามลำดับ bar |
| สถานะภายในที่สะสมนอก `ctx` | restart แล้วต้องได้ผลเดิม |

**ถ้าข้อนี้พลาด SPEC-033 จะพิสูจน์ backtest ไม่ได้เลย** — และเราจะไม่มีทางรู้ว่า
backtest เชื่อได้ไหมตลอดโครงการ

### 4.2 การตัดสินใจ → `target_volume`

```
สัญญาณ long  → target_volume = +size
สัญญาณ short → target_volume = −size
```

**ไม่มีการ "ถือต่อ" หรือ "เพิ่มไม้"** — ทุกครั้งที่มี bar ใหม่ ให้คำนวณ target ใหม่ทั้งหมด
· ถ้าเท่าเดิม EA จะตอบ `NOOP` เอง ([contract §4.5.1](../02-contracts.md))

**ห้ามส่ง `INTENT` ถ้า target เท่ากับ `owned_net` ปัจจุบัน** (ภายใน tolerance `volume_step/2`)
— ลดขยะบนสายและใน DB · แต่**ถ้าส่งไปก็ไม่ผิด** เพราะ EA จัดการได้

### 4.3 SL / TP

| | |
|---|---|
| SL | `entry ∓ 2.0 × ATR(14)` (long ลบ · short บวก) |
| TP | `entry ± 3.0 × ATR(14)` |
| ATR | คำนวณจาก bar ที่ปิดแล้วเท่านั้น |
| `target_volume = 0` | `sl_price = null` · `tp_price = null` |

**R9 บังคับว่าทุก position ต้องมี SL** → ถ้าคำนวณ ATR ไม่ได้ (bar ไม่พอ)
**ห้ามส่ง INTENT** ไม่ใช่ส่งโดยไม่มี SL

ตัวเลข 2.0/3.0 **ไม่ได้ผ่านการ optimize และห้าม optimize** — เลือกให้ SL
กว้างพอที่จะไม่โดน noise และแคบพอที่จะทดสอบ R10 ได้

### 4.4 ★★ สูตร lot — ต้องเป็นสูตรเดียวกับ R1 รวมทั้งลำดับที่แก้แล้ว

```
risk_money      = equity × risk_per_trade_pct / 100
sl_distance_pts = |entry − sl| / point
value_per_point = tick_value × (point / tick_size)
raw_lot         = risk_money / (sl_distance_pts × value_per_point)
lot             = floor(raw_lot / volume_step) × volume_step

if lot < volume_min → ไม่ส่ง INTENT              ← ★ ก่อน clamp
lot = min(lot, volume_max, max_lot_per_order)    ← clamp ลงเท่านั้น
```

**ลำดับ 2 บรรทัดสุดท้ายห้ามสลับ** — เป็น bug ที่เคยอยู่ใน risk-spec เอง
([ADR-002 §4](../decisions/ADR-002-symbols-capital-hours.md))

ค่าที่ใช้:
- `equity` จาก `STATE` ล่าสุด
- `tick_value` `point` `tick_size` `volume_*` จาก `HELLO.symbol` — **ห้าม hardcode**
- `risk_per_trade_pct` · `max_lot_per_order` จาก `HELLO.local_limits`

> ⚠️ **EA จะคำนวณซ้ำและ clamp ได้** (R1) · ถ้า `INTENT_ACK.volume_clamped_to`
> ไม่ null **บ่อยผิดปกติ** แปลว่าสองฝั่งคำนวณไม่ตรงกัน → **นับและ log**
> · นี่คือกลไกตรวจสอบตัวเองที่ได้มาฟรี ไม่ต้องบังคับให้ตรงเป๊ะ

### 4.5 ★ ห้ามส่ง `INTENT` ก่อนได้ `STATE` ตัวแรก

กฎมาจาก [SPEC-017 §4.2](SPEC-017-reconciliation.md) — หลัง EA รีสตาร์ต ภาพในหัว brain
เก่าแล้ว · `STATE` ตัวแรกคือสิ่งเดียวที่แก้ได้

| สถานะ session | ส่ง INTENT ได้ไหม |
|---------------|-------------------|
| ยังไม่ได้ `STATE` เลย | ❌ **ห้าม** — เก็บ decision ไว้ ทิ้งถ้ามี bar ใหม่มาทับ |
| ได้ `STATE` แล้ว | ✅ |

### 4.6 หลาย session ของ canonical เดียวกัน

หลังเพิ่ม XM ([ADR-003](../decisions/ADR-003-multi-broker.md)) `XAUUSD` อาจมาจาก
2 โบรกเกอร์พร้อมกัน

**ใน Phase 1 ให้ตัดสินใจ *ต่อ session* แยกกัน** — แต่ละ session เห็น bar ของตัวเอง
และได้ `INTENT` ของตัวเอง

⚠️ **นี่ทำให้ exposure ต่อ canonical เป็นสองเท่าโดยตั้งใจ** — เป็นสิ่งที่
**P3/P4 (SPEC-024/025) ต้องเป็นคนคุม ไม่ใช่ strategy**
· บันทึกไว้ให้ชัดว่ารู้ตัว ไม่ใช่มองข้าม

### 4.7 ★ ต้องปิดได้ และต้องไม่ใช่ตัวที่รันตอนเงินจริง

| | |
|---|---|
| เปิด/ปิดด้วย env | `FARM_STRATEGY=ema_baseline` · ไม่ตั้ง = **ไม่มี strategy รัน** |
| ตอนสตาร์ต | log `WARN` ทุกครั้ง: `baseline strategy — for pipeline validation only, not for production` |
| ตอนขึ้น live | **SPEC-057 (live readiness audit) ต้องเช็คว่าไม่ได้ใช้ตัวนี้** |

กลยุทธ์ชั่วคราวที่ไม่มีใครถอดออกคือกลยุทธ์ถาวร — จึงต้องเห็นมันทุกครั้งที่สตาร์ต

---

## 5. Edge cases

1. **bar ไม่พอ (< 50)** → ไม่ตัดสินใจ · log DEBUG ครั้งเดียวไม่ใช่ทุก bar
2. **backfill 300 bar มาถึง** → คำนวณ EMA จากทั้งชุด แล้วพร้อมตัดสินใจทันทีหลังจากนั้น
3. **bar ซ้ำ (`bar_time` เดิม)** → **ข้าม ไม่คำนวณซ้ำ** — เกิดได้จาก backfill หลัง reconnect
4. **bar ย้อนหลัง (`bar_time` เก่ากว่าตัวล่าสุด)** → ข้าม + WARN (ไม่ควรเกิด)
5. **bar ขาดช่วง** (สุดสัปดาห์) → ปกติ · EMA คำนวณต่อจากที่มี ไม่ต้องเติม
6. **`equity` ยังไม่มี** (ไม่เคยได้ STATE) → §4.5 ครอบแล้ว
7. **ATR = 0** (ตลาดนิ่งสนิท) → **ไม่ส่ง INTENT** (SL จะเป็นราคาเดียวกับ entry)
8. **`raw_lot < volume_min`** → ไม่ส่ง INTENT + log · **นี่คือสถานะปกติที่ทุน $30**
   ([ADR-002 §3](../decisions/ADR-002-symbols-capital-hours.md)) — ห้ามตกใจ ห้าม "แก้"
9. **session หลุดกลางทาง** → ล้าง context ของ session นั้น · รอ `STATE` ใหม่
10. **symbol ไม่อยู่ใน registry** → ไม่ควรถึงตรงนี้ (gateway กันแล้ว) · ถ้าถึง = ERROR

---

## 6. Acceptance criteria

- [ ] `FARM_STRATEGY` ไม่ตั้ง → **ไม่มี INTENT ออกเลย**
- [ ] ตั้งแล้ว → log WARN ว่าเป็น baseline ทุกครั้งที่สตาร์ต
- [ ] **ป้อน bar ชุดเดียวกัน 2 ครั้ง → ได้ `Decision` เหมือนกันทุกตัว** ★★ §4.1
- [ ] **`grep -rniE "datetime\.now|time\.time|random\." brain/strategies/` — ไม่เจอ** ★★
- [ ] bar < 50 → ไม่ตัดสินใจ
- [ ] EMA cross ขึ้น → `target_volume > 0` · cross ลง → `< 0`
- [ ] target เท่ากับ `owned_net` → **ไม่ส่ง INTENT**
- [ ] `target_volume ≠ 0` → **มี `sl_price` เสมอ** (R9) ★
- [ ] ATR คำนวณไม่ได้ → **ไม่ส่ง INTENT** ไม่ใช่ส่งโดยไม่มี SL ★
- [ ] `raw_lot < volume_min` → ไม่ส่ง + log · **ไม่ crash** (สถานะปกติที่ทุนน้อย)
- [ ] **ยังไม่ได้ `STATE` → ไม่ส่ง INTENT** ★ §4.5
- [ ] bar ซ้ำ/ย้อนหลัง → ข้าม ไม่คำนวณซ้ำ
- [ ] สูตร lot ตรงกับ §4.4 **รวมลำดับ reject-ก่อน-clamp** — มี test เฉพาะ ★★
- [ ] `volume_clamped_to` ที่ไม่ null ถูกนับและ log
- [ ] `provenance.strategy_id = "ema_baseline"` · `model_version = null` · `confidence` มีค่า
- [ ] `python tools/task.py check` ผ่าน (test ทั้งหมดเป็น pure ไม่ต้องมี DB/MT5)
- [ ] `grep -rn "except:" brain/strategies/ brain/runner.py` — ไม่เจอ bare except

## 7. Test list

### `tests/test_sizing.py` — สูตร lot

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_lot_from_risk_and_sl_distance` | สูตรพื้นฐาน |
| 2 | `test_rejects_when_raw_lot_below_volume_min` | ★★ ลำดับ reject ก่อน clamp |
| 3 | `test_clamp_only_reduces_never_raises` | ★★ [ADR-002 §4](../decisions/ADR-002-symbols-capital-hours.md) |
| 4 | `test_respects_volume_step_floor` | ปัดลงไม่ใช่ปัดใกล้สุด |
| 5 | `test_uses_symbol_spec_not_hardcoded` | ★ |
| 6 | `test_zero_sl_distance_rejects` | หารศูนย์ |

### `tests/test_ema_baseline.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 7 | `test_same_bars_produce_same_decisions` | ★★ §4.1 determinism |
| 8 | `test_no_decision_before_50_bars` | |
| 9 | `test_cross_up_targets_long` | |
| 10 | `test_cross_down_targets_short` | |
| 11 | `test_equal_emas_holds_position` | |
| 12 | `test_no_intent_when_target_equals_owned_net` | |
| 13 | `test_always_has_sl_when_opening` | ★ R9 |
| 14 | `test_no_intent_when_atr_zero` | edge 7 |
| 15 | `test_no_intent_before_first_state` | ★ §4.5 |
| 16 | `test_duplicate_bar_ignored` | edge 3 |
| 17 | `test_out_of_order_bar_ignored` | edge 4 |
| 18 | `test_backfill_then_live_bar_continuous` | edge 2 |
| 19 | `test_disabled_without_env_var` | §4.7 |
| 20 | `test_two_sessions_same_canonical_decide_independently` | §4.6 — **บันทึกว่าเป็นพฤติกรรมที่ตั้งใจ** |

**test 7 กับ test 2/3 คือสามตัวที่สำคัญที่สุด:**
- 7 คือสิ่งที่ทำให้ SPEC-033 พิสูจน์ backtest ได้
- 2/3 คือ bug ที่เคยอยู่ใน risk-spec เอง — ห้ามให้มันกลับมาทางฝั่ง Python

## 8. Files

**Touch:** `brain/strategies/**` · `brain/runner.py` · `tests/test_ema_baseline.py`
· `tests/test_sizing.py`

**ห้ามแตะ:** `brain/gateway/**` · `brain/store/**` · `mt5-ea/**` · `contracts/**`
· `docs/**` · `AGENTS.md` · `CLAUDE.md`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | EMA(20/50) บน H1 จะเกิดสัญญาณกี่ครั้งต่อสัปดาห์ | **ไม่บล็อก** — **วัดจากข้อมูลจริงแล้วรายงาน** · ถ้าน้อยกว่า ~2 ครั้ง/สัปดาห์ ทั้ง 6 คู่ จะพิสูจน์ท่อได้ไม่พอใน 5 วัน → **บอกมา อย่าปรับ parameter เอง** |
| Q2 | `confidence` ควรใส่ค่าอะไร (ไม่มี model) | **ไม่บล็อก** — ใส่ `1.0` คงที่ · P9 ต้องการแค่ค่าใน [0,1] · **ห้ามแกล้งคำนวณให้ดูฉลาด** |
| Q3 | ATR(14) หรือช่วงอื่น | **ไม่บล็อก** — ใช้ 14 · **ห้าม tune** (§2) |

> **ไม่มีคำถามที่บล็อก — เริ่มจาก `sizing.py` + test 1–6 ได้เลย เป็นฟังก์ชันบริสุทธิ์**

---

## ภาคผนวก — ทำไมกลยุทธ์ที่ "ไม่ตั้งใจทำเงิน" ถึงต้องเขียนให้ดี

มันจะถูกใช้ 3 อย่างที่ไม่มีอะไรเกี่ยวกับกำไรเลย:

1. **พิสูจน์ท่อ** — Phase 1 exit ต้องรัน 5 วันโดยไม่มี order ผิด · ต้องมีอะไรสั่งเทรด
2. **ฐานเทียบของ SPEC-033** — รันทั้ง backtest และ live แล้วเทียบ signal
   ถ้าไม่ตรง ≥ 99% แปลว่า **backtest ทั้งระบบเชื่อไม่ได้**
3. **ตัวถ่วงเวลาให้ risk layer** — Phase 2 ต้องมีอะไรสร้าง order จริงให้ R1–R17 ได้ทำงาน

ข้อ 2 คือเหตุผลที่ §4.1 (determinism) เข้มขนาดนั้น — ถ้ากลยุทธ์นี้ไม่ deterministic
เราจะไม่มีวันรู้ว่า backtest ที่สร้างในภายหลังเชื่อได้หรือไม่ และจะไปรู้ตอนเอาเงินจริงลง

กลยุทธ์โง่ๆ ที่ deterministic มีค่ามากกว่ากลยุทธ์ฉลาดที่ reproduce ไม่ได้
