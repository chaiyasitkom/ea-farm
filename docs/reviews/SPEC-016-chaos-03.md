# Review — SPEC-016 ชั้น A รอบ 3 · **ปิด W1 และ chaos เขียวครบ**

**วันที่:** 2026-07-31 · **ผู้ตรวจ:** Claude
**อ้าง:** [chaos รอบ 2](SPEC-016-chaos-02.md) · [work-order](../work-order.md) · handoff 001–017

## ผลตัดสิน: 🟢 `APPROVED_WITH_NOTES`

```
CHAOS GATE: PASSED -- skipped=1
Ran 6 tests in 256.761s · OK (skipped=1)
```

| gate | ผล |
|------|-----|
| `compile-gate.ps1` | ✅ 3 target · 0 error 0 warning · `.mqh` ครบ |
| `run-mql5-tests.ps1` | ✅ TestWire **53/53** · TestBrokerTime **67/67** |
| `run-chaos.ps1` (fast) | ✅ **PASSED** — 5 ผ่าน · 1 skip (soak 1 ชม.) |

---

## เส้นทางของ W1 — 5 รอบ และบทเรียนที่ต้องเก็บ

| รอบ | แก้อะไร | ผล |
|-----|---------|-----|
| 1 | `SocketTimeouts()` | ❌ หักล้างด้วย log ที่เพิ่มเข้าไปเอง |
| 2 | **deferred hello** (แยก connect/send คนละ `Pump()`) | ✅ ทำให้ HELLO **ส่งออก**ได้ครั้งแรก |
| 3 | drain-before-disconnect (F1) | ❌ ไม่ช่วย · revert |
| 4 | **`FileFlush()` diag file** — เลิกแก้ตรรกะ ไปทำให้มองเห็น | ★ **จุดเปลี่ยน** |
| 5 | `SocketRead` ขอไม่เกิน `avail` | ✅ **ต้นเหตุจริง** |

### ต้นเหตุที่แท้จริง

```mql5
while(SocketIsReadable(m_socket))                              // ← ใช้ค่า byte เป็น bool
   SocketRead(m_socket, buf, FARM_WIRE_READ_CHUNK_BYTES, 0);   // ← ขอ 4096 เสมอ
```

`SocketIsReadable()` ของ MQL5 คืน **จำนวน byte ที่อ่านได้** · โค้ดเดิมขอ `SocketRead` 4096 byte
ทุกครั้ง → **บล็อกรอจนครบ 4096 หรือจน server ตัด** · HELLO_ACK ยาวไม่กี่ร้อย byte จึงไม่มีวันครบ

| | ก่อน | หลัง |
|---|------|------|
| `pump_us` สูงสุด | **29,031,694** | **16,576** |
| เทียบเกณฑ์ [SPEC-001 §1.7](../work-order.md) (p99 < 20,000) | ❌ เกิน **1,450 เท่า** | ✅ ผ่าน |
| `pump_slow` | ทุกครั้ง | **0** |
| `inbound` | ไม่มีเลย | `HELLO_ACK` · `HEARTBEAT` |
| state สูงสุด | `AUTHENTICATING` | **`READY`** |

### 📌 บทเรียนที่ควรเป็นกฎถาวร

> **เดาผิดติดกัน 2 ครั้ง → หยุดเดา แล้วลงทุนกับการมองเห็น**

รอบ 1–3 เป็นการเดาที่ผิดทั้งหมด · รอบ 4 เลิกแก้ตรรกะแล้วทำ `FileFlush()` diag
→ รอบ 5 จบทันทีเพราะ **เห็นตัวเลข 29,031,694 µs ด้วยตาตัวเอง**

เกิดรูปแบบเดียวกันสองครั้งในวันเดียว — อีกครั้งคือตอนไล่ MT5 whitelist
ซึ่งจบได้เพราะเจอวิธีอ่าน `common.ini` **ไม่ใช่เพราะเดาถูก**

---

## หลักฐานพฤติกรรมที่ผ่านจริง

### backoff ladder — พิสูจน์ครบถึง cap

```
 0.00s  ← EA ชีวิตแรก (MT5 re-init ตอนโหลด history)
+11.05s ← ช่องว่างจาก re-init
+ 1.99s ┐
+ 2.02s │
+ 5.00s ├── 1, 2, 4, 8, 16, 30 + granularity ของ EventSetTimer(1)
+ 8.99s │
+17.00s │
+30.00s ┘  ★ ถึง cap 30 วินาที
```

**ครบทุกขั้นรวม cap** — ไม่ใช่แค่ผ่านเกณฑ์หลวมๆ

### สิ่งที่ปิดไปในรอบนี้

| # | |
|---|---|
| **W1** | `SocketRead` บล็อก — **ต้นเหตุที่แท้จริง** |
| **W3 (บางส่วน)** | `wait_for_no_terminal_running()` ปิดช่อง terminal ค้างข้ามเทสต์ |
| **F2/T2** | tolerance บวก granularity ของ `EventSetTimer(1)` |
| **`\r` ใน input** | `host_raw=10→9` · `token_raw=11→10` — **หนี้ที่จะระเบิดตอน SPEC-013** แก้ทันแล้ว |
| **diag file** | `FileFlush()` ทุกบรรทัด — เครื่องมือที่ทำให้ W1 จบ **ต้องเก็บถาวร** |

---

## 🟠 N1 · ข้อสังเกตที่ต้องแก้ — test ที่ assertion ไม่มีทางล้ม

`test_wire_resilience.py` `_wait_for_backoff_ladder_connects()` ค้นหา window ที่
**ผ่าน `_backoff_gaps_match()` อยู่แล้ว** แล้วคืนออกมา · จากนั้น test ก็ assert เงื่อนไขเดิมซ้ำ

```python
if self._backoff_gaps_match(candidate_gaps, expected_gaps):
    return candidate            # ← คืนเฉพาะ window ที่ผ่านแล้ว
...
for observed, nominal in zip(gaps, expected, strict=True):
    self.assertGreaterEqual(...)   # ← จึงผ่านเสมอ เป็น dead code
```

| ผลเสีย | |
|--------|---|
| **assertion เป็น dead code** | ถ้า backoff พัง test จะไม่ล้มที่ assert แต่จะ **timeout 100 วินาที** พร้อมข้อความที่อ่านแล้วเหมือนปัญหาสิ่งแวดล้อม ไม่ใช่ regression |
| ช้าลงตอนพัง | 100 วินาทีกว่าจะรู้ แทนที่จะล้มทันทีพร้อมตัวเลขที่ผิด |
| เสี่ยงเจอ window ที่บังเอิญตรง | สแกนทุกตำแหน่งเริ่มต้น |

**นี่คือรูปแบบที่ [CLAUDE.md](../../CLAUDE.md) ระบุว่าอันตรายกว่า test แดง** —
*"test ที่ผ่านแบบไม่ได้ทดสอบอะไร"* · แม้รอบนี้พฤติกรรมจะถูกจริง (ผมตรวจข้อมูลดิบเองแล้ว)
แต่โครงสร้างนี้จะกลบ regression ในอนาคต

**แก้เล็กมาก — แยก "หา" ออกจาก "ตรวจ":**

```python
# หา: ใช้เกณฑ์แคบอย่างเดียว ห้ามใช้ _backoff_gaps_match
if 0.7 <= gap <= 2.6 and len(connects) - start_idx >= count:
    return connects[start_idx : start_idx + count]
# ตรวจ: ให้ assertion เป็นคนตัดสิน -> ล้มพร้อมตัวเลขจริงเมื่อ ladder ผิด
```

**ไม่บล็อกการปิด ticket** — พฤติกรรมพิสูจน์แล้วด้วยข้อมูลดิบ · แต่ต้องแก้ก่อนพึ่ง test นี้จับ regression

---

## สถานะ SPEC-016 ชั้น A · SPEC-001

| test | |
|------|---|
| `test_ea_reconnects_after_server_kill` | ✅ |
| `test_backoff_schedule_matches_spec` | ✅ ถึง cap 30s |
| `test_bad_token_waits_60s` | ✅ |
| `test_ea_handles_duplicate_session_rejection` | ✅ |
| `test_heartbeat_gap_triggers_reconnect` | ✅ |
| `test_no_heartbeat_loss_over_1h` | ⏭ slow gate — **ยังไม่ได้รัน** |

### เหลือก่อนปิด SPEC-001

| # | งาน | สถานะ |
|---|-----|-------|
| 1.6 | `test_partial_send_resumes` ด้วย socket จริง | ✅ อยู่ใน `ran_names` ของ TestWire แล้ว |
| 1.7 | `Pump()` p99 < 20,000 µs | ✅ **16,576 µs** วัดจากของจริง |
| 1.7 | **soak 24 ชม. ผ่านสุดสัปดาห์** | 🔴 **ยังไม่ได้รัน** — บีบเวลาไม่ได้ |
| — | slow gate `test_no_heartbeat_loss_over_1h` | 🔴 ยังไม่ได้รัน |
| N1 | แก้ test ให้ assertion ทำงานจริง | 🟠 |
| W2 | `echo_server` นับเฉพาะ connection ที่พูดโปรโตคอล | 🟠 |

**ทางที่เหลือชัดแล้ว** — ไม่มีบั๊กที่ยังหาไม่เจอ เหลือแต่งานที่ต้องใช้เวลาปฏิทิน (soak)
