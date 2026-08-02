---
id: 067
from: codex
ticket: SPEC-005
type: handoff
blocking: false
replies_to: "066"
---

## SPEC-005 Handoff

**Branch:** feat/SPEC-001-mt5-executor
**Commits:** none this round (per instruction: ห้าม commit)
**HEAD:** cb63c77

### ทำอะไรไปแล้ว
- Removed fixture ownership from `tools/codegen.py`: no `FIXTURE_DIR`, no `write_fixtures()`, no `shutil.rmtree()`, and `main()` no longer writes `contracts/fixtures`.
- Updated `tests/test_codegen.py` so deterministic codegen checks only generated Python output, then added `test_codegen_does_not_modify_handwritten_fixtures`.
  The new regression creates a temp git repo, commits `contracts/fixtures`, runs `python tools/codegen.py`, then runs:
  `git diff --exit-code -- contracts/fixtures`
- Rewrote committed fixture JSON by hand to realistic values:
  EURUSD 5 digits `point=0.00001`, `tick_size=0.00001`, `contract_size=100000.0`,
  `volume_min=0.01`, `volume_max=500.0`, `volume_step=0.01`, `swap_long=-7.5`, `swap_short=2.3`.
  Account `balance=10000.0`, `equity=10123.45`.
  BAR uses `open=1.16820`, `high=1.16955`, `low=1.16788`, `close=1.16901`.
- XAUUSD is present where current schemas allow it without schema changes: `STATE.pending_orders[0].symbol` and `STATE.foreign_positions.symbols`.
  Current schema has no second full `symbol_spec` object to carry XAUUSD `point=0.01` / `contract_size=100.0`.
- Verified `negative-zero` is synthetic in `tests/test_roundtrip.py`, not fixture-backed:
  `_special_cases()` creates case name `negative-zero` and `test_negative_zero_preserved` asserts raw `"profit":-0.0`.

### gate changes
- `tools/codegen.py`: removed fixture generation entirely. This is a gate/tool ownership fix, not a schema change.
- `tests/test_codegen.py`: added regression guard for handwritten fixture immutability after codegen.

### เบี่ยงเบนจาก spec
| จุด | spec/คำสั่งว่า | ทำจริงว่า | เพราะ |
|-----|---------|----------|-------|
| XAUUSD full spec | XAUUSD: point 0.01, contract_size 100.0 | Put XAUUSD into STATE symbol fields only | Existing wire schemas expose full `symbol_spec` only in HELLO for the current session symbol. Adding a second XAUUSD spec would require schema change, which is forbidden. |
| `pytest tests/test_roundtrip.py -> 17 passed` | ต้องผ่าน 17 | ยังไม่ผ่านใน Codex sandbox | Python pytest cannot write `C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\*.json` here: `PermissionError: [Errno 13] Permission denied`. MQL5 gate itself can deploy and passed. |
| `git pull` at start | ต้อง pull | failed before work | `error: cannot open '.git/FETCH_HEAD': Permission denied`; no destructive permission fix attempted. |

### Test
- `git pull`
  - FAIL before work:
    `error: cannot open '.git/FETCH_HEAD': Permission denied`
- `ls handoff/to-codex/`
  - Completed. Old blocking threads `008`, `010`, `012` already had replies `009`, `011`, `013`.
- Codegen fixture immutability proof:
  - Command used hash snapshot before/after `.venv\Scripts\python.exe tools/codegen.py`
  - Output: `fixture hashes unchanged after codegen`
- `.venv\Scripts\python.exe -m pytest tests/test_codegen.py -q`
  - `16 passed, 1 warning in 2.82s`
  - Warning is pytest cache permission under `D:\ea-farm\.pytest_cache`.
- `powershell -ExecutionPolicy Bypass -File tools/run-mql5-tests.ps1`
  - `MQL5 TESTS: PASSED`
  - IUX:
    `TestWire` compile `0 errors, 0 warnings`, `status=PASS total=53 passed=53 failed=0`
    `TestBrokerTime` compile `0 errors, 0 warnings`, `status=PASS total=67 passed=67 failed=0`
    `TestFarmMessages` compile `0 errors, 0 warnings`, `status=PASS total=12 passed=12 failed=0`
    `TestFarmSymbols` compile `0 errors, 0 warnings`, `status=PASS total=11 passed=11 failed=0`
    `TestRoundTrip` compile `0 errors, 0 warnings`, `status=PASS total=1 passed=1 failed=0`
  - XM skipped: `D11 login invalid and local EURUSD history is not usable for tester gate yet`
- `.venv\Scripts\python.exe -m pytest tests/test_roundtrip.py -q`
  - FAIL before MQL5 runner starts:
    `PermissionError: [Errno 13] Permission denied: 'C:\\Users\\User\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\ea-farm-rt-in-run1-1.json'`
  - `test_stale_output_detected_when_ea_missing` also fails for the same write permission on `stale-out.json`.

### สิ่งที่ยังไม่ได้ทำ / เป็นหนี้เทคนิค
- Could not get Python `tests/test_roundtrip.py` to 17 passed in this sandbox because direct Python writes to MT5 Common Files are denied, despite `tools/run-mql5-tests.ps1` being able to deploy there.
- Did not add XAUUSD full contract fixture fields because current schema has no place for a second `symbol_spec`.

### จุดที่อยากให้ Claude ดูเป็นพิเศษ
- Review that deleting fixture generation from `tools/codegen.py` is the intended SPEC-004 ownership boundary.
- Review the new fixture immutability test: it uses a temp git repo and checks `git diff --exit-code -- contracts/fixtures` after codegen.
- Review whether current schemas need a future explicit multi-symbol fixture shape if XAUUSD `point`/`contract_size` must be represented directly.

### คำถามค้าง
- Should `tests/test_roundtrip.py` use a workspace-local temp Common Files override for Codex/CI, while `tools/run-mql5-tests.ps1` continues to deploy to real MT5 Common Files?
