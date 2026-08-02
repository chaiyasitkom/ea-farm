from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from brain.common.registry import SymbolRegistry
from research.quality.checks import Bar, analyze_dataset
from research.quality.report import write_dataset_report

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BARS_DIR = ROOT / "data" / "bars"
DEFAULT_OUTPUT_DIR = ROOT / "data" / "quality"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--broker")
    parser.add_argument("--symbol")
    parser.add_argument("--bars-dir", type=Path, default=DEFAULT_BARS_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--fail-under-threshold", action="store_true")
    args = parser.parse_args(argv)

    if not args.all and (args.broker is None or args.symbol is None):
        parser.error("use --all or provide both --broker and --symbol")
    if args.all and (args.broker is not None or args.symbol is not None):
        parser.error("--all cannot be combined with --broker/--symbol")

    dataset = (
        _load_all(args.bars_dir)
        if args.all
        else _load_one(args.bars_dir, args.broker, args.symbol)
    )
    report = analyze_dataset(dataset)
    write_dataset_report(report, args.output_dir)
    if args.fail_under_threshold and not report.passed_threshold:
        return 1
    return 0


def _load_one(bars_dir: Path, broker: str, symbol: str) -> dict[tuple[str, str], list[Bar]]:
    return {(broker, symbol): _read_bars_for(bars_dir, broker, symbol)}


def _load_all(bars_dir: Path) -> dict[tuple[str, str], list[Bar]]:
    registry = SymbolRegistry.load()
    dataset: dict[tuple[str, str], list[Bar]] = {}
    for broker in registry.brokers():
        for symbol in registry.raws_for_broker(broker):
            bars = _read_bars_for(bars_dir, broker, symbol)
            if bars:
                dataset[(broker, symbol)] = bars
    if not dataset:
        raise SystemExit("quality input missing: no bars found under data/bars")
    return dataset


def _read_bars_for(bars_dir: Path, broker: str, symbol: str) -> list[Bar]:
    root = bars_dir / f"broker={broker}" / f"symbol={symbol}" / "tf=M1"
    if not root.exists():
        return []
    bars: list[Bar] = []
    for path in sorted(root.rglob("*")):
        if path.suffix == ".csv":
            bars.extend(_read_csv(path))
        elif path.suffix == ".jsonl":
            bars.extend(_read_jsonl(path))
    return bars


def _read_csv(path: Path) -> list[Bar]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return [_bar_from_mapping(row, path) for row in csv.DictReader(handle)]


def _read_jsonl(path: Path) -> list[Bar]:
    bars: list[Bar] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_number} JSONL row must be an object")
            bars.append(_bar_from_mapping(value, path))
    return bars


def _bar_from_mapping(row: dict[str, Any], path: Path) -> Bar:
    try:
        raw_timestamp = row.get("timestamp", row.get("time", row.get("bar_time")))
        if raw_timestamp is None:
            raise KeyError("timestamp")
        return Bar(
            timestamp=_parse_timestamp(str(raw_timestamp)),
            open=float(row["open"]),
            high=float(row["high"]),
            low=float(row["low"]),
            close=float(row["close"]),
            tick_volume=int(row.get("tick_volume", row.get("volume", 0))),
            spread=int(row.get("spread", row.get("spread_points", 0))),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"{path}: invalid bar row, missing or bad field: {exc}") from exc


def _parse_timestamp(value: str) -> datetime:
    parsed = value.removesuffix("Z")
    return datetime.fromisoformat(parsed)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
