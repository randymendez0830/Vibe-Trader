#!/usr/bin/env bash
# One-command setup for Vibe-Trading on Mac/Linux.
# Creates an isolated Python environment, installs the agent,
# and prepares your .env file.
set -euo pipefail

echo "==> Checking Python version (need 3.11+)..."
PY=""
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    ver=$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    major=${ver%%.*}; minor=${ver##*.}
    if [ "$major" -eq 3 ] && [ "$minor" -ge 11 ]; then
      PY="$candidate"
      break
    fi
  fi
done

if [ -z "$PY" ]; then
  echo "ERROR: Python 3.11+ not found."
  echo "  Mac:    brew install python@3.12"
  echo "  Ubuntu: sudo apt install python3.12 python3.12-venv"
  exit 1
fi
echo "    Using $PY ($($PY --version))"

echo "==> Creating virtual environment in .venv ..."
"$PY" -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate

echo "==> Installing vibe-trading-ai (this can take a few minutes)..."
pip install --upgrade pip
pip install "vibe-trading-ai[anthropic,channels]"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "==> Created .env — open it and paste in your API keys."
fi

echo "==> Installing the Options Desk persona skill..."
mkdir -p ~/.vibe-trading/skills/user
cp -r skills/options-desk ~/.vibe-trading/skills/user/
# NOTE: we deliberately do NOT copy .env to ~/.vibe-trading/.env here.
# That copy would be blank (the key isn't added until the next step), and the
# runtime checks ~/.vibe-trading/.env FIRST — a blank copy there would shadow
# the real key in this project's .env. Add your key below, then sync it.

echo ""
echo "✅ Done! Next steps:"
echo "   1. Edit .env and paste your Anthropic API key into ANTHROPIC_API_KEY="
echo "   2. Sync the key to the runtime:  cp .env ~/.vibe-trading/.env"
echo "   3. Run:  source .venv/bin/activate && vibe-trading"
echo ""
echo "   (For the Telegram bot instead, see docs/TELEGRAM_SETUP.md)"
