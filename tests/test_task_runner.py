from __future__ import annotations

import platform
import re
import shutil
import venv
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


def test_check_fails_when_environment_is_incomplete(capsys: pytest.CaptureFixture[str]) -> None:
    code = task.summarize("check", [_result("lint", "SKIP", "ruff missing", 3)])

    output = capsys.readouterr().out
    assert code == 3
    assert "[SKIP] lint -- ruff missing" in output
    assert "check: ENVIRONMENT INCOMPLETE" in output


def test_finds_repo_root_from_any_cwd() -> None:
    assert task.ROOT == Path(__file__).resolve().parents[1]


def test_mql5_gate_propagates_exit_code(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(platform, "system", lambda: "Windows")
    monkeypatch.setattr(shutil, "which", lambda _name: "powershell")
    monkeypatch.setattr(
        task,
        "_run",
        lambda _command, name, _timeout_sec=900.0: _result(name, "FAIL", "exit=7", 7),
    )

    result = task.target_mql5_gate()

    assert result.status == "FAIL"
    assert result.code == 7


def test_missing_tool_reports_skip_not_traceback(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(task, "_task_python_or_skip", lambda _name: Path("python"))
    monkeypatch.setattr(task, "_module_exists", lambda _name, _python: False)

    result = task.target_lint()

    assert result.status == "SKIP"
    assert result.code == 3
    assert "ruff is not installed" in result.detail


def test_tool_lookup_uses_selected_python(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    selected_python = tmp_path / "python.exe"
    selected_python.write_text("", encoding="utf-8")
    seen: list[Path] = []

    def module_exists(_name: str, python: Path) -> bool:
        seen.append(python)
        return True

    monkeypatch.setattr(task, "_selected_python", lambda: selected_python)
    monkeypatch.setattr(task, "_python_version", lambda _python: (3, 11))
    monkeypatch.setattr(task, "_module_exists", module_exists)
    monkeypatch.setattr(
        task,
        "_run",
        lambda _command, name, _timeout_sec=900.0: _result(name, "OK"),
    )

    result = task.target_lint()

    assert result.status == "OK"
    assert seen == [selected_python]


def test_existing_venv_with_wrong_python_version_warns_without_recreating(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    created: list[Path] = []
    root = tmp_path / "repo"
    (root / ".venv").mkdir(parents=True)

    monkeypatch.setattr(task, "ROOT", root)
    monkeypatch.setattr(task, "_venv_python", lambda: Path(__file__))
    monkeypatch.setattr(task, "_python_version", lambda _python: (3, 10))
    monkeypatch.setattr(venv, "create", lambda path, with_pip: created.append(path))

    result = task.target_install()

    assert result.status == "FAIL"
    assert ".venv uses Python 3.10" in result.detail
    assert created == []


def test_env_example_has_no_real_values() -> None:
    env = (task.ROOT / ".env.example").read_text(encoding="utf-8")

    assert "changeme" in env
    assert "FARM_TELEGRAM_BOT_TOKEN=\n" in env
    assert "FARM_TELEGRAM_CHAT_ID=\n" in env
    assert "test-token" not in env
    assert not re.search(r"\b[A-Za-z]:\\", env)
    assert "/Users/" not in env
    assert "/home/" not in env


def test_pytest_markers_declared() -> None:
    pyproject = (task.ROOT / "pyproject.toml").read_text(encoding="utf-8")

    assert "slow:" in pyproject
    assert "live_terminal:" in pyproject
    assert "mql5:" in pyproject
