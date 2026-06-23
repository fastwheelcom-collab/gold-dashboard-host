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
input double MinPctMove     = 0.10;   // Min % move to consider trend (0.10 = 0.10%)
input double StrongPctMove  = 0.40;   // Strong trend threshold (0.40 = 0.40%)
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

//+------------------------------------------------------------------+
//| EA Init                                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("══════════════════════════════════════════");
   Print("  TomAutoBot v2.0 — Autonomous Gold Bot");
   Print("  Symbol: ", Symbol(), " | TF: ", Period());
   Print("  Lot: ", LotSize, " | SL: $", StopLoss, " | TP: $", TakeProfit);
   Print("  Logic: Tom Dashboard Analysis (same as panel)");
   Print("══════════════════════════════════════════");

   if(!EnableTrading)
      Print("⚠️  Trading DISABLED — EnableTrading=false");

   EventSetTimer(30); // Run analysis every 30 seconds
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("TomAutoBot stopped. Total trades: ", totalTrades,
         " | Wins: ", totalWins, " | Losses: ", totalLosses,
         " | P&L: $", DoubleToStr(totalPnL, 2));
}

//+------------------------------------------------------------------+
//| Timer — runs every 30 seconds                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!EnableTrading) return;
   RunTomAnalysis();
}

//+------------------------------------------------------------------+
//| Tick — also check on every tick for trade management            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| TOM ANALYSIS — Same logic as dashboard Tom Assistant Panel      |
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

   if(EnableLogs)
      Print("🔍 [Tom] $", DoubleToStr(price,2), " | ", action, " | ", reason);

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
