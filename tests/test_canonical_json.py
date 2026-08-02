from __future__ import annotations

import re

import pytest

from brain.common.canonical_json import dumps_canonical_json


def _raw_numbers(raw: str) -> list[str]:
    pattern = r"(?<![A-Za-z0-9_])[-]?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
    return re.findall(pattern, raw)


def test_json_number_format_matches_wire_contract() -> None:
    raw = dumps_canonical_json(
        {
            "small": 0.00001,
            "large": 1e20,
            "double_int": 100000.0,
            "integer": 100000,
            "one": 1.0,
            "negative_zero": -0.0,
        },
        sort_keys=True,
    )
    assert raw == (
        '{"double_int":100000.0,"integer":100000,'
        '"large":100000000000000000000.0,"negative_zero":0.0,'
        '"one":1.0,"small":0.00001}'
    )
    assert not [number for number in _raw_numbers(raw) if "e" in number.lower()]


def test_json_rejects_non_finite_float() -> None:
    with pytest.raises(ValueError, match="non-finite"):
        dumps_canonical_json({"bad": float("nan")})
