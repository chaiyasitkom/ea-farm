---
id: 083
from: codex
ticket: SPEC-010
type: handoff
blocking: false
replies_to: "082"
---

## SPEC-010 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none

### What changed
- `tools/python-gate-env.ps1`: added shared PowerShell gate helper.
  - `Get-GatePython` selects `<repo>/.venv/Scripts/python.exe` when present, else `python`.
  - `Assert-GatePythonImports` exits 3 with `FAILED (ENV)` and prints the interpreter plus the missing import/attribute.
  - Import spec supports `module:attribute`; chaos/soak verify `farm_contracts.models:PAYLOAD_MODELS`.
- `tools/run-chaos.ps1`: dot-sources the shared helper, preflights `farm_contracts` and `PAYLOAD_MODELS`, prints `python=...`, and runs unittest through the selected interpreter instead of system `python`.
- `tools/run-soak.ps1`: dot-sources the same helper, preflights `psutil`, `farm_contracts`, and `PAYLOAD_MODELS`, and runs unittest through the selected interpreter.
- `tests/mql5/TestWire.mq5`: `test_json_unknown_field_ignored` now parses `HELLO_ACK` payload and asserts `ack.accepted`.

### Gate changes
- Changed chaos and soak gate interpreter selection.
- Added import preflight before launching the live harness, so missing `farm_contracts` fails in preflight with exit 3 instead of surfacing as `echo server did not start`.
- Shared the selection/import implementation in one PowerShell helper to avoid duplicated `.venv` rules.

### Spec deviations
ไม่มี

### Tests / checks
- Not run: fast chaos gate, MQL5 gate, and `check` per instruction.
- Ran PowerShell parser only:
  - `tools/python-gate-env.ps1 syntax OK`
  - `tools/run-chaos.ps1 syntax OK`
  - `tools/run-soak.ps1 syntax OK`
- Ran direct helper import preflight only:
  - selected `D:\ea-farm\.venv\Scripts\python.exe`
  - `farm_contracts` and `farm_contracts.models:PAYLOAD_MODELS` import OK

### Not done / technical debt
- No commit made per instruction.
- `git pull` at session start failed with `.git/FETCH_HEAD: Permission denied`; work continued against the existing working tree.

### Please review especially
- `tools/python-gate-env.ps1` quoting/argument handling for `python -c` under Windows PowerShell.
- Whether soak should also preflight any future soak-only harness imports beyond `psutil` and echo-server contract imports.
