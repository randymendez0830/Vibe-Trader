# Get Agent Messages on Telegram (+ a Morning Review)

This connects the agent to a private Telegram bot so you can chat with it from
your phone and receive a daily market/account review. It uses **polling mode**,
which means **no public server, no webhook, no port forwarding** — it just works
from your laptop.

There are two parts you must do yourself (they need your phone and can't be
automated): **creating the bot** and **finding your user ID**. Everything else
is already set up in this repo.

---

## Step 1 — Create your bot (2 minutes, on your phone)

1. Open Telegram and search for **@BotFather** (the official one, with the blue check).
2. Send it: **`/newbot`**
3. It asks for a **name** (anything, e.g. "My Trading Desk") and a **username** (must end in `bot`, e.g. `mytradingdesk_bot`).
4. BotFather replies with a **token** that looks like:
   ```
   8123456789:AAH9x_ExampleTokenStringYouWillReceive
   ```
   **Copy it — that's your bot's password. Keep it private.**

---

## Step 2 — Find your Telegram user ID (1 minute)

The agent only replies to *you*, so it needs your numeric user ID.

1. In Telegram, search for **@userinfobot** and start it.
2. It immediately replies with your **Id** (a number like `987654321`). Copy it.
3. Now open a chat with **your own new bot** (the username you just made) and send it any message like "hi" — this lets the bot see you. (It won't reply yet; we haven't started it.)

---

## Step 3 — Put the token and ID into the config

The repo ships a template at `config/agent.example.json`. Copy it into place and
fill in your two values:

```bash
mkdir -p ~/.vibe-trading
cp config/agent.example.json ~/.vibe-trading/agent.json
```

Now open `~/.vibe-trading/agent.json` in any text editor and replace:
- `PASTE_YOUR_BOTFATHER_TOKEN_HERE` → your bot token from Step 1
- `PASTE_YOUR_TELEGRAM_USER_ID_HERE` → your user ID from Step 2 (keep the quotes)

It should end up looking like:
```json
"telegram": {
  "enabled": true,
  "token": "8123456789:AAH9x_ExampleTokenStringYouWillReceive",
  "mode": "polling",
  "allow_from": ["987654321"]
}
```

> **Security note:** this file now holds your bot token. It lives in your home
> folder (`~/.vibe-trading/`), **not** in the git repo, so it won't be committed
> or pushed. Keep it that way.

---

## Step 4 — Start the bot and talk to it

```bash
source .venv/bin/activate
vibe-trading channels start     # starts your Telegram bot
vibe-trading channels status    # confirm it's running
```

Now open your bot in Telegram and message it, e.g.:

> *What's the volatility setup on SPY this week — credit or debit structures?*

You'll get the agent's answer right in the chat, on your phone. To stop the bot:

```bash
vibe-trading channels stop
```

---

## Automate the morning review

The repo includes **`morning_review.sh`**, which asks the agent to check your
Alpaca paper account and your watchlist and summarize what to look at today. Run
it any time:

```bash
./morning_review.sh
```

(Edit the `WATCHLIST=` line near the top of that file to your own tickers.)

To have it run **every weekday morning automatically**, pick whichever fits you:

### Option A — Simple OS schedule (recommended, most reliable)

On **Mac or Linux**, add a cron entry. Run `crontab -e` and add one line
(this runs at 8:30am on weekdays — adjust the time; cron uses 24h local time):

```
30 8 * * 1-5 /full/path/to/Vibe-Trader/morning_review.sh >> ~/vibe-morning.log 2>&1
```

Replace `/full/path/to/Vibe-Trader` with your actual folder path (run `pwd`
inside the project to get it). Keep the Telegram bot running
(`vibe-trading channels start`) and the review lands in your chat each morning.

> Your computer has to be awake at that time for cron to fire. If you want it to
> run when your laptop is closed, that's when a small always-on cloud server
> makes sense — a later step, not needed for the POC.

### Option B — Built-in scheduler (via the web dashboard)

Vibe-Trading has its own scheduler. Turn it on by adding this to your `.env`:
```
VIBE_TRADING_ENABLE_SCHEDULER=1
```
Then run the web dashboard (`vibe-trading dev`, open http://localhost:5173) and
create a scheduled research job there with the morning-review prompt and a cron
schedule like `30 8 * * 1-5`. This keeps everything inside the app, but needs the
dashboard/app process running. For a laptop, Option A is simpler and sturdier.

---

## Troubleshooting

- **Bot doesn't reply:** make sure you messaged the bot at least once (Step 2.3), your user ID in `allow_from` is exactly right (it's numeric, keep the quotes), and `vibe-trading channels status` shows it running.
- **"bot token not configured":** the token in `~/.vibe-trading/agent.json` is missing or has a typo.
- **Nothing at the scheduled time:** confirm the bot is running, the cron path is the real absolute path, and your computer was awake. Check `~/vibe-morning.log`.
