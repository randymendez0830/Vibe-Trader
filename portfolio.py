#!/usr/bin/env python3
"""Authoritative account snapshot — read from Alpaca in plain Python.

Why this exists
---------------
Briefings used to get your positions by TELLING the LLM to "read positions from
the Alpaca connector -- never from memory". That is an instruction, not a
guarantee. On 2026-07-27 a 9:09am briefing said "No open positions, no pending
orders" while the account held AAPL and AMD, and then described a trade "from
Friday July 24" -- recalled from an old conversation instead of read from the
broker. A briefing that under-reports positions is the single most dangerous
failure this system can have: it invites you to ignore an exposure that is
actually live.

So we do what already fixed the time hallucination -- we stop asking and start
injecting. This module reads the account directly (same code path as
watchdog.py, which has never been wrong) and produces two things:

  snapshot  -- a ground-truth block pasted INTO the prompt, so the model cannot
               fail to look it up; the facts are already in front of it.
  footer    -- a short line appended to the outgoing text, so the real numbers
               are in the message you read even if the model still gets it wrong.
               If the model claims you are flat while positions exist, the
               footer leads with a correction.

Usage:
    python portfolio.py snapshot                # prompt-injection block
    python portfolio.py footer [summary_file]   # phone-message footer
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

from watchdog import et_now, finnhub_price, is_option, alpaca_client

MAX_FOOTER_POSITIONS = 4        # keep the text short; count covers the rest


class SnapshotError(RuntimeError):
    """Could not read the account. Must be surfaced, never silently emptied."""


def _f(value, default=0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def read_account() -> dict:
    """Pull equity, positions and open orders. Raises SnapshotError on failure.

    Never returns an empty-but-successful result on error -- "no positions"
    and "could not check" have to stay distinguishable all the way through.
    """
    try:
        tc = alpaca_client()
    except SystemExit as exc:                                  # noqa: BLE001
        raise SnapshotError(str(exc)) from exc

    try:
        acct = tc.get_account()
        raw_positions = tc.get_all_positions()
    except Exception as exc:                                   # noqa: BLE001
        raise SnapshotError(f"{type(exc).__name__}: {exc}") from exc

    try:
        orders = tc.get_orders()
    except Exception:                                          # noqa: BLE001
        orders = []            # orders are a nice-to-have; positions are not

    positions = []
    for p in raw_positions:
        sym = p.symbol.upper()
        entry = _f(p.avg_entry_price)
        # Real-time quote for stocks; options have to use Alpaca's own mark.
        live = None if is_option(sym) else finnhub_price(sym)
        price = live if live else _f(p.current_price, entry)
        positions.append({
            "symbol": sym,
            "qty": _f(p.qty),
            "side": str(getattr(p, "side", "long")).split(".")[-1].lower(),
            "entry": entry,
            "price": price,
            "source": "live" if live else "delayed",
            "pct": ((price / entry) - 1) * 100 if entry else 0.0,
            "pnl": _f(p.unrealized_pl),
            "value": _f(p.market_value),
            "option": is_option(sym),
        })
    positions.sort(key=lambda x: -abs(x["value"]))

    return {
        "equity": _f(getattr(acct, "equity", 0)),
        "cash": _f(getattr(acct, "cash", 0)),
        "buying_power": _f(getattr(acct, "buying_power", 0)),
        "positions": positions,
        "orders": [{
            "symbol": str(getattr(o, "symbol", "?")).upper(),
            "side": str(getattr(o, "side", "")).split(".")[-1].lower(),
            "qty": getattr(o, "qty", None),
            "type": str(getattr(o, "order_type", "")).split(".")[-1].lower(),
            "limit": getattr(o, "limit_price", None),
            "status": str(getattr(o, "status", "")).split(".")[-1].lower(),
        } for o in orders],
    }


def _qty(q: float) -> str:
    return f"{q:g}" if q == int(q) else f"{q:.4f}".rstrip("0")


def snapshot_text() -> str:
    """The block injected into every briefing prompt as ground truth."""
    stamp = et_now().strftime("%A %Y-%m-%d %I:%M %p ET")
    try:
        acct = read_account()
    except SnapshotError as exc:
        return (
            "ACCOUNT SNAPSHOT: UNAVAILABLE. Reading the Alpaca account failed "
            f"({exc}). You therefore do NOT know what is open. Say exactly that "
            "-- 'I could not read the account' -- and do NOT state or guess "
            "positions, P&L or orders. Do not say the account is flat."
        )

    lines = [
        f"ACCOUNT SNAPSHOT read directly from Alpaca at {stamp}. "
        "This is ground truth, verified outside the model. It overrides your "
        "memory, this conversation, and anything a tool tells you.",
        f"Equity ${acct['equity']:,.2f} | Cash ${acct['cash']:,.2f} | "
        f"Buying power ${acct['buying_power']:,.2f}",
    ]

    pos = acct["positions"]
    if pos:
        lines.append(f"OPEN POSITIONS: {len(pos)}")
        for p in pos:
            kind = "OPTION" if p["option"] else "shares"
            lines.append(
                f"  {p['symbol']} {p['side']} {_qty(p['qty'])} {kind} | "
                f"entry {p['entry']:,.2f} | now {p['price']:,.2f} ({p['source']}) | "
                f"{p['pct']:+.2f}% | ${p['pnl']:+,.2f} | value ${p['value']:,.2f}"
            )
    else:
        lines.append("OPEN POSITIONS: 0 — the account is genuinely flat.")

    orders = [o for o in acct["orders"]
              if o["status"] in ("new", "accepted", "pending_new", "partially_filled", "held")]
    if orders:
        lines.append(f"OPEN ORDERS: {len(orders)}")
        for o in orders:
            px = f" @ {o['limit']}" if o["limit"] else ""
            lines.append(f"  {o['symbol']} {o['side']} {o['qty']} {o['type']}{px} ({o['status']})")
    else:
        lines.append("OPEN ORDERS: 0")

    lines.append(
        "Use these exact numbers. Do NOT claim a position that is not listed "
        "above, and do NOT say you have none if any are listed."
    )
    return "\n".join(lines)


# Ways the model has claimed flatness. Matched only to add a correction line --
# never to edit the model's words, so a false positive costs nothing but noise.
_CLAIMS_FLAT = re.compile(
    r"\bno\s+(?:open\s+|current\s+|active\s+)?positions?\b"
    r"|\bno\s+positions?\s+(?:open|held)\b"
    r"|\baccount\s+is\s+flat\b"
    r"|\byou(?:'re| are)\s+(?:currently\s+)?flat\b"
    r"|\bnothing\s+(?:is\s+)?open\b"
    r"|\bcurrently\s+holding\s+nothing\b",
    re.IGNORECASE,
)


def footer_text(summary_path: str | None = None) -> str:
    """Short ground-truth line appended to the outgoing text message."""
    try:
        acct = read_account()
    except SnapshotError as exc:
        return f"(Could not verify positions with Alpaca: {exc})"

    stamp = et_now().strftime("%-I:%M %p ET")
    pos = acct["positions"]

    claimed_flat = False
    if summary_path:
        try:
            with open(summary_path, encoding="utf-8", errors="replace") as fh:
                claimed_flat = bool(_CLAIMS_FLAT.search(fh.read()))
        except OSError:
            pass

    if not pos:
        return f"Verified with Alpaca {stamp}: no open positions. Cash ${acct['cash']:,.0f}."

    shown = pos[:MAX_FOOTER_POSITIONS]
    parts = [f"{p['symbol']} {_qty(p['qty'])} {p['pct']:+.1f}%" for p in shown]
    if len(pos) > len(shown):
        parts.append(f"+{len(pos) - len(shown)} more")
    body = f"{', '.join(parts)}. Cash ${acct['cash']:,.0f}."

    if claimed_flat:
        return (f"CORRECTION — the message above is wrong. Alpaca shows "
                f"{len(pos)} OPEN position(s) as of {stamp}: {body}")
    return f"Verified with Alpaca {stamp}: {body}"


def save(path: str) -> None:
    """Record the account as it stands, to compare against later."""
    try:
        acct = read_account()
    except SnapshotError:
        acct = None                      # a failed read must not look like "flat"
    pathlib.Path(path).write_text(json.dumps(acct))


def diff(path: str) -> str:
    """What actually changed since save() — read from the broker, not claimed.

    The agent reporting "I bought NVDA" is a claim. This is the receipt. If an
    order was rejected, silently not placed, or filled at a different size, the
    difference shows up here and nowhere else.
    """
    try:
        before = json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return ""
    if before is None:
        return ""                        # nothing trustworthy to compare against
    try:
        after = read_account()
    except SnapshotError as exc:
        return f"(Could not verify what changed: {exc})"

    old = {p["symbol"]: p for p in before.get("positions", [])}
    new = {p["symbol"]: p for p in after["positions"]}

    lines = []
    for sym, p in new.items():
        if sym not in old:
            lines.append(f"BOUGHT {sym} — {_qty(p['qty'])} at {p['entry']:,.2f} "
                         f"(${abs(p['value']):,.2f})")
        elif abs(p["qty"]) > abs(old[sym]["qty"]):
            lines.append(f"ADDED to {sym} — {_qty(old[sym]['qty'])} to {_qty(p['qty'])}")
    for sym, p in old.items():
        if sym not in new:
            lines.append(f"CLOSED {sym} — {_qty(p['qty'])} out, "
                         f"last seen {p['pct']:+.2f}% (${p['pnl']:+,.2f})")
        elif abs(p["qty"]) > abs(new[sym]["qty"]):
            lines.append(f"TRIMMED {sym} — {_qty(p['qty'])} down to {_qty(new[sym]['qty'])}")

    if not lines:
        return "No orders filled — the account is unchanged."
    return "\n".join(lines)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
    if mode == "snapshot":
        print(snapshot_text())
        return 0
    if mode == "footer":
        print(footer_text(sys.argv[2] if len(sys.argv) > 2 else None))
        return 0
    if mode in ("save", "diff"):
        if len(sys.argv) < 3:
            print(f"{mode} needs a file path", file=sys.stderr)
            return 2
        if mode == "save":
            save(sys.argv[2])
        else:
            out = diff(sys.argv[2])
            if out:
                print(out)
        return 0
    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
