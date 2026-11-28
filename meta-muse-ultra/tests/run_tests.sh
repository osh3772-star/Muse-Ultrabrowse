#!/usr/bin/env bash
# Regression tests for the defects fixed in the 2026-11-27 audit pass,
# plus the 2026-11-28 pickle-adopt surface (F-DETECT, fail-closed password
# guard, daemon start lock, vault-match + chain vault routing, vault-login
# mock flows incl. the CAPTCHA answer-file bridge — all local fixtures,
# fake credentials only).
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

# --- L0 F-DETECT (2026-11-28): a broken detector is not a page verdict ---
cp "$T/html2text.py" "$T/html2text.py.bak"
printf 'import sys; sys.exit(1)\n' > "$T/html2text.py"
check "F-DETECT broken extractor is F-DETECT in L0" 'code=F-DETECT' "$(l0 public)"
mv "$T/html2text.py.bak" "$T/html2text.py"

# --- vault-match.py (metadata only) ---
VMETA="$T/vault-meta.json"
cat > "$VMETA" <<'EOF'
{"neonet-80598881": {"purpose": "부동산뱅크 로그인용", "stored": "2026-11-25"},
 "zigbang-osh3629": {"purpose": "직방 로그인용", "stored": "2026-11-25"},
 "localtest-x": {"purpose": "로컬 테스트", "site": "127.0.0.1", "stored": "2026-11-28"}}
EOF
check "vault-match subdomain matches entry" 'neonet-80598881' "$(AGENT_VAULT_META="$VMETA" python3 "$T/vault-match.py" agency.neonet.co.kr)"
check "vault-match registrable domain matches" 'zigbang-osh3629' "$(AGENT_VAULT_META="$VMETA" python3 "$T/vault-match.py" ceo.zigbang.com)"
AGENT_VAULT_META="$VMETA" python3 "$T/vault-match.py" example.com >/dev/null 2>&1; VRC=$?
check "vault-match unknown host exits 1" 'rc=1' "rc=$VRC"
AGENT_VAULT_META="$T/no-such-meta.json" python3 "$T/vault-match.py" agency.neonet.co.kr >/dev/null 2>&1; VRC=$?
check "vault-match missing meta exits 1 (safe direction)" 'rc=1' "rc=$VRC"

# --- intake: a failed row's password is blanked too (2026-11-28) ---
mkdir -p "$T/vault2" "$T/intake-test"
cp "$HOME/workspace/agent-vault/vault.py" "$T/vault2/vault.py"
python3 "$T/vault2/vault.py" init >/dev/null 2>&1
python3 - "$T" <<'EOF'
import sys
t = sys.argv[1]
rows = [
    ["site", "username", "password", "entry", "purpose"],
    ["https://good.example/login", "gooduser", "good-pw-1", "goodentry", "테스트"],
    ["https://bad.example/login", "baduser", "bad-pw-1", "BAD ENTRY!", "테스트"],
]
with open(t + "/intake-test/form.tsv", "w", encoding="utf-8") as f:
    for r in rows:
        f.write("\t".join(r) + "\n")
EOF
IOUT=$(python3 "$SRC/intake/apply-intake.py" "$T/intake-test/form.tsv" --vault-py "$T/vault2/vault.py" 2>/dev/null)
check "intake stores the good row" 'ok site=https://good.example/login cleared=yes' "$IOUT"
check "intake blanks a failed row's password" 'fail site=https://bad.example/login cleared=yes reason=bad-entry' "$IOUT"
FORMAFTER=$(cat "$T/intake-test/form.tsv" 2>/dev/null)
case "$FORMAFTER" in *bad-pw-1*|*good-pw-1*) PWLEAK=leaked ;; *) PWLEAK=clean ;; esac
check "intake kept form holds no password values" 'clean' "$PWLEAK"
case "$FORMAFTER" in *baduser*) USERKEPT=kept ;; *) USERKEPT=lost ;; esac
check "intake kept form preserves the username" 'kept' "$USERKEPT"

# --- L1 (run.sh + daemon) ---
if [ "${UB_TEST_SKIP_L1:-}" != "1" ]; then
  check "001 L1 long doc stays ok"        'status=ok'   "$(l1 longdoc)"
  check "001 L1 challenge is F-BOT"       'code=F-BOT'  "$(l1 challenge)"
  check "002 L1 login wall is F-AUTH"     'code=F-AUTH' "$(l1 login)"
  check "002 L1 public page stays ok"     'status=ok'   "$(l1 public)"
  SP=$(stat -c '%a' "$HOME/.local/share/muse-ultra-browser/cdp-daemon.sock" 2>/dev/null || echo '?')
  check "004 daemon socket is owner-only" '600' "$SP"

  # --- chain.sh vault-aware routing (2026-11-28) ---
  COUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy AGENT_VAULT_META="$VMETA" timeout 120 ./chain.sh open "http://127.0.0.1:$PORT/login" 2>/dev/null); CRC=$?
  check "chain F-AUTH with vault entry routes to vault-login" 'next_action=vault-login vault=localtest-x' "$COUT"
  check "chain vault route exit code is 5" 'rc=5' "rc=$CRC"
  COUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy AGENT_VAULT_META="$T/no-meta.json" timeout 120 ./chain.sh open "http://127.0.0.1:$PORT/login" 2>/dev/null); CRC=$?
  check "chain F-AUTH without vault entry keeps L2 handoff" 'next_action=L2' "$COUT"
  check "chain L2 handoff exit code is 3" 'rc=3' "rc=$CRC"

  # --- fail-closed password guard (2026-11-28) ---
  cat > "$T/guard.js" <<EOF
const t = await taskSpace('guard-test');
const p = await t.newPage();
await p.goto('http://127.0.0.1:$PORT/guardpage');
let refused = 'no';
try { await p.type('#gpw', 'should-not-type'); } catch (e) { refused = String((e && e.message) || e).includes('password_field_refused') ? 'yes' : 'other'; }
let typed = '';
try { await p.type('#q', 'hello'); typed = await p.evaluate(() => document.querySelector('#q').value); } catch (e) { typed = 'ERR'; }
await t.finish({ keep: [] });
console.log('guard-refused=' + refused + ' typed=' + typed);
EOF
  GOUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy timeout 90 ./run.sh -f guard.js 2>/dev/null)
  check "guard refuses typing into a password field" 'guard-refused=yes' "$GOUT"
  check "guard still types into a text field" 'typed=hello' "$GOUT"

  # --- daemon start lock: a stale lock is reclaimed (2026-11-28) ---
  (cd "$T" && ./run.sh stop >/dev/null 2>&1)
  LOCKDIR="$HOME/.local/share/muse-ultra-browser/daemon.start.lock"
  mkdir -p "$LOCKDIR"; touch -d '1 hour ago' "$LOCKDIR"
  printf 'console.log("lock-ok");\n' > "$T/lock.js"
  LOUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy timeout 90 ./run.sh -f lock.js 2>/dev/null)
  check "stale daemon start lock is reclaimed" 'lock-ok' "$LOUT"

  # --- vault-login mock flows (fake vault, local pages only) ---
  mkdir -p "$T/vault"
  cp "$HOME/workspace/agent-vault/vault.py" "$T/vault/vault.py"
  python3 "$T/vault/vault.py" init >/dev/null 2>&1
  printf '%s' '{"username":"tester","password":"pw-1234"}' | python3 "$T/vault/vault.py" store localtest --purpose '로컬 테스트용 가짜 항목' >/dev/null 2>&1
  VOUT=$(node "$T/vault-login.mjs" "http://127.0.0.1:$PORT/vaultlogin" localtest --site example.com 2>/dev/null); VRC=$?
  check "vault-login origin gate refuses a foreign site" '"status":"origin_mismatch"' "$VOUT"
  check "vault-login origin refusal exit code is 2" 'rc=2' "rc=$VRC"
  VOUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy MUSE_ULTRA_VAULT_PY="$T/vault/vault.py" timeout 120 node vault-login.mjs "http://127.0.0.1:$PORT/vaultlogin" localtest --site 127.0.0.1 2>/dev/null)
  check "vault-login local flow logs in" '"status":"logged_in"' "$VOUT"
  ANS="$T/captcha-answer.txt"; STATE="$T/captcha-state.json"
  ( sleep 6; printf 'AB12' > "$ANS" ) &
  VOUT=$(cd "$T" && env -u HTTPS_PROXY -u https_proxy MUSE_ULTRA_VAULT_PY="$T/vault/vault.py" timeout 180 node vault-login.mjs "http://127.0.0.1:$PORT/vaultcaptcha" localtest --site 127.0.0.1 --wait-answer-file "$ANS" --state-file "$STATE" --wait-timeout 90 2>/dev/null)
  check "vault-login CAPTCHA answer-file bridge logs in" '"status":"logged_in"' "$VOUT"
  if [ -f "$ANS" ]; then AEX=present; else AEX=gone; fi
  check "vault-login consumes the answer file" 'gone' "$AEX"
  SM=$(stat -c '%a' "$STATE" 2>/dev/null || echo '?')
  check "vault-login state file is 0600" '600' "$SM"
fi

echo "----"
echo "tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
