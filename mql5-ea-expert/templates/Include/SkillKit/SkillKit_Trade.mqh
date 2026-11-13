//+------------------------------------------------------------------+
//| SkillKit_Trade.mqh                                               |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: order execution with broker-constraint checks           |
//+------------------------------------------------------------------+
// Rules encoded here:
//  - Prices are rounded to SYMBOL_TRADE_TICK_SIZE (indices often tick in 0.25),
//    not only NormalizeDouble(_Digits).
//  - Stops respect SYMBOL_TRADE_STOPS_LEVEL; modifications respect
//    SYMBOL_TRADE_FREEZE_LEVEL.
//  - Filling mode comes from the symbol (SetTypeFillingBySymbol), margin mode
//    from the account (hedging vs netting).
//  - Positions are always selected and closed BY TICKET, filtered by magic and
//    symbol. PositionClose(symbol) can hit another EA's position on hedging.
//  - Partial closes are only sent when both the closed part and the remainder
//    are >= the minimum volume (70% of a 0.01-lot position cannot be closed).
#ifndef SKILLKIT_TRADE_MQH
#define SKILLKIT_TRADE_MQH

#include <Trade\Trade.mqh>
#include "SkillKit_Risk.mqh"

double SkNormalizePrice(const string symbol, const double price)
  {
   double tick   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(tick > 0.0)
      return NormalizeDouble(MathRound(price / tick) * tick, digits);
   return NormalizeDouble(price, digits);
  }

class CSkTrader
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;
   datetime          m_retryAfter;   // no close attempts before this time (market closed)
   bool              m_closedNoted;

   bool              ResultOk(const string what)
     {
      uint rc = m_trade.ResultRetcode();
      if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)
         return true;
      PrintFormat("[TRADE] %s failed: retcode %u (%s), last error %d", what, rc,
                  m_trade.ResultRetcodeDescription(), GetLastError());
      return false;
     }

public:
                     CSkTrader(void) : m_symbol(""), m_magic(0), m_retryAfter(0), m_closedNoted(false) {}

   bool              Init(const string symbol, const ulong magic, const ulong deviationPoints)
     {
      m_symbol = symbol;
      m_magic  = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviationPoints);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      if(!m_trade.SetTypeFillingBySymbol(symbol))
        {
         PrintFormat("[TRADE] Could not set filling mode for %s", symbol);
         return false;
        }
      return true;
     }

   //--- distance check against the broker's minimum stop distance
   bool              StopsValid(const ENUM_ORDER_TYPE type, const double sl, const double tp) const
     {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return false;
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minD  = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      bool   buy   = (type == ORDER_TYPE_BUY);
      double ref   = buy ? tick.bid : tick.ask;    // a buy is closed at bid, a sell at ask
      if(sl > 0.0 && (buy ? ref - sl : sl - ref) <= minD)
         return false;
      if(tp > 0.0 && (buy ? tp - ref : ref - tp) <= minD)
         return false;
      return true;
     }

   //--- market order; sl/tp are absolute prices (0 = none)
   bool              Market(const ENUM_ORDER_TYPE type, const double volume, double sl, double tp, const string comment)
     {
      if(type != ORDER_TYPE_BUY && type != ORDER_TYPE_SELL)
         return false;
      sl = (sl > 0.0) ? SkNormalizePrice(m_symbol, sl) : 0.0;
      tp = (tp > 0.0) ? SkNormalizePrice(m_symbol, tp) : 0.0;
      if(!StopsValid(type, sl, tp))
        {
         PrintFormat("[TRADE] Stops too close to price (stops level %I64d points)",
                     SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL));
         return false;
        }
      bool sent = (type == ORDER_TYPE_BUY)
                  ? m_trade.Buy(volume, m_symbol, 0.0, sl, tp, comment)
                  : m_trade.Sell(volume, m_symbol, 0.0, sl, tp, comment);
      return ResultOk("market order") && sent;
     }

   //--- count this EA's positions on this symbol
   int               Count(void) const
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) == m_magic && PositionGetString(POSITION_SYMBOL) == m_symbol)
            n++;
        }
      return n;
     }

   //--- close all of this EA's positions on this symbol, by ticket; returns positions still open.
   //--- While the market is closed it waits instead of hammering the server every tick/second.
   int               CloseAll(const string reason)
     {
      if(TimeCurrent() < m_retryAfter)
         return Count();
      if(SkMinutesToSessionEnd(m_symbol, TimeCurrent()) < 0)
        {
         if(!m_closedNoted && Count() > 0)
            PrintFormat("[TRADE] %s: market closed, %d position(s) wait for the reopen", reason, Count());
         m_closedNoted = true;
         m_retryAfter  = TimeCurrent() + 60;
         return Count();
        }
      m_closedNoted = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(m_trade.PositionClose(ticket))
            PrintFormat("[EXIT] %s: closed #%I64u", reason, ticket);
         else
           {
            ResultOk("close #" + IntegerToString((long)ticket));
            if(m_trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED)
               m_retryAfter = TimeCurrent() + 60;
           }
        }
      return Count();
     }

   //--- move SL only in the favourable direction, honouring stops and freeze levels
   bool              ImproveStop(const ulong ticket, double newSl)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      bool   buy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double curSl  = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      newSl = SkNormalizePrice(m_symbol, newSl);
      if(curSl > 0.0 && (buy ? newSl <= curSl + point / 2 : newSl >= curSl - point / 2))
         return false; // not an improvement
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return false;
      double ref    = buy ? tick.bid : tick.ask;
      double stops  = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double freeze = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
      double gap    = buy ? ref - newSl : newSl - ref;
      if(gap <= MathMax(stops, freeze))
         return false;
      if(curSl > 0.0 && MathAbs(ref - curSl) <= freeze)
         return false; // current stop is inside the freeze zone: modification forbidden
      bool sent = m_trade.PositionModify(ticket, newSl, tp);
      return ResultOk("modify #" + IntegerToString((long)ticket)) && sent;
     }

   //--- close a fraction only when the closed part and the remainder are both tradable volumes
   bool              ClosePartial(const ulong ticket, const double fraction)
     {
      if(!PositionSelectByTicket(ticket) || fraction <= 0.0 || fraction >= 1.0)
         return false;
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double vmin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double part = SkVolumeFloor(m_symbol, vol * fraction);
      if(part + 1e-9 < vmin || (vol - part) + 1e-9 < vmin)
        {
         PrintFormat("[TRADE] Partial close skipped: volume %.2f cannot be split (min %.2f)", vol, vmin);
         return false;
        }
      bool sent = m_trade.PositionClosePartial(ticket, part);
      return ResultOk("partial close") && sent;
     }
  };

#endif // SKILLKIT_TRADE_MQH
