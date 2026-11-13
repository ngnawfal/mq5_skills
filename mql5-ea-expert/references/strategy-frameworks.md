# Strategy frameworks: precise definitions, known failure modes, how to test

Popular frameworks are vocabularies, not edges. This file turns them into testable rules and
says how each one typically fails. Results quoted come from `case-studies.md` (one dataset each,
not universal truths).

---

## 1. Swing structure and the A-B-C ("Pola N") breakout

Definitions (price only, no indicators):
- **Swing high at bar s**: `high[s]` beats the `k` older bars strictly and the `k` newer bars with
  `>=` (one swing for equal highs). It is **known only when the k newer bars have closed**.
- Consecutive swings of the same type are merged into the more extreme one, so swings alternate.
- **Bullish A-B-C**: A = swing low, B = swing high, C = swing low with A < C < B (higher low).
  Trigger: a closed bar closes above B (+ buffer) and the previous close did not (fresh break).
  Stop below C (- buffer). Target = RR x risk. Bearish mirrored.
- Code: `SkRecentSwings()` in `SkillKit_Structure.mqh`; reference EA `SkillKit_StructureBreakout.mq5`;
  visual check `SkillKit_Swings.mq5`.

Failure modes:
- Look-ahead if swings are dated at the pivot bar (the classic repainting "fractal").
- The stop at C is often far: with a large minimum volume the trade is either oversized (bug) or
  skipped (strategy changes - test the skip).
- Trend filters (moving averages, higher-timeframe structure) change little: in one 5-year gold
  test neither EMA 50/200 nor H1 Dow-structure filters produced a stable edge (case study 7).
- Break-even and partial-close add-ons raise the win rate and usually lower expectancy.

Test plan: confirmed-swing engine, real ticks, sizing skips included, 3+ time blocks, null
baseline with random direction on the same trigger bars.

## 2. Opening-range breakout (ORB)

Definitions:
- Range = high/low of the first `N` minutes after a market open, anchored in that market's zone
  (US equity open 09:30 New York -> 13:30 UTC in summer, 14:30 UTC in winter; set
  `AnchorNewYork`-style logic, never a fixed UTC hour).
- OCO stop orders at range high/low, one trade per day; stop at the opposite side of the range (or
  a fixed distance); exit at target, stop, or a flat time before the session end.

Failure modes:
- Designed for index futures at the cash open; transplanting it to gold or FX at arbitrary hours
  is a different strategy.
- Wide ranges + minimum volume: skip rules decide most of the results.
- Stops fill beyond the range on news opens (NFP, CPI at 08:30 New York is before the 09:30 open,
  but some markets react at the open).
- Broker dependency: one broker's 5-year data showed +0.12R/trade on gold NY-open ORB, the prop
  broker's 18 months showed PF 0.78-0.92 for every variant (case study 8). Always test on the
  account's own broker before trusting another data source.

## 3. Liquidity sweep -> market structure shift -> pullback

Definitions:
- Levels: last confirmed swing high/low (confirmed `k` bars after the pivot).
- **Sweep**: a bar trades through the level and closes back on the original side within
  `reclaimBars` bars.
- **MSS**: within `mssWindow` bars after the sweep, a close beyond the opposite level.
- **Entry**: first pullback bar in `pbWindow` that touches the MSS level and closes back with a
  rejection shape (lower wick >= x body or close in the top y% of the range); enter next bar.
- Stop beyond the sweep extreme; target RR x risk.

Failure modes:
- Many free parameters (windows, wick ratio, close position, retrace depth, tick-volume spike,
  session, higher-timeframe bias) -> grid searches of 10^4-10^5 combinations make in-sample
  winners almost certain. Count combinations; demand out-of-sample.
- Duplicate trades: nested sweeps converge on the same entry bar; deduplicate by
  (direction, entry bar), not by swept level, or statistics count one trade several times.

## 4. SMC / ICT / CRT vocabulary as testable rules

| Term | Testable definition | Watch out |
|---|---|---|
| Break of structure (BOS) | Close beyond the last confirmed swing in the trend direction | "Last swing" must be confirmed before the break bar |
| Change of character (CHoCH) | First close beyond the last confirmed opposite swing | Same as MSS above |
| Fair value gap (FVG) | Bullish: `low[i] > high[i+2]` on closed bars i, i+2 (series indexing) | Gap is known after bar i closes |
| Order block (OB) | Last opposite-colour candle before the displacement that caused a BOS | Many definitions; fix one and stick to it |
| Equal highs/lows | Two confirmed swings within a tolerance in price (not in points) | Tolerance scales with volatility |
| Kill zones / Silver Bullet | Time windows defined in **New York time** | Convert with a zone model; never `TimeGMT()` |
| CRT (candle range) | Reference candle high/low; sweep of one side then close back inside | Reference candle must be closed |
| Displacement | Body >= x times the average body of the last n bars | Use closed bars only |

Treat each combination as a hypothesis with a fixed rule set, then apply the full validation
protocol. A vocabulary that explains every chart after the fact predicts nothing.

## 5. Multi-timeframe bias

- Use the last **closed** higher-timeframe bar (`shift 1`); the forming bar changes until it closes.
- Moving averages, Dow-structure (higher highs and higher lows) and prior-day direction are all
  bias candidates; each must beat "no filter" out-of-sample, otherwise drop it.
- A filter that removes 70% of trades needs 3x more history for the same statistical power.

## 6. Mean reversion and range strategies

- Edges, when present, tend to appear in low-volatility regimes and disappear in trends; test the
  regime split explicitly.
- Fixed take-profit inside the range + wide stop gives high win rates and rare large losses:
  measure the worst block and the worst trade on real ticks before trusting the win rate.

## 7. Grid, martingale, recovery

Not a strategy class but a position-sizing scheme; see `grid-martingale.md` and do the
risk-of-ruin math before writing a line.
