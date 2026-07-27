# SPEC-060 — MarketDataCollector: ป้อนราคาทุก symbol ให้ brain

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-006, SPEC-013, SPEC-064
**Blocks:** SPEC-024, SPEC-026, SPEC-041, SPEC-061
**ปิดช่องว่าง:** [G1](../06-gap-audit.md)

---

## 1. Goal

ให้ brain มีราคาของ **ทุก symbol ในชุด** ไม่ว่าจะมี EA เทรดอยู่หรือไม่

**ปัญหาที่แก้:** EA ส่ง `BAR` เฉพาะ symbol ของตัวเอง · ถ้าวันนี้เทรดแค่ `EURUSD`
brain จะไม่มีข้อมูล `GBPUSD` เลย → P4 คำนวณ correlation ไม่ได้ →
**ได้ correlation = 0 แล้วปล่อยผ่านทุก intent = fail-open ในชั้น risk** ([G1](../06-gap-audit.md))

## 2. Non-goals

- ❌ **ห้ามส่ง order · ห้าม modify · read-only 100%** ★
- ❌ ห้ามคำนวณ correlation (SPEC-026) หรือ exposure (SPEC-024) — ที่นี่แค่**ป้อนข้อมูล**
- ❌ ห้าม implement stale guard (SPEC-061) — แต่ต้อง**ออก metadata ให้มันใช้** (§4.5)
- ❌ ห้ามเดา broker offset เอง — ดู §4.3 ★★
- ❌ ห้ามดึงข้อมูลย้อนหลังยาว (SPEC-007) — ที่นี่คือ**ข้อมูลสด**

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | หมายเหตุ |
|------|----------|
| `brain/collector/mt5_reader.py` | อ่านจาก MT5 ผ่าน `MetaTrader5` package |
| `brain/collector/service.py` | ลูป poll + เขียน DB + ออก metadata |
| `brain/collector/__main__.py` | รันเป็น process แยก |
| `tools/task.py` | **แก้** — เพิ่ม `collector` |
| `tests/test_collector.py` | §7 |

### 3.2 ทำไมเป็น process แยก ไม่ใช่ EA

[01-architecture](../01-architecture.md) ระบุไว้แล้วว่าเป็น *"MT5 read-only 1 ตัว + `MetaTrader5` pkg"*

| ทางเลือก | ทำไมไม่เอา |
|----------|-----------|
| EA อีกตัวต่อ 1 symbol | ต้องเปิด 6 ชาร์ต · 6 session บน gateway · เปลืองและซับซ้อน |
| MQL5 Service | ต้องเพิ่ม session type ใหม่ในโปรโตคอล |
| **Python + `MetaTrader5`** | ✅ 1 process อ่านครบทุก symbol · ไม่ผ่าน wire · ไม่มี session ใหม่ |

### 3.3 API

```python
@dataclass(frozen=True)
class Quote:
    broker: str
    raw_symbol: str
    canonical: str
    bid: float
    ask: float
    ts_utc: datetime          # ★ แปลงแล้ว -- ดู §4.3
    ts_broker_raw: datetime   # ดิบจาก MT5 (ไว้ debug)

class MarketDataCollector:
    async def start(self) -> None: ...
    async def stop(self) -> None: ...

    def latest_quote(self, canonical: str) -> Quote | None: ...
    def freshness(self) -> dict[str, FreshnessInfo]: ...   # ★ ให้ SPEC-061
```

---

## 4. Behaviour

### 4.1 เก็บ 2 อย่าง ต่างจังหวะกัน

| ข้อมูล | ใช้ทำอะไร | ความถี่ | เก็บที่ |
|--------|-----------|---------|---------|
| **quote (bid/ask)** | P3 แปลง exposure เป็นสกุลบัญชี | **ทุก 5 วินาที** | ในหน่วยความจำ |
| **bar (H1)** | P4 correlation 20 วัน · SPEC-041 regime | **ทุก bar close** (เช็คทุก 60 วินาที) | ตาราง `bars` |

**ไม่ต้อง realtime** — P4 คำนวณ correlation 20 วัน · P3 คุม exposure ที่เพดาน 2%
· quote อายุ 5 วินาทีไม่มีผลกับการตัดสินใจระดับนั้น

### 4.2 หลาย broker ต้อง poll ทีละตัว

`MetaTrader5` package ต่อได้ **ทีละเทอร์มินัลเท่านั้น** ([SPEC-007 §4.6](SPEC-007-data-ingest.md))

```
loop:
  for broker in brokers:
      initialize(path) → อ่านทุก symbol ของ broker นั้น → shutdown()
  sleep(interval)
```

- broker ที่ต่อไม่ได้ → **`[SKIP]` + mark stale ทุก symbol ของ broker นั้น** ไม่ใช่ crash
- XM ตอนนี้ login ไม่ได้ ([D11](../backlog.md)) → เข้าเคสนี้

### 4.3 ★★ เวลา — ห้ามเดา offset เอง ต้องขอจาก gateway

MT5 คืนเวลาเป็น **เวลา broker** · brain ต้องการ UTC

[G6](../06-gap-audit.md) กำหนดว่า **มีแหล่งความจริงเดียวคือ `CBrokerTime` ในตัว EA**
และส่งขึ้นมาทาง `HELLO.broker_time` / `HEARTBEAT.wire.broker_utc_offset_sec`
([SPEC-063 §3.3](SPEC-063-broker-time.md))

```
offset = gateway.session_registry.broker_offset(broker)

offset ไม่มี (ไม่มี EA session ของ broker นั้นเลย)
   →  ★ ไม่เขียนข้อมูลของ broker นั้น + mark stale + WARN
```

**ห้ามคำนวณ offset เอง** แม้จะทำได้ — จะกลายเป็นแหล่งความจริงที่สอง
ซึ่งคือ G6 กลับมาอีกรอบ

> **ผลข้างเคียงที่ยอมรับ:** ถ้าไม่มี EA ต่อกับ broker ไหนเลย collector จะไม่เก็บ
> ข้อมูลของ broker นั้น — **ซึ่งถูกต้อง** เพราะเราไม่ได้เทรดที่นั่นอยู่แล้ว
> และการเดา offset เพื่อเก็บข้อมูลที่ไม่ได้ใช้ ไม่คุ้มกับความเสี่ยงที่ข้อมูลจะผิด

### 4.4 read-only เด็ดขาด

| กฎ | |
|----|---|
| ห้าม `order_send` · `order_check` · `order_calc_*` ที่เปลี่ยนสถานะ | |
| ห้ามเรียก `symbol_select(name, False)` | จะถอด symbol ออกจาก Market Watch ของคนอื่น |
| `symbol_select(name, True)` **ทำได้** | จำเป็นเพื่ออ่านราคา · แต่ต้อง log ครั้งแรกที่ทำ |
| acceptance | `grep` ห้ามเจอ `order_send` · `order_close` · `positions_` ★ |

### 4.5 ★ ต้องออก metadata ความสดให้ SPEC-061

```python
@dataclass(frozen=True)
class FreshnessInfo:
    canonical: str
    last_quote_utc: datetime | None
    last_bar_utc: datetime | None
    broker_available: bool
    offset_known: bool          # ★ §4.3
```

**collector ไม่ตัดสินว่า "เก่าเกินไป"** — มันแค่บอกว่า *"ล่าสุดคือเมื่อไร"*
· การตัดสินเป็นของ [SPEC-061](SPEC-061-stale-data-guard.md)

**แยกหน้าที่แบบนี้สำคัญ** — ถ้า collector ตัดสินเอง แล้ววันหนึ่งเกณฑ์เปลี่ยน
จะต้องแก้สองที่ และมีโอกาสที่สองที่ไม่ตรงกัน

### 4.6 collector ตายต้อง **เห็นได้**

| | |
|---|---|
| หัวใจเต้น | เขียน `collector_heartbeat_utc` ทุกรอบ (ในหน่วยความจำ + log) |
| ตายแล้ว | `freshness()` จะค้างที่เวลาเดิม → SPEC-061 เห็นเอง |
| **ห้าม** | ห้ามคืน `FreshnessInfo` ที่ดูสดทั้งที่ไม่ได้อัปเดต ★ |

**นี่คือหัวใจของ G1** — ระบบต้อง**รู้ตัว**ว่าข้อมูลไม่มา ไม่ใช่แค่ได้ค่าว่างแล้วเดินต่อ

### 4.7 symbol ที่จะเก็บมาจาก registry

`SymbolRegistry` ([SPEC-064](SPEC-064-symbol-registry.md)) บอกว่า broker ไหนมี raw symbol อะไร
· **ห้าม hardcode** · symbol ที่ไม่อยู่ใน registry → ไม่เก็บ (ไม่ใช่ error)

---

## 5. Edge cases

1. **ตลาดปิด** → ไม่มี quote ใหม่ · `last_quote_utc` ค้าง → **ถูกต้อง**
   · SPEC-061 ต้องแยกกรณี "ตลาดปิด" ออกจาก "collector ตาย" (§4.5 ให้ `broker_available`)
2. **`symbol_info_tick()` คืน `None`** → mark stale symbol นั้น ไม่ใช่ทั้ง broker
3. **`bid` หรือ `ask` เป็น 0** → ไม่เขียน + WARN (ราคา 0 เป็นไปไม่ได้)
4. **`ask < bid`** → ไม่เขียน + ERROR (spread ติดลบ = ข้อมูลเสีย)
5. **terminal ถูกปิดระหว่างรัน** → จับได้ · mark stale · **retry รอบหน้า ไม่ crash**
6. **`initialize()` ค้าง** → ต้องมี timeout · ไม่งั้น collector ค้างทั้งตัว
7. **bar ที่ได้ซ้ำกับที่ EA ส่งมา** → `ON CONFLICT DO NOTHING` ([SPEC-014 §4.5](SPEC-014-persistence.md))
8. **collector กับ MQL5 gate ชนกัน** → gate ต้องการเทอร์มินัลปิด · **ต้องเช็คกันและกัน**
   ([SPEC-007 §4.2](SPEC-007-data-ingest.md))
9. **นาฬิกาเครื่องเพี้ยน** → ไม่กระทบ เพราะ offset มาจาก EA ไม่ใช่จากเครื่อง (§4.3)

---

## 6. Acceptance criteria

- [ ] เก็บ quote ครบทุก symbol ใน registry ที่ broker นั้นมี
- [ ] **`grep -rniE "order_send|order_close|positions_get" brain/collector/` — ไม่เจอ** ★★
- [ ] **ไม่มี EA session ของ broker → ไม่เขียนข้อมูลของ broker นั้น + WARN** ★★ §4.3
- [ ] `grep -rn "TimeGMT\|utcnow\|astimezone" brain/collector/` — **ไม่เจอการคำนวณ offset เอง** ★★
- [ ] broker ต่อไม่ได้ → `[SKIP]` + mark stale · **ไม่ crash** · broker อื่นทำงานต่อ
- [ ] `bid = 0` หรือ `ask < bid` → ไม่เขียน + log
- [ ] collector ตาย → `freshness()` **ค้างที่เวลาเดิม** ไม่ใช่ดูสด ★★
- [ ] `freshness()` แยก `broker_available` ออกจาก `offset_known` ได้
- [ ] bar ที่ซ้ำกับของ EA → ไม่ error
- [ ] เขียน `bars` ด้วย **raw symbol + broker** ([SPEC-006 §4.4](SPEC-006-database.md))
- [ ] `initialize()` มี timeout — collector ไม่ค้าง
- [ ] `python tools/task.py check` ผ่านบนเครื่องที่ไม่มี MT5 (marker `mt5_live`)
- [ ] `grep -rn "except:" brain/collector/` — ไม่เจอ bare except

## 7. Test list — `tests/test_collector.py`

unit test ใช้ **fake MT5 reader** — deterministic ไม่ต้องมี MT5

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_collects_all_registry_symbols` | §4.7 |
| 2 | `test_skips_symbol_not_in_registry` | |
| 3 | `test_no_offset_means_no_write` | ★★ §4.3 |
| 4 | `test_never_computes_offset_itself` | ★★ |
| 5 | `test_broker_unavailable_marks_stale_not_crash` | §4.2 |
| 6 | `test_other_brokers_continue_when_one_fails` | |
| 7 | `test_zero_bid_rejected` | edge 3 |
| 8 | `test_ask_below_bid_rejected` | edge 4 |
| 9 | `test_freshness_does_not_advance_when_dead` | ★★ §4.6 |
| 10 | `test_freshness_separates_market_closed_from_dead` | ★ edge 1 |
| 11 | `test_duplicate_bar_no_error` | edge 7 |
| 12 | `test_bars_written_with_raw_symbol_and_broker` | |
| 13 | `test_read_only_no_trading_calls` | ★★ §4.4 |

**test 3 · 9 · 13 คือสามตัวที่สำคัญที่สุด** — 3 กันไม่ให้เกิดแหล่งความจริงที่สอง
· 9 คือหัวใจของ G1 · 13 คือ read-only

## 8. Files

**Touch:** `brain/collector/**` · `tests/test_collector.py` · `tools/task.py`

**ห้ามแตะ:** `brain/gateway/**` (อ่าน session registry ได้ ห้ามแก้) · `brain/store/**`
· `mt5-ea/**` · `contracts/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | 5 วินาที/quote · 60 วินาที/bar เหมาะไหม | **ไม่บล็อก** — เริ่มที่นี่ · **วัด CPU และ latency ของ `initialize()` แล้วรายงาน** ถ้า connect/disconnect ทุก 5 วิแพงเกินไป ให้เสนอทางอื่น อย่าปรับเอง |
| Q2 | ควรอ่าน session registry ผ่าน API หรือแชร์ object | **ไม่บล็อก** — collector กับ gateway อยู่คนละ process ได้หรือไม่ได้ก็ได้ · **รายงานว่าเลือกอะไรและทำไม** |

> **ไม่มีคำถามที่บล็อก — เริ่มได้เมื่อ 006 + 013 + 064 merge**
