//+------------------------------------------------------------------+
//|  TomAutoBot.mq4 — Autonomous Gold Trading Bot                   |
//|  Same logic as Tom Assistant Dashboard Panel                     |
//|  Broker: Vantage | Symbol: XAUUSD | Timeframe: H1               |
//+------------------------------------------------------------------+
#property copyright "Tom — Trading Assistant"
#property version   "2.0"
#property strict

//── INPUTS ──────────────────────────────────────────────────────────
input double LotSize        = 0.01;   // Lot size
input double StopLoss       = 30.0;   // Stop Loss in $
input double TakeProfit     = 60.0;   // Take Profit in $
input double MinPctMove     = 0.10;   // Min % move to consider trend
input double StrongPctMove  = 0.40;   // Strong trend threshold
input int    CooldownMins   = 5;      // Minutes between same-direction trades
input int    MagicNumber    = 20260623;
input bool   EnableTrading  = true;   // Master on/off switch
input bool   EnableLogs     = true;   // Print logs to journal

//── STATE ────────────────────────────────────────────────────────────
datetime lastSignalTime  = 0;
string   lastSignalDir   = "";
int      totalTrades     = 0;
int      totalWins       = 0;
int      totalLosses     = 0;
double   totalPnL        = 0;
bool     botEnabled      = true;   // runtime toggle via button
string   lastAction      = "Starting...";
string   lastReason      = "Initializing";
string   botStatus       = "ACTIVE";
datetime lastAnalysisTime= 0;

//── BUTTON & LABEL NAMES ─────────────────────────────────────────────
#define BTN_TOGGLE    "TomBtn_Toggle"
#define LBL_STATUS    "TomLbl_Status"
#define LBL_ACTION    "TomLbl_Action"
#define LBL_REASON    "TomLbl_Reason"
#define LBL_STATS     "TomLbl_Stats"
#define LBL_PRICE     "TomLbl_Price"
#define LBL_TITLE     "TomLbl_Title"
#define LBL_BG        "TomLbl_BG"
#define LBL_LAST      "TomLbl_Last"
#define LBL_TIME      "TomLbl_Time"

//+------------------------------------------------------------------+
//| EA Init                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("══════════════════════════════════════════");
   Print("  TomAutoBot v2.0 — Autonomous Gold Bot");
   Print("  Symbol: ", Symbol(), " | TF: ", Period());
   Print("  Lot: ", LotSize, " | SL: $", StopLoss, " | TP: $", TakeProfit);
   Print("  Logic: Tom Dashboard Analysis");
   Print("══════════════════════════════════════════");

   botEnabled = EnableTrading;
   CreatePanel();
   UpdatePanel();

   EventSetTimer(30);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeletePanel();
   Print("TomAutoBot stopped. Trades: ", totalTrades,
         " | Wins: ", totalWins, " | Losses: ", totalLosses,
         " | P&L: $", DoubleToStr(totalPnL, 2));
}

//+------------------------------------------------------------------+
//| Timer — runs every 30 seconds                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   RunTomAnalysis();
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Tick — update price on panel + manage trades                    |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenTrades();
   // Update price on panel every tick
   double price = MarketInfo(Symbol(), MODE_BID);
   ObjectSetText(LBL_PRICE, "Price: $" + DoubleToStr(price, 2), 11, "Arial Bold", clrWhite);
}

//+------------------------------------------------------------------+
//| Chart event — handle button click                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_TOGGLE)
   {
      botEnabled = !botEnabled;
      if(botEnabled)
      {
         botStatus  = "ACTIVE";
         lastAction = "Bot STARTED";
         lastReason = "Manual start by user";
         Print("TomAutoBot STARTED by user");
      }
      else
      {
         botStatus  = "STOPPED";
         lastAction = "Bot STOPPED";
         lastReason = "Manual stop by user";
         Print("TomAutoBot STOPPED by user");
      }
      UpdatePanel();
      // Reset button state so it can be clicked again
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_STATE, false);
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| TOM ANALYSIS — Same logic as dashboard Tom Assistant Panel      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CREATE PANEL on chart                                           |
//+------------------------------------------------------------------+
void CreatePanel()
{
   // Background box
   ObjectCreate(0, LBL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_BG, OBJPROP_XDISTANCE,  10);
   ObjectSetInteger(0, LBL_BG, OBJPROP_YDISTANCE,  10);
   ObjectSetInteger(0, LBL_BG, OBJPROP_XSIZE,      320);
   ObjectSetInteger(0, LBL_BG, OBJPROP_YSIZE,      230);
   ObjectSetInteger(0, LBL_BG, OBJPROP_BGCOLOR,    C'20,20,30');
   ObjectSetInteger(0, LBL_BG, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, LBL_BG, OBJPROP_COLOR,      C'0,200,100');
   ObjectSetInteger(0, LBL_BG, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, LBL_BG, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, LBL_BG, OBJPROP_BACK,       false);

   // Title
   ObjectCreate(0, LBL_TITLE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_TITLE, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_TITLE, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, LBL_TITLE, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetText(LBL_TITLE, "TomAutoBot v2.0  |  XAUUSD", 10, "Arial Bold", C'0,200,100');

   // Price
   ObjectCreate(0, LBL_PRICE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_PRICE, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_PRICE, OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, LBL_PRICE, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Status
   ObjectCreate(0, LBL_STATUS, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_STATUS, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_STATUS, OBJPROP_YDISTANCE, 65);
   ObjectSetInteger(0, LBL_STATUS, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Action
   ObjectCreate(0, LBL_ACTION, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_ACTION, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_ACTION, OBJPROP_YDISTANCE, 90);
   ObjectSetInteger(0, LBL_ACTION, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Reason
   ObjectCreate(0, LBL_REASON, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_REASON, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_REASON, OBJPROP_YDISTANCE, 112);
   ObjectSetInteger(0, LBL_REASON, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Stats
   ObjectCreate(0, LBL_STATS, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_STATS, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_STATS, OBJPROP_YDISTANCE, 135);
   ObjectSetInteger(0, LBL_STATS, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Last trade
   ObjectCreate(0, LBL_LAST, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_LAST, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_LAST, OBJPROP_YDISTANCE, 158);
   ObjectSetInteger(0, LBL_LAST, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // Last analysis time
   ObjectCreate(0, LBL_TIME, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_TIME, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, LBL_TIME, OBJPROP_YDISTANCE, 178);
   ObjectSetInteger(0, LBL_TIME, OBJPROP_CORNER,    CORNER_LEFT_UPPER);

   // START/STOP Button
   ObjectCreate(0, BTN_TOGGLE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XDISTANCE,  20);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YDISTANCE,  200);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XSIZE,      130);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YSIZE,      28);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_FONTSIZE,   10);
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR,    C'0,160,80');
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_COLOR,      clrWhite);
   ObjectSetString(0,  BTN_TOGGLE, OBJPROP_FONT,       "Arial Bold");
   ObjectSetText(BTN_TOGGLE, "  STOP BOT", 10, "Arial Bold", clrWhite);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| UPDATE PANEL labels                                             |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   double price   = MarketInfo(Symbol(), MODE_BID);
   double dayOpen = iOpen(Symbol(), PERIOD_D1, 0);
   double pct     = dayOpen > 0 ? ((price - dayOpen) / dayOpen) * 100.0 : 0;
   int    openTrades = 0;
   for(int i=0; i<OrdersTotal(); i++)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderMagicNumber()==MagicNumber) openTrades++;

   double accuracy = totalTrades > 0 ? 100.0 * totalWins / totalTrades : 0;

   // Price
   ObjectSetText(LBL_PRICE,
      "Price: $" + DoubleToStr(price,2) + "  (" + (pct>=0?"+":"") + DoubleToStr(pct,2) + "% today)",
      11, "Arial Bold", clrWhite);

   // Status
   color  statusColor  = botEnabled ? C'0,220,100' : C'220,60,60';
   string statusText   = botEnabled ? "STATUS:  ACTIVE  |  Analyzing every 30s" : "STATUS:  STOPPED  |  Click START to resume";
   ObjectSetText(LBL_STATUS, statusText, 10, "Arial Bold", statusColor);

   // Action
   color actionColor = (lastAction=="BUY")  ? C'0,220,100' :
                       (lastAction=="SELL") ? C'220,60,60'  :
                       (lastAction=="WAIT") ? C'220,180,0'  : clrSilver;
   string actionIcon = (lastAction=="BUY")  ? "BUY  >>" :
                       (lastAction=="SELL") ? "SELL >>" :
                       (lastAction=="WAIT") ? "WAIT --" : lastAction;
   ObjectSetText(LBL_ACTION, "Decision:  " + actionIcon, 12, "Arial Bold", actionColor);

   // Reason (truncate to 42 chars)
   string shortReason = StringLen(lastReason) > 42 ? StringSubstr(lastReason,0,42)+"..." : lastReason;
   ObjectSetText(LBL_REASON, shortReason, 9, "Arial", clrSilver);

   // Stats
   ObjectSetText(LBL_STATS,
      "Trades: " + IntegerToString(totalTrades) +
      "   Wins: " + IntegerToString(totalWins) +
      "   Loss: " + IntegerToString(totalLosses) +
      "   Acc: " + DoubleToStr(accuracy,1) + "%" +
      "   P&L: $" + DoubleToStr(totalPnL,2),
      9, "Arial", clrSilver);

   // Last signal + open trades
   string lastSig = lastSignalDir == "" ? "None yet" : lastSignalDir + " @ " + TimeToStr(lastSignalTime, TIME_MINUTES);
   ObjectSetText(LBL_LAST,
      "Last Signal: " + lastSig + "   Open: " + IntegerToString(openTrades) + " trade(s)",
      9, "Arial", clrSilver);

   // Last analysis time
   string lastT = lastAnalysisTime > 0 ? TimeToStr(lastAnalysisTime, TIME_SECONDS) : "--";
   ObjectSetText(LBL_TIME, "Last analysis: " + lastT + "  (next in ~30s)", 9, "Arial", C'100,100,120');

   // Button text + color
   if(botEnabled)
   {
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, C'180,40,40');
      ObjectSetText(BTN_TOGGLE, "  STOP BOT", 10, "Arial Bold", clrWhite);
   }
   else
   {
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, C'0,160,80');
      ObjectSetText(BTN_TOGGLE, "  START BOT", 10, "Arial Bold", clrWhite);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DELETE PANEL objects                                            |
//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectDelete(0, LBL_BG);
   ObjectDelete(0, LBL_TITLE);
   ObjectDelete(0, LBL_PRICE);
   ObjectDelete(0, LBL_STATUS);
   ObjectDelete(0, LBL_ACTION);
   ObjectDelete(0, LBL_REASON);
   ObjectDelete(0, LBL_STATS);
   ObjectDelete(0, LBL_LAST);
   ObjectDelete(0, LBL_TIME);
   ObjectDelete(0, BTN_TOGGLE);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TOM ANALYSIS                                                    |
//+------------------------------------------------------------------+
void RunTomAnalysis()
{
   double price   = MarketInfo(Symbol(), MODE_BID);
   double spread  = MarketInfo(Symbol(), MODE_SPREAD) * Point;
   double dayHigh = iHigh(Symbol(), PERIOD_D1, 0);
   double dayLow  = iLow(Symbol(), PERIOD_D1, 0);
   double dayOpen = iOpen(Symbol(), PERIOD_D1, 0);
   double dayRange= dayHigh - dayLow;

   if(price <= 0 || dayOpen <= 0) return;

   double chg     = price - dayOpen;
   double pct     = (chg / dayOpen) * 100.0;
   double pctAbs  = MathAbs(pct);
   bool   isBull  = chg > 0;
   bool   isStrong= pctAbs >= StrongPctMove;
   bool   isFlat  = pctAbs < MinPctMove;

   // Overbought/Oversold — near day high/low (within 10% of range)
   bool isOverbought = dayRange > 5 && price > dayHigh - (dayRange * 0.10);
   bool isOversold   = dayRange > 5 && price < dayLow  + (dayRange * 0.10);

   // Session check (Dubai = UTC+4)
   int dubaiHour = GetDubaiHour();
   bool londonOpen = dubaiHour >= 11 && dubaiHour < 19;
   bool nyOpen     = dubaiHour >= 16 || dubaiHour < 1;
   bool tokyoOpen  = dubaiHour >= 3  && dubaiHour < 12;
   bool overlap    = londonOpen && nyOpen;
   bool anyOpen    = londonOpen || nyOpen || tokyoOpen;

   string sessLabel = overlap    ? "London+NY Overlap ⚡" :
                      londonOpen ? "London Session" :
                      nyOpen     ? "New York Session" :
                      tokyoOpen  ? "Tokyo Session" : "Off-Hours";

   // ── DECISION LOGIC (mirrors dashboard JS exactly) ──
   string action    = "WAIT";
   string reason    = "";
   string direction = "";

   if(!anyOpen)
   {
      action = "WAIT";
      reason = "All sessions closed (" + sessLabel + ") — low volume";
   }
   else if(isFlat)
   {
      action = "WAIT";
      reason = StringFormat("Price flat (%.2f%%) — ranging — no clear direction", pct);
   }
   else if(isBull && isStrong && !isOverbought)
   {
      action    = "BUY";
      direction = "BUY";
      reason    = StringFormat("Gold +%.2f%% | Strong bull | %s | Room to high $%.0f", pct, sessLabel, dayHigh);
   }
   else if(isBull && isOverbought)
   {
      action = "WAIT";
      reason = StringFormat("Bullish but near day high $%.0f — too risky to chase", dayHigh);
   }
   else if(isBull && !isStrong)
   {
      action = "WAIT";
      reason = StringFormat("Mild bullish +%.2f%% — wait for stronger momentum", pct);
   }
   else if(!isBull && isStrong && !isOversold)
   {
      action    = "SELL";
      direction = "SELL";
      reason    = StringFormat("Gold %.2f%% | Strong bear | %s | Room to low $%.0f", pct, sessLabel, dayLow);
   }
   else if(!isBull && isOversold)
   {
      action = "WAIT";
      reason = StringFormat("Bearish but near day low $%.0f — bounce risk", dayLow);
   }
   else
   {
      action = "WAIT";
      reason = StringFormat("Mild move %.2f%% — no clear setup yet", pct);
   }

   lastAction       = action;
   lastReason        = reason;
   lastAnalysisTime  = TimeCurrent();

   if(EnableLogs)
      Print("[Tom] $", DoubleToStr(price,2), " | ", action, " | ", reason);

   if(!botEnabled) return;

   // ── FIRE TRADE ──
   if(direction != "")
      TryFireTrade(direction, price, reason);
}

//+------------------------------------------------------------------+
//| Fire trade with cooldown check                                   |
//+------------------------------------------------------------------+
void TryFireTrade(string direction, double price, string reason)
{
   // Cooldown — don't repeat same direction within CooldownMins
   bool samDir    = (direction == lastSignalDir);
   bool inCooldown= (TimeCurrent() - lastSignalTime) < (CooldownMins * 60);

   if(samDir && inCooldown)
   {
      int remaining = (CooldownMins * 60) - (int)(TimeCurrent() - lastSignalTime);
      if(EnableLogs)
         Print("⏳ Cooldown ", remaining, "s — skipping duplicate ", direction);
      return;
   }

   // Don't open if already have open trade in same direction
   if(HasOpenTrade(direction))
   {
      if(EnableLogs)
         Print("⚠️  Already have open ", direction, " trade — skipping");
      return;
   }

   // Place trade
   int ticket = PlaceTrade(direction, price, reason);
   if(ticket > 0)
   {
      lastSignalDir  = direction;
      lastSignalTime = TimeCurrent();
      totalTrades++;
      Print("✅ Trade placed: ", direction, " #", ticket, " @ $", DoubleToStr(price, 2));
   }
}

//+------------------------------------------------------------------+
//| Place market order                                               |
//+------------------------------------------------------------------+
int PlaceTrade(string direction, double price, string reason)
{
   int    cmd   = (direction == "BUY") ? OP_BUY : OP_SELL;
   double entry = (direction == "BUY") ? MarketInfo(Symbol(), MODE_ASK)
                                       : MarketInfo(Symbol(), MODE_BID);
   double point = MarketInfo(Symbol(), MODE_POINT);
   int    digits= (int)MarketInfo(Symbol(), MODE_DIGITS);

   // Convert $ SL/TP to points
   // Gold: 1 point = $0.01, so $1 = 100 points for 0.01 lot
   // For 0.01 lot: $1 profit = 1 pip move ≈ depends on lot
   // Simpler: use price distance directly
   double slDist = StopLoss  * point * 100; // $30 SL
   double tpDist = TakeProfit* point * 100; // $60 TP

   double sl, tp;
   if(direction == "BUY")
   {
      sl = NormalizeDouble(entry - slDist, digits);
      tp = NormalizeDouble(entry + tpDist, digits);
   }
   else
   {
      sl = NormalizeDouble(entry + slDist, digits);
      tp = NormalizeDouble(entry - tpDist, digits);
   }

   int ticket = OrderSend(
      Symbol(), cmd, LotSize, entry, 3, sl, tp,
      "TomAutoBot: " + reason,
      MagicNumber, 0, cmd == OP_BUY ? clrGreen : clrRed
   );

   if(ticket < 0)
      Print("❌ OrderSend failed: error ", GetLastError(), " | ", direction, " @ $", DoubleToStr(entry,2));

   return ticket;
}

//+------------------------------------------------------------------+
//| Check if already have open trade in this direction              |
//+------------------------------------------------------------------+
bool HasOpenTrade(string direction)
{
   int cmd = (direction == "BUY") ? OP_BUY : OP_SELL;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == cmd)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage open trades — track wins/losses when closed             |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   static int lastOrderCount = 0;
   int currentCount = OrdersHistoryTotal();

   if(currentCount > lastOrderCount)
   {
      // New closed trade — check result
      if(OrderSelect(currentCount - 1, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderMagicNumber() == MagicNumber)
         {
            double pnl = OrderProfit() + OrderSwap() + OrderCommission();
            totalPnL += pnl;
            if(pnl >= 0) totalWins++;
            else         totalLosses++;

            string result = pnl >= 0 ? "✅ WIN" : "❌ LOSS";
            Print(result, " | ", OrderType()==OP_BUY?"BUY":"SELL",
                  " | P&L: $", DoubleToStr(pnl,2),
                  " | Total P&L: $", DoubleToStr(totalPnL,2),
                  " | Accuracy: ", totalTrades>0 ? DoubleToStr(100.0*totalWins/totalTrades,1) : "0", "%");
         }
      }
      lastOrderCount = currentCount;
   }
}

//+------------------------------------------------------------------+
//| Get current Dubai hour (UTC+4)                                  |
//+------------------------------------------------------------------+
int GetDubaiHour()
{
   datetime utcTime = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);
   return (dt.hour + 4) % 24;
}
//+------------------------------------------------------------------+
