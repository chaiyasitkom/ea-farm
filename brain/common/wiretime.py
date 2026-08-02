from __future__ import annotations

from datetime import UTC, datetime


def parse_utc(value: str) -> datetime:
    if not value.endswith("Z"):
        raise ValueError("wire timestamp must end with Z")
    parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    if parsed.tzinfo != UTC:
        parsed = parsed.astimezone(UTC)
    return parsed


def format_utc(value: datetime) -> str:
    if value.tzinfo is None:
        raise ValueError("wire timestamp must be timezone-aware")
    utc_value = value.astimezone(UTC)
    text = utc_value.isoformat(timespec="milliseconds").replace("+00:00", "Z")
    return text.replace(".000Z", "Z")
