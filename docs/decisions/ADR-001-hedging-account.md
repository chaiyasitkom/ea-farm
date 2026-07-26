# ADR-001 — บัญชีเป็น Hedging Mode

**สถานะ:** ACCEPTED · **วันที่:** 2026-07-26 · **ตัดสินโดย:** เจ้าของโปรเจกต์
**ปิดหนี้เทคนิค:** D3 · **กระทบ:** SPEC-011 (OrderRouter), R3/R4, `02-contracts.md` §4.4/§4.5

---

## บริบท

`docs/02-contracts.md` กำหนดว่า brain ส่ง **target-state** (`target_volume` = net position ที่ต้องการ)
แล้ว EA คำนวณส่วนต่างเอง วิธี reconcile ต่างกันสิ้นเชิงระหว่าง netting กับ hedging:

| | Netting | Hedging |
|---|---------|---------|
| position ต่อ symbol | 1 เสมอ broker netting ให้ | ได้หลายไม้ แต่ละไม้มี ticket/SL/TP/ราคาเปิดของตัวเอง |
| เพิ่มขนาด | ส่ง order เพิ่ม broker รวมให้ | เกิด ticket ใหม่ |
| กลับทาง long→short | ส่ง 1 order ขนาด (N+|T|) จบ | ต้องปิดฝั่งเดิมก่อน แล้วเปิดใหม่ (2 จังหวะ) |
| ลดขนาด | ส่ง order สวนบางส่วน | partial close ticket ที่เลือก |

## การตัดสิน

**บัญชีเป็น hedging** (`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`)

EA ต้อง verify ตอน `OnInit`: อ่าน `AccountInfoInteger(ACCOUNT_MARGIN_MODE)`
ถ้าไม่ใช่ hedging → **`OnInit` fail** ไม่ใช่ปรับตัวเอง (โค้ดที่รองรับสองโหมดพร้อมกัน
คือโค้ดที่ทดสอบครบไม่ได้จริง — เอาให้ชัดดีกว่า)

## ผลที่ตามมา (consequences)

### 1. Ownership เป็นแบบ magic-scoped

EA จัดการเฉพาะ position ที่ `POSITION_MAGIC == InpMagic` **และ** `POSITION_SYMBOL == symbol` ของตัวเอง

```
owned_net = Σ (volume × (side == BUY ? +1 : −1))   เฉพาะไม้ที่เป็นเจ้าของ
```

| อย่าง | นับใน |
|-------|-------|
| Reconciliation, R3, R4 | **owned เท่านั้น** |
| Margin level (R8), equity, daily loss (R6), DD (R7) | **ทั้งบัญชี** รวมไม้ที่ไม่ใช่ของเรา |

เหตุผล: ไม้ที่คนอื่นเปิด (มือ หรือ EA อื่น) กินมาร์จิ้นและกระทบ equity จริง
จะมองข้ามไม่ได้ แต่เราก็ไม่มีสิทธิ์ไปปิดของเขา

→ **เพิ่ม field ใน `STATE`:** `foreign_positions` เพื่อให้เห็นบน dashboard ว่ามีของแปลกปลอมอยู่
บัญชีในฟาร์มควรมีแต่ไม้ของ EA — ถ้าเจอ foreign ต้อง alert (อาจเป็นการเทรดมือที่ลืม หรือ magic ชนกัน)

### 2. ★ No-Internal-Hedge Invariant (กฎเหล็กข้อใหม่)

> **ห้ามถือไม้ long และ short ของ symbol เดียวกันภายใต้ magic เดียวกันพร้อมกัน เด็ดขาด**

เพราะ net exposure = 0 แต่จ่าย spread 2 ขา + swap 2 ขา = เผาเงินโดยไม่ได้อะไร
และทำให้ P3/P4 ใน portfolio risk คำนวณ exposure เพี้ยน

- ตอน flip ทิศ: **ปิดฝั่งเดิมให้หมดและยืนยันสำเร็จก่อน** แล้วค่อยเปิดฝั่งใหม่
- ถ้า reconciler เจอว่ามีทั้งสองฝั่ง (เกิดจาก bug หรือ crash กลางทาง)
  → ถือเป็น **anomaly** ต้อง net ออกทันที + ส่ง `ERROR severity:ERROR` + alert
- ถ้าโบรกเกอร์รองรับ `SYMBOL_ORDER_CLOSEBY` → ใช้ปิดคู่กัน ประหยัด spread
  ไม่รองรับ → ปิดฝั่งที่เล็กกว่าด้วย market order

### 3. R3 เปลี่ยนความหมาย

ปัญหา: hedging + `max_positions_per_symbol = 1` ทำให้ **เพิ่มขนาดไม่ได้เลย**
ต้อง close+reopen ซึ่งจ่าย spread ซ้ำและรีเซ็ตราคาเปิด — แย่กว่าเปิดไม้ที่สอง

จึงแยกเป็น 2 กฎ:

| กฎใหม่ | default | บทบาท |
|--------|---------|-------|
| `max_net_volume_per_symbol` | 0.50 | **คุมความเสี่ยงจริง** — เพดาน \|owned_net\| |
| `max_tickets_per_symbol` | 4 | **anti-bug guard** — ถ้าเกินนี้แปลว่า logic พัง ไม่ใช่กลยุทธ์ |

`max_tickets_per_symbol` ไม่ใช่กฎ risk — เป็นเบรกฉุกเฉินกัน bug ที่เปิดไม้รัว
เกิน = block + `ERROR severity:ERROR` เพราะไม่ควรเกิดขึ้นเลย

R4 `max_total_positions` = 4 → เปลี่ยนเป็น 8 (นับ ticket ไม่ใช่ symbol) แต่คุม
ความเสี่ยงจริงด้วย P3 currency exposure ที่ระดับ portfolio

### 4. นโยบายเลือกไม้ปิด = FIFO

ตอนลดขนาด ต้องเลือกว่าปิดไม้ไหน ใช้ **FIFO (`time_open` เก่าสุดก่อน, tie-break ด้วย ticket น้อยสุด)**

เหตุผล:
- deterministic → reproduce และ audit ได้ ต่างจาก "ปิดไม้ที่ขาดทุนสุด" ที่เปลี่ยนตามราคาขณะนั้น
- โบรกเกอร์บางรายบังคับ FIFO อยู่แล้ว — ทำตามตั้งแต่ต้นไม่ต้องมาแก้ทีหลัง
- ไม่สร้างแรงจูงใจให้ระบบ "เก็บไม้ขาดทุนไว้ ปิดไม้กำไร" ซึ่งทำให้ P/L ดูดีกว่าจริง

### 5. SL/TP: ไม้ทุกใบของ symbol ใช้ค่าเดียวกัน

`INTENT` ให้ `sl_price`/`tp_price` มาชุดเดียว แต่ hedging มีหลาย ticket
→ **apply ค่าเดียวกันกับทุกไม้ที่เป็นเจ้าของใน symbol นั้น**

brain มีมุมมองเดียวว่า stop ควรอยู่ไหน ไม่ใช่มุมมองต่อไม้
ไม้ไหน SL/TP ไม่ตรง → `PositionModify` เฉพาะไม้นั้น (ไม่ต้องแตะไม้ที่ตรงแล้ว)

### 6. Flip เป็น 2 จังหวะ — แต่ล้มกลางทางแล้วปลอดภัย

```
N = +0.20, T = −0.10
  ขั้น 1: ปิด long 0.20 ทั้งหมด
  ขั้น 2: เปิด short 0.10
```

ถ้าขั้น 1 สำเร็จแต่ขั้น 2 ล้ม → เราอยู่ที่ flat (0) ไม่ใช่ −0.10
นี่คือ **ผลลัพธ์ที่ปลอดภัยกว่าเป้าหมาย** → ยอมรับได้
ตอบ `EXEC_REPORT result:PARTIAL` แล้วให้ brain ตัดสินใจส่ง intent ใหม่
**ห้าม EA retry ขั้น 2 เองหลัง `valid_until` หมดอายุ** — ราคาเปลี่ยนไปแล้ว
การตัดสินใจเดิมอาจไม่ valid อีก

ลำดับนี้ห้ามสลับ (เปิดใหม่ก่อนปิดเก่า) เพราะจะละเมิดข้อ 2 ชั่วขณะ
และถ้าปิดเก่าล้มจะเหลือ hedge ค้าง

### 7. Partial close ต้องกัน leftover ที่ต่ำกว่า `volume_min`

```
ต้องการลด 0.15 จากไม้ 0.20 · volume_min = 0.10
→ leftover = 0.05 < volume_min = ส่งไม่ได้ / โบรกเกอร์ reject
```

กฎ: ถ้า `ticket_volume − close_volume` อยู่ระหว่าง 0 กับ `volume_min`
→ **ปิดไม้นั้นทั้งใบ** แล้วรายงานว่า overshoot ไปเท่าไร ใน `INTENT_ACK`
(overshoot = ลดเยอะกว่าที่สั่ง = ปลอดภัยกว่า ยอมรับได้ ตรงข้ามกับ undershoot ที่ไม่ยอมรับ)

---

## ทางเลือกที่พิจารณาแล้วไม่เอา

| ทางเลือก | ทำไมไม่เอา |
|----------|-----------|
| รองรับทั้ง netting และ hedging ในโค้ดชุดเดียว | branch เยอะ ทดสอบไม่ครบจริง และ path ที่ไม่ได้ใช้จะเน่าเงียบๆ |
| บังคับ 1 ticket ต่อ symbol เสมอ (`max_tickets = 1`) | เพิ่มขนาดต้อง close+reopen จ่าย spread ซ้ำ รีเซ็ตราคาเปิด |
| ปิดไม้ที่ขาดทุนมากสุดก่อน (LIFO/worst-first) | ไม่ deterministic · สร้างแรงจูงใจให้ P/L ดูดีกว่าจริง |
| ปล่อยให้มี hedge ภายในถ้ากลยุทธ์ต่างกันสั่งสวนกัน | เผา spread+swap 2 ขาเพื่อ net exposure = 0 · ทำให้ P3/P4 คำนวณเพี้ยน — ถ้าอยากให้กลยุทธ์สวนกันได้ ให้ **แยกบัญชี** ไม่ใช่แยก magic |
| SL/TP ต่อไม้แยกกันตาม intent ที่เปิดไม้นั้น | brain ไม่ได้คิดเป็นต่อไม้ · จัดการยาก · ตอน flip งงว่าใช้ค่าไหน |

## สิ่งที่ต้องแก้ตามมา

- [x] `02-contracts.md` §4.4 เพิ่ม `foreign_positions` · §4.5 เพิ่ม §4.5.1 hedging semantics
- [x] `03-risk-spec.md` R3 แยกเป็น 2 กฎ · R4 นับ ticket
- [x] `docs/specs/SPEC-011-order-router.md` เขียนใหม่ทั้งฉบับตาม ADR นี้
- [x] `backlog.md` ปิด D3
- [x] `SPEC-001` §9 Q1 ตอบแล้ว
