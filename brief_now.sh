#!/usr/bin/env bash
# Send yourself a briefing RIGHT NOW, on demand.
#
#   ./brief_now.sh                  general status briefing
#   ./brief_now.sh entry            run the full pre-trade checklist
#   ./brief_now.sh call             signal mode: one affordable swing-call card
#                                   sized for a small Robinhood account
#   ./brief_now.sh "how is AMD?"    any question you like
#
# Useful for testing that texts arrive correctly, or when you just want an
# update between the scheduled check-ins. Does not touch the daily stamps, so
# it never suppresses a scheduled briefing.
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source .venv/bin/activate

now_et=$(python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;print(datetime.now(ZoneInfo("America/New_York")).strftime("%A %Y-%m-%d %I:%M %p ET"))')
mkt=$(python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;n=datetime.now(ZoneInfo("America/New_York"));m=n.hour*60+n.minute;print("OPEN" if (n.weekday()<5 and 570<=m<960) else "CLOSED")')

# Same watchlist resolution as alerts.sh: VIBE_WATCHLIST env override, then
# ~/.vibe-trading/watchlist.txt (one ticker per line), then the fallback.
if [ -n "${VIBE_WATCHLIST:-}" ]; then
  WATCHLIST="$VIBE_WATCHLIST"
else
  WATCHLIST=$(python3 -c 'import pathlib;p=pathlib.Path.home()/".vibe-trading/watchlist.txt";print(", ".join(l.strip().upper() for l in p.read_text().splitlines() if l.strip() and not l.strip().startswith("#")) if p.exists() else "")' 2>/dev/null)
  [ -n "$WATCHLIST" ] || WATCHLIST="SPY, QQQ, AAPL, NVDA, MSFT, TSLA, AMD, GOOGL, AMZN, META"
fi

ARG="${1:-status}"
case "$ARG" in
  status)
    TASK="STATUS BRIEFING. Report my open positions with P&L in dollars and percent, cash, and whether anything is near its stop or target. Then one line on how my watchlist is trading right now and anything notable in the news."
    LABEL="Status update" ;;
  entry)
    TASK="ENTRY CHECK. Load the pre-trade-checklist skill and run all eight sections on the best candidate from my watchlist. Report the verdict: TRADE / WAIT FOR <specific trigger> / NO TRADE, and which veto stopped it if any. NO TRADE is a good answer."
    LABEL="Entry check" ;;
  call)
    TASK="CALL SIGNAL for my ~\$200 Robinhood options budget. Find the ONE best swing CALL setup right now (watchlist first, but any liquid US name is allowed for this scan), or say NO TRADE. NON-NEGOTIABLE FILTERS: expiry 30-45 days out, never same-week; strike at-the-money or one strike in-the-money, delta near 0.5 -- NOT cheap far out-of-the-money strikes, those are lottery tickets and are banned; estimated premium \$120 or less, which usually means an underlying priced under about \$80; decent option volume so the bid-ask spread is tight; no earnings report inside the next 3 weeks. Run the pre-trade-checklist on the underlying first -- any veto means NO TRADE. If the best setup's contract costs over \$120, say so and either name an affordable alternative or say NO TRADE; do NOT solve affordability by going further out-of-the-money. If you cannot get a live option quote, estimate the premium from the stock price and volatility and label it ESTIMATE -- I will verify the real price on Robinhood before entering. OUTPUT A TRADE CARD with exact numbers I can tap into Robinhood: ticker; strike and expiry date; estimated cost per contract; 2-line thesis; underlying stop (exit if the stock closes below this level); profit rule (sell at +50% to +100% of premium, or on thesis break); time rule (sell by 21 days to expiry no matter what -- never hold to expiration); and the one thing that would kill the idea. NO TRADE with a reason is a perfectly good card."
    LABEL="Call signal" ;;
  *)
    TASK="The user asks: $ARG"
    LABEL="On-demand briefing" ;;
esac

echo "Running briefing ($ARG)... this takes ~30-60s."
OUT=$(mktemp)
SUMF=$(mktemp)
trap 'rm -f "$OUT" "$SUMF"' EXIT

# Ground truth, read in plain Python before the model runs (see portfolio.py).
ACCT=$(python portfolio.py snapshot 2>/dev/null)

vibe-trading run --no-rich -p "CURRENT TIME: $now_et. US MARKET IS $mkt. Trust these two facts absolutely; do not infer the time or market state from data timestamps.

$ACCT

MY WATCHLIST is exactly: $WATCHLIST. When a briefing says 'my watchlist', it means these names and only these. Do not substitute your own list, and if you flag a ticker outside it, say plainly that it is NOT being monitored and must be added to ~/.vibe-trading/watchlist.txt to be watched again. The list is long on purpose: lead with the names that have fresh news or a notable move today, and skip the quiet ones -- you do not need to cover every name every time.

$TASK

RULES: The account snapshot above is authoritative for positions, P&L, cash and orders -- use it and never contradict it from memory. Get current prices via get_market_data with source=\"finnhub\" (real time); Alpaca quotes are delayed. Keep the whole reply under 900 characters, plain text only, no markdown tables, headers or asterisks -- it is going to a phone. Lead with the single most important thing. Do NOT promise future alerts, pings or check-ins.

FORMAT: after any analysis, output your final phone message on its own, introduced by a line containing exactly BRIEFING: and nothing else. Everything after that line is what gets texted, so make it complete and self-contained -- do not start mid-thought, and do not reference the analysis above it." >"$OUT" 2>&1 || true

python notify.py summarize "$OUT" >"$SUMF"
SUMMARY=$(cat "$SUMF")
if [ -z "$SUMMARY" ]; then
  echo "No summary produced. Last lines of raw output:"
  tail -n 20 "$OUT"
  exit 1
fi
FOOTER=$(python portfolio.py footer "$SUMF" 2>/dev/null)

echo "----- what will be texted -----"
printf '%s\n\n%s\n' "$SUMMARY" "$FOOTER"
echo "-------------------------------"
if python notify.py send "$LABEL
$SUMMARY

$FOOTER"; then
  echo "Sent to Telegram."
else
  echo "Telegram send failed (see error above)."
  exit 1
fi
