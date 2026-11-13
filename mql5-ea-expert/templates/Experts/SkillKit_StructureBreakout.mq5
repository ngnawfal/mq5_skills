//+------------------------------------------------------------------+
//| SkillKit_StructureBreakout.mq5                                   |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: reference EA - swing-structure (A-B-C) breakout with    |
//|          prop-firm-safe risk. Example logic: NO EDGE IS CLAIMED. |
//+------------------------------------------------------------------+
// Bullish setup: A = swing low, B = swing high, C = higher low (A < C < B).
// Trigger: the last CLOSED bar closes above B (+buffer) and the bar before it
// did not (fresh breakout). Stop below C (-buffer). Target = RewardRisk x risk.
// Bearish is the mirror image.
//
// What this file demonstrates (the strategy itself is only a placeholder):
//  - decisions on closed bars only, swings confirmed k bars later (no repaint)
//  - money risk sized from OrderCalcProfit, trade SKIPPED if min volume is too big
//  - prop-firm guard on account equity: daily limit with a persisted snapshot at
//    the firm's reset time, max loss from start balance, floating-loss shield,
//    profit-target lock, new risk limited to the remaining room
//  - session and flat time in UTC, identical in the Strategy Tester and live
//  - trades-per-period counted from history, so a restart cannot re-enter
//  - OnTester() criterion that rejects small samples and deep drawdowns
#property copyright "mql5-ea-expert"
#property link      "https://github.com/nawfdev/mq5_skills"
#property version   "3.00"
#property description "Reference EA for the mql5-ea-expert skill. Educational; validate before any live use."

#include <SkillKit\SkillKit_Time.mqh>
#include <SkillKit\SkillKit_Risk.mqh>
#include <SkillKit\SkillKit_Trade.mqh>
#include <SkillKit\SkillKit_Structure.mqh>

input group "=== STRATEGY (example logic, no edge claimed) ==="
input ENUM_TIMEFRAMES   InpSignalTF       = PERIOD_M15; // Signal timeframe
input int               InpSwingK         = 5;          // Swing: closed bars required on each side
input int               InpLookbackBars   = 300;        // Bars scanned for swings
input int               InpEntryBufferPts = 0;          // Breakout buffer beyond B (points)
input int               InpStopBufferPts  = 0;          // Stop buffer beyond C (points)
input double            InpRewardRisk     = 1.5;        // Target distance / stop distance

input group "=== RISK ==="
input double            InpRiskMoney      = 0.0;        // Risk per trade in money (0 = use percent)
input double            InpRiskPercent    = 0.5;        // Risk per trade, % of balance
input double            InpCommissionLot  = 0.0;        // Round-turn commission per 1.0 lot (money)
input double            InpMarginUse      = 0.5;        // Max share of free margin one trade may use
input int               InpMaxSpreadPts   = 0;          // Max spread in points (0 = off)
input int               InpMaxTradesDay   = 2;          // Max entries per reset period (0 = unlimited)

input group "=== PROP FIRM RULES (copy from the firm's rule page) ==="
input double            InpStartBalance   = 0.0;        // Account start balance (0 = balance at first run)
input double            InpDailyLimit     = 0.0;        // Daily loss guard in money (0 = off)
input ENUM_SK_DAY_BASIS InpDailyBasis     = SK_DAY_BASIS_EQUITY; // Daily reference: balance / equity / max
input ENUM_SK_ZONE      InpResetZone      = SK_ZONE_UTC;// Daily reset time zone
input int               InpResetHour      = 0;          // Daily reset hour in that zone
input int               InpResetMinute    = 0;          // Daily reset minute
input double            InpMaxLoss        = 0.0;        // Max loss from start balance (0 = off)
input double            InpFloatShield    = 0.0;        // Close all at this floating loss (0 = off)
input double            InpProfitTarget   = 0.0;        // Stop trading at this profit (0 = off)

input group "=== TIME (hours in UTC) ==="
input ENUM_SK_SERVER_TZ InpServerTz       = SK_TZ_GMT2_EU_DST; // Server time model: MEASURE it with SkillKit_ServerTimeProbe
input int               InpFixedGmtOffset = 2;          // Server GMT offset for SK_TZ_FIXED / tester AUTO
input int               InpSessionStartH  = 7;          // Entries allowed from (UTC hour)
input int               InpSessionEndH    = 16;         // Entries allowed until (UTC hour, exclusive)
input int               InpFlatHourUtc    = 20;         // Close all positions at (UTC hour, -1 = off)
input int               InpFlatMinuteUtc  = 50;         // Close all positions at (UTC minute)
input int               InpFlatBeforeEnd  = 10;         // Close all N minutes before the symbol's session end (-1 = off)
input int               InpNoEntryBeforeEnd = 60;       // No entries in the last N minutes of a session

input group "=== EA ==="
input ulong             InpMagic          = 260513;     // Magic number (unique per EA instance)
input int               InpDeviationPts   = 20;         // Max slippage (points)
input string            InpComment        = "";         // Order comment
input int               InpMinTestTrades  = 100;        // OnTester: fewer trades -> criterion 0

CSkClock     g_clock;
CSkPropGuard g_guard;
CSkTrader    g_trader;
CSkNewBar    g_bar;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpSwingK < 1 || InpLookbackBars < 4 * InpSwingK + 4 || InpRewardRisk <= 0.0)
     {
      Print("[INIT] Invalid strategy inputs");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskMoney <= 0.0 && (InpRiskPercent <= 0.0 || InpRiskPercent > 5.0))
     {
      Print("[INIT] Risk must be set: money > 0, or 0 < percent <= 5");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMarginUse <= 0.0 || InpMarginUse > 1.0)
     {
      Print("[INIT] InpMarginUse must be in (0, 1]");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_clock.Init(InpServerTz, InpFixedGmtOffset);
   if(!g_trader.Init(_Symbol, InpMagic, (ulong)InpDeviationPts))
      return INIT_FAILED;
   if(!g_guard.Init(GetPointer(g_clock), InpMagic, InpStartBalance, InpDailyLimit, InpDailyBasis,
                    InpResetZone, InpResetHour, InpResetMinute, InpMaxLoss, InpFloatShield, InpProfitTarget))
      return INIT_FAILED;
   g_bar.Init(_Symbol, InpSignalTF);
   if(!EventSetTimer(1))
      Print("[INIT] Timer not available; daily snapshot will be taken on ticks only");
   PrintFormat("[INIT] %s %s | start balance %.2f | server GMT%+d now", _Symbol, EnumToString(InpSignalTF),
               g_guard.StartBalance(), g_clock.ServerOffsetSec(TimeCurrent()) / 3600);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Guards run on every tick and every second.                       |
//+------------------------------------------------------------------+
bool EnforceGuards(void)
  {
   g_guard.Update();
   if(g_guard.ShieldHit())
      g_trader.CloseAll("floating-loss shield");
   if(g_guard.Halted())
     {
      if(g_trader.Count() > 0)
         g_trader.CloseAll(g_guard.TargetReached() ? "profit target lock" : "loss limit");
      return false;
     }
   if(g_trader.Count() > 0)
     {
      int now  = SkMinuteOfDay(g_clock.UtcNow());
      int flat = InpFlatHourUtc * 60 + InpFlatMinuteUtc;
      //--- flat from the flat time until the session reopens (window may wrap past midnight)
      if(InpFlatHourUtc >= 0 && SkInWindow(now, flat, InpSessionStartH * 60))
         g_trader.CloseAll("flat time");
      //--- and before the broker's scheduled session end (daily break, Friday close)
      int left = SkMinutesToSessionEnd(_Symbol, TimeCurrent());
      if(InpFlatBeforeEnd >= 0 && left >= 0 && left <= InpFlatBeforeEnd)
         g_trader.CloseAll("session end");
     }
   return true;
  }

void OnTimer()
  {
   EnforceGuards();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!EnforceGuards())
      return;
   if(!g_bar.IsNew())
      return;
   EvaluateSignal();
  }

//+------------------------------------------------------------------+
int EntriesThisPeriod(void)
  {
   datetime from = g_clock.UtcToServer(g_guard.PeriodStartUtc());
   if(!HistorySelect(from, TimeCurrent() + 60))
      return 0;
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic
         && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol
         && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
void EvaluateSignal(void)
  {
   if(g_trader.Count() > 0)
      return;
   int now = SkMinuteOfDay(g_clock.UtcNow());
   if(!SkInWindow(now, InpSessionStartH * 60, InpSessionEndH * 60))
      return;
   int left = SkMinutesToSessionEnd(_Symbol, TimeCurrent());
   if(left < 0 || left <= InpNoEntryBeforeEnd)
      return;
   if(InpMaxTradesDay > 0 && EntriesThisPeriod() >= InpMaxTradesDay)
      return;
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
      return;

   SkSwing sw[];
   if(SkRecentSwings(_Symbol, InpSignalTF, InpSwingK, InpLookbackBars, sw, 3) < 3)
      return;
   SkSwing c = sw[0], b = sw[1], a = sw[2];

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double close1 = iClose(_Symbol, InpSignalTF, 1);
   double close2 = iClose(_Symbol, InpSignalTF, 2);
   if(close1 == 0.0 || close2 == 0.0)
      return;

   ENUM_ORDER_TYPE type;
   double stop;
   if(a.type == -1 && b.type == 1 && c.type == -1 && c.price > a.price && c.price < b.price)
     {
      double level = b.price + InpEntryBufferPts * point;
      if(!(close1 > level && close2 <= level))
         return;
      type = ORDER_TYPE_BUY;
      stop = c.price - InpStopBufferPts * point;
     }
   else
      if(a.type == 1 && b.type == -1 && c.type == 1 && c.price < a.price && c.price > b.price)
        {
         double level = b.price - InpEntryBufferPts * point;
         if(!(close1 < level && close2 >= level))
            return;
         type = ORDER_TYPE_SELL;
         stop = c.price + InpStopBufferPts * point;
        }
      else
         return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   double entry = (type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   double dist  = (type == ORDER_TYPE_BUY) ? entry - stop : stop - entry;
   if(dist <= 2 * point)
      return; // price already beyond the stop
   double target = (type == ORDER_TYPE_BUY) ? entry + InpRewardRisk * dist : entry - InpRewardRisk * dist;

   double wanted = (InpRiskMoney > 0.0) ? InpRiskMoney : AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double budget = g_guard.RiskBudget(wanted, InpMagic);
   double lots   = SkLotsForRisk(_Symbol, type, entry, stop, budget, InpCommissionLot);
   if(lots <= 0.0)
     {
      PrintFormat("[SKIP] %s setup: budget %.2f too small for a stop %s away", EnumToString(type), budget, DoubleToString(dist, _Digits));
      return;
     }
   if(!SkMarginOk(_Symbol, type, lots, entry, InpMarginUse))
     {
      Print("[SKIP] Not enough free margin");
      return;
     }
   if(g_trader.Market(type, lots, stop, target, InpComment))
      PrintFormat("[ENTRY] %s %.2f lots | stop %s | target %s | risk budget %.2f", EnumToString(type), lots,
                  DoubleToString(stop, _Digits), DoubleToString(target, _Digits), budget);
  }

//+------------------------------------------------------------------+
//| Optimization criterion: net profit / equity drawdown (money),    |
//| zero for small samples or drawdown above 20% so the optimizer    |
//| cannot select a lucky handful of trades.                         |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   double ddPct  = TesterStatistics(STAT_EQUITYDD_PERCENT);  // percent
   double ddMoney = TesterStatistics(STAT_EQUITY_DD);        // money
   double net    = TesterStatistics(STAT_PROFIT);
   if(trades < InpMinTestTrades || ddPct > 20.0 || net <= 0.0)
      return 0.0;
   return net / MathMax(ddMoney, 1.0);
  }
//+------------------------------------------------------------------+
