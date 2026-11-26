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
trap 'rm -f "$HTML" "$TXT"' EXIT

CURL_PROXY=()
[ -n "$PROXY" ] && CURL_PROXY=(-x "$PROXY")
HTTP=$(curl -sS "${CURL_PROXY[@]}" -A "$UA" -L --max-time "$MAXTIME" \
  -o "$HTML" -w '%{http_code}' "$URL" 2>/tmp/meta-muse-ultra-l0-curl.err)
RC=$?
if [ $RC -ne 0 ]; then
  if [ $RC -eq 28 ]; then result fail F-TIMEOUT 0 000; else result fail F-NET 0 000; fi
  cat /tmp/meta-muse-ultra-l0-curl.err >&2
  exit 1
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
# Block-page markers served with HTTP 200
if grep -qiE 'attention required|sorry, you have been blocked|access denied|접속이 일시적으로 제한|접속이 제한되었습니다|비정상적인 접근이 감지' "$TXT"; then
  result fail F-IP "$CHARS" "$HTTP"; exit 1
fi
if grep -qiE 'verify you are human|are you a robot|unusual traffic from your computer' "$TXT"; then
  result fail F-BOT "$CHARS" "$HTTP"; exit 1
fi
if [ "$CHARS" -lt "$MINCHARS" ]; then
  result fail F-EMPTY "$CHARS" "$HTTP"; exit 1
fi
cat "$TXT"
printf '\n'  # extracted text may lack a trailing newline — keep result line parseable
result ok - "$CHARS" "$HTTP"
exit 0
