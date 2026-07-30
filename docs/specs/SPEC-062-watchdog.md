# SPEC-062 — Watchdog: ใครแจ้งเมื่อ brain ตาย

**Phase:** 2 ★ · **Owner:** Codex · **Depends on:** SPEC-028, SPEC-029 (เฉพาะ `/health` ที่จะไป poll)
**ปิดช่องว่าง:** [G2](../06-gap-audit.md) · **ต้องเสร็จก่อนจบ Phase 2 (ก่อนเงินจริง)**

> ## ★★ กฎข้อเดียวที่สำคัญกว่าทุกข้อในเอกสารนี้
>
> **watchdog ห้ามพึ่งอะไรที่ brain พึ่ง** — ไม่ import · ไม่แชร์ venv · ไม่ต่อ DB ·
> ไม่ใช้ third-party package แม้แต่ตัวเดียว
>
> ถ้าละเมิดข้อนี้ ticket นี้จะกลายเป็นสิ่งที่**ดูเหมือนมี** แต่ตายพร้อมกับสิ่งที่มันเฝ้า
> ซึ่งแย่กว่าไม่มีเลย เพราะจะทำให้เจ้าของนอนหลับสนิทกว่าเดิม

---

## 1. Goal

process เล็กที่สุดที่เป็นไปได้ คอยตรวจว่า brain · dashboard · ท่อ alert ยังทำงานอยู่
และ**ส่งข้อความหาเจ้าของด้วยตัวเองเมื่อไม่ใช่** โดยไม่พึ่งอะไรที่กำลังพังอยู่

## 2. Non-goals

- ❌ **ห้าม restart brain อัตโนมัติใน v1** — ดู §4.6 · นั่นคือ **SPEC-053** (NSSM · Phase 6)
- ❌ ห้ามต่อ PostgreSQL ★★
- ❌ ห้าม `import` อะไรจาก `brain/` ★★
- ❌ ห้ามลง third-party package (ไม่มี `httpx` · ไม่มี `requests` · ไม่มี `pydantic`) ★★
- ❌ ห้ามตัดสินใจเรื่อง risk / ส่ง order / เขียนไฟล์ kill
- ❌ ห้ามอ่าน log ของ brain เพื่อวิเคราะห์ (เปราะและช้า) — ใช้ `/health` เท่านั้น

---

## 3. Interface

### 3.1 ไฟล์ — อยู่นอก `brain/` โดยตั้งใจ

```
watchdog/
  watchdog.py          ← ไฟล์เดียว · stdlib ล้วน · ต้องรันด้วย python.exe ของระบบได้
  watchdog.example.ini ← config แยกจาก .env ของ brain  ★
tests/unit/test_watchdog.py
```

| ข้อบังคับ | เหตุผล |
|-----------|--------|
| **ไฟล์เดียว** ไม่มี package ย่อย | อ่านจบใน 5 นาที · ตรวจสอบด้วยตาได้ทั้งไฟล์ |
| **stdlib ล้วน** (`urllib.request` · `json` · `configparser` · `time` · `logging`) | `pip install` ที่พังจะไม่ลากมันลงไปด้วย |
| **config แยกจาก `.env`** | `.env` เสีย/ถูกแก้ผิด = brain ตาย · watchdog ต้องรอด |
| รันด้วย **python ของระบบ ไม่ใช่ venv ของ brain** | venv พังคือหนึ่งในสาเหตุที่ brain ตาย |

### 3.2 สิ่งที่ตรวจ

| # | เป้า | วิธี | ถือว่าตายเมื่อ |
|---|------|------|---------------|
| 1 | gateway | `GET http://127.0.0.1:<port>/health` | timeout 5s · ไม่ 200 · หรือ `ok != true` |
| 2 | dashboard | `GET /health` ([SPEC-028 §3.3](SPEC-028-dashboard-kill-switch.md)) | เหมือนกัน |
| 3 | ท่อ alert | `/health` ของ sender → `unsent_backlog` | backlog > 0 และใบเก่าสุด > **300 วินาที** |
| 4 | ความสดของข้อมูล | `newest_state_age_sec` จาก `/health` ของ dashboard | > **120 วินาที** |
| 5 | ตัวเอง | — | §4.5 |

**ข้อ 4 คือเหตุผลที่ต้อง poll dashboard ด้วย ไม่ใช่แค่ gateway** — gateway ตอบ `ok`
ได้ทั้งที่ไม่มี EA ตัวไหนส่งอะไรมาเลย 2 ชั่วโมง · "process ยังอยู่" ≠ "ระบบยังทำงาน"

### 3.3 `watchdog.ini`

```ini
[targets]
gateway_health   = http://127.0.0.1:8765/health
dashboard_health = http://127.0.0.1:8781/health
alert_health     = http://127.0.0.1:8782/health

[thresholds]
poll_sec              = 15
fail_streak_to_alert  = 3     ; 3 × 15s = แจ้งหลังตายจริง ~45 วินาที
repeat_alert_min      = 30
state_age_sec         = 120
alert_backlog_sec     = 300

[telegram]
bot_token = ...
chat_id   = ...

[heartbeat]
daily_ok_hour_utc = 1
```

**`bot_token` ซ้ำกับของ brain โดยตั้งใจ** — ดู §4.4

---

## 4. Behaviour

### 4.1 Loop

```
ทุก poll_sec:
   สำหรับแต่ละเป้า:
      ok  → fail_streak = 0 · ถ้าเคยแจ้งว่าตาย → ส่ง RECOVERED
      พัง → fail_streak++
            ถ้า fail_streak == fail_streak_to_alert     → ส่ง DOWN
            ถ้า fail_streak > … และครบ repeat_alert_min → ส่ง STILL DOWN
```

`fail_streak_to_alert = 3` กัน false positive จากการ restart ปกติหรือ GC ค้างชั่วครู่
· **ห้ามแจ้งตั้งแต่ครั้งแรกที่ต่อไม่ติด** — จะกลายเป็น alert ที่คนเลิกอ่าน

### 4.2 ★ ข้อความต้องบอกว่าให้ทำอะไร ไม่ใช่แค่ว่ามีอะไรพัง

```
🚨 WATCHDOG · GATEWAY DOWN
ต่อ http://127.0.0.1:8765/health ไม่ได้ 3 ครั้งติด (45 วินาที)
ล่าสุดที่ยังดี: 2026-07-30 14:21:03 UTC

EA ยังมี SL ฝั่งโบรกเกอร์อยู่ · จะเข้า SafeMode REDUCE_ONLY เองใน 10 วิ (R16)
ถ้าต้องหยุดทั้งหมด: วางไฟล์ farm_kill.txt (ดู runbook §kill)
```

**สามบรรทัดท้ายสำคัญที่สุด** — คนที่เพิ่งตื่นมาอ่านต้องรู้ทันทีว่า
(ก) ตอนนี้อันตรายแค่ไหน (ข) ระบบกำลังป้องกันตัวเองยังไง (ค) ถ้าจะลงมือต้องทำอะไร
· ข้อความที่บอกแค่ *"gateway down"* ทำให้คนตื่นตระหนกโดยไม่รู้จะทำอะไร

### 4.3 ต้องรู้ว่า "ตาย" กับ "ไม่มีเน็ต" ต่างกัน

ถ้าส่ง Telegram ไม่ออกด้วย = **อาจเป็นเน็ตของ VPS เอง ไม่ใช่ brain**

| | ทำ |
|---|-----|
| poll ล้มทุกเป้า **และ** ส่ง Telegram ไม่ออก | เขียน `watchdog.log` + **retry ต่อไปเรื่อยๆ ไม่ยอมแพ้** · ส่งทันทีที่เน็ตกลับมา พร้อมบอกว่าตายมาตั้งแต่เมื่อไร |
| poll ล้มบางเป้า · Telegram ส่งออกได้ | brain พังจริง — แจ้งตามปกติ |

**ห้าม exit ไม่ว่ากรณีใด** — watchdog ที่ตายเองคือความล้มเหลวที่เงียบที่สุดในระบบทั้งหมด
· ทุก exception ต้องถูกจับที่ loop นอกสุด log แล้ววนต่อ

### 4.4 ทำไมถึงก๊อป 30 บรรทัดแทนที่จะ import — และทำไมนั่นถูก

`brain/alerting/transport.py` ([SPEC-029](SPEC-029-telegram-alerting.md)) มีโค้ดส่ง Telegram อยู่แล้ว
**ห้าม import** · เขียนใหม่ด้วย `urllib.request` ~30 บรรทัด

| ปกติการก๊อปโค้ดเป็นหนี้ | ที่นี่มันคือ**คุณสมบัติ** |
|------------------------|--------------------------|
| แก้ที่เดียวไม่ครบทุกที่ | ถ้าแก้ที่เดียวแล้วครบทุกที่ = **พังที่เดียวก็พังทุกที่** ซึ่งคือสิ่งที่ ticket นี้มีไว้ป้องกัน |

`bot_token` ซ้ำใน 2 config ด้วยเหตุผลเดียวกัน · **เขียน comment บอกไว้ในไฟล์ทั้งสองฝั่ง**
ว่าความซ้ำนี้ตั้งใจ ห้ามใครมา refactor รวม

### 4.5 ★★ ใครเฝ้า watchdog — โซ่ต้องจบที่คน

watchdog ตายเงียบ = กลับไปที่ G2 พอดี · v1 แก้ด้วย **daily OK ping**:

```
ทุกวันเวลา daily_ok_hour_utc → ส่ง
✅ WATCHDOG OK · uptime 6d 4h · ตรวจ 3/3 เป้าปกติ · เตือนไป 2 ครั้งใน 24 ชม.
```

**กฎที่ต้องเขียนลง runbook (SPEC-030b): วันที่ไม่ได้รับข้อความนี้ = ต้องไปดูเครื่อง**
· นี่คือจุดที่โซ่จบ — **จบที่มนุษย์โดยตั้งใจ ไม่ใช่เพราะลืม**

> ยอมรับตรงๆ ว่านี่ยังไม่แข็ง: ถ้าเจ้าของไม่สังเกตว่าข้อความไม่มา ก็เท่าเดิม
> ทางที่แข็งกว่าคือ **dead-man's switch ภายนอก** (บริการนอกที่คอยรับ ping
> แล้วเตือนเมื่อ ping ขาด) — ต้องมีบริการนอก + บัญชี จึงเป็น **Q1 §9 ไม่ใช่ของ v1**

### 4.6 ทำไม v1 ไม่ restart brain ให้

| เหตุผล | |
|--------|---|
| flapping | brain ที่พังเพราะ config ผิดจะถูก restart วนไม่รู้จบ · alert ท่วม · log เต็มดิสก์ |
| double-run | restart ผิดจังหวะ = gateway 2 ตัวแย่ง port แย่ง session → **สถานะบัญชีสองชุด** ★ |
| ปิดบังปัญหา | restart สำเร็จเงียบๆ = bug ที่ทำให้ crash ไม่มีใครไปแก้ จนวันที่มันพังตอนที่ restart ไม่ช่วย |

**การ restart เป็นงานของ service manager ที่ออกแบบมาเพื่อสิ่งนี้** (NSSM · SPEC-053)
ซึ่งจัดการ backoff และ single-instance ได้ถูกต้อง · watchdog มีหน้าที่ **บอก** ไม่ใช่ **ซ่อม**

### 4.7 ติดตั้ง

**Windows Scheduled Task** trigger `At startup` + `Restart on failure every 1 minute`
· รันด้วย `pythonw.exe` ของระบบ · ส่งไฟล์ `.xml` ของ task ไว้ในรีโปให้ import ได้

**ไม่ใช้ NSSM ใน ticket นี้** — NSSM เป็นของ SPEC-053 และการเพิ่ม dependency ตอนนี้
ขัดกับกฎข้อแรกของเอกสารนี้ · Scheduled Task มีในทุกเครื่อง Windows อยู่แล้ว

---

## 5. Edge cases

1. **brain restart ปกติ (deploy)** — หายไป ~10s < `3 × 15s` → **ไม่แจ้ง** ✅ ตามเจตนา
2. **VPS reboot** — Scheduled Task `At startup` พา watchdog กลับมา · ตอนสตาร์ทต้อง
   **รอ 60 วินาทีก่อน poll ครั้งแรก** ไม่งั้นจะแจ้ง "ทุกอย่างตาย" ทุกครั้งที่รีบูต ★
3. **นาฬิกาเครื่องเพี้ยน** — ใช้ `time.monotonic()` สำหรับทุกช่วงเวลา ·
   ใช้เวลาจริงเฉพาะตอนแสดงผลและ daily ping
4. **daily ping ตรงกับช่วง brain ตาย** — ส่งทั้งสองข้อความ ไม่ยุบรวม
5. **`/health` ตอบ 200 แต่ body ไม่ใช่ JSON** — ถือว่าพัง (บ่งว่ามีอะไรผิดจริง)
6. **`/health` ตอบช้า 4.9 วินาที ทุกครั้ง** — ยังไม่ timeout แต่ **ผิดปกติ** →
   log WARN · ไม่ต้องแจ้ง Telegram (ไม่งั้นจะกลายเป็น alert เรื้อรัง)
7. **สอง watchdog รันพร้อมกัน** — จะได้ข้อความซ้ำ · กันด้วย lock file
   `%TEMP%\ea-farm-watchdog.lock` ที่มี pid · **ตัวที่สองต้อง exit พร้อม log** (ข้อยกเว้นเดียวของ §4.3)
8. **ดิสก์เต็ม** — `watchdog.log` เขียนไม่ได้ → **ห้าม crash** · ส่ง Telegram ต่อได้ก็พอ

---

## 6. Acceptance criteria

- [ ] `grep -rn "^import\|^from" watchdog/watchdog.py` — **มีแต่ stdlib** ★★
- [ ] `grep -rn "brain\|psycopg\|httpx\|requests\|pydantic\|fastapi" watchdog/` — **ไม่เจอ** ★★
- [ ] รันด้วย `python.exe` ของระบบ (ไม่ใช่ venv) สำเร็จบนเครื่องเปล่า ★★
- [ ] **kill gateway → ได้ข้อความภายใน ~45 วินาที** (พิสูจน์ด้วยการฆ่าจริง) ★★
- [ ] กู้ gateway กลับ → ได้ข้อความ `RECOVERED`
- [ ] **kill ทั้ง brain (gateway + dashboard + sender) → ยังได้ข้อความ** ★★
- [ ] ถอดสาย/บล็อกเน็ต → watchdog **ไม่ตาย** · ต่อเน็ตกลับ → ส่งย้อนพร้อมเวลาที่เริ่มพัง ★★
- [ ] restart brain ปกติ (< 45s) → **ไม่มีข้อความ** (ไม่ใช่ false positive) ★
- [ ] `newest_state_age_sec > 120` ทั้งที่ทุก process ยังตอบ `ok` → **แจ้ง** ★★
- [ ] daily OK ping ส่งจริงตามเวลา
- [ ] watchdog ตัวที่สอง → exit พร้อม log ไม่ส่งซ้ำ
- [ ] โยน exception ในทุกจุดของ loop → **ไม่ exit** วนต่อได้ (test ด้วย fake ที่ยิง error) ★★
- [ ] รอ 60 วินาทีก่อน poll ครั้งแรก (edge 2)
- [ ] `watchdog.py` **ยาวไม่เกิน 300 บรรทัด** — ถ้าเกิน แปลว่าใส่ของที่ไม่ควรอยู่ ★
- [ ] ส่ง `.xml` ของ Scheduled Task ไว้ในรีโป + ขั้นตอนติดตั้งในหนึ่งหน้า

## 7. Test list — `tests/unit/test_watchdog.py`

> test ทั้งหมดต้อง**ฉีด fake HTTP + fake transport + fake clock** ไม่แตะเน็ตจริง
> ยกเว้น test 13

| # | test | ตรวจอะไร |
|---|------|----------|
| 1 | `test_alerts_after_three_consecutive_failures` | §4.1 |
| 2 | `test_no_alert_on_single_failure` | ★ §4.1 |
| 3 | `test_no_alert_when_restart_shorter_than_streak` | ★ edge 1 |
| 4 | `test_recovered_message_after_down` | §4.1 |
| 5 | `test_repeat_alert_respects_interval` | §4.1 |
| 6 | `test_stale_state_age_triggers_alert_even_when_all_ok` | ★★ §3.2 ข้อ 4 |
| 7 | `test_alert_backlog_triggers_alert` | §3.2 ข้อ 3 |
| 8 | `test_loop_survives_exception_in_every_stage` | ★★ §4.3 |
| 9 | `test_never_exits_when_telegram_unreachable` | ★★ §4.3 |
| 10 | `test_queues_and_sends_after_network_returns` | ★★ §4.3 |
| 11 | `test_second_instance_exits_via_lockfile` | edge 7 |
| 12 | `test_waits_60s_before_first_poll` | edge 2 |
| 13 | `test_daily_ok_ping_sent_once_per_day` | §4.5 |
| 14 | `test_uses_monotonic_for_durations` | edge 3 |
| 15 | `test_non_json_health_body_counts_as_down` | edge 5 |
| 16 | `test_message_includes_what_to_do` | ★ §4.2 · assert มีคำว่า `farm_kill` และ `R16` |
| 17 | `test_survives_unwritable_log_file` | edge 8 |

**test 6 · 8 · 9 · 10 คือสี่ตัวที่ห้ามพลาด** — 6 คือ "process อยู่แต่ระบบตาย" ·
8/9/10 คือความสามารถในการอยู่รอดของตัว watchdog เอง ซึ่งเป็นเหตุผลทั้งหมดที่มันมีอยู่

## 8. Files

**Touch:** `watchdog/watchdog.py` · `watchdog/watchdog.example.ini`
· `watchdog/ea-farm-watchdog-task.xml` · `tests/unit/test_watchdog.py`
· `README.md` เฉพาะส่วนติดตั้ง (ต้องขออนุมัติ Claude ก่อน — เป็นไฟล์ของ Claude)

**ห้ามแตะ:** `brain/**` ★★ · `mt5-ea/**` · `contracts/**` · `docs/**`

## 9. Open questions

| # | คำถาม | สถานะ |
|---|-------|-------|
| Q1 | เอา **dead-man's switch ภายนอก** ไหม (บริการนอกเตือนเมื่อ ping ขาด) | **ไม่บล็อก v1** — daily ping (§4.5) พอสำหรับ Phase 2 · แต่ควรตัดสินก่อนขึ้นทุนเต็ม เพราะเป็นช่องเดียวที่เหลือ · **เสนอเป็น D18 ให้เจ้าของ** ตอนถึง Phase 7 |
| Q2 | watchdog ควรเฝ้า MT5 terminal ด้วยไหม (process ยังอยู่?) | **ไม่ใน v1** — terminal ตาย → heartbeat หาย → เข้าข้อ 4 (`newest_state_age_sec`) อยู่แล้ว · เฝ้าตรงๆ ต้องรู้ pid ของแต่ละ terminal ซึ่งเป็นงานของ SPEC-053 |
| Q3 | เก็บประวัติ uptime ไหม | **ไม่** — ต้องมีที่เก็บ = dependency · `watchdog.log` พอ |
