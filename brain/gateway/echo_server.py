from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import signal
import time
from dataclasses import dataclass, field
from typing import Any

PROTOCOL_VERSION = 1
MAX_FRAME_BYTES = 64 * 1024
ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def ulid() -> str:
    timestamp_ms = int(time.time() * 1000)
    chars = ["0"] * 10
    for idx in range(9, -1, -1):
        chars[idx] = ULID_ALPHABET[timestamp_ms & 31]
        timestamp_ms >>= 5
    chars.extend(ULID_ALPHABET[random.SystemRandom().randrange(32)] for _ in range(16))
    return "".join(chars)


def envelope(message_type: str, session_id: str, payload: dict[str, Any]) -> bytes:
    message = {
        "v": PROTOCOL_VERSION,
        "type": message_type,
        "msg_id": ulid(),
        "session_id": session_id,
        "ts_server": utc_now(),
        "ts_sent": utc_now(),
        "payload": payload,
    }
    return (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")


@dataclass
class EchoGateway:
    token: str
    host: str = "127.0.0.1"
    port: int = 9101
    heartbeat_ack: bool = True
    event_log_path: str | None = None
    force_hello_reject: str | None = None
    close_on_accept: bool = False
    close_after_hello: bool = False
    stop_reading: bool = False
    sessions: set[str] = field(default_factory=set)
    server: asyncio.Server | None = None

    def log_event(self, event: str, **fields: Any) -> None:
        if self.event_log_path is None:
            return
        record = {
            "event": event,
            "wall_time": utc_now(),
            # Only compare monotonic values produced by the same server process.
            "monotonic": time.monotonic(),
            **fields,
        }
        with open(self.event_log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, separators=(",", ":")) + "\n")

    async def start(self) -> None:
        self.server = await asyncio.start_server(self.handle_client, self.host, self.port)

    async def stop(self) -> None:
        if self.server is None:
            return
        self.server.close()
        await self.server.wait_closed()

    async def handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        session_id = ""
        peer = writer.get_extra_info("peername")
        self.log_event("connect", peer=str(peer))
        if self.close_on_accept:
            self.log_event("close_on_accept", peer=str(peer))
            writer.close()
            await writer.wait_closed()
            return
        if self.stop_reading:
            self.log_event("stop_reading", peer=str(peer))
            await asyncio.Event().wait()
        try:
            while True:
                raw = await asyncio.wait_for(reader.readline(), timeout=30.0)
                if raw == b"":
                    self.log_event("client_closed", session_id=session_id)
                    return
                if len(raw) > MAX_FRAME_BYTES:
                    self.log_event("frame_too_large", session_id=session_id, size=len(raw))
                    writer.write(envelope("ERROR", session_id, {
                        "code": "PROTOCOL_FRAME_TOO_LARGE",
                        "severity": "ERROR",
                        "message": f"frame {len(raw)} bytes exceeds {MAX_FRAME_BYTES}",
                        "context": {},
                        "fatal": True,
                    }))
                    await writer.drain()
                    return

                try:
                    message = json.loads(raw.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue

                message_type = message.get("type")
                session_id = str(message.get("session_id") or session_id)
                self.log_event("message", session_id=session_id, type=str(message_type))
                payload = message.get("payload")
                if not isinstance(payload, dict):
                    payload = {}

                if message_type == "HELLO":
                    await self._handle_hello(writer, session_id, payload)
                    if self.close_after_hello:
                        self.log_event("close_after_hello", session_id=session_id)
                        return
                elif message_type == "HEARTBEAT" and self.heartbeat_ack:
                    seq = payload.get("seq", 0)
                    self.log_event("heartbeat", session_id=session_id, seq=seq, ack=True)
                    writer.write(envelope("HEARTBEAT_ACK", session_id, {
                        "seq": seq,
                        "server_time": utc_now(),
                        "brain_healthy": True,
                    }))
                    await writer.drain()
                else:
                    writer.write(raw if raw.endswith(b"\n") else raw + b"\n")
                    await writer.drain()
        finally:
            if session_id:
                self.sessions.discard(session_id)
            self.log_event("disconnect", session_id=session_id)
            writer.close()
            await writer.wait_closed()

    async def _handle_hello(
        self, writer: asyncio.StreamWriter, session_id: str, payload: dict[str, Any]
    ) -> None:
        accepted = True
        reason: str | None = None

        if self.force_hello_reject:
            accepted = False
            reason = self.force_hello_reject
        elif payload.get("token") != self.token:
            accepted = False
            reason = "BAD_TOKEN"
        elif session_id in self.sessions:
            accepted = False
            reason = "DUPLICATE_SESSION"

        if accepted:
            self.sessions.add(session_id)

        self.log_event("hello_ack", session_id=session_id, accepted=accepted, reason=reason)
        writer.write(envelope("HELLO_ACK", session_id, {
            "accepted": accepted,
            "server_time": utc_now(),
            "assigned_session_id": session_id,
            "brain_version": "1.0.0",
            "reject_reason": reason,
            "initial_directive": {"mode": "NORMAL", "scale_factor": 1.0},
        }))
        await writer.drain()


async def run_until_signal(gateway: EchoGateway) -> None:
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass
    await gateway.start()
    sockets = gateway.server.sockets if gateway.server is not None else []
    for sock in sockets or []:
        print(f"echo_server listening on {sock.getsockname()}", flush=True)
    await stop_event.wait()
    await gateway.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description="SPEC-001 JSON-lines echo gateway")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9101)
    parser.add_argument("--no-heartbeat-ack", action="store_true")
    parser.add_argument("--event-log")
    parser.add_argument("--force-hello-reject", choices=["BAD_TOKEN", "DUPLICATE_SESSION"])
    parser.add_argument("--close-on-accept", action="store_true")
    parser.add_argument("--close-after-hello", action="store_true")
    parser.add_argument("--stop-reading", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("FARM_TOKEN", "")
    if not token:
        raise SystemExit("FARM_TOKEN is required")

    gateway = EchoGateway(
        token=token,
        host=args.host,
        port=args.port,
        heartbeat_ack=not args.no_heartbeat_ack,
        event_log_path=args.event_log,
        force_hello_reject=args.force_hello_reject,
        close_on_accept=args.close_on_accept,
        close_after_hello=args.close_after_hello,
        stop_reading=args.stop_reading,
    )
    asyncio.run(run_until_signal(gateway))


if __name__ == "__main__":
    main()
