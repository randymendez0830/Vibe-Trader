#!/usr/bin/env bash
# ONE command to bring the whole system up.
#
#   ./start.sh                                        alerts only
#   ./start.sh --auto-exit                            alerts + auto-close on stops
#   VIBE_BRIEFINGS="premarket,entry,close" ./start.sh --auto-exit
#
# Starts, in order:
#   1. the backend API server        (needed by the Telegram chat bot)
#   2. the Telegram chat bot         (so you can MESSAGE Trady26Bot and get replies)
#   3. the alert system              (watchdog every 3 min + timed briefings)
#
# Leave this window open. Ctrl+C stops everything cleanly.
set -uo pipefail
cd "$(dirname "$0")"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

say "=============================================="
say " Vibe-Trader — starting up"
say "=============================================="

# --- 0. sanity checks -------------------------------------------------------
[ -d .venv ] || fail "no .venv here. Run ./setup.sh first."
# shellcheck disable=SC1091
source .venv/bin/activate

[ -f "$HOME/.vibe-trading/agent.json" ] || fail "missing ~/.vibe-trading/agent.json (Telegram config). See docs/TELEGRAM_SETUP.md"
[ -f "$HOME/.vibe-trading/alpaca.json" ] || say "!! no ~/.vibe-trading/alpaca.json — trading/watchdog will be limited. See docs/ALPACA_PAPER_SETUP.md"
grep -q "sk-ant" "$HOME/.vibe-trading/.env" 2>/dev/null || say "!! no Anthropic key in ~/.vibe-trading/.env — briefings will fail. Run: cp .env ~/.vibe-trading/.env"

# --- 1. don't double-run ----------------------------------------------------
if launchctl list 2>/dev/null | grep -q com.vibetrader.alerts; then
  say ""
  say "!! The background service is also running — you'd get DUPLICATE texts."
  say "   Stopping it now so this window is the only one."
  ./install_service.sh --uninstall >/dev/null 2>&1 || true
fi
pkill -f "vibe-trading serve" >/dev/null 2>&1 && say "   (stopped an old API server)"
sleep 2

# --- 2. backend API server (for the chat bot) -------------------------------
say ""
say "[1/3] Starting backend API server..."
vibe-trading serve --port 8000 > "$HOME/vibe-server.log" 2>&1 &
SERVER_PID=$!

cleanup() {
  say ""
  say "Shutting down..."
  vibe-trading channels stop >/dev/null 2>&1 || true
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  pkill -f "vibe-trading serve" >/dev/null 2>&1 || true
  say "Stopped. Nothing is monitoring now."
  exit 0
}
trap cleanup INT TERM

# wait for it to answer, up to ~60s
say "      waiting for it to come up..."
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if curl -s -o /dev/null --max-time 2 http://127.0.0.1:8000/ 2>/dev/null; then ready=1; break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    say "      server died — last log lines:"; tail -n 15 "$HOME/vibe-server.log"; fail "API server failed to start"
  fi
  sleep 2
  i=$((i+1))
done
[ "$ready" -eq 1 ] && say "      API server up (log: ~/vibe-server.log)" || say "      !! server slow to answer; continuing anyway"

# --- 3. Telegram chat bot ---------------------------------------------------
say ""
say "[2/3] Starting Telegram chat bot..."
vibe-trading channels start >/dev/null 2>&1 || true
sleep 3
if vibe-trading channels status 2>/dev/null | grep -E '^\s*\|?\s*telegram' | grep -q "yes *$"; then
  say "      chat bot RUNNING — you can message Trady26Bot"
else
  say "      retrying once..."
  vibe-trading channels stop >/dev/null 2>&1 || true
  sleep 2
  vibe-trading channels start >/dev/null 2>&1 || true
  sleep 3
  if vibe-trading channels status 2>/dev/null | grep -E '^\s*\|?\s*telegram' | grep -q "yes *$"; then
    say "      chat bot RUNNING"
  else
    say "      !! chat bot not confirmed running. Alerts will still work."
    say "         Check with: vibe-trading channels status"
  fi
fi

# --- 4. alerts (foreground) -------------------------------------------------
say ""
say "[3/3] Starting alerts (watchdog + briefings)..."
say "=============================================="
say ""
exec ./alerts.sh "$@"
