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

**3. Telegram on your phone** — chat with the agent and get a daily review pushed to you. Full step-by-step (create a bot, get your ID, start it): **[docs/TELEGRAM_SETUP.md](docs/TELEGRAM_SETUP.md)**. Quick version:
```bash
cp config/agent.example.json ~/.vibe-trading/agent.json   # then fill in your bot token + user ID
vibe-trading channels start                               # bot goes live; message it from your phone
./morning_review.sh                                       # a market + paper-account review (schedule it via cron)
```
Uses polling mode — no server or webhook needed.

### Letting it actually place trades (paper first!)

The agent can place trades automatically through a broker connector. **Start with
Alpaca Paper** — free, fake money, zero risk — to prove the agent out before ever
touching real funds. Full step-by-step guide: **[docs/ALPACA_PAPER_SETUP.md](docs/ALPACA_PAPER_SETUP.md)**.

Quick note on the two platforms people ask about: **TradingView** isn't a broker (it's charts/alerts — the agent can't trade through it), and **Robinhood** has no paper account (connecting it = real money from day one). Alpaca Paper is the right place to start. Interactive Brokers and Tiger paper accounts also work if you prefer them.

**Ready for real money later?** Once your Alpaca paper POC has earned your trust, see **[docs/REAL_MONEY_BROKERS.md](docs/REAL_MONEY_BROKERS.md)** — which brokers actually support live automated trading in this tool (short answer: graduate to Alpaca Live, since it's the same connector you already validated), the "mandate" safety gate that stops real trades from happening by accident, and a slow, evidence-based plan for going live.

### Things to try first

```bash
vibe-trading run -p "Analyze the current IV rank on AAPL and propose one defined-risk trade using the options-desk format"
vibe-trading run -p "Backtest a 30-delta SPY iron condor entered weekly over the last 2 years"
vibe-trading alpha list          # browse 462 pre-built strategies
```

### The agent's brain

Configured as **Claude Sonnet 4.5** (`LANGCHAIN_MODEL_NAME` in `.env`). It's the sweet spot for this project: strong enough for rigorous options reasoning, and about 5x cheaper than Opus so your API credits stretch much further — a typical research question costs a few cents.

> Note: this version of Vibe-Trading sends a `temperature` setting that the very newest models (Opus 4.8, Sonnet 5) reject, which is why Sonnet 4.5 is the pinned default. It's verified working end-to-end.

### One-time requirement: API credits

The Anthropic API uses **prepaid credits — separate from any Claude.ai subscription**. Add them at [console.anthropic.com → Plans & Billing](https://console.anthropic.com/settings/billing) ($5 goes a long way at Sonnet pricing).

## Important disclaimers

- **This is research software, not financial advice.** AI agents can be confidently wrong. Backtest results do not guarantee future returns.
- **Start in paper-trading mode.** Vibe-Trading's broker connectors support read-only and paper trading — use those until you deeply trust a strategy, and even then, risk only what you can afford to lose.
- **Guard your API keys.** Keep them in `.env`, never in code or screenshots.
