"""Unit tests for tools/edge_check.py (stdlib only): python -m unittest discover -s tools -p "test_*.py"."""

from __future__ import annotations

import math
import random
import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import edge_check as ec  # noqa: E402


def synthetic(win_prob: float, n: int = 1500, seed: int = 1) -> list[tuple[datetime, float]]:
    rng = random.Random(seed)
    t = datetime(2024, 1, 1, 10)
    out = []
    for _ in range(n):
        t += timedelta(hours=rng.choice([5, 20, 26]))
        out.append((t, 21.0 if rng.random() < win_prob else -14.0))
    return out


class DescribeTests(unittest.TestCase):
    def test_zero_edge_interval_contains_zero(self):
        s = ec.describe([p for _, p in synthetic(0.4)])   # 0.4*21 - 0.6*14 = 0
        self.assertLessEqual(s["ci_low"], 0.0)
        self.assertGreaterEqual(s["ci_high"], 0.0)

    def test_real_edge_is_detected(self):
        s = ec.describe([p for _, p in synthetic(0.52)])  # +4.2 per trade expected
        self.assertGreater(s["ci_low"], 0.0)
        self.assertGreater(s["t"], 4.0)

    def test_drawdown_and_streak(self):
        s = ec.describe([10, -5, -5, -5, 20])
        self.assertEqual(s["max_dd"], 15)
        self.assertEqual(s["max_losing_streak"], 3)
        self.assertAlmostEqual(s["pf"], 30 / 15)


class BlockTests(unittest.TestCase):
    def test_blocks_cover_all_trades(self):
        trades = synthetic(0.45, n=300)
        parts = ec.blocks(trades, 3)
        self.assertEqual(len(parts), 3)
        self.assertEqual(sum(len(p) for _, p in parts), len(trades))


class ChallengeTests(unittest.TestCase):
    def test_zero_edge_matches_gamblers_ruin(self):
        # symmetric +/-10 steps, target 80, max loss 60: P(target first) ~ 60/140
        # (expected duration is 48 steps, so 600 steps is effectively unlimited)
        res = ec.simulate([10.0, -10.0], horizon=600, target=80, daily_limit=0, max_loss=60,
                          fund_target=0, trials=3000, block=1, rng=random.Random(3))
        self.assertAlmostEqual(res["pass"], 60 / 140, delta=0.04)

    def test_edge_beats_null_control(self):
        trades = synthetic(0.52, n=2000)
        days = ec.daily_pnl(trades, 0)
        mean = sum(days) / len(days)
        rng = random.Random(5)
        real = ec.simulate(days, 60, 80, 30, 60, 0, 3000, 1, rng)
        null = ec.simulate([d - mean for d in days], 60, 80, 30, 60, 0, 3000, 1, rng)
        self.assertGreater(real["pass"], null["pass"] + 0.2)

    def test_daily_limit_breach(self):
        res = ec.simulate([-35.0], horizon=5, target=80, daily_limit=30, max_loss=60,
                          fund_target=0, trials=100, block=1, rng=random.Random(1))
        self.assertEqual(res["breach"], 1.0)
        self.assertTrue(math.isnan(res["median_days_to_pass"]))


if __name__ == "__main__":
    unittest.main()
