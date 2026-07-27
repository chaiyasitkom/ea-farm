# contracts/schema — normative wire contract

**Owner:** Claude · **ห้าม Codex แก้ไฟล์ในโฟลเดอร์นี้** ([CLAUDE.md](../../CLAUDE.md))
ถ้าต้องเปลี่ยน → เขียน implementation note ให้ Claude แก้

> **ไฟล์เหล่านี้เป็น source of truth ที่ผูกพัน** — [`docs/02-contracts.md`](../../docs/02-contracts.md)
> เป็นคำอธิบายและตัวอย่าง ถ้าสองที่ไม่ตรงกัน **schema ชนะ**

---

## ไฟล์

| ไฟล์ | เนื้อหา |
|------|---------|
| `common.json` | `$defs` ที่ใช้ร่วม — enum, id, timestamp, symbol_spec, account_info, local_limits |
| `envelope.json` | ห่อหุ้มทุก message + `type` enum ครบ 12 |
| `hello.json` · `hello_ack.json` | handshake |
| `heartbeat.json` · `heartbeat_ack.json` | keep-alive + wire metric |
| `bar.json` · `state.json` | EA → Brain telemetry |
| `intent.json` · `intent_ack.json` | ★ target-state + ผลการ reconcile |
| `exec_report.json` | ผลการส่ง order (append-only audit) |
| `risk_directive.json` | Brain → EA คุม mode/scale |
| `error.json` | ทั้งสองทาง |
| `config_update.json` | 🚫 RESERVED — ห้าม implement ก่อน Phase 5 |

`payload` ของ type `X` อยู่ในไฟล์ `x.json` (ตัวเล็ก) — กฎนี้ตรงตัวเสมอ codegen พึ่งได้

---

## กฎที่ต้องรู้ก่อนเขียน codegen (SPEC-004)

### 1. draft 2020-12 · `$defs` · `$ref` แบบข้ามไฟล์ในโฟลเดอร์เดียวกัน

`{ "$ref": "common.json#/$defs/symbol" }` — relative filename ไม่ใช่ URL เต็ม
`$id` ที่ใส่ไว้เป็นแค่ identity ไม่ต้อง resolve ผ่านเน็ต

### 2. ★ `additionalProperties: true` ทุกที่ — โดยเจตนา

[§7](../../docs/02-contracts.md) บังคับว่าทั้งสองฝั่งต้อง**ข้าม unknown field ได้**
ถ้า generator สร้าง model ที่ reject unknown field → **การเพิ่ม optional field จะกลายเป็น breaking change**
ซึ่งขัดกับ versioning policy ทั้งหมด

- pydantic: ต้องเป็น `model_config = ConfigDict(extra="ignore")` **ไม่ใช่ `extra="forbid"`**
- MQL5 parser: เจอ key ที่ไม่รู้จัก → ข้าม ห้าม error

**ยกเว้นที่เดียว:** `config_update.json` → `settings` ตั้ง `additionalProperties: false`
เพราะที่นั่น unknown field = ความพยายามเปลี่ยนค่าที่ไม่อนุญาต ต้อง reject

### 3. `null` ≠ `0` ≠ ไม่มี field

| แบบ | ความหมาย |
|-----|----------|
| `"sl": null` | ไม่ได้ตั้ง SL |
| `"sl": 0` | **ผิด** — ราคา 0 เป็นไปไม่ได้ schema จะ reject (`exclusiveMinimum: 0`) |
| ไม่มี key `sl` เลย | ผิด ถ้าอยู่ใน `required` |

MQL5 คืน `0.0` เมื่อไม่มี SL → **generator/EA ต้องแปลง `0.0` เป็น `null` ตอน serialize**
ไม่ใช่ส่ง `0` ขึ้นไป จุดนี้พลาดง่ายที่สุดในทั้ง contract

### 4. float ห้ามเทียบด้วย `==`

`volume` เทียบด้วย tolerance `volume_step / 2` เสมอ (ระบุใน `common.json#/$defs/volume`)

### 5. `ts_utc` ต้องเป็น UTC จริง ลงท้าย `Z`

pattern บังคับ `Z` — offset แบบ `+07:00` จะ **fail validation**
⚠️ `TimeCurrent()` คืนเวลา **broker-local** ไม่ใช่ UTC → ต้องหัก offset ก่อน (SPEC-063 BrokerTime)

### 6. `timeframe` ต้องตัด prefix `PERIOD_`

`EnumToString(PERIOD_H1)` คืน `"PERIOD_H1"` แต่ schema รับแค่ `"H1"`

### 7. `symbol` เก็บชื่อจริงรวม suffix — ไม่ทำเป็น enum

`EURUSD.iux` ไม่ใช่ `EURUSD` · ห้าม normalize ที่ชั้น wire
รายชื่อที่**อนุญาต**ให้เทรดเป็น config ไม่ใช่ protocol → อยู่ใน SymbolRegistry (SPEC-064)
เหตุผล: เปลี่ยนชุด symbol ไม่ควรต้องแก้ schema และ bump `v`

### 8. invariant ที่ JSON Schema บังคับไม่ได้ → อยู่ใน `$comment`

ทุกไฟล์ที่มี invariant ข้ามฟิลด์ (เช่น `low <= open <= high`) เขียนไว้ใน `$comment` ท้ายไฟล์
**ต้อง implement เป็น validator ในโค้ดด้วย** schema จับให้ไม่ได้ — และต้องมี test

---

## ตรวจ schema เอง

```bash
node tools/validate-schema.js       # (SPEC-004 ต้องสร้าง) — parse + resolve $ref + เช็ค type ครบ
```
ขั้นต่ำที่ต้องตรวจ: ทุกไฟล์ parse ได้ · ทุก `$ref` resolve ได้ · ทุกค่าใน
`envelope.type` enum มีไฟล์ `<type>.json` · ไม่มี payload ไหนตั้ง top-level
`additionalProperties: false`

---

## Versioning

- เพิ่ม optional field · เพิ่มค่าใน enum → **ไม่ breaking** ไม่ต้อง bump `v`
- ลบ field · เปลี่ยนความหมาย · เปลี่ยน required · แคบ type ลง → **breaking** ต้อง bump `v`
  และอัปเดตทั้งสองฝั่งพร้อมกัน
