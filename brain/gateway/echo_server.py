from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

PROTOCOL_VERSION = 1
MAX_FRAME_BYTES = 64 * 1024


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def envelope(message_type: str, session_id: str, payload: dict[str, Any]) -> bytes:
    message = {
        "v": PROTOCOL_VERSION,
        "type": message_type,
        "msg_id": uuid.uuid4().hex[:26],
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
    sessions: set[str] = field(default_factory=set)
    server: asyncio.AbstractServer | None = None

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
        try:
            while True:
                raw = await asyncio.wait_for(reader.readline(), timeout=30.0)
                if raw == b"":
                    return
                if len(raw) > MAX_FRAME_BYTES:
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
                payload = message.get("payload")
                if not isinstance(payload, dict):
                    payload = {}

                if message_type == "HELLO":
                    await self._handle_hello(writer, session_id, payload)
                elif message_type == "HEARTBEAT" and self.heartbeat_ack:
                    writer.write(envelope("HEARTBEAT_ACK", session_id, {"ok": True}))
                    await writer.drain()
                else:
                    writer.write(raw if raw.endswith(b"\n") else raw + b"\n")
                    await writer.drain()
        finally:
            if session_id:
                self.sessions.discard(session_id)
            writer.close()
            await writer.wait_closed()

    async def _handle_hello(
        self, writer: asyncio.StreamWriter, session_id: str, payload: dict[str, Any]
    ) -> None:
        accepted = True
        reason: str | None = None

        if payload.get("token") != self.token:
            accepted = False
            reason = "BAD_TOKEN"
        elif session_id in self.sessions:
            accepted = False
            reason = "DUPLICATE_SESSION"

        if accepted:
            self.sessions.add(session_id)

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
    args = parser.parse_args()

    token = os.environ.get("FARM_TOKEN", "")
    if not token:
        raise SystemExit("FARM_TOKEN is required")

    gateway = EchoGateway(
        token=token,
        host=args.host,
        port=args.port,
        heartbeat_ack=not args.no_heartbeat_ack,
    )
    asyncio.run(run_until_signal(gateway))


if __name__ == "__main__":
    main()
