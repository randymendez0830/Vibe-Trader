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
STOPS_ONLY=""
case " $* " in *" --stops-only "*) STOPS_ONLY="--stops-only" ;; esac
# Placing orders is opt-in and explicit. Without this flag nothing ever buys.
AUTO_TRADE=""
case " $* " in *" --auto-trade "*) AUTO_TRADE="yes" ;; esac

# When to look for a new trade. Never before 10:00 (the checklist vetoes the
# first 30 minutes) and never after 15:30. Default starts at 10:30, not 10:00:
# at 10:00 the opening range has *just* formed and the pass would be judging a
# 30-minute-old chart the moment it becomes legal. Give it something to read.
# Override: VIBE_TRADE_TIMES="1000,1400"
TRADE_TIMES="${VIBE_TRADE_TIMES:-1030,1200,1400}"
MAX_ORDER_USD="${VIBE_MAX_ORDER_USD:-2000}"     # ceiling on any single position
MAX_TRADES_PER_DAY="${VIBE_MAX_TRADES:-2}"      # hard stop on how busy it gets

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

# trade_pass <slot> — look for one trade, place it if every veto passes, then
# report what ACTUALLY happened in the account (not what the model says it did).
trade_pass() {
  slot="trade_$1"
  today=$(et_stamp | cut -d' ' -f1)
  stamp="$STAMP_DIR/${today}_${slot}"
  if [ -f "$stamp" ]; then return 0; fi

  filled=$(ls "$STAMP_DIR" 2>/dev/null | grep -c "^${today}_filled_" || true)
  if [ "${filled:-0}" -ge "$MAX_TRADES_PER_DAY" ]; then
    touch "$stamp"                                   # cap reached, skip quietly
    return 0
  fi

  echo "[$(date '+%H:%M')] trade pass: $1  (filled today: ${filled:-0}/$MAX_TRADES_PER_DAY)"
  out=$(mktemp)
  sumf=$(mktemp)
  before="$STAMP_DIR/.before_$$"
  now_et=$(et_pretty)
  python portfolio.py save "$before" 2>/dev/null
  acct=$(python portfolio.py snapshot 2>/dev/null)

  vibe-trading run --no-rich -p "CURRENT TIME: $now_et. US MARKET IS OPEN. Trust this absolutely; do not infer the time from data timestamps.

$acct

MY WATCHLIST is exactly: $WATCHLIST. You may only trade these names.

TRADING PASS on a PAPER account (fake money, Alpaca paper connector). Stocks only this pass -- no options.

HARD LIMITS, never exceed:
- At most ONE new position this pass, at or under \$$MAX_ORDER_USD.
- Watchlist names only.
- Opening none is a perfectly good outcome and happens most passes.

DO THIS IN ORDER:
1. Manage what is open, using the snapshot above. The watchdog already handles stops and targets automatically, so do NOT close anything that is simply near a level -- only close a position whose THESIS has broken (news changed, the setup failed, a level lost that mattered).
2. NEWS CHECK, yourself, do not ask me. Use web_search / get_stock_news on the watchlist. Any name that moved sharply: find out WHY. A drop on a guidance cut, recall, miss, exec exit or regulatory action is a falling knife -- do not buy that bounce.
3. INDICATOR READ across timeframes: 20/50/200 moving averages, Fibonacci retracement off the recent swing, RSI, ATR, support and resistance. A setup that fights the daily trend is low quality; say so.
4. PRE-TRADE CHECKLIST -- load the pre-trade-checklist skill and complete all eight sections on your best candidate BEFORE placing anything. ANY veto means NO TRADE or WAIT. Never override a veto.
5. Only if every veto passes, place the order through the connector, sized at or under \$$MAX_ORDER_USD.
6. Journal the decision to memory: ticker, thesis, horizon, entry, stop, target.

VOICE: write to me like a trusted assistant texting an update -- warm, direct, first person, no jargon without a plain-English gloss. Tell me what you did and why in a couple of sentences, or tell me you sat on your hands and which veto stopped you. Under 900 characters, plain text, no markdown, no tables, no asterisks. Do NOT promise future alerts or check-ins.

FORMAT: after any analysis, output your final phone message on its own, introduced by a line containing exactly BRIEFING: and nothing else. Everything after that line gets texted, so make it complete and self-contained." >"$out" 2>&1 || true

  python notify.py summarize "$out" >"$sumf"
  summary=$(cat "$sumf")
  # The receipt: what the broker says changed. If the model claimed a trade it
  # did not place, or it filled differently, this is where it shows up.
  changed=$(python portfolio.py diff "$before" 2>/dev/null)
  footer=$(python portfolio.py footer "$sumf" 2>/dev/null)

  case "$changed" in
    *BOUGHT*|*ADDED*) touch "$STAMP_DIR/${today}_filled_$1" ;;
  esac

  if [ -n "$summary" ] || [ -n "$changed" ]; then
    python notify.py send "Trade pass
$summary

WHAT CHANGED: $changed
$footer" || true
  fi
  rm -f "$out" "$sumf" "$before"
  touch "$stamp"
}

echo "Assistant running."
if [ -n "$AUTO_EXIT" ] && [ -z "$STOPS_ONLY" ]; then
  echo "  Watchdog : every 3 min while open  (AUTO-EXIT ON: closes on stops AND targets)"
elif [ -n "$AUTO_EXIT" ]; then
  echo "  Watchdog : every 3 min while open  (AUTO-EXIT ON: stops only, winners left running)"
else
  echo "  Watchdog : every 3 min while open  (alert only -- add --auto-exit to close)"
fi
if [ -n "$AUTO_TRADE" ]; then
  echo "  Trading  : ON — passes at $TRADE_TIMES ET, max \$$MAX_ORDER_USD each, $MAX_TRADES_PER_DAY/day  (PAPER)"
  echo "             (entry briefing is folded into the trade passes — no double texts)"
else
  echo "  Trading  : off (reports only -- add --auto-trade to let it place orders)"
fi
echo "  Watchlist: $WATCHLIST"
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
      # With --auto-trade on, the trade pass IS the entry check (same checklist,
      # but it can act) -- running both costs double and texts you twice.
      enabled entry && [ -z "$AUTO_TRADE" ] && briefing entry "ENTRY WINDOW. The opening range is set and the no-entry window has passed. Load the pre-trade-checklist skill and run it fully on the best candidate. Report the verdict: TRADE / WAIT FOR <specific trigger> / NO TRADE. NO TRADE is a perfectly good answer." "Entry window"
    elif [ "$hm" -ge 1200 ] && [ "$hm" -lt 1215 ]; then
      enabled midday && briefing midday "MIDDAY CHECK. Report open positions with P&L in dollars and percent, whether any is near its stop or target, and whether this morning's thesis still holds. Midday is chop -- be skeptical of new entries." "Midday check"
    elif [ "$hm" -ge 1500 ] && [ "$hm" -lt 1515 ]; then
      enabled powerhour && briefing powerhour "POWER HOUR. Final hour. Report positions and P&L, and say clearly which should be closed before the bell versus held overnight, with the reason. Flag any option nearing expiry." "Power hour"
    elif [ "$hm" -ge 1545 ] && [ "$hm" -lt 1600 ]; then
      enabled close && briefing close "END OF DAY. Summarize today: trades taken, P&L in dollars and percent, what worked and what did not. Note anything expiring or needing attention tomorrow. Write one honest lesson to memory." "Market close"
    fi

    # Watchdog: cheap and fast, runs every loop while the market is open.
    if [ "$hm" -ge 930 ] && [ "$hm" -lt 1600 ]; then
      python watchdog.py --quiet $AUTO_EXIT $STOPS_ONLY || true
    fi

    # Trading passes, only with --auto-trade, only inside the safe window.
    if [ -n "$AUTO_TRADE" ] && [ "$hm" -ge 1000 ] && [ "$hm" -lt 1530 ]; then
      for t in $(printf '%s' "$TRADE_TIMES" | tr ',' ' '); do
        if [ "$hm" -ge "$t" ] && [ "$hm" -lt $((t + 15)) ]; then
          trade_pass "$t"
        fi
      done
    fi
  fi

  sleep 180
done
