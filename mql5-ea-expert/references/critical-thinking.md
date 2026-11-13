# Critical thinking for strategy work

How to judge a trading idea, a target and a backtest before anyone risks money. Use this
whenever a user brings a strategy, a target ("pass in 2 weeks"), or a result ("PF 2.4!").

---

## 1. Start from the base rate

- After spread, commission and slippage, most simple rule sets (breakouts, crossovers, candle
  patterns, "smart money" setups) have an expectancy indistinguishable from zero on liquid
  markets. Treat every new idea as zero edge until evidence says otherwise.
- A positive backtest is weak evidence on its own: with enough freedom (symbols, timeframes,
  sessions, filters, stop sizes) a random rule set will produce one.
- The user's conviction, a video, a high win rate, or a smooth equity curve on one period are
  not evidence. Out-of-sample results with costs are.

## 2. Questions before writing any code

1. **What is the hypothesis, in one sentence?** "Price continues after a 15-minute range at the
   New York open breaks" is testable; "smart money leaves footprints" is not.
2. **Who loses the money you win, and why do they keep doing it?** No answer -> expect no edge.
3. **When should it fail?** Name the regime (range days, news days, low volatility) and check it.
4. **What exactly is measured on closed data?** Every condition must be computable from bars
   that have closed. Swings need their confirmation bars; daily ranges are known only after the
   range ends.
5. **What does it cost to trade?** Spread at the trading hour, commission, typical slippage at
   the stop, swap if held overnight. A 1:1 strategy with a $0.30 spread on a $3 stop pays 10% per
   trade before anything else.
6. **What would make us drop it?** Write the rejection rule before testing (section 7).

## 3. Feasibility math for targets

Use money for target `T`, max loss `L`, risk per trade `r`, trades per day `f`, days `D`.

- Gain needed in R: `T / r`. Example: Propanium STARTER $1,000, target $80, risk $14 -> 5.7R.
- Trades available: `f * D`. A once-a-day strategy over 10 trading days -> 10 trades.
- Average needed per trade: `5.7R / 10 = 0.57R`. Realistic edges are 0.05-0.2R. So a 2-week
  pass is a bet on a lucky streak, whatever the entry logic.
- Zero-edge odds of hitting `+T` before `-L` with no time limit: `L / (T + L)`
  (80 vs 55 -> 41%). This is why cheap challenge tickets "work" even with no edge: the odds come
  from the rule geometry, and a daily limit plus a deadline reduce them.
- With mean `mu` and standard deviation `sigma` per trade:
  `P = (1 - exp(-2 mu L / sigma^2)) / (1 - exp(-2 mu (T + L) / sigma^2))`.
- Get real numbers from the user's trades: `python tools/edge_check.py report.htm --risk r
  --target T --daily-limit X --max-loss L --days N --fund-target F` (prints the same odds with
  the edge removed, so the user sees how much the strategy actually contributes).

How to answer an impossible target:
1. Show the arithmetic (R needed, trades available, required R per trade).
2. Give the measured or estimated probability, not adjectives.
3. Offer real options: longer horizon, smaller target, accept the odds knowingly (cheap tickets),
   or stop. Never invent a strategy "that reaches it".

## 4. How much data is enough

- Standard error of expectancy = `s / sqrt(n)`. Typical `s` for fixed-R trades is 1.0-1.5R.
- To show `e` with t = 2: `n ~ (2 s / e)^2`.

| True edge e | s = 1.2R: trades for t = 2 |
|---|---|
| 0.30R | ~64 |
| 0.20R | ~144 |
| 0.10R | ~576 |
| 0.05R | ~2,300 |

- Fewer than ~100 trades cannot distinguish a small edge from luck. A 6-month sample of a
  once-a-day strategy is a pilot, not a verdict.
- Always print the 95% interval of the expectancy. If it contains zero, say "no evidence of an
  edge", whatever the profit factor.

## 5. Multiple testing (the silent killer)

- Testing 100 settings and keeping the best guarantees an impressive in-sample number. The
  expected best of many zero-edge variants is far above zero.
- Count and report how many variants were tried, including the ones discarded.
- Keep a holdout period never used for choosing anything. Look at it once, at the end.
- Prefer parameter plateaus (neighbours also work) over peaks (only one setting works).
- A result that holds only on one broker's data, one session, or one half-year is a regime
  description, not an edge.

## 6. Null baselines (does the logic beat nothing?)

Run the same engine with the signal destroyed and compare:
- **Random direction**: same entry times and exits, direction from a coin flip.
- **Random time**: same number of entries per day at random times, same exits.
- **Shuffled days**: block-bootstrap the daily P&L with the mean removed (`edge_check.py` does this
  for challenge odds).
If the strategy is not clearly better than its null, the entry rule adds nothing; the exits and
the risk geometry produce the result.

## 7. Decision gates (write them down before testing)

A strategy may go to demo/forward testing only if all hold:
1. Real ticks (or the most realistic model available), the target broker's symbol, real spread,
   commission and a slippage allowance.
2. At least ~100 trades (more for small edges, see section 4).
3. 95% interval of expectancy above zero.
4. Every time block (e.g. 3 x 6 months) positive, or the worst block explicitly acceptable.
5. Out-of-sample/holdout within roughly half of the in-sample expectancy.
6. Beats its null baseline.
7. Parameter neighbourhood also positive.
8. Worst trade and worst day measured on real ticks stay inside the account limits with a buffer.

If none of a pre-set list of hypotheses passes, the honest result is "no edge found" - stop
searching variants of the same idea. More tuning raises the false-positive rate, not the odds.

## 8. Look-ahead and leakage checklist

- Signals use `shift >= 1` only; nothing reads the forming bar's close.
- Pivots/swings are dated at their confirmation bar, not at the pivot bar.
- Higher-timeframe values are taken from the last CLOSED higher-timeframe bar.
- Daily/session ranges are used only after the range window has ended.
- Same-bar SL and TP hits in bar-based research count as losses (worst case) unless tick data
  resolves the order.
- Indicators that redraw history (zigzag-style, centred filters) are unusable for entries.
- Research code and EA produce the same trades on the same data (parity check, see
  `backtesting-validation.md`).

## 9. Execution reality checklist

- Minimum volume vs risk: with a 1 oz minimum on gold, a $20 stop is $20 risk - no smaller
  position exists. Such setups must be skipped, not clamped.
- Stops slip: on real ticks, stops around news fill beyond the stop (see `case-studies.md`:
  -$24 on a $14 risk at NFP). Size limits with a buffer.
- Markets close early on holidays and pause daily; positions can be trapped and gap.
- Partial closes need volume for both parts.
- Server time is not UTC and its DST calendar must be measured.

## 10. Honest reporting

- Every number: source, symbol, period, model, costs, in-sample or out-of-sample.
- Show the bad: worst block, worst trade, worst day, losing streak, drawdown.
- Avoid: "guaranteed", "100% pass rate", "holy grail", "high probability" without a number,
  win rate without payoff ratio, PF without trade count.
- If an earlier answer stated numbers that were wrong or unverified, correct it explicitly and
  say what changed.
- Template:

```text
Verdict: <edge / no evidence of edge / negative>, based on <n> trades.
Data: <broker/source> <symbol> <period>, <tester model>, spread <...>, commission <...>.
Expectancy: <+x.xxR> (95% interval <a..b>), PF <..>, worst block <..>, worst trade <..>.
Against null baseline: <..>. Out-of-sample: <..>.
Challenge odds (<rules>): pass <p%> within <N> days, breach <q%>; without the edge <p0%>.
Not tested yet: <...>. Next test: <command>.
```
