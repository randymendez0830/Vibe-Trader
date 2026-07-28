#!/usr/bin/env python3
"""Make the Telegram CHAT bot see your real account, like the briefings do.

The problem this fixes
----------------------
Scheduled briefings and brief_now.sh get an ACCOUNT SNAPSHOT pasted into their
prompt, so they cannot hallucinate positions. But when you MESSAGE the bot on
Telegram, the vibe-trading package forwards your text to the agent verbatim
(src/channels/runtime.py -> send_message(msg.content)) with no account data
attached. That is the code path that claimed an "AMD $540C" option you never
owned and promised a 3 PM exit that did not exist.

What this does
--------------
Patches the installed package (in this repo's .venv) so every inbound chat
message gets the live snapshot prepended before the agent sees it:

  1. Drops `vibe_chat_snapshot.py` into site-packages. It shells out to THIS
     repo's portfolio.py -- one source of truth, no duplicated logic.
  2. Rewrites the send_message call in src/channels/runtime.py to prepend the
     snapshot (in a thread, so other chats don't stall on the ~3s Alpaca read).

Safe to re-run (it detects itself). start.sh runs it on every launch, so a
`pip install -U` that overwrites the package gets re-patched next start.
A backup of the original file is kept at runtime.py.orig.

Usage:  python install_chat_snapshot.py [--quiet]
"""

from __future__ import annotations

import pathlib
import sys
import sysconfig

REPO = pathlib.Path(__file__).resolve().parent
MARKER = "vibe_chat_snapshot"

SHIM = f'''"""Auto-installed by Vibe-Trader (install_chat_snapshot.py). Safe to delete."""

REPO = {str(REPO)!r}


def account_preamble() -> str:
    """Live account snapshot via the repo's portfolio.py -- '' on any failure."""
    import pathlib
    import subprocess
    import sys

    script = pathlib.Path(REPO) / "portfolio.py"
    if not script.exists():
        return ""
    try:
        out = subprocess.run(
            [sys.executable, str(script), "snapshot"],
            capture_output=True, text=True, timeout=25, cwd=REPO,
        )
        return out.stdout.strip()
    except Exception:
        return ""
'''

ANCHOR = """            result = await self.session_service.send_message(
                session_id,
                msg.content,
                include_shell_tools=False,
            )"""

PATCHED = """            _content = msg.content
            try:  # vibe-trader patch: attach live account data (install_chat_snapshot.py)
                from vibe_chat_snapshot import account_preamble
                _snap = await asyncio.to_thread(account_preamble)
                if _snap:
                    _content = _snap + "\\n\\nUSER MESSAGE:\\n" + _content
            except Exception:
                pass
            result = await self.session_service.send_message(
                session_id,
                _content,
                include_shell_tools=False,
            )"""


def main() -> int:
    quiet = "--quiet" in sys.argv
    say = (lambda *_: None) if quiet else print

    site = pathlib.Path(sysconfig.get_paths()["purelib"])
    runtime = site / "src" / "channels" / "runtime.py"
    if not runtime.exists():
        print(f"!! cannot find {runtime} — is the venv active?", file=sys.stderr)
        return 1

    (site / f"{MARKER}.py").write_text(SHIM)

    text = runtime.read_text()
    if MARKER in text:
        say("chat snapshot patch already applied.")
        return 0
    if ANCHOR not in text:
        print("!! vibe-trading package layout changed — chat patch NOT applied.\n"
              "   Chat replies will not see live positions until this is updated.",
              file=sys.stderr)
        return 1

    (runtime.parent / "runtime.py.orig").write_text(text)
    runtime.write_text(text.replace(ANCHOR, PATCHED, 1))
    # Stale bytecode would silently keep the old behaviour.
    for pyc in (runtime.parent / "__pycache__").glob("runtime.*.pyc"):
        pyc.unlink(missing_ok=True)

    say("chat snapshot patch applied — the Telegram chat bot now sees your real account.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
