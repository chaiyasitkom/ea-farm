# SPEC-026 — Correlation engine + P4 correlated risk cap

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-024, SPEC-060, SPEC-061, SPEC-064
**Blocks:** SPEC-025 (P4 ถูกเรียกจากที่นั่น) · **ผูกพันกับ:** [ADR-004](../decisions/ADR-004-exposure-unit.md) · [ADR-005 §5](../decisions/ADR-005-cross-account-hedge.md)
**อ้าง:** [03-risk-spec P4](../03-risk-spec.md) · [G1](../06-gap-audit.md)

> **หน่วยของ P4 เหมือน P3 เป๊ะ** — `risk-normalized % ของ farm equity` ([ADR-004](../decisions/ADR-004-exposure-unit.md))
> ห้ามคำนวณ risk เอง · ต้อง `import ExposureEngine` จาก [SPEC-024](SPEC-024-currency-exposure.md)

---

## 1. Goal

รู้ว่า symbol ไหน "เป็นเดิมพันเดียวกัน" จากข้อมูลจริง แล้วบังคับเพดาน **1.0% ต่อกลุ่ม**
เพื่อไม่ให้ฟาร์มถือ 6 คู่ที่จริงๆ แล้วคือเดิมพันเดียวกันคูณ 6

ชุด 6 คู่มีเดิมพันอิสระจริงราว **4 ก้อน** ([03-risk-spec](../03-risk-spec.md)) —
`EURUSD`+`GBPUSD` · `USDJPY` · `AUDUSD`+`USDCAD` · `XAUUSD` และยังมี `AUDUSD`↔`XAUUSD` ข้ามก้อน

## 2. Non-goals

- ❌ ห้ามคำนวณ `risk_pct` เอง — `import` จาก SPEC-024
- ❌ ห้าม implement P3 หรือกฎ P อื่น (SPEC-024 / SPEC-025)
- ❌ ห้ามเก็บ bar เอง — อ่านจาก `bars` ที่ SPEC-060 เขียนไว้
- ❌ ห้ามเขียน stale logic ใหม่ — `StaleDataGuard.require()` (SPEC-061)
- ❌ ห้ามใช้ correlation ทำนายอะไร — ที่นี่คือ **กฎ risk** ไม่ใช่ feature ของโมเดล (Phase 3)
- ❌ ห้ามแตะ `contracts/**` · `mt5-ea/**` · `docs/**`

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ทำอะไร |
|------|--------|
| `brain/risk/correlation.py` | **สร้าง** — `CorrelationEngine` + `P4Guard` |
| `tests/test_correlation.py` | **สร้าง** — §7 |

### 3.2 API

```python
@dataclass(frozen=True)
class CorrelationMatrix:
    values: dict[tuple[str, str], float]     # (canonical, canonical) -> corr ∈ [-1, 1]
    sample_sizes: dict[tuple[str, str], int]
    assumed_pairs: frozenset[tuple[str, str]]  # ★ คู่ที่ใช้ค่า fallback 1.0 (§4.4)
    computed_at: datetime

@dataclass(frozen=True)
class CorrelationGroup:
    key: str                     # ชื่อกลุ่มที่ deterministic (§4.5)
    members: tuple[str, ...]     # canonical เรียง A→Z
    gross_pct: float             # Σ|risk_pct| ของทุกไม้ใน members

@dataclass(frozen=True)
class P4Verdict:
    ok: bool
    scale: float                 # 1.0 = ไม่ต้องลด · 0.0 = ทำไม่ได้เลย
    reason: str
    group: CorrelationGroup | None

class CorrelationEngine:
    def __init__(self, bars_repo: BarsRepo, registry: SymbolRegistry,
                 guard: StaleDataGuard, clock: Clock, config: CorrelationConfig): ...

    def matrix(self) -> CorrelationMatrix: ...            # cache ตาม §4.6
    def groups(self, snap: ExposureSnapshot) -> tuple[CorrelationGroup, ...]: ...

class P4Guard:
    def evaluate(self, intent: Intent, snap: ExposureSnapshot) -> P4Verdict: ...
```

### 3.3 `CorrelationConfig`

| key | default | หมายเหตุ |
|-----|---------|----------|
| `max_correlated_risk_pct` | **1.0** | % ของ farm equity ต่อกลุ่ม |
| `correlation_threshold` | **0.7** | ใช้กับ **\|corr\|** (§4.3) |
| `timeframe` | `"H1"` | §4.2 |
| `window_bars` | **480** | 20 วัน × 24 ชม. |
| `min_overlap_bars` | **400** | น้อยกว่านี้ = ไม่เชื่อ → fallback (§4.4) |

---

## 4. Behaviour

### 4.1 สูตร

```
r_t(c)      = ln(close_t / close_{t−1})            ★ log return ไม่ใช่ผลต่างราคา
corr(a, b)  = Pearson(r(a), r(b)) บน bar ที่ทั้งคู่มี timestamp ตรงกันเท่านั้น
```

**ต้อง align ด้วย `bar_time` ไม่ใช่จับคู่ตามลำดับ** — โบรกเกอร์คนละเจ้ามีจำนวน bar ไม่เท่ากัน
(วันหยุด · gap · ทองมีพักรายวัน) · การ zip ตามลำดับจะจับ return คนละชั่วโมงมาคู่กันแล้วให้ค่าที่ดูปกติแต่ผิด

ใช้ **canonical** เสมอ — bar ของ `GOLD` (XM) กับ `XAUUSD.iux` (IUX) เป็นสินทรัพย์เดียวกัน
· ถ้ามีทั้งสองโบรก ให้ใช้ชุดของโบรกที่มี bar ครบกว่า (tie → เรียงชื่อ broker A→Z เพื่อให้ deterministic)

### 4.2 ทำไม H1 480 bar ไม่ใช่ D1 20 bar

| ทางเลือก | ปัญหา |
|----------|-------|
| D1 × 20 จุด | 20 จุดให้ correlation ที่ error สูงมาก — สลับระหว่าง 0.5/0.9 ได้จากวันเดียว |
| H1 × 480 จุด | ✅ ครอบ "20 วัน" ตามที่ risk-spec เขียน และมีจุดพอให้ค่านิ่ง |
| M1 | noise ครอบงำ · microstructure ไม่ใช่ความสัมพันธ์ของเดิมพัน |

### 4.3 ★ ใช้ค่าสัมบูรณ์ในการจัดกลุ่ม

```
a, b อยู่กลุ่มเดียวกัน  ⇔  |corr(a, b)| > threshold
```

`corr = −0.85` **ไม่ได้แปลว่าไม่เกี่ยวกัน** — long `EURUSD` กับ short คู่ที่ corr −0.85
คือเดิมพันเดียวกันแทบทุกประการ · ถ้าใช้ค่าดิบจะพลาดครึ่งหนึ่งของเคสที่กฎนี้มีไว้จับ

**การรวม risk ภายในกลุ่มเป็น gross** `Σ|risk_pct|` — ทิศทางไม่ลดตัวเลข
(หลักการเดียวกับ [ADR-005 §5](../decisions/ADR-005-cross-account-hedge.md): hedge ต้องไม่ทำให้ความเสี่ยงดู "หายไป")

### 4.4 ★★ fail-closed — คู่ที่คำนวณไม่ได้คือ 1.0 ไม่ใช่ 0

| สภาพ | `corr` ที่ใช้ | บันทึก |
|------|--------------|--------|
| bar ครบ ≥ `min_overlap_bars` | ค่าที่คำนวณได้ | — |
| overlap < `min_overlap_bars` | **1.0** | เพิ่มคู่นั้นใน `assumed_pairs` |
| ไม่มี bar ของ symbol ใดเลย | **1.0** กับทุกคู่ของ symbol นั้น | `assumed_pairs` |
| ค่าที่คำนวณได้เป็น `NaN` (ราคาคงที่ทั้งช่วง / variance = 0) | **1.0** | `assumed_pairs` + WARN |
| `guard.require()` ไม่ผ่านสำหรับ symbol ในกลุ่ม | **reject intent** ทั้งใบ | [SPEC-061 §4.5](SPEC-061-stale-data-guard.md) |

**นี่คือช่องว่าง [G1](../06-gap-audit.md) เป๊ะๆ** — `corr = 0` แปลว่า *"ยืนยันแล้วว่าไม่เกี่ยวกัน"*
ซึ่งทำให้ P4 ยอมให้ถือทุกตัวเต็มขนาดพร้อมกัน **ตอนที่ระบบตาบอด**

`correlation_group` ใน [SPEC-064](SPEC-064-symbol-registry.md) เป็น fallback ชั้นสอง:
symbol ที่อยู่กลุ่มเดียวกันในตารางต้องถูกจับรวมกันเสมอ **แม้ข้อมูลจะบอกว่า corr ต่ำ** —
ตารางเป็นความรู้เชิงโครงสร้าง (AUD กับ XAU สัมพันธ์กันเชิงเศรษฐกิจ) ที่หน้าต่าง 20 วันอาจมองไม่เห็น

### 4.5 การจัดกลุ่ม — connected components

```
สร้างกราฟ: node = canonical ที่ฟาร์มถืออยู่ (หรือกำลังจะถือจาก intent)
           edge  = |corr| > threshold  หรือ  อยู่ correlation_group เดียวกันใน registry
กลุ่ม     = connected component
key       = "+".join(sorted(members))          ★ deterministic
```

**A~B และ B~C แต่ A≁C → ทั้งสามอยู่กลุ่มเดียวกัน** (transitive) — เลือกแบบนี้เพราะ:

| ทางเลือก | ผล |
|----------|-----|
| complete linkage (ต้องสัมพันธ์กันครบทุกคู่) | หลวมกว่า · แตกกลุ่มง่าย → ถือ 3 ตัวที่โยงกันเป็นสายได้เต็มขนาดทั้งสาม |
| ✅ **connected components** | เข้มกว่า · ถ้า B เชื่อมทั้ง A และ C การขาดทุนของ B ลากทั้งสายอยู่ดี |

### 4.6 จังหวะคำนวณ — cache ได้ แต่ต้องหมดอายุ

| | |
|---|---|
| คำนวณ matrix ใหม่ | ทุก **60 นาที** หรือเมื่อมี bar H1 ใหม่ |
| อายุ cache สูงสุด | **90 นาที** — เกินนี้ถือว่า `STALE` → กลับไปใช้กฎ §4.4 (`1.0`) |
| การจัดกลุ่ม | คำนวณ **ทุกครั้งที่ประเมิน intent** (ถูก · ขึ้นกับไม้ที่ถืออยู่ ณ ตอนนั้น) |

**ห้าม cache ผลการประเมิน intent** — ไม้เปลี่ยนทุกวินาที

### 4.7 P4 บังคับใช้อย่างไร — scale ไม่ใช่ reject

```
group        = กลุ่มที่ intent นี้จะเข้าไปอยู่ (รวม symbol ของ intent เข้าไปในกราฟก่อน)
headroom     = cap − group.gross_pct                       // % ที่เหลือของกลุ่มนั้น
requested    = risk_pct ที่ intent จะสร้าง (จาก ExposureEngine)

headroom <= 0            →  ok=False · scale=0.0 · reason "P4_GROUP_FULL …"
requested <= headroom    →  ok=True  · scale=1.0
0 < headroom < requested →  ok=True  · scale = headroom / requested        ★ ลดขนาด
```

- `scale` ที่คืนไปจะถูกคูณกับ `target_volume` **ก่อน**เข้า R1 ([SPEC-027 Q2](SPEC-027-risk-directive.md))
- ถ้า scale แล้ว lot ต่ำกว่า `volume_min` EA จะ reject ด้วย `RISK_TOO_SMALL_FOR_MIN_LOT`
  ([SPEC-020](SPEC-020-lot-sizing.md)) — **ถูกต้องแล้ว ห้ามปัดขึ้นให้ถึง `volume_min`** ที่ฝั่ง brain
- `target_volume = 0` และ intent ที่ลดขนาดในฝั่งเดิม → **ผ่านเสมอ `scale=1.0`**

`reason` ต้องบอกกลุ่ม สมาชิก ค่าจริง และเพดาน:
`"P4_GROUP_SCALED group=AUDUSD+XAUUSD gross=0.82% cap=1.00% requested=0.35% scale=0.51"`

### 4.8 ต้องเปิดเผยให้เห็นจากภายนอก

| ค่า | ใช้ที่ไหน |
|-----|-----------|
| matrix ล่าสุด + `computed_at` | dashboard (SPEC-028) — heatmap |
| `assumed_pairs` (คู่ที่ใช้ 1.0 เพราะข้อมูลไม่พอ) | ★ dashboard + alert ถ้าค้างเกิน 1 ชั่วโมง |
| กลุ่มปัจจุบัน + `gross_pct` ต่อกลุ่ม | dashboard |
| จำนวนครั้งที่ P4 scale/reject | alert (SPEC-029) |

**`assumed_pairs` ที่ไม่ว่างคือสถานะที่ระบบกำลังเดาแบบเข้มที่สุด** — ต้องเห็น ไม่ใช่ซ่อน
ไม่งั้นจะมีคนสงสัยว่าทำไมเทรดไม่เข้าแล้วไปปิดกฎทิ้ง

---

## 5. Edge cases

1. **ฟาร์มไม่ถืออะไรเลย** → ไม่มีกลุ่ม → intent แรกเทียบกับ `gross = 0` → ผ่าน
2. **intent ของ symbol ที่ยังไม่เคยถือ** → ต้องเพิ่ม node เข้ากราฟ**ก่อน**คำนวณกลุ่ม ★
3. **ทุกคู่ correlated > 0.7 หมด (วิกฤต)** → ทั้ง 6 คู่เป็นกลุ่มเดียว เพดานรวม 1.0%
   → **ถูกต้องตามเจตนา** ไม่ใช่ bug · ต้องมี log ที่อ่านรู้เรื่องว่าทำไมเทรดไม่เข้า
4. **ราคาคงที่ทั้งหน้าต่าง** (symbol ตายหรือตลาดปิดยาว) → variance 0 → `NaN` → 1.0 (§4.4)
5. **bar มี gap สุดสัปดาห์** → return ข้ามสุดสัปดาห์เป็น return ปกติ 1 จุด **ห้ามเติมค่า** (ห้าม forward-fill)
6. **สองโบรกมี bar ของ canonical เดียวกัน** → §4.1 เลือกชุดเดียว ห้ามเอามาต่อกัน
7. **`XAUUSD` พักรายวัน** → bar หายไปบางชั่วโมง → align ด้วย `bar_time` จัดการให้แล้ว
8. **DST เปลี่ยน** → `bar_time` เป็น UTC แล้ว ([SPEC-063](SPEC-063-broker-time.md)) → ไม่มีผล
9. **matrix cache หมดอายุระหว่างประเมิน intent** → คำนวณใหม่ทันที ถ้าคำนวณไม่ได้ → 1.0
10. **กลุ่มเต็มพอดี `headroom = 0.0`** → `ok=False` (ใช้ `<=` ไม่ใช่ `<`)
11. **intent ที่ทำให้กลุ่มสองกลุ่มรวมเป็นกลุ่มเดียว** (symbol ใหม่เป็นสะพาน) →
    ประเมินกับกลุ่มที่รวมแล้ว **ซึ่งจะเข้มขึ้น** ★ ถูกต้อง
12. **มีไม้อยู่แล้วเกินเพดานกลุ่ม** (equity ตก) → intent ใหม่ทุกใบ reject ·
    ticket นี้**ไม่สั่งปิดไม้** — SPEC-025 เป็นคนตัดสินว่าจะ `REDUCE_ONLY` ไหม

---

## 6. Acceptance criteria

- [ ] **ข้อมูลไม่พอ → `corr = 1.0` ไม่ใช่ `0`** ★★ (ปิด G1 ร่วมกับ SPEC-061)
- [ ] จัดกลุ่มด้วย **\|corr\|** — คู่ที่ corr `−0.85` อยู่กลุ่มเดียวกัน ★★
- [ ] รวม risk ในกลุ่มแบบ **gross** — long + short ในกลุ่มเดียวกันไม่หักกัน ★
- [ ] align ด้วย `bar_time` — test ที่ให้ bar ขาดคนละตำแหน่งต้องได้ผลถูก ★★
- [ ] `correlation_group` จาก registry ทำให้ symbol อยู่กลุ่มเดียวกัน **แม้ corr ต่ำ** ★
- [ ] connected components — A~B, B~C, A≁C → **กลุ่มเดียว** ★
- [ ] `scale = headroom / requested` ตรงสูตร §4.7 · `headroom <= 0` → `scale=0` ★★
- [ ] `target_volume = 0` → ผ่านเสมอ ★★
- [ ] brain **ไม่ปัด lot ขึ้น**ให้ถึง `volume_min` หลัง scale
- [ ] `assumed_pairs` ไม่ว่าง → เปิดเผยออกมาได้ (มี test อ่านค่า)
- [ ] cache หมดอายุ 90 นาที → กลับไปใช้ 1.0 ★
- [ ] `risk_pct` ทุกค่า**มาจาก `ExposureEngine`** — `grep -rn "price_open\|contract_size" brain/risk/correlation.py` **ไม่เจอ** ★★
- [ ] `grep -rniE "fillna|ffill|interpolate|dropna\(\)|corr\(\) *or 0|, *0\)" brain/risk/correlation.py` — ไม่เจอการเติมค่า ★★
- [ ] `python tools/task.py check` เขียว · test ใช้ bar ปลอมทั้งหมด ไม่ต่อ DB จริง

## 7. Test list — `tests/test_correlation.py`

| # | test | ตรวจอะไร | กฎ |
|---|------|----------|-----|
| 1 | `test_insufficient_overlap_yields_one_not_zero` | ★★ ปิด G1 | P4 |
| 2 | `test_no_bars_at_all_yields_one` | ★★ §4.4 | P4 |
| 3 | `test_nan_variance_yields_one_with_warning` | edge 4 | P4 |
| 4 | `test_negative_correlation_groups_together` | ★★ §4.3 | P4 |
| 5 | `test_group_risk_is_gross_not_net` | ★ §4.3 | P4 |
| 6 | `test_bars_aligned_by_time_not_index` | ★★ §4.1 (bar ขาดคนละตำแหน่ง) | P4 |
| 7 | `test_log_return_not_price_difference` | §4.1 | P4 |
| 8 | `test_registry_group_forces_grouping_despite_low_corr` | ★ §4.4 | P4 |
| 9 | `test_connected_components_transitive` | ★ §4.5 | P4 |
| 10 | `test_group_key_is_deterministic` | §4.5 | P4 |
| 11 | `test_scale_equals_headroom_over_requested` | ★★ §4.7 | P4 |
| 12 | `test_full_group_rejects_with_scale_zero` | ★★ §4.7 · edge 10 | P4 |
| 13 | `test_zero_target_always_passes` | ★★ | P4 |
| 14 | `test_shrink_same_direction_passes` | §4.7 | P4 |
| 15 | `test_new_symbol_added_to_graph_before_grouping` | ★ edge 2 | P4 |
| 16 | `test_bridging_symbol_merges_two_groups` | ★ edge 11 | P4 |
| 17 | `test_all_correlated_gives_single_group` | edge 3 | P4 |
| 18 | `test_cache_expires_after_90_minutes` | ★ §4.6 | P4 |
| 19 | `test_weekend_gap_not_filled` | edge 5 | P4 |
| 20 | `test_same_canonical_two_brokers_uses_one_series` | edge 6 | P4 |
| 21 | `test_stale_group_member_rejects_intent` | [SPEC-061 §4.5](SPEC-061-stale-data-guard.md) | P4/P10 |
| 22 | `test_assumed_pairs_exposed` | §4.8 | P4 |
| 23 | `test_reason_contains_group_members_and_numbers` | §4.7 | P4 |
| 24 | `test_known_series_gives_known_correlation` | ค่าจาก series ที่คำนวณมือได้ (เช่น `corr=1.0` เมื่อเท่ากันเป๊ะ · `−1.0` เมื่อกลับข้าง) | P4 |

**test 1 กับ test 6 คือสองข้อที่ควรเขียนก่อน** — ข้อแรกคือเหตุผลที่ ticket นี้ต้อง fail-closed
ข้อที่หกคือ bug ที่ผ่าน review ได้ง่ายที่สุดเพราะผลลัพธ์ดู "มีเหตุผล" เสมอ

## 8. Files

**Touch:** `brain/risk/correlation.py` · `tests/test_correlation.py`

**ห้ามแตะ:** `brain/risk/exposure.py` (SPEC-024 — `import` ได้ ห้ามแก้) ·
`brain/risk/staleness.py` · `brain/risk/directive.py` · `brain/collector/**` ·
`contracts/**` · `mt5-ea/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | threshold 0.7 เหมาะไหมกับ H1 return | **ไม่บล็อก** — ใช้ค่าจาก risk-spec ไปก่อน · **เก็บสถิติจริงตอน soak แล้วรายงาน อย่าปรับเอง** (เปลี่ยนเพดาน risk = ต้องผ่าน ADR) |
| Q2 | ควรใช้ Spearman แทน Pearson ไหม (ทน outlier กว่า) | **ไม่บล็อก — ตอบแล้ว: Pearson** · outlier ในบริบทนี้ (ข่าวแรง) คือ**เหตุการณ์ที่เราอยากให้กฎจับ** ไม่ใช่ noise ที่ควรลดน้ำหนัก |
| Q3 | ควรถ่วงน้ำหนักให้ bar ล่าสุดมากกว่า (EWMA) ไหม | **ไม่บล็อก — ยังไม่ต้อง** · เพิ่มพารามิเตอร์ที่ยังไม่มีใครรู้ค่าที่ถูก · เปิด ticket ใหม่ถ้าข้อมูลจริงบอกว่าจำเป็น |

> **ไม่มีคำถามที่บล็อก** — D9 ปิดแล้ว ([ADR-004](../decisions/ADR-004-exposure-unit.md))
> เริ่มได้เมื่อ SPEC-024 merge
