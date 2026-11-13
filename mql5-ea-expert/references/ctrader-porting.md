# Porting an EA to cTrader (cAlgo) and running ctrader-cli

Observations from porting MQL5 EAs to cBots and running them headless (cTrader 5.9, ctrader-cli
5.9.0, Propanium cTrader accounts, Ubuntu 24.04). Re-check against the current cTrader docs.

---

## 1. API mapping

| MQL5 | cAlgo (C#) | Note |
|---|---|---|
| `OnInit` / `OnTick` / `OnDeinit` | `OnStart` / `OnTick` / `OnStop`, `OnBar` | `OnBar` fires on a new bar of the robot's timeframe |
| Server time, manual conversion | `[Robot(TimeZone = TimeZones.UTC)]` -> `Server.Time` in UTC | Removes the server-offset problem; NY/Prague still need DST logic |
| `CopyRates` / `iClose` | `Bars.ClosePrices.Last(1)`, `MarketData.GetBars(tf)` | `Last(0)` is the forming bar |
| Magic number | `Label` on orders/positions (+ symbol) | Keep labels unique per instance |
| `OrderCalcProfit` | `Symbol.PipValue`, `Symbol.PipSize`, or position `NetProfit` | Risk per unit = distance / PipSize * PipValue |
| Volume in lots | `VolumeInUnits`; `Symbol.QuantityToVolumeInUnits(lots)` | XAUUSD 0.01 lot = 1 unit (1 oz) on Propanium |
| `CTrade.Buy` | `ExecuteMarketOrder(TradeType.Buy, symbol, units, label, slPips, tpPips)` | Stops in **pips** relative to the fill |
| Global variables | `LocalStorage` | Persistence across restarts |
| `OnTimer` | `Timer.Start(TimeSpan)` + `OnTimer` | Guards without ticks |

## 2. Traps seen in practice

- **`Symbol.NormalizeVolumeInUnits(units, RoundingMode.Down)` raises volumes below the minimum to
  the minimum.** Check `units < Symbol.VolumeInUnitsMin` **before** normalising and skip the trade.
  The unchecked version entered a range breakout with an $81 range on a 1 oz minimum and lost
  -$92 on a $14 risk budget.
- Partial-close settings (e.g. 70% at 1R) never execute when the position is the minimum volume;
  the strategy then behaves differently from its design.
- Stop distances are passed in pips relative to the fill price: recompute from the actual entry.
- cTrader's position `NetProfit` includes commissions; `GrossProfit` does not.

## 3. ctrader-cli backtests

- `ctrader-cli backtest bot.algo --data-mode=m1 ...` uses **spread 0** unless `--spread=<pips>` is
  given. Always pass a realistic spread (or use tick data) and print it in the report.
- Tick mode (`--data-mode=ticks`) is far slower and long ranges may time out; run shorter windows.
- Authentication: `--ctid=<id> --pwd-file=<file>` or the `CTRADER_CLI_AUTHTOKEN` environment
  variable with `-e`. Never commit tokens or password files.
- Parameter overrides: `--ParamName=value`; the run log prints a table showing "cmd arg" vs
  "default value" - check it to confirm every override applied.
- Prop broker history can be short for some symbols ("No historical data for the specified
  period"): probe month by month before designing a long test.
- Running many backtests in parallel can fail with "algo host stopped unexpectedly"; on Windows
  `--full-access` resolved it in our runs, and moderate parallelism (6-12) was stable.

## 4. Running cBots headless on Linux

- Official native Linux package (Homebrew tap `spotware/homebrew-tap`, `ctrader-cli-<ver>-linux-x64.tar.gz`);
  restore the executable bit on extensionless binaries and `algohost.netcore` after extracting.
- The algo host needs a .NET runtime matching the cBot target (net6.0 at the time):
  `A fatal error occurred. The required library libhostfxr.so could not be found` -> install the
  .NET runtime (e.g. `dotnet-install.sh --channel 6.0 --runtime dotnet --install-dir /usr/share/dotnet`)
  and set `DOTNET_ROOT`.
- Linux has no algo sandbox; `--full-access` skips the start-up countdown. Run only your own code.
- systemd unit: `Restart=always`, `RestartSec=5`, `EnvironmentFile` for the token (mode 600),
  log to a file, one service per account/strategy. Verify with the log lines `Logged in`,
  `CBot instance [...] started` and your own `[INIT]`.
- One strategy per prop account: several bots on one small account multiply the daily risk.

## 5. Parity check after porting

Backtest the MQL5 EA and the cBot on the same broker, symbol, period and spread; compare entries
by time and direction. Differences usually come from bar alignment (server vs UTC), tie rules on
equal highs/lows, spread handling and volume rounding.
