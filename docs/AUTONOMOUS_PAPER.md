# Hands-Off Paper Trading (the safe, staged way)

You want the agent to manage trades on its own. There are **two tiers**, and this
guide sets up the first one — the safe stepping stone you should live on for a
while before the second.

## Tier 1 — Scheduled auto-manage (what this guide sets up)

A script (`auto_manage.sh`) that, each time it runs, has the agent:
1. Read your **paper** account and open positions.
2. Close any winner that hit your profit target, or any loser that hit your stop.
3. Optionally open **one small** new stock position from your watchlist.
4. Report everything to your Telegram.

It's bounded (small size, stocks only, paper only) and uses the trading tools
you've already tested. Run it on a schedule and it *feels* autonomous — but every
action is logged and sent to your phone, so you can watch its judgment before you
ever trust it with more.

### Set your rules

Open `auto_manage.sh` and edit the block near the top:
- `WATCHLIST` — the stocks it may consider
- `MAX_ORDER_USD` — biggest single new position (default $500)
- `PROFIT_TARGET_PCT` / `STOP_PCT` — when to take profit / cut losses

### Run it once by hand first

```bash
cd ~/Desktop/Vibe-Trader
./auto_manage.sh
```

Watch what it does. If the Telegram bot is running, the summary also hits your
phone. Check results any time with:
```bash
python - <<'EOF'
from src.trading.connectors.alpaca import sdk
print("POSITIONS:", sdk.get_positions())
print("OPEN ORDERS:", sdk.get_open_orders())
EOF
```

### Schedule it during market hours

US market hours are 9:30am–4:00pm **Eastern**, weekdays. Run `crontab -e` and add
a line — this runs every 30 minutes in that window. **Adjust the hours to your own
timezone's equivalent of 9:30–16:00 ET.** (cron uses your Mac's local time.)

```
*/30 9-16 * * 1-5 /Users/YOUR_NAME/Desktop/Vibe-Trader/auto_manage.sh >> ~/vibe-auto.log 2>&1
```

Replace `/Users/YOUR_NAME/...` with your real path (run `pwd` in the project to get
it). Keep the Telegram bot running so the summaries reach your phone, and keep the
Mac awake during market hours. Peek at what it's done with `cat ~/vibe-auto.log`.

**To stop the schedule:** `crontab -e` and delete that line.

---

## Tier 2 — The full continuous runner (later, deliberately)

`vibe-trading connector start` is the real always-on runner: it wakes on a
schedule, decides, and trades **within a committed mandate**, and survives
restarts. Two things make it a bigger step:

1. **It needs a committed "mandate"** — a signed risk agreement (caps + which
   assets + expiry). By design, **only you can commit it** through a deliberate
   consent action; the AI is structurally forbidden from authorizing its own
   trading. Committing it cleanly wants the web dashboard (`vibe-trading dev`,
   which needs Node.js installed).
2. **It runs continuously**, so there's no per-action pause for you to catch a bad
   call — the guardrails (kill switch, daily trade cap, exposure limits) are what
   protect you.

Graduate to Tier 2 only after Tier 1 has earned your trust over real weeks — and
even then, on paper first. When you're ready, that's a setup session of its own.

---

## The rule that doesn't change

Everything here is **paper** — fake money, real market simulation, zero risk. That
is exactly where autonomous trading belongs until it has a long, boring,
*verified* track record. Automated trading can lose money fast; the whole point of
this staged approach is to find out how the agent behaves when the stakes are zero.
