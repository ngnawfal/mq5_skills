# Pitfalls: wrong vs right, and why

Use as a review checklist for any MQL5 code, including code written earlier in the conversation.

---

## Sizing and risk

| Wrong | Right | Why |
|---|---|---|
| `lot = MathMax(minLot, rawLot)` | If `rawLot < minLot` -> skip the trade | Clamping multiplies the planned risk; a $14 budget produced a -$92 loss |
| `NormalizeDouble(lot, 2)` | Floor to `SYMBOL_VOLUME_STEP`, digits from the step | Steps of 0.001, 0.1 or 1 exist |
| Risk from `pips * pipValue` | `OrderCalcProfit()` between entry and stop | Exact for gold, indices, crypto, crosses |
| Kelly % compared with a risk % input | Keep units explicit (fraction vs percent) | Old code mixed 0.05 (5%) with 1.0 (1%) |
| Daily DD = `(balance - equity) / balance` | Day reference snapshot at the rule's reset time and zone | Floating-only formula ignores realised losses of the day |
| Total DD from current balance | From the start balance (or the rule's trailing reference) | Prop max loss is anchored |
| Close only `_Symbol` positions on a breach | Rules are per account: measure account equity | Other EAs and manual trades count |
| Risk check once at entry | Re-check on every tick/timer, close on breach | Equity moves after entry |
| Partial close 70% of the minimum lot | Only if both parts >= minimum volume | Order is rejected; logic silently changes |
| Stop treated as the maximum loss | Buffer for slippage; measure worst R on real ticks | NFP fill: -1.72R |

## Orders and positions

| Wrong | Right | Why |
|---|---|---|
| `trade.PositionClose(_Symbol)` | `trade.PositionClose(ticket)` after magic + symbol filter | On hedging it can close another EA's position |
| Forward loop while closing | Loop `PositionsTotal()-1 .. 0` | Indices shift as positions close |
| Hard-coded `ORDER_FILLING_FOK` | `SetTypeFillingBySymbol(symbol)` | Brokers differ; wrong mode -> 10030 |
| `NormalizeDouble(price, _Digits)` only | Round to `SYMBOL_TRADE_TICK_SIZE` | Indices tick in 0.25/0.5 |
| Ignoring stops/freeze level | Check `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL` | 10016 invalid stops, 10029 frozen |
| `if(trade.Buy(...))` = success | Check `ResultRetcode()` | `true` means "sent" |
| Retry every tick on failure | Back off; wait for the session on 10018 | 8,704 failed retries in one backtest |
| `position.Commission()` / `POSITION_COMMISSION` | Sum `DEAL_COMMISSION` of the deals | Deprecated, returns 0 |
| Several EAs on one symbol on a netting account | One EA per symbol, or a hedging account | Netting merges positions |

## Signals and data

| Wrong | Right | Why |
|---|---|---|
| Signals on `close[0]` / bar 0 | Closed bars (`shift >= 1`) once per new bar | Bar 0 changes every tick; tester and live diverge |
| Swing dated at the pivot bar | Usable only after `k` newer bars closed | Look-ahead; repaints |
| One global `lastBarTime` for several timeframes | One detector per symbol/timeframe | Signals are skipped or doubled |
| `CopyBuffer` result unchecked | Check the count, `BarsCalculated`, retry later | Fresh handles return -1 for a while |
| Handle created in `OnTick` | Create in `OnInit`, release in `OnDeinit` | Leaks and slowdowns |
| `ArraySetAsSeries(close,true)` with ascending non-series loop | One indexing convention for all arrays | Reads the wrong bars |
| Higher-timeframe value from shift 0 | Shift 1 (closed HTF bar) | Forming bar changes until it closes |

## Time

| Wrong | Right | Why |
|---|---|---|
| Sessions from `TimeGMT()` | Explicit server-time model (`CSkClock`) | Tester does not model GMT |
| Assuming US DST for the server | Measure with `SkillKit_ServerTimeProbe` | XM follows the EU calendar; one week per year differs |
| NY event at a fixed UTC hour | Anchor in New York time and convert | Off by one hour half the year |
| Flat at a fixed late time only | Also N minutes before the session end | Daily pause, Friday close |
| Ignoring holidays | Early closes are not in the session table | Positions trapped until reopen |
| Daily baseline reset on EA restart | Persist the snapshot (global variables) | Restart mid-day forgets the day's losses |
| Entry counter in memory | Count deals from history | Restart re-enters |

## Testing and statistics

| Wrong | Right | Why |
|---|---|---|
| Spread 0 / quiet-hour spread | Real-tick spread or spread at the trading hour | Inflates short-stop strategies |
| `STAT_EQUITY_DD > 20` as percent | `STAT_EQUITYDD_PERCENT` | `STAT_EQUITY_DD` is money |
| Best of many optimised settings as "the result" | Holdout + count of variants + plateau | Selection bias |
| PF/win rate without n and interval | Expectancy in R with 95% interval | 82 trades, PF 1.43 was not significant |
| One period, one broker | Time blocks + the account's own broker data | Regime and data-source dependence |
| "Compiles" claimed without compiling | `tools/compile_mql5.py` output | Syntax-only proof even then |

## Style and safety

| Wrong | Right | Why |
|---|---|---|
| `#property strict` | Omit | MQL4 directive, no effect in MQL5 |
| Magic number hard-coded | Input, unique per instance | Multiple charts collide |
| Credentials/tokens in source | Inputs or external config, never committed | Leaks |
| Unvalidated inputs | Validate in `OnInit`, return `INIT_PARAMETERS_INCORRECT` | Silent misbehaviour |
