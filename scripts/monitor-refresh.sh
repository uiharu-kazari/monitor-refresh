#!/bin/zsh
# monitor-refresh.sh — revive a stuck/black external monitor without replugging cables.
#
# Requires BetterDisplay (free version is fine) installed in /Applications:
#   https://github.com/waydabber/BetterDisplay
#
# Usage:
#   ./monitor-refresh.sh --list                 List connected display names
#   ./monitor-refresh.sh "<display name>"       DDC power-cycle (like pressing the
#                                               monitor's power button) — the main fix
#   ./monitor-refresh.sh "<display name>" --reconnect
#                                               Software unplug/replug (macOS removes and
#                                               re-adds the display; may move windows)
#   ./monitor-refresh.sh --hard                 Sleep all displays 5s, then wake
#
# Example:
#   ./monitor-refresh.sh "LINK"

BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay

die() { echo "error: $1" >&2; exit 1 }

[[ -x $BD ]] || die "BetterDisplay.app not found in /Applications — install it first."

# DDC through DP->HDMI converters and docks is flaky; retry each command a few times.
ddc() { # ddc <name> <vcp> <value>
  for i in 1 2 3 4 5; do
    "$BD" set -name="$1" -ddc -vcp=$2 -value=$3 2>/dev/null && return 0
    sleep 1
  done
  echo "warning: DDC $2=$3 failed after 5 tries" >&2
  return 1
}

case "$1" in
  --list)
    # Only physical displays ("deviceType" precedes "name" in each JSON object).
    "$BD" get -identifiers | awk -F'"' '
      /"deviceType"/ { type = $4 }
      /"name"/ && type == "Display" { print $4 }' | sort -u
    ;;
  --hard)
    echo "Sleeping all displays 5s, then waking..."
    pmset displaysleepnow
    sleep 5
    /usr/bin/caffeinate -u -t 2
    ;;
  "")
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
  *)
    NAME="$1"
    if [[ "$2" == "--reconnect" ]]; then
      echo "Software unplug/replug of \"$NAME\"..."
      "$BD" set -name="$NAME" -connected=off || die "disconnect failed (may require BetterDisplay Pro)"
      sleep 5
      "$BD" set -name="$NAME" -connected=on
    else
      echo "DDC power-cycling \"$NAME\" (off 6s, then on)..."
      ddc "$NAME" powerMode 4
      sleep 6
      ddc "$NAME" powerMode 1
    fi
    ;;
esac
echo "Done."
