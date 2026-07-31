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
    read_events,
    read_ea_log_since,
    slow_enabled,
    wait_for_event,
    wait_for_event_count,
)

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "brain" / "gateway" / "echo_server.py"
TOKEN = "test-token"


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

    def _wait_for_backoff_ladder_connects(
        self,
        event_log: Path,
        expected_gaps: list[float],
        timeout: float,
    ) -> list[dict[str, Any]]:
        count = len(expected_gaps) + 1
        deadline = time.monotonic() + timeout
        last_gaps: list[float] = []
        while time.monotonic() < deadline:
            connects = [
                item for item in read_events(event_log) if item.get("event") == "connect"
            ]
            times = [float(item["monotonic"]) for item in connects]
            gaps = [times[idx + 1] - times[idx] for idx in range(len(times) - 1)]
            last_gaps = gaps
            for start_idx, gap in enumerate(gaps):
                if not 0.7 <= gap <= 2.6 or len(connects) - start_idx < count:
                    continue
                candidate = connects[start_idx : start_idx + count]
                candidate_times = [float(item["monotonic"]) for item in candidate]
                candidate_gaps = [
                    candidate_times[idx + 1] - candidate_times[idx]
                    for idx in range(len(candidate_times) - 1)
                ]
                if self._backoff_gaps_match(candidate_gaps, expected_gaps):
                    return candidate
            time.sleep(0.1)
        raise AssertionError(
            f"timed out waiting for {count} backoff ladder connects; observed gaps={last_gaps}"
        )

    def _backoff_gaps_match(self, gaps: list[float], expected: list[float]) -> bool:
        for observed, nominal in zip(gaps, expected, strict=True):
            if observed < nominal * 0.7 or observed > nominal * 1.5 + 1.1:
                return False
        for prev, current in zip(gaps, gaps[1:], strict=False):
            if current < prev * 0.7:
                return False
        return True

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
        with echo_server(port, event_log, "--close-on-accept"):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                expected = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]
                connects = self._wait_for_backoff_ladder_connects(
                    event_log,
                    expected,
                    timeout=100.0,
                )

        times = [float(item["monotonic"]) for item in connects]
        gaps = [times[idx + 1] - times[idx] for idx in range(len(times) - 1)]
        for observed, nominal in zip(gaps, expected, strict=True):
            self.assertGreaterEqual(observed, nominal * 0.7)
            self.assertLessEqual(observed, nominal * 1.5 + 1.1)
        for prev, current in zip(gaps, gaps[1:], strict=False):
            self.assertGreaterEqual(current, prev * 0.7)

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

    @unittest.skipUnless(slow_enabled(), "set EA_FARM_LIVE_MT5_SLOW=1 to run the 1h soak")
    def test_no_heartbeat_loss_over_1h(self) -> None:
        port = chaos_port()
        event_log = self._event_log("live-events-soak")
        event_log.write_text("", encoding="utf-8")
        with echo_server(port, event_log):
            event_log.write_text("", encoding="utf-8")
            with live_terminal(port):
                wait_for_event(event_log, "hello_ack", timeout=30.0)
                deadline = time.monotonic() + 3600.0
                last_progress = time.monotonic()
                seen_count = 0
                while time.monotonic() < deadline:
                    heartbeats_now = [
                        float(item["monotonic"])
                        for item in read_events(event_log)
                        if item.get("event") == "heartbeat" and item.get("ack") is True
                    ]
                    if len(heartbeats_now) > seen_count:
                        seen_count = len(heartbeats_now)
                        last_progress = time.monotonic()
                    self.assertLessEqual(time.monotonic() - last_progress, 3.5)
                    time.sleep(0.5)

        heartbeats = [
            float(item["monotonic"])
            for item in read_events(event_log)
            if item.get("event") == "heartbeat" and item.get("ack") is True
        ]
        self.assertGreaterEqual(len(heartbeats), 1700)
        gaps = [heartbeats[idx + 1] - heartbeats[idx] for idx in range(len(heartbeats) - 1)]
        self.assertLessEqual(max(gaps), 3.5)


if __name__ == "__main__":
    unittest.main()
