#!/usr/bin/env bash
# meta-muse-ultra idle-stop watchdog: armed by run.sh on every L1 call.
# Sleeps IDLE_STOP_SEC, then stops daemon+relay only if no newer call
# refreshed .chain-state/last-used and keep mode is off.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/.chain-state"
IDLE="${IDLE_STOP_SEC:-600}"
export PATH="$HOME/.local/bin:$PATH"
sleep "$IDLE"
[ -f "$STATE/keep" ] && exit 0
LAST=0
[ -f "$STATE/last-used" ] && LAST=$(cat "$STATE/last-used" 2>/dev/null || echo 0)
NOW=$(date +%s)
AGE=$(( NOW - ${LAST:-0} ))
if [ "$AGE" -ge "$(( IDLE - 2 ))" ]; then
  node "$HERE/cdp-client.mjs" --stop >/dev/null 2>&1 || true
  "$HERE/stop-relay.sh" >/dev/null 2>&1 || true
fi
exit 0
