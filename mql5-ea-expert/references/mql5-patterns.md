# MQL5 canonical patterns

Every snippet here either comes from the compile-verified SkillKit templates or was compiled
in a scratch EA with MetaEditor (0 errors, 0 warnings) before being written down. Prefer
including SkillKit over re-typing these.

---

## 1. Program skeleton

```mql5
#property copyright "..."
#property version   "1.00"                // no #property strict: MQL4-only, no effect in MQL5

#include <SkillKit\SkillKit_Trade.mqh>     // pulls Risk and Time

input group "=== RISK ==="
input double InpRiskMoney = 10.0;          // Risk per trade (money)
input group "=== EA ==="
input ulong  InpMagic     = 260513;        // Magic number

CSkClock  g_clock;
CSkTrader g_trader;
CSkNewBar g_bar;

int OnInit()
  {
   if(InpRiskMoney <= 0.0)
      return INIT_PARAMETERS_INCORRECT;    // validate every input
   g_clock.Init(SK_TZ_GMT2_EU_DST, 2);     // measured with SkillKit_ServerTimeProbe
   if(!g_trader.Init(_Symbol, InpMagic, 20))
      return INIT_FAILED;
   g_bar.Init(_Symbol, PERIOD_M15);
   EventSetTimer(1);                       // guards also run without ticks
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer()                 { /* guards */ }
void OnTick()
  {
   /* guards first */
   if(!g_bar.IsNew())
      return;                              // signals once per closed bar
   /* evaluate signal on shift >= 1 */
  }
```

## 2. Indicator handles

```mql5
int h_atr = INVALID_HANDLE;

int OnInit()
  {
   h_atr = iATR(_Symbol, PERIOD_H1, 14);
   if(h_atr == INVALID_HANDLE)
     {
      PrintFormat("[INIT] iATR failed, error %d", GetLastError());
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(h_atr != INVALID_HANDLE)
      IndicatorRelease(h_atr);
  }

bool AtrClosed(double &value)              // value of the last CLOSED bar
  {
   if(BarsCalculated(h_atr) < 15)
      return false;                        // not ready yet (common right after start / on other TFs)
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h_atr, 0, 1, 1, buf) != 1)
      return false;                        // retry on a later tick, do not trade on garbage
   value = buf[0];
   return true;
  }
```

- Never create handles in `OnTick`. Data for another timeframe/symbol may not be ready on the
  first calls: `BarsCalculated` < required or `CopyBuffer` returning -1 means "try later".

## 3. Prices, volumes, distances

- Round prices to the tick size: `SkNormalizePrice(symbol, price)` (indices often tick in 0.25 or 0.5).
- Express distances in **price** (or points), not "pips": a pip is undefined for gold, indices and
  crypto, and `pips * _Point * 10` is wrong on 2- and 3-digit gold quotes.
- Volumes: `SkVolumeFloor` (down to the step, digits from the step). Never `NormalizeDouble(v, 2)`
  for a step of 0.001 or 1.
- Money per lot between two prices: `OrderCalcProfit(type, symbol, 1.0, from, to, profit)`.
  `SYMBOL_TRADE_TICK_VALUE` can differ for profit and loss and changes with conversion rates.

## 4. Orders

```mql5
// Market order with absolute SL/TP, stops-level checked, retcode verified
g_trader.Market(ORDER_TYPE_BUY, lots, stopPrice, targetPrice, "");

// Pending stop order with expiration, if the symbol allows ORDER_TIME_SPECIFIED
CTrade trade;
long expModes = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
bool canExpire = (expModes & SYMBOL_EXPIRATION_SPECIFIED) != 0;
datetime expiry = TimeCurrent() + 3600;
if(canExpire)
   trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry, "");
else
   trade.BuyStop(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "");   // cancel it yourself at expiry
```

- `SetTypeFillingBySymbol(symbol)`: brokers support different filling modes (FOK/IOC/Return).
- `SetMarginMode()`: makes `CTrade` aware of hedging vs netting.
- Check `ResultRetcode()`; `Buy()` returning true only means the request was sent.
- Pending prices must also respect the stops level relative to the current price.

## 5. Positions

```mql5
for(int i = PositionsTotal() - 1; i >= 0; i--)     // backwards: closing shifts indices
  {
   ulong ticket = PositionGetTicket(i);              // also selects the position
   if(ticket == 0) continue;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
   // ... act by ticket: trade.PositionClose(ticket), trade.PositionModify(ticket, sl, tp)
  }
```

- Never `trade.PositionClose(_Symbol)` on hedging accounts: it picks a position of the symbol
  regardless of magic.
- Netting accounts hold one position per symbol; several EAs on one symbol share it. Use one EA
  per symbol on netting, or a hedging account.
- `POSITION_COMMISSION` is deprecated; commissions are on deals (`DEAL_COMMISSION`).
- Stops management: `CSkTrader::ImproveStop` (only improves, respects stops and freeze levels).
  Partial close: `CSkTrader::ClosePartial` (both parts >= minimum volume).

## 6. History and fills

```mql5
// entries of this EA since a server time (restart-safe trade counting)
int EntriesSince(const datetime from)
  {
   if(!HistorySelect(from, TimeCurrent() + 60)) return 0;
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic
         && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol
         && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         n++;
     }
   return n;
  }

// react to fills (e.g. cancel the opposite pending order of an OCO pair)
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      PrintFormat("[FILL] deal %I64u at %s", trans.deal,
                  DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits));
  }
```

Net result of a closed trade = `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP` of its deals (entry
deals carry commission too).

## 7. Persistence across restarts

- Terminal global variables survive terminal restarts (not tester runs):
  `GlobalVariableSet(name, value)`, `GlobalVariableGet(name)`, `GlobalVariableCheck(name)`.
  Prefix names with login and magic. `CSkPropGuard` stores the start balance and the daily snapshot.
- Anything derivable from history (entries today, last trade time) should be recomputed from
  history in `OnInit`, not kept only in memory.
- Files: `FileOpen(name, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ)` then `FileSeek(h, 0, SEEK_END)`
  to append. Add `FILE_COMMON` to share between terminals/tester agents. Tester files go to the
  agent's sandbox, not the terminal's `MQL5\Files`.

## 8. Return codes worth handling

| Retcode | Meaning | Response |
|---|---|---|
| 10004 REQUOTE / 10020 PRICE_CHANGED / 10021 PRICE_OFF | Price moved or no quote | Refresh tick, retry once if still valid |
| 10006 REJECT | Rejected by dealer | Log, do not loop |
| 10014 INVALID_VOLUME | Volume vs min/step/max | Fix sizing (`SkVolumeFloor`, skip below min) |
| 10015 INVALID_PRICE / 10016 INVALID_STOPS | Price/tick size, stops level | Normalise to tick size, respect stops level |
| 10018 MARKET_CLOSED | Session closed or holiday | Wait for the session (`CSkTrader` backs off) |
| 10019 NO_MONEY | Margin | Check `OrderCalcMargin` before sending |
| 10024 TOO_MANY_REQUESTS | Flooding | Throttle; never retry every tick |
| 10027 CLIENT_DISABLES_AT | AutoTrading off | Stop trading, alert the user |
| 10029 FROZEN | Inside freeze level | Do not modify/close now |
| 10030 INVALID_FILL | Filling mode | `SetTypeFillingBySymbol` |

## 9. Logging

Use tags so logs can be counted automatically (`run_mt5_tester.py` does this):
`[INIT] [ENTRY] [EXIT] [SKIP] [RISK] [PROP] [TRADE] [TIME] [FILL]`. Log every skipped setup with
its reason - "the EA does not trade" is usually a skip rule doing its job, and the log proves it.

## 10. Multi-symbol EAs

- One `CSkNewBar`, handle set and `CSkTrader` per symbol; check `SymbolSelect(symbol, true)` in `OnInit`.
- Signals for other symbols arrive only on the chart symbol's ticks: drive them from `OnTimer`.
- Exposure limits across symbols (correlated pairs) belong to the account-level guard.
