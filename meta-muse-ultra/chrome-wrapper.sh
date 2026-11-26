#!/usr/bin/env bash
# chrome-wrapper — the executable the CDP daemon spawns as "Chrome"
# (CHROME_PATH). It absorbs per-machine differences so the daemon does not
# have to know them. Nothing about a specific machine's layout is hardcoded
# here anymore; everything comes from ub-config.sh / config.env:
#  1) Chromium binary: resolved from configuration (explicit path >
#     Playwright cache, newest revision > PATH). A specific install
#     revision is never assumed.
#  2) Egress proxy: when a proxy is configured (config.env or the standard
#     HTTPS_PROXY env), Chrome is pointed at it — via a local socat relay
#     when the environment needs one (some sandboxes 403 Chrome's own
#     CONNECT while letting other processes through; the relay hides the
#     process identity, traffic still goes through the same proxy), or
#     directly otherwise. No proxy configured = direct connection.
#  3) Proxy CA: when a proxy CA certificate is configured, the dedicated
#     NSS DB (chrome-home/.pki/nssdb) is prepared with that CA at full
#     trust (ensure-nssdb.sh) and Chrome's HOME is pointed at chrome-home
#     so its built-in verifier reads that DB. Certificate verification
#     stays ON — --ignore-certificate-errors is never used. No CA
#     configured = NSS step skipped, HOME untouched.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/ub-config.sh"

REAL_CHROME=$(ub_resolve_chrome) || exit 1

# NSS DB only matters when a proxy MITMs TLS with its own CA.
if [ -n "$UB_PROXY_CA" ] && [ -f "$UB_PROXY_CA" ]; then
  "$HERE/ensure-nssdb.sh" || echo "chrome-wrapper: ensure-nssdb failed, cert validation may fail" >&2
  export HOME="$MUSE_ULTRA_CHROME_HOME"
fi

PROXY_ARGS=()
if [ -n "$UB_PROXY" ]; then
  if ub_relay_wanted; then
    RELAY_PORT="$UB_RELAY_PORT"
    if ! (exec 3<>/dev/tcp/127.0.0.1/$RELAY_PORT) 2>/dev/null; then
      nohup socat TCP-LISTEN:$RELAY_PORT,fork,reuseaddr,bind=127.0.0.1 TCP:$UB_PROXY_HOST:$UB_PROXY_PORT >/dev/null 2>&1 &
      for i in $(seq 1 20); do
        (exec 3<>/dev/tcp/127.0.0.1/$RELAY_PORT) 2>/dev/null && break
        sleep 0.25
      done
    fi
    PROXY_ARGS=(--proxy-server="http://127.0.0.1:$RELAY_PORT")
  elif [ -n "$UB_PROXY_FOR_CHROME" ]; then
    PROXY_ARGS=(--proxy-server="$UB_PROXY_FOR_CHROME")
  fi
fi

# === 인자 정규화 (2026-11-20 지문·WebGL 조정, 전부 래퍼 층) ===
#  - 호출자가 붙이는 --disable-gpu를 제거한다: 기본값에서는 WebGL 컨텍스트
#    생성 자체가 실패(no-context)해 실브라우저와 동떨어진 지문이 된다.
#    --use-angle=swiftshader로 소프트웨어 렌더링을 명시해 WebGL을 살린다.
#    (실측: 이 플래그를 빼면 다시 no-context로 돌아간다 — 둘 다 필수.)
#  - --user-agent: 헤드리스 기본 UA에 박히는 "HeadlessChrome" 표기를 뺀
#    정식 Chrome UA. 버전은 해석된 바이너리에서 도출한다 (UB_UA로 재정의 가능).
#  - --lang=ko-KR: navigator.language(s)와 기본 Accept-Language를 한국어 우선으로.
#    (run.sh의 open/read는 여기에 더해 CDP Emulation.setUserAgentOverride로
#     Accept-Language와 클라이언트 힌트 브랜드까지 맞춘다.)
FULL=$(ub_chrome_full_version "$REAL_CHROME" || true)
MAJOR="${FULL%%.*}"
UA="${UB_UA:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${MAJOR:-159}.0.0.0 Safari/537.36}"
ARGS=()
for a in "$@"; do
  [ "$a" = "--disable-gpu" ] && continue
  ARGS+=("$a")
done
exec "$REAL_CHROME" "${PROXY_ARGS[@]}" \
  --use-angle=swiftshader \
  "--user-agent=$UA" \
  --lang=ko-KR \
  "${ARGS[@]}"
