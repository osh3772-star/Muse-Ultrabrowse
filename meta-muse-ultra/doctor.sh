#!/usr/bin/env bash
# doctor.sh — Muse Ultra Browser environment doctor (2026-11-26).
# Verifies that this tree can actually run on the current machine, using the
# same resolution rules as production (config.env + ub-config.sh): required
# tools, Chromium discovery, config sanity, state/profile directories,
# proxy reachability and NSS DB readiness.
#
#   doctor.sh           checks only — nothing is started or restarted; the
#                       only writes are creating missing directories (the
#                       fresh-install ENOENT class) and a probe file inside
#                       the state dir. A live profile dir is never written to.
#   doctor.sh --smoke   additionally boots a throwaway daemon on TEMP state /
#                       profile / chrome-home dirs, does one eval round-trip
#                       and stops it. The real daemon and profile are never
#                       touched.
#
# Output: one PASS/FAIL/SKIP line per check with a one-line reason, then a
# summary. Exit code is non-zero when a critical check fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/config.env" ] && set -a && . "$HERE/config.env" && set +a
export PATH="$HOME/.local/bin:$PATH"
. "$HERE/ub-config.sh"

SMOKE=0
case "${1:-}" in
  --smoke) SMOKE=1 ;;
  "") ;;
  *) echo "usage: doctor.sh [--smoke]" >&2; exit 2 ;;
esac

NPASS=0; NFAIL=0; NSKIP=0; NCRIT=0
ok()   { NPASS=$((NPASS+1)); printf 'PASS  %-12s %s\n' "$1" "$2"; }
bad()  { NFAIL=$((NFAIL+1)); [ "${3:-0}" = 1 ] && NCRIT=$((NCRIT+1)); printf 'FAIL  %-12s %s\n' "$1" "$2"; }
skip() { NSKIP=$((NSKIP+1)); printf 'SKIP  %-12s %s\n' "$1" "$2"; }

echo "doctor: Muse Ultra Browser — $HERE"

# --- OS / architecture ------------------------------------------------------
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Linux|Darwin) ok "os" "$OS $ARCH" ;;
  *) bad "os" "unsupported OS: $OS $ARCH (Linux/macOS expected)" 1 ;;
esac

# --- runtime tools ----------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  NODE_V="$(node --version)"; NODE_MAJ="${NODE_V#v}"; NODE_MAJ="${NODE_MAJ%%.*}"
  if [ "$NODE_MAJ" -ge 22 ] 2>/dev/null; then ok "node" "$NODE_V (>= 22)"
  else bad "node" "$NODE_V — Node >= 22 required (daemon uses Node 22 built-ins)" 1; fi
else bad "node" "node not found in PATH" 1; fi

if command -v python3 >/dev/null 2>&1; then ok "python3" "$(python3 --version 2>&1)"
else bad "python3" "python3 not found (snaptrim.py / html2text.py / routecache.py need it)" 1; fi

if command -v curl >/dev/null 2>&1; then ok "curl" "present (L0 fetch.sh)"
else bad "curl" "curl not found — L0 fetch.sh cannot run (L1 read unaffected)"; fi

# socat is only needed when the local relay in front of the proxy is intended:
# a non-local proxy configured and the relay not disabled.
RELAY_INTENT=0
if [ -n "$UB_PROXY" ] && [ "$MUSE_ULTRA_RELAY" != "0" ]; then
  case "$UB_PROXY_HOST" in ""|127.0.0.1|localhost|::1) ;; *) RELAY_INTENT=1 ;; esac
fi
if command -v socat >/dev/null 2>&1; then
  if [ "$RELAY_INTENT" = 1 ]; then ok "socat" "present (relay :$UB_RELAY_PORT -> $UB_PROXY_HOST:$UB_PROXY_PORT)"
  else ok "socat" "present (relay not needed in this configuration)"; fi
elif [ "$RELAY_INTENT" = 1 ]; then
  bad "socat" "socat missing — relay unavailable; Chrome will connect to the proxy directly"
else skip "socat" "not needed (no non-local proxy / relay disabled)"; fi

# certutil/openssl matter only when a proxy CA is configured.
CA_FILE_OK=0
if [ -n "$UB_PROXY_CA" ]; then
  if [ ! -f "$UB_PROXY_CA" ]; then
    bad "proxy-ca" "configured CA file not found: $UB_PROXY_CA" 1
  elif ! command -v certutil >/dev/null 2>&1; then
    bad "proxy-ca" "certutil missing — cannot prepare the NSS DB for $UB_PROXY_CA" 1
  elif ! command -v openssl >/dev/null 2>&1; then
    CA_FILE_OK=1
    bad "proxy-ca" "openssl missing — CA fingerprint compare unavailable (NSS DB would rebuild on every launch)"
  else CA_FILE_OK=1; ok "proxy-ca" "$UB_PROXY_CA (certutil + openssl present)"; fi
else skip "proxy-ca" "no proxy CA configured — NSS preparation is skipped by design"; fi

# --- Chromium discovery (same resolver the wrapper uses) ---------------------
CHROME_BIN=""
if CHROME_BIN="$(ub_resolve_chrome 2>/dev/null)" && [ -n "$CHROME_BIN" ]; then
  ok "chromium" "$CHROME_BIN (version $(ub_chrome_full_version "$CHROME_BIN"))"
else
  FIRST="$(ub_resolve_chrome 2>&1 >/dev/null | head -1)"
  bad "chromium" "not found — ${FIRST#ub-config: }" 1
fi

# --- CHROME_PATH (what the daemon spawns) ------------------------------------
EFF_CHROME_PATH="${CHROME_PATH:-$HERE/chrome-wrapper.sh}"
if [ -x "$EFF_CHROME_PATH" ]; then ok "chrome-path" "$EFF_CHROME_PATH"
else bad "chrome-path" "not executable: $EFF_CHROME_PATH" 1; fi

# --- config.env sanity --------------------------------------------------------
if [ -f "$HERE/config.env" ]; then
  PROBLEMS=""
  if [ -n "${CHROME_PATH:-}" ] && [ ! -x "$CHROME_PATH" ]; then PROBLEMS="$PROBLEMS CHROME_PATH not executable ($CHROME_PATH);"; fi
  if [ -n "${MUSE_ULTRA_CHROME:-}" ] && [ ! -x "$MUSE_ULTRA_CHROME" ]; then PROBLEMS="$PROBLEMS MUSE_ULTRA_CHROME not executable ($MUSE_ULTRA_CHROME);"; fi
  if [ -n "${MUSE_ULTRA_PROXY:-}" ] && [ -z "$UB_PROXY_HOST" ]; then PROBLEMS="$PROBLEMS MUSE_ULTRA_PROXY does not parse to host:port;"; fi
  if [ -z "$PROBLEMS" ]; then ok "config" "config.env present — set values resolve (paths exist, proxy parses)"
  else bad "config" "config.env problems:$PROBLEMS"; fi
else skip "config" "config.env absent — ub-config.sh resolves from environment/defaults"; fi

# --- directories ---------------------------------------------------------------
# label dir critical probe(1=write a probe file; 0=writability flag only —
# a pre-existing browser profile is never written into)
check_dir() {
  local label="$1" dir="$2" crit="$3" probe="$4" created=""
  if [ ! -d "$dir" ]; then
    if mkdir -p "$dir" 2>/dev/null; then created=" (created)"
    else bad "$label" "cannot create: $dir" "$crit"; return; fi
  fi
  if [ ! -w "$dir" ]; then bad "$label" "not writable: $dir" "$crit"; return; fi
  if [ "$probe" = 1 ]; then
    local pf="$dir/.doctor-probe-$$"
    if touch "$pf" 2>/dev/null; then rm -f "$pf"; else bad "$label" "write probe failed: $dir" "$crit"; return; fi
  fi
  ok "$label" "$dir$created"
}
check_dir "state-dir" "$MUSE_ULTRA_STATE_DIR" 1 1
check_dir "profile-dir" "$MUSE_ULTRA_PROFILE" 1 0
check_dir "chrome-home" "$MUSE_ULTRA_CHROME_HOME" 0 1

# --- proxy reachability ---------------------------------------------------------
# Only host:port is ever printed — the configured URL may embed credentials.
if [ -z "$UB_PROXY" ]; then
  skip "proxy" "not configured — direct connection is the default"
elif timeout 5 bash -c "exec 3<>/dev/tcp/$UB_PROXY_HOST/$UB_PROXY_PORT" 2>/dev/null; then
  ok "proxy" "reachable: $UB_PROXY_HOST:$UB_PROXY_PORT"
else
  bad "proxy" "not reachable: $UB_PROXY_HOST:$UB_PROXY_PORT (TCP connect failed)"
fi

# --- NSS DB readiness -------------------------------------------------------------
if [ -z "$UB_PROXY_CA" ]; then
  skip "nss-db" "no proxy CA — nothing to prepare"
elif [ "$CA_FILE_OK" != 1 ]; then
  skip "nss-db" "cannot inspect — see the proxy-ca check above"
else
  DB="$UB_NSSDB_DIR"
  if [ -d "$DB" ]; then
    SRC_FP="$(openssl x509 -in "$UB_PROXY_CA" -noout -sha256 -fingerprint 2>/dev/null | cut -d= -f2)"
    DB_FP="$(certutil -L -d "sql:$DB" -n "$UB_NSSDB_NICK" -a 2>/dev/null | openssl x509 -noout -sha256 -fingerprint 2>/dev/null | cut -d= -f2)"
    if [ -n "$SRC_FP" ] && [ "$SRC_FP" = "$DB_FP" ]; then ok "nss-db" "ready: $DB (CA fingerprint matches)"
    else ok "nss-db" "present but CA not imported yet — chrome-wrapper rebuilds it on first launch"; fi
  else
    ok "nss-db" "not built yet — chrome-wrapper builds it on first launch (ensure-nssdb.sh)"
  fi
fi

# --- vault-login readiness --------------------------------------------------------
if [ -f "$HERE/vault-login.mjs" ] && node --check "$HERE/vault-login.mjs" 2>/dev/null; then
  if [ -f "${MUSE_ULTRA_VAULT_PY:-$HOME/workspace/agent-vault/vault.py}" ]; then
    ok "vault-login" "vault-login.mjs syntax OK; agent-vault present (contents never inspected)"
  else
    skip "vault-login" "vault-login.mjs OK; agent-vault not installed — vault logins unavailable"
  fi
else
  bad "vault-login" "vault-login.mjs missing or has a syntax error" 0
fi

# --- daemon smoke (opt-in) ---------------------------------------------------------
if [ "$SMOKE" = 1 ]; then
  SMOKE_TMP="$(mktemp -d /tmp/ub-doctor-smoke-XXXXXX)"
  SMOKE_JS="$SMOKE_TMP/smoke.js"
  SMOKE_ERR="$SMOKE_TMP/smoke.err"
  printf 'const t = await taskSpace("doctor-smoke");\nconst p = await t.newPage();\nconst v = await p.evaluate(() => 21 * 2);\nawait t.finish({ keep: [] });\nconsole.log("doctor-smoke-eval=" + v);\n' > "$SMOKE_JS"
  OUT="$(MUSE_ULTRA_STATE_DIR="$SMOKE_TMP/state" MUSE_ULTRA_PROFILE="$SMOKE_TMP/profile" \
         MUSE_ULTRA_CHROME_HOME="$SMOKE_TMP/chrome-home" MUSE_ULTRA_CDP_PORT=19331 \
         timeout 90 node "$HERE/cdp-client.mjs" < "$SMOKE_JS" 2> "$SMOKE_ERR")"; RC=$?
  # Stop the throwaway daemon with the same temp environment, then verify
  # it is really gone before removing the directory.
  MUSE_ULTRA_STATE_DIR="$SMOKE_TMP/state" timeout 15 node "$HERE/cdp-client.mjs" --stop >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6 7 8; do [ ! -S "$SMOKE_TMP/state/cdp-daemon.sock" ] && break; sleep 1; done
  if [ -S "$SMOKE_TMP/state/cdp-daemon.sock" ] && [ -f "$SMOKE_TMP/state/cdp-daemon.pid" ]; then
    kill "$(cat "$SMOKE_TMP/state/cdp-daemon.pid" 2>/dev/null)" 2>/dev/null || true; sleep 1
  fi
  if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'doctor-smoke-eval=42'; then
    ok "smoke" "temp daemon eval round-trip OK (eval=42), stopped and cleaned up"
  else
    ERR1="$(tail -1 "$SMOKE_ERR" 2>/dev/null)"
    bad "smoke" "temp daemon round-trip failed (rc=$RC)${ERR1:+ — $ERR1}" 1
  fi
  rm -rf "$SMOKE_TMP"
else
  skip "smoke" "not run (pass --smoke for a temp-daemon eval round-trip)"
fi

echo "----"
echo "doctor: PASS=$NPASS FAIL=$NFAIL SKIP=$NSKIP critical-failures=$NCRIT"
[ "$NCRIT" = 0 ]
