#!/usr/bin/env python3
"""Backtest the auto_manage strategy on real historical data.

Tests the actual rules the bot follows:
  - Watchlist of large-cap names
  - Enter on strength (close above the 20-day moving average AND up on the day)
  - One position at a time, fixed dollar size
  - Exit at +PROFIT_TARGET%, -STOP% , or after MAX_HOLD_DAYS
  - Realistic slippage + fees applied on entry and exit

Then it compares the result against simply buying and holding SPY, and splits
the period in half so you can see whether the edge holds out-of-sample.

Everything is computed from downloaded daily bars — no numbers are invented.

Run:  source .venv/bin/activate && python backtest_strategy.py
"""

from __future__ import annotations

import sys

# ---- the strategy being tested (match these to auto_manage.sh) ----
WATCHLIST = ["SPY", "QQQ", "AAPL", "NVDA", "MSFT", "TSLA", "AMD", "GOOGL", "AMZN", "META"]
POSITION_USD = 2000.0     # dollars per position
PROFIT_TARGET = 0.04      # +4% take profit
STOP_LOSS = 0.03          # -3% stop
MAX_HOLD_DAYS = 10        # give up after N trading days
MA_WINDOW = 20            # "strength" = close above this moving average
SLIPPAGE = 0.0005         # 0.05% each side (round trip ~0.1%)
YEARS = 3                 # how much history to test
START_EQUITY = 100_000.0
# -------------------------------------------------------------------


def load_history(tickers: list[str], years: int):
    """Download daily bars. Returns {ticker: list[(date, open, high, low, close)]}."""
    try:
        import yfinance as yf
    except ImportError:
        sys.exit("yfinance not installed. Run: pip install yfinance")

    print(f"Downloading {years}y of daily data for {len(tickers)} tickers...")
    raw = yf.download(
        tickers, period=f"{years}y", interval="1d",
        auto_adjust=True, progress=False, group_by="ticker",
    )
    if raw is None or raw.empty:
        sys.exit("No data returned. Check your internet connection.")

    out: dict[str, list] = {}
    for t in tickers:
        try:
            df = raw[t].dropna() if len(tickers) > 1 else raw.dropna()
        except KeyError:
            print(f"  ! no data for {t}, skipping")
            continue
        bars = [
            (idx.date(), float(r["Open"]), float(r["High"]), float(r["Low"]), float(r["Close"]))
            for idx, r in df.iterrows()
        ]
        if len(bars) > MA_WINDOW + 5:
            out[t] = bars
            print(f"  {t}: {len(bars)} days ({bars[0][0]} -> {bars[-1][0]})")
    if not out:
        sys.exit("No usable data.")
    return out


def build_signals(history: dict[str, list]) -> dict:
    """For each ticker/date: is this a 'strength' entry signal, per the bot's rule?"""
    signals: dict = {}
    for t, bars in history.items():
        closes = [b[4] for b in bars]
        for i in range(MA_WINDOW, len(bars)):
            ma = sum(closes[i - MA_WINDOW:i]) / MA_WINDOW
            strong = closes[i] > ma and closes[i] > closes[i - 1]
            if strong:
                signals.setdefault(bars[i][0], []).append((t, i))
    return signals


def run_backtest(history: dict[str, list], date_from=None, date_to=None) -> dict:
    """Simulate the strategy. One open position at a time, entered next day's open."""
    signals = build_signals(history)
    all_dates = sorted({b[0] for bars in history.values() for b in bars})
    if date_from:
        all_dates = [d for d in all_dates if d >= date_from]
    if date_to:
        all_dates = [d for d in all_dates if d <= date_to]

    equity = START_EQUITY
    trades: list[dict] = []
    open_pos = None
    peak, max_dd = equity, 0.0

    for d in all_dates:
        # --- manage an open position first ---
        if open_pos:
            t = open_pos["ticker"]
            bars = history[t]
            idx = next((i for i, b in enumerate(bars) if b[0] == d), None)
            if idx is not None:
                _, o, hi, lo, close = bars[idx]
                entry = open_pos["entry"]
                tp = entry * (1 + PROFIT_TARGET)
                sl = entry * (1 - STOP_LOSS)
                exit_px = reason = None
                # Conservative: if both levels touched same day, assume the stop hit first.
                if lo <= sl:
                    exit_px, reason = sl, "stop"
                elif hi >= tp:
                    exit_px, reason = tp, "target"
                elif open_pos["days"] >= MAX_HOLD_DAYS:
                    exit_px, reason = close, "time"
                if exit_px is not None:
                    exit_fill = exit_px * (1 - SLIPPAGE)
                    pnl = (exit_fill - entry) * open_pos["shares"]
                    equity += pnl
                    trades.append({
                        "ticker": t, "entry_date": open_pos["date"], "exit_date": d,
                        "entry": entry, "exit": exit_fill, "pnl": pnl,
                        "pct": (exit_fill / entry - 1) * 100, "reason": reason,
                    })
                    open_pos = None
                else:
                    open_pos["days"] += 1

        # --- look for a new entry (only when flat) ---
        if not open_pos and d in signals:
            t, idx = signals[d][0]  # first qualifying name that day
            bars = history[t]
            if idx + 1 < len(bars):
                nxt = bars[idx + 1]
                entry = nxt[1] * (1 + SLIPPAGE)  # next day's open + slippage
                shares = POSITION_USD / entry
                open_pos = {"ticker": t, "entry": entry, "shares": shares,
                            "date": nxt[0], "days": 0}

        peak = max(peak, equity)
        if peak > 0:
            max_dd = max(max_dd, (peak - equity) / peak)

    wins = [t for t in trades if t["pnl"] > 0]
    losses = [t for t in trades if t["pnl"] <= 0]
    gross_win = sum(t["pnl"] for t in wins)
    gross_loss = abs(sum(t["pnl"] for t in losses))
    return {
        "trades": trades, "n": len(trades),
        "final_equity": equity,
        "return_pct": (equity / START_EQUITY - 1) * 100,
        "win_rate": (len(wins) / len(trades) * 100) if trades else 0.0,
        "avg_win": (gross_win / len(wins)) if wins else 0.0,
        "avg_loss": (gross_loss / len(losses)) if losses else 0.0,
        "profit_factor": (gross_win / gross_loss) if gross_loss else float("inf"),
        "max_dd_pct": max_dd * 100,
        "start": all_dates[0] if all_dates else None,
        "end": all_dates[-1] if all_dates else None,
    }


def benchmark_spy(history: dict[str, list], date_from=None, date_to=None) -> float:
    """Buy-and-hold SPY over the same window, in percent."""
    bars = history.get("SPY")
    if not bars:
        return float("nan")
    sel = [b for b in bars
           if (date_from is None or b[0] >= date_from) and (date_to is None or b[0] <= date_to)]
    if len(sel) < 2:
        return float("nan")
    return (sel[-1][4] / sel[0][4] - 1) * 100


def report(title: str, r: dict, bench: float) -> None:
    print(f"\n{'=' * 62}\n{title}\n{'=' * 62}")
    if not r["n"]:
        print("No trades taken in this period.")
        return
    print(f"Period            : {r['start']} -> {r['end']}")
    print(f"Trades            : {r['n']}")
    print(f"Win rate          : {r['win_rate']:.1f}%")
    print(f"Average win       : ${r['avg_win']:,.2f}")
    print(f"Average loss      : ${r['avg_loss']:,.2f}")
    print(f"Profit factor     : {r['profit_factor']:.2f}   (>1 means gross wins beat gross losses)")
    print(f"Max drawdown      : {r['max_dd_pct']:.1f}%")
    print(f"Final equity      : ${r['final_equity']:,.2f}  (from ${START_EQUITY:,.0f})")
    print(f"STRATEGY RETURN   : {r['return_pct']:+.2f}%")
    print(f"SPY buy & hold    : {bench:+.2f}%")
    verdict = "BEAT" if r["return_pct"] > bench else "LOST TO"
    print(f"\n>>> The strategy {verdict} simply buying and holding SPY.")


def main() -> None:
    print("=" * 62)
    print("BACKTEST: auto_manage strategy on real historical data")
    print("=" * 62)
    print(f"Rules: buy strength (close > {MA_WINDOW}d MA and up on day), "
          f"${POSITION_USD:,.0f}/position,\n       take profit +{PROFIT_TARGET:.0%}, "
          f"stop -{STOP_LOSS:.0%}, max hold {MAX_HOLD_DAYS}d, "
          f"slippage {SLIPPAGE:.2%}/side")

    history = load_history(WATCHLIST, YEARS)

    full = run_backtest(history)
    report("FULL PERIOD", full, benchmark_spy(history))

    # Split in half: does the edge survive in the second, unseen half?
    dates = sorted({b[0] for bars in history.values() for b in bars})
    mid = dates[len(dates) // 2]
    first = run_backtest(history, date_to=mid)
    second = run_backtest(history, date_from=mid)
    report("FIRST HALF (in-sample)", first, benchmark_spy(history, date_to=mid))
    report("SECOND HALF (out-of-sample)", second, benchmark_spy(history, date_from=mid))

    if full["trades"]:
        print(f"\n{'=' * 62}\nLAST 10 TRADES\n{'=' * 62}")
        for t in full["trades"][-10:]:
            print(f"{t['entry_date']} -> {t['exit_date']}  {t['ticker']:<6} "
                  f"{t['pct']:+6.2f}%  ${t['pnl']:+9.2f}  ({t['reason']})")

    print(f"\n{'=' * 62}")
    print("HONEST CAVEATS — read these")
    print("=" * 62)
    print("- Backtests are optimistic. Real fills, gaps and emotions are worse.")
    print("- Uses DAILY bars; the live bot checks every 30 min, so results differ.")
    print("- When both target and stop were touched in one day, a STOP is assumed")
    print("  (the conservative choice) - real intraday order matters.")
    print("- Past performance does not predict future results.")
    print("- If the strategy loses to SPY buy-and-hold, that is the honest signal")
    print("  that this edge is not real. Do not tune parameters until it looks")
    print("  good - that is overfitting, and it fails on live money.")


if __name__ == "__main__":
    main()
