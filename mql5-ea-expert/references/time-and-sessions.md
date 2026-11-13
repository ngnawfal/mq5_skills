# Time, sessions and DST

Time bugs are silent: the EA compiles, trades, and simply does things one hour off on some
weeks of the year. Make every time explicit and measure the broker's clock.

---

## 1. Clocks in MetaTrader 5

| Function | Meaning | In the Strategy Tester |
|---|---|---|
| `TimeCurrent()` | Time of the last quote received (server time) | Simulated server time |
| `TimeTradeServer()` | Calculated current server time | Simulated server time |
| `TimeGMT()` | GMT from the computer's clock and time-zone settings | **Not modelled: equals the simulated server time** |
| `TimeLocal()` | Computer's local time | Simulated server time |

Consequence: any session filter, kill zone or reset time computed from `TimeGMT()` is wrong in
backtests by the server offset (usually 2-3 hours) while looking fine live. Convert explicitly:
`CSkClock::ServerToUtc()` with a model that is identical in tester and live.

Live, `TimeTradeServer() - TimeGMT()` measures the offset, but it depends on the VPS clock and
time-zone settings being correct.

## 2. Broker server time zones

Most FX/CFD servers run at GMT+2 in winter and GMT+3 in summer so that the daily candle closes
at 17:00 New York. But **which DST calendar** they follow differs:

| Model | Summer time from / to | `ENUM_SK_SERVER_TZ` |
|---|---|---|
| US DST (stays aligned to New York all year) | 2nd Sunday of March / 1st Sunday of November | `SK_TZ_GMT2_US_DST` |
| EU DST | last Sunday of March / last Sunday of October | `SK_TZ_GMT2_EU_DST` |
| Fixed | never changes | `SK_TZ_FIXED` |

Between the US and EU switch dates (about 3 weeks in March, 1 week around November) the two
models disagree by one hour. A wrong model shifts sessions, flat times and daily resets on
those weeks only.

**Measure, do not assume.** Run `templates/Experts/SkillKit_ServerTimeProbe.mq5` in the tester
over a year or more on an FX pair or gold. It maps the start of each daily pause to 17:00 New
York and prints every confirmed offset change. Measured on XM (GOLDm#, 2025-01 .. 2026-11):

```text
2025.01.02  pause 23:58 server -> server = GMT+2
2025.03.31  pause 23:58 server -> server = GMT+3   (EU DST start)
2025.10.27  pause 22:58 server -> server = GMT+2   (EU DST end, US still on DST)
2026.03.30  pause 23:58 server -> server = GMT+3
2026.10.26  pause 22:58 server -> server = GMT+2
irregular pauses at 21:24 server on US holidays (early close)
```

So XM follows the EU calendar: from late October to the first Sunday of November the daily pause
starts at 22:58 server instead of 23:58. An EA assuming the US calendar missed its flat on
2026-10-29 and held a position through the pause (case study 5).

## 3. Anchoring events to the right zone

| Event | Natural zone | Notes |
|---|---|---|
| FX/metals daily pause, rollover | New York 17:00 | Swap charged at rollover; spreads widen minutes before and after. |
| US equity open (ORB on indices) | New York 09:30 | = 13:30 UTC (summer) or 14:30 UTC (winter). |
| US data releases (NFP, CPI) | New York 08:30 | = 12:30 / 13:30 UTC; stops slip. |
| London open | London 08:00 | EU DST calendar. |
| Prop-firm daily reset | As written by the firm | 00:00 UTC, midnight Prague, 17:00 New York are all common. |

Express an anchored time in its own zone (`CSkClock::UtcToZone`) and convert; never hard-code a
UTC hour for a New York event - it is wrong for part of the year.

## 4. Sessions, pauses, holidays

- `SymbolInfoSessionTrade()` gives the broker's trading sessions per weekday in server time.
  `SkMinutesToSessionEnd()` joins sessions that continue past midnight and returns the minutes
  left (-1 when closed). Use it to flatten before the daily pause and the Friday close, and to
  block entries in the last N minutes.
- Holiday early closes are **not** in the session table. On XM gold, US holidays (MLK, Presidents,
  Memorial, Juneteenth, Labor Day, Thanksgiving) stopped quoting around 21:24 server. A flat time
  set later cannot execute; the position waits for the reopen and may gap. Options: no entries on
  known holiday afternoons, an earlier flat on those dates, or accept and size for the gap.
- While the market is closed, close requests return retcode 10018. Back off (`CSkTrader` waits 60 s)
  instead of retrying every tick or timer event.
- Quotes may resume a minute or two before trading is allowed again; the first requests after a
  pause can still fail with 10018.

## 5. Bars and time

- `iTime(symbol, tf, 0)` is the open time of the forming bar in server time. Bars do not exist for
  periods without quotes, so "the 14:00 bar" may be missing on thin days - code for absence.
- Daily (D1) bars follow the server's midnight, which is New York 17:00 only if the server offset
  matches the DST model; on mismatch weeks D1 bars start one hour off.
- Higher-timeframe values must come from the last closed higher-timeframe bar (`shift 1`).
- Per-timeframe new-bar detection needs one detector per timeframe (`CSkNewBar`).

## 6. Checklist for any time logic

- [ ] Every time input says its zone in the input comment.
- [ ] Conversion through `CSkClock` (or equivalent), no `TimeGMT()` in decisions.
- [ ] Server DST model measured with the probe for this broker.
- [ ] Flat before session end, entries blocked near session end.
- [ ] Holiday early closes considered; behaviour on closed market tested in the tester log.
- [ ] Daily reset of risk limits uses the firm's zone and is persisted across restarts.
