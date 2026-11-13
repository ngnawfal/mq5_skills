# Backtesting and validation

A backtest answers "what would this code have done on this data with these costs". It only
becomes evidence of an edge after the checks below.

---

## 1. Verify the code before judging the strategy

1. Compile: `python tools/compile_mql5.py path/to/EA.mq5` -> must print 0 errors, 0 warnings.
2. Smoke run: `python tools/run_mt5_tester.py path/to/EA.mq5 --symbol XAUUSD --period M15
   --from 2026.05.01 --to 2026.06.01 --model 1 --deposit 1000 --set InpRiskMoney=14`.
3. Read the EA log summary the runner prints: tag counts, `failed operations` (must be 0),
   `[SKIP]` reasons, `[EXIT]` reasons. Open the saved `_ealog.txt` for anything odd.
4. Check behaviour, not only totals: do flats happen at the intended server time, is the daily
   snapshot taken at the reset time, are skips reported when the minimum volume is too big?

Runtime checks find what compiling cannot: the reference EA compiled cleanly and then produced
8,704 "market closed" retries and a missed flat in its first tester run (case study 5).

## 2. Strategy Tester settings

| Setting | Use |
|---|---|
| Model 4 "Every tick based on real ticks" | Any verdict, anything with stops/targets inside a bar, news, scalping. |
| Model 0 "Every tick" (generated) | Only when real ticks are missing; still synthetic inside bars. |
| Model 1 "1 minute OHLC" | Smoke tests and fast iteration only. |
| Model 2 "Open prices only" | Only for logic that acts exclusively at bar open and has no intrabar stops. |
| Symbol | The target broker's symbol (spreads, contract size, sessions and DST differ by broker). |
| Spread | From history (real ticks) or a realistic fixed value at the trading hour - never 0. |
| Commission | Configure the symbol's commission or pass it to sizing (`InpCommissionLot`). |
| Delay | Test with execution delay (`ExecutionMode` / `--delay-ms`) for strategies sensitive to fills. |
| Deposit/leverage | The real account's size: sizing granularity at $1,000 is very different from $100,000. |

Other platforms: cTrader CLI `backtest --data-mode=m1` uses spread 0 unless `--spread` is given
(case study 3). Always print the spread used.

Check history availability first: a prop broker's server may hold only months of data for some
symbols (Propanium had SPX500/US2000 from Nov 2025 and NAS100/US30 from Jul 2026 - too short for
any verdict). Never fill gaps by silently switching broker without saying so.

## 3. Protocol

1. **Fix the hypothesis and the decision gates first** (`critical-thinking.md` section 7).
2. **Split time**: in-sample (design), out-of-sample (selection check), holdout (one final look).
   Use at least 3 blocks so stability can be seen.
3. **Real costs and real ticks** for every run that informs a decision.
4. **Run the null baseline**: same engine, random direction or random entry times.
5. **Optimise sparingly**: few parameters, coarse grid, record every run. Prefer the centre of a
   plateau. MT5's Forward option (e.g. 1/3) reserves an out-of-sample period automatically.
6. **Analyse with uncertainty**: `python tools/edge_check.py report.htm --risk 14 --blocks 3`.
7. **Walk-forward** if parameters are re-fitted over time: optimise on window k, test on k+1, chain.
8. **Forward test** on demo with the exact production settings before real money; compare
   fills, slippage and trade count with the backtest of the same weeks.

## 4. Reading the numbers

- Expectancy in R and its 95% interval matter more than net profit or PF.
- Profit factor without the trade count means nothing; PF 1.43 on 82 trades was t = 1.45
  (not significant) in the reference EA run.
- Win rate is meaningless without the payoff ratio.
- Drawdown from closed trades understates the intraday drawdown that prop rules measure.
- `trades needed for t = 2` from `edge_check.py` tells whether the sample could have shown the
  edge at all.
- A pass rate in a challenge simulation must be compared with its no-edge control.

## 5. Optimisation criterion (`OnTester`)

```mql5
double OnTester()
  {
   double trades  = TesterStatistics(STAT_TRADES);
   double ddPct   = TesterStatistics(STAT_EQUITYDD_PERCENT);   // percent
   double ddMoney = TesterStatistics(STAT_EQUITY_DD);          // money
   double net     = TesterStatistics(STAT_PROFIT);
   if(trades < 100 || ddPct > 20.0 || net <= 0.0)
      return 0.0;                                              // reject small or deep samples
   return net / MathMax(ddMoney, 1.0);
  }
```

`STAT_EQUITY_DD` is money; comparing it with 20 as if it were percent is a classic bug.

## 6. Parity check (research code vs EA)

When a strategy was researched in Python (or another platform) and then coded as an EA, prove
they are the same strategy:
1. Port the EA logic to the research environment (or vice versa) on the same bars.
2. Compare trade lists by entry time and direction; aim for > 80-90% identical entries.
3. Explain every systematic difference (bar alignment, spread, tie rules for equal highs,
   confirmation timing). In one session a Python port matched 183 of 220 cTrader trades
   (83%) with the same profit factor (1.11) - enough to trust the port for 5-year research.

## 7. Common ways backtests lie

| Inflation | Fix |
|---|---|
| Spread 0 or "current spread" from a quiet hour | Real-tick spread or the spread at the trading hour |
| Bar models with stops inside the bar | Real ticks; same-bar SL/TP counted as loss in research |
| Swings dated at the pivot bar | Date at the confirmation bar (`SkRecentSwings`, `SkillKit_Swings`) |
| Signals on `bar[0]` | Closed bars only |
| Lot clamped to minimum | Skip trades that exceed the budget |
| Session/flat in `TimeGMT()` | Explicit server-time model; tester does not model GMT |
| One lucky half-year | Blocks + holdout + other data source |
| Choosing the best of many | Count variants; holdout; plateau |
| Ignoring holidays/news | Real ticks show the gaps; add blackouts and measure worst trade |
