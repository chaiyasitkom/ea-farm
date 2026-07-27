from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
import unittest
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, cast

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


if __name__ == "__main__":
    unittest.main()
