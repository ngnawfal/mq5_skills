# Risk sizing and prop-firm rules

Prop-firm accounts fail on rules, not on strategy. Turn every rule into an explicit code limit,
measure it the way the firm measures it, and keep a buffer for what the stop cannot protect.

---

## 1. Read the rules, then classify them

Always take rules from the firm's current rule page (date it in the answer). Classify each one:

| Rule type | Questions that change the code |
|---|---|
| Profit target | % of start balance? Equity or closed balance? Minimum trading days? |
| Daily loss | Measured on balance, equity, or max(balance, equity)? Reset time **and time zone** (00:00 UTC, midnight Prague CE(S)T, 17:00 New York)? Includes floating loss? |
| Max loss | Static from start balance, or trailing (from equity/balance high-water mark)? Does it lock at break-even after some profit? |
| Floating-loss rule | e.g. Propanium "Smart Exit": all trades closed at 2% floating loss and the profit split reduced; not a breach but costly. |
| Per-trade / exposure | Max lots, max positions, stop loss mandatory, max risk per trade. |
| Time / events | News windows (orders near high-impact events voided), weekend holding, inactivity. |
| Behaviour | Consistency rules, gambling/"all-in" bans, HFT, hedging across accounts, copy-trading. |
| Payout | Profit buffer before payout, minimum payout, payout cap, split. |

Encode every limit as an input in money (not %), so the EA does not depend on balance changes.

### Example: Propanium STARTER ($1,000), rule page read 2026-11-11

| Rule | Value | Guard in the EA |
|---|---|---|
| Target | 8% = $80 | `InpProfitTarget = 80` (lock and stop) |
| Daily drawdown | 3% = $30, equity snapshot at 00:00 UTC | `InpDailyLimit = 25`, `InpDailyBasis = EQUITY`, `InpResetZone = UTC`, hour 0 |
| Max drawdown | 6% = $60 | `InpMaxLoss = 55` |
| Smart Exit | floating loss 2% = $20 closes everything, -10% profit split each time | `InpFloatShield = 17`, risk per trade <= 12-14 |
| Profit buffer | 3% = $30 before payout; payouts capped at $100 lifetime | funded phase target $30 + payout |
| Minimum volume (XAUUSD) | 0.01 lot = 1 oz -> $1 per $1 move | setups with a stop wider than the risk budget are skipped |

Rules change - re-read the page before every deployment.

## 2. Sizing a trade

```mql5
double wanted = InpRiskMoney;                                   // or balance * percent
double budget = g_guard.RiskBudget(wanted, InpMagic);            // remaining room, minus open risk
double lots   = SkLotsForRisk(_Symbol, type, entry, stop, budget, InpCommissionLot);
if(lots <= 0.0) { /* SKIP: min volume would risk more than the budget */ return; }
if(!SkMarginOk(_Symbol, type, lots, entry, 0.5)) return;
```

- `SkLotsForRisk` uses `OrderCalcProfit()` for the money lost per lot at the stop, adds
  commission, rounds **down** to the volume step and returns 0 if the minimum volume is too
  big. Clamping up to the minimum volume is the most common sizing bug: a $14 budget became a
  -$92 loss in a real cBot backtest (case study 1).
- `RiskBudget` takes the minimum of: wanted risk, daily room, total room, floating-shield room,
  each minus the risk still open to other positions' stops. An open position without a stop
  makes the budget 0.
- Percent-of-balance risk shrinks after losses and grows after wins; fixed money risk is easier
  to reason about against fixed money limits.

## 3. Buffers: the stop is not a cap

- Stops are market orders when triggered. Around news, rollover, open and weekend gaps they fill
  beyond the stop. Case study 4: $14 planned risk, -$24.05 realised at NFP on real ticks, which
  would trip a $20 floating-loss rule.
- Measure on real ticks: `edge_check.py --risk r` warns about trades worse than -1.05R and prints
  the worst R. Set `risk + worst observed slippage < hard limit`, and keep news blackouts.
- Daily room: guard at 80-85% of the firm's limit (25 of 30), close everything on breach.
- The floating-loss shield must sit below the firm's floating rule (17 of 20); with one position
  at a time, per-trade risk must also sit below it with margin.

## 4. Enforcing limits live

```mql5
void OnTimer() { EnforceGuards(); }          // EventSetTimer(1) in OnInit
void OnTick()  { if(!EnforceGuards()) return; ... }

bool EnforceGuards()
  {
   g_guard.Update();                                 // snapshot at the firm's reset time
   if(g_guard.ShieldHit()) g_trader.CloseAll("floating-loss shield");
   if(g_guard.Halted())                              // daily breach, max loss, or target reached
     {
      if(g_trader.Count() > 0) g_trader.CloseAll("limit");
      return false;
     }
   return true;
  }
```

- Measure on **account** equity: other EAs and manual trades count against the same limits.
- The daily snapshot is taken by timer close to the reset time and stored in terminal global
  variables, so a restart mid-day restores it instead of resetting the baseline to the current
  (possibly already reduced) equity.
- Count entries per period from deal history, not from a variable, so a restart cannot re-enter.
- Close on breach immediately; do not wait for stops.

## 5. Daily snapshot basis and reset zone

| Firm says | Set |
|---|---|
| "Daily loss from equity at 00:00 UTC" | `SK_DAY_BASIS_EQUITY`, `SK_ZONE_UTC`, 0:00 |
| "From balance at midnight CE(S)T" | `SK_DAY_BASIS_BALANCE`, `SK_ZONE_PRAGUE`, 0:00 |
| "From the higher of balance/equity at 17:00 New York" | `SK_DAY_BASIS_MAX`, `SK_ZONE_NEW_YORK`, 17:00 |

If the firm snapshots equity while you hold a position, your EA's snapshot at the same moment
differs slightly by tick timing; keep the buffer.

## 6. Minimum volume, partial closes and break-even

- Know `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_STEP` and the money value of one minimum lot per price
  unit. On a $1,000 account with gold at 1 oz minimum, any setup with a stop farther than the
  risk budget cannot be traded; skipping them changes the strategy - backtest the skip.
- A 70% partial close of a 0.01-lot position is impossible. Plan partials only when the position
  is at least `min / fraction` and the remainder is >= min.
- Break-even moves and partials raise win rate and usually lower expectancy; prove them on
  real ticks before using them.

## 7. Time-related risk

- Daily pause (17:00 New York for FX/metals) and weekend: flatten before the session end
  (`SkMinutesToSessionEnd`), or accept gap risk explicitly.
- US holidays close metals early (case study 6: about 21:24 server on XM) and are not in the
  session table - a flat time after the early close cannot execute.
- High-impact news: firms often void orders opened within minutes of events, and stops slip.
  The MQL5 economic calendar does not provide history inside the Strategy Tester, so a news
  filter must be backtested with an imported event list, or its effect stays unproven.

## 8. Money management choices

- Fixed fractional (constant % or money) is the default.
- Kelly fraction requires a reliable edge estimate; with the uncertainty of 100-300 trades the
  estimate is noise. If used: quarter-Kelly or less, and cap at the per-trade limit.
- Increasing size after losses (martingale, recovery) is incompatible with daily-loss rules; see
  `grid-martingale.md`.
- After passing an evaluation, the funded phase is a new problem (buffer before payout, payout
  cap): compute its odds separately with `edge_check.py --fund-target`.
