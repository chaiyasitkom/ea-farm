from __future__ import annotations

import math
from bisect import bisect_left, insort
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Iterable

from brain.common.registry import SymbolRegistry
from research.quality.profile import MIN_PROFILE_DAYS, SessionProfile, build_session_profile

GAP_FAIL_THRESHOLD_PCT = 0.1
SPIKE_FAIL_THRESHOLD_PCT = 0.01
MARKET_WIDE_MIN_SYMBOLS = 4
SPIKE_WINDOW = 1440


@dataclass(frozen=True)
class Bar:
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    tick_volume: int
    spread: int


@dataclass(frozen=True)
class Issue:
    code: str
    severity: str
    count: int
    detail: str


@dataclass(frozen=True)
class GapRange:
    start: datetime
    end: datetime
    reason: str
    missing_bars: int


@dataclass
class SymbolReport:
    broker: str
    symbol: str
    status: str
    checked_bars: int
    expected_bars: int = 0
    missing_symbol_specific: int = 0
    missing_market_wide: int = 0
    missing_ambiguous: int = 0
    spike_count: int = 0
    issues: list[Issue] = field(default_factory=list)
    bad_ranges: list[GapRange] = field(default_factory=list)
    market_wide_ranges: list[GapRange] = field(default_factory=list)
    ambiguous_ranges: list[GapRange] = field(default_factory=list)
    missing_candidates: set[datetime] = field(default_factory=set, repr=False)
    ambiguous_candidates: set[datetime] = field(default_factory=set, repr=False)
    profile: SessionProfile | None = field(default=None, repr=False)

    @property
    def missing_pct(self) -> float:
        if self.expected_bars == 0:
            return 0.0
        return self.missing_symbol_specific * 100.0 / self.expected_bars

    @property
    def spike_pct(self) -> float:
        if self.checked_bars == 0:
            return 0.0
        return self.spike_count * 100.0 / self.checked_bars

    @property
    def passed_threshold(self) -> bool:
        if any(issue.severity == "FAIL" for issue in self.issues):
            return False
        if self.missing_pct >= GAP_FAIL_THRESHOLD_PCT:
            return False
        return self.spike_pct < SPIKE_FAIL_THRESHOLD_PCT


@dataclass(frozen=True)
class DatasetReport:
    symbols: list[SymbolReport]

    @property
    def has_data(self) -> bool:
        return any(report.checked_bars > 0 for report in self.symbols)

    @property
    def passed_threshold(self) -> bool:
        return self.has_data and all(report.passed_threshold for report in self.symbols)


def analyze_symbol(broker: str, symbol: str, bars: Iterable[Bar]) -> SymbolReport:
    ordered_input = list(bars)
    report = SymbolReport(
        broker=broker,
        symbol=symbol,
        status="ok" if ordered_input else "no_data",
        checked_bars=len(ordered_input),
    )
    if not ordered_input:
        return report

    _check_invariants(ordered_input, report)
    sorted_bars = sorted(ordered_input, key=lambda bar: bar.timestamp)
    _check_volume_and_spread(sorted_bars, report)
    report.spike_count = _count_spikes(sorted_bars)
    if report.spike_pct >= SPIKE_FAIL_THRESHOLD_PCT:
        report.issues.append(
            Issue("SPIKE_THRESHOLD", "FAIL", report.spike_count, "spike rate exceeds 0.01%")
        )

    profile = build_session_profile([bar.timestamp for bar in sorted_bars])
    report.profile = profile
    if profile is None:
        report.issues.append(
            Issue(
                "GAP_CHECK_SKIPPED_SHORT_HISTORY",
                "WARN",
                len(sorted_bars),
                f"history is shorter than {MIN_PROFILE_DAYS} days",
            )
        )
        return report

    present = {bar.timestamp.replace(second=0, microsecond=0) for bar in sorted_bars}
    current = profile.first
    while current <= profile.last:
        state = profile.state_for(current)
        if state == "traded":
            report.expected_bars += 1
            if current not in present:
                report.missing_candidates.add(current)
        elif state == "ambiguous" and current not in present:
            report.ambiguous_candidates.add(current)
        current += timedelta(minutes=1)
    report.missing_ambiguous = len(report.ambiguous_candidates)
    report.ambiguous_ranges = _ranges(report.ambiguous_candidates, "GAP_AMBIGUOUS")
    if report.missing_ambiguous:
        report.issues.append(
            Issue(
                "GAP_AMBIGUOUS",
                "WARN",
                report.missing_ambiguous,
                "missing bars in ambiguous session-profile slots",
            )
        )
    return report


def analyze_dataset(dataset: dict[tuple[str, str], list[Bar]]) -> DatasetReport:
    reports = [
        analyze_symbol(broker, symbol, bars)
        for (broker, symbol), bars in sorted(dataset.items(), key=lambda item: item[0])
    ]
    _classify_market_wide_gaps(reports)
    _check_cross_broker_prices(reports, dataset)
    for report in reports:
        report.bad_ranges = _ranges(report.missing_candidates, "GAP_SYMBOL_SPECIFIC")
        report.missing_symbol_specific = sum(item.missing_bars for item in report.bad_ranges)
        report.missing_market_wide = sum(item.missing_bars for item in report.market_wide_ranges)
        if report.missing_pct >= GAP_FAIL_THRESHOLD_PCT:
            report.issues.append(
                Issue(
                    "GAP_SYMBOL_SPECIFIC_THRESHOLD",
                    "FAIL",
                    report.missing_symbol_specific,
                    "symbol-specific missing bars exceed 0.1%",
                )
            )
        if report.missing_market_wide:
            report.issues.append(
                Issue(
                    "GAP_MARKET_WIDE",
                    "WARN",
                    report.missing_market_wide,
                    "missing bars are shared across the market",
                )
            )
    return DatasetReport(symbols=reports)


def _check_invariants(bars: list[Bar], report: SymbolReport) -> None:
    seen: set[datetime] = set()
    duplicate = 0
    unsorted = 0
    off_grid = 0
    nonpositive = 0
    ohlc = 0
    negative_spread = 0
    previous: datetime | None = None
    for bar in bars:
        if bar.timestamp in seen:
            duplicate += 1
        seen.add(bar.timestamp)
        if previous is not None and bar.timestamp < previous:
            unsorted += 1
        previous = bar.timestamp
        if bar.timestamp.second != 0 or bar.timestamp.microsecond != 0:
            off_grid += 1
        if min(bar.open, bar.high, bar.low, bar.close) <= 0.0:
            nonpositive += 1
        if bar.low > min(bar.open, bar.close) or bar.high < max(bar.open, bar.close):
            ohlc += 1
        if bar.low > bar.high:
            ohlc += 1
        if bar.spread < 0:
            negative_spread += 1

    _fail_issue(report, "OHLC_VIOLATION", ohlc)
    _fail_issue(report, "NONPOSITIVE_PRICE", nonpositive)
    _fail_issue(report, "DUPLICATE_TIMESTAMP", duplicate)
    _fail_issue(report, "UNSORTED_TIMESTAMP", unsorted)
    _fail_issue(report, "OFF_GRID_TIMESTAMP", off_grid)
    _fail_issue(report, "NEGATIVE_SPREAD", negative_spread)


def _check_volume_and_spread(bars: list[Bar], report: SymbolReport) -> None:
    zero_volume_moving = sum(
        1 for bar in bars if bar.tick_volume == 0 and not math.isclose(bar.high, bar.low)
    )
    if zero_volume_moving == len(bars):
        report.issues.append(
            Issue(
                "TICK_VOLUME_ALL_ZERO",
                "WARN",
                1,
                "all bars have zero tick volume; broker may not provide volume",
            )
        )
    elif zero_volume_moving * 100.0 / len(bars) >= 0.1:
        report.issues.append(
            Issue(
                "TICK_VOLUME_ZERO_WITH_RANGE",
                "WARN",
                zero_volume_moving,
                "zero tick volume on moving bars exceeds 0.1%",
            )
        )

    spreads = sorted(bar.spread for bar in bars if bar.spread >= 0)
    if len(spreads) >= 1000:
        index = min(len(spreads) - 1, math.ceil(len(spreads) * 0.999) - 1)
        limit = spreads[index] * 5
        high_spreads = sum(1 for spread in spreads if spread > limit)
        if high_spreads:
            report.issues.append(
                Issue("SPREAD_HIGH_OUTLIER", "WARN", high_spreads, "spread exceeds p99.9 x 5")
            )


def _count_spikes(bars: list[Bar]) -> int:
    returns: list[float] = []
    sorted_abs_returns: list[float] = []
    spikes = 0
    previous_close: float | None = None
    for bar in bars:
        if previous_close is None:
            previous_close = bar.close
            continue
        current_return = math.log(bar.close / previous_close)
        if sorted_abs_returns:
            mad = _median_sorted(sorted_abs_returns)
            if mad > 0.0 and abs(current_return) > 20.0 * mad:
                spikes += 1
        returns.append(current_return)
        insort(sorted_abs_returns, abs(current_return))
        if len(returns) > SPIKE_WINDOW:
            old_abs = abs(returns[-SPIKE_WINDOW - 1])
            old_index = bisect_left(sorted_abs_returns, old_abs)
            del sorted_abs_returns[old_index]
        previous_close = bar.close
    return spikes


def _median_sorted(values: list[float]) -> float:
    middle = len(values) // 2
    if len(values) % 2:
        return values[middle]
    return (values[middle - 1] + values[middle]) / 2.0


def _classify_market_wide_gaps(reports: list[SymbolReport]) -> None:
    by_broker: dict[str, list[SymbolReport]] = defaultdict(list)
    for report in reports:
        if report.missing_candidates:
            by_broker[report.broker].append(report)

    for broker_reports in by_broker.values():
        threshold = (
            MARKET_WIDE_MIN_SYMBOLS
            if len(broker_reports) >= MARKET_WIDE_MIN_SYMBOLS
            else len(broker_reports)
        )
        if threshold < 2:
            continue
        counts: defaultdict[datetime, int] = defaultdict(int)
        for report in broker_reports:
            for timestamp in report.missing_candidates:
                counts[timestamp] += 1
        market_wide = {
            timestamp for timestamp, count in counts.items() if count >= threshold
        }
        for report in broker_reports:
            shared = report.missing_candidates & market_wide
            if shared:
                report.market_wide_ranges = _ranges(shared, "GAP_MARKET_WIDE")
                report.missing_candidates -= shared


def _check_cross_broker_prices(
    reports: list[SymbolReport],
    dataset: dict[tuple[str, str], list[Bar]],
) -> None:
    by_key = {(report.broker, report.symbol): report for report in reports}
    registry = SymbolRegistry.load()
    latest_by_canonical: defaultdict[str, list[tuple[str, str, datetime, float]]]
    latest_by_canonical = defaultdict(list)
    for (broker, symbol), bars in sorted(dataset.items()):
        if not bars:
            continue
        if not registry.is_known(broker, symbol):
            by_key[(broker, symbol)].issues.append(
                Issue(
                    "CROSS_BROKER_CHECK_SKIPPED_UNKNOWN_SYMBOL",
                    "WARN",
                    1,
                    "symbol is not in registry",
                )
            )
            continue
        canonical = registry.to_canonical(broker, symbol)
        latest = max(bars, key=lambda bar: bar.timestamp)
        latest_by_canonical[canonical].append((broker, symbol, latest.timestamp, latest.close))

    for entries in latest_by_canonical.values():
        if len({broker for broker, _symbol, _timestamp, _close in entries}) < 2:
            continue
        closes = [close for _broker, _symbol, _timestamp, close in entries]
        low = min(closes)
        high = max(closes)
        if low <= 0.0:
            continue
        divergence_pct = (high - low) * 100.0 / low
        if divergence_pct > 0.5:
            for broker, symbol, _timestamp, _close in entries:
                by_key[(broker, symbol)].issues.append(
                    Issue(
                        "CROSS_BROKER_PRICE_DIVERGENCE",
                        "WARN",
                        1,
                        f"canonical price divergence is {divergence_pct:.6f}%",
                    )
                )


def _fail_issue(report: SymbolReport, code: str, count: int) -> None:
    if count:
        report.issues.append(Issue(code, "FAIL", count, f"{code} count is non-zero"))


def _ranges(timestamps: set[datetime], reason: str) -> list[GapRange]:
    if not timestamps:
        return []
    ordered = sorted(timestamps)
    ranges: list[GapRange] = []
    start = ordered[0]
    previous = ordered[0]
    count = 1
    for timestamp in ordered[1:]:
        if timestamp == previous + timedelta(minutes=1):
            previous = timestamp
            count += 1
            continue
        ranges.append(GapRange(start=start, end=previous, reason=reason, missing_bars=count))
        start = timestamp
        previous = timestamp
        count = 1
    ranges.append(GapRange(start=start, end=previous, reason=reason, missing_bars=count))
    return ranges
