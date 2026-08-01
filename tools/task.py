from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import venv
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class TaskResult:
    name: str
    status: str
    detail: str = ""
    code: int = 0


TaskFunc = Callable[[], TaskResult]


def _module_exists(name: str, python: Path) -> bool:
    command = [
        str(python),
        "-c",
        (
            "import importlib.util, sys; "
            "raise SystemExit(importlib.util.find_spec(sys.argv[1]) is None)"
        ),
        name,
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30.0,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return completed.returncode == 0


def _run(command: Sequence[str], name: str, timeout_sec: float = 900.0) -> TaskResult:
    try:
        completed = subprocess.run(command, cwd=ROOT, check=False, timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        return TaskResult(name, "FAIL", f"timeout after {timeout_sec:.0f}s", 1)
    if completed.returncode == 0:
        return TaskResult(name, "OK")
    return TaskResult(name, "FAIL", f"exit={completed.returncode}", completed.returncode)


def _skip(name: str, detail: str) -> TaskResult:
    return TaskResult(name, "SKIP", detail)


def _env_skip(name: str, detail: str) -> TaskResult:
    return TaskResult(name, "SKIP", detail, 3)


def _venv_python() -> Path:
    if platform.system() == "Windows":
        return ROOT / ".venv" / "Scripts" / "python.exe"
    return ROOT / ".venv" / "bin" / "python"


def _selected_python() -> Path:
    if (ROOT / ".venv").exists():
        return _venv_python()
    return Path(sys.executable)


def _python_version(python: Path) -> tuple[int, int] | None:
    try:
        completed = subprocess.run(
            [
                str(python),
                "-c",
                "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=30.0,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    version = completed.stdout.strip()
    try:
        major, minor = version.split(".", maxsplit=1)
        return int(major), int(minor)
    except ValueError:
        return None


def _python_version_failure(name: str, python: Path) -> TaskResult | None:
    version = _python_version(python)
    if version is None:
        return TaskResult(name, "FAIL", f"cannot read Python version from {python}", 1)
    if version < (3, 11) or version >= (3, 14):
        found = f"{version[0]}.{version[1]}"
        return TaskResult(
            name,
            "FAIL",
            (
                f".venv uses Python {found}; project requires >=3.11,<3.14. "
                "Recreate .venv manually."
            ),
            1,
        )
    return None


def _task_python_or_skip(name: str) -> Path | TaskResult:
    python = _selected_python()
    if not python.exists():
        return _env_skip(name, f"Python executable is missing: {python}")
    if (ROOT / ".venv").exists():
        failure = _python_version_failure(name, python)
        if failure is not None:
            return failure
    return python


def target_install() -> TaskResult:
    venv_dir = ROOT / ".venv"
    if venv_dir.exists():
        python = _venv_python()
        if not python.exists():
            return TaskResult("install", "FAIL", ".venv exists but python executable is missing", 1)
        failure = _python_version_failure("install", python)
        if failure is not None:
            return failure
    else:
        venv.create(venv_dir, with_pip=True)
        python = _venv_python()
        failure = _python_version_failure("install", python)
        if failure is not None:
            return failure
    return _run(
        [str(python), "-m", "pip", "install", "-e", ".[dev]"],
        "install",
        1200.0,
    )


def target_lint() -> TaskResult:
    python = _task_python_or_skip("lint")
    if isinstance(python, TaskResult):
        return python
    if not _module_exists("ruff", python):
        return _env_skip("lint", f"ruff is not installed in {python}; run install")
    return _run([str(python), "-m", "ruff", "check", "."], "lint")


def target_fmt() -> TaskResult:
    python = _task_python_or_skip("fmt")
    if isinstance(python, TaskResult):
        return python
    if not _module_exists("ruff", python):
        return _env_skip("fmt", f"ruff is not installed in {python}; run install")
    return _run([str(python), "-m", "ruff", "format", "."], "fmt")


def target_typecheck() -> TaskResult:
    python = _task_python_or_skip("typecheck")
    if isinstance(python, TaskResult):
        return python
    if not _module_exists("mypy", python):
        return _env_skip("typecheck", f"mypy is not installed in {python}; run install")
    return _run([str(python), "-m", "mypy"], "typecheck")


def target_test() -> TaskResult:
    python = _task_python_or_skip("test")
    if isinstance(python, TaskResult):
        return python
    if not _module_exists("pytest", python):
        return _env_skip("test", f"pytest is not installed in {python}; run install")
    return _run(
        [str(python), "-m", "pytest", "-m", "not slow and not live_terminal and not mql5"],
        "test",
    )


def target_test_all() -> TaskResult:
    python = _task_python_or_skip("test-all")
    if isinstance(python, TaskResult):
        return python
    if not _module_exists("pytest", python):
        return _env_skip("test-all", f"pytest is not installed in {python}; run install")
    return _run([str(python), "-m", "pytest"], "test-all")


def target_codegen() -> TaskResult:
    codegen = ROOT / "tools" / "codegen.py"
    if not codegen.exists():
        return _skip("codegen", "tools/codegen.py is not available until SPEC-004")
    python = _task_python_or_skip("codegen")
    if isinstance(python, TaskResult):
        return python
    return _run([str(python), str(codegen)], "codegen")


def target_codegen_check() -> TaskResult:
    codegen = target_codegen()
    if codegen.status != "OK":
        return TaskResult("codegen-check", codegen.status, codegen.detail, codegen.code)
    return _run(["git", "diff", "--exit-code", "--", "contracts/gen"], "codegen-check")


def target_mql5_gate() -> TaskResult:
    if platform.system() != "Windows":
        return _skip("mql5-gate", "requires Windows and MetaEditor")
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if powershell is None:
        return _skip("mql5-gate", "PowerShell is not available")
    script = ROOT / "tools" / "run-mql5-tests.ps1"
    if not script.exists():
        return _skip("mql5-gate", "tools/run-mql5-tests.ps1 is missing")
    return _run(
        [powershell, "-ExecutionPolicy", "Bypass", "-File", str(script)],
        "mql5-gate",
        7200.0,
    )


TARGETS: dict[str, TaskFunc] = {
    "install": target_install,
    "lint": target_lint,
    "fmt": target_fmt,
    "typecheck": target_typecheck,
    "test": target_test,
    "test-all": target_test_all,
    "codegen": target_codegen,
    "codegen-check": target_codegen_check,
    "mql5-gate": target_mql5_gate,
}

CHECK_TARGETS = ("lint", "typecheck", "test", "codegen-check")
CHECK_FULL_TARGETS = ("lint", "typecheck", "test", "codegen-check", "test-all", "mql5-gate")


def run_sequence(
    names: Sequence[str],
    targets: Mapping[str, TaskFunc] = TARGETS,
) -> list[TaskResult]:
    results: list[TaskResult] = []
    for name in names:
        results.append(targets[name]())
    return results


def summarize(label: str, results: Sequence[TaskResult]) -> int:
    counts = {"OK": 0, "FAIL": 0, "SKIP": 0}
    env_skip_count = 0
    labels = {"OK": " OK ", "FAIL": "FAIL", "SKIP": "SKIP"}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1
        if result.status == "SKIP" and result.code != 0:
            env_skip_count += 1
        detail = f" -- {result.detail}" if result.detail else ""
        print(f"[{labels.get(result.status, result.status):4}] {result.name}{detail}")
    if counts["FAIL"]:
        print(
            f"{label}: FAILED ({counts['FAIL']} failed, "
            f"{counts['SKIP']} skipped, {counts['OK']} passed)"
        )
        return 1
    if env_skip_count:
        print(
            f"{label}: ENVIRONMENT INCOMPLETE ({env_skip_count} environment skipped, "
            f"{counts['SKIP'] - env_skip_count} planned skipped, "
            f"{counts['OK']} passed)"
        )
        return 3
    print(f"{label}: OK ({counts['OK']} passed, {counts['SKIP']} skipped)")
    return 0


def run_target(name: str) -> int:
    if name == "check":
        return summarize("check", run_sequence(CHECK_TARGETS))
    if name == "check-full":
        return summarize("check-full", run_sequence(CHECK_FULL_TARGETS))
    result = TARGETS[name]()
    return summarize(name, [result])


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=sorted([*TARGETS.keys(), "check", "check-full"]))
    args = parser.parse_args(argv)
    try:
        os.chdir(ROOT)
        return run_target(str(args.target))
    except KeyError as exc:
        print(f"task runner error: unknown target {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"task runner error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
