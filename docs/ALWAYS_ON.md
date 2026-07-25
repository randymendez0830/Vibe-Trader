# Running the alerts 24/7 (no Terminal window)

Three levels, cheapest first. Level 1 takes two minutes and covers most of what
you want. Level 3 is the only one that is genuinely always-on.

---

## Level 1 — Background service on your Mac (free, do this now)

Installs the alerts as a proper macOS background service (a launchd
LaunchAgent). **No Terminal window**, starts automatically when you log in, and
restarts itself if it crashes.

```bash
cd ~/Desktop/Vibe-Trader
./install_service.sh --auto-exit
```

Manage it:

```bash
./install_service.sh --status      # running? recent log lines?
./install_service.sh --logs        # live tail of the log
./install_service.sh --uninstall   # stop it and remove it from login
```

Logs live at `~/Library/Logs/vibe-alerts.log` (and `.error.log`).

**Stop the old Terminal loop first** — press `Ctrl+C` in the window running
`alerts.sh`, or you will have two copies sending duplicate texts.

### The catch: your Mac must be awake

A background service still can't run while the machine is asleep. Fix that:

- **System Settings → Lock Screen / Displays → "Prevent automatic sleeping when
  the display is off"** (on an iMac, plugged in, this is usually enough — and
  your iMac is a desktop, so it isn't going anywhere).
- The service already wraps itself in `caffeinate -i`, which blocks idle sleep
  while it runs.
- Optional, wake it for the trading day even if it did sleep:
  ```bash
  sudo pmset repeat wakeorpoweron MTWRF 08:45:00
  ```
  (Undo with `sudo pmset repeat cancel`.)

A desktop iMac that stays powered on covers market hours fine. A laptop you
close and carry around does not — that's Level 3.

---

## Level 2 — Add a second machine you already own

If you have a spare Mac, a Mac mini, or a Raspberry Pi that lives on your desk
plugged in, install there instead (same Level 1 steps, plus copying
`~/.vibe-trading/`). Free, and it isn't competing with your daily driver.

Copy the config across (it holds your API keys, so keep it private):

```bash
scp -r ~/.vibe-trading other-machine:~/
```

---

## Level 3 — A small cloud server (~$5/month, genuinely 24/7)

The only setup that runs with your laptop closed, your Mac off, or your power
out. A $5–6/month VPS from **DigitalOcean**, **Hetzner**, **Vultr**, or
**Railway** is plenty — this workload is tiny.

Rough path (Ubuntu box):

```bash
# on the server
sudo apt update && sudo apt install -y python3 python3-venv git
git clone https://github.com/randymendez0830/Vibe-Trader && cd Vibe-Trader
python3 -m venv .venv && source .venv/bin/activate
pip install "vibe-trading-ai[anthropic,channels]" alpaca-py yfinance requests

# copy your config up from the Mac (keys live here — never commit it)
# run this ON THE MAC:
scp -r ~/.vibe-trading user@your-server-ip:~/

# back on the server, install the persona skills
cp -r skills/options-desk skills/pre-trade-checklist ~/.vibe-trading/skills/user/

# run it under systemd so it survives reboots
sudo tee /etc/systemd/system/vibe-alerts.service >/dev/null <<'UNIT'
[Unit]
Description=Vibe Trader alerts
After=network-online.target

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/Vibe-Trader
ExecStart=/bin/bash /home/YOUR_USERNAME/Vibe-Trader/alerts.sh --auto-exit
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now vibe-alerts
sudo systemctl status vibe-alerts      # check it
sudo journalctl -u vibe-alerts -f      # watch the log
```

Notes for a Linux server:
- `alerts.sh` uses real Eastern time via `zoneinfo`, so the server's timezone
  does not matter.
- Drop `caffeinate` (that's macOS-only) — systemd keeps it alive instead. The
  `ExecStart` above already omits it.
- **Set the server timezone to UTC and leave it** — the scripts convert
  internally.

### Honest cost

| | Monthly |
|---|---|
| VPS (DigitalOcean/Hetzner basic) | ~$5–6 |
| Claude API credits (6 briefings/day) | ~$10–30 depending on usage |
| Alpaca paper trading | free |
| Finnhub free tier | free |
| **Total** | **~$15–35/month** |

The watchdog itself is free to run (no LLM), so credits scale with how many
briefings you keep. Trim the briefing list in `alerts.sh` to cut cost.

---

## Which should you pick?

- **Right now:** Level 1. It's free, takes two minutes, and your iMac is a
  desktop that's probably on anyway.
- **Only move to Level 3** once you've watched this run for a few weeks and
  decided the alerts are genuinely worth $15–35/month to you. Don't pay for
  infrastructure to host a strategy you haven't validated yet — that's the
  wrong order, and it's how people spend money to lose money faster.

## Before you rely on any of it

- **Verify it actually fires.** `./install_service.sh --status` and check that a
  briefing lands on your phone at 9:00am. A service you *believe* is running but
  isn't is worse than no service, because you'll stop watching.
- **Nothing here removes the need to look.** Auto-exit closes stops; it does not
  make judgement calls. Read the texts.
- **Keep `~/.vibe-trading/` private.** It holds your Alpaca keys, your bot
  token, and your Anthropic key. It is gitignored for that reason.
