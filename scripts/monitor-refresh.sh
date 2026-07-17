#!/bin/zsh
# monitor-refresh.sh — revive a stuck/black external monitor without replugging cables.
#
# A thin CLI wrapper around the MonitorRefresh app's built-in command line mode
# (the app binary does native DDC itself — no third-party software required).
#
# Usage:
#   ./monitor-refresh.sh --list            List connected display names
#   ./monitor-refresh.sh "<display name>"  DDC power-cycle (like pressing the
#                                          monitor's power button) — the main fix
#   ./monitor-refresh.sh --hard            Sleep all displays 5s, then wake
#
# Example:
#   ./monitor-refresh.sh "LINK"

APP_BIN=""
for candidate in \
  "$HOME/Applications/MonitorRefresh.app/Contents/MacOS/MonitorRefresh" \
  "/Applications/MonitorRefresh.app/Contents/MacOS/MonitorRefresh"; do
  [[ -x "$candidate" ]] && APP_BIN="$candidate" && break
done

case "$1" in
  --hard)
    echo "Sleeping all displays 5s, then waking..."
    pmset displaysleepnow
    sleep 5
    /usr/bin/caffeinate -u -t 2
    echo "Done."
    ;;
  "")
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
  *)
    [[ -n "$APP_BIN" ]] || { echo "error: MonitorRefresh.app not found — install it first (see README)" >&2; exit 1 }
    if [[ "$1" == "--list" ]]; then
      exec "$APP_BIN" --list
    else
      exec "$APP_BIN" --power-cycle "$1"
    fi
    ;;
esac
