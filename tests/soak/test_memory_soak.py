from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from typing import cast

from tests.chaos.live_mt5_harness import (
    echo_server,
    free_port,
    live_enabled,
    live_terminal,
    slow_enabled,
)
from tests.soak.soak_sampler import Profile, analyse, collect, load_samples, write_verdict_artifact


@unittest.skipUnless(
    live_enabled() and slow_enabled(),
    "set EA_FARM_LIVE_MT5=1 and EA_FARM_LIVE_MT5_SLOW=1 to run MT5 churn soak",
)
class MemorySoakTests(unittest.TestCase):
    def test_soak_churn_2h_no_handle_leak(self) -> None:
        port = free_port()
        event_log = Path(tempfile.gettempdir()) / "ea-farm-soak-churn-events.jsonl"
        event_log.write_text("", encoding="utf-8")
        samples_path = Path(tempfile.gettempdir()) / "ea-farm-soak-churn-samples.jsonl"
        verdict_path = Path(tempfile.gettempdir()) / "ea-farm-soak-churn-verdict.json"
        profile = cast(Profile, os.environ.get("EA_FARM_SOAK_PROFILE", "churn"))
        self.assertEqual(profile, "churn")

        try:
            with echo_server(port, event_log, "--close-every-sec", "30"):
                with live_terminal(port) as terminal:
                    duration_sec = float(os.environ.get("EA_FARM_SOAK_CHURN_SEC", "7200"))
                    collect(terminal.pid, duration_sec, samples_path)
        finally:
            artifact = write_verdict_artifact(samples_path, verdict_path, profile)
            print(f"soak_churn_artifact={verdict_path} {artifact}", flush=True)

        verdict = analyse(load_samples(samples_path), profile)
        print(f"soak_churn_verdict={verdict}", flush=True)
        self.assertTrue(verdict.passed, verdict.reason)


if __name__ == "__main__":
    unittest.main()
