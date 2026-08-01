from __future__ import annotations

import argparse
import importlib.util
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


def _module_exists(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


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


def _venv_python() -> Path:
    if platform.system() == "Windows":
        return ROOT / ".venv" / "Scripts" / "python.exe"
    return ROOT / ".venv" / "bin" / "python"


def target_install() -> TaskResult:
    venv_dir = ROOT / ".venv"
    if venv_dir.exists():
        python = _venv_python()
        if not python.exists():
            return TaskResult("install", "FAIL", ".venv exists but python executable is missing", 1)
    else:
        venv.create(venv_dir, with_pip=True)
        python = _venv_python()
    return _run([str(python), "-m", "pip", "install", "-e", ".[dev]"], "install", 1200.0)


def target_lint() -> TaskResult:
    if not _module_exists("ruff"):
        return _skip("lint", "ruff is not installed; run install")
    return _run([sys.executable, "-m", "ruff", "check", "."], "lint")


def target_fmt() -> TaskResult:
    if not _module_exists("ruff"):
        return _skip("fmt", "ruff is not installed; run install")
    return _run([sys.executable, "-m", "ruff", "format", "."], "fmt")


def target_typecheck() -> TaskResult:
    if not _module_exists("mypy"):
        return _skip("typecheck", "mypy is not installed; run install")
    return _run([sys.executable, "-m", "mypy"], "typecheck")


def target_test() -> TaskResult:
    if not _module_exists("pytest"):
        return _skip("test", "pytest is not installed; run install")
    return _run(
        [sys.executable, "-m", "pytest", "-m", "not slow and not live_terminal and not mql5"],
        "test",
    )


def target_test_all() -> TaskResult:
    if not _module_exists("pytest"):
        return _skip("test-all", "pytest is not installed; run install")
    return _run([sys.executable, "-m", "pytest"], "test-all")


def target_codegen() -> TaskResult:
    codegen = ROOT / "tools" / "codegen.py"
    if not codegen.exists():
        return _skip("codegen", "tools/codegen.py is not available until SPEC-004")
    return _run([sys.executable, str(codegen)], "codegen")


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
    return _run([powershell, "-ExecutionPolicy", "Bypass", "-File", str(script)], "mql5-gate", 7200.0)


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


def run_sequence(names: Sequence[str], targets: Mapping[str, TaskFunc] = TARGETS) -> list[TaskResult]:
    results: list[TaskResult] = []
    for name in names:
        results.append(targets[name]())
    return results


def summarize(label: str, results: Sequence[TaskResult]) -> int:
    counts = {"OK": 0, "FAIL": 0, "SKIP": 0}
    labels = {"OK": " OK ", "FAIL": "FAIL", "SKIP": "SKIP"}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1
        detail = f" -- {result.detail}" if result.detail else ""
        print(f"[{labels.get(result.status, result.status):4}] {result.name}{detail}")
    if counts["FAIL"]:
        print(
            f"{label}: FAILED ({counts['FAIL']} failed, "
            f"{counts['SKIP']} skipped, {counts['OK']} passed)"
        )
        return 1
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
