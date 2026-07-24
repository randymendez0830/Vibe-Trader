#!/usr/bin/env bash
# Runs auto_manage.sh every 30 minutes during US market hours (Mon-Fri).
# Simpler and more reliable on a Mac than cron (no Full Disk Access / TCC issues).
# Launch it once and leave the window open:
#
#     caffeinate -i ./schedule.sh
#
# `caffeinate -i` keeps the Mac awake while this runs. Press Ctrl+C to stop.
#
# NOTE: assumes your Mac's clock is US Eastern time (market = 9:30am-4:00pm ET).
# If your Mac is on a different timezone, change 930 / 1600 below to your local
# equivalent of 9:30am and 4:00pm Eastern.
set -uo pipefail
cd "$(dirname "$0")"

echo "Auto-schedule running. auto_manage runs every 30 min, Mon-Fri 10:00am-4:00pm ET (skips the volatile first 30 min)."
echo "Leave this window open. Press Ctrl+C to stop."

while true; do
  dow=$(date +%u)                 # 1=Mon .. 7=Sun
  hm=$((10#$(date +%H%M)))        # local time as HHMM (base-10 forced)
  if [ "$dow" -le 5 ] && [ "$hm" -ge 1000 ] && [ "$hm" -le 1600 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M')] running auto_manage pass..."
    ./auto_manage.sh || true
    sleep 1800                    # 30 minutes
  else
    sleep 300                     # outside market hours: re-check in 5 min
  fi
done
