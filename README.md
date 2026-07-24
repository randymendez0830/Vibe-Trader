# Vibe-Trader — Your Personal AI Trading Setup

This repo is your home base for the setup shown in those Instagram posts. It combines two free, open-source projects:

| Project | What it is | How you run it |
|---|---|---|
| [Vibe-Trading](https://github.com/HKUDS/Vibe-Trading) | An AI trading agent: ask research questions in plain English, run backtests, draft strategies, get multi-agent "investment committee" debates | Installed with `pip`, runs in your terminal or as a local web app |
| [Fincept Terminal](https://github.com/Fincept-Corporation/FinceptTerminal) | A free Bloomberg-style desktop terminal: live market data, charts, screeners, 37 built-in AI agents, 100+ data connectors | Downloaded as a normal desktop app (Windows / Mac / Linux) |

They complement each other: **Fincept Terminal is your eyes** (market data, charts, news), and **Vibe-Trading is your brain** (research, backtesting, strategy building). You can install either one alone, or both.

---

## Part 1 — Install Vibe-Trading (the AI agent)

### Prerequisites

- **Python 3.11 or newer.** Check with `python3 --version`.
  - Mac: `brew install python@3.12` (install [Homebrew](https://brew.sh) first if needed)
  - Windows: download from [python.org](https://www.python.org/downloads/) and check "Add Python to PATH" during install
- **At least one AI provider API key** — this powers the agent's reasoning. Any one of these works:
  - [Anthropic (Claude)](https://console.anthropic.com/) — recommended
  - [OpenAI](https://platform.openai.com/)
  - [DeepSeek](https://platform.deepseek.com/) — cheapest
  - [Ollama](https://ollama.com/) — free, runs models locally on your machine (needs a decent computer)

### Install

```bash
pip install vibe-trading-ai
```

Optional extras, depending on what you want:

```bash
pip install "vibe-trading-ai[anthropic]"   # Claude support
pip install "vibe-trading-ai[channels]"    # Telegram/Slack/Discord alerts
pip install "vibe-trading-ai[harmonic]"    # harmonic pattern detection
```

### Configure your keys

Copy the template in this repo and fill in your keys:

```bash
cp .env.example .env
```

Then open `.env` in any text editor and paste in your API keys. **Never commit `.env` to GitHub** — the `.gitignore` in this repo already protects it.

### First run

```bash
# Interactive mode — just talk to it
vibe-trading

# Or ask a one-off research question
vibe-trading run -p "Compare NVDA and AMD momentum over the last 6 months"

# Run a backtest against a library of 462 pre-built alpha strategies
vibe-trading alpha bench --zoo gtja191 --universe csi300 --period 2018-2025

# Upload your broker trade history for analysis
vibe-trading --upload trades_export.csv
```

### Optional: the web UI (looks like the screenshots)

```bash
vibe-trading setup   # one-time setup
vibe-trading dev     # starts backend + frontend
```

Then open **http://localhost:5173** in your browser.

If you prefer Docker (and have [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed), clone the upstream repo and run `docker compose up` instead.

---

## Part 2 — Install Fincept Terminal (the Bloomberg-style desktop app)

No coding needed. Go to the [FinceptTerminal Releases page](https://github.com/Fincept-Corporation/FinceptTerminal/releases) and download the installer for your system:

- **Windows:** `FinceptTerminal-Windows-x64-setup.exe`
- **Mac (Apple Silicon):** `FinceptTerminal-macOS-arm64.dmg`
- **Linux:** `FinceptTerminal-Linux-x64.run`

Run the installer, open the app, and create a free account. The free tier includes 350 API credits (no credit card, credits don't expire). It's free for personal use under the AGPL-3.0 license.

---

## Part 3 — Free data source API keys (optional but recommended)

Vibe-Trading works out of the box with 22 free data sources, but registering a few free keys makes it much more reliable:

| Source | What it gives you | Free tier |
|---|---|---|
| [Finnhub](https://finnhub.io/) | US stocks, real-time quotes, news | Yes |
| [Alpha Vantage](https://www.alphavantage.co/support/#api-key) | Stocks, forex, crypto, indicators | Yes |
| [FRED](https://fred.stlouisfed.org/docs/api/api_key.html) | US economic data (rates, inflation, jobs) | Yes |
| [Polygon](https://polygon.io/) | US market data | Limited free |
| [Tushare](https://tushare.pro/) | Chinese A-shares | Yes |

Add whichever keys you get to your `.env` file.

---

## Quick start (TL;DR)

On Mac or Linux, the script in this repo does Part 1 for you:

```bash
./setup.sh
```

Then edit `.env` with your keys and run `vibe-trading`.

---

## Using your Options Desk agent

This repo ships a custom **`options-desk`** persona skill (in `skills/options-desk/`) that makes the agent behave like a disciplined professional options trader: it checks the volatility environment before any idea, only proposes defined-risk structures, always reports the Greeks / max loss / breakevens / probability of profit, sizes positions at 1–2% max risk, and defines the exit before the entry. `setup.sh` installs it automatically.

### Three ways to interact with it

**1. Terminal chat** — the fastest way to talk to it:
```bash
source .venv/bin/activate
vibe-trading                     # interactive chat
vibe-trading run -p "What's the IV setup on SPY this week — credit or debit structures?"
vibe-trading --list              # see past research runs
vibe-trading --show <RUN_ID>     # re-open any run
```

**2. Web dashboard** — the visual interface (sessions, backtests, research history):
```bash
vibe-trading setup   # one time
vibe-trading dev     # then open http://localhost:5173
```

**3. Telegram on your phone** — get research pushed to you:
```bash
vibe-trading channels   # follow the prompts; create a bot with @BotFather first
```
Combine with the scheduler (`VIBE_TRADING_ENABLE_SCHEDULER=1` in `.env`) to get a recurring morning scan of your watchlist delivered automatically.

### Things to try first

```bash
vibe-trading run -p "Analyze the current IV rank on AAPL and propose one defined-risk trade using the options-desk format"
vibe-trading run -p "Backtest a 30-delta SPY iron condor entered weekly over the last 2 years"
vibe-trading alpha list          # browse 462 pre-built strategies
```

### One-time requirement: API credits

The agent's brain runs on the Anthropic API, which uses **prepaid credits — separate from any Claude.ai subscription**. Add credits at [console.anthropic.com → Plans & Billing](https://console.anthropic.com/settings/billing) ($5 minimum goes a long way; typical research questions cost a few cents each).

## Important disclaimers

- **This is research software, not financial advice.** AI agents can be confidently wrong. Backtest results do not guarantee future returns.
- **Start in paper-trading mode.** Vibe-Trading's broker connectors support read-only and paper trading — use those until you deeply trust a strategy, and even then, risk only what you can afford to lose.
- **Guard your API keys.** Keep them in `.env`, never in code or screenshots.
