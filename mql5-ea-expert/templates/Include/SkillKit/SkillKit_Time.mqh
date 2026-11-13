//+------------------------------------------------------------------+
//| SkillKit_Time.mqh                                                |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: server/UTC/New York/Prague time, DST, per-TF new bar    |
//+------------------------------------------------------------------+
// Why this file exists:
//  - Broker server time is NOT UTC and usually shifts with DST (GMT+2 / GMT+3).
//  - TimeGMT() is NOT modelled by the Strategy Tester: there it returns the
//    tester's server time. Session logic built on TimeGMT() therefore behaves
//    differently in backtest and live. Use CSkClock instead.
//  - Market events (NY open, prop-firm daily resets) follow a local time zone
//    with its own DST calendar.
#ifndef SKILLKIT_TIME_MQH
#define SKILLKIT_TIME_MQH

enum ENUM_SK_SERVER_TZ
  {
   SK_TZ_GMT2_US_DST = 0, // GMT+2, GMT+3 during US DST (most "New York close" brokers)
   SK_TZ_GMT2_EU_DST = 1, // GMT+2, GMT+3 during EU DST
   SK_TZ_FIXED       = 2, // fixed offset from InpFixedGmtOffset
   SK_TZ_AUTO_LIVE   = 3  // live: TimeTradeServer()-TimeGMT(); tester: fixed offset
  };

enum ENUM_SK_ZONE
  {
   SK_ZONE_UTC      = 0, // UTC
   SK_ZONE_NEW_YORK = 1, // America/New_York (US DST)
   SK_ZONE_PRAGUE   = 2, // Europe/Prague, CE(S)T (EU DST)
   SK_ZONE_SERVER   = 3  // broker server time
  };

//--- 00:00 UTC of the n-th Sunday of a month (n = 1..4) or the last Sunday (n = -1)
datetime SkNthSunday(const int year, const int month, const int n)
  {
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year;
   d.mon  = month;
   d.day  = 1;
   datetime first = StructToTime(d);
   MqlDateTime f;
   TimeToStruct(first, f);
   int toSunday = (7 - f.day_of_week) % 7;
   if(n > 0)
      return first + (toSunday + 7 * (n - 1)) * 86400;
//--- last Sunday: first Sunday of next month minus 7 days
   int ny = (month == 12) ? year + 1 : year;
   int nm = (month == 12) ? 1 : month + 1;
   return SkNthSunday(ny, nm, 1) - 7 * 86400;
  }

//--- US DST: 2nd Sunday of March 07:00 UTC .. 1st Sunday of November 06:00 UTC
bool SkIsUsDst(const datetime utc)
  {
   MqlDateTime t;
   TimeToStruct(utc, t);
   datetime start = SkNthSunday(t.year, 3, 2) + 7 * 3600;
   datetime end   = SkNthSunday(t.year, 11, 1) + 6 * 3600;
   return (utc >= start && utc < end);
  }

//--- EU DST: last Sunday of March 01:00 UTC .. last Sunday of October 01:00 UTC
bool SkIsEuDst(const datetime utc)
  {
   MqlDateTime t;
   TimeToStruct(utc, t);
   datetime start = SkNthSunday(t.year, 3, -1) + 3600;
   datetime end   = SkNthSunday(t.year, 10, -1) + 3600;
   return (utc >= start && utc < end);
  }

//--- offset (seconds) of a zone at a given UTC instant
int SkZoneOffsetSec(const ENUM_SK_ZONE zone, const datetime utc)
  {
   if(zone == SK_ZONE_NEW_YORK)
      return (SkIsUsDst(utc) ? -4 : -5) * 3600;
   if(zone == SK_ZONE_PRAGUE)
      return (SkIsEuDst(utc) ? 2 : 1) * 3600;
   return 0;
  }

//+------------------------------------------------------------------+
//| Converts between broker server time and UTC, identically in the  |
//| Strategy Tester and live (except SK_TZ_AUTO_LIVE, see enum).     |
//+------------------------------------------------------------------+
class CSkClock
  {
private:
   ENUM_SK_SERVER_TZ m_mode;
   int               m_fixedSec;

public:
                     CSkClock(void) : m_mode(SK_TZ_GMT2_US_DST), m_fixedSec(2 * 3600) {}

   void              Init(const ENUM_SK_SERVER_TZ mode, const int fixedGmtOffsetHours)
     {
      m_mode     = mode;
      m_fixedSec = fixedGmtOffsetHours * 3600;
      if(m_mode == SK_TZ_AUTO_LIVE && MQLInfoInteger(MQL_TESTER))
         PrintFormat("[TIME] Tester cannot measure the server offset (TimeGMT is not modelled); using fixed GMT%+d", fixedGmtOffsetHours);
     }

   //--- server offset in seconds at a given server time
   int               ServerOffsetSec(const datetime serverTime) const
     {
      switch(m_mode)
        {
         case SK_TZ_GMT2_US_DST:
            return SkIsUsDst(serverTime - 2 * 3600) ? 3 * 3600 : 2 * 3600;
         case SK_TZ_GMT2_EU_DST:
            return SkIsEuDst(serverTime - 2 * 3600) ? 3 * 3600 : 2 * 3600;
         case SK_TZ_AUTO_LIVE:
           {
            if(MQLInfoInteger(MQL_TESTER))
               return m_fixedSec;
            long raw = (long)(TimeTradeServer() - TimeGMT());
            return (int)(MathRound(raw / 900.0) * 900); // brokers use 15-minute granularity at most
           }
         default:
            return m_fixedSec;
        }
     }

   datetime          ServerToUtc(const datetime serverTime) const { return serverTime - ServerOffsetSec(serverTime); }
   datetime          UtcNow(void) const                          { return ServerToUtc(TimeCurrent()); }

   //--- UTC -> server (iterate once so the DST decision uses the right side of the switch)
   datetime          UtcToServer(const datetime utc) const
     {
      datetime guess = utc + 2 * 3600;
      return utc + ServerOffsetSec(guess);
     }

   //--- local wall-clock time of a zone
   datetime          UtcToZone(const ENUM_SK_ZONE zone, const datetime utc) const
     {
      if(zone == SK_ZONE_SERVER)
         return UtcToServer(utc);
      return utc + SkZoneOffsetSec(zone, utc);
     }
  };

//--- minute of day (0..1439) of a time value
int SkMinuteOfDay(const datetime t)
  {
   return (int)((t % 86400) / 60);
  }

//--- [startMin, endMin) window that may wrap past midnight
bool SkInWindow(const int minuteOfDay, const int startMin, const int endMin)
  {
   if(startMin == endMin)
      return false;
   if(startMin < endMin)
      return (minuteOfDay >= startMin && minuteOfDay < endMin);
   return (minuteOfDay >= startMin || minuteOfDay < endMin);
  }

//+------------------------------------------------------------------+
//| New-bar detector. One instance per symbol/timeframe: a single    |
//| global "last bar time" shared by several timeframes is a bug.    |
//+------------------------------------------------------------------+
class CSkNewBar
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   datetime          m_last;

public:
                     CSkNewBar(void) : m_symbol(""), m_tf(PERIOD_CURRENT), m_last(0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      m_symbol = symbol;
      m_tf     = tf;
      m_last   = 0;
     }

   //--- true once per new bar; false while history is not ready
   bool              IsNew(void)
     {
      datetime t = iTime(m_symbol, m_tf, 0);
      if(t == 0)
         return false;
      if(t == m_last)
         return false;
      m_last = t;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| Minutes until the symbol's current trade session ends, from the  |
//| symbol's session table (server time); -1 = market closed now.   |
//| A session ending at 24:00 that continues at 00:00 the next day   |
//| is joined. Holiday early closes are NOT in the session table:    |
//| a position can still be trapped by an unscheduled close.         |
//+------------------------------------------------------------------+
int SkMinutesToSessionEnd(const string symbol, const datetime serverTime)
  {
   MqlDateTime d;
   TimeToStruct(serverTime, d);
   int tod = (int)(serverTime % 86400);
   datetime from = 0, to = 0;
   for(int i = 0; i < 16; i++)
     {
      if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)d.day_of_week, i, from, to))
         break;
      int f = (int)from, t = (int)to;   // seconds from 00:00; 24:00 is 86400
      if(tod < f || tod >= t)
         continue;
      int remaining = t - tod;
      int dow = d.day_of_week;
      for(int guard = 0; t >= 86400 && guard < 7; guard++)
        {
         dow = (dow + 1) % 7;
         datetime f2 = 0, t2 = 0;
         if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)dow, 0, f2, t2) || (int)f2 != 0)
            break;
         t = (int)t2;
         remaining += t;
        }
      return remaining / 60;
     }
   return -1;
  }

#endif // SKILLKIT_TIME_MQH
