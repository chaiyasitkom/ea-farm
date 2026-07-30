# SPEC-029 — Telegram alerting

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-006, SPEC-014
**Blocks:** SPEC-062 (บางส่วน — ดู §2) · **อ้าง:** [G2](../06-gap-audit.md) · [risk-spec](../03-risk-spec.md) · [02-contracts §4.9](../02-contracts.md)

> 🔑 **ต้องมี bot token ก่อนรัน test ชั้น live** — สร้างผ่าน [@BotFather](https://t.me/BotFather)
> · **ไม่บล็อกการเขียนโค้ด** ทุก test ยกเว้น 1 ตัวใช้ fake transport (§7)

---

## 1. Goal

ทำให้เหตุการณ์ที่ต้องรู้**ทันที** ไปถึงมือถือเจ้าของภายใน ~10 วินาที
โดยที่ **alert storm ไม่ทำให้ alert สำคัญจม** และ **การส่งไม่สำเร็จต้องไม่เงียบ**

## 2. Non-goals

- ❌ **ห้ามให้ alert ไปบล็อกการเทรด** — Telegram ล่ม ≠ หยุดเทรด (ดู §4.6) ★★
- ❌ ห้ามเป็นคน**ตัดสิน**ว่าอะไรคือ breach — อ่านจาก `risk_events` ที่คนอื่นเขียนไว้
- ❌ ห้ามรับคำสั่งกลับจาก Telegram (ไม่มี bot command · ไม่มีปุ่ม flatten ผ่านแชท) ★
- ❌ ห้ามเป็นตัวเฝ้า brain เอง — **นั่นคือ SPEC-062** และมันต้องไม่พึ่ง ticket นี้
- ❌ ห้ามส่งข้อมูลบัญชี/token/password ลงแชท (§4.7)

---

## 3. Interface

### 3.1 ไฟล์

| ไฟล์ | ทำอะไร |
|------|--------|
| `brain/alerting/outbox.py` | **สร้าง** — เขียน alert ลงตาราง (transactional) |
| `brain/alerting/sender.py` | **สร้าง** — loop อ่าน outbox → ส่ง → mark |
| `brain/alerting/transport.py` | **สร้าง** — `TelegramTransport` + `Transport` protocol |
| `brain/alerting/rules.py` | **สร้าง** — เหตุการณ์ไหน → ระดับไหน (§4.2) |
| `brain/db/migrations/00X_alerts.sql` | **สร้าง** — ตาราง `alerts` |
| `tests/unit/test_alerting.py` | **สร้าง** |

### 3.2 API

```python
class Transport(Protocol):
    async def send(self, text: str) -> None: ...      # ยิง exception ถ้าส่งไม่สำเร็จ

class AlertOutbox:
    # เรียกในทรานแซกชันเดียวกับคนที่เขียน risk_events
    def enqueue(self, *, level: Level, key: str, title: str,
                body: str, dedupe_sec: int) -> None: ...

class AlertSender:
    async def run_forever(self) -> None: ...
    async def drain_once(self) -> int: ...            # คืนจำนวนที่ส่งสำเร็จ (ใช้ใน test)
```

`level` ∈ `INFO` · `WARN` · `BREACH` · `FATAL`
`key` = รหัสจับกลุ่มสำหรับ dedupe เช่น `P1_FARM_DAILY_LOSS:acct-3`

### 3.3 ตาราง `alerts`

```sql
CREATE TABLE alerts (
  id           BIGSERIAL PRIMARY KEY,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  level        TEXT NOT NULL,
  key          TEXT NOT NULL,
  title        TEXT NOT NULL,
  body         TEXT NOT NULL,
  suppressed_count INT NOT NULL DEFAULT 0,   -- กี่ตัวถูกยุบเข้ามาในใบนี้
  sent_at      TIMESTAMPTZ,                  -- NULL = ยังไม่ส่ง
  attempts     INT NOT NULL DEFAULT 0,
  last_error   TEXT
);
CREATE INDEX alerts_unsent ON alerts (created_at) WHERE sent_at IS NULL;
CREATE INDEX alerts_dedupe ON alerts (key, created_at DESC);
```

---

## 4. Behaviour

### 4.1 ★★ Outbox — เขียน DB ก่อน แล้วค่อยส่ง

```
เหตุการณ์เกิด → INSERT alerts (ในทรานแซกชันเดียวกับ risk_events) → COMMIT
                                  │
              sender loop ─────────┘  อ่านที่ sent_at IS NULL → ส่ง → UPDATE sent_at
```

| ทำไมไม่ยิง HTTP ตรงตอนเกิดเหตุ | |
|---|---|
| brain restart ระหว่างยิง | alert **หายไปเลย** ไม่มีใครรู้ว่าเคยมี |
| Telegram ช้า 3 วินาที | ไปหน่วง path ที่กำลังจัดการ risk อยู่ ★ |
| อยากรู้ย้อนหลังว่าเคยเตือนอะไรบ้าง | ไม่มีที่ให้ดู |

**`enqueue()` ต้องอยู่ในทรานแซกชันเดียวกับคนเขียน `risk_events`** — ถ้า risk event ถูก rollback
alert ต้องหายไปด้วย · ไม่งั้นจะเตือนเรื่องที่ไม่เคยเกิด

### 4.2 เหตุการณ์ไหน → ระดับไหน

| เหตุการณ์ | level | dedupe | แหล่ง |
|-----------|-------|--------|-------|
| `risk_events.level = BREACH` (P1–P11, R6, R7 hard) | `BREACH` | 60s | DB |
| kill switch ถูกกด | `FATAL` | **ไม่ dedupe** | SPEC-028 |
| EA เข้า `HALT` | `BREACH` | 300s ต่อ session | `account_state.guard_mode` |
| heartbeat หาย > 30s (P11) | `WARN` | 300s ต่อ session | `account_state.ts` |
| heartbeat หาย > 300s | `BREACH` | 900s ต่อ session | เดียวกัน |
| `foreign_position_count > 0` (R19) | `WARN` | 3600s | `account_state` |
| `internal_hedge_detected` (R18) | `BREACH` | 300s | `account_state` ★ anomaly |
| `ERROR` `severity = FATAL` จาก EA | `FATAL` | 60s ต่อ code | `errors` |
| `BROKER_TIME_OFFSET_CHANGED` | `INFO` | 3600s | SPEC-063 §4.4 |
| DB write ล้มเหลว | `FATAL` | 60s | SPEC-014 |
| guard mode เปลี่ยนไปทางเข้มขึ้น | `WARN` | 60s ต่อ session | `account_state` |
| guard mode ผ่อนลง | `INFO` | 300s | เดียวกัน |

**ไม่มี alert สำหรับ "ทุกอย่างปกติ"** — ยกเว้น digest รายวัน §4.5

### 4.2.1 📮 กริ่ง Handoff Bus — **ส่งแค่ว่ามีของ ไม่ส่งเนื้อของ** (เพิ่ม 2026-07-31)

[`handoff/`](../../handoff/README.md) เป็นช่องทางคุยระหว่าง Claude ↔ Codex บนดิสก์
· ปัญหาเดียวที่มันแก้ไม่ได้คือ **เจ้าของไม่รู้ว่าถึงคิวต้องเปิด session ไหน**

| เหตุการณ์ | level | dedupe |
|-----------|-------|--------|
| ไฟล์ใหม่ใน `handoff/to-claude/` หรือ `to-codex/` | `INFO` | 300s |
| ไฟล์ใหม่ที่มี `blocking: true` | `WARN` | **ไม่ dedupe** |
| ข้อความ `blocking: true` ค้างเกิน **4 ชั่วโมง** | `WARN` | 4h |

```
📮 มีงานรอ Claude review
handoff/to-claude/002-w1-socketsend.md · type=handoff · SPEC-016
```

#### ★ ส่งอะไร / ไม่ส่งอะไร

| ส่ง | **ห้ามส่ง** |
|-----|------------|
| ชื่อไฟล์ · `type` · `ticket` · `blocking` | **เนื้อหาข้อความ** |
| จำนวนที่ค้างในกล่อง | review ฉบับเต็ม · โค้ด · log · path ในเครื่อง |

**เหตุผลที่ห้ามส่งเนื้อหา — 4 ข้อ ไม่ใช่แค่เรื่องขนาด:**

1. **4096 ตัวอักษร** — review จริงยาว 300 บรรทัด ส่งไม่ได้ทั้งใบ ตัดแล้วอ่านผิดความหมาย
2. **format พัง** — §4.4 บังคับไม่ตั้ง `parse_mode` อยู่แล้ว · path กับชื่อ test เต็มไปด้วย `_`
3. ★ **สองแหล่งความจริง** — ถ้าเนื้อหาอยู่ทั้งในไฟล์และในแชท มันจะค่อยๆ ต่างกัน
   แล้ววันหนึ่งจะมีคนตัดสินใจจากฉบับที่ผิด · เป็น bug class เดียวกับ
   [02-contracts §8](../02-contracts.md) ที่ทั้งโปรเจกต์นี้ต่อสู้อยู่
4. **ไฟล์มีประวัติใน git · แชทไม่มี** — การตัดสินใจต้องสืบย้อนได้

> **หลักการ: ไฟล์ขนของ · Telegram สั่นกระเป๋า**
> Telegram ล่ม → เห็นช้าลงเท่านั้น · **งานไม่หาย และทำงานต่อได้ปกติ**
> ซึ่งตรงกับ §2 ที่ห้ามให้ alert ไปบล็อกอะไร

### 4.3 ★ Dedupe + storm cap — ห้ามให้ของสำคัญจม

```
ภายใน dedupe_sec ของ key เดียวกัน  →  ไม่สร้างแถวใหม่
                                       เพิ่ม suppressed_count ของแถวล่าสุดที่ยังไม่ส่ง
                                       ถ้าแถวนั้นส่งไปแล้ว → สร้างใหม่พร้อม "(ซ้ำ ×N)"
```

**Storm cap:** ส่งได้ไม่เกิน **20 ข้อความ / 5 นาที** · เกินกว่านั้นยุบเป็นใบเดียว
*"ยับยั้งไป N alert ใน 5 นาที · ระดับสูงสุด BREACH · ดู dashboard"*

| ข้อยกเว้นที่ห้ามยุบเด็ดขาด | |
|---|---|
| `FATAL` | ส่งเสมอ ทุกใบ ★★ |
| `BREACH` **ใบแรกของ key นั้น** | ส่งเสมอ · ใบที่ 2+ ยุบได้ |

**เหตุผล:** cap มีไว้กันจอเต็มจนคนเลิกอ่าน — ถ้า cap ไปกลืน BREACH ใบแรก
มันจะกลายเป็นสิ่งที่ทำให้พลาดเรื่องสำคัญ ซึ่งตรงข้ามกับที่มันมีไว้ทำ

### 4.4 รูปแบบข้อความ — ต้องมีตัวเลขจริง

```
🔴 BREACH · P1_FARM_DAILY_LOSS
farm day_pl = -3.2% (breach at -3.0%)
equity 8,412.55 / hwm 8,995.10 · 4 sessions
2026-07-30 14:22:07 UTC · acct-3
```

| กฎ | |
|----|---|
| บรรทัดแรก: emoji + level + `key` | กวาดตาหาได้เร็ว |
| **ต้องมีตัวเลขที่วัดได้** ไม่ใช่ *"daily loss เกิน"* | กฎเดียวกับ [02-contracts §4.9](../02-contracts.md) |
| เวลาเป็น **UTC** เสมอ + ระบุ `UTC` ตรงตัว | ตรงกับ log และ DB · ไม่ต้องเดา timezone ตอนตี 3 |
| ท้ายข้อความ: `session_id` ถ้าเกี่ยวกับบัญชีเดียว | |
| **ห้ามใช้ Markdown ของ Telegram** | ตัวเลขที่มี `_` หรือ `*` จะทำให้ parse พังแล้ว**ส่งไม่ออกทั้งใบ** → ใช้ `parse_mode` = ไม่ตั้ง (plain text) ★ |

### 4.5 Digest รายวัน — INFO ใบเดียว

ส่งเวลา **00:05 broker time** ของวันใหม่ (ใช้ `broker_utc_offset_sec` จากสายตาม
[SPEC-063 §3.3](SPEC-063-broker-time.md) · **ห้ามคำนวณ offset เอง**):
จำนวน session · equity รวม · day P/L · จำนวน risk event แยกตามระดับ · alert ที่ถูกยุบ

**จุดประสงค์คือพิสูจน์ว่าท่อยังทำงาน** — วันที่ digest ไม่มา = มีอะไรพัง
แม้จะไม่มี alert อื่นเลย · นี่คือ heartbeat ของระบบ alert เอง

### 4.6 ★★ ส่งไม่สำเร็จ — ห้ามเงียบ และห้ามลาม

| สถานการณ์ | ทำอะไร | **ห้าม**ทำ |
|-----------|--------|-----------|
| HTTP error / timeout | retry แบบ backoff `2s → 4s → 8s → 30s → 60s` (สูงสุด 5 ครั้ง) · เก็บ `last_error` | retry ถี่จนโดน rate limit |
| ครบ 5 ครั้งแล้วยังไม่ได้ | **เขียน log `FATAL` + คงแถวไว้ `sent_at IS NULL`** | ลบแถวทิ้ง ★ |
| Telegram ล่มยาว | ระบบ**เทรดต่อตามปกติ** | บล็อก · ทำให้ risk path ช้า ★★ |
| `sent_at IS NULL` เก่ากว่า 5 นาที | `/health` ของ sender ต้องรายงาน `unsent_backlog` + อายุใบเก่าสุด | ปล่อยให้ดูปกติ |

**ใครเป็นคนบอกว่า alert ส่งไม่ออก** — ไม่ใช่ ticket นี้ (มันคือคนที่พังอยู่)
· `/health` เปิดไว้ให้ **SPEC-062 watchdog** มาอ่าน · **นั่นคือคำตอบของ [G2](../06-gap-audit.md)**

### 4.7 ห้ามหลุดความลับลงแชท

| ห้ามส่ง | |
|---------|---|
| `DASHBOARD_TOKEN` · bot token · รหัสผ่าน DB | ชัดเจน |
| เลขบัญชีเต็ม | ใช้ `session_id` หรือ alias (`acct-3`) แทน |
| stack trace เต็ม | ส่งแค่ exception type + บรรทัดแรก · เต็มไปอยู่ใน log |

**Acceptance ต้องมี test ที่ยิง alert จากทุก rule แล้ว assert ว่าไม่มี secret หลุด** (§7 test 14)

---

## 5. Edge cases

1. **bot token ผิด / ถูก revoke** — Telegram ตอบ 401 → **ห้าม retry** (ไม่มีวันสำเร็จ)
   → log `FATAL` ทันที + `last_error` ชัดเจน
2. **chat_id ผิด** — 400 `chat not found` → เหมือนข้อ 1 ห้าม retry
3. **ข้อความยาวเกิน 4096 ตัวอักษร** — ตัดที่ 4000 + `… (ตัด)` · **ห้ามส่งไม่ออกทั้งใบ**
4. **สอง sender รันพร้อมกัน** (เผลอเปิดซ้ำ) — `SELECT … FOR UPDATE SKIP LOCKED` กันส่งซ้ำ ★
5. **DB ล่ม** — `enqueue()` ล้มไปพร้อมทรานแซกชันแม่ (ถูกต้อง) · sender loop retry เงียบๆ
   จนกว่า DB กลับมา · **ห้าม crash ทั้ง process**
6. **นาฬิกาเครื่องเพี้ยน** — `created_at` ใช้ `now()` ของ DB ไม่ใช่ของ Python
7. **alert เกิดตอน sender ยังไม่สตาร์ท** — ไม่หาย เพราะอยู่ใน outbox แล้ว → ส่งตอนสตาร์ท
   · **แต่ต้องไม่ส่งย้อนหลังเกิน 1 ชั่วโมง** (`created_at` เก่ากว่านั้น → mark `sent_at` +
   `last_error='too_old'`) ไม่งั้นเปิดเครื่องมาแล้วโดนถล่ม 200 ข้อความจากเมื่อวาน ★
8. **`suppressed_count` ล้น** — cap ที่ 999 แล้วแสดง `999+`

---

## 6. Acceptance criteria

- [ ] `enqueue()` อยู่ในทรานแซกชันเดียวกับ `risk_events` — rollback แล้ว alert หายด้วย ★★
- [ ] Telegram ล่ม → **ระบบยังเทรดต่อ** · latency ของ risk path ไม่เปลี่ยน ★★
- [ ] ส่งไม่สำเร็จครบ 5 ครั้ง → แถวยังอยู่ `sent_at IS NULL` + log FATAL · **ไม่ถูกลบ** ★★
- [ ] `FATAL` **ไม่เคยถูก storm cap ยุบ** · `BREACH` ใบแรกของ key ก็ไม่ถูกยุบ ★★
- [ ] 401/400 → **ไม่ retry** เลย (ไม่ใช่ retry 5 ครั้งแล้วยอมแพ้)
- [ ] ข้อความ > 4096 → ตัดแล้วส่งได้ ไม่ใช่ส่งไม่ออก
- [ ] ไม่ตั้ง `parse_mode` — ตัวเลขที่มี `_` `*` ส่งผ่านได้ (test ด้วย `-3.2%_x*y`)
- [ ] สอง sender พร้อมกัน → ไม่มีข้อความซ้ำ (`SKIP LOCKED`)
- [ ] alert เก่ากว่า 1 ชม. ตอนสตาร์ท → ไม่ส่ง · mark ว่า `too_old` ★
- [ ] `/health` รายงาน `unsent_backlog` + อายุใบเก่าสุด
- [ ] digest รายวันใช้ **broker time จากสาย** ไม่ใช่คำนวณ offset เอง ★
- [ ] **ไม่มี secret หลุดลงข้อความ** — test วนทุก rule (§7 test 14) ★★
- [ ] ไม่มี bot command handler ใดๆ · `grep -rn "getUpdates\|setWebhook" brain/alerting/` ไม่เจอ ★
- [ ] `ruff` · `mypy` · `pytest` ผ่าน

## 7. Test list — `tests/unit/test_alerting.py`

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_enqueue_rolls_back_with_parent_txn` | ★★ §4.1 |
| 2 | `test_sender_survives_transport_failure` | ★★ §4.6 |
| 3 | `test_failed_alert_row_is_kept_not_deleted` | ★★ §4.6 |
| 4 | `test_backoff_sequence_2_4_8_30_60` | §4.6 |
| 5 | `test_401_does_not_retry` | edge 1 |
| 6 | `test_400_chat_not_found_does_not_retry` | edge 2 |
| 7 | `test_dedupe_increments_suppressed_count` | §4.3 |
| 8 | `test_storm_cap_collapses_after_20_in_5min` | §4.3 |
| 9 | `test_fatal_never_capped` | ★★ §4.3 |
| 10 | `test_first_breach_of_key_never_capped` | ★★ §4.3 |
| 11 | `test_long_message_truncated_not_dropped` | edge 3 |
| 12 | `test_no_parse_mode_so_underscores_survive` | §4.4 |
| 13 | `test_two_senders_no_duplicate_send` | ★ edge 4 |
| 14 | `test_no_secret_in_any_rendered_alert` | ★★ §4.7 · วนทุก rule + assert ไม่เจอค่าใน `.env` |
| 15 | `test_stale_alerts_marked_too_old_on_start` | ★ edge 7 |
| 16 | `test_message_contains_real_numbers` | §4.4 · regex หาตัวเลขในทุก template |
| 17 | `test_digest_uses_broker_offset_from_wire` | ★ §4.5 |
| 18 | `test_health_reports_unsent_backlog` | §4.6 |
| 19 | `test_live_send_to_real_telegram` | 🔑 **marker `live`** — ข้ามได้ถ้าไม่มี token · ต้องรันจริงอย่างน้อย 1 ครั้งก่อนปิด ticket |

## 8. Files

**Touch:** `brain/alerting/**` · `brain/db/migrations/00X_alerts.sql`
· `tests/unit/test_alerting.py` · `.env.example` (`TELEGRAM_BOT_TOKEN` · `TELEGRAM_CHAT_ID`)
· `brain/gateway/*` เฉพาะจุดที่เรียก `enqueue()` · `tools/task.py`

**ห้ามแตะ:** `mt5-ea/**` · `contracts/**` · `docs/**` · `brain/dashboard/**` · `brain/risk/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | ใช้ Telegram หรือช่องทางอื่น | **ตัดสินแล้ว: Telegram** — ฟรี · มีแอปบนมือถือ · API เป็น HTTP POST ธรรมดา ไม่ต้องมี SDK · `Transport` เป็น protocol อยู่แล้ว เปลี่ยนทีหลังได้โดยไม่แตะ rule |
| Q2 | ควรมีปุ่มใน Telegram ให้กด flatten ไหม | **ไม่ — และห้าม** · แชทถูก forward ได้ · บัญชี Telegram ถูกยึดได้ · kill switch มีทางเดียวคือ [SPEC-028](SPEC-028-dashboard-kill-switch.md) + ไฟล์ |
| Q3 | ส่งเข้า group หรือ chat ส่วนตัว | **เจ้าของเลือกตอนตั้ง `TELEGRAM_CHAT_ID`** — โค้ดไม่ต่างกัน · แนะนำ group ที่มีคนเดียวไว้ก่อน จะได้เพิ่มคนทีหลังโดยไม่ต้องแก้ config |

---

## ภาคผนวก — ใครเฝ้าคนเฝ้า

ticket นี้แก้ครึ่งเดียวของ [G2](../06-gap-audit.md) · อีกครึ่งคือ **ถ้า brain ตายทั้งตัว
โมดูลนี้ก็ตายไปด้วย แล้วความเงียบจะดูเหมือนความสงบ**

โครงสร้างที่ ticket นี้วางไว้ให้ [SPEC-062](SPEC-062-watchdog.md) ใช้ต่อ:

| | |
|---|---|
| `/health` ของ sender | watchdog อ่านได้โดยไม่ต้อง import อะไร |
| digest รายวัน (§4.5) | วันที่ไม่มา = สัญญาณ แม้ไม่มี alert อื่น |
| `Transport` protocol | watchdog **ก๊อปโค้ด 30 บรรทัดไปใช้เอง** ห้าม import — เหตุผลอยู่ใน SPEC-062 |
