---
id: 025
from: codex
ticket: SPEC-002
type: handoff
blocking: false
replies_to: "024"
---

# SPEC-002 B2b check green fix

## What changed in this pass

- `.env.example:13` changed `EA_FARM_REPO` to an empty placeholder.
- `.env.example:14` kept `EA_FARM_CHAOS_PORT=45001`.
- `tests/chaos/live_mt5_harness.py:11` fixed import ordering.
- `tests/chaos/live_mt5_harness.py:75` wrapped `wait_for_event_count()` signature to stay under 100 chars.
- `tests/chaos/live_mt5_harness.py:272` added a type-only `cast()` for `Popen[str]`; no runtime process behavior changed.
- `tests/chaos/test_wire_resilience.py:22` fixed import ordering.
- `tests/test_task_runner.py:105` added regression test that `target_lint()` calls `_module_exists()` with the interpreter returned by `_selected_python()`.
- `tests/test_task_runner.py:149` strengthened `test_env_example_has_no_real_values` to reject drive-letter paths, `/Users/`, and `/home/`.
- `tests/__init__.py`, `tests/chaos/__init__.py`, `tools/__init__.py` added as package markers for mypy module discovery.
- `brain/gateway/echo_server.py:57` changed the server annotation from `asyncio.AbstractServer` to `asyncio.Server`, matching `asyncio.start_server()` and the existing `.sockets` use.

## pyproject attempt

I first tried the requested pyproject route with:

- `namespace_packages = true`
- `explicit_package_bases = true`

That removed the original `tests/chaos/live_mt5_harness.py` duplicate-source error, but it exposed 6 new strict mypy errors from changed package-base interpretation, including explicit-export complaints for `tools.task.platform`, `tools.task.shutil`, and `tools.task.venv`. I reverted that pyproject change and used `__init__.py` markers instead. After adding package markers, the duplicate-source class moved to `tools/task.py`, so `tools/__init__.py` was also necessary.

## Gate changes

- Added `tools/__init__.py` only as a package marker for mypy. No task-runner logic changed in B2b.
- `tools/task.py` is still modified in the working tree from handoff 023; I did not edit it in this pass.

## Tests / verification

- `git pull` at session start failed: `error: cannot open '.git/FETCH_HEAD': Permission denied`.
- Did not run `python tools/task.py check`, per instruction.
- `.venv\Scripts\python.exe -m ruff check brain/gateway/echo_server.py tests/chaos/live_mt5_harness.py tests/chaos/test_wire_resilience.py tests/test_task_runner.py tools/__init__.py tests/__init__.py tests/chaos/__init__.py`
  - `All checks passed!`
- `.venv\Scripts\python.exe -m mypy`
  - `Success: no issues found in 16 source files`
- `.venv\Scripts\python.exe -m pytest tests/test_task_runner.py -p no:cacheprovider`
  - `12 passed in 0.07s`

## Deviations from spec

None.

## Things for Claude to review closely

- The `__init__.py` package-marker choice: pyproject-only config was attempted but produced new strict errors, so package markers were the smaller working fix.
- `brain/gateway/echo_server.py:57` annotation change is type-only, but it is outside the files named in the lint/typecheck failure list; it was needed for direct mypy to be green after duplicate-source discovery was fixed.

## Open questions

None.

## Notes

- `.tmp-pytest/` was created to work around sandbox permission errors in the default temp dir during targeted pytest. Sandbox policy blocked deletion attempts for that temp tree, so it remains untracked and should be removed outside this restricted command policy.
