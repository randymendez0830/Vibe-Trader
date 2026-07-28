#!/usr/bin/env python3
"""Position watchdog — texts you the moment a stop or target is hit.

This is deliberately PLAIN PYTHON with no LLM in the loop, because that makes it:
  * fast      — runs in ~2 seconds, so it can check every couple of minutes
  * reliable  — a price comparison cannot hallucinate or forget
  * free      — burns zero Claude credits
The LLM is great at deciding WHAT to trade. It is the wrong tool for watching a
price tick against a stop. That job belongs here.

What it does, each run:
  1. Reads your ACTUAL open positions from Alpaca (never from memory).
  2. Gets a real-time price for each (Finnhub for stocks, Alpaca for options).
  3. Compares against the stop / target for that position — from watch_plans.json
     if you set one, otherwise the defaults below.
  4. Texts you on Telegram if a level is hit, a position moved sharply, or a
     price-alert trigger fired.
  5. Optionally CLOSES the position automatically when a stop is breached.
  6. Remembers what it already told you, so you don't get the same alert
     every two minutes.

Run once:      python watchdog.py
Run + close:   python watchdog.py --auto-exit
Continuously:  ./alerts.sh   (see that script)
"""

from __future__ import annotations

import json
import pathlib
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

# ---- defaults when a position has no explicit plan ----
# Backtesting on 5y of data showed WIDE exits beat tight ones: cutting winners
# at +4% caps upside while stops still take full losses. Hence 10/5, not 4/3.
DEFAULT_TARGET_PCT = 10.0
DEFAULT_STOP_PCT = -5.0
BIG_MOVE_PCT = 7.0        # heads-up if a position swings this much either way
# -------------------------------------------------------

HOME = pathlib.Path.home()
VT = HOME / ".vibe-trading"
PLANS_FILE = VT / "watch_plans.json"
STATE_FILE = VT / "watchdog_state.json"


def et_now() -> datetime:
    return datetime.now(ZoneInfo("America/New_York"))


def market_open(now: datetime | None = None) -> bool:
    now = now or et_now()
    mins = now.hour * 60 + now.minute
    return now.weekday() < 5 and 570 <= mins < 960   # 9:30-16:00 ET


# ------------------------------- config ------------------------------------
def load_json(path: pathlib.Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def telegram_send(text: str) -> bool:
    """Send a message. Uses requests (certifi CAs) so it works on macOS."""
    try:
        import requests
    except ImportError:
        print("requests missing; cannot text")
        return False
    tg = load_json(VT / "agent.json", {}).get("channels", {}).get("telegram", {})
    token, allow = tg.get("token"), tg.get("allow_from") or []
    if not token or not allow:
        print("Telegram not configured in ~/.vibe-trading/agent.json")
        return False
    try:
        r = requests.post(f"https://api.telegram.org/bot{token}/sendMessage",
                          data={"chat_id": allow[0], "text": text}, timeout=20)
        return r.status_code == 200
    except Exception as exc:                                  # noqa: BLE001
        print(f"telegram send failed: {exc}")
        return False


def alpaca_client():
    cfg = load_json(VT / "alpaca.json", {})
    if not cfg.get("api_key"):
        sys.exit("No Alpaca keys in ~/.vibe-trading/alpaca.json")
    try:
        from alpaca.trading.client import TradingClient
    except ImportError:
        sys.exit("alpaca-py not installed. Run: pip install alpaca-py")
    paper = str(cfg.get("profile", "paper")).startswith("paper")
    return TradingClient(cfg["api_key"], cfg["secret_key"], paper=paper)


def finnhub_price(symbol: str) -> float | None:
    """Real-time quote for a stock symbol. Returns None for options/failures."""
    key = ""
    for envf in (VT / ".env", pathlib.Path.cwd() / ".env"):
        try:
            for line in envf.read_text().splitlines():
                if line.startswith("FINNHUB_API_KEY="):
                    key = line.split("=", 1)[1].strip()
                    break
        except OSError:
            continue
        if key:
            break
    if not key:
        return None
    try:
        import requests
        r = requests.get("https://finnhub.io/api/v1/quote",
                         params={"symbol": symbol, "token": key}, timeout=10)
        c = r.json().get("c")
        return float(c) if c else None
    except Exception:                                          # noqa: BLE001
        return None


def is_option(symbol: str) -> bool:
    """Alpaca option symbols look like AMD260724C00540000 (OCC format)."""
    return len(symbol) > 12 and any(ch.isdigit() for ch in symbol[-9:])


# ------------------------------- checks ------------------------------------
def close_position(tc, symbol: str) -> tuple[bool, str]:
    try:
        tc.close_position(symbol)
        return True, "Closed it for you."
    except Exception as exc:                                   # noqa: BLE001
        return False, f"Auto-close FAILED: {exc}\nClose it manually."


def check_positions(tc, plans: dict, state: dict, auto_exit: bool,
                    exit_targets: bool = True) -> list[str]:
    msgs: list[str] = []
    plan_by_sym = {p["symbol"].upper(): p for p in plans.get("positions", [])}

    try:
        positions = tc.get_all_positions()
    except Exception as exc:                                   # noqa: BLE001
        return [f"⚠️ Could not read Alpaca positions: {exc}"]

    if not positions:
        return []

    for p in positions:
        sym = p.symbol.upper()
        entry = float(p.avg_entry_price)
        # Prefer a real-time stock quote; options must use Alpaca's own mark.
        live = None if is_option(sym) else finnhub_price(sym)
        price = live if live else float(p.current_price or entry)
        pct = ((price / entry) - 1) * 100 if entry else 0.0
        pnl = float(p.unrealized_pl or 0)

        plan = plan_by_sym.get(sym, {})
        stop_pct = float(plan.get("stop_pct", DEFAULT_STOP_PCT))
        targ_pct = float(plan.get("target_pct", DEFAULT_TARGET_PCT))
        stop_px = float(plan["stop"]) if plan.get("stop") else None
        targ_px = float(plan["target"]) if plan.get("target") else None

        # A fixed stop within 2% of the actual entry (or above it) is almost
        # always a stale number in watch_plans.json -- the plan was written for
        # a different entry. This exact mistake armed a 0.16% stop once (530
        # against a 530.85 fill). Warn once a day rather than silently letting
        # ordinary wiggle stop the position out.
        if stop_px is not None and entry and (entry - stop_px) / entry < 0.02:
            key = f"stalestop:{sym}:{et_now().date()}"
            if not state.get(key):
                room = (entry - stop_px) / entry * 100
                msgs.append(f"⚠️ {sym}: fixed stop {stop_px:,.2f} is "
                            f"{'ABOVE entry' if room <= 0 else f'only {room:.1f}% below entry'} "
                            f"{entry:,.2f} — probably stale in watch_plans.json. "
                            f"Normal wiggle will trigger it. Use stop_pct instead.")
                state[key] = True

        hit_stop = (stop_px is not None and price <= stop_px) or pct <= stop_pct
        hit_targ = (targ_px is not None and price >= targ_px) or pct >= targ_pct
        src = "live" if live else "delayed"

        if hit_stop:
            key = f"stop:{sym}:{et_now().date()}"
            if not state.get(key):
                line = (f"🛑 STOP HIT — {sym}\n"
                        f"Price {price:,.2f} ({src}) vs entry {entry:,.2f} = "
                        f"{pct:+.2f}%  (${pnl:+,.2f})\n"
                        f"Stop was {stop_px if stop_px else f'{stop_pct:+.1f}%'}")
                if auto_exit:
                    ok, note = close_position(tc, p.symbol)
                    line += f"\n{'✅' if ok else '❌'} {note}"
                else:
                    line += "\n(no auto-exit — run with --auto-exit to close these)"
                msgs.append(line)
                state[key] = True

        elif hit_targ:
            key = f"target:{sym}:{et_now().date()}"
            if not state.get(key):
                line = (f"🎯 TARGET HIT — {sym}\n"
                        f"Price {price:,.2f} ({src}) = {pct:+.2f}% "
                        f"(${pnl:+,.2f})\n"
                        f"Target was "
                        f"{targ_px if targ_px else f'{targ_pct:+.1f}%'}.")
                if auto_exit and exit_targets:
                    ok, note = close_position(tc, p.symbol)
                    line += f"\n{'✅ Profit taken. ' if ok else '❌ '}{note}"
                elif auto_exit:
                    line += "\nConsider taking profit. (--stops-only is set, so I left it open.)"
                else:
                    line += "\nConsider taking profit."
                msgs.append(line)
                state[key] = True

        elif abs(pct) >= BIG_MOVE_PCT:
            bucket = int(abs(pct) // BIG_MOVE_PCT)
            key = f"move:{sym}:{et_now().date()}:{bucket}"
            if not state.get(key):
                arrow = "📈" if pct > 0 else "📉"
                msgs.append(f"{arrow} BIG MOVE — {sym} {pct:+.2f}% "
                            f"(${pnl:+,.2f}) at {price:,.2f} ({src})")
                state[key] = True

        if is_option(sym):
            key = f"optwarn:{sym}:{et_now().date()}"
            if not state.get(key):
                msgs.append(f"⏳ Reminder: {sym} is an OPTION. Options expire — "
                            f"check the expiry and don't let it run to zero.")
                state[key] = True
    return msgs


def check_alerts(plans: dict, state: dict) -> list[str]:
    """Price alerts for tickers you're watching but don't own yet.

    Fires ONCE per crossing, not once per day: the key persists until price
    retreats ~1% back through the level, which re-arms it. (The dated keys we
    used before re-rang the same bell every morning a level stayed crossed —
    CDNS above 330 alerted two days running.)
    """
    msgs = []
    for a in plans.get("alerts", []):
        sym = str(a.get("symbol", "")).upper()
        if not sym:
            continue
        px = finnhub_price(sym)
        if px is None:
            continue
        note = a.get("note", "")
        above, below = a.get("above"), a.get("below")
        if above is not None:
            key = f"above:{sym}:{above}"
            if px >= float(above):
                if not state.get(key):
                    msgs.append(f"🔔 {sym} crossed ABOVE {above} — now {px:,.2f}"
                                + (f"\n{note}" if note else ""))
                    state[key] = True
            elif state.get(key) and px < float(above) * 0.99:
                state.pop(key, None)                       # re-armed
        if below is not None:
            key = f"below:{sym}:{below}"
            if px <= float(below):
                if not state.get(key):
                    msgs.append(f"🔔 {sym} dropped BELOW {below} — now {px:,.2f}"
                                + (f"\n{note}" if note else ""))
                    state[key] = True
            elif state.get(key) and px > float(below) * 1.01:
                state.pop(key, None)                       # re-armed
    return msgs


def main() -> None:
    auto_exit = "--auto-exit" in sys.argv
    quiet = "--quiet" in sys.argv
    # --auto-exit closes BOTH sides: stops and targets. --stops-only keeps the
    # old behaviour where a winner is only reported and left running.
    exit_targets = "--stops-only" not in sys.argv

    if not market_open() and "--force" not in sys.argv:
        if not quiet:
            print(f"[{et_now():%H:%M ET}] market closed — nothing to do")
        return

    plans = load_json(PLANS_FILE, {})
    state = load_json(STATE_FILE, {})

    # No plans file means no price alerts are armed at all -- a ticker you were
    # told about (CDNS at 320) is simply never checked. That used to fail
    # silently, which is indistinguishable from "watching, nothing triggered".
    if not PLANS_FILE.exists():
        key = f"noplans:{et_now().date()}"
        if not state.get(key):
            print(f"NOTE: {PLANS_FILE} not found — no price alerts are armed. "
                  f"Only open positions are being watched. To arm alerts:\n"
                  f"  cp config/watch_plans.example.json {PLANS_FILE}")
            state[key] = True
    # Drop yesterday's dated memory so position alerts fire fresh each day.
    # Crossing alerts (above:/below:) persist until price re-arms them.
    today = str(et_now().date())
    state = {k: v for k, v in state.items()
             if today in k or k.startswith(("above:", "below:"))}

    tc = alpaca_client()
    msgs = (check_positions(tc, plans, state, auto_exit, exit_targets)
            + check_alerts(plans, state))

    if msgs:
        body = f"⚡ Watchdog {et_now():%-I:%M %p ET}\n\n" + "\n\n".join(msgs)
        print(body)
        telegram_send(body)
    elif not quiet:
        print(f"[{et_now():%H:%M ET}] checked — nothing triggered")

    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(state, indent=2))
    except OSError:
        pass


if __name__ == "__main__":
    main()
