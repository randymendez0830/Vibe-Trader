#!/usr/bin/env bash
# Morning market + paper-account review.
# Runs a research pass with your Options Desk agent. If your Telegram bot is
# running (vibe-trading channels start), the result also reaches your phone.
#
# Run it by hand any time:   ./morning_review.sh
# Or schedule it — see docs/TELEGRAM_SETUP.md ("Automate the morning review").
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source .venv/bin/activate

# Edit this watchlist to the tickers you care about.
WATCHLIST="SPY, QQQ, AAPL, NVDA"

vibe-trading run --no-rich -p "Morning options desk review. \
1) Read my Alpaca paper account: current balance, open positions, and open orders (use the connector; if it isn't configured, say so and skip). \
2) For my watchlist ($WATCHLIST), give a quick read on the volatility environment (IV vs realized, rank if known) and flag anything notable today. \
3) If any of my open option positions have hit 50% of max profit or breached an adjustment point, say so clearly. \
4) End with a one-line 'In plain terms:' summary of what, if anything, I should look at today. \
Keep the whole thing under 300 words. This is research only — do not place any trades."
