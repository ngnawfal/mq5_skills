//+------------------------------------------------------------------+
//| SkillKit_Swings.mq5                                              |
//| Project: mql5-ea-expert SkillKit v3.0                            |
//| Purpose: reference indicator - confirmed swing highs/lows        |
//+------------------------------------------------------------------+
// Demonstrates the two things most generated indicators get wrong:
//  1. Indexing: OnCalculate arrays are NOT series by default (0 = oldest,
//     rates_total-1 = forming bar). Never call ArraySetAsSeries(close, true)
//     and then loop i = prev_calculated .. rates_total as if they were not.
//  2. Confirmation lag: a swing at bar i is only drawn once InpK bars to its
//     right have CLOSED. The arrow appears InpK bars late - that is the truth
//     an EA can trade on. Drawing it earlier repaints and lies in backtests.
#property copyright "mql5-ea-expert"
#property link      "https://github.com/nawfdev/mq5_skills"
#property version   "3.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "Swing high (confirmed)"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrTomato
#property indicator_width1  1
#property indicator_label2  "Swing low (confirmed)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1

input int InpK = 5; // Closed bars required on each side of a swing

double g_high[];
double g_low[];

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpK < 1)
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0, g_high, INDICATOR_DATA);
   SetIndexBuffer(1, g_low, INDICATOR_DATA);
   ArraySetAsSeries(g_high, false);
   ArraySetAsSeries(g_low, false);
   PlotIndexSetInteger(0, PLOT_ARROW, 234);
   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   IndicatorSetString(INDICATOR_SHORTNAME, "SkillKit Swings(" + IntegerToString(InpK) + ")");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2 * InpK + 2)
      return 0;
//--- newest pivot that has InpK CLOSED bars to its right (rates_total-1 is still forming)
   int lastPivot = rates_total - 2 - InpK;
//--- a new closed bar confirms the pivot InpK bars back: recompute that far, plus one bar of margin
   int start = (prev_calculated == 0) ? 0 : MathMax(0, prev_calculated - InpK - 2);
   for(int i = start; i < rates_total; i++)
     {
      g_high[i] = EMPTY_VALUE;
      g_low[i]  = EMPTY_VALUE;
      if(i < InpK || i > lastPivot)
         continue;
      bool isHigh = true, isLow = true;
      for(int j = 1; j <= InpK && (isHigh || isLow); j++)
        {
         //--- older bars (i-j) must be beaten strictly, newer bars (i+j) with >=: equal highs give one swing
         if(!(high[i] > high[i - j] && high[i] >= high[i + j]))
            isHigh = false;
         if(!(low[i] < low[i - j] && low[i] <= low[i + j]))
            isLow = false;
        }
      if(isHigh)
         g_high[i] = high[i];
      if(isLow)
         g_low[i] = low[i];
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
