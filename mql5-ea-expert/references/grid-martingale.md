# Grid, martingale and recovery schemes

These are position-sizing schemes, not edges. They convert many small wins into rare large
losses. With no edge they lose; with a small edge they usually still lose to the tail.

---

## 1. Do the math first

Martingale with multiplier `m`, `k` steps, base risk `r` per step (money lost if a step fails):
- Loss of a full failed sequence: `r * (1 + m + m^2 + ... + m^(k-1)) = r * (m^k - 1) / (m - 1)`.
- With per-step loss probability `q` (independent), a sequence fails with probability `q^k`.
- Example: `r = $10`, `m = 1.5`, `k = 4`, `q = 0.5`: failed sequence = $81.25, probability 6.25%;
  a won sequence earns roughly one base win. 16 sequences in, the expected number of failures is 1.
- Prop limits: a $30 daily limit allows only `r * (m^k-1)/(m-1) <= 30 - buffer`. With $10 base
  and m = 1.5 that is k = 2. Recovery schemes and daily limits are fundamentally incompatible.

Grid with `n` levels spaced `d`, equal volume `v` per level, adverse move `D >= n*d`:
- Floating loss at the last level ~ `v * d * n(n+1)/2` (per unit move value), growing with the
  square of the levels. Always compute the basket loss at the hard stop before coding.

## 2. Mandatory caps when the user still wants it

- Multiplier <= 1.5 and <= 4 steps / levels.
- A hard basket stop in money that is below every account limit with buffer, closing all
  positions of the scheme by ticket.
- Stop loss or basket stop must be server-side or enforced on every tick and timer event.
- No adding during the daily pause, news windows, or near the session end.
- Stop the scheme for the day after one failed sequence.
- Check the prop-firm rules: many prohibit martingale/grid or "all-in" behaviour; some void profits.

## 3. Implementation notes

- Track the scheme by magic number and a sequence id in the comment; recompute the state from
  open positions and history in `OnInit` (restart-safe).
- Size every level with `SkLotsForRisk` against the remaining basket budget; if the minimum
  volume exceeds it, stop adding.
- Close the basket with `CSkTrader::CloseAll` (ticket-based, market-closed back-off).
- Backtest on real ticks over periods that include trending crashes (e.g. 2020-03, 2022 for
  FX/gold); report the worst basket loss, not the win rate.

## 4. What to tell the user

State the failure probability and the failed-sequence loss in money next to the account limits,
before any code. If the scheme cannot fit the daily or total limit, say so and offer a fixed-risk
alternative.
