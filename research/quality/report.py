from __future__ import annotations

import json
from dataclasses import asdict
from pathlib import Path
from typing import Any

from research.quality.checks import DatasetReport, GapRange, SymbolReport


def report_to_dict(report: SymbolReport) -> dict[str, Any]:
    return {
        "broker": report.broker,
        "symbol": report.symbol,
        "status": report.status,
        "checked_bars": report.checked_bars,
        "expected_bars": report.expected_bars,
        "missing_symbol_specific": report.missing_symbol_specific,
        "missing_market_wide": report.missing_market_wide,
        "missing_ambiguous": report.missing_ambiguous,
        "missing_pct": round(report.missing_pct, 8),
        "spike_count": report.spike_count,
        "spike_pct": round(report.spike_pct, 8),
        "passed_threshold": report.passed_threshold,
        "issues": [asdict(issue) for issue in sorted(report.issues, key=lambda item: item.code)],
        "bad_ranges": [_range_to_dict(item) for item in report.bad_ranges],
        "market_wide_ranges": [_range_to_dict(item) for item in report.market_wide_ranges],
        "ambiguous_ranges": [_range_to_dict(item) for item in report.ambiguous_ranges],
    }


def dataset_to_dict(dataset: DatasetReport) -> dict[str, Any]:
    return {
        "has_data": dataset.has_data,
        "passed_threshold": dataset.passed_threshold,
        "symbols": [report_to_dict(report) for report in dataset.symbols],
    }


def write_dataset_report(dataset: DatasetReport, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    bad_ranges: dict[str, list[dict[str, Any]]] = {}
    summary_lines: list[str] = []
    for report in dataset.symbols:
        key = f"{report.broker}/{report.symbol}"
        bad_ranges[key] = [_range_to_dict(item) for item in report.bad_ranges]
        path = output_dir / f"report-{_safe(report.broker)}-{_safe(report.symbol)}.json"
        _write_json(path, report_to_dict(report))
        summary_lines.append(
            (
                f"{key} status={report.status} bars={report.checked_bars} "
                f"missing_pct={report.missing_pct:.6f} "
                f"spike_pct={report.spike_pct:.6f} passed={report.passed_threshold}"
            )
        )
    _write_json(output_dir / "bad_ranges.json", bad_ranges)
    (output_dir / "summary.txt").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")


def _range_to_dict(item: GapRange) -> dict[str, Any]:
    return {
        "from": item.start.isoformat(timespec="seconds"),
        "to": item.end.isoformat(timespec="seconds"),
        "reason": item.reason,
        "missing_bars": item.missing_bars,
    }


def _write_json(path: Path, data: Any) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _safe(value: str) -> str:
    return "".join(char if char.isalnum() or char in ".-" else "_" for char in value)

