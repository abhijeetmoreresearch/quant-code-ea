#include <Trade/Trade.mqh>
CTrade tradeHandler;  


enum TradeDirection { BUY = 0, SELL = 1 };

input group "Trading Parameters"
input double riskPercent = 1.0;             
input int slPoints = 100;                 
input int tpPoints = 300;                   
input int trailingPoints = 50;            
input double partialClosePercent = 50.0;    

input group "Indicator Settings"
input int rsiPeriod = 14;                   
input int fastEMAPeriod = 9;               
input int slowEMAPeriod = 21;              

input group "Filters and Risk Management"
input double maxSpreadPoints = 20.0;        
input double breakevenBufferPoints = 10.0;
input bool enableTimeFilter = true;        
input int startHour = 8;                   
input int endHour = 20;                     
input bool enableAlgo = true;     

input group "Advanced"
input int magicNumber = 12345;           

const double RSI_BUY_THRESHOLD = 50.0;
const double RSI_SELL_THRESHOLD = 50.0;
const double PARTIAL_PROFIT_MULTIPLIER = 0.5;  

bool tradingAllowed = true;
datetime lastTradeTime = 0;
static datetime lastBarTime = 0;


int handleFastEMA = INVALID_HANDLE;
int handleSlowEMA = INVALID_HANDLE;
int handleRSI = INVALID_HANDLE;


double bufferFastEMA[1], bufferSlowEMA[1], bufferRSI[1];


bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
    if (currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}


bool IsTradingTimeAllowed()
{
    if (!enableTimeFilter) return true;
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    int currentHour = timeStruct.hour;
    return (currentHour >= startHour && currentHour <= endHour) && (timeStruct.day_of_week >= 1 && timeStruct.day_of_week <= 5);  
}

double CalculateLotSize(double entryPrice, double slPrice)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = accountBalance * (riskPercent / 100.0);
    double slDistance = MathAbs(entryPrice - slPrice) / _Point;
    if (tickValue == 0 || slDistance == 0) return 0.01;  
    return NormalizeDouble(riskAmount / (slDistance * tickValue), 2);
}


void FetchIndicators()
{
    CopyBuffer(handleFastEMA, 0, 0, 1, bufferFastEMA);
    CopyBuffer(handleSlowEMA, 0, 0, 1, bufferSlowEMA);
    CopyBuffer(handleRSI, 0, 0, 1, bufferRSI);
}

bool EntrySignalBuy()
{
    double closePrice = iClose(_Symbol, PERIOD_M15, 0);
    return (bufferFastEMA[0] > bufferSlowEMA[0] && bufferRSI[0] > RSI_BUY_THRESHOLD && closePrice > bufferSlowEMA[0]);
}

bool EntrySignalSell()
{
    double closePrice = iClose(_Symbol, PERIOD_M15, 0);
    return (bufferFastEMA[0] < bufferSlowEMA[0] && bufferRSI[0] < RSI_SELL_THRESHOLD && closePrice < bufferSlowEMA[0]);
}

void ManagePosition(TradeDirection direction)
{
    if (!PositionSelectByTicket(GetEATicket())) return;  

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = (direction == BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    double profitPoints = (direction == BUY) ? (currentPrice - openPrice) / _Point : (openPrice - currentPrice) / _Point;


    double partialThreshold = tpPoints * PARTIAL_PROFIT_MULTIPLIER;
    if (profitPoints >= partialThreshold && PositionGetDouble(POSITION_VOLUME) > 0.01)
    {
        double closeVolume = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (partialClosePercent / 100.0), 2);
        tradeHandler.PositionClosePartial(PositionGetTicket(0), closeVolume);
        Print("Partial close executed at ", partialThreshold, " points profit.");
    }

    if (profitPoints > breakevenBufferPoints)
    {
        double newSL = (direction == BUY) ? openPrice + _Point : openPrice - _Point;
        if ((direction == BUY && currentSL < newSL) || (direction == SELL && currentSL > newSL))
        {
            if (!tradeHandler.PositionModify(PositionGetTicket(0), newSL, currentTP))
                Print("Breakeven failed: ", tradeHandler.ResultRetcodeDescription());
        }
    }

    if (profitPoints > breakevenBufferPoints + trailingPoints)
    {
        double trailSL = (direction == BUY) ? currentPrice - trailingPoints * _Point : currentPrice + trailingPoints * _Point;
        if ((direction == BUY && currentSL < trailSL) || (direction == SELL && currentSL > trailSL))
        {
            if (!tradeHandler.PositionModify(PositionGetTicket(0), trailSL, currentTP))
                Print("Trailing stop failed: ", tradeHandler.ResultRetcodeDescription());
        }
    }
}

ulong GetEATicket()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
            return PositionGetTicket(i);
    }
    return 0;
}

void OnTick()
{
    if (!enableAlgo || !tradingAllowed || !IsTradingTimeAllowed()) return;

    ulong ticket = GetEATicket();
    TradeDirection direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? BUY : SELL;
    ManagePosition(direction);  // Manage open position (breakeven, trailing, partial)

    if (ticket != 0) return;  

    double currentSpread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
    if (currentSpread > maxSpreadPoints) return;  // Skip high-spread conditions

    if (!IsNewBar()) return;  

    FetchIndicators();  

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (EntrySignalBuy())
    {
        double slPrice = ask - slPoints * _Point;
        double lot = CalculateLotSize(ask, slPrice);
        if (tradeHandler.Buy(lot, _Symbol, ask, slPrice, ask + tpPoints * _Point, "", magicNumber))
        {
            lastTradeTime = TimeCurrent();
            Print("Buy order opened with lot: ", lot);
        }
        else
        {
            Print("Buy failed: ", tradeHandler.ResultRetcodeDescription());
        }
    }
    else if (EntrySignalSell())
    {
        double slPrice = bid + slPoints * _Point;
        double lot = CalculateLotSize(bid, slPrice);
        if (tradeHandler.Sell(lot, _Symbol, bid, slPrice, bid - tpPoints * _Point, "", magicNumber))
        {
            lastTradeTime = TimeCurrent();
            Print("Sell order opened with lot: ", lot);
        }
        else
        {
            Print("Sell failed: ", tradeHandler.ResultRetcodeDescription());
        }
    }
}

int OnInit()
{
    tradingAllowed = true;

    handleFastEMA = iMA(_Symbol, PERIOD_M15, fastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleSlowEMA = iMA(_Symbol, PERIOD_M15, slowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleRSI = iRSI(_Symbol, PERIOD_M15, rsiPeriod, PRICE_CLOSE);

    if (handleFastEMA == INVALID_HANDLE || handleSlowEMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles.");
        return INIT_FAILED;
    }

    if (riskPercent <= 0 || slPoints <= 0 || tpPoints <= 0 || rsiPeriod <= 0 ||
        fastEMAPeriod <= 0 || slowEMAPeriod <= 0 || breakevenBufferPoints < 0 ||
        maxSpreadPoints < 0 || trailingPoints <= 0 || partialClosePercent < 0 || partialClosePercent > 100)
    {
        Print("Invalid input parameters. Please correct and restart.");
        return INIT_PARAMETERS_INCORRECT;
    }

    if (startHour > endHour || startHour < 0 || endHour > 23)
    {
        Print("Invalid trading hours. Adjusting to defaults.");
        startHour = 8;
        endHour = 20;
    }

    Print("EA initialized successfully with magic: ", magicNumber);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    tradingAllowed = false;

    IndicatorRelease(handleFastEMA);
    IndicatorRelease(handleSlowEMA);
    IndicatorRelease(handleRSI);

    Print("EA deinitialized with reason: ", reason);
}
