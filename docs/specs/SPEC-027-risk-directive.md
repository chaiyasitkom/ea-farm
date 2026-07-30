# SPEC-027 — RISK_DIRECTIVE end-to-end + mode precedence

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-013, SPEC-019, SPEC-023, SPEC-063
**Blocks:** SPEC-025, SPEC-028 · **อ้าง:** [02-contracts §4.8](../02-contracts.md) · [risk-spec L2](../03-risk-spec.md) · [`risk_directive.json`](../../contracts/schema/risk_directive.json)

> ## ⚠️ กลับด้าน dependency จาก backlog เดิม — อ่านก่อน
>
> backlog เดิมเขียนว่า **SPEC-027 ขึ้นกับ SPEC-025** ซึ่งทำให้ ticket นี้ติดอยู่หลัง 🔴 **D9 + D10**
> ที่เจ้าของยังไม่ตอบ · **ไม่จริง และแพงโดยไม่จำเป็น**
>
> | | ขอบเขต |
> |---|--------|
> | **SPEC-027 (ticket นี้)** | **ท่อ + กฎ precedence** — directive เดินทางยังไง · รวมกับ local guard ยังไง · หมดอายุยังไง |
> | **SPEC-025** | **คนตัดสิน** — P1…P11 ดูตัวเลขแล้วตัดสินว่าจะส่ง directive อะไรออกมา |
>
> กฎ `effective = max(local, directive)` **ไม่ขึ้นกับว่า P3 วัดเป็น notional หรือ risk-normalized เลย**
> → ticket นี้จึงหลุดจากเงา D9/D10 และทำได้ทันทีหลังรอบ 7
>
> **SPEC-025 จะ `import` โมดูลจาก ticket นี้ ห้ามเขียนใหม่** (§8)

---

## 1. Goal

ทำให้ `RISK_DIRECTIVE` เดินทางจาก brain → gateway → EA แล้ว**มีผลจริง** และพิสูจน์ได้ว่า
**กฎเหล็ก "เข้มได้ ผ่อนไม่ได้" ทำงานครบทุกคู่ผสม** ไม่ใช่แค่เคสที่นึกออก

จบ ticket นี้ = brain สั่งลดความเสี่ยงทั้งฟาร์มได้ · และ**พิสูจน์ได้ว่าสั่งเพิ่มความเสี่ยงไม่ได้**

## 2. Non-goals

- ❌ ห้าม implement P1–P11 ที่ **ตัดสินใจ**ว่าจะส่ง directive อะไร — นั่นคือ SPEC-025
- ❌ ห้ามแตะ dashboard / ปุ่ม kill switch (SPEC-028) — ที่นี่คือ **ท่อ** ไม่ใช่ UI
- ❌ ห้าม implement การ**ปิด position** เอง — `FLATTEN` แค่ตั้งสถานะ + ส่งรายชื่อ symbol
      ให้ `COrderRouter` (SPEC-011) เป็นคนวนปิด
- ❌ ห้ามแตะ `contracts/schema/**` — schema ครบแล้ว
- ❌ ห้ามทำ `CONFIG_UPDATE` ([02-contracts §4.10](../02-contracts.md) RESERVED ถึง Phase 5)

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ทำอะไร |
|------|--------|
| `mt5-ea/Include/Farm/Directive.mqh` | **สร้าง** — `CDirectiveState` |
| `tests/mql5/TestDirective.mq5` | **สร้าง** — ★ รวม matrix 25 ช่อง |
| `brain/risk/directive.py` | **สร้าง** — model + strictness + validation (pure) |
| `brain/risk/dispatcher.py` | **สร้าง** — ส่ง · persist · resend ตอน reconnect |
| `tests/unit/test_directive_precedence.py` | **สร้าง** — matrix เดียวกันฝั่ง Python |
| `mt5-ea/Include/Farm/RiskGuard.mqh` | **แก้** — `AttachDirective()` + รวม mode |
| `brain/gateway/session.py` | **แก้** — `HELLO_ACK.initial_directive` |
| `tools/mql5-suites.json` · `tools/run-mql5-tests.ps1` | **แก้** — เพิ่ม suite |

### 3.2 EA side

```mql5
struct FarmDirective
{
   string                directive_id;      // ULID · "" = ไม่มี directive
   ENUM_FARM_GUARD_MODE  mode;
   double                scale_factor;      // 0.0 – 1.0
   string                reason;
   datetime              expires_at_utc;    // 0 = ไม่หมดอายุ
   string                flatten_symbols[]; // ว่าง + mode FLATTEN = ทุก symbol
};

class CDirectiveState
{
public:
   bool Init(CBrokerTime *clock);

   // รับ directive ใหม่ · คืน false = ปฏิเสธ (caller ต้องส่ง INTENT_ACK REJECTED_INVALID)
   bool Accept(const FarmDirective &d, string &out_reject_reason);

   // เรียกทุก Pump() -- จัดการหมดอายุ · คืน true ถ้าสถานะเปลี่ยน
   bool Evaluate();

   ENUM_FARM_GUARD_MODE Mode() const;        // NORMAL ถ้าไม่มี directive ที่ยังไม่หมดอายุ
   double  ScaleFactor() const;              // 1.0 ถ้าไม่มี
   string  DirectiveId() const;
   string  Reason() const;
   bool    HasActive() const;

   // FLATTEN: คืน true ถ้า symbol นี้ต้องถูกปิด (ว่าง = ทุกตัว)
   bool    MustFlatten(const string symbol) const;
};
```

### 3.3 ★ จุดรวม — กฎเหล็กอยู่ที่นี่ที่เดียว

```mql5
// RiskGuard.mqh
ENUM_FARM_GUARD_MODE CRiskGuard::Mode() const
{
   ENUM_FARM_GUARD_MODE m = LocalRuleMode();               // R1…R19
   if(m_safemode  != NULL) m = StricterOf(m, m_safemode.Mode());     // SPEC-023
   if(m_directive != NULL) m = StricterOf(m, m_directive.Mode());    // ★ ticket นี้
   return m;
}
```

**`StricterOf()` ต้องมีที่เดียวในระบบ** — ห้ามเขียนตรรกะเปรียบเทียบ mode ซ้ำที่อื่น
· ทุกที่ที่ต้องเทียบความเข้มต้องเรียกฟังก์ชันนี้

### 3.4 Brain side

```python
# brain/risk/directive.py -- pure, ไม่มี I/O
STRICTNESS: dict[Mode, int] = {
    Mode.NORMAL: 0, Mode.SCALED: 1, Mode.REDUCE_ONLY: 2,
    Mode.FLATTEN: 3, Mode.HALT: 4,
}

def stricter_of(a: Mode, b: Mode) -> Mode: ...
def validate(d: RiskDirective) -> list[str]: ...   # ว่าง = ผ่าน

# brain/risk/dispatcher.py
class DirectiveDispatcher:
    async def broadcast(self, d: RiskDirective) -> None: ...
    async def send_to(self, session_id: str, d: RiskDirective) -> None: ...
    def current_for(self, session_id: str) -> RiskDirective | None: ...   # ใช้ตอน HELLO_ACK
```

---

## 4. Behaviour

### 4.1 ลำดับความเข้ม — ตัวเลขนี้คือความจริงข้อเดียว

```
NORMAL(0) < SCALED(1) < REDUCE_ONLY(2) < FLATTEN(3) < HALT(4)
```

| | สูตร |
|---|------|
| mode | `effective = max(strictness)` ของ local · safemode · directive |
| scale | `effective_scale = min(local_scale, directive_scale)` |

**ทั้งสองบรรทัดต้องเป็น `max`/`min` เสมอ** — ไม่มีเงื่อนไขไหนที่ผลลัพธ์ผ่อนกว่าขาที่เข้มที่สุด

### 4.2 ★★ จุดที่สับสนที่สุดของ ticket นี้ — "ผ่อนไม่ได้" ผ่อนอะไรไม่ได้กันแน่

มีสองความสัมพันธ์ที่หน้าตาเหมือนกันแต่กฎคนละข้อ · **สลับกันเมื่อไรระบบพังทันที**

| | กฎ |
|---|---|
| directive ใหม่ **เทียบกับ directive เก่า** | ✅ **แทนที่ได้เต็มที่ ผ่อนได้** — brain ต้องถอน `SCALED 0.5` ของตัวเองคืนได้ ไม่งั้นฟาร์มจะเข้มขึ้นทางเดียวจนหยุดเทรดถาวร |
| directive **เทียบกับ local guard** | ❌ **ผ่อนไม่ได้** — `max()` ตาม §4.1 · `LocalRiskGuard` halt อยู่ แล้ว `RISK_DIRECTIVE: NORMAL` เข้ามา → **ยัง halt** |

```
directive เก่า = REDUCE_ONLY · directive ใหม่ = NORMAL · local = HALT (R6 daily loss)
   → directive state = NORMAL       ✅ แทนที่แล้ว
   → effective        = HALT         ✅ local ชนะ
```

> **ทดสอบข้อนี้ให้ตาย** — ถ้า implement เป็น `max(directive_เก่า, directive_ใหม่)`
> ระบบจะดูปกติทุกวันจนถึงวันที่ต้องถอน directive แล้วถอนไม่ออก
> · และถ้า implement เป็น `directive ชนะ local` เงินจะหายวันที่ brain มี bug

### 4.3 การรับ directive — ตรวจก่อนรับ

| เช็ค | ผล |
|------|-----|
| `directive_id` ไม่ใช่ ULID | reject `INVALID_DIRECTIVE_ID` |
| `directive_id` ≤ `directive_id` ปัจจุบัน (เทียบ string ตรงๆ — ULID เรียงตามเวลาอยู่แล้ว) | **ignore เงียบ** + counter `directives_out_of_order` · ไม่ใช่ reject (มาช้าไม่ใช่ผิด) |
| `mode = HALT` แต่ `expires_at != null` | reject `HALT_MUST_NOT_EXPIRE` · **คงสถานะเดิม** |
| `mode = SCALED` แต่ `scale_factor >= 1.0` | reject `SCALED_WITHOUT_EFFECT` |
| `scale_factor` นอก `[0,1]` | reject `SCALE_OUT_OF_RANGE` (schema กันไว้แล้ว แต่ EA ต้องกันซ้ำ — ห้ามเชื่อฝั่งตรงข้าม) |
| `expires_at` อยู่ในอดีตแล้ว | reject `ALREADY_EXPIRED` |
| ผ่านหมด | ✅ แทนที่ state เดิม + ตอบ `INTENT_ACK` `ACCEPTED` โดยใช้ `directive_id` เป็น `intent_id` |

**ทุก reject ต้องตอบ `INTENT_ACK` `REJECTED_INVALID` พร้อม `reason`** — brain ต้องรู้ว่าไม่ถึง
· เงียบไม่ได้ เพราะ brain จะคิดว่าฟาร์มถูกจำกัดแล้วทั้งที่ยังไม่

### 4.4 หมดอายุ — กลับไปหา **local guard** ไม่ใช่กลับเป็น NORMAL

```
expires_at ผ่านไปแล้ว  →  ทิ้ง directive  →  effective = local guard เพียงลำพัง
```

`HALT` ต้อง `expires_at = null` เสมอ (§4.3) → ปลดด้วย directive ใหม่หรือมือเท่านั้น

#### ★★ `IsValid()==false` → **ห้ามหมดอายุ** (fail-closed)

ถ้า `CBrokerTime.IsValid()` เป็น `false` เราไม่รู้ว่าตอนนี้กี่โมง → **เทียบ `expires_at` ไม่ได้**

| ทางเลือก | ผล |
|----------|-----|
| ถือว่าหมดอายุ | ❌ ข้อจำกัดถูกปลดเพราะ**นาฬิกาพัง** — ความเสี่ยงเพิ่มขึ้นจากความไม่รู้ |
| ✅ **คง directive ไว้** | ข้อจำกัดยังอยู่จนกว่าจะรู้เวลาอีกครั้ง |

**เลือกข้อล่างเสมอ** — หลักการเดียวกับ [SPEC-063 §4.7](SPEC-063-broker-time.md) และ
[02-contracts §8.2](../02-contracts.md): *ไม่รู้ ต้องไม่กลายเป็นไฟเขียว*
· นับ `expiry_checks_skipped_no_time` + log WARN ครั้งแรกของช่วง

### 4.5 แต่ละ mode ทำอะไรกับ intent

| mode | intent ที่เปิดใหม่ | intent ที่เพิ่มขนาด | intent ที่ลด/ปิด | `target_volume = 0` |
|------|-------------------|--------------------|-----------------|---------------------|
| `NORMAL` | ✅ | ✅ | ✅ | ✅ |
| `SCALED` | ✅ × `scale` | ✅ × `scale` | ✅ | ✅ |
| `REDUCE_ONLY` | ❌ | ❌ | ✅ | ✅ |
| `FLATTEN` | ❌ | ❌ | ✅ | ✅ |
| `HALT` | ❌ | ❌ | ✅ **manual only** | ✅ ★ |

**★ `target_volume = 0` ต้องผ่านได้ทุก mode รวมทั้ง `HALT`** — ตรงกับ
[SPEC-019 §4.1](SPEC-019-local-risk-guard.md) และ [SPEC-023](SPEC-023-safemode.md):
*ความสามารถในการปิดไม้ต้องไม่ถูกปิดกั้นโดยกฎที่ตั้งใจลดความเสี่ยง*

**นิยาม "เพิ่มขนาด" ให้ชัด** (จุดที่เดาได้หลายแบบ):

```
เพิ่มขนาด  ⇔  |target| > |current_net|   หรือ   sign(target) ≠ sign(current_net) และ target ≠ 0
```

ข้อหลังสำคัญ: `current = +0.10` แล้วขอ `target = −0.05` **ไม่ใช่การลด** — เป็นการกลับข้าง
ซึ่งต้องปิด 0.10 แล้วเปิด 0.05 ฝั่งตรงข้าม = **เปิดใหม่** → `REDUCE_ONLY` ต้อง **ปฏิเสธ**
(ยอมได้เฉพาะการลดเข้าหา 0 ในฝั่งเดิม)

### 4.6 `FLATTEN` — array ว่างคือ "ทุก symbol"

```
flatten_symbols = []            →  ปิดทุก symbol        ★ พลาดง่ายที่สุดใน message นี้
flatten_symbols = ["EURUSD"]    →  ปิดเฉพาะ EURUSD · symbol อื่นเป็น REDUCE_ONLY
```

`MustFlatten(symbol)` คืน `true` เมื่อ mode = `FLATTEN` และ (array ว่าง **หรือ** มี symbol นั้น)

**การปิดจริงเป็นงานของ `COrderRouter`** — และต้อง**วนปิดทุก ticket** ไม่ใช่ส่ง order สวน 1 ไม้
(จะกลายเป็น internal hedge ละเมิด R18 ทันที · [ADR-001](../decisions/ADR-001-hedging-account.md))

### 4.7 Reconnect — สถานะต้องไม่หายไปกับ session

EA จำ directive ข้าม session ไม่ได้ (ไม่ persist) → **brain ต้องเป็นคนบอกซ้ำ**

```
EA ต่อใหม่ → HELLO → gateway เรียก dispatcher.current_for(session_id)
           → ใส่ใน HELLO_ACK.initial_directive (directive_core: mode + scale_factor)
```

| กรณี | `initial_directive` |
|------|---------------------|
| brain มี directive ที่ยังไม่หมดอายุ | ใส่ `mode` + `scale_factor` ของตัวนั้น |
| ไม่มี | **ละ key** (ไม่ใช่ `null` · ไม่ใช่ `NORMAL`) — [02-contracts §8](../02-contracts.md) |

**ห้ามพึ่ง `initial_directive` เพียงอย่างเดียว** — dispatcher ต้องส่ง `RISK_DIRECTIVE` เต็มใบ
ตามมาหลัง `HELLO_ACK` ด้วย เพราะ `directive_core` ไม่มี `expires_at` / `flatten_symbols`

### 4.8 Persistence ฝั่ง brain

ทุก directive ที่ **ส่งออก** ต้องลง `risk_events` (append-only) ก่อนส่ง:

| คอลัมน์ | ค่า |
|---------|-----|
| `rule` | `reason` ของ directive (ต้องจับคู่กับ P-rule id ได้ · schema บังคับ ≤ 64 ตัวอักษร) |
| `scope` | `FARM` (broadcast) หรือ `ACCOUNT` (ส่งเจาะ session) |
| `action_taken` | `mode` |
| `detail` | payload เต็มเป็น JSONB |

**เขียน DB ก่อนส่ง** — ถ้าเขียนไม่ได้ **ห้ามส่ง** (ตรงกับ [SPEC-014](SPEC-014-persistence.md)
*"ไม่มีหลักฐาน = ไม่เทรด"*) · directive คือการตัดสินใจที่ต้องสืบย้อนได้เสมอ

---

## 5. Edge cases

1. **directive มาก่อน `HELLO_ACK`** — EA ยังไม่ authenticated → ทิ้ง + log (gateway ไม่ควรส่ง)
2. **directive สอง ใบ `directive_id` เท่ากันเป๊ะ** — ใบหลัง ignore (idempotent · ไม่ใช่ error)
3. **`expires_at` = เวลาปัจจุบันพอดี** — ถือว่า**ยังไม่หมด** (ใช้ `>` ไม่ใช่ `>=`)
4. **`FLATTEN` ตอนตลาดปิด** — ตั้งสถานะได้ · การปิดจะล้มที่โบรกเกอร์ → retry ตอนเปิด + คงสถานะ
5. **`FLATTEN` เสร็จแล้ว (ไม่มี position เหลือ)** — **ยังคง `FLATTEN`** จนกว่าจะมี directive ใหม่
   · ห้ามปลดเองเพราะ "ทำเสร็จแล้ว" — mode คือคำสั่ง ไม่ใช่ task
6. **`flatten_symbols` มี symbol ที่บัญชีนี้ไม่มีไม้** — ไม่ใช่ error · no-op
7. **`flatten_symbols` มี symbol ที่ไม่รู้จัก** — ยังรับ directive · log WARN
   (SymbolRegistry SPEC-064 เป็นคน map · symbol ที่ map ไม่ได้ = ไม่มีไม้อยู่แล้ว)
8. **brain ตายตอน directive `REDUCE_ONLY` ค้างอยู่** — directive **ไม่หายไป** ·
   R16 SafeMode จะเพิ่ม `REDUCE_ONLY` ทับอีกชั้น → effective ยังเป็น `REDUCE_ONLY` ✅
9. **`expires_at` มาถึงตอน brain ตาย** — directive หมดอายุตามปกติ → เหลือ local + SafeMode(R16)
   **ไม่ใช่ NORMAL** เพราะ R16 ทำงานอยู่
10. **EA มี 2 ตัวบน terminal เดียว** — คนละ session → คนละ directive state · ไม่แชร์
11. **`scale_factor = 0.0` กับ mode `SCALED`** — ถูกต้องตาม schema · ผลคือทุก target เป็น 0
    = ปิดหมดแบบนุ่มนวล · **ต่างจาก `FLATTEN`** ตรงที่ยังรับ intent ได้ (แค่ได้ 0)
12. **directive_id ของ session ใหม่เล็กกว่าของ session เก่า** — เป็นไปได้ถ้านาฬิกา brain ถอย
    · ยังใช้กฎ §4.3 (ignore) · brain ต้องไม่สร้าง ULID ถอยหลัง — เป็นข้อบังคับของ SPEC-013

---

## 6. Acceptance criteria

- [ ] **matrix 25 ช่องผ่านครบ** (5 local × 5 directive) — §7.1 ★★
- [ ] `StricterOf()` มีที่เดียว · `grep -rn "GUARD_HALT\s*>\|> *FARM_GUARD" mt5-ea/` ไม่เจอการเทียบ mode มือ
- [ ] directive ใหม่ที่ผ่อนกว่าเก่า **แทนที่ได้** · แต่ effective ยังถูก local จำกัด (§4.2) ★★
- [ ] `local = HALT` + `directive = NORMAL` → effective **`HALT`** ★★
- [ ] `directive = HALT` + `local = NORMAL` → effective **`HALT`** ★★
- [ ] `target_volume = 0` ผ่านได้**ทุก mode รวม `HALT`** ★★
- [ ] `REDUCE_ONLY` ปฏิเสธการกลับข้าง (`+0.10 → −0.05`) (§4.5) ★
- [ ] `FLATTEN` + `flatten_symbols = []` → `MustFlatten()` คืน `true` ทุก symbol ★★
- [ ] `HALT` + `expires_at != null` → **reject** + คงสถานะเดิม + ตอบ `INTENT_ACK REJECTED_INVALID`
- [ ] `directive_id` เก่ากว่าปัจจุบัน → **ignore** + counter เพิ่ม · ไม่เปลี่ยนสถานะ
- [ ] **`IsValid()==false` → directive ไม่หมดอายุ** (§4.4) ★★
- [ ] reconnect → `HELLO_ACK.initial_directive` มีค่าตรงกับ directive ปัจจุบัน ·
      **ละ key** เมื่อไม่มี directive
- [ ] เขียน `risk_events` ไม่สำเร็จ → **ไม่ส่ง directive** (§4.8) ★
- [ ] ทุก reject ตอบ `INTENT_ACK` — ไม่มีเคสไหนเงียบ
- [ ] `pytest tests/unit/test_directive_precedence.py` — matrix เดียวกันฝั่ง Python ผ่านครบ
- [ ] compile 0 error 0 warning · gate เขียว (รวม suite ใหม่ใน `$RequiredSuiteNames`)

## 7. Test list

### 7.1 ★★ `tests/mql5/TestDirective.mq5` — matrix คือหัวใจ

```mql5
// test_precedence_matrix_25 -- วน 5×5 เทียบกับตารางที่ hardcode ไว้
// ห้ามคำนวณค่าคาดหวังด้วยสูตรเดียวกับที่ implement (จะผ่านทั้งที่สูตรผิด)
const ENUM_FARM_GUARD_MODE EXPECTED[5][5] = { … };   // เขียนมือทั้ง 25 ช่อง
```

**ข้อบังคับ:** ตารางคาดหวังต้อง**เขียนมือ** ไม่ใช่เรียก `StricterOf()` มาสร้าง
· test ที่ใช้สูตรเดียวกับโค้ดจะผ่านเสมอแม้สูตรผิด

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_precedence_matrix_25` | ★★ 5×5 ครบ |
| 2 | `test_local_halt_beats_directive_normal` | ★★ กฎเหล็ก |
| 3 | `test_directive_halt_beats_local_normal` | ★★ ทิศตรงข้าม |
| 4 | `test_newer_directive_may_relax_previous` | ★★ §4.2 |
| 5 | `test_relaxed_directive_still_bounded_by_local` | ★★ §4.2 |
| 6 | `test_scale_is_min_of_local_and_directive` | §4.1 |
| 7 | `test_flatten_empty_list_means_all_symbols` | ★★ §4.6 |
| 8 | `test_flatten_named_list_only_those` | §4.6 |
| 9 | `test_zero_target_allowed_in_every_mode` | ★★ §4.5 |
| 10 | `test_reduce_only_rejects_side_flip` | ★ §4.5 |
| 11 | `test_reduce_only_allows_shrink_toward_zero` | §4.5 |
| 12 | `test_halt_with_expiry_rejected` | §4.3 |
| 13 | `test_scaled_with_factor_one_rejected` | §4.3 |
| 14 | `test_out_of_order_directive_ignored` | §4.3 |
| 15 | `test_duplicate_directive_id_idempotent` | edge 2 |
| 16 | `test_expiry_releases_to_local_not_normal` | ★★ §4.4 |
| 17 | `test_no_expiry_when_broker_time_invalid` | ★★ §4.4 fail-closed |
| 18 | `test_expiry_exactly_now_not_expired` | edge 3 |
| 19 | `test_flatten_persists_after_positions_closed` | edge 5 |
| 20 | `test_every_reject_produces_intent_ack` | §4.3 |

### 7.2 `tests/unit/test_directive_precedence.py`

| # | test |
|---|------|
| 1 | `test_stricter_of_matrix_25` — **ตารางเดียวกับ MQL5 เป๊ะ** ★★ |
| 2 | `test_validate_rejects_halt_with_expiry` |
| 3 | `test_validate_rejects_scale_out_of_range` |
| 4 | `test_dispatcher_writes_risk_event_before_send` ★ |
| 5 | `test_dispatcher_does_not_send_when_db_write_fails` ★★ |
| 6 | `test_current_for_returns_none_after_expiry` |
| 7 | `test_hello_ack_omits_key_when_no_directive` — §4.7 · [02-contracts §8](../02-contracts.md) |
| 8 | `test_broadcast_skips_unauthenticated_sessions` — edge 1 |

> ★★ **test 1 ของทั้งสองฝั่งต้องได้ผลเหมือนกันทุกช่อง** — ถ้า MQL5 กับ Python
> ตีความความเข้มต่างกันแม้ช่องเดียว จะเกิดสถานะที่ brain คิดว่าจำกัดแล้วแต่ EA ไม่คิด
> · ให้ copy ตาราง 25 ช่องเป็น comment ที่เหมือนกันในทั้งสองไฟล์

## 8. Files

**Touch:** ตาราง §3.1

**ห้ามแตะ:**
- `contracts/schema/**` — ครบแล้ว ถ้าคิดว่าต้องเพิ่ม → implementation note
- `docs/**` · `AGENTS.md` · `CLAUDE.md`
- `brain/risk/` ไฟล์อื่นนอกจาก `directive.py` / `dispatcher.py` — **สงวนไว้ให้ SPEC-025**

**★ ข้อตกลงกับ SPEC-025:** `stricter_of()` · `STRICTNESS` · `validate()` · `DirectiveDispatcher`
เป็นของ ticket นี้ · **SPEC-025 ต้อง `import` ห้ามเขียนใหม่** — ถ้าเขียนซ้ำจะได้ตรรกะความเข้ม
สองชุดที่ค่อยๆ ต่างกัน ซึ่งเป็น bug ที่หาไม่เจอจนกว่าจะเสียเงิน

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | ควร persist directive ฝั่ง EA (GlobalVariable) ให้รอด restart ไหม | **ตอบแล้ว: ไม่** — brain เป็นแหล่งความจริง และ §4.7 ให้ทางกลับมาแล้ว · EA ที่จำเองจะมีสองแหล่งความจริงที่ไม่ตรงกันได้ · **แต่ `HALT` จาก local guard ยัง persist ตามเดิม** (SPEC-021/022) |
| Q2 | `SCALED` ควรคูณกับ lot ที่ R1 คำนวณแล้ว หรือคูณกับ `target_volume` ที่ brain ส่งมา | **ตอบแล้ว: คูณกับ `target_volume` ก่อนเข้า R1** — R1 ต้องเป็นด่านสุดท้ายเสมอ ไม่งั้น scale จะดัน lot ให้ต่ำกว่า `volume_min` แล้วถูก reject ด้วยเหตุผลที่อ่านไม่รู้เรื่อง ([SPEC-020](SPEC-020-lot-sizing.md)) |
| Q3 | brain ควรส่ง directive ซ้ำเป็นระยะ (keepalive) ไหม | **ไม่ต้องใน ticket นี้** — §4.7 ครอบ reconnect แล้ว · ถ้า SPEC-025 อยากได้ ให้เปิด ticket ใหม่ ไม่ใช่ขยายอันนี้ |

> **ไม่มีคำถามที่บล็อก — และ ticket นี้ไม่ขึ้นกับ D9/D10** (ดูกล่องบนสุด)

---

## ภาคผนวก — ทำไม matrix 25 ช่องถึงคุ้มกับที่เขียน

กฎ "เข้มได้ ผ่อนไม่ได้" ฟังดูง่ายจนไม่มีใครคิดว่าจะเขียนผิด แต่มันมี **สองความสัมพันธ์**
(§4.2) ที่หน้าตาเหมือนกัน และ implement ผิดได้ทั้งสองทาง:

| ผิดแบบ | อาการ | เจอเมื่อไร |
|--------|-------|-----------|
| `max()` กับ directive เก่า | ฟาร์มเข้มขึ้นทางเดียว ถอนไม่ออก | วันที่พยายามถอน `SCALED` — อาจเป็นเดือนถัดไป |
| directive ชนะ local | brain มี bug → ปลด halt ที่ R6 ตั้งไว้ | **วันที่เงินหาย** |

ทั้งสองอย่างจะไม่ถูกจับด้วย test ที่เขียนจากเคสที่นึกออก เพราะเคสที่นึกออกคือเคสที่เข้าใจถูกแล้ว
· 25 ช่องบังคับให้ตอบทุกคู่ รวมคู่ที่ไม่มีใครนึกถึงจนกว่าจะเกิด
