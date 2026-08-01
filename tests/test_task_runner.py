from __future__ import annotations

from pathlib import Path

import pytest

from tools import task


def _result(name: str, status: str, detail: str = "", code: int = 0) -> task.TaskResult:
    return task.TaskResult(name=name, status=status, detail=detail, code=code)


def test_check_runs_all_targets_even_when_one_fails() -> None:
    calls: list[str] = []

    def make(name: str, status: str) -> task.TaskFunc:
        def inner() -> task.TaskResult:
            calls.append(name)
            return _result(name, status)

        return inner

    targets = {
        "lint": make("lint", "FAIL"),
        "typecheck": make("typecheck", "OK"),
        "test": make("test", "OK"),
        "codegen-check": make("codegen-check", "SKIP"),
    }

    results = task.run_sequence(task.CHECK_TARGETS, targets)

    assert calls == ["lint", "typecheck", "test", "codegen-check"]
    assert [item.status for item in results] == ["FAIL", "OK", "OK", "SKIP"]


def test_skip_is_reported_and_not_counted_as_pass(capsys: pytest.CaptureFixture[str]) -> None:
    code = task.summarize("check", [_result("codegen-check", "SKIP", "missing")])

    output = capsys.readouterr().out
    assert code == 0
    assert "[SKIP] codegen-check -- missing" in output
    assert "0 passed, 1 skipped" in output


def test_exit_code_1_when_any_target_fails(capsys: pytest.CaptureFixture[str]) -> None:
    code = task.summarize("check", [_result("lint", "FAIL", "exit=1", 1)])

    output = capsys.readouterr().out
    assert code == 1
    assert "check: FAILED" in output


def test_exit_code_0_when_only_skips(capsys: pytest.CaptureFixture[str]) -> None:
    code = task.summarize("check", [_result("codegen-check", "SKIP", "missing")])

    output = capsys.readouterr().out
    assert code == 0
    assert "FAILED" not in output


def test_finds_repo_root_from_any_cwd() -> None:
    assert task.ROOT == Path(__file__).resolve().parents[1]


def test_mql5_gate_propagates_exit_code(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(task.platform, "system", lambda: "Windows")
    monkeypatch.setattr(task.shutil, "which", lambda _name: "powershell")
    monkeypatch.setattr(task, "_run", lambda _command, name: _result(name, "FAIL", "exit=7", 7))

    result = task.target_mql5_gate()

    assert result.status == "FAIL"
    assert result.code == 7


def test_missing_tool_reports_skip_not_traceback(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(task, "_module_exists", lambda _name: False)

    result = task.target_lint()

    assert result.status == "SKIP"
    assert "ruff is not installed" in result.detail


def test_env_example_has_no_real_values() -> None:
    env = (task.ROOT / ".env.example").read_text(encoding="utf-8")

    assert "changeme" in env
    assert "FARM_TELEGRAM_BOT_TOKEN=\n" in env
    assert "FARM_TELEGRAM_CHAT_ID=\n" in env
    assert "test-token" not in env


def test_pytest_markers_declared() -> None:
    pyproject = (task.ROOT / "pyproject.toml").read_text(encoding="utf-8")

    assert "slow:" in pyproject
    assert "live_terminal:" in pyproject
    assert "mql5:" in pyproject
