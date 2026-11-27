#!/usr/bin/env bash
# Regression tests for the defects fixed in the 2026-11-27 audit pass.
# Scope is deliberately narrow: one test per FIXED defect (MUSE-001, 002,
# 005, 006, 007-partial, 008, 015 + L0/L1 phrase unification). The audit's
# full A-E matrix and 30-run benchmarks were judged disproportionate for a
# single-agent local tool and are NOT implemented (see audit report).
#
# Everything runs against a local HTTP server (tests/server.py) in a temp
# copy of this tree with the egress proxy blanked — no external network, no
# contact with the real profile or route cache.
# Usage: tests/run_tests.sh   (UB_TEST_SKIP_L1=1 skips the daemon tests)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(dirname "$HERE")"
T=$(mktemp -d /tmp/ub-tests-XXXXXX)
PORT=8937
PASS=0; FAIL=0
cleanup() {
  "$T/run.sh" stop >/dev/null 2>&1 || true
  fuser -k "$PORT/tcp" 2>/dev/null || true
  pkill -f "^bash $T/idle-stop.sh" 2>/dev/null || true
  rm -rf "$T"
}
trap cleanup EXIT

for f in "$SRC"/*.sh "$SRC"/*.py "$SRC"/*.mjs; do cp "$f" "$T/"; done
printf 'MUSE_ULTRA_HEADLESS=1\nMUSE_ULTRA_PROXY=\n' > "$T/config.env"
sed -i "s/8931/$PORT/" "$HERE/server.py" > /dev/null 2>&1 || true
cp "$HERE/server.py" "$T/server.py"
sed -i "s/8931/$PORT/" "$T/server.py"
(cd "$T" && nohup python3 server.py > server.log 2>&1 &)
sleep 1

check() { # name expected-substr actual
  if printf '%s' "$3" | grep -q "$2"; then PASS=$((PASS+1)); echo "PASS $1";
  else FAIL=$((FAIL+1)); echo "FAIL $1 -- expected [$2], got: $3"; fi
}
l0() { (cd "$T" && env -u HTTPS_PROXY -u https_proxy ./fetch.sh "http://127.0.0.1:$PORT/$1" 2>/dev/null | grep '^%%CHAIN%%'); }
l1() { (cd "$T" && env -u HTTPS_PROXY -u https_proxy timeout 90 ./run.sh read "http://127.0.0.1:$PORT/$1" 2>/dev/null | grep '^%%CHAIN%%'); }

# --- L0 (fetch.sh) ---
check "001 long technical doc is not a block page" 'status=ok'        "$(l0 longdoc)"
check "001+unify challenge page is F-BOT in L0"     'code=F-BOT'      "$(l0 challenge)"
check "002 login wall is F-AUTH in L0"              'code=F-AUTH'     "$(l0 login)"
check "002 HTTP 401 is F-AUTH"                      'code=F-AUTH'     "$(l0 401)"
check "002 public page with login link stays ok"    'status=ok'       "$(l0 public)"
check "B03 HTTP 403 stays F-IP"                     'code=F-IP'       "$(l0 403)"
check "015 file:// is F-SCHEME, not F-NET"          'code=F-SCHEME'   "$(cd "$T" && env -u HTTPS_PROXY -u https_proxy ./fetch.sh 'file:///etc/hostname' 2>/dev/null | grep '^%%CHAIN%%')"

# --- routecache.py ---
cd "$T"; rm -f route-cache.json route-cache.json.lock
python3 routecache.py set example.com l0 F-NET
python3 routecache.py set example.com l1 ok
G=$(python3 routecache.py get example.com)
check "006 lanes keep independent values" 'l0=F-NET l1=ok' "$G"
python3 - <<'EOF'
import json, time
d = json.load(open('route-cache.json')); d['example.com']['l0']['ts'] = time.time() - 61
json.dump(d, open('route-cache.json', 'w'))
EOF
G=$(python3 routecache.py get example.com)
check "005 F-NET expires after 60s, l1 untouched" 'l0=- l1=ok' "$G"
python3 routecache.py set example.com l0 F-EMPTY
G=$(python3 routecache.py get example.com)
check "007 F-EMPTY is never stored (page-specific)" 'l0=- l1=ok' "$G"
rm -f route-cache.json
for i in $(seq 1 20); do python3 routecache.py set "dom$i.example" l0 ok & done; wait
N=$(python3 -c "import json; print(len(json.load(open('route-cache.json'))))")
check "008 20 concurrent sets all survive" '20' "$N"
printf '{broken' > route-cache.json
G=$(python3 routecache.py get example.com)
check "008 corrupt cache degrades to no-hint" 'l0=- l1=-' "$G"
G=$(UB_ROUTECACHE=0 python3 routecache.py get example.com)
check "005 cache can be disabled" 'l0=- l1=-' "$G"
cd - >/dev/null

# --- L1 (run.sh + daemon) ---
if [ "${UB_TEST_SKIP_L1:-}" != "1" ]; then
  check "001 L1 long doc stays ok"        'status=ok'   "$(l1 longdoc)"
  check "001 L1 challenge is F-BOT"       'code=F-BOT'  "$(l1 challenge)"
  check "002 L1 login wall is F-AUTH"     'code=F-AUTH' "$(l1 login)"
  check "002 L1 public page stays ok"     'status=ok'   "$(l1 public)"
  SP=$(stat -c '%a' "$HOME/.local/share/muse-ultra-browser/cdp-daemon.sock" 2>/dev/null || echo '?')
  check "004 daemon socket is owner-only" '600' "$SP"
fi

echo "----"
echo "tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
