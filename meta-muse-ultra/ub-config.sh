# ub-config.sh — shared environment resolution for meta-muse-ultra.
# Sourced by run.sh, chrome-wrapper.sh, ensure-nssdb.sh, fetch.sh and
# stop-relay.sh. Every machine-specific value (Chromium binary, egress
# proxy, proxy CA / NSS DB, state/profile directories) is resolved here
# from configuration with portable defaults, so the same tree runs on
# another Muse instance without code edits. Per-instance overrides live
# in config.env next to this file (see config.env.example).
# shellcheck shell=bash

# Directory containing this file (the meta-muse-ultra tree).
UB_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Per-instance config (optional). run.sh sources it before us already;
# sourcing twice is harmless (plain assignments).
if [ -f "$UB_HOME/config.env" ]; then
  set -a; . "$UB_HOME/config.env"; set +a
fi

# --- directories -----------------------------------------------------------
# State dir (daemon socket/pid/logs). Override: MUSE_ULTRA_STATE_DIR.
MUSE_ULTRA_STATE_DIR="${MUSE_ULTRA_STATE_DIR:-$HOME/.local/share/muse-ultra-browser}"
# Browser profile (logins live here). Default: <tree>/profile.
MUSE_ULTRA_PROFILE="${MUSE_ULTRA_PROFILE:-$UB_HOME/profile}"
# HOME given to the Chrome process (holds the NSS DB under .pki/nssdb).
MUSE_ULTRA_CHROME_HOME="${MUSE_ULTRA_CHROME_HOME:-$UB_HOME/chrome-home}"
export MUSE_ULTRA_STATE_DIR MUSE_ULTRA_PROFILE MUSE_ULTRA_CHROME_HOME

# --- egress proxy ----------------------------------------------------------
# UB_PROXY (explicit, historic name) > MUSE_ULTRA_PROXY (config.env) >
# HTTPS_PROXY / https_proxy (standard environment) > empty = direct.
UB_PROXY="${UB_PROXY:-${MUSE_ULTRA_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}}"
export UB_PROXY
# Host/port parsed out of the proxy URL (userinfo stripped) for the relay.
UB_PROXY_HOST=""; UB_PROXY_PORT=""
if [ -n "$UB_PROXY" ]; then
  _ub_hp="${UB_PROXY#*://}"; _ub_hp="${_ub_hp##*@}"; _ub_hp="${_ub_hp%%/*}"
  UB_PROXY_HOST="${_ub_hp%:*}"; UB_PROXY_PORT="${_ub_hp##*:}"
  if [ "$UB_PROXY_PORT" = "$UB_PROXY_HOST" ]; then
    case "$UB_PROXY" in https://*) UB_PROXY_PORT=443 ;; *) UB_PROXY_PORT=80 ;; esac
  fi
  unset _ub_hp
fi
export UB_PROXY_HOST UB_PROXY_PORT
# Proxy URL safe to hand to Chrome's --proxy-server: embedded credentials
# are stripped (headless Chrome cannot answer proxy auth prompts).
UB_PROXY_FOR_CHROME=""
if [ -n "$UB_PROXY" ]; then
  case "$UB_PROXY" in
    *://*@*) UB_PROXY_FOR_CHROME="${UB_PROXY%%://*}://${UB_PROXY_HOST}:${UB_PROXY_PORT}" ;;
    *) UB_PROXY_FOR_CHROME="$UB_PROXY" ;;
  esac
fi
export UB_PROXY_FOR_CHROME

# Local socat relay in front of the proxy. Some sandboxes refuse Chrome's
# own CONNECT while letting other processes through; the relay hides the
# process identity (the traffic still goes through the same proxy).
# MUSE_ULTRA_RELAY: auto (default — relay only when a non-local proxy is
# configured and socat exists) | 1 (force) | 0 (never, use proxy directly).
MUSE_ULTRA_RELAY="${MUSE_ULTRA_RELAY:-auto}"
UB_RELAY_PORT="${UB_RELAY_PORT:-18080}"
export MUSE_ULTRA_RELAY UB_RELAY_PORT

ub_relay_wanted() {
  [ -n "$UB_PROXY" ] || return 1
  case "$MUSE_ULTRA_RELAY" in
    0|off|no) return 1 ;;
    1|on|yes) command -v socat >/dev/null 2>&1 ;;
    *) case "$UB_PROXY_HOST" in
         ""|127.0.0.1|localhost|::1) return 1 ;;
         *) command -v socat >/dev/null 2>&1 ;;
       esac ;;
  esac
}

# --- proxy CA / NSS --------------------------------------------------------
# UB_PROXY_CA (config) > HATCH_EGRESS_CA (historic env) > the Hatch sandbox
# CA path when it exists on this machine. Empty result = no proxy CA
# configured: the NSS preparation step is skipped entirely.
# UB_PROXY_CA=none forces "no CA" (also disables the auto-detection).
UB_PROXY_CA="${UB_PROXY_CA:-${HATCH_EGRESS_CA:-}}"
if [ "$UB_PROXY_CA" = "none" ]; then
  UB_PROXY_CA=""
elif [ -z "$UB_PROXY_CA" ] && [ -f /usr/local/share/ca-certificates/hatch-egress-ca.crt ]; then
  UB_PROXY_CA=/usr/local/share/ca-certificates/hatch-egress-ca.crt
fi
export UB_PROXY_CA
UB_NSSDB_DIR="$MUSE_ULTRA_CHROME_HOME/.pki/nssdb"
UB_NSSDB_NICK="${UB_NSSDB_NICK:-hatch-egress}"
export UB_NSSDB_DIR UB_NSSDB_NICK

# --- Chromium binary -------------------------------------------------------
# MUSE_ULTRA_CHROME / CHROME_BIN (explicit) > Playwright browser cache
# (newest chromium-* revision; PLAYWRIGHT_BROWSERS_PATH honored) >
# PATH (google-chrome-stable, google-chrome, chromium, chromium-browser).
# Prints the resolved path on stdout. On failure prints what was tried to
# stderr and returns 1 — callers fail with that message, not a crash.
ub_resolve_chrome() {
  local c d root
  for c in "${MUSE_ULTRA_CHROME:-}" "${CHROME_BIN:-}"; do
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  local roots=()
  [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && roots+=("$PLAYWRIGHT_BROWSERS_PATH")
  roots+=("$HOME/.cache/ms-playwright")
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    c=$(ls -d "$root"/chromium-*/chrome-linux*/chrome "$root"/chromium-*/chrome-mac*/Chromium.app/Contents/MacOS/Chromium 2>/dev/null | sort -V | tail -1)
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
    c=$(ls -d "$root"/chromium_headless_shell-*/chrome-linux*/headless_shell 2>/dev/null | sort -V | tail -1)
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  for c in google-chrome-stable google-chrome chromium chromium-browser chrome; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  {
    echo "ub-config: no Chromium binary found. Tried:"
    echo "  - \$MUSE_ULTRA_CHROME / \$CHROME_BIN (unset or not executable)"
    echo "  - Playwright cache: ${roots[*]} (no chromium-*/chrome-linux*/chrome)"
    echo "  - PATH: google-chrome-stable google-chrome chromium chromium-browser chrome"
    echo "Fix: install Chromium (e.g. 'npx playwright install chromium') or set"
    echo "MUSE_ULTRA_CHROME=/path/to/chrome in config.env."
  } >&2
  return 1
}

# Full version of a Chromium binary ("159.0.8154.6"); empty on failure.
ub_chrome_full_version() { "$1" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){3}' | head -1; }
