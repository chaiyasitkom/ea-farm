from __future__ import annotations

import socket
import tempfile
import time
from datetime import datetime, timedelta
from pathlib import Path

from pytest import MonkeyPatch

import tests.chaos.live_mt5_harness as harness
from tests.chaos.live_mt5_harness import read_events
from tests.chaos.test_wire_resilience import (
    hello,
    recv_message,
    send_message,
    server_process,
)

SESSION_ID = "acct-1-EURUSD-H1"


def envelope(message_type: str, payload: dict[str, object], seq: int) -> dict[str, object]:
    return {
        "v": 1,
        "type": message_type,
        "msg_id": f"01J8X4K2P9QZ7M3N4R5T6V7{seq % 1000:03d}",
        "session_id": SESSION_ID,
        "ts_server": "2026-07-26T14:30:00Z",
        "ts_sent": "2026-07-26T14:30:00Z",
        "payload": payload,
    }


def bar_payload(index: int) -> dict[str, object]:
    bar_time = datetime(2026, 7, 26) + timedelta(hours=index)
    return {
        "symbol": "EURUSD",
        "timeframe": "H1",
        "bar_time": f"{bar_time:%Y-%m-%dT%H:%M:%SZ}",
        "open": 1.08000 + index * 0.0001,
        "high": 1.08100 + index * 0.0001,
        "low": 1.07900 + index * 0.0001,
        "close": 1.08050 + index * 0.0001,
        "tick_volume": 4000 + index,
        "real_volume": 0,
        "spread_points_avg": 8,
        "spread_points_max": 12,
        "is_final": True,
    }


def state_payload() -> dict[str, object]:
    return {
        "balance": 10000.0,
        "equity": 10042.0,
        "margin_used": 0.0,
        "margin_free": 10042.0,
        "margin_level_pct": None,
        "equity_hwm": 10042.0,
        "day_start_equity": 10000.0,
        "day_pl": 42.0,
        "day_pl_pct": 0.42,
        "positions": [],
        "pending_orders": [],
        "owned_net": {"EURUSD": 0.0},
        "owned_ticket_count": {"EURUSD": 0},
        "foreign_positions": {
            "count": 0,
            "symbols": [],
            "total_volume": 0.0,
            "margin_estimate": 0.0,
        },
        "account_margin_mode": "RETAIL_HEDGING",
        "guard": {
            "halted": False,
            "halt_reason": None,
            "mode": "NORMAL",
            "current_spread_points": 8,
            "internal_hedge_detected": False,
            "halted_until": None,
        },
    }


def event_log(name: str) -> Path:
    path = Path(tempfile.gettempdir()) / f"ea-farm-state-reporter-{name}.jsonl"
    path.write_text("", encoding="utf-8")
    return path


def test_live_harness_set_file_does_not_double_crlf(
    monkeypatch: MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(harness, "IUX_DATA", tmp_path / "terminal")
    harness.write_startup_files(12345, tmp_path)

    raw = (tmp_path / "terminal" / "MQL5" / "Presets" / "farm-chaos.set").read_bytes()
    assert b"\r\n" in raw
    assert b"\r\r" not in raw
    assert b"InpStrategyId=trend_v1\r\n" in raw


def connect_and_hello(port: int) -> socket.socket:
    sock = socket.create_connection(("127.0.0.1", port), timeout=2.0)
    send_message(sock, hello(SESSION_ID))
    response = recv_message(sock)
    assert response["payload"]["accepted"] is True
    return sock


def test_backfill_300_bars_all_received_in_order() -> None:
    log = event_log("backfill")
    with server_process("--event-log", str(log)) as (_proc, port):
        with connect_and_hello(port) as sock:
            for idx in range(1, 301):
                send_message(sock, envelope("BAR", bar_payload(idx), idx))
                recv_message(sock)
        time.sleep(0.1)
    bars = [item for item in read_events(log) if item.get("event") == "bar"]
    assert len(bars) == 300
    assert [int(item["count"]) for item in bars] == list(range(1, 301))


def test_heartbeat_uninterrupted_during_backfill() -> None:
    log = event_log("heartbeat")
    with server_process("--event-log", str(log)) as (_proc, port):
        with connect_and_hello(port) as sock:
            send_message(
                sock,
                envelope(
                    "HEARTBEAT",
                    {
                        "seq": 1,
                        "wire": {
                            "state": "READY",
                            "send_queue_depth": 0,
                            "messages_sent": 1,
                            "messages_recv": 1,
                            "reconnect_count": 1,
                            "bytes_dropped": 0,
                            "seconds_since_last_inbound": 0,
                            "broker_utc_offset_sec": 10800,
                            "pump_p99_us": 100,
                        },
                    },
                    1,
                ),
            )
            assert recv_message(sock)["type"] == "HEARTBEAT_ACK"
            send_message(sock, envelope("BAR", bar_payload(2), 2))
            recv_message(sock)
        time.sleep(0.1)
    events = read_events(log)
    assert any(item.get("event") == "heartbeat" and item.get("ack") is True for item in events)
    assert any(item.get("event") == "bar" for item in events)


def test_all_payloads_validate_against_schema() -> None:
    log = event_log("validation")
    with server_process("--event-log", str(log)) as (_proc, port):
        with connect_and_hello(port) as sock:
            send_message(sock, envelope("BAR", bar_payload(3), 3))
            recv_message(sock)
            send_message(sock, envelope("STATE", state_payload(), 4))
            recv_message(sock)
        time.sleep(0.1)
    valid = [item for item in read_events(log) if item.get("event") == "payload_valid"]
    assert {item.get("type") for item in valid} >= {"HELLO", "BAR", "STATE"}


def test_bar_gap_detectable_by_bar_time() -> None:
    log = event_log("gap")
    with server_process("--event-log", str(log)) as (_proc, port):
        with connect_and_hello(port) as sock:
            send_message(sock, envelope("BAR", bar_payload(1), 1))
            recv_message(sock)
            send_message(sock, envelope("BAR", bar_payload(3), 3))
            recv_message(sock)
        time.sleep(0.1)
    bars = [item for item in read_events(log) if item.get("event") == "bar"]
    assert [item["bar_time"] for item in bars] == [
        "2026-07-26T01:00:00Z",
        "2026-07-26T03:00:00Z",
    ]


def test_state_matches_mt5_positions() -> None:
    log = event_log("state")
    with server_process("--event-log", str(log)) as (_proc, port):
        with connect_and_hello(port) as sock:
            send_message(sock, envelope("STATE", state_payload(), 1))
            recv_message(sock)
        time.sleep(0.1)
    states = [item for item in read_events(log) if item.get("event") == "state"]
    assert len(states) == 1
    assert states[0]["positions"] == 0
    assert states[0]["owned_net"] == {"EURUSD": 0.0}
