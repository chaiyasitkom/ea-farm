from __future__ import annotations

import argparse
import importlib
import json
import math
import time
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

SAMPLE_INTERVAL_SEC = 30
WARMUP_SEC = 3600
MB = 1024 * 1024

MAX_PRIVATE_SLOPE_MB_PER_HOUR = 1.0
MAX_PRIVATE_GROWTH_MB = 24.0
MAX_HANDLE_GROWTH = 50
MAX_THREAD_GROWTH = 4
MIN_SAMPLE_COVERAGE = 0.90
MAX_GAP_FACTOR = 1.5


class SoakEnvironmentError(RuntimeError):
    """The soak environment cannot produce a trustworthy verdict."""


@dataclass(frozen=True)
class Sample:
    monotonic: float
    wall_utc: str
    pid: int
    rss_bytes: int
    private_bytes: int
    num_handles: int
    num_threads: int
    mql5_memory_used_mb: int | None


@dataclass(frozen=True)
class Verdict:
    passed: bool
    reason: str
    private_slope_mb_per_hour: float
    private_growth_mb: float
    handle_growth: int
    thread_growth: int
    samples_used: int
    gaps_detected: list[tuple[str, float]]


def linear_slope(xs: list[float], ys: list[float]) -> float:
    if len(xs) != len(ys):
        raise ValueError("xs and ys must have the same length")
    if len(xs) < 2:
        raise ValueError("at least two points are required")
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    denominator = sum((x - x_mean) ** 2 for x in xs)
    if denominator == 0:
        raise ValueError("xs must not all be equal")
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys, strict=True))
    return numerator / denominator


def _sample_from_dict(raw: dict[str, Any]) -> Sample:
    return Sample(
        monotonic=float(raw["monotonic"]),
        wall_utc=str(raw["wall_utc"]),
        pid=int(raw["pid"]),
        rss_bytes=int(raw["rss_bytes"]),
        private_bytes=int(raw["private_bytes"]),
        num_handles=int(raw["num_handles"]),
        num_threads=int(raw["num_threads"]),
        mql5_memory_used_mb=(
            None if raw.get("mql5_memory_used_mb") is None else int(raw["mql5_memory_used_mb"])
        ),
    )


def load_samples(path: Path) -> list[Sample]:
    samples: list[Sample] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        raw = json.loads(line)
        if not isinstance(raw, dict):
            raise ValueError(f"{path}:{line_number}: sample must be a JSON object")
        samples.append(_sample_from_dict(raw))
    return samples


def _post_warmup_samples(samples: list[Sample]) -> list[Sample]:
    if not samples:
        raise SoakEnvironmentError("no samples collected")
    sorted_samples = sorted(samples, key=lambda sample: sample.monotonic)
    pids = {sample.pid for sample in sorted_samples}
    if len(pids) != 1:
        raise SoakEnvironmentError(f"pid changed during soak: {sorted(pids)}")
    warmup_end = sorted_samples[0].monotonic + WARMUP_SEC
    used = [sample for sample in sorted_samples if sample.monotonic >= warmup_end]
    if len(used) < 2:
        raise SoakEnvironmentError("fewer than two samples after warmup")
    return used


def _detect_gaps(samples: list[Sample]) -> list[tuple[str, float]]:
    gaps: list[tuple[str, float]] = []
    for previous, current in zip(samples, samples[1:], strict=False):
        gap = current.monotonic - previous.monotonic
        if gap > SAMPLE_INTERVAL_SEC * MAX_GAP_FACTOR:
            gaps.append((current.wall_utc, gap))
    return gaps


def analyse(samples: list[Sample]) -> Verdict:
    used = _post_warmup_samples(samples)
    baseline = used[0]
    final = used[-1]
    elapsed = final.monotonic - baseline.monotonic
    if elapsed <= 0:
        raise SoakEnvironmentError("post-warmup samples have no elapsed time")

    private_slope_bytes_per_sec = linear_slope(
        [sample.monotonic for sample in used],
        [float(sample.private_bytes) for sample in used],
    )
    private_slope_mb_per_hour = private_slope_bytes_per_sec * 3600 / MB
    private_growth_mb = (final.private_bytes - baseline.private_bytes) / MB
    handle_growth = final.num_handles - baseline.num_handles
    thread_growth = final.num_threads - baseline.num_threads
    gaps = _detect_gaps(used)
    expected_samples = int(math.floor(elapsed / SAMPLE_INTERVAL_SEC)) + 1
    coverage = len(used) / expected_samples if expected_samples > 0 else 0.0

    failures: list[str] = []
    if private_slope_mb_per_hour > MAX_PRIVATE_SLOPE_MB_PER_HOUR:
        failures.append(
            f"M1 private_slope_mb_per_hour={private_slope_mb_per_hour:.3f} "
            f"> {MAX_PRIVATE_SLOPE_MB_PER_HOUR:.3f}"
        )
    if private_growth_mb > MAX_PRIVATE_GROWTH_MB:
        failures.append(
            f"M2 private_growth_mb={private_growth_mb:.3f} > {MAX_PRIVATE_GROWTH_MB:.3f}"
        )
    if handle_growth > MAX_HANDLE_GROWTH:
        failures.append(f"M3 handle_growth={handle_growth} > {MAX_HANDLE_GROWTH}")
    if thread_growth > MAX_THREAD_GROWTH:
        failures.append(f"M4 thread_growth={thread_growth} > {MAX_THREAD_GROWTH}")
    if coverage < MIN_SAMPLE_COVERAGE:
        failures.append(f"M5 samples_used={len(used)}/{expected_samples} coverage={coverage:.3f}")
    if gaps:
        max_gap = max(gap for _, gap in gaps)
        failures.append(f"M5 gaps_detected={len(gaps)} max_gap_sec={max_gap:.3f}")

    return Verdict(
        passed=not failures,
        reason="; ".join(failures),
        private_slope_mb_per_hour=private_slope_mb_per_hour,
        private_growth_mb=private_growth_mb,
        handle_growth=handle_growth,
        thread_growth=thread_growth,
        samples_used=len(used),
        gaps_detected=gaps,
    )


def _private_bytes(process: Any) -> int:
    info = process.memory_full_info()
    private = getattr(info, "private", None)
    if private is None:
        raise SoakEnvironmentError("psutil did not expose private bytes for this process")
    return int(private)


def _num_handles(process: Any) -> int:
    try:
        return int(process.num_handles())
    except AttributeError as exc:
        raise SoakEnvironmentError("psutil did not expose num_handles for this process") from exc


def _utc_now_z() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def collect(pid: int, duration_sec: float, out_path: Path) -> Path:
    try:
        psutil = cast(Any, importlib.import_module("psutil"))
    except ImportError as exc:
        raise SoakEnvironmentError(
            "psutil is required for soak sampling; install dev dependencies with "
            "`python -m pip install -e .[dev]`"
        ) from exc

    process = psutil.Process(pid)
    start = time.monotonic()
    deadline = start + duration_sec
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as fh:
        while True:
            now = time.monotonic()
            if now > deadline:
                break
            sample = Sample(
                monotonic=now - start,
                wall_utc=_utc_now_z(),
                pid=pid,
                rss_bytes=int(process.memory_info().rss),
                private_bytes=_private_bytes(process),
                num_handles=_num_handles(process),
                num_threads=int(process.num_threads()),
                mql5_memory_used_mb=None,
            )
            fh.write(json.dumps(asdict(sample), separators=(",", ":")) + "\n")
            fh.flush()
            time.sleep(min(SAMPLE_INTERVAL_SEC, max(0.0, deadline - time.monotonic())))
    return out_path


def _main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--duration-sec", type=float, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verdict", type=Path, required=True)
    args = parser.parse_args()

    try:
        samples_path = collect(args.pid, args.duration_sec, args.out)
        verdict = analyse(load_samples(samples_path))
    except SoakEnvironmentError as exc:
        print(str(exc))
        return 3

    args.verdict.parent.mkdir(parents=True, exist_ok=True)
    args.verdict.write_text(
        json.dumps(asdict(verdict), indent=2, sort_keys=True),
        encoding="utf-8",
    )
    print(args.verdict.read_text(encoding="utf-8"))
    return 0 if verdict.passed else 1


if __name__ == "__main__":
    raise SystemExit(_main())
