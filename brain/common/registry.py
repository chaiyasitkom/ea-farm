from __future__ import annotations

import json
import re
import warnings
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NoReturn, cast

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SYMBOLS_PATH = ROOT / "contracts" / "symbols.json"

_BROKER_RE = re.compile(r"^.{1,64}$")
_RAW_SYMBOL_RE = re.compile(r"^[A-Za-z0-9]{1,24}(\.[A-Za-z0-9]{1,8})?$")
_CANONICAL_RE = re.compile(r"^[A-Z]{6}$")
_CURRENCY_RE = re.compile(r"^[A-Z]{3}$")
_SESSION_POLICY_RE = re.compile(
    r"^(MON|TUE|WED|THU|FRI|SAT|SUN)_[0-2][0-9][0-5][0-9]_"
    r"(MON|TUE|WED|THU|FRI|SAT|SUN)_[0-2][0-9][0-5][0-9]$"
)
_CORRELATION_GROUPS = frozenset({"EUROPE", "JPY", "COMMODITY_FX", "METALS"})


class SymbolRegistryError(ValueError):
    pass


class UnknownSymbolError(SymbolRegistryError):
    pass


class SymbolRegistryValidationError(SymbolRegistryError):
    pass


@dataclass(frozen=True)
class RiskProfile:
    max_spread_points: int | None
    max_sl_distance_pct: float
    session_policy: str


@dataclass(frozen=True)
class CanonicalInfo:
    base: str
    quote: str
    group: str
    risk: RiskProfile


def _fail(message: str) -> NoReturn:
    raise SymbolRegistryValidationError(message)


def _object_pairs_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            _fail(f"duplicate key: {key}")
        out[key] = value
    return out


def load_symbol_registry_data(path: str | Path = DEFAULT_SYMBOLS_PATH) -> dict[str, Any]:
    raw = Path(path).read_text(encoding="utf-8")
    data = json.loads(raw, object_pairs_hook=_object_pairs_no_duplicates)
    if not isinstance(data, dict):
        _fail("registry root must be an object")
    return cast(dict[str, Any], data)


def validate_symbol_registry_data(data: Mapping[str, Any]) -> None:
    if set(data) != {"version", "brokers", "canonicals"}:
        _fail("registry must contain only version, brokers, and canonicals")
    if data["version"] != 1:
        _fail("registry version must be 1")
    brokers = data["brokers"]
    canonicals = data["canonicals"]
    if not isinstance(brokers, dict) or not brokers:
        _fail("brokers must be a non-empty object")
    if not isinstance(canonicals, dict) or not canonicals:
        _fail("canonicals must be a non-empty object")

    canonical_names = set[str]()
    for canonical, entry in canonicals.items():
        if not isinstance(canonical, str) or not _CANONICAL_RE.fullmatch(canonical):
            _fail(f"invalid canonical symbol: {canonical!r}")
        if not isinstance(entry, dict):
            _fail(f"canonical entry must be object: {canonical}")
        required = {
            "base",
            "quote",
            "group",
            "max_spread_points",
            "max_sl_distance_pct",
            "session_policy",
        }
        if set(entry) != required:
            _fail(f"canonical entry has invalid keys: {canonical}")
        base = entry["base"]
        quote = entry["quote"]
        if not isinstance(base, str) or not _CURRENCY_RE.fullmatch(base):
            _fail(f"invalid base for {canonical}")
        if not isinstance(quote, str) or not _CURRENCY_RE.fullmatch(quote):
            _fail(f"invalid quote for {canonical}")
        if base == quote:
            _fail(f"base must not equal quote for {canonical}")
        group = entry["group"]
        if not isinstance(group, str) or group not in _CORRELATION_GROUPS:
            _fail(f"invalid correlation group for {canonical}")
        spread = entry["max_spread_points"]
        if spread is not None and (
            not isinstance(spread, int) or isinstance(spread, bool) or spread < 1 or spread > 100000
        ):
            _fail(f"invalid max_spread_points for {canonical}")
        sl_distance = entry["max_sl_distance_pct"]
        if not isinstance(sl_distance, int | float) or isinstance(sl_distance, bool):
            _fail(f"invalid max_sl_distance_pct for {canonical}")
        if float(sl_distance) <= 0.0 or float(sl_distance) > 10.0:
            _fail(f"invalid max_sl_distance_pct for {canonical}")
        session_policy = entry["session_policy"]
        if not isinstance(session_policy, str) or not _SESSION_POLICY_RE.fullmatch(session_policy):
            _fail(f"invalid session_policy for {canonical}")
        canonical_names.add(canonical)

    referenced = set[str]()
    for broker, mapping in brokers.items():
        if not isinstance(broker, str) or not _BROKER_RE.fullmatch(broker):
            _fail(f"invalid broker name: {broker!r}")
        if not isinstance(mapping, dict) or not mapping:
            _fail(f"broker mapping must be non-empty object: {broker}")
        seen_canonicals = set[str]()
        for raw, canonical in mapping.items():
            if not isinstance(raw, str) or not _RAW_SYMBOL_RE.fullmatch(raw):
                _fail(f"invalid raw symbol for {broker}: {raw!r}")
            if not isinstance(canonical, str) or not _CANONICAL_RE.fullmatch(canonical):
                _fail(f"invalid canonical mapping for {broker}/{raw}")
            if canonical not in canonical_names:
                _fail(f"mapping references undefined canonical: {broker}/{raw}->{canonical}")
            if canonical in seen_canonicals:
                _fail(f"duplicate canonical mapping for broker {broker}: {canonical}")
            seen_canonicals.add(canonical)
            referenced.add(canonical)

    unused = sorted(canonical_names - referenced)
    if unused:
        warnings.warn(
            "canonical entries are not mapped by any broker: " + ", ".join(unused),
            stacklevel=2,
        )


class SymbolRegistry:
    def __init__(self, data: Mapping[str, Any]) -> None:
        validate_symbol_registry_data(data)
        brokers = cast(dict[str, dict[str, str]], data["brokers"])
        canonicals = cast(dict[str, dict[str, Any]], data["canonicals"])
        self._broker_to_canonical = {
            broker: dict(sorted(mapping.items())) for broker, mapping in sorted(brokers.items())
        }
        self._canonical_to_raw: dict[str, dict[str, str]] = {}
        for broker, mapping in self._broker_to_canonical.items():
            self._canonical_to_raw[broker] = {
                canonical: raw
                for raw, canonical in sorted(mapping.items(), key=lambda item: item[1])
            }
        self._canonicals = {
            canonical: CanonicalInfo(
                base=str(entry["base"]),
                quote=str(entry["quote"]),
                group=str(entry["group"]),
                risk=RiskProfile(
                    max_spread_points=cast(int | None, entry["max_spread_points"]),
                    max_sl_distance_pct=float(entry["max_sl_distance_pct"]),
                    session_policy=str(entry["session_policy"]),
                ),
            )
            for canonical, entry in sorted(canonicals.items())
        }

    @classmethod
    def load(cls, path: str | Path = DEFAULT_SYMBOLS_PATH) -> SymbolRegistry:
        return cls(load_symbol_registry_data(path))

    def to_canonical(self, broker: str, raw: str) -> str:
        try:
            return self._broker_to_canonical[broker][raw]
        except KeyError as exc:
            raise UnknownSymbolError(f"unknown symbol broker={broker!r} raw={raw!r}") from exc

    def to_raw(self, broker: str, canonical: str) -> str:
        try:
            return self._canonical_to_raw[broker][canonical]
        except KeyError as exc:
            raise UnknownSymbolError(
                f"unknown raw mapping broker={broker!r} canonical={canonical!r}"
            ) from exc

    def is_known(self, broker: str, raw: str) -> bool:
        return broker in self._broker_to_canonical and raw in self._broker_to_canonical[broker]

    def base_quote(self, canonical: str) -> tuple[str, str]:
        info = self._canonical_info(canonical)
        return info.base, info.quote

    def risk_profile(self, canonical: str) -> RiskProfile:
        return self._canonical_info(canonical).risk

    def correlation_group(self, canonical: str) -> str:
        return self._canonical_info(canonical).group

    def is_production_ready(self, canonical: str) -> bool:
        return self.risk_profile(canonical).max_spread_points is not None

    def brokers(self) -> list[str]:
        return sorted(self._broker_to_canonical)

    def canonicals(self) -> list[str]:
        return sorted(self._canonicals)

    def raws_for_broker(self, broker: str) -> list[str]:
        if broker not in self._broker_to_canonical:
            raise UnknownSymbolError(f"unknown broker={broker!r}")
        return sorted(self._broker_to_canonical[broker])

    def _canonical_info(self, canonical: str) -> CanonicalInfo:
        try:
            return self._canonicals[canonical]
        except KeyError as exc:
            raise UnknownSymbolError(f"unknown canonical={canonical!r}") from exc
