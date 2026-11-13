#!/usr/bin/env python3
"""Does this trade list show an edge, and what are the real odds of passing a challenge with it?

Input: an MT5 Strategy Tester report (.htm/.html) or a CSV with a close-time column and a
profit column (optional R column). Standard library only.

    python tools/edge_check.py report.htm --risk 14
    python tools/edge_check.py trades.csv --time-col close_time --profit-col net --risk 14 ^
        --target 80 --daily-limit 30 --max-loss 60 --days 14 --fund-target 45

What it prints:
  1. Sample statistics with uncertainty: expectancy, its standard error, t-statistic,
     95% interval, profit factor, max consecutive losses, closed-trade drawdown.
  2. Stability: the same statistics per time block. An edge that lives in one block is a regime,
     not an edge.
  3. Challenge odds by bootstrapping whole trading days: P(pass target within --days),
     P(breach), median days to pass, with the SAME day distribution re-centred to zero mean
     (the "no-edge control"). If both numbers are close, the pass rate comes from variance and
     rule geometry, not from the strategy.
"""

from __future__ import annotations

import argparse
import csv
import html
import math
import random
import re
import statistics
import sys
from datetime import datetime
from pathlib import Path


# ----------------------------------------------------------------------------- loading
def _read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8", errors="ignore")


def _num(s: str) -> float:
    return float(s.replace("\u00a0", "").replace(" ", "").replace(",", ""))


def load_mt5_report(path: Path) -> list[tuple[datetime, float]]:
    """Closed trades from the Deals table: profit + commission + swap of every 'out' deal."""
    text = _read_text(path)
    trades: list[tuple[datetime, float]] = []
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", text, re.S | re.I):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S | re.I)]
        cells = [c for c in cells if c != ""]
        # Time, Deal, Symbol, Type, Direction, Volume, Price, Order, Commission, Swap, Profit, Balance, [Comment]
        if len(cells) >= 12 and re.match(r"\d{4}\.\d\d\.\d\d \d\d:\d\d", cells[0]) and cells[4] in ("out", "in/out"):
            try:
                net = _num(cells[8]) + _num(cells[9]) + _num(cells[10])
            except ValueError:
                continue
            trades.append((datetime.strptime(cells[0][:19], "%Y.%m.%d %H:%M:%S"), net))
    return trades


def load_csv(path: Path, time_col: str, profit_col: str, r_col: str | None):
    trades, rs = [], []
    with path.open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            t = row[time_col].strip()
            for fmt in ("%Y-%m-%d %H:%M:%S", "%Y.%m.%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
                try:
                    ts = datetime.strptime(t[:19].replace("+00:00", ""), fmt)
                    break
                except ValueError:
                    continue
            else:
                sys.exit(f"FAIL: cannot parse time '{t}'")
            trades.append((ts, float(row[profit_col])))
            if r_col:
                rs.append(float(row[r_col]))
    return trades, (rs or None)


# ----------------------------------------------------------------------------- statistics
def describe(values: list[float]) -> dict[str, float]:
    n = len(values)
    if n == 0:
        return {"n": 0}
    mean = statistics.fmean(values)
    sd = statistics.stdev(values) if n > 1 else 0.0
    se = sd / math.sqrt(n) if n > 1 else float("inf")
    wins = [v for v in values if v > 0]
    losses = [v for v in values if v <= 0]
    gross_loss = -sum(losses)
    eq = peak = dd = 0.0
    streak = worst_streak = 0
    for v in values:
        eq += v
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
        streak = streak + 1 if v <= 0 else 0
        worst_streak = max(worst_streak, streak)
    t = mean / se if se not in (0.0, float("inf")) else 0.0
    return {
        "n": n, "win_rate": len(wins) / n, "mean": mean, "sd": sd, "se": se, "t": t,
        "p_two_sided": math.erfc(abs(t) / math.sqrt(2)),
        "ci_low": mean - 1.96 * se, "ci_high": mean + 1.96 * se,
        "pf": (sum(wins) / gross_loss) if gross_loss > 0 else float("inf"),
        "net": sum(values), "max_dd": dd, "max_losing_streak": worst_streak,
        "worst": min(values), "best": max(values),
    }


def blocks(trades: list[tuple[datetime, float]], k: int) -> list[tuple[str, list[float]]]:
    trades = sorted(trades)
    if k <= 1 or len(trades) < k:
        return [("all", [p for _, p in trades])]
    start, end = trades[0][0], trades[-1][0]
    span = (end - start).total_seconds() / k or 1.0
    out: list[tuple[str, list[float]]] = []
    for i in range(k):
        lo = start.timestamp() + i * span
        hi = lo + span if i < k - 1 else float("inf")
        part = [p for t, p in trades if lo <= t.timestamp() < hi]
        out.append((f"{datetime.fromtimestamp(lo):%Y-%m-%d}..", part))
    return out


# ----------------------------------------------------------------------------- challenge
def daily_pnl(trades: list[tuple[datetime, float]], day_start_hour: int) -> list[float]:
    days: dict[str, float] = {}
    for t, p in trades:
        key = datetime.fromtimestamp(t.timestamp() - day_start_hour * 3600).strftime("%Y-%m-%d")
        days[key] = days.get(key, 0.0) + p
    if not days:
        return []
    # include flat weekdays so trade frequency is preserved
    first = datetime.strptime(min(days), "%Y-%m-%d")
    last = datetime.strptime(max(days), "%Y-%m-%d")
    out = []
    d = first
    while d <= last:
        if d.weekday() < 5:
            out.append(days.get(d.strftime("%Y-%m-%d"), 0.0))
        d = datetime.fromtimestamp(d.timestamp() + 86400)
    return out


def simulate(days: list[float], horizon: int, target: float, daily_limit: float, max_loss: float,
             fund_target: float, trials: int, block: int, rng: random.Random) -> dict[str, float]:
    """Bootstrap paths of `horizon` trading days by resampling blocks of consecutive days.
    Daily loss is checked on closed P&L of the day (intraday floating loss is NOT modelled:
    real breach odds are higher)."""
    passed = breached = paid = 0
    pass_days: list[int] = []
    n = len(days)
    for _ in range(trials):
        path: list[float] = []
        while len(path) < horizon:
            s = rng.randrange(n)
            path.extend(days[(s + j) % n] for j in range(block))
        bal, phase = 0.0, "eval"
        for i, p in enumerate(path[:horizon]):
            if daily_limit > 0 and p <= -daily_limit:
                breached += 1
                break
            bal += p
            if max_loss > 0 and bal <= -max_loss:
                breached += 1
                break
            if phase == "eval" and bal >= target:
                passed += 1
                pass_days.append(i + 1)
                if fund_target <= 0:
                    break
                phase, bal = "fund", 0.0
            elif phase == "fund" and bal >= fund_target:
                paid += 1
                break
    res = {"pass": passed / trials, "breach": breached / trials,
           "median_days_to_pass": statistics.median(pass_days) if pass_days else float("nan")}
    if fund_target > 0:
        res["payout"] = paid / trials
    return res


# ----------------------------------------------------------------------------- report
def fmt(v: float, money: bool = True) -> str:
    if isinstance(v, float) and (math.isinf(v) or math.isnan(v)):
        return str(v)
    return f"{v:,.2f}" if money else f"{v:.3f}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="MT5 tester report .htm or a CSV of closed trades")
    ap.add_argument("--time-col", default="close_time")
    ap.add_argument("--profit-col", default="profit")
    ap.add_argument("--r-col", help="CSV column with the R multiple of each trade")
    ap.add_argument("--risk", type=float, help="money risked per trade; converts profit to R")
    ap.add_argument("--blocks", type=int, default=3, help="time blocks for the stability check")
    ap.add_argument("--target", type=float, default=0, help="challenge profit target (money)")
    ap.add_argument("--daily-limit", type=float, default=0, help="daily loss limit (money)")
    ap.add_argument("--max-loss", type=float, default=0, help="max total loss (money)")
    ap.add_argument("--fund-target", type=float, default=0, help="funded-phase profit needed for the payout (money)")
    ap.add_argument("--days", type=int, default=20, help="horizon in trading days")
    ap.add_argument("--day-start-hour", type=int, default=0, help="hour (of the trade timestamps) the daily limit resets")
    ap.add_argument("--trials", type=int, default=20000)
    ap.add_argument("--block", type=int, default=1, help="bootstrap block length in days (keeps streaks)")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    src = Path(args.source)
    rs = None
    if src.suffix.lower() in (".htm", ".html"):
        trades = load_mt5_report(src)
    else:
        trades, rs = load_csv(src, args.time_col, args.profit_col, args.r_col)
    if len(trades) < 2:
        sys.exit("FAIL: fewer than 2 closed trades found")
    trades.sort()
    profits = [p for _, p in trades]
    if rs is None and args.risk:
        rs = [p / args.risk for p in profits]

    s = describe(profits)
    print(f"Trades: {s['n']}  ({trades[0][0]:%Y-%m-%d} .. {trades[-1][0]:%Y-%m-%d})")
    print(f"  net {fmt(s['net'])} | win rate {s['win_rate']:.1%} | PF {fmt(s['pf'], False)} | worst trade {fmt(s['worst'])}")
    print(f"  expectancy {fmt(s['mean'])} per trade, SE {fmt(s['se'])}, t = {s['t']:.2f}, p ~ {s['p_two_sided']:.3f}")
    print(f"  95% interval of expectancy: [{fmt(s['ci_low'])}, {fmt(s['ci_high'])}]"
          + ("   <- includes zero: no evidence of an edge" if s["ci_low"] <= 0 <= s["ci_high"] else ""))
    print(f"  closed-trade max drawdown {fmt(s['max_dd'])} | longest losing streak {s['max_losing_streak']}")
    if rs:
        r = describe(rs)
        print(f"  in R: expectancy {r['mean']:+.3f}R (SE {r['se']:.3f}R), worst {r['worst']:+.2f}R")
        over = [x for x in rs if x < -1.05]
        if over:
            print(f"  WARNING: {len(over)} trade(s) lost more than 1.05R (worst {min(over):+.2f}R): slippage/gaps,"
                  " the stop is not a hard cap - keep a buffer below every account limit")
    need = 4.0 / max(abs(s['mean']) / s['sd'], 1e-9) ** 2 if s['sd'] > 0 else float("inf")
    print(f"  trades needed for t = 2 at this effect size: ~{need:,.0f}")

    print(f"\nStability ({args.blocks} time blocks):")
    positive = 0
    for label, part in blocks(trades, args.blocks):
        b = describe(part)
        if b["n"] == 0:
            print(f"  {label}: no trades")
            continue
        positive += b["net"] > 0
        print(f"  {label}: n={b['n']:4d}  net {fmt(b['net']):>10}  PF {fmt(b['pf'], False):>6}  t {b['t']:+.2f}")
    print(f"  positive blocks: {positive}/{args.blocks}"
          + ("" if positive == args.blocks else "   <- not consistent across time"))

    if args.target > 0:
        days = daily_pnl(trades, args.day_start_hour)
        mean_day = statistics.fmean(days)
        null_days = [d - mean_day for d in days]
        rng = random.Random(args.seed)
        real = simulate(days, args.days, args.target, args.daily_limit, args.max_loss,
                        args.fund_target, args.trials, args.block, rng)
        null = simulate(null_days, args.days, args.target, args.daily_limit, args.max_loss,
                        args.fund_target, args.trials, args.block, rng)
        print(f"\nChallenge odds over {args.days} trading days ({len(days)} historical weekdays, "
              f"{args.trials:,} bootstrap paths, block {args.block}d):")
        print(f"  target {fmt(args.target)}, daily limit {fmt(args.daily_limit)}, max loss {fmt(args.max_loss)}"
              + (f", funded target {fmt(args.fund_target)}" if args.fund_target > 0 else ""))
        hdr = "  {:<22}{:>8}{:>9}{:>16}" + ("{:>9}" if args.fund_target > 0 else "")
        cols = ["", "pass", "breach", "median days"] + (["payout"] if args.fund_target > 0 else [])
        print(hdr.format(*cols))
        for name, res in (("this strategy", real), ("no-edge control", null)):
            vals = [name, f"{res['pass']:.1%}", f"{res['breach']:.1%}", f"{res['median_days_to_pass']:.0f}"]
            if args.fund_target > 0:
                vals.append(f"{res['payout']:.1%}")
            print(hdr.format(*vals))
        print("  Daily limits are checked on closed daily P&L; intraday floating losses are not modelled.")
        if s["ci_low"] <= 0:
            print("  -> Expectancy is not distinguishable from zero, so the gap between the two rows is not reliable either.")
        elif abs(real["pass"] - null["pass"]) < 0.01:
            print("  -> The pass rate is the same without the edge: it comes from variance and the rule geometry.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
