#!/usr/bin/env bash
# meta-muse-ultra: muse-ultra-browser 래퍼 (Muse 테스트베드 전용)
# 사용법:
#   run.sh warm         — 데몬+Chromium 예열 (상주 확인 포함)
#   run.sh open <url>   — 이동 + 스냅샷 (구조 유지, trim 후처리)
#   run.sh read <url>   — 이동 + 본문 텍스트 추출 (full_page 스냅샷 → text 후처리)
#   run.sh '<JS 코드>'  — 임의 JS 실행
#   run.sh -f script.js — JS 파일 실행
#   echo '<JS>' | run.sh
# 모든 muse-ultra-browser 호출에는 하드 타임아웃 60초가 걸린다 (과거 hang 재발 방지).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 선택 설정 로드 (API 슬롯 등). 파일이 없어도 동작함.
[ -f "$HERE/config.env" ] && set -a && . "$HERE/config.env" && set +a
export PATH="$HOME/.local/bin:$HOME/workspace/muse-ultra-browser-build/shim:$PATH"
# Chromium 지정: CHROME_PATH가 이미 있으면 존중, 없으면 playwright 캐시→shim 순으로 탐색
if [ -z "${CHROME_PATH:-}" ]; then
  PW=$(ls ~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | head -1 || true)
  if [ -n "$PW" ]; then export CHROME_PATH="$PW";
  else export CHROME_PATH=/opt/meta-chromium/chrome; fi  # 주의: meta-chromium은 단독 실행 불가(README 참조)
fi
export MUSE_ULTRA_HEADLESS="${MUSE_ULTRA_HEADLESS:-1}"
MUSE_ULTRA_TIMEOUT=60

# 콜드 스타트 레이스 방지 (2026-11-20): 데몬이 꺼진 상태에서 첫 호출이
# ENOENT daemon.sock 으로 실패하던 문제. 소켓이 없으면 status로 데몬을
# 먼저 깨우고 소켓 준비를 기다린다. 그래도 실패하면 호출부에서 1회 재시도.
DAEMON_SOCK="$HOME/.local/share/muse-ultra-browser/daemon.sock"
ensure_daemon() {
  [ -S "$DAEMON_SOCK" ] && return 0
  timeout 15 muse-ultra-browser status >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    [ -S "$DAEMON_SOCK" ] && return 0
    sleep 0.25
  done
  return 0
}
ensure_daemon

if [ "${1:-}" = "warm" ]; then
  # 데몬 웜 유지 (2026-11-21): 데몬+Chromium을 미리 띄우고 빈 페이지로 예열한다.
  # 데몬(muse-ultra-browser.mjs serve)은 유휴 종료가 없다 — 종료 조건은 muse-ultra-browser stop,
  # Chromium 크래시(데몬 동반 종료 후 다음 호출에서 재생성), VM 재부팅뿐이다.
  # 그래서 웜 유지는 "한 번 띄워 두기"로 충분하고 별도 keepalive가 필요 없다.
  TMPJS=$(mktemp /tmp/meta-muse-ultra-XXXXXX.js)
  RAW=$(mktemp /tmp/meta-muse-ultra-raw-XXXXXX.txt)
  cat > "$TMPJS" <<'EOF'
const t = await taskSpace("warm" + Date.now());
const p = await t.newPage();
await p.goto("about:blank");
console.log("warm ok");
await t.finish({keep: []});
EOF
  RC=0
  timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$TMPJS" > "$RAW" 2>&1 || RC=$?
  if [ $RC -ne 0 ] && grep -q 'daemon\.sock' "$RAW" 2>/dev/null; then
    # 콜드 레이스: 데몬 소켓이 늦게 뜨면 1회만 재시도 (open/read와 동일 패턴)
    ensure_daemon
    RC=0
    timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$TMPJS" > "$RAW" 2>&1 || RC=$?
  fi
  rm -f "$TMPJS"
  cat "$RAW"; rm -f "$RAW"
  if [ $RC -ne 0 ]; then echo "run.sh warm: muse-ultra-browser failed (rc=$RC)" >&2; exit $RC; fi
  muse-ultra-browser status
  exit 0
fi

if [ "${1:-}" = "open" ] || [ "${1:-}" = "read" ]; then
  MODE=$1; URL=${2:?usage: run.sh open|read <url>}
  if [ "$MODE" = "read" ]; then SNAPCALL='await p.snapshot({scope: "full_page"})'; TRIM=text
  else SNAPCALL='await p.snapshot()'; TRIM=trim; fi
  URLJSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$URL")
  TMPJS=$(mktemp /tmp/meta-muse-ultra-XXXXXX.js)
  RAW=$(mktemp /tmp/meta-muse-ultra-raw-XXXXXX.txt)
  cat > "$TMPJS" <<EOF
let t;
try {
  t = await taskSpace("ub" + Date.now());
  const p = await t.newPage();
  try { await p.cdp('Emulation.setUserAgentOverride', {
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36',
    acceptLanguage: 'ko-KR,ko,en-US,en',
    platform: 'Linux',
    userAgentMetadata: {
      brands: [{brand: 'Google Chrome', version: '159'}, {brand: 'Chromium', version: '159'}, {brand: 'Not A(Brand', version: '8'}],
      fullVersionList: [{brand: 'Google Chrome', version: '159.0.8154.6'}, {brand: 'Chromium', version: '159.0.8154.6'}, {brand: 'Not A(Brand', version: '8.0.0.0'}],
      fullVersion: '159.0.8154.6',
      platform: 'Linux', platformVersion: '', architecture: 'x86', model: '', mobile: false, bitness: '64', wow64: false
    }
  }); } catch (e) { /* 실패해도 래퍼 플래그 UA와 프로필 언어 pref가 기본값을 보장 */ }
  try { await p.goto($URLJSON); } catch (e) { /* navigation committed — 스냅샷은 그대로 시도 */ }
  console.log($SNAPCALL);
} finally {
  if (t) { try { await t.finish({keep: []}); } catch (e) {} }
}
EOF
  RC=0
  timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$TMPJS" > "$RAW" || RC=$?
  if [ $RC -ne 0 ] && grep -q 'daemon\.sock' "$RAW" 2>/dev/null; then
    # 소켓 레이스 잔여 케이스: 데몬을 다시 깨우고 1회만 재시도
    ensure_daemon
    RC=0
    timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$TMPJS" > "$RAW" || RC=$?
  fi
  rm -f "$TMPJS"
  if [ $RC -ne 0 ]; then
    echo "run.sh $MODE: muse-ultra-browser failed (rc=$RC, timeout=${MUSE_ULTRA_TIMEOUT}s)" >&2
    cat "$RAW" >&2; rm -f "$RAW"; exit $RC
  fi
  python3 "$HERE/snaptrim.py" $TRIM < "$RAW"
  rm -f "$RAW"
  exit 0
fi

if [ "${1:-}" = "-f" ]; then
  # 원샷 실행 경로 (2026-11-21): 콜드 스타트 소켓 레이스 때만 1회 재시도한다.
  RAW=$(mktemp /tmp/meta-muse-ultra-raw-XXXXXX.txt)
  RC=0
  timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$2" > "$RAW" 2>&1 || RC=$?
  if [ $RC -ne 0 ] && grep -q 'daemon\.sock' "$RAW" 2>/dev/null; then
    ensure_daemon
    RC=0
    timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$2" > "$RAW" 2>&1 || RC=$?
  fi
  cat "$RAW"; rm -f "$RAW"
  exit $RC
fi
if [ -n "${1:-}" ]; then
  # 주의: printf 파이프로 넘기면 muse-ultra-browser가 종료되지 않는 현상이 있어 파일 리다이렉트 사용
  TMPJS=$(mktemp /tmp/meta-muse-ultra-XXXXXX.js)
  printf '%s\n' "$1" > "$TMPJS"
  RC=0
  timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser < "$TMPJS" || RC=$?
  rm -f "$TMPJS"
  exit $RC
fi
exec timeout $MUSE_ULTRA_TIMEOUT muse-ultra-browser
