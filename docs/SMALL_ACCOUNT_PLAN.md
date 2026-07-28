# The $200–500 real-money plan (and the Robinhood question)

You asked for the bot on your Robinhood account with $200–500, trading call
options, growing the money. Here is the honest version of that plan — what
works, what the rules of the market physically prevent, and the path that gets
you the same outcome without the parts that would quietly kill the account.

---

## 1. Robinhood: there is no legitimate API

As of 2026, Robinhood's only official developer API is for **crypto**. For
stocks and options there is no documented, supported API for individuals —
the "Robinhood MCP servers" you can find on GitHub are all built on
reverse-engineered libraries (`robin_stocks` and friends) that log in by
pretending to be the mobile app.

Using one means, concretely:

- **It violates Robinhood's terms of service.** They can (and do) restrict or
  close accounts for automated access. Your money is then frozen behind
  support tickets.
- **It breaks without warning.** Every app update or 2FA change can kill the
  integration — possibly while you have an open position and the bot is the
  only thing watching the stop.
- **There is no paper mode.** First trade is real money. We built this whole
  system around proving things on paper first; Robinhood makes that
  impossible.

**The safe way to "have the bot on Robinhood" is signal mode:** the bot does
everything except press the button — full analysis, checklist, entry, stop,
target, sized for your real balance — and texts you a trade card. You tap it
into the Robinhood app yourself in 30 seconds. No ToS risk, works with any
balance, and you stay the final gate on every real dollar. The execution-speed
loss is real but small at this account size.

For genuine hands-off automation with real money, the broker is **Alpaca
Live** — an actual supported API, and the exact connector this bot already
uses, so the code you validated on paper is the code that goes live.

## 2. The math of $200–500 in call options

This is the part nobody selling bots will tell you.

**One contract is your whole account.** A near-the-money SPY or AAPL call a
few weeks out costs roughly $200–600. Your first position is 50–100%+ of the
account. The desk rule this bot enforces — risk 1–2% per trade — needs about
$10,000–$25,000 before a single options contract fits inside it. At $300, the
bot cannot size correctly no matter how smart it is; every trade is all-in or
close to it.

**The PDT rule caps day trading.** Under $25,000 equity, a margin account gets
three day trades per rolling five business days; the fourth flags you as a
pattern day trader and freezes trading for 90 days. A cash account escapes PDT
but must wait for funds to settle (T+1), so a $300 cash account gets roughly
one round trip per day, and a loss shrinks tomorrow's entire budget.

**Cheap options are lottery tickets.** The contracts a $300 account can afford
several of are far out-of-the-money shorter-dated ones — exactly the 0DTE-style
gambles this desk banned after losing money on them. The affordable version of
"call options on a small account" is the worst version.

**A realistic expectation:** a $200–500 options account doesn't compound; it
survives until one or two all-in losers end it. If you fund this, fund it as
**tuition** — money whose job is to teach you how live fills, spreads, and
your own reactions differ from paper — not as a seed that grows.

## 3. "Proven builds" — what actually exists

There is no publicly verifiable retail LLM trading bot with an audited live
track record. What circulates is marketing, backtests (we saw how ours went:
**29 of 30 strategies failed honest out-of-sample testing**), and survivorship
— you hear from the person whose bot 10x'd, not the thousand whose bots went
to zero. Academic tests of LLM traders show inconsistent results that mostly
disappear after costs.

The only proof that matters is **your own paper record**, which conveniently
is the machine you already have running. That is the moat: not a smarter bot,
but an honest one with receipts.

## 4. The actual plan, phase by phase

### Phase 1 — Validation (now → ~6 weeks of paper trading)

Run exactly what is running today: `--auto-exit --auto-trade` on paper, max
$2,000/position, 2 trades/day, watchdog exits both sides, every action
verified from the broker.

**Go-live gate — ALL of these, measured off the Alpaca paper history:**

| Metric | Bar |
|---|---|
| Closed trades | ≥ 20 (fewer is luck, not evidence) |
| Profit factor | ≥ 1.3 (gross wins ÷ gross losses) |
| Max drawdown | ≤ 10% of the account |
| Hallucinated positions/orders in texts | 0 (the `Verified` footer is the check) |
| Missed stops (position past stop with no exit + no alert) | 0 |

Miss any bar → stay on paper. The market will still be there.

### Phase 2 — First real dollars ($500, stocks, Alpaca Live)

- **Cash account** (no PDT trap), **$500**, **stocks only**, swing timeframe —
  the wide +10%/−5% exits that won the backtest are multi-day holds anyway.
- One position at a time, ~$400 max, watchdog exits both sides.
- Same code, new keys, plus the real-money mandate the system already
  requires. **Kill criterion:** account under $400 (−20%) → back to paper.
  Automatic, not a judgment call.

### Phase 3 — Options, when the account has earned them

Defined-risk spreads (max loss capped at entry) become sizeable at roughly
**$2,000–5,000**, where a $100–200-risk spread is a sane 4–5% of the account.
Alpaca's options API supports multi-leg orders; the bot's connector currently
places stock orders only, so this phase needs connector work — which I'd do
when Phase 2 has a record that justifies it.

Want Robinhood in the loop sooner? Run **signal mode** in parallel from
Phase 1: the bot texts the full trade card and you execute manually in RH.
You get the "bot + my Robinhood money" experience with you as the gate.

## 5. The overhead problem nobody prices in

Claude credits run ~$10–30/month with trading passes on. On a $100k paper
account that's noise. **On a $500 real account it's 2–6% per month** — a
hedge-fund fee structure on a lunch-money account. The bot must beat the
market by that much just to break even.

At Phase 2 size, trim to `VIBE_BRIEFINGS="close"` and
`VIBE_TRADE_TIMES="1030,1400"` (~$8–15/mo). The watchdog — the thing that
actually protects money — costs nothing. This overhead, more than any rule,
is why "start with $200–500 of options" fails structurally: the smaller the
account, the more the thinking costs relative to what it manages.

## 6. Bottom line

| Your ask | Verdict |
|---|---|
| Bot trades my Robinhood via MCP | Unofficial API only — ToS + lockout risk. Use **signal mode** on RH, or Alpaca Live for real automation |
| $200–500 in call options | Structurally broken: sizing impossible, PDT, lottery-priced contracts. $500 → **stocks** first; options at $2k+ as defined-risk spreads |
| Make it grow | Nothing honest promises growth. The plan: **prove edge on paper → tiny real stocks → earned options** — with hard gates and kill criteria at each step |

The uncomfortable truth: at this account size, the discipline — which is free —
matters far more than the automation. The bot's job in Phase 1 is to prove it
has any edge at all. Most strategies don't; ours tested 1-for-30. Let the
paper record decide, not the plan.
