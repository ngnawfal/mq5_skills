//+------------------------------------------------------------------+
//| SkillKit_ServerTimeProbe.mq5                                     |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: measure the broker's server GMT offset and DST calendar |
//|          from price data instead of assuming it                  |
//+------------------------------------------------------------------+
// Run it in the Strategy Tester (any model, 1 year or more) on an FX pair or
// gold. FX and spot metals pause daily at 17:00 New York. The last quote
// before each daily pause is mapped to 17:00 New York, which gives the server
// offset for that day. Output: one line per offset change, e.g.
//   [PROBE] 2026.03.29  pause 23:59 server -> server = GMT+3 (was GMT+2)  US DST:yes EU DST:yes
// Compare the change dates with the US (2nd Sun Mar / 1st Sun Nov) and EU
// (last Sun Mar / last Sun Oct) calendars, then pick ENUM_SK_SERVER_TZ.
// This EA never trades.
#property copyright "mql5-ea-expert"
#property link      "https://github.com/nawfdev/mq5_skills"
#property version   "3.00"
#property description "Measures server GMT offset and DST switches from the daily FX/metal pause."

#include <SkillKit\SkillKit_Time.mqh>

input int InpMinGapMinutes = 30; // A quote gap at least this long (and < 12 h) counts as the daily pause

datetime g_lastTick    = 0;
int      g_offset      = 99;   // confirmed offset (hours)
int      g_candidate   = 99;   // offset seen once, waiting for confirmation
datetime g_candTime    = 0;
int      g_days        = 0;
int      g_earlyCloses = 0;

//+------------------------------------------------------------------+
//| Offset (hours) that puts a server time nearest to 17:00 New York  |
//+------------------------------------------------------------------+
int OffsetAtNyClose(const datetime serverTime, long &errSec)
  {
   int best = 99;
   errSec = 86400;
   for(int h = -12; h <= 14; h++)
     {
      datetime utc = serverTime - h * 3600;
      datetime ny  = utc + SkZoneOffsetSec(SK_ZONE_NEW_YORK, utc);
      long tod = (long)(ny % 86400);
      long err = MathAbs(tod - 17 * 3600);
      err = MathMin(err, 86400 - err);
      if(err < errSec)
        {
         errSec = err;
         best   = h;
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t))
      return;
   datetime now = t.time;
   if(g_lastTick > 0)
     {
      long gap = (long)(now - g_lastTick);
      if(gap >= InpMinGapMinutes * 60 && gap < 12 * 3600)
        {
         long err = 0;
         int  off = OffsetAtNyClose(g_lastTick, err); // the pause starts at the last quote
         g_days++;
         if(err > 45 * 60 || off == g_offset)
           {
            g_candidate = 99;
           }
         else
            if(off == g_candidate || g_offset == 99)
              {
               //--- seen on two consecutive pauses (or first measurement): a real offset change
               datetime utcPause = g_lastTick - off * 3600;
               PrintFormat("[PROBE] %s  pause %s server -> server = GMT%+d (was %s)  US DST:%s EU DST:%s",
                           TimeToString(g_candTime > 0 ? g_candTime : g_lastTick, TIME_DATE),
                           TimeToString(g_lastTick, TIME_MINUTES), off,
                           g_offset == 99 ? "n/a" : StringFormat("GMT%+d", g_offset),
                           SkIsUsDst(utcPause) ? "yes" : "no", SkIsEuDst(utcPause) ? "yes" : "no");
               if(g_candidate != 99)
                  g_earlyCloses--;   // the previous "irregular" pause was the first day of this change
               g_offset    = off;
               g_candidate = 99;
               g_candTime  = 0;
              }
            else
              {
               //--- one-off: an early close (US holiday) unless the next pause confirms it
               g_earlyCloses++;
               g_candidate = off;
               g_candTime  = g_lastTick;
               PrintFormat("[PROBE] %s  irregular pause at %s server (early close / holiday?)",
                           TimeToString(g_lastTick, TIME_DATE), TimeToString(g_lastTick, TIME_MINUTES));
              }
        }
     }
   g_lastTick = now;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("[PROBE] done: %d daily pauses, %d irregular (early closes), last confirmed offset GMT%+d",
               g_days, g_earlyCloses, g_offset);
  }
//+------------------------------------------------------------------+
