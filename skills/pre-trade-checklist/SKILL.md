---
name: pre-trade-checklist
description: "MANDATORY pre-trade gate. Load and complete this BEFORE proposing or placing any trade. Eight checks, hard vetoes, and explicit risk math. A trade is only valid if every veto passes and the checklist score clears the bar. Use together with options-desk."
category: risk
---

# Pre-Trade Checklist — the gate every trade must pass

An amateur asks "will this go up?" A professional asks "does this setup pass my
checklist, and where exactly am I wrong?" You do the second. **Prediction is not
the job — screening out bad trades is the job.** Most of your value comes from
the trades you refuse.

Work the eight sections in order. **Any single VETO = NO TRADE. No exceptions,
no overrides, no "but this one looks really good."** State each veto result
explicitly so the user can see the work.

---

## 1. Market regime — top down, before the ticker

You cannot swim against the tide. Check, in this order:

- **SPY and QQQ trend** on the daily and the current intraday. Are they above or
  below their 20-day MA and VWAP? Rising or falling today?
- **Breadth:** is the move broad or is one name carrying the index?
- **Sector:** is the ticker's sector leading or being sold? Buying a chip name
  while semiconductors are in a sector-wide selloff is fighting the tide — that
  is precisely how the AMD trade failed.
- **Volatility:** if VIX is elevated or spiking, widen stops, cut size, expect
  gaps.

🚫 **VETO:** long entry while SPY/QQQ are in a clear intraday downtrend AND the
ticker's sector is red, unless the name has its own fresh, verified bullish
catalyst strong enough to explain divergence.

## 2. Time of day — the clock is a filter

- **9:30–10:00 ET:** the opening range. Highest volatility, widest spreads,
  most false moves. **Do not initiate here** — let the range establish, then
  trade its break with confirmation.
- **10:00–11:30:** the best window. Real trend, real volume.
- **11:30–14:00:** midday chop. Breakouts fail here at a high rate. Be selective.
- **14:00–15:30:** institutional repositioning; trends resume.
- **After 15:30:** manage existing positions only. Do not open new ones.

🚫 **VETO:** new entry in the first 30 minutes, or after 15:30 ET.
🚫 **VETO:** opening any same-day-expiry (0DTE) option, ever. And no new
directional options position after 14:00 ET on a Friday (weekend decay + gap risk).

## 3. Catalyst — why THIS name, TODAY

- Find the actual reason for the move: earnings, guidance, upgrade/downgrade,
  product, macro print, sector news. Search it; never assume.
- **Fresh or stale?** A catalyst the market already digested is not an edge.
- **Read the market's reaction, not the headline.** This is the expert tell:
  a stock that gaps up on great news and then *sells off all day* is being
  **distributed into strength** — that is bearish, not bullish. AMD gapping
  +8% on five upgrades and closing red was the market rejecting the news.
  Never buy a failed gap just because the headline was good.
- **Bad-news drops are not dips.** Earnings miss, guidance cut, negative free
  cash flow, exec exit, legal/regulatory action = falling knife. Do not buy it.

🚫 **VETO:** no identifiable catalyst AND no clean technical level. "It's down a
lot" is not a thesis.
🚫 **VETO:** buying a large decline driven by fundamental deterioration.
🚫 **VETO:** new swing position within 2 trading days of the company's earnings,
or immediately before a scheduled macro event (FOMC, CPI, jobs) — that is a
coin flip, not a setup.

## 4. Level structure — where exactly, on more than one timeframe

Name the specific price levels. Vague reads are not tradeable.

- Prior day high/low, premarket high/low, opening-range high/low
- **VWAP** — the institutional benchmark. Longs work best above a rising VWAP;
  below it you are fighting the day's average buyer.
- Moving averages: 20 / 50 / 200 (intraday and daily)
- **Fibonacci retracement** off the most recent clean swing: 38.2%, 50%, 61.8%.
  The 61.8% level failing is a common thesis-killer — use it as your stop zone.
- Round numbers, prior swing highs/lows, unfilled gaps
- **Multi-timeframe alignment:** the entry timeframe (5m/15m) must agree with
  the 1h and daily. A 5-minute long inside a daily downtrend is a countertrend
  scalp at best — grade it down or pass.

🚫 **VETO:** entering directly into overhead resistance with no room to the
target.
🚫 **VETO:** entry timeframe conflicts with the daily trend and there is no
strong catalyst justifying the fight.

## 5. Confirmation — react, do not anticipate

- The level must be **tested and held**, not hoped for. Correct: "long only if
  it holds $205 and reclaims $210." Wrong: "it should bounce here."
- **Volume confirms.** A breakout on ≥1.5x average volume is real. A breakout on
  light volume is a trap. A high-volume *rejection* candle is a warning.
- Prefer **failed breakdowns / failed breakouts** — the highest-quality reversals,
  because they trap the crowd on the wrong side.
- Check the candle actually closed beyond the level rather than wicking through.

🚫 **VETO:** the trigger condition has not actually occurred yet. If the setup
requires confirmation you have not seen, the answer is WAIT, not enter.
🚫 **VETO:** chasing. If price has already run more than ~1/3 of the way to your
target before you got in, the trade is gone. Let it go.

## 6. Risk math — compute BEFORE entry, in this order

This ordering is not optional; getting it backwards is what blows up accounts.

1. **Stop first, from structure.** Where does the thesis become wrong? Below the
   held level, the Fib zone, or 1–1.5x ATR — not a round dollar figure you find
   emotionally tolerable.
2. **Risk per trade:** 0.5–1% of account equity. Never more than 2%.
3. **Then position size** = (account risk $) ÷ (entry − stop). The stop distance
   determines the size. A wide stop means a *small* position, not a wide risk.
4. **Reward:risk ≥ 2:1** measured to a **realistic** target — the next actual
   resistance level, not a fantasy. If the nearest resistance is closer than
   2× your stop distance, **skip the trade**.
5. **Liquidity:** tight spread, real volume. For options also check IV rank (are
   you overpaying for premium?), ≥ 2–8 weeks to expiry for swings, open interest,
   and the bid-ask. Wide spreads quietly eat the entire edge.

🚫 **VETO:** reward:risk under 2:1.
🚫 **VETO:** required size exceeds the 1–2% risk cap.
🚫 **VETO:** no defined stop, or a stop placed by dollar comfort instead of structure.
🚫 **VETO:** illiquid instrument or wide spread.

## 7. Portfolio heat — the trade you already have

- **Correlation:** AMD + NVDA + SMCI is *one* semiconductor bet, not three
  trades. Count correlated names as a single position for risk purposes.
- **Total heat:** sum the risk across all open positions. Cap it (e.g. 3–4% of
  equity at risk in total).
- **Daily loss limit:** once down ~2–3% on the day, stop trading for the day.
  This is the single most account-saving rule that exists.
- **Overtrading:** cap trades per day. Churn is a cost, and forced trades are
  bad trades.

🚫 **VETO:** this entry duplicates existing correlated exposure.
🚫 **VETO:** the daily loss limit has been hit.

## 8. Process discipline — the honest self-check

- Is this a setup on the written list, or am I improvising to feel busy?
- **Am I chasing?** Am I revenge-trading a loss? Would I take this exact trade
  if my last one had been a winner?
- Does the size match the actual conviction, or am I sizing up out of hope?
- **NO TRADE is always an available, and frequently the correct, answer.**
  A day with zero trades and zero losses is a good day.

---

## Required output format

Report the checklist result before any recommendation:

```
PRE-TRADE CHECKLIST — <TICKER>
1 Regime    : SPY/QQQ <trend>, sector <lead/lag>, VIX <level>  -> PASS/VETO
2 Timing    : <time ET>, window <name>                          -> PASS/VETO
3 Catalyst  : <headline + date/source, or "none found">         -> PASS/VETO
4 Levels    : VWAP <x>, 20/50/200MA <x>, Fib 38/50/61.8 <x>, S/R <x>, MTF <align?>
5 Confirm   : trigger <occurred / not yet>, volume <x avg>      -> PASS/VETO
6 Risk math : entry <x>, stop <x> (why), target <x> (why), R:R <n>:1,
              size <n> = <risk$> / <stop distance>, <n>% of equity -> PASS/VETO
7 Heat      : correlated exposure <y/n>, total heat <n>%, day P&L <n>% -> PASS/VETO
8 Process   : chasing? revenge? on-list setup?                  -> PASS/VETO

VETOES TRIGGERED: <list, or "none">
VERDICT: TRADE / WAIT FOR <specific trigger> / NO TRADE
CONVICTION: low | moderate | high  (+ the one thing that would raise it)
```

**If any veto triggered, the verdict is NO TRADE or WAIT — never TRADE.**
Do not soften a veto, do not average the score, and do not proceed because the
idea feels compelling. The checklist exists precisely for the moments when a bad
trade feels good.
