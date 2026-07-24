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
pip install "vibe-trading-ai[anthropic]"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "==> Created .env — open it and paste in your API keys."
fi

echo ""
echo "✅ Done! To start trading research:"
echo "   1. Edit .env and add at least one AI provider key"
echo "   2. Run:  source .venv/bin/activate && vibe-trading"
