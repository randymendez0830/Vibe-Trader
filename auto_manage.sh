#!/usr/bin/env bash
# Scheduled paper-account auto-manage pass.
# Each run, the agent reviews your open PAPER positions, exits any that hit a
# profit target or stop, and may open ONE small new stock position. The summary
# is printed AND sent to your Telegram (read from ~/.vibe-trading/agent.json).
#
# PAPER ONLY. This uses the alpaca-paper-trade connector — fake money, no real
# funds can be touched. Run by hand any time:  ./auto_manage.sh
# Or schedule it during market hours — see docs/AUTONOMOUS_PAPER.md.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source .venv/bin/activate

# ---- your bounded rules (edit these) ----
WATCHLIST="SPY, QQQ, AAPL, NVDA, MSFT"   # stocks it may consider
MAX_ORDER_USD="500"                       # biggest single new position, in $
PROFIT_TARGET_PCT="10"                    # close a winner up this many %
STOP_PCT="6"                              # close a loser down this many %
# -----------------------------------------

OUT_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE"' EXIT

vibe-trading run --no-rich -p "Autonomous paper-account management pass. You are trading a PAPER account only (fake money) through the selected Alpaca paper connector. Follow your options-desk discipline for reasoning, but trade STOCKS only in this pass.

STRICT RULES:
- Paper account only. Never exceed \$$MAX_ORDER_USD on any single new position.
- Only symbols in this watchlist: $WATCHLIST.
- At most ONE new position this pass. It is completely fine to open none.

DO THIS, IN ORDER:
1. Read the account and current open positions (use the connector tools).
2. For each open position: if it is up ${PROFIT_TARGET_PCT}% or more, close it (take profit). If it is down ${STOP_PCT}% or more, close it (stop loss). State the P&L for each in dollars and percent.
3. Then decide whether there is ONE clean new entry worth taking from the watchlist right now. If yes, place a market buy sized at or under \$$MAX_ORDER_USD and say why. If nothing is clean, take no new trade — say 'no new trade' and why.
4. Finish with a short 'In plain terms:' summary: what you closed, what you opened, and what you're watching. Keep it under 250 words.

If the market is closed, do not place new orders — just report positions and what you'd watch for at the open." | tee "$OUT_FILE"

# Send the summary to Telegram (best-effort; reads token + chat id from agent.json).
# Uses `requests` (bundles its own CA certs via certifi) rather than urllib, so it
# works on python.org macOS installs that haven't run "Install Certificates".
python - "$OUT_FILE" <<'PY' || true
import json, sys, pathlib
try:
    import requests
except Exception:
    sys.exit(0)
cfg = pathlib.Path.home() / ".vibe-trading" / "agent.json"
try:
    tg = json.loads(cfg.read_text())["channels"]["telegram"]
    token = tg["token"]; chat_id = tg["allow_from"][0]
except Exception:
    sys.exit(0)  # no Telegram configured — the printed/logged output is enough
raw = pathlib.Path(sys.argv[1]).read_text()
# Send just the clean "In plain terms" summary, not the whole terminal dump.
marker = raw.lower().rfind("in plain terms")
summary = raw[marker:] if marker != -1 else raw[-3000:]
# Trim trailing CLI noise that follows the summary.
for cut in ("\n--show", "\nRun ID", "\nRun dir", "\nStatus:", "\nElapsed"):
    i = summary.find(cut)
    if i != -1:
        summary = summary[:i]
summary = summary.strip() or "auto_manage: (no summary)"
try:
    requests.post(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data={"chat_id": chat_id, "text": "🤖 Auto-manage pass\n\n" + summary},
        timeout=20,
    )
except Exception:
    pass
PY
