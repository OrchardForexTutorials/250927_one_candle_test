/*

   One Candle

   Code:
   Copyright 2014-2025, Orchard Forex
   https://orchardforex.com

   Strategy:
   https://www.youtube.com/watch?v=yhC8pEkR-Wk

*/

#property copyright "Copyright 2014-2025, Orchard Forex"
#property link "https://orchardforex.com"
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade        Trade;
CPositionInfo PositionInfo;

enum ENUM_STATE {
   STATE_SOD,
   STATE_RANGE_FOUND,
   STATE_FVG_FOUND,
   STATE_FVG_REENTRY,
   STATE_DONE,
};

input int    InpStartHour   = 16; // Range start hour
input int    InpStartMinute = 30; // Range start minute
input int    InpEndHour     = 16; // Range end hour
input int    InpEndMinute   = 35; // Range end minute

input double InpProfitRatio = 3.0; // Profit ratio

input double InpVolume      = 0.10;         // Volume
input long   InpMagic       = 250900;       // Magic
input string InpComment     = "One Candle"; // Trade comment

int          StartSeconds;
int          EndSeconds;

;
int OnInit() {

   Trade.SetExpertMagicNumber( InpMagic );

   StartSeconds = ( InpStartHour * 3600 ) + ( InpStartMinute * 60 );
   EndSeconds   = ( InpEndHour * 3600 ) + ( InpEndMinute * 60 );

   return ( INIT_SUCCEEDED );
}

void OnDeinit( const int reason ) {}

void OnTick() {

   static ENUM_STATE state     = STATE_DONE;

   static datetime   today     = 0;
   static datetime   startTime = 0;
   static datetime   endTime   = 0;

   static double     highPrice = 0;
   static double     lowPrice  = 0;

   //
   // All activity happens at a bar close
   //
   if ( !IsNewBar() ) return;

   //
   // First state check, new day resets
   //
   datetime newDay = iTime( Symbol(), PERIOD_D1, 0 );
   if ( newDay > today ) {
      state     = STATE_SOD;
      today     = newDay;
      startTime = today + StartSeconds;
      endTime   = today + EndSeconds;
   }

   //
   //	If all done for today nothing more to do
   //
   if ( state == STATE_DONE ) {
      return;
   }

   //
   //	next state, time passed end of time range
   //
   datetime now = TimeCurrent();
   if ( state == STATE_SOD && now >= endTime ) {

      state        = STATE_RANGE_FOUND;

      int endBar   = iBarShift( Symbol(), PERIOD_M1, endTime, false );
      int startBar = iBarShift( Symbol(), PERIOD_M1, startTime, false );

      if ( iTime( Symbol(), PERIOD_M1, endBar ) < endTime ) {
         endBar--;
      }
      while ( iTime( Symbol(), PERIOD_M1, startBar ) < startTime ) {
         startBar--;
      }

      if ( startBar <= endBar ) {
         state = STATE_DONE;
         return;
      }

      highPrice = iHigh( Symbol(), PERIOD_M1, iHighest( Symbol(), PERIOD_M1, MODE_HIGH, startBar - endBar, endBar + 1 ) );
      lowPrice  = iLow( Symbol(), PERIOD_M1, iLowest( Symbol(), PERIOD_M1, MODE_LOW, startBar - endBar, endBar + 1 ) );
   }

   MqlRates rates[];
   ArraySetAsSeries( rates, true );
   CopyRates( Symbol(), Period(), 0, 4, rates );
   static ENUM_ORDER_TYPE breakDirection = -1;
   static double          fvgHigh        = 0;
   static double          fvgLow         = 0;

   //
   //	Next state, look for fvg breakiing out of the range
   //
   //	Not described but the examples all had one of the fvg candles crossing the range
   //
   if ( state == STATE_RANGE_FOUND ) {

      if ( rates[1].low > rates[3].high && rates[1].close > highPrice ) {
         // if (rates[1].low>rates[3].high && rates[1].close>highPrice && (rates[3].open<highPrice || rates[3].close<highPrice) ) {

         breakDirection = ORDER_TYPE_BUY;
         fvgHigh        = rates[1].low;
         fvgLow         = rates[3].high;
         state          = STATE_FVG_FOUND;
      }

      if ( rates[1].high < rates[3].low && rates[1].close < lowPrice ) {
         // if (rates[1].high<rates[3].low && rates[1].close<lowPrice && (rates[3].open>lowPrice || rates[3].close>lowPrice) ) {

         breakDirection = ORDER_TYPE_SELL;
         fvgHigh        = rates[3].low;
         fvgLow         = rates[1].high;
         state          = STATE_FVG_FOUND;
      }
   }

   //
   //	change state on reentry to fvg
   //
   if ( state == STATE_FVG_FOUND ) {

      if ( breakDirection == ORDER_TYPE_BUY && rates[1].low < fvgHigh ) {

         state = STATE_FVG_REENTRY;
      }

      if ( breakDirection == ORDER_TYPE_SELL && rates[1].high > fvgLow ) {

         state = STATE_FVG_REENTRY;
      }
   }

   //
   //	open trade on engulfing
   //
   //	In the examples the engulfing engulfed the candle in the FVG range
   //		but that isn't described so I just look for any engulfing
   //
   if ( state == STATE_FVG_REENTRY ) { // looking for an engulfing candle

      double range2 = MathAbs( rates[2].close - rates[2].open );
      double range1 = MathAbs( rates[1].close - rates[1].open );

      if ( range1 > range2 ) {
         if ( breakDirection == ORDER_TYPE_BUY ) {

            if ( rates[1].close > rates[1].open && rates[1].open <= rates[2].open ) {

               OpenPosition( breakDirection, rates[2].low );
               state = STATE_DONE;
            }
         }

         if ( breakDirection == ORDER_TYPE_SELL ) {

            if ( rates[1].close < rates[1].open && rates[1].open >= rates[2].open ) {

               OpenPosition( breakDirection, rates[2].high );
               state = STATE_DONE;
            }
         }
      }
   }
}

void OpenPosition( ENUM_ORDER_TYPE type, double stopLossPrice ) {

   MqlTick tick;
   SymbolInfoTick( Symbol(), tick );

   double openPrice       = ( type == ORDER_TYPE_BUY ) ? tick.ask : tick.bid;
   double takeProfitPrice = openPrice + ( ( openPrice - stopLossPrice ) * InpProfitRatio );

   openPrice              = NormalizeDouble( openPrice, Digits() );
   stopLossPrice          = NormalizeDouble( stopLossPrice, Digits() );
   takeProfitPrice        = NormalizeDouble( takeProfitPrice, Digits() );

   Trade.PositionOpen( Symbol(), type, InpVolume, openPrice, stopLossPrice, takeProfitPrice, InpComment );
}

bool IsNewBar() {

   static datetime prevTime    = 0;
   datetime        currentTime = iTime( Symbol(), Period(), 0 );
   if ( prevTime == currentTime ) return false;
   prevTime = currentTime;
   return true;
}
