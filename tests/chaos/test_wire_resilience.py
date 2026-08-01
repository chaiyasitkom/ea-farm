from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, cast

from tests.chaos.live_mt5_harness import (
    chaos_port,
    echo_server,
    live_enabled,
    live_terminal,
    mark_ea_log,
    read_ea_log_since,
    read_events,
    slow_enabled,
    wait_for_event,
    wait_for_event_count,
)

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "brain" / "gateway" / "echo_server.py"
TOKEN = "test-token"
HEARTBEAT_SEC = 2
FAST_HEARTBEAT_INTERVAL_SECONDS = 300
SOAK_SECONDS = 3600
WIRE_DIAG = Path(
    r"C:\Users\User\AppData\Roaming\MetaQuotes\Terminal\Common\Files\ea-farm-wire-diag.jsonl"
)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


@contextmanager
def server_process(*args: str) -> Iterator[tuple[subprocess.Popen[str], int]]:
    port = free_port()
    env = os.environ.copy()
    env["FARM_TOKEN"] = TOKEN
    proc = subprocess.Popen(
        [sys.executable, str(SERVER), "--port", str(port), *args],
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
        yield proc, port
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5.0)


def send_message(sock: socket.socket, message: dict[str, object]) -> None:
    sock.sendall((json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8"))


def recv_message(sock: socket.socket) -> dict[str, Any]:
    data = b""
    while not data.endswith(b"\n"):
        chunk = sock.recv(4096)
        if not chunk:
            raise AssertionError("socket closed before response")
        data += chunk
    parsed = json.loads(data.decode("utf-8"))
    if not isinstance(parsed, dict):
        raise AssertionError("response was not a JSON object")
    return cast(dict[str, Any], parsed)


class EventTail:
    def __init__(self, path: Path, *, from_end: bool = False) -> None:
        self.path = path
        self.offset = path.stat().st_size if from_end and path.exists() else 0
        self.partial = ""

    def read_new(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        current_size = self.path.stat().st_size
        if current_size < self.offset:
            self.offset = 0
            self.partial = ""
        events: list[dict[str, Any]] = []
        with self.path.open("r", encoding="utf-8") as fh:
            fh.seek(self.offset)
            chunk = fh.read()
            self.offset = fh.tell()
        if not chunk:
            return []

        data = self.partial + chunk
        last_newline = data.rfind("\n")
        if last_newline < 0:
            self.partial = data
            return []

        complete = data[: last_newline + 1]
        self.partial = data[last_newline + 1 :]
        for line in complete.splitlines():
            if not line.strip():
                continue
            parsed = json.loads(line)
            if isinstance(parsed, dict):
                events.append(parsed)
        return events


def _event_time(item: dict[str, Any]) -> str:
    value = item.get("monotonic", item.get("ts", "?"))
    try:
        return f"{float(value):.3f}"
    except (TypeError, ValueError):
        return str(value)


def _format_timeline(events: list[dict[str, Any]], title: str) -> str:
    lines = [title]
    for item in events[-20:]:
        event = item.get("event", item.get("ev", "?"))
        details = " ".join(
            f"{key}={value}"
            for key, value in item.items()
            if key not in {"event", "ev", "wall_time", "monotonic", "ts"}
        )
        lines.append(f"  t={_event_time(item)} {event} {details}".rstrip())
    return "\n".join(lines)


def _format_seconds(values: list[float]) -> str:
    return "[" + ", ".join(f"{value:.3f}" for value in values) + "]"


def _read_wire_diag_tail(path: Path = WIRE_DIAG, limit: int = 20) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    events: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parsed = json.loads(line)
        if isinstance(parsed, dict):
            events.append(parsed)
    return events[-limit:]


def hello(session_id: str, token: str = TOKEN) -> dict[str, object]:
    return {
        "v": 1,
        "type": "HELLO",
        "msg_id": "01J8X4K2P9QZ7M3N",
        "session_id": session_id,
        "ts_server": "2026-07-26T14:30:00Z",
        "ts_sent": "2026-07-26T14:30:00Z",
        "payload": {"token": token},
    }


def heartbeat(session_id: str) -> dict[str, object]:
    return {
        "v": 1,
        "type": "HEARTBEAT",
        "msg_id": "01J8X4K2P9QZ7M3NABCD123456",
        "session_id": session_id,
        "ts_server": "2026-07-26T14:30:02Z",
        "ts_sent": "2026-07-26T14:30:02Z",
        "payload": {
            "seq": 1,
            "wire": {
                "state": "READY",
                "send_queue_depth": 0,
                "messages_sent": 1,
                "messages_recv": 1,
                "reconnect_count": 1,
                "bytes_dropped": 0,
                "seconds_since_last_inbound": 0,
                "pump_p99_us": 100,
            },
        },
    }


class WireResilienceTests(unittest.TestCase):
    def test_hello_accepted(self) -> None:
        with server_process() as (_proc, port):
            with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
                send_message(sock, hello("acct-1-EURUSD-H1"))
                response = recv_message(sock)
        self.assertEqual(response["type"], "HELLO_ACK")
        self.assertIs(response["payload"]["accepted"], True)

    def test_bad_token_rejected(self) -> None:
        with server_process() as (_proc, port):
            with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
                send_message(sock, hello("acct-1-EURUSD-H1", token="bad"))
                response = recv_message(sock)
        self.assertEqual(response["type"], "HELLO_ACK")
        self.assertIs(response["payload"]["accepted"], False)
        self.assertEqual(response["payload"]["reject_reason"], "BAD_TOKEN")

    def test_duplicate_session_rejected(self) -> None:
        with server_process() as (_proc, port):
            first = socket.create_connection(("127.0.0.1", port), timeout=2.0)
            second = socket.create_connection(("127.0.0.1", port), timeout=2.0)
            try:
                send_message(first, hello("acct-dup-EURUSD-H1"))
                self.assertIs(recv_message(first)["payload"]["accepted"], True)
                send_message(second, hello("acct-dup-EURUSD-H1"))
                response = recv_message(second)
            finally:
                first.close()
                second.close()
        self.assertIs(response["payload"]["accepted"], False)
        self.assertEqual(response["payload"]["reject_reason"], "DUPLICATE_SESSION")

    def test_heartbeat_ack(self) -> None:
        with server_process() as (_proc, port):
            with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
                send_message(sock, hello("acct-hb-EURUSD-H1"))
                self.assertIs(recv_message(sock)["payload"]["accepted"], True)
                send_message(sock, heartbeat("acct-hb-EURUSD-H1"))
                response = recv_message(sock)
        self.assertEqual(response["type"], "HEARTBEAT_ACK")
        self.assertEqual(response["payload"]["seq"], 1)
        self.assertIn("server_time", response["payload"])

    def test_malformed_json_is_skipped_connection_stays_open(self) -> None:
        with server_process() as (_proc, port):
            with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
                sock.sendall(b"{bad json}\n")
                send_message(sock, hello("acct-malformed-EURUSD-H1"))
                response = recv_message(sock)
        self.assertEqual(response["type"], "HELLO_ACK")
        self.assertIs(response["payload"]["accepted"], True)

    def test_non_protocol_tcp_connection_is_not_logged_as_connect(self) -> None:
        event_log = Path(tempfile.gettempdir()) / "ea-farm-non-protocol-connect.jsonl"
        event_log.write_text("", encoding="utf-8")
        with server_process("--event-log", str(event_log)) as (_proc, port):
            with socket.create_connection(("127.0.0.1", port), timeout=2.0):
                pass
            time.sleep(0.2)
            self.assertEqual(
                [item for item in read_events(event_log) if item.get("event") == "connect"],
                [],
            )

            with socket.create_connection(("127.0.0.1", port), timeout=2.0) as sock:
                send_message(sock, hello("acct-real-EURUSD-H1"))
                response = recv_message(sock)
            self.assertIs(response["payload"]["accepted"], True)

        connects = [item for item in read_events(event_log) if item.get("event") == "connect"]
        self.assertEqual(len(connects), 1)
        self.assertEqual(connects[0]["session_id"], "acct-real-EURUSD-H1")

    def test_log_reader_handles_utf16(self) -> None:
        path = Path(tempfile.gettempdir()) / "ea-farm-test-utf16.log"
        path.write_bytes("before\n".encode("utf-16le"))
        mark = mark_ea_log(path)
        with path.open("ab") as fh:
            fh.write("after\n".encode("utf-16le"))
        self.assertEqual(read_ea_log_since(mark), "after\n")

    def test_log_reader_ignores_lines_before_mark(self) -> None:
        path = Path(tempfile.gettempdir()) / "ea-farm-test-mark.log"
        path.write_bytes("old\n".encode("utf-16le"))
        mark = mark_ea_log(path)
        with path.open("ab") as fh:
            fh.write("new\n".encode("utf-16le"))
        self.assertNotIn("old", read_ea_log_since(mark))
        self.assertIn("new", read_ea_log_since(mark))


@unittest.skipUnless(live_enabled(), "set EA_FARM_LIVE_MT5=1 to run live-chart MT5 chaos tests")
class LiveChartChaosTests(unittest.TestCase):
    def _event_log(self, name: str) -> Path:
        return Path(tempfile.gettempdir()) / f"ea-farm-{name}.jsonl"

    def _wait_for_backoff_ladder_diag(
        self,
        diag_tail: EventTail,
        expected_backoff: list[int],
        timeout: float,
    ) -> list[dict[str, Any]]:
        expected_with_cap = [*expected_backoff, expected_backoff[-1]]
        deadline = time.monotonic() + timeout
        events: list[dict[str, Any]] = []
        last_seen: list[int] = []
        while time.monotonic() < deadline:
            events.extend(diag_tail.read_new())
            reconnects = [item for item in events if item.get("ev") == "reconnect"]
            for start_idx in range(0, len(reconnects) - len(expected_with_cap) + 1):
                candidate = reconnects[start_idx : start_idx + len(expected_with_cap)]
                candidate_backoff = [
                    int(item["backoff_sec"])
                    for item in candidate
                    if "backoff_sec" in item
                ]
                last_seen = candidate_backoff
                if candidate_backoff == expected_with_cap:
                    for item in candidate:
                        if not isinstance(item.get("tick_ms"), int):
                            raise AssertionError(
                                "reconnect diag missing integer tick_ms\n"
                                + _format_timeline(reconnects, "ea reconnect timeline")
                            )
                    start_tick = int(candidate[0]["tick_ms"])
                    end_tick = int(candidate[-1]["tick_ms"])
                    candidate_events = [
                        item
                        for item in events
                        if start_tick <= int(item.get("tick_ms", -1)) <= end_tick
                    ]
                    for item in candidate_events:
                        if item.get("ev") == "state" and not isinstance(item.get("tick_ms"), int):
                            raise AssertionError(
                                "state diag missing integer tick_ms\n"
                                + _format_timeline(candidate_events, "ea candidate timeline")
                            )
                    return candidate_events
            time.sleep(0.1)
        raise AssertionError(
            "timed out waiting for EA reconnect ladder "
            f"{expected_with_cap}; observed backoff_sec={last_seen}\n"
            + _format_timeline(reconnects, "ea reconnect timeline")
        )

    def _assert_backoff_waits_match_diag(
        self,
        candidate_events: list[dict[str, Any]],
        expected_backoff: list[int],
    ) -> list[float]:
        reconnects = [item for item in candidate_events if item.get("ev") == "reconnect"]
        ticks_ms = [int(item["tick_ms"]) for item in reconnects]
        waits: list[float] = []
        for idx, nominal in enumerate(expected_backoff):
            next_connecting = next(
                (
                    item
                    for item in candidate_events
                    if item.get("ev") == "state"
                    and item.get("to") == "CONNECTING"
                    and int(item.get("tick_ms", -1)) > ticks_ms[idx]
                    and int(item.get("tick_ms", -1)) <= ticks_ms[idx + 1]
                ),
                None,
            )
            if next_connecting is None:
                raise AssertionError(
                    "missing CONNECTING state after reconnect diag "
                    f"idx={idx} backoff_sec={nominal}\n"
                    + _format_timeline(candidate_events, "ea candidate timeline")
                )
            waits.append((int(next_connecting["tick_ms"]) - ticks_ms[idx]) / 1000.0)

        for observed, nominal in zip(waits, expected_backoff, strict=True):
            lower = nominal * 0.8
            upper = nominal * 1.2 + 1.0
            self.assertGreaterEqual(
                observed,
                lower,
                f"observed waits={waits} expected_backoff={expected_backoff}",
            )
            self.assertLessEqual(
                observed,
                upper,
                f"observed waits={waits} expected_backoff={expected_backoff}",
            )
        return waits

    def test_ea_reconnects_after_server_kill(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-reconnect")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log) as first_server:
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                first = wait_for_event(event_log, "hello_ack", timeout=30.0)
                self.assertIs(first["accepted"], True)

                first_server.terminate()
                first_server.wait(timeout=5.0)
                time.sleep(2.0)
                with echo_server(port, event_log):
                    acks = wait_for_event_count(event_log, "hello_ack", 2, timeout=35.0)

        self.assertIs(acks[1]["accepted"], True)

    def test_backoff_schedule_matches_spec(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-backoff")
        event_log.write_text("", encoding="utf-8")
        diag_tail = EventTail(WIRE_DIAG, from_end=True)
        with echo_server(port, event_log, "--close-on-accept"):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                expected = [1, 2, 4, 8, 16, 30]
                candidate_events = self._wait_for_backoff_ladder_diag(
                    diag_tail,
                    expected,
                    timeout=100.0,
                )

        reconnects = [item for item in candidate_events if item.get("ev") == "reconnect"]
        self.assertEqual([int(item["backoff_sec"]) for item in reconnects], [*expected, 30])
        waits = self._assert_backoff_waits_match_diag(candidate_events, expected)
        ticks_ms = [int(item["tick_ms"]) for item in reconnects]
        gaps = [
            (ticks_ms[idx + 1] - ticks_ms[idx]) / 1000.0
            for idx in range(len(ticks_ms) - 1)
        ]
        print(
            "backoff_ladder "
            f"backoff_sec={[int(item['backoff_sec']) for item in reconnects]} "
            f"waits_sec={_format_seconds(waits)} "
            f"reconnect_gaps_sec={_format_seconds(gaps)}",
            flush=True,
        )

    def test_bad_token_waits_60s(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-bad-token")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log, "--force-hello-reject", "BAD_TOKEN"):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                acks = wait_for_event_count(event_log, "hello_ack", 2, timeout=75.0)

        first = float(acks[0]["monotonic"])
        second = float(acks[1]["monotonic"])
        self.assertFalse(acks[0]["accepted"])
        self.assertEqual(acks[0]["reason"], "BAD_TOKEN")
        self.assertGreaterEqual(second - first, 59.0)
        print(f"bad_token_retry_delay_sec={second - first:.3f}", flush=True)

    def test_ea_handles_duplicate_session_rejection(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-duplicate")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log, "--force-hello-reject", "DUPLICATE_SESSION"):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                acks = wait_for_event_count(event_log, "hello_ack", 2, timeout=75.0)

        first = float(acks[0]["monotonic"])
        second = float(acks[1]["monotonic"])
        self.assertFalse(acks[0]["accepted"])
        self.assertEqual(acks[0]["reason"], "DUPLICATE_SESSION")
        self.assertGreaterEqual(second - first, 55.0)
        print(f"duplicate_session_retry_delay_sec={second - first:.3f}", flush=True)

    def test_heartbeat_gap_triggers_reconnect(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-heartbeat-gap")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log, "--no-heartbeat-ack"):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                wait_for_event(event_log, "hello_ack", timeout=30.0)
                connects = wait_for_event_count(event_log, "connect", 2, timeout=25.0)

        gap = float(connects[1]["monotonic"]) - float(connects[0]["monotonic"])
        self.assertGreaterEqual(gap, 4.0)
        self.assertLessEqual(gap, 12.0)
        print(f"heartbeat_gap_reconnect_sec={gap:.3f}", flush=True)

    def test_heartbeat_interval_within_5pct_over_5min(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-heartbeat-interval")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                wait_for_event(event_log, "hello_ack", timeout=30.0)
                event_tail = EventTail(event_log)
                server_events: list[dict[str, Any]] = read_events(event_log)
                deadline = time.monotonic() + FAST_HEARTBEAT_INTERVAL_SECONDS
                last_progress = time.monotonic()
                while time.monotonic() < deadline:
                    new_events = event_tail.read_new()
                    server_events.extend(new_events)
                    if any(
                        item.get("event") == "heartbeat" and item.get("ack") is True
                        for item in new_events
                    ):
                        last_progress = time.monotonic()
                    if time.monotonic() - last_progress > 10.0:
                        raise AssertionError(
                            "no heartbeat progress for 10s\n"
                            + _format_timeline(server_events, "server timeline")
                            + "\n"
                            + _format_timeline(_read_wire_diag_tail(), "ea pump timeline")
                        )
                    time.sleep(0.5)

        events = read_events(event_log)
        heartbeats = [
            float(item["monotonic"])
            for item in events
            if item.get("event") == "heartbeat" and item.get("ack") is True
        ]
        min_heartbeats = int(
            FAST_HEARTBEAT_INTERVAL_SECONDS / HEARTBEAT_SEC * 0.95
        )
        self.assertGreaterEqual(len(heartbeats), min_heartbeats)
        gaps = [heartbeats[idx + 1] - heartbeats[idx] for idx in range(len(heartbeats) - 1)]
        self.assertTrue(gaps, "not enough heartbeats to measure interval")
        mean_gap = sum(gaps) / len(gaps)
        lower = HEARTBEAT_SEC * 0.95
        upper = HEARTBEAT_SEC * 1.05
        self.assertGreaterEqual(
            mean_gap,
            lower,
            f"mean_gap={mean_gap:.4f} min={min(gaps):.4f} max={max(gaps):.4f}",
        )
        self.assertLessEqual(
            mean_gap,
            upper,
            f"mean_gap={mean_gap:.4f} min={min(gaps):.4f} max={max(gaps):.4f}",
        )
        print(
            "heartbeat_interval "
            f"count={len(heartbeats)} mean_gap_sec={mean_gap:.4f} "
            f"min_gap_sec={min(gaps):.4f} max_gap_sec={max(gaps):.4f}",
            flush=True,
        )

    @unittest.skipUnless(slow_enabled(), "set EA_FARM_LIVE_MT5_SLOW=1 to run the 1h soak")
    def test_no_heartbeat_loss_over_1h(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-soak")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                wait_for_event(event_log, "hello_ack", timeout=30.0)
                event_tail = EventTail(event_log)
                server_events: list[dict[str, Any]] = read_events(event_log)
                deadline = time.monotonic() + SOAK_SECONDS
                last_progress = time.monotonic()
                seen_count = 0
                while time.monotonic() < deadline:
                    new_events = event_tail.read_new()
                    server_events.extend(new_events)
                    new_heartbeats = [
                        item
                        for item in new_events
                        if item.get("event") == "heartbeat" and item.get("ack") is True
                    ]
                    if new_heartbeats:
                        seen_count += len(new_heartbeats)
                        last_progress = time.monotonic()
                    if time.monotonic() - last_progress > 10.0:
                        raise AssertionError(
                            "no heartbeat progress for 10s\n"
                            + _format_timeline(server_events, "server timeline")
                            + "\n"
                            + _format_timeline(_read_wire_diag_tail(), "ea pump timeline")
                        )
                    time.sleep(0.5)

        events = read_events(event_log)
        heartbeats = [
            float(item["monotonic"])
            for item in events
            if item.get("event") == "heartbeat" and item.get("ack") is True
        ]
        min_heartbeats = int(SOAK_SECONDS / HEARTBEAT_SEC * 0.95)
        self.assertGreaterEqual(len(heartbeats), min_heartbeats)
        gaps = [heartbeats[idx + 1] - heartbeats[idx] for idx in range(len(heartbeats) - 1)]
        if gaps:
            self.assertLessEqual(
                max(gaps),
                3.5,
                _format_timeline(events, "server timeline")
                + "\n"
                + _format_timeline(_read_wire_diag_tail(), "ea pump timeline"),
            )
        print(
            "heartbeat_soak "
            f"count={len(heartbeats)} "
            f"max_gap_sec={(max(gaps) if gaps else 0.0):.4f}",
            flush=True,
        )


if __name__ == "__main__":
    unittest.main()
