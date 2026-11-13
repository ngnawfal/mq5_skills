//+------------------------------------------------------------------+
//| SkillKit_Risk.mqh                                                |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: money-at-risk sizing, volume rounding, prop-firm guard  |
//+------------------------------------------------------------------+
// Rules encoded here (each one is a real bug seen in generated EAs):
//  1. Risk per lot comes from OrderCalcProfit(), not from "pips * pip value"
//     guesses: it is exact for gold, indices, crypto and cross currencies.
//  2. Volume is rounded DOWN to the volume step. If the result is below the
//     minimum volume the trade is SKIPPED. Clamping up to the minimum volume
//     silently multiplies the risk (a $14 budget became a $92 loss).
//  3. Prop-firm limits are measured on ACCOUNT equity against the firm's own
//     reference (start balance, daily snapshot at the firm's reset time),
//     and the daily snapshot survives EA restarts.
//  4. New risk is sized from the REMAINING room: daily room, total room,
//     floating-loss shield room, minus the risk still open to other stops.
#ifndef SKILLKIT_RISK_MQH
#define SKILLKIT_RISK_MQH

#include "SkillKit_Time.mqh"

//--- decimals implied by a volume step (0.01 -> 2, 0.1 -> 1, 1 -> 0)
int SkStepDigits(const double step)
  {
   if(step <= 0.0)
      return 2;
   int digits = 0;
   double s = step;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1e-9)
     {
      s *= 10.0;
      digits++;
     }
   return digits;
  }

//--- round a volume DOWN to the step and cap it at the maximum; no minimum clamp here
double SkVolumeFloor(const string symbol, const double volume)
  {
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0 || volume <= 0.0)
      return 0.0;
   double v = MathFloor(volume / step + 1e-7) * step; // epsilon: 0.30/0.01 must not become 29
   if(vmax > 0.0 && v > vmax)
      v = vmax;
   return NormalizeDouble(v, SkStepDigits(step));
  }

//--- money lost by 1.0 lot moving from entry to stop (account currency), > 0 on success
bool SkLossPerLot(const string symbol, const ENUM_ORDER_TYPE type, const double entry,
                  const double stop, double &lossPerLot)
  {
   lossPerLot = 0.0;
   double profit = 0.0;
   if(!OrderCalcProfit(type, symbol, 1.0, entry, stop, profit))
     {
      PrintFormat("[RISK] OrderCalcProfit failed for %s, error %d", symbol, GetLastError());
      return false;
     }
   lossPerLot = -profit;
   return (lossPerLot > 0.0);
  }

//+------------------------------------------------------------------+
//| Volume that loses at most riskMoney at the stop (commission      |
//| included). Returns 0 when even the minimum volume risks more:    |
//| the caller must skip the trade, never trade the minimum anyway.  |
//+------------------------------------------------------------------+
double SkLotsForRisk(const string symbol, const ENUM_ORDER_TYPE type, const double entry,
                     const double stop, const double riskMoney, const double commissionPerLot)
  {
   if(riskMoney <= 0.0)
      return 0.0;
   double lossPerLot = 0.0;
   if(!SkLossPerLot(symbol, type, entry, stop, lossPerLot))
      return 0.0;
   lossPerLot += MathMax(0.0, commissionPerLot);
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double raw  = riskMoney / lossPerLot;
   if(raw + 1e-9 < vmin)
     {
      PrintFormat("[RISK] Skip: minimum volume %.2f risks %.2f > budget %.2f", vmin, vmin * lossPerLot, riskMoney);
      return 0.0;
     }
   double v = SkVolumeFloor(symbol, raw);
   return (v + 1e-9 >= vmin) ? v : 0.0;
  }

//--- margin check with a safety factor (1.0 = all free margin, 0.5 = half)
bool SkMarginOk(const string symbol, const ENUM_ORDER_TYPE type, const double volume,
                const double price, const double useFraction)
  {
   double margin = 0.0;
   if(!OrderCalcMargin(type, symbol, volume, price, margin))
     {
      PrintFormat("[RISK] OrderCalcMargin failed for %s, error %d", symbol, GetLastError());
      return false;
     }
   return (margin <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * useFraction);
  }

//+------------------------------------------------------------------+
//| Money still at risk to the stops of this EA's positions.         |
//| Returns -1 when a position has no stop (unbounded risk).         |
//+------------------------------------------------------------------+
double SkOpenRiskToStops(const ulong magic)
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      string sym  = PositionGetString(POSITION_SYMBOL);
      double sl   = PositionGetDouble(POSITION_SL);
      double cur  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0)
         return -1.0;
      ENUM_ORDER_TYPE type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double lossPerLot = 0.0;
      if(SkLossPerLot(sym, type, cur, sl, lossPerLot))
         total += lossPerLot * vol;
     }
   return total;
  }

enum ENUM_SK_DAY_BASIS
  {
   SK_DAY_BASIS_BALANCE = 0, // balance at the reset time
   SK_DAY_BASIS_EQUITY  = 1, // equity at the reset time
   SK_DAY_BASIS_MAX     = 2  // max(balance, equity) at the reset time
  };

//+------------------------------------------------------------------+
//| Prop-firm guard. All money values are in account currency.       |
//| 0 disables a limit. Configure it from the firm's rule page, not  |
//| from memory: reset time, reset time zone, balance vs equity.     |
//+------------------------------------------------------------------+
class CSkPropGuard
  {
private:
   CSkClock         *m_clock;
   string            m_gv;            // global-variable prefix, survives restarts
   double            m_start;         // account start balance (reference for max loss / target)
   double            m_dailyLimit;
   double            m_maxLoss;
   double            m_floatShield;
   double            m_target;
   ENUM_SK_DAY_BASIS m_basis;
   ENUM_SK_ZONE      m_resetZone;
   int               m_resetMinute;
   long              m_dayKey;
   double            m_dayBase;
   bool              m_haltTotal;

   long              DayKeyAt(const datetime utc) const
     {
      datetime local = m_clock.UtcToZone(m_resetZone, utc);
      return (long)((local - m_resetMinute * 60) / 86400);
     }

   double            BasisValue(void) const
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_basis == SK_DAY_BASIS_BALANCE)
         return bal;
      if(m_basis == SK_DAY_BASIS_EQUITY)
         return eq;
      return MathMax(bal, eq);
     }

public:
                     CSkPropGuard(void) : m_clock(NULL), m_gv(""), m_start(0), m_dailyLimit(0), m_maxLoss(0),
                     m_floatShield(0), m_target(0), m_basis(SK_DAY_BASIS_EQUITY), m_resetZone(SK_ZONE_UTC),
                     m_resetMinute(0), m_dayKey(-1), m_dayBase(0), m_haltTotal(false) {}

   bool              Init(CSkClock *clock, const ulong magic, const double startBalance,
                          const double dailyLimit, const ENUM_SK_DAY_BASIS basis,
                          const ENUM_SK_ZONE resetZone, const int resetHour, const int resetMinute,
                          const double maxLoss, const double floatShield, const double target)
     {
      if(clock == NULL)
         return false;
      m_clock       = clock;
      m_gv          = StringFormat("SK_%I64d_%I64u_", AccountInfoInteger(ACCOUNT_LOGIN), magic);
      m_dailyLimit  = dailyLimit;
      m_basis       = basis;
      m_resetZone   = resetZone;
      m_resetMinute = resetHour * 60 + resetMinute;
      m_maxLoss     = maxLoss;
      m_floatShield = floatShield;
      m_target      = target;
      //--- start balance: input, else persisted value, else balance now (persisted for restarts)
      if(startBalance > 0.0)
         m_start = startBalance;
      else
         if(GlobalVariableCheck(m_gv + "start"))
            m_start = GlobalVariableGet(m_gv + "start");
         else
            m_start = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(m_gv + "start", m_start);
      //--- daily snapshot: restore if the EA restarted inside the same reset period
      long key = DayKeyAt(m_clock.UtcNow());
      if(GlobalVariableCheck(m_gv + "daykey") && (long)GlobalVariableGet(m_gv + "daykey") == key
         && GlobalVariableCheck(m_gv + "daybase"))
        {
         m_dayKey  = key;
         m_dayBase = GlobalVariableGet(m_gv + "daybase");
         PrintFormat("[PROP] Restored daily base %.2f for the current period", m_dayBase);
        }
      else
         Update();
      return true;
     }

   //--- call from OnTick AND OnTimer so the snapshot is taken close to the reset time
   void              Update(void)
     {
      long key = DayKeyAt(m_clock.UtcNow());
      if(key == m_dayKey)
         return;
      m_dayKey  = key;
      m_dayBase = BasisValue();
      GlobalVariableSet(m_gv + "daykey", (double)key);
      GlobalVariableSet(m_gv + "daybase", m_dayBase);
      PrintFormat("[PROP] New period, daily base %.2f", m_dayBase);
     }

   double            StartBalance(void) const { return m_start; }
   double            DayBase(void) const      { return m_dayBase; }
   double            DayLoss(void) const      { return m_dayBase - AccountInfoDouble(ACCOUNT_EQUITY); }
   double            TotalLoss(void) const    { return m_start - AccountInfoDouble(ACCOUNT_EQUITY); }
   double            FloatingLoss(void) const { return AccountInfoDouble(ACCOUNT_BALANCE) - AccountInfoDouble(ACCOUNT_EQUITY); }

   bool              DailyBreached(void) const   { return m_dailyLimit > 0.0 && DayLoss() >= m_dailyLimit; }

   //--- UTC instant at which the current reset period started
   datetime          PeriodStartUtc(void) const
     {
      datetime utc   = m_clock.UtcNow();
      datetime local = m_clock.UtcToZone(m_resetZone, utc);
      long     key   = (long)((local - m_resetMinute * 60) / 86400);
      datetime startLocal = (datetime)(key * 86400 + m_resetMinute * 60);
      return utc - (local - startLocal);
     }

   bool              TotalBreached(void) const   { return m_maxLoss > 0.0 && TotalLoss() >= m_maxLoss; }
   bool              ShieldHit(void) const       { return m_floatShield > 0.0 && FloatingLoss() >= m_floatShield; }
   bool              TargetReached(void) const   { return m_target > 0.0 && (AccountInfoDouble(ACCOUNT_EQUITY) - m_start) >= m_target; }

   //--- latch: total breach / target stops trading until the EA is reconfigured
   bool              Halted(void)
     {
      if(TotalBreached() || TargetReached())
         m_haltTotal = true;
      return m_haltTotal || DailyBreached();
     }

   //--- largest money risk a NEW trade may take without being able to breach a limit at its stop
   double            RiskBudget(const double wanted, const ulong magic) const
     {
      double room = wanted;
      double open = SkOpenRiskToStops(magic);
      if(open < 0.0)
         return 0.0; // an open position without a stop: risk is unbounded, take no more
      if(m_dailyLimit > 0.0)
         room = MathMin(room, m_dailyLimit - DayLoss() - open);
      if(m_maxLoss > 0.0)
         room = MathMin(room, m_maxLoss - TotalLoss() - open);
      if(m_floatShield > 0.0)
         room = MathMin(room, m_floatShield - FloatingLoss() - open);
      return MathMax(0.0, room);
     }
  };

#endif // SKILLKIT_RISK_MQH
