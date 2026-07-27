#!/usr/bin/env bash
# Your assistant's trading day. Two things run together:
#
#   1. WATCHDOG  — every 3 minutes while the market is open. Plain Python, no
#      LLM: reads your real Alpaca positions, gets live prices, and texts you
#      the instant a stop or target is hit. Optionally closes stopped-out
#      positions automatically. Costs no Claude credits.
#
#   2. TIMED BRIEFINGS — LLM check-ins at set times (pre-market, the open,
#      entry window, midday, power hour, close). The "here's what's happening"
#      texts. Each fires once per day.
#
# Start it once and leave the window open:
#     caffeinate -i ./alerts.sh
#
# Add --auto-exit to have stopped-out positions closed for you:
#     caffeinate -i ./alerts.sh --auto-exit
#
# Ctrl+C to stop. All times are US Eastern, whatever your Mac's timezone is.
#
# NOTE: deliberately no Python heredocs inside $(...) here -- macOS ships bash
# 3.2, which mis-parses those. All Python lives in notify.py / watchdog.py.
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source .venv/bin/activate

AUTO_EXIT=""
case " $* " in *" --auto-exit "*) AUTO_EXIT="--auto-exit" ;; esac

# Which LLM briefings to run. The watchdog is free (no LLM); briefings are the
# ONLY thing that costs Claude credits, so this is your cost dial.
#   all six  ~$6-19/mo | three ~$3-9/mo | two ~$2-6/mo
# Override per run:   VIBE_BRIEFINGS="premarket,close" ./alerts.sh
BRIEFINGS="${VIBE_BRIEFINGS:-premarket,open,entry,midday,powerhour,close}"

# The names the briefings look at. This USED to be undefined -- the prompts said
# "my watchlist" and never said what that was, so the model invented a different
# list every run. A ticker mentioned once (CDNS) would silently never be looked
# at again. Add names here, or override for one run:
#   VIBE_WATCHLIST="SPY, NVDA, CDNS" ./start.sh
WATCHLIST="${VIBE_WATCHLIST:-SPY, QQQ, AAPL, NVDA, MSFT, TSLA, AMD, GOOGL, AMZN, META}"

enabled() {  # enabled <slot> -> 0 if that briefing should run
  case ",${BRIEFINGS}," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

STAMP_DIR="$HOME/.vibe-trading/checkin_stamps"
mkdir -p "$STAMP_DIR"

# Eastern-time helpers (single-quoted -c strings: safe in bash 3.2)
et_stamp() { python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;print(datetime.now(ZoneInfo("America/New_York")).strftime("%Y-%m-%d %H%M %u"))'; }
et_pretty() { python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;print(datetime.now(ZoneInfo("America/New_York")).strftime("%A %Y-%m-%d %I:%M %p ET"))'; }
et_mkt() { python3 -c 'from datetime import datetime;from zoneinfo import ZoneInfo;n=datetime.now(ZoneInfo("America/New_York"));m=n.hour*60+n.minute;print("OPEN" if (n.weekday()<5 and 570<=m<960) else "CLOSED")'; }

# briefing <slot> <prompt> <emoji-label>
briefing() {
  slot="$1"; prompt="$2"; label="$3"
  today=$(et_stamp | cut -d' ' -f1)
  stamp="$STAMP_DIR/${today}_${slot}"
  if [ -f "$stamp" ]; then return 0; fi          # already sent today

  echo "[$(date '+%H:%M')] briefing: $slot"
  out=$(mktemp)
  sumf=$(mktemp)
  now_et=$(et_pretty)
  mkt=$(et_mkt)
  # Read the account in plain Python and paste it into the prompt. Telling the
  # model to "look it up" is not enough -- it once reported "no open positions"
  # while two were live. Injected facts cannot be forgotten.
  acct=$(python portfolio.py snapshot 2>/dev/null)

  vibe-trading run --no-rich -p "CURRENT TIME: $now_et. US MARKET IS $mkt. Trust these two facts absolutely; do not infer the time or market state from data timestamps.

$acct

MY WATCHLIST is exactly: $WATCHLIST. When a briefing says 'my watchlist', it means these names and only these. Do not substitute your own list, and if you flag a ticker outside it, say plainly that it is NOT being monitored and must be added to VIBE_WATCHLIST to be watched again.

$prompt

RULES: The account snapshot above is authoritative for positions, P&L, cash and orders -- use it and never contradict it from memory. Get current prices via get_market_data with source=\"finnhub\" (real time); Alpaca quotes are delayed. Keep the whole reply under 900 characters, plain text only, no markdown tables, headers or asterisks -- it is going to a phone. Lead with the single most important thing. Do NOT promise future alerts, pings or check-ins.

FORMAT: after any analysis, output your final phone message on its own, introduced by a line containing exactly BRIEFING: and nothing else. Everything after that line is what gets texted, so make it complete and self-contained -- do not start mid-thought, and do not reference the analysis above it." >"$out" 2>&1 || true

  python notify.py summarize "$out" >"$sumf"
  summary=$(cat "$sumf")
  if [ -n "$summary" ]; then
    # Real numbers ride along in the message itself, and flag any claim of
    # being flat that the account contradicts.
    footer=$(python portfolio.py footer "$sumf" 2>/dev/null)
    python notify.py send "$label
$summary

$footer" || true
  fi
  rm -f "$out" "$sumf"
  touch "$stamp"
}

echo "Assistant running."
if [ -n "$AUTO_EXIT" ]; then
  echo "  Watchdog : every 3 min while open  (AUTO-EXIT ON: stops will close positions)"
else
  echo "  Watchdog : every 3 min while open  (alert only -- add --auto-exit to close)"
fi
echo "  Briefings: $BRIEFINGS"
echo "             (set VIBE_BRIEFINGS to trim cost, e.g. VIBE_BRIEFINGS=premarket,close)"
echo "Leave this window open. Ctrl+C to stop."

while true; do
  # Parse "YYYY-MM-DD HHMM DOW" with plain parameter expansion -- no positional
  # clobbering, no herestrings, safe under bash 3.2 + set -u.
  et_line=$(et_stamp)
  if [ -z "$et_line" ]; then sleep 60; continue; fi
  HM=${et_line#* }; HM=${HM%% *}
  DOW=${et_line##* }
  hm=$((10#$HM))

  if [ "$DOW" -le 5 ]; then
    if [ "$hm" -ge 900 ] && [ "$hm" -lt 930 ]; then
      enabled premarket && briefing premarket "PRE-MARKET BRIEFING. Check overnight and pre-market news for my watchlist and any open positions, plus any earnings reported this morning. Note pre-market gaps and the specific levels you'll watch at the open. The market is closed, so no trades." "Pre-market briefing"
    elif [ "$hm" -ge 932 ] && [ "$hm" -lt 945 ]; then
      enabled open && briefing open "OPENING BELL REACTION. The market just opened. Report how my open positions and watchlist opened versus yesterday's close: gap up, gap down or flat, and anything moving hard. Per the checklist, do NOT enter new positions in the first 30 minutes -- report only." "Opening bell"
    elif [ "$hm" -ge 1000 ] && [ "$hm" -lt 1015 ]; then
      enabled entry && briefing entry "ENTRY WINDOW. The opening range is set and the no-entry window has passed. Load the pre-trade-checklist skill and run it fully on the best candidate. Report the verdict: TRADE / WAIT FOR <specific trigger> / NO TRADE. NO TRADE is a perfectly good answer." "Entry window"
    elif [ "$hm" -ge 1200 ] && [ "$hm" -lt 1215 ]; then
      enabled midday && briefing midday "MIDDAY CHECK. Report open positions with P&L in dollars and percent, whether any is near its stop or target, and whether this morning's thesis still holds. Midday is chop -- be skeptical of new entries." "Midday check"
    elif [ "$hm" -ge 1500 ] && [ "$hm" -lt 1515 ]; then
      enabled powerhour && briefing powerhour "POWER HOUR. Final hour. Report positions and P&L, and say clearly which should be closed before the bell versus held overnight, with the reason. Flag any option nearing expiry." "Power hour"
    elif [ "$hm" -ge 1545 ] && [ "$hm" -lt 1600 ]; then
      enabled close && briefing close "END OF DAY. Summarize today: trades taken, P&L in dollars and percent, what worked and what did not. Note anything expiring or needing attention tomorrow. Write one honest lesson to memory." "Market close"
    fi

    # Watchdog: cheap and fast, runs every loop while the market is open.
    if [ "$hm" -ge 930 ] && [ "$hm" -lt 1600 ]; then
      python watchdog.py --quiet $AUTO_EXIT || true
    fi
  fi

  sleep 180
done
