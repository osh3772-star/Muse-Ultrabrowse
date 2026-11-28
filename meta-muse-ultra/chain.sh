#!/usr/bin/env bash
# Muse Ultra Browser chain entry — agent-first contract (2026-11-24 redesign).
#   chain.sh read <url>   classification R (public, read-only): L0 fetch -> L1
#   chain.sh open <url>   classification V (render/JS needed): L1 only
# Output contract (token-lean, machine-readable):
#   success: winning lane's body + ONE final line, exit 0
#   failure: ONE final line only (no bodies from failed lanes), exit 3 (= descend to L2)
#   final line: %%CHAIN%% final lane=<..> status=<..> code=<..> path=<L0:F-IP>L1:ok> elapsed_s=<n>
# Login-required work does NOT enter this chain (H255 agent-browser rule).
# Per-domain route cache hints skip lanes that recently failed for that domain.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:?usage: chain.sh read|open <url>}"
URL="${2:?usage: chain.sh read|open <url>}"
DOMAIN=$(python3 -c 'import sys; from urllib.parse import urlparse; print((urlparse(sys.argv[1]).hostname or "").lower())' "$URL")
# Vault-aware routing (2026-11-28, adopted from pickle-ultra-browser): if
# agent-vault holds a credential for this host, a login wall (F-AUTH) is
# routed to this harness's own vault-login.mjs (exit 5) instead of L2.
# Metadata only — vault-match.py never touches a value.
VAULT_ENTRY=$(python3 "$HERE/vault-match.py" "$DOMAIN" 2>/dev/null || true)
CACHE=$(python3 "$HERE/routecache.py" get "$DOMAIN" 2>/dev/null || echo "l0=- l1=-")
L0C=$(echo "$CACHE" | sed -n 's/.*l0=\([^ ]*\).*/\1/p')
L1C=$(echo "$CACHE" | sed -n 's/.*l1=\([^ ]*\).*/\1/p')
START=$(date +%s.%N)
elapsed() { awk -v s="$START" -v e="$(date +%s.%N)" 'BEGIN{printf "%.1f", e-s}'; }
T0=$(mktemp /tmp/meta-muse-ultra-chain-l0-XXXXXX.txt)
T1=$(mktemp /tmp/meta-muse-ultra-chain-l1-XXXXXX.txt)
trap 'rm -f "$T0" "$T1"' EXIT
field() { grep '^%%CHAIN%%' "$1" 2>/dev/null | tail -1 | sed -n "s/.* $2=\([^ ]*\).*/\1/p"; }
body() { grep -v '^%%CHAIN%%' "$1"; }
setcache() { python3 "$HERE/routecache.py" set "$DOMAIN" "$1" "$2" >/dev/null 2>&1; }
fin() { # lane status code path exitcode
  # Handoff contract (2026-11-27 audit fix, MUSE-010): exit 3 means "L2
  # handoff REQUIRED", never "L2 succeeded" — say so in the line itself.
  # Exit 5 (2026-11-28): F-AUTH and the vault holds a credential for this
  # host — the handoff target is this harness's vault-login, not L2.
  # Exit 1 with F-DETECT: our own detector failed; that is a hard local
  # failure (next_action=none), never a handoff and never cached.
  if [ "$5" = "3" ]; then
    echo "%%CHAIN%% final lane=$1 status=$2 code=$3 path=$4 elapsed_s=$(elapsed) next_action=L2 handoff_completed=false"
  elif [ "$5" = "5" ]; then
    echo "%%CHAIN%% final lane=$1 status=$2 code=$3 path=$4 elapsed_s=$(elapsed) next_action=vault-login vault=$VAULT_ENTRY handoff_completed=false"
  elif [ "$3" = "F-DETECT" ]; then
    echo "%%CHAIN%% final lane=$1 status=$2 code=$3 path=$4 elapsed_s=$(elapsed) next_action=none"
  else
    echo "%%CHAIN%% final lane=$1 status=$2 code=$3 path=$4 elapsed_s=$(elapsed)"
  fi
  exit "$5"
}
# Overall budget (MUSE-009, proportional form): per-lane timeouts already
# bound a normal run (L0 20s + L1 60s + one in-lane retry) well under the
# documented 5 minutes; this guard only stops pathological stacks (slow
# daemon starts, retries) from drifting past it. CHAIN_BUDGET_S overrides.
BUDGET="${CHAIN_BUDGET_S:-300}"
over_budget() { awk -v e="$(elapsed)" -v b="$BUDGET" 'BEGIN{exit !(e+0 > b+0)}'; }

if [ "$MODE" = "open" ]; then
  "$HERE/run.sh" open "$URL" > "$T1" 2>/dev/null
  ST=$(field "$T1" status); CODE=$(field "$T1" code)
  if [ "$ST" = "ok" ]; then
    setcache l1 ok
    body "$T1"
    fin L1 ok - "L1:ok" 0
  fi
  if [ "$CODE" = "F-DETECT" ]; then
    fin L1 fail F-DETECT "L1:F-DETECT" 1
  fi
  if [ "$CODE" = "F-AUTH" ] && [ -n "$VAULT_ENTRY" ]; then
    setcache l1 F-AUTH
    fin L1 fail F-AUTH "L1:F-AUTH" 5
  fi
  setcache l1 "${CODE:-F-NET}"
  fin L1 fail "${CODE:-F-NET}" "L1:${CODE:-F-NET}" 3
fi

# --- classification R: read ---
PATHREC=""
if [ "$L0C" != "-" ] && [ "$L0C" != "ok" ]; then
  PATHREC="L0:skip($L0C)"
else
  "$HERE/fetch.sh" "$URL" > "$T0" 2>/dev/null
  ST=$(field "$T0" status); CODE=$(field "$T0" code)
  if [ "$ST" = "ok" ]; then
    setcache l0 ok
    body "$T0"
    fin L0 ok - "L0:ok" 0
  fi
  # F-DETECT is our own detector failing, not a property of the domain:
  # never cache it (it would poison the route for a healthy detector).
  [ "${CODE:-}" != "F-DETECT" ] && setcache l0 "${CODE:-F-NET}"
  PATHREC="L0:${CODE:-F-NET}"
fi

if [ "$L1C" = "F-IP" ] || [ "$L1C" = "F-BOT" ]; then
  fin none fail "$L1C" "$PATHREC>L1:skip($L1C)" 3
fi

if over_budget; then
  fin L1 fail F-TIMEOUT "$PATHREC>L1:skip(budget)" 3
fi

"$HERE/run.sh" read "$URL" > "$T1" 2>/dev/null
ST=$(field "$T1" status); CODE=$(field "$T1" code)
if [ "$ST" = "ok" ]; then
  setcache l1 ok
  body "$T1"
  fin L1 ok - "$PATHREC>L1:ok" 0
fi
if [ "$CODE" = "F-DETECT" ]; then
  fin L1 fail F-DETECT "$PATHREC>L1:F-DETECT" 1
fi
if [ "$CODE" = "F-AUTH" ] && [ -n "$VAULT_ENTRY" ]; then
  setcache l1 F-AUTH
  fin L1 fail F-AUTH "$PATHREC>L1:F-AUTH" 5
fi
setcache l1 "${CODE:-F-NET}"
fin L1 fail "${CODE:-F-NET}" "$PATHREC>L1:${CODE:-F-NET}" 3
