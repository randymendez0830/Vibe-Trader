#!/usr/bin/env bash
# Your assistant's day. Two things run together:
#
#   1. WATCHDOG  — every 3 minutes while the market is open. Plain Python, no
#      LLM: reads your real Alpaca positions, gets live prices, and texts you
#      the instant a stop or target is hit. Optionally closes stopped-out
#      positions automatically. Costs no Claude credits.
#
#   2. TIMED CHECK-INS — a handful of LLM briefings at set times (pre-market,
#      the open, entry window, midday, power hour, end of day). These are the
#      "here's what's happening" texts.
#
# Start it once and leave the window open:
#     caffeinate -i ./alerts.sh
#
# Add --auto-exit to have stopped-out positions closed for you:
#     caffeinate -i ./alerts.sh --auto-exit
#
# Ctrl+C to stop. Times are US Eastern regardless of your Mac's timezone.
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source .venv/bin/activate

AUTO_EXIT=""
[[ " $* " == *" --auto-exit "* ]] && AUTO_EXIT="--auto-exit"

STAMP_DIR="$HOME/.vibe-trading/checkin_stamps"
mkdir -p "$STAMP_DIR"

et() { python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;print(datetime.now(ZoneInfo("America/New_York")).strftime("%Y-%m-%d %H%M %u"))'; }

send() {  # send "<text>" -> Telegram
  python3 - "$1" <<'PY' || true
import json,pathlib,sys
try: import requests
except ImportError: sys.exit(0)
vt=pathlib.Path.home()/".vibe-trading"
try:
    tg=json.loads((vt/"agent.json").read_text())["channels"]["telegram"]
except Exception: sys.exit(0)
requests.post(f"https://api.telegram.org/bot{tg['token']}/sendMessage",
              data={"chat_id":tg["allow_from"][0],"text":sys.argv[1]},timeout=20)
PY
}

# briefing <slot-name> <prompt>
briefing() {
  local slot="$1" prompt="$2" today stamp out summary
  today="$(et | cut -d' ' -f1)"
  stamp="$STAMP_DIR/${today}_${slot}"
  [[ -f "$stamp" ]] && return 0          # already sent today
  echo "[$(date '+%H:%M')] briefing: $slot"
  out="$(mktemp)"
  local now_et mkt
  now_et="$(python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;print(datetime.now(ZoneInfo("America/New_York")).strftime("%A %Y-%m-%d %I:%M %p ET"))')"
  mkt="$(python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;n=datetime.now(ZoneInfo("America/New_York"));m=n.hour*60+n.minute;print("OPEN" if (n.weekday()<5 and 570<=m<960) else "CLOSED")')"
  vibe-trading run --no-rich -p "CURRENT TIME: $now_et. US MARKET IS $mkt. Trust these facts; do not infer the time from data timestamps.

$prompt

Rules: read positions from the Alpaca connector, never from memory. Get live prices via get_market_data source=\"finnhub\". Keep the whole reply under 900 characters, plain text, no markdown tables/headers/asterisks — it is going to a phone. Lead with the single most important thing. Do NOT promise future alerts or check-ins." >"$out" 2>&1 || true
  summary="$(python3 - "$out" <<'PY'
import pathlib,re,sys
raw=pathlib.Path(sys.argv[1]).read_text()
for m in ("in plain terms","bottom line","summary:"):
    i=raw.lower().rfind(m)
    if i!=-1: raw=raw[i:]; break
else: raw=raw[-1200:]
for cut in ("\n--show","\nRun ID","\nRun dir","\nStatus:","\nElapsed"):
    j=raw.find(cut)
    if j!=-1: raw=raw[:j]
raw=re.sub(r"[*#`>|]","",raw)
print(re.sub(r"\n{3,}","\n\n",raw).strip()[:1400])
PY
)"
  [[ -n "$summary" ]] && send "$3 $slot
$summary"
  rm -f "$out"
  touch "$stamp"
}

echo "Assistant running."
echo "  Watchdog : every 3 min while market is open ${AUTO_EXIT:+(AUTO-EXIT ON)}"
echo "  Briefings: 9:00 premarket | 9:32 open | 9:45 entry | 12:00 midday | 15:00 power hour | 15:45 close"
echo "Leave this window open. Ctrl+C to stop."

while true; do
  read -r DAY HM DOW <<<"$(et)"
  hm=$((10#$HM))

  if [ "$DOW" -le 5 ]; then
    # ---- timed briefings (each fires once per day) ----
    if   [ "$hm" -ge 900 ] && [ "$hm" -lt 930 ]; then
      briefing premarket "PRE-MARKET BRIEFING. Check overnight and pre-market news for my watchlist and any open positions, plus any earnings released this morning. Note pre-market gaps and what you'll be watching at the open. No trades — market is closed." "🌅 Pre-market"
    elif [ "$hm" -ge 932 ] && [ "$hm" -lt 943 ]; then
      briefing open "OPENING BELL REACTION. The market just opened. Report how my open positions and watchlist opened versus yesterday's close: gap up, gap down, or flat. Flag anything moving hard. Per the checklist, do NOT enter new positions in the first 30 minutes — just report." "🔔 Open"
    elif [ "$hm" -ge 1000 ] && [ "$hm" -lt 1015 ]; then
      briefing entry "ENTRY WINDOW. The opening range is set and the no-entry window has passed. Load the pre-trade-checklist skill and run it on the best candidate. Report the checklist verdict: TRADE / WAIT FOR <trigger> / NO TRADE. NO TRADE is a fine answer." "🎯 Entry window"
    elif [ "$hm" -ge 1200 ] && [ "$hm" -lt 1215 ]; then
      briefing midday "MIDDAY CHECK. Report open positions with P&L, whether any is near its stop or target, and whether the morning thesis still holds. Midday is chop — be skeptical of new entries." "☀️ Midday"
    elif [ "$hm" -ge 1500 ] && [ "$hm" -lt 1515 ]; then
      briefing powerhour "POWER HOUR. Last hour of trading. Report positions and P&L, and say clearly which should be closed before the bell versus held overnight, and why. Flag any option expiring soon." "⚡ Power hour"
    elif [ "$hm" -ge 1545 ] && [ "$hm" -lt 1600 ]; then
      briefing close "END OF DAY. Summarize the day: trades taken, P&L in dollars and percent, what worked, what didn't. Note anything expiring or needing attention tomorrow. Write one honest lesson to memory." "🌆 Close"
    fi

    # ---- watchdog: fast, cheap, every loop while open ----
    if [ "$hm" -ge 930 ] && [ "$hm" -lt 960 ]; then
      python watchdog.py --quiet $AUTO_EXIT || true
    fi
  fi

  sleep 180   # 3 minutes
done
