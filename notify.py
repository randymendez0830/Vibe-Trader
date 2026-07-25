#!/usr/bin/env python3
"""Telegram send + summary cleanup helper.

Kept as a standalone file on purpose. Embedding this Python inside alerts.sh as
a heredoc broke on macOS: Apple still ships bash 3.2, which mis-parses a heredoc
nested inside a $(...) command substitution -- a backtick in a regex there was
read as an unterminated backquote. Calling a real script sidesteps that whole
class of problem.

Usage:
    python notify.py send "message text"
    python notify.py summarize /path/to/output.txt   # prints phone-ready text
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

VT = pathlib.Path.home() / ".vibe-trading"
MAX_CHARS = 1400


def telegram_send(text: str) -> int:
    try:
        import requests
    except ImportError:
        print("requests not installed", file=sys.stderr)
        return 1
    try:
        tg = json.loads((VT / "agent.json").read_text())["channels"]["telegram"]
        token, chat = tg["token"], tg["allow_from"][0]
    except (OSError, ValueError, KeyError, IndexError):
        print("Telegram not configured in ~/.vibe-trading/agent.json", file=sys.stderr)
        return 1
    try:
        r = requests.post(f"https://api.telegram.org/bot{token}/sendMessage",
                          data={"chat_id": chat, "text": text[:4000]}, timeout=20)
        if r.status_code != 200:
            print(f"telegram {r.status_code}: {r.text[:200]}", file=sys.stderr)
            return 1
        return 0
    except Exception as exc:                                   # noqa: BLE001
        print(f"telegram send failed: {exc}", file=sys.stderr)
        return 1


def summarize(path: str) -> str:
    """Pull the human-facing summary out of a CLI run and make it phone-safe."""
    try:
        raw = pathlib.Path(path).read_text(errors="replace")
    except OSError:
        return ""
    low = raw.lower()
    for marker in ("in plain terms", "bottom line", "verdict:", "summary:"):
        i = low.rfind(marker)
        if i != -1:
            raw = raw[i:]
            break
    else:
        raw = raw[-1600:]
    for cut in ("\n--show", "\nRun ID", "\nRun dir", "\nStatus:", "\nElapsed"):
        j = raw.find(cut)
        if j != -1:
            raw = raw[:j]
    raw = re.sub(r"[*#`>|]", "", raw)          # strip markdown for plain text
    raw = re.sub(r"\n{3,}", "\n\n", raw)
    return raw.strip()[:MAX_CHARS]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    mode, arg = sys.argv[1], sys.argv[2]
    if mode == "send":
        return telegram_send(arg)
    if mode == "summarize":
        out = summarize(arg)
        if out:
            print(out)
        return 0
    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
