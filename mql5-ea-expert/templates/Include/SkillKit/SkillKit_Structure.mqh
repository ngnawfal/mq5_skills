//+------------------------------------------------------------------+
//| SkillKit_Structure.mqh                                           |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: confirmed (non-repainting) swing points, price only     |
//+------------------------------------------------------------------+
// A swing high at bar s is only KNOWN after k bars to its right have closed.
// Any logic that "sees" a swing earlier is using the future (look-ahead) and
// will look excellent in a backtest and fail live. This scanner only uses
// closed bars (shift >= 1) and only pivots with k closed bars on both sides.
#ifndef SKILLKIT_STRUCTURE_MQH
#define SKILLKIT_STRUCTURE_MQH

struct SkSwing
  {
   datetime          time;
   double            price;
   int               type;   // +1 swing high, -1 swing low
   int               shift;  // bar shift on the scanned timeframe (1 = last closed bar)
  };

//+------------------------------------------------------------------+
//| Fills out[] with up to maxCount most recent confirmed swings,     |
//| newest first, alternating high/low. Consecutive swings of the     |
//| same type are merged into the more extreme one, so a swing is     |
//| only returned once an opposite swing older than it was found      |
//| (otherwise it could still change). Returns the count.             |
//| Ties: a pivot must beat older bars strictly and newer bars with   |
//| >=, so two equal highs produce exactly one swing.                 |
//+------------------------------------------------------------------+
int SkRecentSwings(const string symbol, const ENUM_TIMEFRAMES tf, const int k,
                   const int lookback, SkSwing &out[], const int maxCount)
  {
   ArrayResize(out, 0);
   if(k < 1 || maxCount < 1 || lookback < 2 * k + 2)
      return 0;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(symbol, tf, 0, lookback + 1, r);   // r[0] = forming bar, never a pivot or neighbour
   if(got < 2 * k + 2)
      return 0;
   SkSwing tmp[];
   int n = 0;
   for(int s = k + 1; s <= got - 1 - k && n <= maxCount; s++)
     {
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= k && (isHigh || isLow); j++)
        {
         // newer bars are s-j (smaller shift), older bars are s+j
         if(!(r[s].high >= r[s - j].high && r[s].high > r[s + j].high))
            isHigh = false;
         if(!(r[s].low <= r[s - j].low && r[s].low < r[s + j].low))
            isLow = false;
        }
      for(int pass = 0; pass < 2 && n <= maxCount; pass++)
        {
         int    type  = (pass == 0) ? 1 : -1;
         bool   found = (pass == 0) ? isHigh : isLow;
         double price = (pass == 0) ? r[s].high : r[s].low;
         if(!found)
            continue;
         if(n > 0 && tmp[n - 1].type == type)
           {
            if((type == 1 && price > tmp[n - 1].price) || (type == -1 && price < tmp[n - 1].price))
              {
               tmp[n - 1].price = price;
               tmp[n - 1].time  = r[s].time;
               tmp[n - 1].shift = s;
              }
            continue;
           }
         ArrayResize(tmp, n + 1);
         tmp[n].type  = type;
         tmp[n].price = price;
         tmp[n].time  = r[s].time;
         tmp[n].shift = s;
         n++;
        }
     }
//--- the oldest collected swing is final only if an older opposite swing closed it
   int finalCount = (n > maxCount) ? maxCount : MathMax(0, n - 1);
   ArrayResize(out, finalCount);
   for(int i = 0; i < finalCount; i++)
      out[i] = tmp[i];
   return finalCount;
  }

#endif // SKILLKIT_STRUCTURE_MQH
