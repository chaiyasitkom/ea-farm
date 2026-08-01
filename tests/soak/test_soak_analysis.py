from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tests.soak.soak_sampler import (
    MB,
    SAMPLE_INTERVAL_SEC,
    WARMUP_SEC,
    Sample,
    SoakEnvironmentError,
    analyse,
    linear_slope,
    load_samples,
)


def _sample(
    monotonic: float,
    private_mb: float,
    *,
    pid: int = 100,
    handles: int = 20,
    threads: int = 5,
) -> Sample:
    return Sample(
        monotonic=monotonic,
        wall_utc=f"2026-08-01T00:{int(monotonic // 60) % 60:02d}:00Z",
        pid=pid,
        rss_bytes=int((private_mb + 10) * MB),
        private_bytes=int(private_mb * MB),
        num_handles=handles,
        num_threads=threads,
        mql5_memory_used_mb=None,
    )


def _series(
    hours_after_warmup: float = 24.0,
    *,
    private_base_mb: float = 100.0,
    slope_mb_per_hour: float = 0.0,
) -> list[Sample]:
    points = int(hours_after_warmup * 3600 / SAMPLE_INTERVAL_SEC) + 1
    samples = [_sample(0.0, private_base_mb + 500.0)]
    for idx in range(points):
        elapsed = idx * SAMPLE_INTERVAL_SEC
        hours = elapsed / 3600
        samples.append(
            _sample(
                WARMUP_SEC + elapsed,
                private_base_mb + slope_mb_per_hour * hours,
            )
        )
    return samples


class SoakAnalysisTests(unittest.TestCase):
    def test_flat_series_passes(self) -> None:
        samples = _series()
        jittered = [
            _sample(sample.monotonic, 100.0 + ((idx % 5) - 2) * 0.5)
            if sample.monotonic >= WARMUP_SEC
            else sample
            for idx, sample in enumerate(samples)
        ]
        verdict = analyse(jittered)
        self.assertTrue(verdict.passed, verdict.reason)
        self.assertEqual(verdict.reason, "")

    def test_linear_leak_2mb_per_hour_fails_m1(self) -> None:
        verdict = analyse(_series(slope_mb_per_hour=2.0))
        self.assertFalse(verdict.passed)
        self.assertIn("M1", verdict.reason)

    def test_step_growth_30mb_fails_m2_not_m1(self) -> None:
        samples = _series()
        stepped = [
            _sample(sample.monotonic, 130.0 if sample.monotonic == samples[-1].monotonic else 100.0)
            if sample.monotonic >= WARMUP_SEC
            else sample
            for sample in samples
        ]
        verdict = analyse(stepped)
        self.assertFalse(verdict.passed)
        self.assertIn("M2", verdict.reason)
        self.assertNotIn("M1", verdict.reason)

    def test_slow_leak_0_9mb_per_hour_fails_m2(self) -> None:
        verdict = analyse(_series(hours_after_warmup=28.0, slope_mb_per_hour=0.9))
        self.assertFalse(verdict.passed)
        self.assertNotIn("M1", verdict.reason)
        self.assertIn("M2", verdict.reason)

    def test_handle_leak_one_per_reconnect_fails_m3(self) -> None:
        samples = _series(hours_after_warmup=2.0)
        leaked = [
            _sample(sample.monotonic, 100.0, handles=20 + idx)
            if sample.monotonic >= WARMUP_SEC
            else sample
            for idx, sample in enumerate(samples)
        ]
        verdict = analyse(leaked)
        self.assertFalse(verdict.passed)
        self.assertIn("M3", verdict.reason)

    def test_warmup_hour_excluded_from_baseline(self) -> None:
        samples = _series()
        samples[0] = _sample(0.0, 10000.0)
        verdict = analyse(samples)
        self.assertTrue(verdict.passed, verdict.reason)

    def test_sleep_gap_20pct_fails_m5(self) -> None:
        samples = _series(hours_after_warmup=2.0)
        gapped = [
            sample
            for idx, sample in enumerate(samples)
            if sample.monotonic < WARMUP_SEC or idx % 5 != 0
        ]
        verdict = analyse(gapped)
        self.assertFalse(verdict.passed)
        self.assertIn("M5", verdict.reason)
        self.assertGreater(len(verdict.gaps_detected), 0)

    def test_pid_change_is_env_failure_not_verdict(self) -> None:
        samples = _series(hours_after_warmup=2.0)
        samples[-1] = _sample(samples[-1].monotonic, 100.0, pid=101)
        with self.assertRaises(SoakEnvironmentError):
            analyse(samples)

    def test_linear_slope_matches_known_series(self) -> None:
        slope = linear_slope([0.0, 10.0, 20.0, 30.0], [3.0, 23.0, 43.0, 63.0])
        self.assertAlmostEqual(slope, 2.0, delta=0.02)

    def test_ea_log_reader_follows_midnight_rollover(self) -> None:
        from tests.chaos.live_mt5_harness import LogMark, read_ea_log_since

        with tempfile.TemporaryDirectory(prefix="ea-farm-logs-") as raw:
            first = Path(raw) / "20260731.log"
            second = Path(raw) / "20260801.log"
            first.write_bytes("before\n".encode("utf-16le"))
            second.write_bytes("after\n".encode("utf-16le"))
            text = read_ea_log_since(LogMark(first, first.stat().st_size))
        self.assertIn("after", text)

    def test_load_samples_reads_jsonl(self) -> None:
        sample = _sample(WARMUP_SEC, 100.0)
        with tempfile.TemporaryDirectory(prefix="ea-farm-samples-") as raw:
            path = Path(raw) / "samples.jsonl"
            path.write_text(json.dumps(sample.__dict__) + "\n", encoding="utf-8")
            loaded = load_samples(path)
        self.assertEqual(loaded, [sample])


if __name__ == "__main__":
    unittest.main()
