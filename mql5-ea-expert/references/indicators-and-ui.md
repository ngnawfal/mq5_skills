# Custom indicators, chart objects, dashboards, logs

Snippets here were compiled with MetaEditor (0 errors, 0 warnings). The full reference
indicator is `templates/Indicators/SkillKit_Swings.mq5`.

---

## 1. Indicator buffers

```mql5
#property indicator_chart_window
#property indicator_buffers 2                 // data + calculation buffers
#property indicator_plots   1                 // plots only
#property indicator_label1  "Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue

double g_signal[];
double g_calc[];

int OnInit()
  {
   SetIndexBuffer(0, g_signal, INDICATOR_DATA);
   SetIndexBuffer(1, g_calc,   INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   return INIT_SUCCEEDED;
  }
```

`indicator_buffers` counts every buffer (data + calculations + colour), `indicator_plots` only the
drawn ones.

## 2. `OnCalculate` indexing - the most common indicator bug

Arrays passed to `OnCalculate` are **not** series by default: index 0 is the oldest bar,
`rates_total - 1` is the forming bar. Pick one convention and keep it for every array.

```mql5
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   int start = (prev_calculated == 0) ? 0 : prev_calculated - 1;   // recompute the last bar
   for(int i = start; i < rates_total; i++)
     {
      g_signal[i] = EMPTY_VALUE;
      if(i < 1 || i == rates_total - 1)
         continue;                                  // need history; forming bar not final
      if(close[i] > high[i - 1])
         g_signal[i] = low[i];
     }
   return rates_total;
  }
```

Wrong (seen in the old version of this skill): `ArraySetAsSeries(close, true)` and then looping
`i = prev_calculated .. rates_total` while writing non-series buffers - indices point at different
bars.

Look-back that is confirmed later (swings) must recompute far enough back: when a new bar closes,
the pivot `k` bars back becomes known, so start at `prev_calculated - k - 2`
(`SkillKit_Swings.mq5`).

## 3. Using an indicator from an EA

- `iCustom(symbol, tf, "Folder\\Name", params...)` returns a handle; read buffers with
  `CopyBuffer(handle, bufferIndex, 1, count, array)`; shift 1 = last closed bar.
- Check `BarsCalculated(handle)` before relying on values; on first calls it may be 0.
- A repainting indicator gives different values in history than it gave live; an EA using it
  backtests far better than it trades.

## 4. Chart objects

```mql5
const string OBJ_PREFIX = "SK_";

void DrawZone(const string id, datetime t1, double p1, datetime t2, double p2, color c)
  {
   string name = OBJ_PREFIX + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

// OnDeinit: ObjectsDeleteAll(0, OBJ_PREFIX);
```

- Skip drawing in optimisation and non-visual tests:
  `if(MQLInfoInteger(MQL_OPTIMIZATION) || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;`
- Object names must be unique per object; prefix everything for cleanup.

## 5. Dashboard (labels)

```mql5
void SetLine(const int row, const string text, const color clr)
  {
   string name = OBJ_PREFIX + "row" + IntegerToString(row);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20 + row * 16);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }
```

Update at most once per second (from `OnTimer`), not on every tick, then `ChartRedraw()`.
Show what helps decisions: equity vs daily limit and max loss, floating loss vs shield, entries
today, last skip reason, server-time model.

## 6. CSV trade journal

```mql5
bool AppendCsv(const string file, const string line)
  {
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("[LOG] cannot open %s, error %d", file, GetLastError());
      return false;
     }
   FileSeek(h, 0, SEEK_END);                       // append, do not overwrite
   FileWriteString(h, line + "\r\n");
   FileClose(h);
   return true;
  }
```

- Write closed trades from `OnTradeTransaction` (deal add with `DEAL_ENTRY_OUT`), including
  deal price, volume, profit, commission, swap, magic and comment.
- In the tester, files live in the agent sandbox (`Tester\...\Agent-*\MQL5\Files`); add
  `FILE_COMMON` to write to the shared `Common\Files` folder instead.

## 7. Alerts and notifications

- `Alert()` (terminal), `SendNotification()` (mobile, needs MetaQuotes ID), `SendMail()` (SMTP
  settings). All three are suppressed in the tester.
- `WebRequest()` for Telegram or webhooks requires the URL in Tools > Options > Expert Advisors and
  is not available in the tester; never put bot tokens in source code committed to a repository.
