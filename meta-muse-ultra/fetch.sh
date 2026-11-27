#!/usr/bin/env bash
# meta-muse-ultra L0 — lightweight fetch lane (no browser).
# Usage: fetch.sh <url>
# Fetches via the VM egress proxy and extracts plain text with stdlib python.
# Last stdout line is always the structured chain result:
#   %%CHAIN%% lane=L0 mode=read status=ok|fail code=<F-*> elapsed_s=<n> chars=<n> http=<code>
# On failure the extracted text is NOT printed (diagnostics go to stderr).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="${1:?usage: fetch.sh <url>}"
# Proxy comes from configuration (ub-config.sh): UB_PROXY > MUSE_ULTRA_PROXY
# (config.env) > HTTPS_PROXY env > empty = direct connection. No proxy
# address is baked into this script.
. "$HERE/ub-config.sh"
PROXY="$UB_PROXY"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36'
MAXTIME="${L0_TIMEOUT:-20}"
MINCHARS="${L0_MINCHARS:-100}"
START=$(date +%s.%N)

elapsed() { awk -v s="$START" -v e="$(date +%s.%N)" 'BEGIN{printf "%.1f", e-s}'; }
result() { # status code chars http
  echo "%%CHAIN%% lane=L0 mode=read status=$1 code=$2 elapsed_s=$(elapsed) chars=$3 http=$4"
}

HTML=$(mktemp /tmp/meta-muse-ultra-l0-XXXXXX.html)
TXT=$(mktemp /tmp/meta-muse-ultra-l0-XXXXXX.txt)
# Per-request curl stderr (2026-11-27 audit fix, MUSE-011): the old fixed
# /tmp path let concurrent requests overwrite each other's diagnostics.
CERR=$(mktemp /tmp/meta-muse-ultra-l0-curl-XXXXXX.err)
trap 'rm -f "$HTML" "$TXT" "$CERR"' EXIT

# Supported schemes are http/https only (MUSE-015): anything else gets a
# distinct F-SCHEME instead of being mistaken for a network failure.
case "$URL" in
  http://*|https://*) ;;
  *) result fail F-SCHEME 0 000; exit 1 ;;
esac

CURL_PROXY=()
[ -n "$PROXY" ] && CURL_PROXY=(-x "$PROXY")
HTTPOUT=$(curl -sS "${CURL_PROXY[@]}" -A "$UA" -L --max-time "$MAXTIME" \
  -o "$HTML" -w '%{http_code} %{url_effective}' "$URL" 2>"$CERR")
RC=$?
if [ $RC -ne 0 ]; then
  if [ $RC -eq 28 ]; then result fail F-TIMEOUT 0 000; else result fail F-NET 0 000; fi
  cat "$CERR" >&2
  exit 1
fi
HTTP="${HTTPOUT%% *}"
EFFURL="${HTTPOUT#* }"
if [ "$HTTP" = "401" ]; then
  result fail F-AUTH 0 "$HTTP"; exit 1
fi
if [ "$HTTP" = "403" ] || [ "$HTTP" = "429" ]; then
  result fail F-IP 0 "$HTTP"; exit 1
fi
case "$HTTP" in
  2*|3*) ;;
  *) result fail F-NET 0 "$HTTP"; exit 1 ;;
esac

python3 "$HERE/html2text.py" < "$HTML" > "$TXT" 2>/dev/null
CHARS=$(wc -m < "$TXT")
# Login wall (MUSE-002): a password field in the served HTML plus either a
# login-ish final URL (redirect target counts) or a short body — a public
# page that merely embeds a login form in a long article is NOT a wall.
if grep -qiE 'type[[:space:]]*=[[:space:]]*["'\'']?password' "$HTML"; then
  EFFPATH=$(python3 -c 'import sys; from urllib.parse import urlparse; print(urlparse(sys.argv[1]).path.lower())' "$EFFURL")
  case "$EFFPATH" in
    *login*|*signin*|*sign-in*|*sign_in*) result fail F-AUTH "$CHARS" "$HTTP"; exit 1 ;;
  esac
  if [ "$CHARS" -lt 2000 ]; then
    result fail F-AUTH "$CHARS" "$HTTP"; exit 1
  fi
fi
# Block-page markers served with HTTP 200. Phrase list unified with run.sh
# detect_code() (2026-11-27: L0 was missing the Cloudflare phrases added to
# L1, so a challenge page passed L0 as ok). Corroboration (MUSE-001): a
# keyword alone does not convict a long document — technical articles about
# blocking legitimately contain these phrases (measured false positive:
# 4,199-char HTTP-200 error guide -> F-IP). Real interstitials are short
# (measured Musinsa challenge: ~1.7k chars), so keyword verdicts require
# CHARS < 2500.
if [ "$CHARS" -lt 2500 ]; then
  if grep -qiE 'attention required|sorry, you have been blocked|access denied|접속이 일시적으로 제한|접속이 제한되었습니다|비정상적인 접근이 감지' "$TXT"; then
    result fail F-IP "$CHARS" "$HTTP"; exit 1
  fi
  if grep -qiE 'verify you are human|are you a robot|unusual traffic from your computer|just a moment|performing security verification|checking if the site connection is secure|verifying you are human|사람인지 확인하는 중|보안 확인 수행 중' "$TXT"; then
    result fail F-BOT "$CHARS" "$HTTP"; exit 1
  fi
fi
if [ "$CHARS" -lt "$MINCHARS" ]; then
  result fail F-EMPTY "$CHARS" "$HTTP"; exit 1
fi
cat "$TXT"
printf '\n'  # extracted text may lack a trailing newline — keep result line parseable
result ok - "$CHARS" "$HTTP"
exit 0
