# Connect the Agent to Alpaca Paper Trading

This lets your Options Desk agent **place simulated trades automatically** with
fake money on a real market simulation. Nothing here can lose you a cent — Alpaca
paper keys physically cannot reach the real-money system. This is the right way
to prove out the agent before you ever think about real funds.

> **Why Alpaca and not TradingView or Robinhood?**
> - **TradingView** isn't a broker — it's charts and alerts. It can't execute trades from the agent. (The agent *can* export strategies to it as Pine Script for you to view, but that's separate.)
> - **Robinhood** has no paper account, so connecting it means real money from day one. Not where you want to start.
> - **Alpaca Paper** is free, US-based, gives you a real paper account with an order API, and is the best-supported connector for this. Start here.

---

## Step 1 — Create a free Alpaca account and get paper keys

1. Go to [alpaca.markets](https://alpaca.markets/) and sign up (free).
2. Once logged in, switch to **Paper Trading** mode (there's a toggle in the dashboard — it starts you with $100,000 of fake money).
3. Find the **API Keys** section for the paper account and click **Generate**.
4. You'll get two values — copy both somewhere safe, you only see the secret once:
   - **API Key ID** (starts with `PK...` for paper)
   - **Secret Key** (a long random string)

---

## Step 2 — Install the Alpaca library

The Alpaca connector needs one extra Python package. From your project folder:

```bash
source .venv/bin/activate
pip install alpaca-py
```

---

## Step 3 — Give the agent your paper keys

The agent reads Alpaca keys from a small file at `~/.vibe-trading/alpaca.json`.
Create it with your two paper keys (replace the placeholder values):

```bash
mkdir -p ~/.vibe-trading
cat > ~/.vibe-trading/alpaca.json <<'JSON'
{
  "api_key": "PK_YOUR_PAPER_KEY_ID",
  "secret_key": "YOUR_PAPER_SECRET_KEY",
  "profile": "paper",
  "feed": "iex",
  "readonly": false
}
JSON
chmod 600 ~/.vibe-trading/alpaca.json
```

`chmod 600` makes the file readable only by you. `"feed": "iex"` is the free
market-data feed. `"readonly": false` is what allows the agent to place paper
orders (set it to `true` if you only want it to *read* your account, never trade).

---

## Step 4 — Point the agent at the paper account and test it

```bash
source .venv/bin/activate

# Choose the paper trading profile (fake money, can place orders)
vibe-trading connector use alpaca-paper-trade

# Confirm it can log in and see your paper account
vibe-trading connector check

# Look at your (fake) account balance and positions
vibe-trading connector account
vibe-trading connector positions
```

If `connector check` shows your account, you're connected. If it can't log in,
double-check the two keys in `alpaca.json` and that you copied the **paper**
keys (not live keys).

---

## Step 5 — Let the agent trade (paper only)

```bash
# Turn on the live-order runner for the selected (paper) connector
vibe-trading connector start

# ...let it work, watch what it does...

# Read what orders are open at any time
vibe-trading connector orders

# Stop it whenever you want
vibe-trading connector stop
```

There's also an emergency brake — a "kill switch" that instantly blocks all new
orders:

```bash
vibe-trading connector halt     # trip the kill switch — no more orders
vibe-trading connector resume   # clear it when you're ready again
```

---

## The safety rails (worth knowing)

Whoever built Vibe-Trading took auto-trading seriously. On **paper** you're
already risk-free, but these protections exist and matter most later:

- **Paper keys can't touch real money** — different keys, different servers, enforced by Alpaca itself.
- **Kill switch** (`halt`/`resume`) — an instant stop you control.
- **Live trading needs a "mandate"** — before the agent can ever place a *real-money* order, you have to explicitly grant a signed permission ("mandate"). The paper profile doesn't need one; the live profile refuses to trade without it. This is a deliberate speed bump so real trading can never happen by accident.
- **Read-only mode** — set `"readonly": true` in `alpaca.json` and the agent can look at your account but never place a single order.

---

## Suggested POC plan

1. Run it on **Alpaca Paper** for a few weeks.
2. After each session, ask the agent to explain *why* it made each trade, and check whether the reasoning holds up.
3. Keep a simple log: did the paper account grow? Were the losses always capped where the agent said they'd be?
4. Only if it earns your trust over real time would you even consider live — and then start with money you'd be fine losing entirely, keep the kill switch handy, and grant the mandate deliberately, not casually.

**The tool makes full automation possible. Whether you should hand it real money
is a separate decision — and early on, the answer is "watch first, automate the
boring parts, risk nothing you can't afford."**
