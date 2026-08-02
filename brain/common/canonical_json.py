from __future__ import annotations

import json
import math
from typing import Any


def dumps_canonical_json(
    data: Any, *, sort_keys: bool = False, trailing_newline: bool = False
) -> str:
    text = _encode(data, sort_keys=sort_keys)
    return text + "\n" if trailing_newline else text


def format_json_float(value: float) -> str:
    if not math.isfinite(value):
        raise ValueError(f"non-finite float is not valid JSON: {value!r}")
    if value == 0.0:
        return "0.0"
    text = f"{value:.10f}"
    if "." in text:
        text = text.rstrip("0")
        if text.endswith("."):
            text += "0"
    return text


def _encode(data: Any, *, sort_keys: bool) -> str:
    if data is None:
        return "null"
    if data is True:
        return "true"
    if data is False:
        return "false"
    if isinstance(data, int):
        return str(data)
    if isinstance(data, float):
        return format_json_float(data)
    if isinstance(data, str):
        return json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if isinstance(data, list):
        return "[" + ",".join(_encode(item, sort_keys=sort_keys) for item in data) + "]"
    if isinstance(data, dict):
        keys = sorted(data) if sort_keys else data.keys()
        return (
            "{"
            + ",".join(
                _encode(str(key), sort_keys=sort_keys)
                + ":"
                + _encode(data[key], sort_keys=sort_keys)
                for key in keys
            )
            + "}"
        )
    raise TypeError(f"unsupported JSON value: {type(data).__name__}")
