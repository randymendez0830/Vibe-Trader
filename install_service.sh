#!/usr/bin/env bash
# Install the alert system as a background macOS service (launchd LaunchAgent).
#
# After this, alerts.sh runs with NO Terminal window open, starts automatically
# when you log in, and restarts itself if it ever crashes.
#
#   ./install_service.sh              # install + start (alert only)
#   ./install_service.sh --auto-exit  # install + start, closing stopped-out positions
#   ./install_service.sh --status     # is it running?
#   ./install_service.sh --logs       # tail the log
#   ./install_service.sh --uninstall  # stop + remove
#
# IMPORTANT: this keeps running without a Terminal, but your Mac still has to be
# awake. See docs/ALWAYS_ON.md for keeping it awake, and for the cloud-server
# option if you want it running with the laptop closed or off.
set -uo pipefail

LABEL="com.vibetrader.alerts"
PROJ="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_OUT="$HOME/Library/Logs/vibe-alerts.log"
LOG_ERR="$HOME/Library/Logs/vibe-alerts.error.log"

case " $* " in
  *" --status "*)
    echo "Label   : $LABEL"
    echo "Plist   : $PLIST"
    if [ -f "$PLIST" ]; then echo "Installed: yes"; else echo "Installed: no"; fi
    echo ""
    if launchctl list | grep -q "$LABEL"; then
      echo "Running : YES"
      launchctl list | grep "$LABEL" | awk '{print "  PID/status: "$1" / "$2}'
    else
      echo "Running : no"
    fi
    echo ""
    echo "Last 15 log lines ($LOG_OUT):"
    tail -n 15 "$LOG_OUT" 2>/dev/null || echo "  (no log yet)"
    exit 0
    ;;
  *" --logs "*)
    echo "Tailing $LOG_OUT  (Ctrl+C to stop)"
    tail -f "$LOG_OUT" 2>/dev/null || echo "no log yet at $LOG_OUT"
    exit 0
    ;;
  *" --uninstall "*)
    launchctl unload "$PLIST" 2>/dev/null || launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Uninstalled. The alert service is stopped and will not start at login."
    exit 0
    ;;
esac

AUTO_EXIT_ARG=""
case " $* " in *" --auto-exit "*) AUTO_EXIT_ARG="<string>--auto-exit</string>" ;; esac

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-i</string>
        <string>/bin/bash</string>
        <string>${PROJ}/alerts.sh</string>
        ${AUTO_EXIT_ARG}
    </array>

    <key>WorkingDirectory</key>
    <string>${PROJ}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>ThrottleInterval</key>
    <integer>60</integer>

    <key>StandardOutPath</key>
    <string>${LOG_OUT}</string>

    <key>StandardErrorPath</key>
    <string>${LOG_ERR}</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
PLISTEOF

# Validate before loading, so a bad plist doesn't silently do nothing.
if command -v plutil >/dev/null 2>&1; then
  if ! plutil -lint "$PLIST" >/dev/null; then
    echo "ERROR: generated plist is invalid. Not loading."
    plutil -lint "$PLIST"
    exit 1
  fi
fi

# Reload cleanly whether or not it was already loaded.
launchctl unload "$PLIST" 2>/dev/null || true
if ! launchctl load "$PLIST" 2>/dev/null; then
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
fi

sleep 2
echo "Installed: $PLIST"
if launchctl list | grep -q "$LABEL"; then
  echo "Status   : RUNNING ✅"
else
  echo "Status   : not detected yet — check ./install_service.sh --status in a minute"
fi
echo ""
echo "It now runs with no Terminal window, and starts again when you log in."
if [ -n "$AUTO_EXIT_ARG" ]; then
  echo "AUTO-EXIT is ON: stopped-out positions will be closed automatically."
else
  echo "Alert-only mode. Re-run with --auto-exit to close stopped-out positions."
fi
echo ""
echo "  ./install_service.sh --status     check on it"
echo "  ./install_service.sh --logs       watch the log"
echo "  ./install_service.sh --uninstall  stop it"
echo ""
echo "Your Mac still needs to be awake — see docs/ALWAYS_ON.md."
