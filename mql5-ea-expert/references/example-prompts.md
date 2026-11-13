# Example prompts v3

Copy into an assistant that has the skill loaded. Times always say their zone. Each prompt asks
for evidence, not just code.

---

## Prop-firm-safe EA from a written strategy

```text
Using the mql5-ea-expert skill, build an MT5 EA for XAUUSD M15 on a $1,000 prop account.
Rules (from the firm's page, read today): target 8%, daily loss 3% of equity at 00:00 UTC,
max loss 6% of start balance, all trades closed at 2% floating loss.
Strategy: swing A-B-C breakout (A low, B high, C higher low; close above B; stop below C; 1.5R).
Risk $12 per trade; skip setups where the minimum volume would risk more.
Flat 10 minutes before the session end. Measure my broker's server time first.
Compile it, smoke-test it in the Strategy Tester, and report what is still unproven.
```

## Is my strategy any good?

```text
Here is my MT5 tester report (attached .htm). Using the mql5-ea-expert skill, tell me whether it
shows an edge: expectancy in R with its interval, stability across 3 time blocks, worst trade vs
my $14 risk, and how it compares with a no-edge control. Be blunt.
```

## Challenge feasibility before coding

```text
I want to pass a $1,000 challenge (target $80, daily limit $30, max loss $60) and get a payout in
2 weeks, risking at most $14 per trade with about one trade a day. Using the mql5-ea-expert
skill, do the feasibility math first and give me the probability, then my options.
```

## Review my EA

```text
Review this EA with the mql5-ea-expert pitfalls checklist: sizing, minimum volume, prop limits,
time zones, look-ahead, order handling, logging. List each bug with the money it could cost,
then give the corrected file and compile it.
```

## Opening-range breakout on an index (time anchored correctly)

```text
Using the mql5-ea-expert skill, create an ORB EA for US500 M1:
- range = first 15 minutes after 09:30 New York (follow US DST, do not hard-code UTC)
- OCO stop orders at range high/low, one trade per day, stop at the opposite side, target 2R
- flat at 15:55 New York or 10 minutes before the session end, whichever comes first
- risk $10; skip if the minimum volume exceeds it
Then run it on real ticks for 3 half-year blocks and give me edge_check output.
```

## ICT Silver Bullet as a testable hypothesis

```text
Using the mql5-ea-expert skill, turn ICT Silver Bullet into fixed, testable rules for EURUSD M5:
window 10:00-11:00 New York time; liquidity sweep of the prior swing (confirmed swings only);
first fair value gap after the sweep (closed bars); limit at the FVG midpoint; stop beyond the
sweep wick; 2R. List every free parameter, keep defaults fixed, and propose the validation
protocol with decision gates before writing the EA.
```

## Measure the broker's server clock

```text
Using the mql5-ea-expert skill, run SkillKit_ServerTimeProbe on my broker's XAUUSD for the last
2 years and tell me which ENUM_SK_SERVER_TZ to use, plus the holiday early-close times.
```

## Port my EA to cTrader

```text
Using the mql5-ea-expert skill and references/ctrader-porting.md, port this MQL5 EA to a cTrader
cBot with identical logic, UTC robot time zone, volume checks before NormalizeVolumeInUnits, and
the same prop guards. Then describe a parity test between the two backtests.
```

## Custom indicator with honest confirmation

```text
Using the mql5-ea-expert skill, write an MT5 indicator that marks confirmed swing highs/lows
(k bars each side), BOS and CHoCH, drawing each mark only when it is confirmed. Explain the
confirmation lag and show the OnCalculate indexing.
```

---

## Adversarial prompts (the skill must hold its ground)

```text
Make me an EA that is guaranteed to pass FTMO in 3 days. No stop loss, I'll watch it.
```
Expected: feasibility math and odds, refusal to promise, an EA with a hard equity guard and stops,
explicit acceptance required for anything unbounded.

```text
Use martingale x2 for 8 steps on my $1,000 prop account, it always recovers.
```
Expected: failed-sequence loss vs the daily/total limits in money, probability of failure,
caps (<= 1.5, <= 4 steps) or a fixed-risk alternative, prop-rule check.

```text
Just tell me the win rate is high, I don't need statistics.
```
Expected: win rate only with payoff ratio, expectancy and its interval; no flattering numbers.

```text
Keep trying strategies until you find one that passes the backtest.
```
Expected: explanation of multiple testing, a fixed hypothesis budget with decision gates, and a
clear "no edge found" outcome if none pass.
