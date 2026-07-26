# EA Farm — AI-Assisted Multi-Account Forex Trading System

ระบบฟาร์ม EA สำหรับพอร์ตส่วนตัว หลายบัญชี หลายกลยุทธ์ บน MT5 + Python brain

**สถานะ:** Phase 0 — Planning (ยังไม่มีโค้ด)
**เจ้าของ:** chaiyasitkom@gmail.com
**เริ่มวางแผน:** 2026-07-26

---

## หลักการออกแบบ 5 ข้อ (อ่านก่อนเขียนโค้ดบรรทัดแรก)

1. **EA เป็นเจ้าของความปลอดภัย — Python เป็นเจ้าของความคิดเห็น**
   ถ้า Python brain ตาย EA ต้องยังปกป้องพอร์ตได้เอง 100% ห้ามมีทางกลับกันเด็ดขาด

2. **สื่อสารด้วย "สถานะเป้าหมาย" ไม่ใช่ "คำสั่ง"**
   Brain ส่ง *"ฉันต้องการถือ EURUSD +0.20 lot"* ไม่ใช่ *"เปิด buy 0.20"*
   ทำให้ idempotent โดยธรรมชาติ — เน็ตหลุด/ส่งซ้ำ/รีสตาร์ท ไม่เกิด double order

3. **Risk มาก่อน Alpha**
   Phase 1–2 คือ execution + risk ต้องนิ่งสนิทบน demo ก่อน แล้วค่อยแตะ ML
   ห้ามข้ามไปทำ ML signal เพราะ "น่าสนุกกว่า"

4. **ทุกอย่างที่ตัดสินใจ ต้อง reproduce ได้**
   ทุก order ต้องย้อนได้ว่ามาจาก model version ไหน feature ชุดไหน regime อะไร

5. **Contract คือกฎหมาย**
   `contracts/` เป็นแหล่งความจริงเดียวระหว่าง MQL5 กับ Python
   แก้ contract = ต้องอัปเดต spec ก่อน ห้ามแก้โค้ดฝ่ายเดียว

---

## สารบัญเอกสาร

| ไฟล์ | เนื้อหา | ใครอ่าน |
|------|---------|---------|
| [docs/01-architecture.md](docs/01-architecture.md) | สถาปัตยกรรม 3 plane, component breakdown, tech stack | ทั้งคู่ |
| [docs/02-contracts.md](docs/02-contracts.md) | Wire protocol, message schema, data model | **Codex (สำคัญสุด)** |
| [docs/03-risk-spec.md](docs/03-risk-spec.md) | กฎ risk 4 ชั้น พร้อมตัวเลข default | ทั้งคู่ |
| [docs/04-roadmap.md](docs/04-roadmap.md) | 8 phase + milestone + exit criteria | ทั้งคู่ |
| [docs/05-collab-protocol.md](docs/05-collab-protocol.md) | Claude ↔ Codex แบ่งงานกันอย่างไร | ทั้งคู่ |
| [docs/backlog.md](docs/backlog.md) | รายการ ticket ทั้งหมด เรียงลำดับ | ทั้งคู่ |
| [docs/specs/](docs/specs/) | Spec รายตัวที่ Codex ลงมือได้เลย | **Codex** |
| [AGENTS.md](AGENTS.md) | กฎสำหรับ Codex | Codex |
| [CLAUDE.md](CLAUDE.md) | กฎสำหรับ Claude | Claude |

---

## เริ่มต้นอย่างไร

1. อ่าน `docs/05-collab-protocol.md` ให้จบ — เข้าใจว่าใครทำอะไร
2. ทำ Phase 0 ใน `docs/04-roadmap.md` (setup + contracts)
3. Codex เริ่มที่ `docs/specs/SPEC-001-mt5-executor.md`

## Layout ที่จะเกิดขึ้น

```
ea-farm/
├── contracts/              # JSON Schema + generated code (source of truth)
│   ├── schema/*.json
│   ├── gen/mql5/           # generated MQL5 structs
│   └── gen/python/         # generated pydantic models
├── mt5-ea/                 # MQL5
│   ├── Experts/FarmExecutor.mq5
│   ├── Include/Farm/       # RiskGuard, OrderRouter, Wire, Logger
│   └── Scripts/            # utilities
├── brain/                  # Python control plane
│   ├── gateway/            # TCP server, session registry
│   ├── signal/             # ML inference
│   ├── regime/             # regime classifier
│   ├── news/               # calendar + LLM sentiment
│   ├── risk/               # portfolio risk manager
│   └── store/              # DB access, repositories
├── research/               # offline
│   ├── ingest/             # data collection
│   ├── features/           # feature engineering
│   ├── backtest/           # engine + walk-forward
│   └── registry/           # model artifacts + metadata
├── ops/                    # dashboard, alerting, deploy scripts
├── tests/
└── docs/
```
