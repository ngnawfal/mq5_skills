# Case studies (real tests, November 2026)

Each case is one dataset and one implementation - evidence for the rules in this skill, not a
universal statement about the strategies. Sources: MetaTrader 5 Strategy Tester on XM (GOLDm#),
cTrader CLI backtests on Propanium (XAUUSD and indices), and 5 years of Exness XAUUSD M5 bars
(Jul 2021 - Jul 2026) replayed in Python with a $0.20 spread.

---

## 0. Numbers without provenance

An assistant summarised a strategy as "win rate 68.8%, PF 1.31, +$269" and "100% pass rate".
The first came from re-filtering an old trade list by hours (not a backtest); the second came from
a different account size and rule set. A fresh backtest on the real account and rules gave PF 1.13.
**Rule:** every number states source, period, model, costs and in/out-of-sample; corrections are
said explicitly.

## 1. Minimum volume clamped up

cTrader ORB bot on XAUUSD, Propanium $1,000, risk $14. On 2026-01-30 the opening range was $81 wide
(buy stop 5073.49, stop 4992.49). The needed volume was below the 1 oz minimum, and
`NormalizeVolumeInUnits(..., RoundingMode.Down)` raised it to the minimum: loss -$92.05.
After checking the volume before normalising, the worst trade became -$25.5.
**Rule:** below the minimum volume -> skip (`SkLotsForRisk` returns 0).

## 2. Partial close of the minimum lot

A "bank 70% at +1R, move the rest to break-even" design ran on 1 oz positions. 70% of the minimum
cannot be closed, so only the break-even move happened - a different strategy from the one designed.
**Rule:** partial closes only when both parts are >= the minimum volume (`CSkTrader::ClosePartial`).

## 3. Spread 0 by default

cTrader CLI `backtest --data-mode=m1` printed `Spread | 0 | default value` in its parameter table.
Every earlier result had been computed without spread. **Rule:** print and set the spread; prefer
real ticks.

## 4. Stops are not caps (news)

Reference EA, XM GOLDm#, 2026-05-01..11-01, real ticks, risk $14: on 2026-10-02 at 12:30 UTC (US
payrolls) a sell stop at 4196.36 filled at 4215.06: -$24.05 (-1.72R). Two of 82 trades lost more
than 1.05R. A $20 floating-loss rule (Propanium Smart Exit) would have fired.
**Rule:** risk + worst measured slippage < hard limit; news blackouts; measure worst R on real ticks.

## 5. Server DST model and holidays

The reference EA assumed US DST for XM's server. The probe EA (`SkillKit_ServerTimeProbe`) showed XM
follows the **EU** calendar (GMT+2 winter, GMT+3 from the last Sunday of March to the last Sunday of
October). In the week 2026-10-26..11-01 the daily pause began at 22:58 server instead of 23:58, so
the EA's flat at "20:50 UTC" came after the market had paused and the position was held through it.
US holidays closed gold early (~21:24 server) - not in the session table. The first tester run logged
8,704 "market closed" close retries from timer and ticks.
After switching to the measured model, flattening 10 minutes before the session end and backing off
on retcode 10018: 0 failed operations, one logged "market closed, waiting" on Memorial Day.
**Rule:** measure the server clock; flatten before the session end; back off when closed.

## 6. Daily loss guard that only blocked new entries

A cBot stopped opening trades after a -$28 day but did not close open positions; realised daily
losses reached -$37.11 against a $30 rule (6 days in 6 months). Its daily baseline was also reset
to the current balance whenever the bot restarted.
**Rule:** close on an equity breach immediately; persist the daily snapshot; size new risk from the
remaining room.

## 7. Short history vs long history (Pola N / A-B-C breakout)

Same logic (gold M5, swing 10, RR 1.5, structure stop <= $15, no indicator filter):
- Propanium cTrader, May 2025 - Oct 2026: 285 trades, PF 1.32, +$534 (looked promising).
- Python port verified against cTrader (183 of 220 entries identical, same PF 1.11 on the overlap),
  run on 5 years: 1,946 trades, expectancy -0.016R; 2022 -0.10R, 2023 -0.04R, 2024 +0.03R,
  2025 +0.03R. Filters tried one by one (breakout candle body, close distance beyond B, C
  retracement depth incl. Fibonacci 0.30-0.65, A-B impulse size, time since C, candle size vs
  average, chase distance, hour, stop size, EMA 50/200, H1 Dow structure): every bucket within
  about +/-0.1R of zero, no consistent improvement.
**Rule:** 18 months can be one regime; demand multi-year, multi-block evidence.

## 8. Same idea, different broker data (ORB)

Gold New York-open ORB (15-minute range from 13:45 UTC, stop at the opposite side, target 3R),
Exness 5 years: +0.116R per trade, 5 of 6 calendar years positive. On Propanium cTrader
(May 2025 - Oct 2026, $14 risk, spread $0.20) every variant lost: PF 0.78-0.95. The positive years
were mostly 2022-2025; the recent period was negative on both data sources.
Indices ORB on Propanium (SPX500, US2000 from Nov 2025; NAS100, US30 from Jul 2026 - the server had
no older data): all 48 variants negative, best PF 0.99.
**Rule:** validate on the account's own broker and the most recent period; respect data limits.

## 9. Null baseline exposed "no edge"

Two-day challenge sprint simulation on 5 years (target $80, risk <= $14, daily stop $28, max loss
$55): Pola N swing 10 with a target set to finish the challenge in one win passed 6.0% of start
dates; the same trades with **random direction** passed 5.9%. Swing 6: 8.4% vs 7.9%.
**Rule:** compare with a null; the pass rate came from the target/limit geometry.

## 10. Feasibility of "payout in 2 weeks"

Propanium STARTER: target $80, then $30 buffer + $15 minimum payout, risk <= $14, about one trade
per day. Needed: about 9R in 10 trading days. Measured probability per ticket of evaluation +
first payout within 14 calendar days: Pola N 0.2-0.4%, adjusted ORB 1.4% (TP 3R) to 5.8% (sprint
target). Median time to the first payout with repeated $1 tickets: about 4 months for Pola N.
**Rule:** compute R needed / trades available before coding; give probabilities, not promises.

## 11. "The bot does not enter"

A live bot made no trade in its first days. A backtest of the previous two months showed 31 entries
(3-4 per week, with gaps of several days); more than half of all breakouts were skipped because
their structural stop exceeded the $15 cap. Hourly `[STATUS]` lines and `[SKIP]` reasons in the log
made the behaviour visible instead of suspicious.
**Rule:** log skips with reasons and a periodic status.

## 12. The research spiral

After a strategy failed validation, more variants were explored (filters, other frameworks), each
with more parameters. None passed on the account's broker data, and the search itself raised the
odds of a false positive. **Rule:** fix a hypothesis budget and decision gates up front; when none
pass, report "no edge found" and stop.
