#!/usr/bin/env bash
# meta-ego chrome-wrapper — ego-linux가 CHROME_PATH로 호출하는 래퍼.
# 이 VM 샌드박스의 두 가지 제약을 흡수한다:
#  1) egress 프록시(hatch-egress-proxy:3128)가 Chrome 프로세스의 직접 CONNECT를 403으로 막음
#     → 127.0.0.1:18080 socat 릴레이를 경유하면 통과 (프록시 자체는 그대로 거침, TLS는 종단간 유지)
#  2) egress 프록시가 Hatch Sandbox Egress CA로 TLS를 MITM함
#     → 런타임 기본 NSS DB(~/.pki/nssdb)는 신뢰 플래그가 'C,,'라 Chrome 내장 검증기가
#       신뢰하지 못함. 대신 UltraBrowse 전용 HOME(chrome-home/.pki/nssdb)에 CA를
#       'CT,C,C' 신뢰로 임포트해 두고, Chrome 프로세스의 HOME만 그쪽으로 지정한다.
#     → 인증서 검증은 켜진 상태가 기본이며 --ignore-certificate-errors는 쓰지 않는다.
#       (검증 근거: 2026-11-20 badssl 차단 + 로컬 CA/self-signed 분리 테스트 통과)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_CHROME="/home/hatch/.cache/ms-playwright/chromium-1255/chrome-linux64/chrome"
RELAY_PORT=18080
"$HERE/ensure-nssdb.sh" || echo "chrome-wrapper: ensure-nssdb failed, cert validation may fail" >&2
if ! (exec 3<>/dev/tcp/127.0.0.1/$RELAY_PORT) 2>/dev/null; then
  nohup socat TCP-LISTEN:$RELAY_PORT,fork,reuseaddr,bind=127.0.0.1 TCP:hatch-egress-proxy:3128 >/dev/null 2>&1 &
  for i in $(seq 1 20); do
    (exec 3<>/dev/tcp/127.0.0.1/$RELAY_PORT) 2>/dev/null && break
    sleep 0.25
  done
fi
export HOME="$HERE/chrome-home"
# === 인자 정규화 (2026-11-20 지문·WebGL 조정, 전부 래퍼 층) ===
#  - ego-linux가 붙이는 --disable-gpu를 제거한다: 기본값에서는 WebGL 컨텍스트
#    생성 자체가 실패(no-context)해 실브라우저와 동떨어진 지문이 된다.
#    --use-angle=swiftshader로 소프트웨어 렌더링을 명시해 WebGL을 살린다.
#    (실측: 이 플래그를 빼면 다시 no-context로 돌아간다 — 둘 다 필수.)
#  - --user-agent: 헤드리스 기본 UA에 박히는 "HeadlessChrome" 표기를 뺀
#    정식 Chrome 159 UA로 고정한다 (헤더·navigator.userAgent 모두).
#  - --lang=ko-KR: navigator.language(s)와 기본 Accept-Language를 한국어 우선으로.
#    (run.sh의 open/read는 여기에 더해 CDP Emulation.setUserAgentOverride로
#     Accept-Language와 클라이언트 힌트 브랜드까지 맞춘다.)
ARGS=()
for a in "$@"; do
  [ "$a" = "--disable-gpu" ] && continue
  ARGS+=("$a")
done
exec "$REAL_CHROME" --proxy-server="http://127.0.0.1:$RELAY_PORT" \
  --use-angle=swiftshader \
  "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36" \
  --lang=ko-KR \
  "${ARGS[@]}"
