from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta
from pathlib import Path

from research.quality.__main__ import main as quality_main
from research.quality.checks import Bar, SymbolReport, analyze_dataset, analyze_symbol
from research.quality.report import dataset_to_dict, write_dataset_report


def _bars(
    start: datetime,
    count: int,
    *,
    base: float = 1.1050,
    step: float = 0.00001,
    symbol: str = "EURUSD",
    skip: set[datetime] | None = None,
    daily_break: range | None = None,
    weekdays_only: bool = False,
) -> list[Bar]:
    out: list[Bar] = []
    skip = skip or set()
    current = start
    while len(out) < count:
        minute = current.hour * 60 + current.minute
        closed = current in skip
        if daily_break is not None and minute in daily_break:
            closed = True
        if weekdays_only and current.weekday() >= 5:
            closed = True
        if not closed:
            index = len(out)
            drift = index * step
            price = base + drift
            spread = 12 if symbol != "XAUUSD" else 35
            out.append(
                Bar(
                    timestamp=current,
                    open=price,
                    high=price + 3 * step,
                    low=price - 2 * step,
                    close=price + step,
                    tick_volume=120 + index % 30,
                    spread=spread,
                )
            )
        current += timedelta(minutes=1)
    return out


def _calendar_bars(
    start: datetime,
    days: int,
    *,
    base: float = 1.1050,
    symbol: str = "EURUSD",
    skip: set[datetime] | None = None,
    daily_break: range | None = None,
    weekdays_only: bool = False,
) -> list[Bar]:
    minutes = days * 24 * 60
    skip = skip or set()
    bars: list[Bar] = []
    current = start
    for offset in range(minutes):
        minute = current.hour * 60 + current.minute
        if current not in skip:
            if daily_break is None or minute not in daily_break:
                if not weekdays_only or current.weekday() < 5:
                    price = base + (offset % 300) * 0.00001
                    price = base + offset * 0.00000001
                    if symbol == "XAUUSD":
                        price = 2100.0 + offset * 0.001
                    bars.append(
                        Bar(
                            timestamp=current,
                            open=price,
                            high=price + (0.00003 if symbol != "XAUUSD" else 0.3),
                            low=price - (0.00002 if symbol != "XAUUSD" else 0.2),
                            close=price + (0.00001 if symbol != "XAUUSD" else 0.1),
                            tick_volume=100 + offset % 50,
                            spread=10 if symbol != "XAUUSD" else 40,
                        )
                    )
        current += timedelta(minutes=1)
    return bars


def _issue_codes(report: SymbolReport) -> set[str]:
    return {issue.code for issue in report.issues}


def test_detects_ohlc_violation() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bars[3] = Bar(bars[3].timestamp, 1.10, 1.09, 1.11, 1.10, 100, 10)

    report = analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)

    assert "OHLC_VIOLATION" in _issue_codes(report)
    assert not report.passed_threshold


def test_detects_nonpositive_price() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bars[1] = Bar(bars[1].timestamp, 1.10, 1.11, 0.0, 1.10, 100, 10)

    assert "NONPOSITIVE_PRICE" in _issue_codes(
        analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)
    )


def test_detects_duplicate_timestamp() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bars[5] = Bar(bars[4].timestamp, 1.10, 1.11, 1.09, 1.10, 100, 10)

    assert "DUPLICATE_TIMESTAMP" in _issue_codes(
        analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)
    )


def test_detects_unsorted_timestamps() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bars[3], bars[4] = bars[4], bars[3]

    assert "UNSORTED_TIMESTAMP" in _issue_codes(
        analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)
    )


def test_detects_off_grid_timestamp() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bad = bars[2]
    bars[2] = Bar(bad.timestamp.replace(second=17), bad.open, bad.high, bad.low, bad.close, 100, 10)

    assert "OFF_GRID_TIMESTAMP" in _issue_codes(
        analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)
    )


def test_detects_negative_spread() -> None:
    bars = _bars(datetime(2026, 1, 5), 10)
    bad = bars[2]
    bars[2] = Bar(bad.timestamp, bad.open, bad.high, bad.low, bad.close, 100, -1)

    assert "NEGATIVE_SPREAD" in _issue_codes(
        analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)
    )


def test_profile_learns_daily_break() -> None:
    break_minutes = range(22 * 60, 23 * 60)
    report = analyze_symbol(
        "IUXMarkets-Demo",
        "XAUUSD.iux",
        _calendar_bars(datetime(2026, 1, 5), 35, symbol="XAUUSD", daily_break=break_minutes),
    )

    assert report.profile is not None
    assert report.profile.state_for(datetime(2026, 1, 5, 22, 15)) == "closed"
    assert report.profile.state_for(datetime(2026, 1, 5, 21, 15)) == "traded"


def test_profile_learns_weekend() -> None:
    report = analyze_symbol(
        "IUXMarkets-Demo",
        "EURUSD.iux",
        _calendar_bars(datetime(2026, 1, 5), 35, weekdays_only=True),
    )

    assert report.profile is not None
    assert report.profile.state_for(datetime(2026, 1, 10, 12, 0)) == "closed"
    assert report.profile.state_for(datetime(2026, 1, 7, 12, 0)) == "traded"


def test_gap_in_traded_session_is_counted() -> None:
    missing = {datetime(2026, 1, 12, 10, minute) for minute in range(30)}
    report = analyze_dataset(
        {("IUXMarkets-Demo", "EURUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 91, skip=missing)}
    ).symbols[0]

    assert report.missing_symbol_specific == 30
    assert report.bad_ranges[0].reason == "GAP_SYMBOL_SPECIFIC"


def test_gap_in_closed_session_is_not_counted() -> None:
    break_minutes = range(22 * 60, 23 * 60)
    missing = {datetime(2026, 1, 12, 22, minute) for minute in range(30)}
    report = analyze_dataset(
        {
            ("IUXMarkets-Demo", "XAUUSD.iux"): _calendar_bars(
                datetime(2026, 1, 5),
                35,
                symbol="XAUUSD",
                skip=missing,
                daily_break=break_minutes,
            )
        }
    ).symbols[0]

    assert report.missing_symbol_specific == 0
    assert report.bad_ranges == []


def test_ambiguous_band_reported_separately() -> None:
    start = datetime(2026, 1, 5)
    partial_holiday_minutes = {
        datetime(2026, 1, day, 3, minute)
        for day in (5, 12)
        for minute in range(60)
    }
    bars = _calendar_bars(start, 35, skip=partial_holiday_minutes)

    report = analyze_dataset({("IUXMarkets-Demo", "EURUSD.iux"): bars}).symbols[0]

    assert report.missing_ambiguous > 0
    assert "GAP_AMBIGUOUS" in _issue_codes(report)
    assert report.missing_symbol_specific == 0


def test_market_wide_gap_not_counted_as_failure() -> None:
    missing = {datetime(2026, 1, 12, 10, minute) for minute in range(20)}
    dataset = {
        ("IUXMarkets-Demo", "EURUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 91, skip=missing),
        ("IUXMarkets-Demo", "GBPUSD.iux"): _calendar_bars(
            datetime(2026, 1, 5),
            91,
            base=1.2750,
            skip=missing,
        ),
    }

    report = analyze_dataset(dataset).symbols[0]

    assert report.missing_market_wide == 20
    assert report.missing_symbol_specific == 0
    assert "GAP_MARKET_WIDE" in _issue_codes(report)


def test_symbol_specific_gap_counted_as_failure() -> None:
    missing = {datetime(2026, 1, 12, hour, minute) for hour in range(6) for minute in range(60)}
    dataset = {
        ("IUXMarkets-Demo", "EURUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 91, skip=missing),
        ("IUXMarkets-Demo", "GBPUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 91, base=1.2750),
    }

    report = analyze_dataset(dataset).symbols[0]

    assert report.missing_pct >= 0.1
    assert "GAP_SYMBOL_SPECIFIC_THRESHOLD" in _issue_codes(report)
    assert not report.passed_threshold


def test_spike_uses_mad_not_stddev() -> None:
    start = datetime(2026, 1, 5)
    bars = _bars(start, 1600, base=1.1000, step=0.000001)
    big = bars[1500]
    second = bars[1501]
    bars[1500] = Bar(big.timestamp, 1.1000, 1.1800, 1.0990, 1.1700, 200, 12)
    bars[1501] = Bar(second.timestamp, 1.1700, 1.1760, 1.1690, 1.1750, 200, 12)

    report = analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)

    assert report.spike_count >= 2
    assert "SPIKE_THRESHOLD" in _issue_codes(report)


def test_spike_skipped_when_mad_zero() -> None:
    bars = [
        Bar(datetime(2026, 1, 5) + timedelta(minutes=i), 1.1, 1.1, 1.1, 1.1, 100, 10)
        for i in range(1500)
    ]
    bars.append(Bar(datetime(2026, 1, 6, 1), 1.1, 1.2, 1.1, 1.2, 100, 10))

    report = analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", bars)

    assert report.spike_count == 0


def test_expected_bars_excludes_before_first_and_after_last() -> None:
    bars = _calendar_bars(datetime(2026, 1, 5), 35)
    report = analyze_dataset({("IUXMarkets-Demo", "EURUSD.iux"): bars}).symbols[0]

    assert report.expected_bars == len(bars)
    assert report.missing_symbol_specific == 0


def test_short_history_skips_gap_check_with_warning() -> None:
    report = analyze_symbol(
        "IUXMarkets-Demo",
        "EURUSD.iux",
        _calendar_bars(datetime(2026, 1, 5), 7),
    )

    assert "GAP_CHECK_SKIPPED_SHORT_HISTORY" in _issue_codes(report)
    assert report.expected_bars == 0


def test_no_data_is_not_failure() -> None:
    report = analyze_symbol("IUXMarkets-Demo", "EURUSD.iux", [])
    dataset_report = analyze_dataset({("IUXMarkets-Demo", "EURUSD.iux"): []})

    assert report.status == "no_data"
    assert report.passed_threshold
    assert report.missing_pct == 0.0
    assert not dataset_report.passed_threshold


def test_report_is_deterministic(tmp_path: Path) -> None:
    dataset = analyze_dataset(
        {("IUXMarkets-Demo", "EURUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 35)}
    )
    write_dataset_report(dataset, tmp_path / "a")
    write_dataset_report(dataset, tmp_path / "b")

    assert (tmp_path / "a" / "report-IUXMarkets-Demo-EURUSD.iux.json").read_bytes() == (
        tmp_path / "b" / "report-IUXMarkets-Demo-EURUSD.iux.json"
    ).read_bytes()
    assert dataset_to_dict(dataset) == dataset_to_dict(dataset)


def test_source_files_unchanged_after_run(tmp_path: Path) -> None:
    source = (
        tmp_path
        / "bars"
        / "broker=IUXMarkets-Demo"
        / "symbol=EURUSD.iux"
        / "tf=M1"
        / "year=2026"
    )
    source.mkdir(parents=True)
    csv_path = source / "part.csv"
    csv_path.write_text(
        "timestamp,open,high,low,close,tick_volume,spread\n"
        "2026-01-05T00:00:00,1.1050,1.1053,1.1048,1.1051,120,10\n",
        encoding="utf-8",
    )
    before = hashlib.sha256(csv_path.read_bytes()).hexdigest()

    code = quality_main(
        [
            "--broker",
            "IUXMarkets-Demo",
            "--symbol",
            "EURUSD.iux",
            "--bars-dir",
            str(tmp_path / "bars"),
            "--output-dir",
            str(tmp_path / "quality"),
        ]
    )

    assert code == 0
    assert hashlib.sha256(csv_path.read_bytes()).hexdigest() == before


def test_exit_code_reflects_threshold(tmp_path: Path) -> None:
    source = (
        tmp_path
        / "bars"
        / "broker=IUXMarkets-Demo"
        / "symbol=EURUSD.iux"
        / "tf=M1"
        / "year=2026"
    )
    source.mkdir(parents=True)
    rows = [
        "timestamp,open,high,low,close,tick_volume,spread",
        "2026-01-05T00:00:00,1.1050,1.1053,1.1048,1.1051,120,10",
    ]
    (source / "part.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")

    code = quality_main(
        [
            "--broker",
            "IUXMarkets-Demo",
            "--symbol",
            "EURUSD.iux",
            "--bars-dir",
            str(tmp_path / "bars"),
            "--output-dir",
            str(tmp_path / "quality"),
            "--fail-under-threshold",
        ]
    )

    assert code == 0
    assert json.loads((tmp_path / "quality" / "bad_ranges.json").read_text(encoding="utf-8"))


def test_cross_broker_check_skipped_with_one_broker() -> None:
    report = analyze_dataset(
        {("IUXMarkets-Demo", "EURUSD.iux"): _calendar_bars(datetime(2026, 1, 5), 35)}
    ).symbols[0]

    assert "CROSS_BROKER_PRICE_DIVERGENCE" not in _issue_codes(report)
    assert report.passed_threshold
