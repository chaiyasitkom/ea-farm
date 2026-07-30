from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "brain" / "gateway" / "echo_server.py"
TOKEN = "test-token"

IUX_DATA = Path(
    r"C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\A45801173FBAFA01B9AFF0EEDE7938E3"
)
IUX_TERMINAL = Path(r"C:\Program Files\IUX Markets MT5 Terminal3\terminal64.exe")
IUX_METAEDITOR = Path(r"C:\Program Files\IUX Markets MT5 Terminal3\metaeditor64.exe")
IUX_SYMBOL = "EURUSD.iux"


def live_enabled() -> bool:
    return os.environ.get("EA_FARM_LIVE_MT5") == "1"


def slow_enabled() -> bool:
    return os.environ.get("EA_FARM_LIVE_MT5_SLOW") == "1"


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def read_events(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    events: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            parsed = json.loads(line)
            if isinstance(parsed, dict):
                events.append(parsed)
    return events


def wait_for_event(path: Path, event: str, timeout: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for item in read_events(path):
            if item.get("event") == event:
                return item
        time.sleep(0.1)
    raise AssertionError(f"timed out waiting for event={event}")


def wait_for_event_count(path: Path, event: str, count: int, timeout: float) -> list[dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        matches = [item for item in read_events(path) if item.get("event") == event]
        if len(matches) >= count:
            return matches
        time.sleep(0.1)
    raise AssertionError(f"timed out waiting for {count} event={event}")


def assert_iux_available() -> None:
    for path in (IUX_DATA, IUX_TERMINAL, IUX_METAEDITOR):
        if not path.exists():
            raise AssertionError(f"IUX MT5 path not found: {path}")


def assert_no_terminal_running() -> None:
    result = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq terminal64.exe", "/FO", "CSV", "/NH"],
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if "terminal64.exe" in result.stdout:
        raise AssertionError("terminal64.exe is already running; close MT5 before live chaos tests")


def deploy_and_compile_farm_executor() -> None:
    assert_iux_available()
    include_dst = IUX_DATA / "MQL5" / "Include" / "Farm"
    expert_dst = IUX_DATA / "MQL5" / "Experts"
    include_dst.mkdir(parents=True, exist_ok=True)
    expert_dst.mkdir(parents=True, exist_ok=True)

    for src in (ROOT / "mt5-ea" / "Include" / "Farm").glob("*.mqh"):
        shutil.copy2(src, include_dst / src.name)
    shutil.copy2(ROOT / "mt5-ea" / "Experts" / "FarmExecutor.mq5", expert_dst / "FarmExecutor.mq5")

    log_path = Path(tempfile.gettempdir()) / "ea-farm-live-FarmExecutor.log"
    result = subprocess.run(
        [
            str(IUX_METAEDITOR),
            f"/compile:{expert_dst / 'FarmExecutor.mq5'}",
            f"/inc:{IUX_DATA / 'MQL5'}",
            f"/log:{log_path}",
        ],
        check=False,
        timeout=60,
    )
    if result.returncode not in (0, 1):
        raise AssertionError(f"MetaEditor exited with {result.returncode}")
    if not (expert_dst / "FarmExecutor.ex5").exists():
        raise AssertionError(f"FarmExecutor.ex5 was not produced; log={log_path}")


def write_startup_files(port: int, work_dir: Path) -> Path:
    set_text = "\r\n".join(
        [
            "InpBrainHost=127.0.0.1",
            f"InpBrainPort={port}",
            f"InpBrainToken={TOKEN}",
            "InpStrategyId=trend_v1",
            "InpMagic=770001",
            "InpHeartbeatSec=2",
            "InpBrainTimeoutSec=10",
            "InpSendQueueMax=256",
            "InpVerboseLog=true",
        ]
    )

    set_name = "farm-chaos.set"
    for set_dir in (
        IUX_DATA / "MQL5" / "Presets",
        IUX_DATA / "MQL5" / "Profiles" / "Tester",
        IUX_DATA / "MQL5" / "Experts",
    ):
        set_dir.mkdir(parents=True, exist_ok=True)
        (set_dir / set_name).write_text(set_text, encoding="ascii")

    ini = work_dir / "farm-chaos-live.ini"
    ini.write_text(
        "\r\n".join(
            [
                "[Experts]",
                "AllowLiveTrading=1",
                "AllowDllImport=0",
                "Enabled=1",
                "Account=0",
                "Profile=0",
                "",
                "[StartUp]",
                "Expert=FarmExecutor",
                f"Symbol={IUX_SYMBOL}",
                "Period=H1",
                f"ExpertParameters={set_name}",
            ]
        ),
        encoding="ascii",
    )
    return ini


@contextmanager
def echo_server(port: int, event_log: Path, *args: str) -> Iterator[subprocess.Popen[str]]:
    env = os.environ.copy()
    env["FARM_TOKEN"] = TOKEN
    proc = subprocess.Popen(
        [sys.executable, str(SERVER), "--port", str(port), "--event-log", str(event_log), *args],
        cwd=ROOT,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    try:
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.05):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            raise AssertionError("echo server did not start")
        yield proc
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5.0)


@contextmanager
def live_terminal(port: int) -> Iterator[subprocess.Popen[str]]:
    assert_no_terminal_running()
    deploy_and_compile_farm_executor()
    with tempfile.TemporaryDirectory(prefix="ea-farm-live-") as raw:
        ini = write_startup_files(port, Path(raw))
        proc = subprocess.Popen([str(IUX_TERMINAL), f"/config:{ini}"], cwd=ROOT)
        try:
            yield proc
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10.0)
