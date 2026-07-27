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


# Lines the CLI prints around the actual answer. Dropping these leaves the
# real reply, so we never have to blind-slice the tail (which cut messages
# mid-word: "n Middle East ceasefire hopes...").
_NOISE = re.compile(
    r"^\s*(?:"
    r"Preflight Check|Prompt:|Status:|Elapsed|Run ID|Run dir|--show|"
    r"\d+/\d+ services ready|"
    r"(?:OK|N/A|FAIL|WARN)\s*[│|]|"                 # preflight table rows
    r"[│┃┏┡┗━┓┛─╇╈]|"                                # table borders
    r"-\s+\w[\w.]*\s+.*?\bOK\s+[\d.]+s|"             # "- trading_account ... OK 0.3s"
    r"OK\s+[\d.]+s\s*$|"                             # bare "OK 0.3s"
    r"\w+ is unavailable, falling back|"
    r"请设置tushare"
    r")",
    re.IGNORECASE,
)


# The agent's thinking-out-loud openers ("I'll check the account first."), which
# are meaningless in a text message.
_PREAMBLE = re.compile(
    r"^\s*(?:I'?ll\b|I will\b|Let me\b|Let's\b|First,|Now (?:let|I)\b|"
    r"Checking\b|Looking\b|Starting\b|I'?m going to\b)",
    re.IGNORECASE,
)


def _strip_noise(text: str) -> str:
    lines = [ln for ln in text.splitlines() if not _NOISE.match(ln)]
    # Drop leading preamble lines, but never eat the whole message.
    while lines and (not lines[0].strip() or _PREAMBLE.match(lines[0])):
        if len([x for x in lines[1:] if x.strip()]) < 2:
            break
        lines.pop(0)
    return "\n".join(lines)


def _tail_at_boundary(text: str, limit: int) -> str:
    """Take the last `limit` chars but start at a clean paragraph/sentence."""
    if len(text) <= limit:
        return text
    tail = text[-limit:]
    for sep in ("\n\n", "\n", ". "):
        i = tail.find(sep)
        if i != -1 and i < limit // 2:          # don't throw away most of it
            return tail[i + len(sep):]
    return tail


def summarize(path: str) -> str:
    """Pull the human-facing reply out of a CLI run and make it phone-safe."""
    try:
        raw = pathlib.Path(path).read_text(errors="replace")
    except OSError:
        return ""

    # 1. Cut everything after the trailing CLI footer.
    for cut in ("\n--show ", "\nRun ID", "\nRun dir", "\nStatus:", "\nElapsed"):
        j = raw.find(cut)
        if j != -1:
            raw = raw[:j]

    # 2. Prefer an explicit marker the prompt asked for.
    low = raw.lower()
    for marker in ("briefing:", "in plain terms", "bottom line", "verdict:", "summary:"):
        i = low.rfind(marker)
        if i != -1:
            raw = raw[i + len(marker):] if marker == "briefing:" else raw[i:]
            break
    else:
        # 3. No marker: drop CLI scaffolding, keep the whole answer.
        raw = _strip_noise(raw)

    raw = re.sub(r"[*#`>|]", "", raw)            # strip markdown for plain text
    raw = re.sub(r"\n{3,}", "\n\n", raw).strip()

    # 4. Only if still too long, trim at a sentence/paragraph boundary.
    return _tail_at_boundary(raw, MAX_CHARS).strip()


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
