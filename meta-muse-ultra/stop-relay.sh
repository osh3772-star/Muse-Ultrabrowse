#!/usr/bin/env bash
# meta-muse-ultra: stop the local proxy relay (127.0.0.1:18080).
# Pattern is anchored (^socat) on purpose: an unanchored pkill -f matches any
# process whose command line merely mentions the pattern — including a caller
# shell running a compound command containing this string (measured 2026-11-24:
# idle-stop's stop-relay SIGTERM'd the invoking agent shell).
pkill -f '^socat TCP-LISTEN:18080' 2>/dev/null && echo "relay stopped" || echo "relay not running"
