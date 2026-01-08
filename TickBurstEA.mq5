#property copyright ""
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input string InpSymbol = "";                 // Instrument (empty = current)
input int    InpPeriodSeconds = 30;          // Tick counting period (seconds)
input int    InpHistoryPeriods = 200;        // History periods for average
input double InpSurgeThreshold = 3.0;        // Current ticks must exceed average * threshold
input double InpDirectionShare = 0.70;       // Direction share threshold
input int    InpTakeProfitPoints = 200;      // Take profit in points
input int    InpDeviationPoints = 10;        // Max deviation in points

CTrade trade;

string symbol_name;
long ticks_total = 0;
long ticks_up = 0;
long ticks_down = 0;

double last_price = 0.0;

long history_counts[];
int history_index = 0;
int history_filled = 0;

int OnInit()
{
   symbol_name = (InpSymbol == "" ? _Symbol : InpSymbol);

   ArrayResize(history_counts, InpHistoryPeriods);
   ArrayInitialize(history_counts, 0);

   trade.SetDeviationInPoints(InpDeviationPoints);

   EventSetTimer(InpPeriodSeconds);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick()
{
   if(SymbolInfoTick(symbol_name, _Tick) == false)
   {
      return;
   }

   ticks_total++;

   if(last_price != 0.0)
   {
      if(_Tick.last > last_price)
      {
         ticks_up++;
      }
      else if(_Tick.last < last_price)
      {
         ticks_down++;
      }
   }

   last_price = _Tick.last;
}

double CalculateAverageHistory()
{
   if(history_filled < InpHistoryPeriods)
   {
      return 0.0;
   }

   long sum = 0;
   for(int i = 0; i < InpHistoryPeriods; i++)
   {
      sum += history_counts[i];
   }

   return (double)sum / (double)InpHistoryPeriods;
}

bool HasOpenPositions()
{
   if(PositionsTotal() == 0)
   {
      return false;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByIndex(i))
      {
         return true;
      }
   }

   return false;
}

double NormalizeVolume(double volume)
{
   double min_volume = SymbolInfoDouble(symbol_name, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol_name, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(symbol_name, SYMBOL_VOLUME_STEP);

   if(volume < min_volume)
   {
      volume = min_volume;
   }

   if(volume > max_volume)
   {
      volume = max_volume;
   }

   double steps = MathFloor((volume - min_volume) / step_volume);
   return min_volume + steps * step_volume;
}

void TryOpenTrade(bool direction_up)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double volume = NormalizeVolume(balance * 10.0);

   double ask = SymbolInfoDouble(symbol_name, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol_name, SYMBOL_BID);

   if(direction_up)
   {
      double tp = ask + InpTakeProfitPoints * _Point;
      trade.Buy(volume, symbol_name, ask, 0.0, tp, "Tick surge buy");
   }
   else
   {
      double tp = bid - InpTakeProfitPoints * _Point;
      trade.Sell(volume, symbol_name, bid, 0.0, tp, "Tick surge sell");
   }
}

void OnTimer()
{
   double average = CalculateAverageHistory();

   bool history_ready = (history_filled >= InpHistoryPeriods);
   bool surge = (history_ready && ticks_total > average * InpSurgeThreshold);

   if(surge && !HasOpenPositions())
   {
      if(ticks_total > 0)
      {
         double up_share = (double)ticks_up / (double)ticks_total;
         double down_share = (double)ticks_down / (double)ticks_total;

         if(up_share >= InpDirectionShare)
         {
            TryOpenTrade(true);
         }
         else if(down_share >= InpDirectionShare)
         {
            TryOpenTrade(false);
         }
      }
   }

   if(history_filled < InpHistoryPeriods)
   {
      history_filled++;
   }

   history_counts[history_index] = ticks_total;
   history_index++;
   if(history_index >= InpHistoryPeriods)
   {
      history_index = 0;
   }

   ticks_total = 0;
   ticks_up = 0;
   ticks_down = 0;
   last_price = 0.0;
}
