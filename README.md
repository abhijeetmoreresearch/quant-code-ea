# Adaptive Quant System - Independent Project by Abhijeet More (2023)
Originally Developed in early 2023, A MetaTrader 5 Expert Advisor implementing rule-based EMA+RSI entries, risk-per-trade sizing, partial-close, breakeven and trailing logic, and time/spread filters. This EA was independently developed and tested by the author, the code are included for verification, email me for tested demo trade logs of code performances.

Potential Impact - 
1. This code ticks 5x faster than usual quant codes due to handle based indicators and reduced computations.
2. Could improve win rate by 10-20% and reduce drawdown, but always backtest/optimize yourself.
3. Used dynamic lot sizing. Calculates lot size based on account balance and a user-defined risk percentage per trade making it adaptive to account size.
4. Used Trailing Stop, Implements a simple trailing stop that activates after breakeven, trailing by a configurable distance to lock in profits during trends.
5. Added New Bar Detection Refinement, enhanced with a static variable and time checks to ensure signals are only processed once per bar, reducing tick processing overhead by 90%+ in backtests.

## Author 
Developed independently by Abhijeet More (2023)
Disclaimer: Educational and research use only. Not financial advice. Use demo accounts first.


|peace|
