# SPEC-024 — Currency exposure decomposition + P3

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-060, SPEC-061, SPEC-064, SPEC-013
**Blocks:** SPEC-025, SPEC-026 · **ผูกพันกับ:** [ADR-004](../decisions/ADR-004-exposure-unit.md) · [ADR-005 §5](../decisions/ADR-005-cross-account-hedge.md)
**อ้าง:** [03-risk-spec §L2](../03-risk-spec.md) · [02-contracts §4.4](../02-contracts.md)

> ticket นี้เขียนได้เพราะ **D9 ปิดแล้ว** — หน่วยของ exposure คือ `risk-normalized`
> ทุกสูตรใน §4 มาจาก [ADR-004](../decisions/ADR-004-exposure-unit.md) โดยตรง **ห้าม implement ต่างจากนั้น**

---

## 1. Goal

มีเครื่องมือเดียวที่ตอบได้ว่า *"ตอนนี้ทั้งฟาร์มเสี่ยงกับสกุลเงินไหนอยู่กี่เปอร์เซ็นต์"*
และ *"ถ้ารับ intent ใบนี้จะเกินเพดานไหม"* โดยนับข้ามบัญชีและข้ามโบรกเกอร์อย่างถูกต้อง

จบ ticket นี้ = P3 บังคับใช้ได้จริง และ SPEC-025/026 มีฐานตัวเลขชุดเดียวกันใช้

## 2. Non-goals

- ❌ ห้าม implement P1/P2/P5/P6/P9/P10/P11/P12 — นั่นคือ SPEC-025
- ❌ ห้าม implement correlation หรือ P4 — SPEC-026 (ticket นี้ให้ `PositionRisk` ให้มันใช้)
- ❌ ห้ามเก็บราคาเอง — อ่านจาก `MarketDataCollector` (SPEC-060) เท่านั้น
- ❌ ห้ามเขียน stale logic ใหม่ — เรียก `StaleDataGuard.require()` (SPEC-061)
- ❌ ห้ามแปลงชื่อ symbol เอง — `SymbolRegistry` (SPEC-064) เท่านั้น
- ❌ ห้ามส่ง `RISK_DIRECTIVE` — ticket นี้ **ตัดสิน intent** ไม่ใช่สั่งฟาร์ม
- ❌ ห้ามแตะ `contracts/**` · `mt5-ea/**` · `docs/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ทำอะไร |
|------|--------|
| `brain/risk/exposure.py` | **สร้าง** — `ExposureEngine` + dataclass ทั้งหมด |
| `brain/risk/config.py` | **สร้าง** — `ExposureConfig` (ค่า default + โหลดจากไฟล์ config) |
| `tests/test_exposure.py` | **สร้าง** — §7 |
| `tools/task.py` | **แก้** — เพิ่ม suite เข้า `check` (ถ้ายังไม่ครอบ `tests/**`) |

### 3.2 API

```python
AccountKey = tuple[str, int]          # (broker, login) -- broker = HELLO.account.server

@dataclass(frozen=True)
class PositionRisk:
    account: AccountKey
    ticket: int
    canonical: str
    side: Side                        # BUY / SELL
    volume: float
    risk_money: float                 # สกุลบัญชี
    risk_pct: float                   # % ของ farm equity
    sl_assumed: bool                  # True = ไม้นี้ไม่มี SL จริง ใช้ R10 แทน (§4.6)

@dataclass(frozen=True)
class SymbolExposure:
    canonical: str
    gross_pct: float                  # Σ|risk_pct|            ★ ADR-005 §5
    net_by_account: dict[AccountKey, float]   # net volume ต่อบัญชี (ให้ P12 ใช้)

@dataclass(frozen=True)
class ExposureSnapshot:
    farm_equity: float
    accounts_counted: tuple[AccountKey, ...]
    accounts_excluded: tuple[AccountKey, ...]         # §4.7
    by_symbol: dict[str, SymbolExposure]
    by_currency: dict[str, float]                     # signed % (ยังไม่ abs)
    positions: tuple[PositionRisk, ...]
    computed_at: datetime

@dataclass(frozen=True)
class P3Verdict:
    ok: bool
    reason: str                       # "" เมื่อ ok · ต้องระบุสกุล + ค่าจริง + เพดาน เมื่อไม่ ok
    projected: dict[str, float]       # exposure ต่อสกุลหลังรับ intent (abs)

class ExposureEngine:
    def __init__(self, registry: SymbolRegistry, collector: MarketDataCollector,
                 guard: StaleDataGuard, clock: Clock, config: ExposureConfig): ...

    def snapshot(self,
                 states: Mapping[SessionId, AccountState],
                 pending: Sequence[PendingIntent] = ()) -> ExposureSnapshot: ...

    def evaluate(self, intent: Intent, snap: ExposureSnapshot) -> P3Verdict: ...
```

### 3.3 `ExposureConfig`

| key | default | หมายเหตุ |
|-----|---------|----------|
| `max_currency_exposure_pct` | **2.0** | ทุกสกุลที่ไม่ใช่สกุลบัญชี |
| `max_account_currency_exposure_pct` | **5.0** | สกุลบัญชี (ตอนนี้ = USD) — [ADR-004 §3](../decisions/ADR-004-exposure-unit.md) |

**ห้ามมีค่า default อยู่ที่อื่นนอกจากไฟล์นี้** · ห้าม hardcode `"USD"` — สกุลบัญชีมาจาก
`HELLO.account.currency` ของแต่ละบัญชี (§4.8)

---

## 4. Behaviour

### 4.1 risk ต่อ 1 position

```
risk_money = |price_open − sl| / point × value_per_point × volume
risk_pct   = risk_money / farm_equity × 100
```

| กรณี | `value_per_point` | symbol |
|------|-------------------|--------|
| quote = สกุลบัญชี | `contract_size × point` | `EURUSD` `GBPUSD` `AUDUSD` `XAUUSD` |
| base = สกุลบัญชี | `contract_size × point / price_current` | `USDJPY` `USDCAD` |
| ไม่มีสกุลบัญชีทั้งสองขา | ❌ คำนวณไม่ได้ → §4.5 fail-closed | — |

- `contract_size` · `point` มาจาก `HELLO.symbol` ของ session นั้น (คงที่ตลอดอายุ symbol)
- `price_current` = mid ของ `collector.latest_quote(canonical)` — **ห้ามใช้ `tick_value` จาก `HELLO`**
  (ค่านั้นอ่านครั้งเดียวตอน `OnInit` และเคลื่อนตามอัตราแลกเปลี่ยนสำหรับคู่ที่ quote ≠ สกุลบัญชี
  → ใช้แล้วจะได้ exposure **ต่ำกว่าจริง** ซึ่งเป็นทิศที่อันตราย)

### 4.2 ★ farm equity — dedupe ตามบัญชี ไม่ใช่บวกทุก session

```
farm_equity = Σ equity ของ (broker, login) ที่ไม่ซ้ำ
```

`session_id = acct-{login}-{symbol}-{timeframe}` → บัญชีเดียวมีได้หลาย session
และทุกอันรายงาน `STATE.equity` ของบัญชีเดียวกัน

**ถ้าบวกทุก session:** 3 EA บนบัญชีเดียว → farm equity ใหญ่ 3 เท่า →
**ทุกเพดาน % หลวมลง 3 เท่าโดยไม่มีอะไรพัง** — นี่คือ bug ที่ test ต้องจับ (§7 test 3)

ใช้ `STATE.equity` ที่ **ใหม่ที่สุด** ของบัญชีนั้น (เทียบด้วย `ts_server`)

### 4.3 ★ position — dedupe ตาม ticket

`STATE.positions[]` กรองด้วย `(magic, symbol)` เท่านั้น ไม่ได้กรองด้วย timeframe →
session `EURUSD-H1` และ `EURUSD-M15` ที่ magic เดียวกันจะรายงาน **ไม้เดียวกันทั้งคู่**

```
key = (broker, login, ticket)          ★ ห้ามมี session_id อยู่ใน key
```

ถ้าเจอ ticket เดียวกันจากสอง session ที่ค่าไม่ตรงกัน → ใช้อันที่ `ts_server` ใหม่กว่า + log WARN

### 4.4 รวมเป็น exposure

```
symbol:    gross_pct(c)  = Σ |risk_pct|  ของทุก position ที่ canonical = c        ★ gross
currency:  by_currency[X] = Σ signed risk_pct                                     ★ signed

BUY  c(base B, quote Q) →  +risk_pct ให้ B  ·  −risk_pct ให้ Q
SELL c(base B, quote Q) →  −risk_pct ให้ B  ·  +risk_pct ให้ Q

ละเมิดเมื่อ  |by_currency[X]| > cap(X)
```

`base`/`quote` มาจาก `registry.base_quote(canonical)` — **ห้ามแยกจากชื่อ symbol เอง**
(`XAUUSD` → `("XAU","USD")` เดาไม่ได้ทั่วไป และ `GOLD` ยิ่งเดาไม่ได้)

ระดับ symbol เป็น **gross** โดยตั้งใจ ([ADR-005 §5](../decisions/ADR-005-cross-account-hedge.md)) —
hedge ต้องไม่ทำให้ตัวเลขความเสี่ยงลดลง · ระดับสกุลเป็น **signed** เพราะการหักล้างข้ามคู่
(long `EURUSD` + short `EURGBP`) เป็นการลดความเสี่ยง EUR จริง

### 4.5 ★★ fail-closed — ทุกทางที่คำนวณไม่ได้ต้องจบที่ reject

| สถานการณ์ | ต้องทำ |
|-----------|--------|
| `registry.to_canonical()` ไม่รู้จัก raw symbol | **reject intent** + `ERROR` · ห้ามข้ามไม้นั้นแล้วรวมต่อ |
| `guard.require()` บอก `STALE`/`MISSING`/`MARKET_CLOSED` | **reject intent** (`MARKET_CLOSED` ไม่ alert — [SPEC-061 §4.3](SPEC-061-stale-data-guard.md)) |
| ไม่มี `contract_size` ของ symbol (ยังไม่เคยมี `HELLO`) | reject intent |
| `farm_equity <= 0` | reject intent ทุกใบ + alert `FATAL` |
| ไม่มีสกุลบัญชีทั้ง base และ quote | reject + `ERROR` (ยังเกิดไม่ได้กับชุด 6 คู่ — ต้องไม่เงียบวันที่เพิ่ม cross pair) |

**ห้ามมีเส้นทางไหนที่ข้อมูลหายแล้ว exposure ออกมาต่ำ** · ห้ามใช้ `or 0` / `dict.get(k, 0)` /
`fillna(0)` กับค่าที่เป็น exposure หรือราคา

### 4.6 ไม้ที่ไม่มี SL — ใช้ค่าที่แย่ที่สุดที่กฎอนุญาต

```
sl == 0 หรือ null  →  sl สมมติ = price_open × (1 ± max_sl_distance_pct/100)   ทิศตรงข้ามกับกำไร
                   →  PositionRisk.sl_assumed = True
                   →  alert P3_POSITION_WITHOUT_SL severity ERROR (ทุกรอบที่ยังพบ)
```

`max_sl_distance_pct` = R10 จาก `registry.risk_profile(canonical)`
· **ห้ามข้ามไม้นั้น** (exposure ต่ำกว่าจริง) และ **ห้ามใช้ ∞** (ฟาร์มหยุดทั้งระบบเพราะไม้เดียว)

### 4.7 บัญชีที่ heartbeat หาย (คาบเกี่ยวกับ P11)

| | ทำอะไร |
|---|--------|
| equity ของบัญชีนั้น | **เอาออก**จาก `farm_equity` (ไม่รู้ว่ายังเป็นค่านั้นอยู่ไหม) → ใส่ใน `accounts_excluded` |
| position ของบัญชีนั้น | **ยังนับต่อ**จาก `STATE` ล่าสุด ★★ |

ไม้ยังเปิดอยู่จริงแม้ heartbeat หาย — ถ้าเอาออกทั้งบัญชี exposure จะ**ลดลงเพราะการตาบอด**
ซึ่งเป็น fail-open ชัดๆ · ผลของกฎนี้คือ `risk_pct` สูงขึ้น (ตัวหารเล็กลง ตัวตั้งเท่าเดิม) = conservative ✅

### 4.8 สกุลบัญชี = ตัวที่ได้เพดาน 5.0%

```
account_currency(a) = HELLO.account.currency ของบัญชี a
```

- ตอนนี้ทุกบัญชีเป็น `USD` → `USD` ได้ 5.0% · สกุลอื่นได้ 2.0%
- **ถ้าฟาร์มมีบัญชีหลายสกุลปนกัน** → สกุลที่ได้เพดานพิเศษคือสกุลที่ **ทุกบัญชี**ใช้ร่วมกันเท่านั้น
  ถ้าไม่ตรงกันทั้งฟาร์ม → **ไม่มีสกุลไหนได้เพดานพิเศษ** (ทุกสกุลใช้ 2.0%) + alert `WARN`
  · การรวม equity ข้ามสกุลบัญชีที่ต่างกันเป็นเรื่องที่ ticket นี้ **ไม่รองรับ** — ต้องเปิด ticket ใหม่

### 4.9 ประเมิน intent — ต้องดูสภาพ "หลังรับ" ไม่ใช่สภาพปัจจุบัน

```
1. คำนวณ risk_pct ที่ intent จะสร้าง:
      entry ประมาณ = ask (BUY) / bid (SELL) จาก quote ล่าสุด
      volume        = |target_volume − current_net| ที่ต้องเปิดเพิ่ม   (ส่วนที่ลดลงไม่สร้าง risk ใหม่)
      sl            = intent.sl_price      ★ ห้ามใช้ SL ของไม้เดิม
2. projected[X] = |by_currency[X] ± risk_pct ตามทิศของ intent|
3. ok = ทุกสกุลที่กระทบ projected[X] <= cap(X)
```

| เคส | ผล |
|-----|-----|
| `target_volume = 0` (ปิดทั้งหมด) | ✅ **ผ่านเสมอ** ไม่ต้องคำนวณ |
| intent ที่ลดขนาดในฝั่งเดิม | ✅ ผ่านเสมอ (exposure ลดลง) |
| intent ที่กลับข้าง (`+0.10` → `−0.05`) | ประเมินเป็น **เปิดใหม่ 0.05 ฝั่งตรงข้าม** (ตรงกับ [SPEC-027 §4.5](SPEC-027-risk-directive.md)) |
| เกินเพดาน | ❌ **reject** — P3 ไม่ scale (การ scale เป็นงานของ P4/P6/P7) |

`reason` ต้องอ่านแล้วรู้ทันทีว่าเกิดอะไร:
`"P3_CURRENCY_EXPOSURE EUR projected=2.31% cap=2.00% intent=EURUSD BUY 0.05"`
— ห้ามเป็น `"P3 exceeded"` เปล่าๆ

### 4.10 นับ intent ที่ยังไม่ยืนยัน

`snapshot(states, pending)` ต้องบวก risk ของ intent ที่ส่งไปแล้วแต่ยังไม่เห็นใน `STATE`
(จาก intent cache [SPEC-012](SPEC-012-intent-cache.md)) — ไม่งั้น intent สองใบที่ไปคนละบัญชี
ในช่วง 5 วินาทีเดียวกันจะเห็นภาพเก่าทั้งคู่แล้วผ่านทั้งคู่

intent ที่ค้างเกิน timeout ให้ถือว่า **ยังค้างอยู่** จนกว่าจะมี `INTENT_ACK REJECTED`
หรือ `STATE` ที่ยืนยันว่าไม่เกิด (fail-closed)

---

## 5. Edge cases

1. **ฟาร์มไม่มีบัญชีเลย / ยังไม่มี `STATE` ใบไหน** → `farm_equity = 0` → reject ทุก intent (§4.5)
2. **บัญชีเดียวมี 6 session** → `farm_equity` ต้องเท่ากับ equity ของบัญชีเดียว ★
3. **ticket เดียวรายงานจาก 2 session** → นับครั้งเดียว ★
4. **`XAU` ไม่ใช่รหัส ISO** → ปฏิบัติเหมือนสกุลเงินทุกประการ ไม่ต้องมีเคสพิเศษ
5. **`USDJPY` point = 0.001 · `XAUUSD` contract_size = 100** → ห้าม hardcode ค่าไหนเลย
6. **`sl` อยู่ผิดฝั่ง** (BUY แต่ `sl > price_open`) → ยังคำนวณด้วย `| |` ได้ · **ห้ามระเบิด**
   · การ reject เป็นหน้าที่ P9 (SPEC-025) ไม่ใช่ที่นี่
7. **`volume = 0` ใน `STATE.positions`** → ข้ามไม้นั้น + WARN (ไม่ควรมี)
8. **quote ของ `USDJPY` หายแต่จะเทรด `EURUSD`** → ถ้าฟาร์มถือ `USDJPY` อยู่ = **reject**
   (แปลง exposure ของไม้ที่ถืออยู่ไม่ได้ = ไม่รู้ยอดรวมจริง) · ถ้าไม่ถืออยู่ = ผ่าน
9. **ตลาดปิด** → reject แต่ **ไม่ alert** ([SPEC-061 §4.3](SPEC-061-stale-data-guard.md))
10. **exposure เกินเพดานอยู่แล้วโดยไม่มี intent ใหม่** (equity ตกจาก drawdown) →
    ไม่ใช่หน้าที่ ticket นี้จะแก้ · แต่ต้อง **เปิดเผยค่า** ให้ SPEC-025 เห็นเพื่อสั่ง `REDUCE_ONLY`
11. **สองบัญชีคนละสกุล (`USD` + `EUR`)** → §4.8 · ทุกสกุลใช้ 2.0% + WARN
12. **`risk_pct` ของไม้เดียวเกินเพดานตั้งแต่ต้น** (SL กว้างผิดปกติ) → reject ปกติ ·
    ตัวเลขใน `reason` ต้องบอกว่าไม้เดียวก็เกินแล้ว

---

## 6. Acceptance criteria

- [ ] `farm_equity` **dedupe ตาม `(broker, login)`** — 3 session บัญชีเดียวให้ equity เท่าบัญชีเดียว ★★
- [ ] position **dedupe ตาม ticket** — ไม้เดียวรายงาน 2 session นับครั้งเดียว ★★
- [ ] `risk_money` ของ `USDJPY` ใช้ `contract_size × point / price` — **ไม่ใช่ `tick_value` จาก `HELLO`** ★★
- [ ] `by_symbol[c].gross_pct` เป็น **gross** — long บัญชี A + short บัญชี B ให้ผลรวม **ไม่ใช่ 0** ★★
- [ ] `by_currency` เป็น **signed** — long `EURUSD` + short `EURGBP` หัก EUR กันจริง ★
- [ ] USD ใช้เพดาน **5.0%** · สกุลอื่น **2.0%** · สกุลบัญชีอ่านจาก `HELLO` ไม่ hardcode ★★
- [ ] ไม้ไม่มี SL → ใช้ R10 + `sl_assumed=True` + alert · **ไม่ถูกข้าม** ★★
- [ ] บัญชี heartbeat หาย → equity หลุดจากตัวหาร แต่ **position ยังถูกนับ** ★★ (§4.7)
- [ ] `target_volume = 0` → `ok=True` ทุกกรณี **รวมตอนข้อมูล stale** ★★
- [ ] quote stale ของ symbol ที่ **ถืออยู่** → reject · ของ symbol ที่ไม่ถือ → ผ่าน ★
- [ ] `P3Verdict.reason` มีชื่อสกุล + ค่าจริง + เพดาน — `grep -rn '"P3 exceeded"' brain/` ไม่เจอ
- [ ] `grep -rniE "or 0|\.get\([^)]+, *0\)|fillna\(0\)|except:" brain/risk/exposure.py` — **ไม่เจอ** ★★
- [ ] `grep -rn '"USD"' brain/risk/exposure.py` — **ไม่เจอ** (สกุลบัญชีต้องมาจากข้อมูล)
- [ ] ไม่มีการตัด/ต่อ string ของชื่อ symbol — `grep -rn "replace\|removesuffix\|\[:6\]" brain/risk/exposure.py` ไม่เจอ
- [ ] `python tools/task.py check` เขียว · unit test ทั้งหมดใช้ fake collector/registry ไม่ต่อ MT5 จริง

## 7. Test list — `tests/test_exposure.py`

| # | test | ตรวจอะไร | กฎ |
|---|------|----------|-----|
| 1 | `test_risk_money_quote_ccy_is_account_ccy` | `EURUSD` สูตรตรง §4.1 | P3 |
| 2 | `test_risk_money_base_ccy_is_account_ccy_uses_price` | ★★ `USDJPY` หารด้วยราคา | P3 |
| 3 | `test_farm_equity_dedupes_sessions_of_same_account` | ★★ §4.2 | P3 |
| 4 | `test_position_dedupes_same_ticket_two_sessions` | ★★ §4.3 | P3 |
| 5 | `test_symbol_exposure_is_gross_across_accounts` | ★★ ADR-005 §5 | P3/P12 |
| 6 | `test_currency_exposure_is_signed_across_pairs` | ★ §4.4 | P3 |
| 7 | `test_account_currency_gets_higher_cap` | ★★ USD 5% vs EUR 2% | P3 |
| 8 | `test_account_currency_read_from_hello_not_hardcoded` | ★ บัญชี EUR → EUR ได้ 5% | P3 |
| 9 | `test_mixed_account_currencies_disable_special_cap` | §4.8 · edge 11 | P3 |
| 10 | `test_position_without_sl_uses_r10_and_flags` | ★★ §4.6 | P3 |
| 11 | `test_position_without_sl_not_skipped` | ★★ exposure ต้องไม่ลดลง | P3 |
| 12 | `test_stale_heartbeat_account_equity_excluded_positions_kept` | ★★ §4.7 | P3/P11 |
| 13 | `test_zero_target_always_passes_even_when_stale` | ★★ §4.9 | P3 |
| 14 | `test_stale_quote_of_held_symbol_rejects` | ★ edge 8 | P3/P10 |
| 15 | `test_stale_quote_of_unheld_symbol_passes` | edge 8 | P3/P10 |
| 16 | `test_market_closed_rejects_without_alert` | edge 9 | P3/P10 |
| 17 | `test_unknown_symbol_rejects_not_skipped` | ★★ §4.5 | P3 |
| 18 | `test_zero_farm_equity_rejects_all` | edge 1 | P3 |
| 19 | `test_projected_uses_intent_sl_not_existing_sl` | ★ §4.9 | P3 |
| 20 | `test_shrink_in_same_direction_always_passes` | §4.9 | P3 |
| 21 | `test_side_flip_evaluated_as_new_open` | ★ §4.9 | P3 |
| 22 | `test_pending_intents_counted_in_snapshot` | ★★ §4.10 | P3 |
| 23 | `test_two_concurrent_intents_cannot_both_pass` | ★★ §4.10 | P3 |
| 24 | `test_reject_reason_contains_currency_value_and_cap` | §4.9 | P3 |
| 25 | `test_xauusd_treated_as_currency_xau` | edge 4 | P3 |
| 26 | `test_no_hardcoded_contract_size_or_point` | edge 5 (อ่านค่าจาก fixture คนละชุดแล้วผลต่างกัน) | P3 |
| 27 | `test_sl_on_wrong_side_does_not_crash` | edge 6 | P3 |
| 28 | `test_snapshot_matches_worked_example_from_adr` | ★★ ตัวเลขใน [ADR-004 §2.4](../decisions/ADR-004-exposure-unit.md) เป๊ะ | P3 |

**test 28 คือด่านที่จับการตีความผิดได้ดีที่สุด** — ตาราง 3 ไม้ใน ADR-004 §2.4
ต้องออกมาเป็น `EUR 0.350% · USD 0.525% · JPY 0.175%` เป๊ะ
· ค่าคาดหวังต้อง**เขียนมือ** ห้ามคำนวณด้วยสูตรเดียวกับที่ implement

## 8. Files

**Touch:** ตาราง §3.1

**ห้ามแตะ:**
- `contracts/**` · `mt5-ea/**` · `docs/**` · `AGENTS.md` · `CLAUDE.md`
- `brain/collector/**` (อ่านได้ ห้ามแก้) · `brain/risk/staleness.py` (SPEC-061)
- `brain/risk/directive.py` · `dispatcher.py` (SPEC-027)
- `brain/risk/` ไฟล์อื่นที่ยังไม่มี — **สงวนให้ SPEC-025/026**

**★ ข้อตกลงกับ SPEC-025/026:** `ExposureEngine` · `PositionRisk` · `ExposureSnapshot`
เป็นของ ticket นี้ · **SPEC-025 และ SPEC-026 ต้อง `import` ห้ามคำนวณ risk เอง**
ถ้าคำนวณซ้ำจะได้ตัวเลขสองชุดที่ค่อยๆ ต่างกัน แล้วไม่มีใครรู้ว่าอันไหนถูก

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | `price_current` ควรใช้ mid หรือฝั่งที่แย่กว่า (bid สำหรับ long) | **ไม่บล็อก — ตอบแล้ว: mid** · ความต่างระดับ spread ไม่มีผลกับเพดาน 2% · แต่ `entry ประมาณ` ใน §4.9 **ต้องใช้ฝั่งที่แย่กว่า** เพราะเป็นราคาที่จะได้จริง |
| Q2 | ควร cache snapshot ไหม (คำนวณทุก intent แพงไหม) | **ไม่บล็อก** — ไม้ทั้งฟาร์มมีไม่เกินหลักสิบ · **ห้าม cache ข้าม intent** ถ้าไม่มี invalidation ที่พิสูจน์ได้ · วัดก่อนค่อย optimize |
| Q3 | บัญชีหลายสกุลควรรองรับเลยไหม | **ไม่บล็อก — ตอบแล้ว: ไม่** (§4.8) · ตอนนี้ทุกบัญชีเป็น USD · เปิด ticket ใหม่วันที่มีจริง ไม่ใช่เขียนโค้ดที่ไม่มีใครรัน |

> **ไม่มีคำถามที่บล็อก** — D9/D10 ปิดแล้ว ([ADR-004](../decisions/ADR-004-exposure-unit.md) · [ADR-005](../decisions/ADR-005-cross-account-hedge.md))
> เริ่มได้เมื่อ SPEC-060 + SPEC-061 + SPEC-064 merge
