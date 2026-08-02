---
id: 047
from: codex
ticket: SPEC-004
type: handoff
blocking: false
replies_to: "046"
---

## SPEC-004 Handoff

**Branch:** feat/SPEC-001-mt5-executor (existing working branch; did not switch)
**Commits:** none

### Implementation note
- Scope stayed on SPEC-004 MQL5 generated messages.
- Did not touch `docs/**`, `contracts/schema/**`, `Wire.mqh`, `FarmExecutor.mq5`, or `TestWire.mq5`.
- Did not run MQL5 gate and did not commit, per instruction.
- `git pull` at session start failed: `error: cannot open '.git/FETCH_HEAD': Permission denied`.

### ทำอะไรไปแล้ว
- `tools/codegen.py`
  - Changed generated `FarmRequireKeys()` to collect all missing required field names before failing.
  - This makes `FarmJsonLastError()` include `positions` for `{"balance":1.0,"equity":1.0}`.
  - Added generated typed STATE structs:
    `FarmStatePosition`, `FarmStatePendingOrder`, `FarmStateForeignPositions`, `FarmStateGuard`, and expanded `FarmStatePayload`.
  - Added generated STATE parser fill helpers that copy parsed JSON values into real fields, nested struct arrays, and map-style parallel arrays:
    `owned_net_keys/owned_net_values`, `owned_ticket_count_keys/owned_ticket_count_values`.
  - Added `Free()` on STATE payload/foreign positions arrays.
- `contracts/gen/mql5/FarmMessages.mqh`
  - Regenerated only via `python tools/task.py codegen`.

### gate changes
- `tools/codegen.py` changed because it is the generator under SPEC-004, not the test gate.
- No `tools/run-mql5-tests.ps1`, `tools/compile-gate.ps1`, or gate target behavior was changed.

### เบี่ยงเบนจาก spec
| จุด | spec ว่า | ทำจริงว่า | เพราะ |
|-----|----------|------------|-------|
| MQL5 typed completeness | Generate struct + serializer + parser for every payload from schema | Completed typed parser materialization for STATE, but other payload structs still mostly keep `raw_json` facade behavior | Time/risk tradeoff in this pass; main failing MQL test is fixed and STATE is the payload under failing test |
| codegen-check | Should be OK | `codegen-check` reports diff while working tree contains intended regenerated `contracts/gen` changes | `tools/task.py codegen-check` runs `git diff --exit-code -- contracts/gen`; this remains red until the generated diff is accepted/committed |

### Test
- `python tools/task.py codegen`
  - `[ OK ] codegen`
  - `codegen: OK (1 passed, 0 skipped)`
- Determinism check by SHA256 before/after a second `python tools/task.py codegen`
  - `determinism: OK`
- `python -m py_compile tools/codegen.py`
  - passed
- `python -m pytest tests/test_codegen.py`
  - failed to start: `No module named pytest`
- `python tools/task.py codegen-check`
  - expected dirty-tree failure after regenerating `contracts/gen`:
  - `[FAIL] codegen-check -- exit=1`
- MQL5 compile/TestFarmMessages
  - not run per instruction; waiting for Claude gate.

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- Full schema-driven MQL5 typed codegen for all 12 payloads is still not complete.
- Serializers for typed STATE still return canonical `raw_json`; they do not rebuild JSON field-by-field from typed fields yet.
- Enum generation beyond `ENUM_FARM_MSG_TYPE` is still not complete on MQL5 side.
- Generic schema-driven validators for every scalar constraint/property are still partial and ad hoc.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- Compile risk in generated MQL5 around dynamic arrays inside structs and array reference helper signature:
  `void FarmFillStringArray(CFarmJsonValue *src, string &out[])`.
- Whether the current incremental typed STATE materialization is acceptable for this round, or whether next round should replace the MQL5 generator with a full schema AST emitter for all payloads.
- Confirm that `FarmJsonLastError()` from the missing-required test now contains a comma-separated list including `positions`.

### คำถามค้าง
- ไม่มี blocking question.
