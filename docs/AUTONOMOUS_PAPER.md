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

### Schedule it during market hours (the easy Mac way)

The repo includes **`schedule.sh`**, which runs `auto_manage.sh` every 30 minutes
during US market hours (Mon–Fri, 9:30am–4:00pm ET) and does nothing overnight.
This avoids the macOS cron permission headaches. Launch it once and leave the
window open:

```bash
caffeinate -i ./schedule.sh
```

`caffeinate -i` keeps your Mac awake while it runs. Keep the Telegram bot running
in its own window so the summaries reach your phone. **Press Ctrl+C to stop.**

> `schedule.sh` assumes your Mac's clock is US Eastern. If not, edit the `930` /
> `1600` values inside it to your local equivalent of 9:30am / 4:00pm Eastern.

**Prefer real cron instead?** `crontab -e` and add (fix the path with `pwd`):
```
*/30 9-16 * * 1-5 /Users/YOUR_NAME/Desktop/Vibe-Trader/auto_manage.sh >> ~/vibe-auto.log 2>&1
```
On modern macOS, cron may need Full Disk Access (System Settings → Privacy &
Security) to run a script under `~/Desktop`. The `schedule.sh` loop above sidesteps
that entirely, which is why it's the recommended path.

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
