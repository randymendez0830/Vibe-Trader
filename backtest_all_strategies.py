#!/usr/bin/env python3
"""Backtest MANY classic strategies on your watchlist and rank them honestly.

Tests 10 well-known strategy families x 3 exit schemes on real daily history,
then reports each one's metrics IN-SAMPLE and OUT-OF-SAMPLE, compared against
SPY buy-and-hold.

*** READ THIS BEFORE TRUSTING ANY RESULT ***
Testing many strategies and picking the winner is called DATA MINING, and it is
the single easiest way to fool yourself. If you test 30 combinations, a few will
look excellent from luck alone -- the same way flipping 30 coins gives you one
that lands heads 8 times running. That coin is not "a good flipper."

This script defends against that in two ways:
  1. It splits history in half. A strategy is only credible if it works in the
     SECOND half too (data it was not selected on).
  2. It assigns a CONFIDENCE grade that punishes small trade counts and
     in-sample-only success.
Anything that wins in-sample but fails out-of-sample is noise. Discard it.

Run:  source .venv/bin/activate && python backtest_all_strategies.py
"""

from __future__ import annotations

import sys
from statistics import mean, pstdev

WATCHLIST = ["SPY", "QQQ", "AAPL", "NVDA", "MSFT", "TSLA", "AMD", "GOOGL", "AMZN", "META"]
# Position size as a FRACTION OF CURRENT EQUITY (compounding), so the result is
# directly comparable to buy-and-hold, which is 100% invested. With the old
# fixed $2,000-of-$100,000 sizing, only 2% of capital ever worked and every
# strategy lost to the benchmark by construction -- an unfair test.
# 1.0 = go "all in" on one position at a time. Lower it to trade smaller.
POSITION_PCT = 1.0
SLIPPAGE = 0.0005          # 0.05% per side
YEARS = 5                  # more history = more reliable
START_EQUITY = 100_000.0
MIN_TRADES_CREDIBLE = 30   # below this, results are statistically meaningless


# ----------------------------- data ---------------------------------------
def load_history(tickers, years):
    try:
        import yfinance as yf
    except ImportError:
        sys.exit("yfinance not installed. Run: pip install yfinance")
    print(f"Downloading {years}y daily data for {len(tickers)} tickers...")
    raw = yf.download(tickers, period=f"{years}y", interval="1d",
                      auto_adjust=True, progress=False, group_by="ticker")
    if raw is None or raw.empty:
        sys.exit("No data returned - check your connection.")
    out = {}
    for t in tickers:
        try:
            df = raw[t].dropna() if len(tickers) > 1 else raw.dropna()
        except KeyError:
            continue
        bars = [(i.date(), float(r["Open"]), float(r["High"]), float(r["Low"]),
                 float(r["Close"]), float(r.get("Volume", 0) or 0))
                for i, r in df.iterrows()]
        if len(bars) > 250:
            out[t] = bars
    if not out:
        sys.exit("No usable data.")
    print(f"  loaded {len(out)} tickers, ~{len(next(iter(out.values())))} days each")
    return out


# --------------------------- indicators -----------------------------------
def sma(v, i, n):
    return mean(v[i - n:i]) if i >= n else None


def ema_series(v, n):
    k, out, prev = 2 / (n + 1), [], None
    for x in v:
        prev = x if prev is None else x * k + prev * (1 - k)
        out.append(prev)
    return out


def rsi_at(closes, i, n=14):
    if i < n + 1:
        return None
    gains = losses = 0.0
    for j in range(i - n + 1, i + 1):
        d = closes[j] - closes[j - 1]
        gains += max(d, 0.0)
        losses += max(-d, 0.0)
    if losses == 0:
        return 100.0
    rs = (gains / n) / (losses / n)
    return 100 - (100 / (1 + rs))


def atr_at(bars, i, n=14):
    if i < n + 1:
        return None
    trs = []
    for j in range(i - n + 1, i + 1):
        _, _, hi, lo, c, _ = bars[j]
        pc = bars[j - 1][4]
        trs.append(max(hi - lo, abs(hi - pc), abs(lo - pc)))
    return mean(trs)


# --------------------------- strategies -----------------------------------
# Each returns True when a LONG entry triggers at bar i (entry fills next open).
def s_momentum_ma20(b, c, i, e50, e200):
    m = sma(c, i, 20)
    return m is not None and c[i] > m and c[i] > c[i - 1]


def s_golden_cross(b, c, i, e50, e200):
    return i > 200 and e50[i] > e200[i] and e50[i - 1] <= e200[i - 1]


def s_trend_pullback(b, c, i, e50, e200):
    r = rsi_at(c, i)
    return i > 200 and c[i] > e200[i] and r is not None and r < 40


def s_mean_reversion_2sd(b, c, i, e50, e200):
    if i < 20:
        return False
    w = c[i - 20:i]
    m, sd = mean(w), pstdev(w)
    return sd > 0 and c[i] < m - 2 * sd


def s_rsi_oversold(b, c, i, e50, e200):
    r = rsi_at(c, i)
    return r is not None and r < 30


def s_breakout_20d(b, c, i, e50, e200):
    if i < 21:
        return False
    return c[i] > max(x[4] for x in b[i - 20:i])


def s_breakout_volume(b, c, i, e50, e200):
    if i < 21:
        return False
    hi20 = max(x[4] for x in b[i - 20:i])
    v20 = mean(x[5] for x in b[i - 20:i]) or 1
    return c[i] > hi20 and b[i][5] > 1.5 * v20


def s_high52w(b, c, i, e50, e200):
    if i < 252:
        return False
    return c[i] >= max(x[4] for x in b[i - 252:i]) * 0.98


def s_three_up(b, c, i, e50, e200):
    return i > 3 and c[i] > c[i - 1] > c[i - 2] > c[i - 3]


def s_gap_up_hold(b, c, i, e50, e200):
    if i < 21:
        return False
    m = sma(c, i, 20)
    return m is not None and b[i][1] > c[i - 1] * 1.01 and c[i] > b[i][1] and c[i] > m


STRATEGIES = {
    "Momentum (>20d MA, up day)": s_momentum_ma20,
    "Golden cross (50/200 EMA)": s_golden_cross,
    "Trend pullback (>200MA, RSI<40)": s_trend_pullback,
    "Mean reversion (-2 std dev)": s_mean_reversion_2sd,
    "RSI oversold (<30)": s_rsi_oversold,
    "Breakout (20d high)": s_breakout_20d,
    "Breakout + volume confirm": s_breakout_volume,
    "52-week high momentum": s_high52w,
    "Three up days": s_three_up,
    "Gap up and hold": s_gap_up_hold,
}

# Exit schemes: (name, take_profit, stop, max_hold_days, atr_stop_mult)
EXITS = [
    ("tight +4%/-3%", 0.04, 0.03, 10, None),
    ("wide +10%/-5%", 0.10, 0.05, 30, None),
    ("ATR trail 2x, 20d", None, None, 20, 2.0),
]


# --------------------------- simulation -----------------------------------
def simulate(history, sig_fn, exit_cfg, date_from=None, date_to=None):
    _, tp_pct, sl_pct, max_hold, atr_mult = exit_cfg

    # Precompute per-ticker series and signal dates.
    signals = {}
    prep = {}
    for t, bars in history.items():
        closes = [x[4] for x in bars]
        e50, e200 = ema_series(closes, 50), ema_series(closes, 200)
        prep[t] = (bars, closes)
        for i in range(1, len(bars) - 1):
            try:
                if sig_fn(bars, closes, i, e50, e200):
                    signals.setdefault(bars[i][0], []).append((t, i))
            except (IndexError, ValueError):
                continue

    dates = sorted({x[0] for bars in history.values() for x in bars})
    if date_from:
        dates = [d for d in dates if d >= date_from]
    if date_to:
        dates = [d for d in dates if d <= date_to]

    equity, pos, trades = START_EQUITY, None, []
    peak, max_dd = equity, 0.0

    for d in dates:
        if pos:
            bars, _ = prep[pos["t"]]
            idx = pos["idx"] + pos["days"] + 1
            if idx < len(bars) and bars[idx][0] == d:
                _, o, hi, lo, close, _ = bars[idx]
                entry, exit_px, reason = pos["entry"], None, None
                if atr_mult:  # ATR trailing stop
                    pos["peak"] = max(pos["peak"], hi)
                    trail = pos["peak"] - atr_mult * pos["atr"]
                    if lo <= trail:
                        exit_px, reason = trail, "trail"
                    elif pos["days"] >= max_hold:
                        exit_px, reason = close, "time"
                else:
                    if lo <= entry * (1 - sl_pct):      # stop assumed first (conservative)
                        exit_px, reason = entry * (1 - sl_pct), "stop"
                    elif hi >= entry * (1 + tp_pct):
                        exit_px, reason = entry * (1 + tp_pct), "target"
                    elif pos["days"] >= max_hold:
                        exit_px, reason = close, "time"
                if exit_px is not None:
                    fill = exit_px * (1 - SLIPPAGE)
                    pnl = (fill - entry) * pos["sh"]
                    equity += pnl
                    trades.append({"pnl": pnl, "pct": (fill / entry - 1) * 100,
                                   "reason": reason, "t": pos["t"]})
                    pos = None
                else:
                    pos["days"] += 1

        if not pos and d in signals:
            t, i = signals[d][0]
            bars, _ = prep[t]
            if i + 1 < len(bars):
                entry = bars[i + 1][1] * (1 + SLIPPAGE)
                a = atr_at(bars, i) or (entry * 0.02)
                # Size as a fraction of CURRENT equity so gains compound, making
                # the result comparable to a 100%-invested buy-and-hold benchmark.
                stake = equity * POSITION_PCT
                pos = {"t": t, "idx": i, "entry": entry, "sh": stake / entry,
                       "days": 0, "atr": a, "peak": entry}
        peak = max(peak, equity)
        if peak > 0:
            max_dd = max(max_dd, (peak - equity) / peak)

    wins = [x for x in trades if x["pnl"] > 0]
    losses = [x for x in trades if x["pnl"] <= 0]
    gw = sum(x["pnl"] for x in wins)
    gl = abs(sum(x["pnl"] for x in losses))
    return {"n": len(trades), "ret": (equity / START_EQUITY - 1) * 100,
            "win": (len(wins) / len(trades) * 100) if trades else 0.0,
            "pf": (gw / gl) if gl else (float("inf") if gw else 0.0),
            "dd": max_dd * 100}


def spy_bh(history, date_from=None, date_to=None):
    bars = history.get("SPY")
    if not bars:
        return float("nan")
    s = [b for b in bars if (date_from is None or b[0] >= date_from)
         and (date_to is None or b[0] <= date_to)]
    return (s[-1][4] / s[0][4] - 1) * 100 if len(s) > 1 else float("nan")


def grade(ins, oos, bench_in, bench_out):
    """Confidence grade. Punishes low trade counts and in-sample-only wins."""
    beat_in = ins["ret"] > bench_in
    beat_out = oos["ret"] > bench_out
    enough = oos["n"] >= MIN_TRADES_CREDIBLE and ins["n"] >= MIN_TRADES_CREDIBLE
    if beat_in and beat_out and enough and oos["pf"] > 1.2:
        return "MODERATE"          # deliberately the ceiling - see the caveats
    if beat_out and enough:
        return "LOW-MODERATE"
    if beat_out and not enough:
        return "LOW (too few trades)"
    if beat_in and not beat_out:
        return "NONE (in-sample only)"
    return "NONE"


def main():
    print("=" * 78)
    print("MULTI-STRATEGY BACKTEST - 10 strategies x 3 exit schemes")
    print("=" * 78)
    history = load_history(WATCHLIST, YEARS)
    dates = sorted({b[0] for bars in history.values() for b in bars})
    mid = dates[len(dates) // 2]
    bench_full, bench_in, bench_out = (spy_bh(history), spy_bh(history, date_to=mid),
                                       spy_bh(history, date_from=mid))
    print(f"\nPeriod: {dates[0]} -> {dates[-1]}   (split at {mid})")
    print(f"SPY buy & hold: full {bench_full:+.1f}% | "
          f"1st half {bench_in:+.1f}% | 2nd half {bench_out:+.1f}%")
    print(f"\n{'Strategy':<34}{'Exit':<16}{'Trades':>7}{'Win%':>6}"
          f"{'PF':>6}{'MaxDD':>7}{'OOS ret':>9}  Confidence")
    print("-" * 78)

    rows = []
    for sname, fn in STRATEGIES.items():
        for ecfg in EXITS:
            ins = simulate(history, fn, ecfg, date_to=mid)
            oos = simulate(history, fn, ecfg, date_from=mid)
            g = grade(ins, oos, bench_in, bench_out)
            rows.append((sname, ecfg[0], ins, oos, g))
            print(f"{sname[:33]:<34}{ecfg[0][:15]:<16}{oos['n']:>7}"
                  f"{oos['win']:>6.0f}{oos['pf']:>6.2f}{oos['dd']:>7.1f}"
                  f"{oos['ret']:>+9.2f}  {g}")

    survivors = [r for r in rows if r[4].startswith(("MODERATE", "LOW-MODERATE"))]
    print("\n" + "=" * 78)
    print(f"SURVIVORS (beat SPY out-of-sample with enough trades): {len(survivors)} "
          f"of {len(rows)} tested")
    print("=" * 78)
    if survivors:
        for s, e, ins, oos, g in sorted(survivors, key=lambda r: -r[3]["ret"]):
            print(f"  {g:<20} {s} | {e}")
            print(f"     in-sample {ins['ret']:+.1f}% ({ins['n']} trades)  ->  "
                  f"out-of-sample {oos['ret']:+.1f}% ({oos['n']} trades)")
    else:
        print("  NONE. Not one strategy beat buy-and-hold out-of-sample.")
        print("  That is a real result, not a bug. It is what most retail")
        print("  strategies do once fees, slippage and honest testing apply.")

    print("\n" + "=" * 78)
    print("HOW TO READ THIS - the part that matters")
    print("=" * 78)
    print(f"- {len(rows)} combinations were tested. By luck alone, ~1 in 20 looks good")
    print("  at random. That is why only OUT-OF-SAMPLE results count here.")
    print("- 'MODERATE' is the highest grade this script will give. Nothing about a")
    print("  backtest justifies 'high confidence' - real money behaves worse.")
    print("- Fewer than 30 trades means the result is noise, whatever the return.")
    print("- Daily bars; your live bot checks every 30 min, so live results differ.")
    print("- Same-day target+stop touches are counted as STOPS (conservative).")
    print("- DO NOT tune parameters until something looks good. That is overfitting,")
    print("  and it is the reason most backtested systems lose money live.")
    print("- Beating SPY on paper for 2.5 years is still not proof of an edge.")
    print(f"- LONG-ONLY: every strategy here buys. No shorts, no puts. In a market")
    print("  that rose +79% over this window, long-only flatters results; a bear")
    print("  market would look very different.")
    print(f"- Sizing is {POSITION_PCT:.0%} of equity per trade, one position at a time,")
    print("  compounding. That makes it comparable to 100%-invested buy-and-hold,")
    print("  but it is also concentrated risk - all eggs in one stock at a time.")


if __name__ == "__main__":
    main()
