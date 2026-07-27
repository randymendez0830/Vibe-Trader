#!/usr/bin/env bash
# Send yourself a briefing RIGHT NOW, on demand.
#
#   ./brief_now.sh                  general status briefing
#   ./brief_now.sh entry            run the full pre-trade checklist
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

# Must match alerts.sh, or an on-demand briefing looks at different names than
# the scheduled ones. Override per run: VIBE_WATCHLIST="CDNS, NVDA" ./brief_now.sh
WATCHLIST="${VIBE_WATCHLIST:-SPY, QQQ, AAPL, NVDA, MSFT, TSLA, AMD, GOOGL, AMZN, META}"

ARG="${1:-status}"
case "$ARG" in
  status)
    TASK="STATUS BRIEFING. Report my open positions with P&L in dollars and percent, cash, and whether anything is near its stop or target. Then one line on how my watchlist is trading right now and anything notable in the news."
    LABEL="Status update" ;;
  entry)
    TASK="ENTRY CHECK. Load the pre-trade-checklist skill and run all eight sections on the best candidate from my watchlist. Report the verdict: TRADE / WAIT FOR <specific trigger> / NO TRADE, and which veto stopped it if any. NO TRADE is a good answer."
    LABEL="Entry check" ;;
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

MY WATCHLIST is exactly: $WATCHLIST. When a briefing says 'my watchlist', it means these names and only these. Do not substitute your own list, and if you flag a ticker outside it, say plainly that it is NOT being monitored and must be added to VIBE_WATCHLIST to be watched again.

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
